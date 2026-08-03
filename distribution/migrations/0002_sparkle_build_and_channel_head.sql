CREATE UNIQUE INDEX releases_unique_sparkle_build_idx
    ON releases (channel, platform, architecture, build_number);
