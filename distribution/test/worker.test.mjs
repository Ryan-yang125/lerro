import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

import worker, {
  APPCAST_PATH,
  LATEST_DOWNLOAD_PATH,
  SQL,
  escapeXML,
  parseByteRange,
} from "../src/worker.mjs";
import {
  preparePublicationBatch,
  publishRelease,
  renderPublicationSQL,
} from "../src/publication-batch.mjs";

const publishedAt = "2026-08-02T08:00:00.000Z";
const release = {
  id: "8e83b7aa-fffa-48dc-bff4-fc3e9c39ce2b",
  version: "1.0.2",
  build_number: 3,
  minimum_macos: "26.0.0",
  published_at: publishedAt,
  release_notes_url: "https://lerroapp.com/releases/1.0.2",
};
const artifact = {
  r2_key: "releases/1.0.2/3/Lerro-macOS-arm64.zip",
  filename: "Lerro-macOS-arm64.zip",
  bytes: 10,
  sha256: "f".repeat(64),
  sparkle_ed_signature: "c2lnbmF0dXJl",
  content_type: "application/zip",
};

class FakeStatement {
  constructor(database, sql) {
    this.database = database;
    this.sql = sql;
    this.args = [];
  }

  bind(...args) {
    this.args = args;
    return this;
  }

  async first() {
    return this.database.first(this.sql, this.args);
  }

  async all() {
    return { results: this.database.all(this.sql, this.args) };
  }
}

class FakeDatabase {
  constructor({
    appcastItems = [
      release,
      {
        ...release,
        version: "1.0.1",
        build_number: 2,
        release_notes_url: "https://lerroapp.com/releases/1.0.1?source=appcast&channel=stable",
      },
    ],
    latest = artifact,
    immutable = artifact,
  } = {}) {
    this.appcastItems = appcastItems;
    this.latest = latest;
    this.immutable = immutable;
    this.calls = [];
    this.batches = [];
  }

  prepare(sql) {
    this.calls.push(sql);
    return new FakeStatement(this, sql);
  }

  all(sql, args) {
    assert.equal(sql, SQL.appcastItems);
    assert.deepEqual(args, ["stable"]);
    return this.appcastItems.map((item) => ({ ...artifact, ...item }));
  }

  first(sql, args) {
    if (sql === SQL.latestArtifact) {
      assert.deepEqual(args, ["stable"]);
      return this.latest && { ...release, ...this.latest };
    }
    if (sql === SQL.immutableArtifact) {
      assert.deepEqual(args, ["1.0.2", 3, artifact.filename]);
      return this.immutable && { ...release, ...this.immutable };
    }
    throw new Error("Unexpected query");
  }

  async batch(statements) {
    this.batches.push(statements);
    return statements.map(() => ({ success: true }));
  }
}

class FakeBucket {
  constructor(bytes = new TextEncoder().encode("0123456789")) {
    this.bytes = bytes;
    this.getCalls = [];
    this.headCalls = [];
    this.uploaded = new Date(publishedAt);
  }

  async head(key) {
    this.headCalls.push(key);
    if (key !== artifact.r2_key) {
      return null;
    }
    return {
      size: this.bytes.byteLength,
      httpEtag: '"r2-object-etag"',
      uploaded: this.uploaded,
    };
  }

  async get(key, options = undefined) {
    this.getCalls.push({ key, options });
    if (key !== artifact.r2_key) {
      return null;
    }
    const range = options?.range;
    const payload = range
      ? this.bytes.slice(range.offset, range.offset + range.length)
      : this.bytes;
    return { body: new Blob([payload]).stream() };
  }
}

function environment(options = {}) {
  return {
    DB: new FakeDatabase(options),
    RELEASES: new FakeBucket(options.bytes),
    PUBLIC_BASE_URL: "https://updates.lerroapp.com",
  };
}

function request(path, init = undefined) {
  return new Request(`https://updates.lerroapp.com${path}`, init);
}

