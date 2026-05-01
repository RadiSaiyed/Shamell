# Transit Catalog Module

Owns canonical transport read models:
- stops and stop clusters
- cities and aliases
- lines, trips, calendars
- fare products and amenities
- search-oriented catalog projections

Non-goals:
- live seat holds
- booking state
- ticket issuance
- settlement

Current runtime anchor:
- first production schema slice currently lives in `services_rs/bff_gateway`
- migration: `0066_bff_auth_coach_catalog_foundation.sql`
- alias extension: `0067_bff_auth_coach_catalog_aliases.sql`
- feed health extension: `0068_bff_auth_coach_catalog_feed_health.sql`
- import run audit: `0069_bff_auth_coach_catalog_import_runs.sql`
- import run issue catalog: `0070_bff_auth_coach_catalog_import_run_issues.sql`
- import config store: `0071_bff_auth_coach_catalog_import_configs.sql`
- source artifact store + import references: `0072_bff_auth_coach_catalog_source_artifacts.sql`
- repository: `src/coach_catalog.rs`
- GTFS startup importer: `src/coach_gtfs.rs` via `COACH_GTFS_FEED_DIR`
- GTFS upload extraction root: `COACH_GTFS_UPLOAD_DIR`
- optional GTFS source discovery list: `COACH_GTFS_FEED_OPTIONS`
- operator config surface: `GET /me/coach/operator/catalog_import_config`
- operator source discovery surface: `GET /me/coach/operator/catalog_import_sources`
- operator source artifact history surface: `GET /me/coach/operator/catalog_source_artifacts`
- operator source artifact detail surface: `GET /me/coach/operator/catalog_source_artifacts/:artifact_id`
  with paginated referencing import runs via `limit` and `cursor`
- operator source upload surface: `POST /me/coach/operator/catalog_import_sources/upload`
- operator config mutation surface: `POST /me/coach/operator/catalog_import_config`
- operator audit surface: `GET /me/coach/operator/catalog_import_runs`
- the import run list now carries compact replay lineage summary per run
  and supports `status` plus `replay_scope` filters for ops triage
- operator audit detail surface: `GET /me/coach/operator/catalog_import_runs/:import_run_id`
  with paginated import issues via `limit` and `cursor`, plus server-side
  `severity` and `stage` issue filters for ops drilldown
- operator replay lineage surface: `GET /me/coach/operator/catalog_import_runs/:import_run_id/replays`
  with paginated replay runs via `limit` and `cursor`
- import issue summaries are exposed separately from the paginated issue page
- uploaded GTFS ZIPs are persisted as source artifacts and linked from config + import runs
- manual GTFS rerun surface: `POST /me/coach/operator/catalog_import_runs`
- catalog import run saved views are now server-backed per ops account, support `personal` and `shared_ops` visibility scopes, expose the owner `account_id` for shared-view attribution, and the read surface accepts `visibility_scope=all|personal|shared_ops`
- catalog import run issue saved views are now server-backed per ops account, support a single default issue drilldown view, and are exposed via
  `GET/POST /me/coach/operator/catalog_import_run_issue_saved_views` and
  `POST /me/coach/operator/catalog_import_run_issue_saved_views/:view_id/delete`
  with `visibility_scope=all|personal|shared_ops` on the read surface and owner `account_id` in saved-view payloads
- manual reruns can optionally target a specific uploaded source artifact without changing saved config
- manual reruns can also replay a historical import run via `replay_import_run_id`
- startup currently seeds a tiny pilot catalog when the coach catalog is empty

This is intentional for the strangler phase. The next step is to route coach search
through this catalog before extracting the module boundary into `v2_core/transit_catalog`.
