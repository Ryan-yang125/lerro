const RELEASE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CHANNEL_PATTERN = /^[a-z0-9][a-z0-9-]{0,31}$/;
const VERSION_PATTERN = /^[0-9][0-9A-Za-z.-]{0,63}$/;
const FILE_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.zip$/;
const SHA256_PATTERN = /^[0-9a-f]{64}$/i;
const ED_SIGNATURE_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;
const SUPPORTED_ARCHITECTURES = new Set(["arm64", "x86_64", "universal"]);

const INSERT_RELEASE_IF_CHANNEL_HEAD_MATCHES = `
  INSERT INTO releases (
    id, channel, version, build_number, platform, architecture, minimum_macos,
    status, published_at, release_notes_url, created_at
  )
  SELECT ?, ?, ?, ?, ?, ?, ?, 'published', ?, ?, ?
  WHERE COALESCE((
    SELECT generation
    FROM channel_heads
    WHERE channel = ? AND platform = ? AND architecture = ?
  ), 0) = ?
`;

const INSERT_ARTIFACT = `
  INSERT INTO artifacts (
    id, release_id, kind, r2_key, filename, bytes, sha256,
    sparkle_ed_signature, content_type, created_at
  ) VALUES (?, ?, 'macos-zip', ?, ?, ?, ?, ?, ?, ?)
`;

const ADVANCE_CHANNEL_HEAD = `
  INSERT INTO channel_heads (
    channel, platform, architecture, release_id, generation, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?)
  ON CONFLICT(channel, platform, architecture) DO UPDATE SET
    release_id = excluded.release_id,
    generation = excluded.generation,
    updated_at = excluded.updated_at
  WHERE channel_heads.generation = ?
`;

function assert(condition, message) {
  if (!condition) {
    throw new TypeError(message);
  }
}

function isPositiveSafeInteger(value) {
  return Number.isSafeInteger(value) && value > 0;
}

function assertTimestamp(value, field) {
  assert(typeof value === "string" && Number.isFinite(Date.parse(value)), `${field} must be an ISO timestamp`);
}

function assertHttpsURL(value, field) {
  if (value == null) {
    return;
  }

  assert(typeof value === "string" && value.length <= 2_048, `${field} must be an HTTPS URL`);
  const parsed = new URL(value);
  assert(parsed.protocol === "https:", `${field} must be an HTTPS URL`);
}

function normalizedMinimumMacOS(release) {
  const camelCaseValue = release.minimumMacOS;
  const databaseCaseValue = release.minimum_macos;

  assert(
    camelCaseValue == null || databaseCaseValue == null || camelCaseValue === databaseCaseValue,
    "release.minimumMacOS and release.minimum_macos must agree",
  );

  return camelCaseValue ?? databaseCaseValue;
}

export function validatePublication(input) {
  assert(input && typeof input === "object", "publication is required");
  const { release, artifact, generation, expectedGeneration } = input;
  assert(release && typeof release === "object", "release is required");
  assert(artifact && typeof artifact === "object", "artifact is required");

  const minimumMacOS = normalizedMinimumMacOS(release);
  const normalizedRelease = { ...release, minimumMacOS };

  assert(RELEASE_ID_PATTERN.test(normalizedRelease.id), "release.id must be a UUID");
  assert(CHANNEL_PATTERN.test(normalizedRelease.channel), "release.channel is invalid");
  assert(VERSION_PATTERN.test(normalizedRelease.version), "release.version is invalid");
  assert(isPositiveSafeInteger(normalizedRelease.buildNumber), "release.buildNumber must be a positive integer");
  assert(normalizedRelease.platform === "macos", "release.platform must be macos");
  assert(SUPPORTED_ARCHITECTURES.has(normalizedRelease.architecture), "release.architecture is unsupported");
  assert(typeof normalizedRelease.minimumMacOS === "string" && /^\d+(?:\.\d+){0,2}$/.test(normalizedRelease.minimumMacOS), "release.minimum_macos is invalid");
  assertTimestamp(normalizedRelease.publishedAt, "release.publishedAt");
  assertHttpsURL(normalizedRelease.releaseNotesURL, "release.releaseNotesURL");

  assert(RELEASE_ID_PATTERN.test(artifact.id), "artifact.id must be a UUID");
  assert(FILE_NAME_PATTERN.test(artifact.filename), "artifact.filename is invalid");
  assert(isPositiveSafeInteger(artifact.bytes), "artifact.bytes must be a positive integer");
  assert(typeof artifact.sha256 === "string" && SHA256_PATTERN.test(artifact.sha256), "artifact.sha256 must be a SHA-256 digest");
  assert(typeof artifact.edSignature === "string" && ED_SIGNATURE_PATTERN.test(artifact.edSignature), "artifact.edSignature is invalid");
  assert(typeof artifact.contentType === "string" && artifact.contentType === "application/zip", "artifact.contentType must be application/zip");
  assert(
    artifact.r2Key === `releases/${release.version}/${release.buildNumber}/${artifact.filename}`,
    "artifact.r2Key must use the immutable release key",
  );
  assert(isPositiveSafeInteger(generation), "generation must be a positive integer");
  assert(Number.isSafeInteger(expectedGeneration) && expectedGeneration >= 0, "expectedGeneration must be a non-negative integer");
  assert(generation === expectedGeneration + 1, "generation must immediately follow expectedGeneration");

  return { release: normalizedRelease, artifact, generation, expectedGeneration };
}

