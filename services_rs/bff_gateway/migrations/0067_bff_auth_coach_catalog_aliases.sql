CREATE TABLE IF NOT EXISTS auth_coach_catalog_city_aliases (
    city_alias_id TEXT PRIMARY KEY,
    city_id TEXT NOT NULL REFERENCES auth_coach_catalog_cities(city_id) ON DELETE CASCADE,
    alias_name TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_city_aliases_id_nonempty
        CHECK (btrim(city_alias_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_city_aliases_city_nonempty
        CHECK (btrim(city_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_city_aliases_name_nonempty
        CHECK (btrim(alias_name) <> '')
);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_auth_coach_catalog_city_aliases_city_alias_lower
    ON auth_coach_catalog_city_aliases(city_id, LOWER(alias_name));

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_city_aliases_alias_active
    ON auth_coach_catalog_city_aliases(LOWER(alias_name), active);

CREATE TABLE IF NOT EXISTS auth_coach_catalog_stop_cluster_aliases (
    stop_cluster_alias_id TEXT PRIMARY KEY,
    stop_cluster_id TEXT NOT NULL REFERENCES auth_coach_catalog_stop_clusters(stop_cluster_id) ON DELETE CASCADE,
    city_id TEXT NOT NULL REFERENCES auth_coach_catalog_cities(city_id) ON DELETE CASCADE,
    alias_name TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_stop_cluster_aliases_id_nonempty
        CHECK (btrim(stop_cluster_alias_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stop_cluster_aliases_cluster_nonempty
        CHECK (btrim(stop_cluster_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stop_cluster_aliases_city_nonempty
        CHECK (btrim(city_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stop_cluster_aliases_name_nonempty
        CHECK (btrim(alias_name) <> '')
);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_auth_coach_catalog_stop_cluster_aliases_cluster_alias_lower
    ON auth_coach_catalog_stop_cluster_aliases(stop_cluster_id, LOWER(alias_name));

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_stop_cluster_aliases_alias_active
    ON auth_coach_catalog_stop_cluster_aliases(LOWER(alias_name), active);
