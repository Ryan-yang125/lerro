const APPCAST_PATH = "/appcast/stable.xml";
const LATEST_DOWNLOAD_PATH = "/download/macos/latest";
const RELEASE_PATH_PATTERN = /^\/releases\/([0-9][0-9A-Za-z.-]{0,63})\/([1-9][0-9]*)\/([A-Za-z0-9][A-Za-z0-9._-]{0,127}\.zip)$/;
const FILE_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.zip$/;
const VERSION_PATTERN = /^[0-9][0-9A-Za-z.-]{0,63}$/;
const MINIMUM_MACOS_PATTERN = /^\d+(?:\.\d+){0,2}$/;
const ED_SIGNATURE_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;
const DEFAULT_PUBLIC_BASE_URL = "https://updates.lerroapp.com";

const SQL = {
  appcastItems: `
    SELECT
      release.version,
      release.build_number,
      release.minimum_macos,
      release.published_at,
      release.release_notes_url,
      artifact.filename,
      artifact.bytes,
      artifact.sparkle_ed_signature
    FROM channel_heads AS head
    JOIN releases AS release ON release.id = head.release_id
    JOIN artifacts AS artifact ON artifact.release_id = release.id
    WHERE head.channel = ?
      AND head.platform = 'macos'
      AND head.architecture = 'arm64'
      AND release.status = 'published'
      AND artifact.kind = 'macos-zip'
      AND artifact.sparkle_ed_signature <> ''
    LIMIT 1
  `,
  latestArtifact: `
    SELECT
      release.id AS release_id,
      release.version,
      release.build_number,
      artifact.r2_key,
      artifact.filename,
      artifact.bytes,
      artifact.sha256,
      artifact.content_type
    FROM channel_heads AS head
    JOIN releases AS release ON release.id = head.release_id
    JOIN artifacts AS artifact ON artifact.release_id = release.id
    WHERE head.channel = ?
      AND head.platform = 'macos'
      AND head.architecture = 'arm64'
      AND release.status = 'published'
      AND artifact.kind = 'macos-zip'
    LIMIT 1
  `,
  immutableArtifact: `
    SELECT
      release.id AS release_id,
      release.version,
      release.build_number,
      artifact.r2_key,
      artifact.filename,
      artifact.bytes,
      artifact.sha256,
      artifact.content_type
    FROM releases AS release
    JOIN artifacts AS artifact ON artifact.release_id = release.id
    WHERE release.version = ?
      AND release.build_number = ?
      AND release.platform = 'macos'
      AND release.architecture = 'arm64'
      AND release.status = 'published'
      AND artifact.kind = 'macos-zip'
      AND artifact.filename = ?
    LIMIT 1
  `,
};

function noStoreHeaders(extra = undefined) {
  return new Headers({
    "Cache-Control": "no-store",
    ...(extra ?? {}),
  });
}

function unavailable() {
  return new Response("Service temporarily unavailable. Please try again.", {
    status: 503,
    headers: noStoreHeaders(),
  });
}

function missing() {
  return new Response("Release unavailable.", {
    status: 404,
    headers: noStoreHeaders(),
  });
}

function methodNotAllowed() {
  return new Response("Method unavailable.", {
    status: 405,
    headers: noStoreHeaders({ Allow: "GET, HEAD" }),
  });
}

function acceptsReadMethod(request) {
  return request.method === "GET" || request.method === "HEAD";
}

function safeArtifact(record) {
  return (
    record &&
    typeof record.version === "string" &&
    VERSION_PATTERN.test(record.version) &&
    Number.isSafeInteger(Number(record.build_number)) &&
    Number(record.build_number) > 0 &&
    typeof record.filename === "string" &&
    FILE_NAME_PATTERN.test(record.filename) &&
    record.r2_key === `releases/${record.version}/${record.build_number}/${record.filename}` &&
    Number.isSafeInteger(Number(record.bytes)) &&
    Number(record.bytes) > 0 &&
    typeof record.content_type === "string" &&
    record.content_type === "application/zip"
  );
}

function safeAppcastItem(item) {
  if (
    !item ||
    typeof item.version !== "string" ||
    !VERSION_PATTERN.test(item.version) ||
    !Number.isSafeInteger(Number(item.build_number)) ||
    Number(item.build_number) <= 0 ||
    typeof item.minimum_macos !== "string" ||
    !MINIMUM_MACOS_PATTERN.test(item.minimum_macos) ||
    typeof item.filename !== "string" ||
    !FILE_NAME_PATTERN.test(item.filename) ||
    !Number.isSafeInteger(Number(item.bytes)) ||
    Number(item.bytes) <= 0 ||
    typeof item.sparkle_ed_signature !== "string" ||
    !ED_SIGNATURE_PATTERN.test(item.sparkle_ed_signature) ||
    !Number.isFinite(Date.parse(item.published_at))
  ) {
    return false;
  }

  if (item.release_notes_url == null) {
    return true;
  }

  try {
    return new URL(item.release_notes_url).protocol === "https:";
  } catch {
    return false;
  }
}

