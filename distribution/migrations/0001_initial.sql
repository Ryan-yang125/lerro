PRAGMA foreign_keys = ON;

CREATE TABLE releases (
    id TEXT PRIMARY KEY,
    channel TEXT NOT NULL,
    version TEXT NOT NULL,
    build_number INTEGER NOT NULL CHECK (build_number > 0),
    platform TEXT NOT NULL CHECK (platform = 'macos'),
    architecture TEXT NOT NULL CHECK (architecture IN ('arm64', 'x86_64', 'universal')),
    minimum_macos TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('draft', 'published', 'withdrawn')),
    published_at TEXT,
    release_notes_url TEXT,
    created_at TEXT NOT NULL,
    UNIQUE (channel, version, build_number, platform, architecture)
);

CREATE TABLE artifacts (
    id TEXT PRIMARY KEY,
    release_id TEXT NOT NULL REFERENCES releases(id) ON DELETE RESTRICT,
    kind TEXT NOT NULL CHECK (kind = 'macos-zip'),
    r2_key TEXT NOT NULL UNIQUE,
    filename TEXT NOT NULL,
    bytes INTEGER NOT NULL CHECK (bytes > 0),
    sha256 TEXT NOT NULL,
    sparkle_ed_signature TEXT NOT NULL,
    content_type TEXT NOT NULL DEFAULT 'application/zip',
    created_at TEXT NOT NULL,
    UNIQUE (release_id, kind)
);

CREATE TABLE channel_heads (
    channel TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform = 'macos'),
    architecture TEXT NOT NULL CHECK (architecture IN ('arm64', 'x86_64', 'universal')),
    release_id TEXT NOT NULL REFERENCES releases(id) ON DELETE RESTRICT,
    generation INTEGER NOT NULL CHECK (generation > 0),
    updated_at TEXT NOT NULL,
    PRIMARY KEY (channel, platform, architecture)
);

CREATE INDEX releases_appcast_idx
    ON releases (channel, platform, architecture, status, build_number DESC);

CREATE INDEX artifacts_release_idx
    ON artifacts (release_id, kind);