test("appcast renders only valid database-published metadata, escapes XML, and supports ETag validation", async () => {
  const env = environment();
  const response = await worker.fetch(request(APPCAST_PATH), env);

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Content-Type"), "application/xml; charset=utf-8");
  assert.match(response.headers.get("ETag"), /^"[0-9a-f]{64}"$/);
  const xml = await response.text();
  assert.match(xml, /sparkle:edSignature="c2lnbmF0dXJl"/);
  assert.match(xml, /sparkle:hardwareRequirements="arm64"/);
  assert.match(xml, /https:\/\/updates\.lerroapp\.com\/releases\/1\.0\.2\/3\/Lerro-macOS-arm64\.zip/);
  assert.match(xml, /source=appcast&amp;channel=stable/);
  assert.equal(env.RELEASES.headCalls.length, 0);

  const cached = await worker.fetch(
    request(APPCAST_PATH, { headers: { "If-None-Match": response.headers.get("ETag") } }),
    env,
  );
  assert.equal(cached.status, 304);
  assert.equal(await cached.text(), "");
});

test("appcast suppresses malformed metadata and XML escaping remains deterministic", async () => {
  const env = environment({
    appcastItems: [
      release,
      { ...release, version: "1.0.1", build_number: 2, sparkle_ed_signature: "invalid signature" },
    ],
  });
  const response = await worker.fetch(request(APPCAST_PATH), env);

  assert.equal(response.status, 200);
  const xml = await response.text();
  assert.match(xml, /Version 1\.0\.2/);
  assert.doesNotMatch(xml, /Version 1\.0\.1/);
  assert.equal(escapeXML("<tag a='b'&>"), "&lt;tag a=&apos;b&apos;&amp;&gt;");
});

test("latest download streams the D1-selected R2 object and returns a range response", async () => {
  const env = environment();
  const response = await worker.fetch(
    request(LATEST_DOWNLOAD_PATH, { headers: { Range: "bytes=2-5" } }),
    env,
  );

  assert.equal(response.status, 206);
  assert.equal(response.headers.get("Content-Range"), "bytes 2-5/10");
  assert.equal(response.headers.get("Content-Length"), "4");
  assert.equal(response.headers.get("Cache-Control"), "public, max-age=60, must-revalidate");
  assert.equal(await response.text(), "2345");
  assert.deepEqual(env.RELEASES.getCalls, [
    { key: artifact.r2_key, options: { range: { offset: 2, length: 4 } } },
  ]);
});

test("immutable downloads support HEAD, ETag validation, and cache immutable artifacts", async () => {
  const env = environment();
  const path = "/releases/1.0.2/3/Lerro-macOS-arm64.zip";
  const head = await worker.fetch(request(path, { method: "HEAD" }), env);

  assert.equal(head.status, 200);
  assert.equal(head.headers.get("Content-Length"), "10");
  assert.equal(head.headers.get("Cache-Control"), "public, max-age=31536000, immutable");
  assert.equal(await head.text(), "");
  assert.equal(env.RELEASES.getCalls.length, 0);

  const cached = await worker.fetch(
    request(path, { headers: { "If-None-Match": '"r2-object-etag"' } }),
    env,
  );
  assert.equal(cached.status, 304);
  assert.equal(env.RELEASES.getCalls.length, 0);
});

test("unsupported methods, malformed paths, unavailable artifacts, and invalid ranges are fail-closed", async () => {
  const env = environment();
  const post = await worker.fetch(request(LATEST_DOWNLOAD_PATH, { method: "POST" }), env);
  assert.equal(post.status, 405);
  assert.equal(post.headers.get("Allow"), "GET, HEAD");

  const unknown = await worker.fetch(request("/releases/1.0.2/3/%2e%2e%2fprivate.zip"), env);
  assert.equal(unknown.status, 404);

  const invalidRange = await worker.fetch(
    request(LATEST_DOWNLOAD_PATH, { headers: { Range: "bytes=999-1000" } }),
    env,
  );
  assert.equal(invalidRange.status, 416);
  assert.equal(invalidRange.headers.get("Content-Range"), "bytes */10");

  const unavailable = await worker.fetch(
    request(LATEST_DOWNLOAD_PATH),
    environment({ latest: { ...artifact, bytes: 11 } }),
  );
  assert.equal(unavailable.status, 503);

  const incorrectKey = await worker.fetch(
    request(LATEST_DOWNLOAD_PATH),
    environment({ latest: { ...artifact, r2_key: "releases/1.0.2/3/other.zip" } }),
  );
  assert.equal(incorrectKey.status, 503);
});