function publicationStatements(input) {
  const { release, artifact, generation, expectedGeneration } = validatePublication(input);
  const timestamp = release.publishedAt;

  return [
    {
      sql: INSERT_RELEASE_IF_CHANNEL_HEAD_MATCHES,
      values: [
        release.id,
        release.channel,
        release.version,
        release.buildNumber,
        release.platform,
        release.architecture,
        release.minimumMacOS,
        timestamp,
        release.releaseNotesURL ?? null,
        timestamp,
        release.channel,
        release.platform,
        release.architecture,
        expectedGeneration,
      ],
    },
    {
      sql: INSERT_ARTIFACT,
      values: [
        artifact.id,
        release.id,
        artifact.r2Key,
        artifact.filename,
        artifact.bytes,
        artifact.sha256.toLowerCase(),
        artifact.edSignature,
        artifact.contentType,
        timestamp,
      ],
    },
    {
      sql: ADVANCE_CHANNEL_HEAD,
      values: [
        release.channel,
        release.platform,
        release.architecture,
        release.id,
        generation,
        timestamp,
        expectedGeneration,
      ],
    },
  ];
}

function sqlLiteral(value) {
  if (value == null) {
    return "NULL";
  }

  if (typeof value === "number") {
    assert(Number.isSafeInteger(value), "SQL number must be a safe integer");
    return String(value);
  }

  assert(typeof value === "string", "SQL value must be a string, integer, or null");
  assert(!value.includes("\0"), "SQL string cannot contain NUL");
  return `'${value.replaceAll("'", "''")}'`;
}

function renderBoundStatement({ sql, values }) {
  let index = 0;
  const statement = sql.replace(/\?/g, () => {
    assert(index < values.length, "SQL statement has more placeholders than values");
    const literal = sqlLiteral(values[index]);
    index += 1;
    return literal;
  });

  assert(index === values.length, "SQL statement has more values than placeholders");
  return statement.trim();
}

/**
 * Produces the three statements that must be submitted through D1Database.batch.
 * The release insert and channel-head update both compare the expected generation,
 * so a competing publisher makes the batch fail atomically instead of replacing
 * the current stable head.
 */
export function preparePublicationBatch(database, input) {
  assert(database && typeof database.prepare === "function", "D1 database is required");
  return publicationStatements(input).map(({ sql, values }) => database.prepare(sql).bind(...values));
}

/**
 * Produces semicolon-separated D1 SQL for the controlled publication CLI.
 * It intentionally shares validation, SQL, and binding order with the Worker API.
 */
export function renderPublicationSQL(input) {
  return `${publicationStatements(input).map(renderBoundStatement).join(";\n\n")};\n`;
}

export async function publishRelease(database, input) {
  return database.batch(preparePublicationBatch(database, input));
}