function publicBaseURL(env) {
  const configured = env.PUBLIC_BASE_URL || DEFAULT_PUBLIC_BASE_URL;
  const parsed = new URL(configured);

  if (parsed.protocol !== "https:" || parsed.pathname !== "/" || parsed.search || parsed.hash) {
    throw new TypeError("PUBLIC_BASE_URL must be an HTTPS origin");
  }

  return parsed.origin;
}

function escapeXML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function releaseURL(baseURL, item) {
  return `${baseURL}/releases/${encodeURIComponent(item.version)}/${item.build_number}/${encodeURIComponent(item.filename)}`;
}

function renderAppcast(baseURL, items) {
  const renderedItems = items
    .map((item) => {
      const published = new Date(item.published_at).toUTCString();
      const notes = item.release_notes_url
        ? `\n      <sparkle:releaseNotesLink>${escapeXML(item.release_notes_url)}</sparkle:releaseNotesLink>`
        : "";

      return `    <item>
      <title>Version ${escapeXML(item.version)}</title>
      <pubDate>${escapeXML(published)}</pubDate>${notes}
      <enclosure
        url="${escapeXML(releaseURL(baseURL, item))}"
        sparkle:version="${escapeXML(item.build_number)}"
        sparkle:shortVersionString="${escapeXML(item.version)}"
        sparkle:minimumSystemVersion="${escapeXML(item.minimum_macos)}"
        sparkle:hardwareRequirements="arm64"
        sparkle:edSignature="${escapeXML(item.sparkle_ed_signature)}"
        length="${escapeXML(item.bytes)}"
        type="application/octet-stream"
      />
    </item>`;
    })
    .join("\n");

  return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Lerro</title>
    <link>${escapeXML(baseURL)}</link>
    <description>Lerro macOS updates</description>
${renderedItems}
  </channel>
</rss>\n`;
}

async function opaqueETag(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `"${hex}"`;
}

function normalizeETag(value) {
  return value.trim().replace(/^W\//, "");
}

function etagMatches(headerValue, entityTag) {
  if (!headerValue) {
    return false;
  }

  return headerValue.split(",").some((candidate) => {
    const trimmed = candidate.trim();
    return trimmed === "*" || normalizeETag(trimmed) === normalizeETag(entityTag);
  });
}

function parseDecimal(value) {
  if (!/^\d+$/.test(value)) {
    return null;
  }

  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function parseByteRange(value, size) {
  if (!value) {
    return { kind: "full" };
  }

  const match = /^bytes=(\d*)-(\d*)$/.exec(value.trim());
  if (!match || (match[1] === "" && match[2] === "")) {
    return { kind: "invalid" };
  }

  const [, startValue, endValue] = match;
  if (startValue === "") {
    const suffix = parseDecimal(endValue);
    if (suffix == null || suffix === 0 || size === 0) {
      return { kind: "invalid" };
    }

    const length = Math.min(suffix, size);
    return { kind: "range", start: size - length, end: size - 1 };
  }

  const start = parseDecimal(startValue);
  const requestedEnd = endValue === "" ? null : parseDecimal(endValue);
  if (start == null || start >= size || (endValue !== "" && requestedEnd == null) || (requestedEnd != null && requestedEnd < start)) {
    return { kind: "invalid" };
  }

  return {
    kind: "range",
    start,
    end: requestedEnd == null ? size - 1 : Math.min(requestedEnd, size - 1),
  };
}

function allowsRange(request, entityTag, uploadedAt) {
  const ifRange = request.headers.get("If-Range");
  if (!ifRange) {
    return true;
  }

  if (ifRange.startsWith("W/")) {
    return false;
  }

  if (ifRange.startsWith('"')) {
    return ifRange === entityTag;
  }

  const suppliedDate = Date.parse(ifRange);
  return Number.isFinite(suppliedDate) && uploadedAt.getTime() <= suppliedDate;
}

function artifactHeaders({ artifact, entityTag, uploadedAt, size, range, cacheControl }) {
  const responseSize = range.kind === "range" ? range.end - range.start + 1 : size;
  const headers = new Headers({
    "Accept-Ranges": "bytes",
    "Cache-Control": cacheControl,
    "Content-Disposition": `attachment; filename="${artifact.filename}"; filename*=UTF-8''${encodeURIComponent(artifact.filename)}`,
    "Content-Length": String(responseSize),
    "Content-Type": artifact.content_type,
    ETag: entityTag,
    "Last-Modified": uploadedAt.toUTCString(),
    "X-Content-Type-Options": "nosniff",
  });

  if (range.kind === "range") {
    headers.set("Content-Range", `bytes ${range.start}-${range.end}/${size}`);
  }

  return headers;
}

async function serveArtifact(request, env, artifact, cacheControl) {
  if (!safeArtifact(artifact)) {
    return unavailable();
  }

  const metadata = await env.RELEASES.head(artifact.r2_key);
  if (!metadata) {
    return unavailable();
  }

  const size = metadata.size;
  if (!Number.isSafeInteger(size) || size <= 0 || size !== Number(artifact.bytes)) {
    return unavailable();
  }

  const entityTag = metadata.httpEtag;
  if (!entityTag) {
    return unavailable();
  }

  if (etagMatches(request.headers.get("If-None-Match"), entityTag)) {
    return new Response(null, {
      status: 304,
      headers: artifactHeaders({
        artifact,
        entityTag,
        uploadedAt: metadata.uploaded,
        size,
        range: { kind: "full" },
        cacheControl,
      }),
    });
  }

  let range = parseByteRange(request.headers.get("Range"), size);
  if (range.kind === "range" && !allowsRange(request, entityTag, metadata.uploaded)) {
    range = { kind: "full" };
  }

  if (range.kind === "invalid") {
    return new Response(null, {
      status: 416,
      headers: new Headers({
        "Accept-Ranges": "bytes",
        "Cache-Control": cacheControl,
        "Content-Range": `bytes */${size}`,
        ETag: entityTag,
        "X-Content-Type-Options": "nosniff",
      }),
    });
  }

  const headers = artifactHeaders({ artifact, entityTag, uploadedAt: metadata.uploaded, size, range, cacheControl });
  const status = range.kind === "range" ? 206 : 200;
  if (request.method === "HEAD") {
    return new Response(null, { status, headers });
  }

  const object = range.kind === "range"
    ? await env.RELEASES.get(artifact.r2_key, { range: { offset: range.start, length: range.end - range.start + 1 } })
    : await env.RELEASES.get(artifact.r2_key);

  if (!object || !object.body) {
    return unavailable();
  }

  return new Response(object.body, { status, headers });
}

async function appcastResponse(request, env) {
  const result = await env.DB.prepare(SQL.appcastItems).bind("stable").all();
  const items = (result.results ?? []).filter(safeAppcastItem);
  if (items.length === 0) {
    return missing();
  }

  const xml = renderAppcast(publicBaseURL(env), items);
  const entityTag = await opaqueETag(xml);
  const headers = new Headers({
    "Cache-Control": "public, max-age=300, stale-while-revalidate=60",
    "Content-Type": "application/xml; charset=utf-8",
    ETag: entityTag,
    "X-Content-Type-Options": "nosniff",
  });

  if (etagMatches(request.headers.get("If-None-Match"), entityTag)) {
    return new Response(null, { status: 304, headers });
  }

  return new Response(request.method === "HEAD" ? null : xml, { status: 200, headers });
}

async function latestDownloadResponse(request, env) {
  const artifact = await env.DB.prepare(SQL.latestArtifact).bind("stable").first();
  if (!artifact) {
    return missing();
  }

  return serveArtifact(request, env, artifact, "public, max-age=60, must-revalidate");
}

async function immutableDownloadResponse(request, env, releaseMatch) {
  const [, version, buildNumber, filename] = releaseMatch;
  const numericBuildNumber = Number(buildNumber);
  if (!Number.isSafeInteger(numericBuildNumber)) {
    return missing();
  }

  const artifact = await env.DB.prepare(SQL.immutableArtifact).bind(version, numericBuildNumber, filename).first();
  if (!artifact) {
    return missing();
  }

  return serveArtifact(request, env, artifact, "public, max-age=31536000, immutable");
}

const worker = {
  async fetch(request, env) {
    if (!acceptsReadMethod(request)) {
      return methodNotAllowed();
    }

    try {
      const pathname = new URL(request.url).pathname;
      if (pathname === APPCAST_PATH) {
        return appcastResponse(request, env);
      }

      if (pathname === LATEST_DOWNLOAD_PATH) {
        return latestDownloadResponse(request, env);
      }

      const releaseMatch = RELEASE_PATH_PATTERN.exec(pathname);
      if (releaseMatch) {
        return immutableDownloadResponse(request, env, releaseMatch);
      }

      return missing();
    } catch {
      return unavailable();
    }
  },
};

export {
  APPCAST_PATH,
  LATEST_DOWNLOAD_PATH,
  SQL,
  escapeXML,
  parseByteRange,
  renderAppcast,
};

export default worker;