test("If-Range preserves a complete transfer when the entity tag is stale or weak", async () => {
  const env = environment();
  const response = await worker.fetch(
    request(LATEST_DOWNLOAD_PATH, {
      headers: { Range: "bytes=0-3", "If-Range": '"older-object-etag"' },
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal(await response.text(), "0123456789");
  assert.deepEqual(env.RELEASES.getCalls, [{ key: artifact.r2_key, options: undefined }]);

  const weakEnvironment = environment();
  const weakResponse = await worker.fetch(
    request(LATEST_DOWNLOAD_PATH, {
      headers: { Range: "bytes=0-3", "If-Range": 'W/"r2-object-etag"' },
    }),
    weakEnvironment,
  );
  assert.equal(weakResponse.status, 200);
  assert.equal(await weakResponse.text(), "0123456789");
});

test("range parser handles open, suffix, and malformed ranges", () => {
  assert.deepEqual(parseByteRange("bytes=3-", 10), { kind: "range", start: 3, end: 9 });
  assert.deepEqual(parseByteRange("bytes=-4", 10), { kind: "range", start: 6, end: 9 });
  assert.deepEqual(parseByteRange("bytes=0-99", 10), { kind: "range", start: 0, end: 9 });
  assert.deepEqual(parseByteRange("bytes=0-1,2-3", 10), { kind: "invalid" });
});

test("publication helper creates one atomic D1 batch with immutable R2 metadata", async () => {
  const database = new FakeDatabase();
  const publication = {
    release: {
      id: release.id,
      channel: "stable",
      version: "1.0.2",
      buildNumber: 3,
      platform: "macos",
      architecture: "arm64",
      minimumMacOS: "26.0.0",
      publishedAt,
      releaseNotesURL: "https://lerroapp.com/releases/1.0.2",
    },
    artifact: {
      id: "0ae2a66f-d156-4859-8b83-12910f746276",
      r2Key: artifact.r2_key,
      filename: artifact.filename,
      bytes: 10,
      sha256: artifact.sha256,
      edSignature: artifact.sparkle_ed_signature,
      contentType: "application/zip",
    },
    generation: 1,
    expectedGeneration: 0,
  };

  const statements = preparePublicationBatch(database, publication);
  assert.equal(statements.length, 3);
  await publishRelease(database, publication);
  assert.equal(database.batches.length, 1);
  assert.equal(database.batches[0].length, 3);

  assert.throws(
    () => preparePublicationBatch(database, {
      ...publication,
      artifact: { ...publication.artifact, r2Key: "releases/other.zip" },
    }),
    /immutable release key/,
  );
});

test("publication SQL CLI shares validation and safely renders D1 statements", () => {
  const publication = {
    release: {
      id: release.id,
      channel: "stable",
      version: "1.0.2",
      buildNumber: 3,
      platform: "macos",
      architecture: "arm64",
      minimum_macos: "26.4.1",
      publishedAt,
      releaseNotesURL: "https://lerroapp.com/releases/O'Reilly",
    },
    artifact: {
      id: "0ae2a66f-d156-4859-8b83-12910f746276",
      r2Key: artifact.r2_key,
      filename: artifact.filename,
      bytes: 10,
      sha256: artifact.sha256,
      edSignature: artifact.sparkle_ed_signature,
      contentType: "application/zip",
    },
    generation: 7,
    expectedGeneration: 6,
  };

  const sql = renderPublicationSQL(publication);
  assert.match(sql, /'26\.4\.1'/);
  assert.match(sql, /'https:\/\/lerroapp\.com\/releases\/O''Reilly'/);
  assert.doesNotMatch(sql, /\?/);
  assert.equal((sql.match(/;/g) ?? []).length, 3);
  assert.match(sql, /\b7\b/);
  assert.match(sql, /\b6\b/);

  const database = new FakeDatabase();
  const [releaseStatement] = preparePublicationBatch(database, publication);
  assert.equal(releaseStatement.args[6], "26.4.1");

  const cliPath = fileURLToPath(new URL("../bin/render-publication-sql.mjs", import.meta.url));
  const result = spawnSync(process.execPath, [cliPath], {
    encoding: "utf8",
    input: JSON.stringify(publication),
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, sql);
  assert.equal(result.stderr, "");

  assert.throws(
    () => renderPublicationSQL({
      ...publication,
      release: { ...publication.release, minimumMacOS: "26.4.2" },
    }),
    /must agree/,
  );

  assert.throws(
    () => preparePublicationBatch(database, {
      ...publication,
      expectedGeneration: 7,
    }),
    /immediately follow/,
  );
});
