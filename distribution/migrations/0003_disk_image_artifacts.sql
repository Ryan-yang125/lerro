PRAGMA defer_foreign_keys = true;

CREATE TABLE artifacts_new (
    id TEXT PRIMARY KEY,
    release_id TEXT NOT NULL REFERENCES releases(id) ON DELETE RESTRICT,
    kind TEXT NOT NULL CHECK (kind IN ('macos-zip', 'macos-dmg')),
    r2_key TEXT NOT NULL UNIQUE,
    filename TEXT NOT NULL,
    bytes INTEGER NOT NULL CHECK (bytes > 0),
    sha256 TEXT NOT NULL,
    sparkle_ed_signature TEXT NOT NULL,
    content_type TEXT NOT NULL DEFAULT 'application/zip',
    created_at TEXT NOT NULL,
    UNIQUE (release_id, kind),
    CHECK (
        (kind = 'macos-zip' AND sparkle_ed_signature <> '')
        OR (kind = 'macos-dmg' AND sparkle_ed_signature = '')
    )
);

INSERT INTO artifacts_new (
    id, release_id, kind, r2_key, filename, bytes, sha256,
    sparkle_ed_signature, content_type, created_at
)
SELECT
    id, release_id, kind, r2_key, filename, bytes, sha256,
    sparkle_ed_signature, content_type, created_at
FROM artifacts;

DROP TABLE artifacts;

ALTER TABLE artifacts_new RENAME TO artifacts;

CREATE INDEX artifacts_release_idx
    ON artifacts (release_id, kind);
