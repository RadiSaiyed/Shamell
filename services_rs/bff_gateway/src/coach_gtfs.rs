use crate::auth::AuthRuntime;
use crate::coach_catalog::{
    CoachCatalogCity, CoachCatalogCounts, CoachCatalogFareProduct, CoachCatalogImportRun,
    CoachCatalogImportRunIssue, CoachCatalogLine, CoachCatalogOperator, CoachCatalogRepository,
    CoachCatalogServiceCalendar, CoachCatalogStop, CoachCatalogStopCluster, CoachCatalogTrip,
    CoachOperatorFeedHealthUpsert,
};
use csv::Trim;
use serde::de::DeserializeOwned;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::error::Error;
use std::fs;
use std::io::{copy, Cursor};
use std::path::{Path, PathBuf};
use zip::ZipArchive;

type DynError = Box<dyn Error + Send + Sync>;

const DEFAULT_SEATS_TOTAL: i32 = 49;
const DEFAULT_SOURCE_KIND: &str = "gtfs";
const GTFS_FEED_OPTIONS_ENV: &str = "COACH_GTFS_FEED_OPTIONS";
const GTFS_UPLOAD_ROOT_ENV: &str = "COACH_GTFS_UPLOAD_DIR";
const GTFS_UPLOAD_MAX_ARCHIVE_BYTES: usize = 64 * 1024 * 1024;
const GTFS_UPLOAD_MAX_ARCHIVE_ENTRIES: usize = 2_048;
const GTFS_UPLOAD_MAX_EXTRACTED_BYTES: u64 = 256 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachGtfsFeedConfig {
    pub source_kind: String,
    pub configured: bool,
    pub feed_locator: Option<String>,
    pub status: String,
    pub detail: String,
    pub config_origin: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachGtfsFeedSourceOption {
    pub source_kind: String,
    pub feed_locator: String,
    pub source_origin: String,
    pub source_label: String,
    pub status: String,
    pub detail: String,
    pub selected: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachGtfsUploadedSource {
    pub source_artifact_id: String,
    pub source_kind: String,
    pub source_label: String,
    pub file_name: String,
    pub file_checksum_sha256: String,
    pub content_length_bytes: i64,
    pub feed_locator: String,
    pub extracted_file_count: usize,
    pub operator_ids: Vec<String>,
}

#[derive(Debug, Clone)]
struct CoachGtfsImportBundle {
    operators: Vec<CoachCatalogOperator>,
    cities: Vec<CoachCatalogCity>,
    stop_clusters: Vec<CoachCatalogStopCluster>,
    stops: Vec<CoachCatalogStop>,
    lines: Vec<CoachCatalogLine>,
    service_calendars: Vec<CoachCatalogServiceCalendar>,
    trips: Vec<CoachCatalogTrip>,
    fare_products: Vec<CoachCatalogFareProduct>,
    operator_trip_counts: BTreeMap<String, i64>,
}

fn gtfs_bundle_counts(bundle: &CoachGtfsImportBundle) -> CoachCatalogCounts {
    CoachCatalogCounts {
        operators: bundle.operators.len() as i64,
        cities: bundle.cities.len() as i64,
        stop_clusters: bundle.stop_clusters.len() as i64,
        stops: bundle.stops.len() as i64,
        lines: bundle.lines.len() as i64,
        service_calendars: bundle.service_calendars.len() as i64,
        trips: bundle.trips.len() as i64,
        fare_products: bundle.fare_products.len() as i64,
    }
}

#[derive(Debug, Clone, Deserialize)]
struct GtfsAgencyRow {
    agency_id: Option<String>,
    agency_name: String,
    #[serde(rename = "agency_timezone")]
    _agency_timezone: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct GtfsStopRow {
    stop_id: String,
    stop_name: String,
    stop_lat: Option<f64>,
    stop_lon: Option<f64>,
    #[serde(rename = "location_type")]
    _location_type: Option<i32>,
    parent_station: Option<String>,
    municipality: Option<String>,
    #[serde(rename = "stop_desc")]
    _stop_desc: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct GtfsRouteRow {
    route_id: String,
    agency_id: Option<String>,
    route_short_name: Option<String>,
    route_long_name: Option<String>,
    route_type: Option<i32>,
}

#[derive(Debug, Clone, Deserialize)]
struct GtfsTripRow {
    route_id: String,
    service_id: String,
    trip_id: String,
}

#[derive(Debug, Clone, Deserialize)]
struct GtfsStopTimeRow {
    trip_id: String,
    arrival_time: Option<String>,
    departure_time: Option<String>,
    stop_id: String,
    stop_sequence: i32,
}

#[derive(Debug, Clone, Deserialize)]
struct GtfsCalendarRow {
    service_id: String,
    monday: i32,
    tuesday: i32,
    wednesday: i32,
    thursday: i32,
    friday: i32,
    saturday: i32,
    sunday: i32,
    start_date: String,
    end_date: String,
}

#[derive(Debug, Clone, Deserialize)]
struct GtfsFareAttributeRow {
    fare_id: String,
    price: String,
    currency_type: String,
}

#[derive(Debug, Clone, Deserialize)]
struct GtfsFareRuleRow {
    fare_id: String,
    route_id: Option<String>,
}

#[derive(Debug, Clone)]
struct GtfsImportedStop {
    stop_id: String,
    city_id: String,
    city_name: String,
    cluster_id: String,
    cluster_name: String,
    stop_name: String,
    platform_code: Option<String>,
    lat: Option<f64>,
    lon: Option<f64>,
}

#[derive(Debug, Clone)]
struct GtfsResolvedFare {
    currency: String,
    price_minor_units: i64,
    fare_name: String,
}

#[derive(Debug, Clone)]
struct CoachGtfsImportIssueSpec {
    severity: &'static str,
    stage: &'static str,
    code: &'static str,
    message: String,
    file_name: Option<String>,
    row_reference: Option<String>,
}

pub async fn import_gtfs_catalog_best_effort(
    auth: Option<&AuthRuntime>,
    feed_dir: Option<&str>,
    context: &'static str,
) {
    let Some(auth) = auth else {
        return;
    };
    let Some(feed_dir) = feed_dir.map(str::trim).filter(|value| !value.is_empty()) else {
        return;
    };
    if let Err(error) = execute_gtfs_catalog_import(auth, feed_dir, context, None, None).await {
        tracing::warn!(
            error = %error,
            context,
            feed_dir,
            "coach GTFS import failed during startup; continuing without blocking service startup"
        );
    }
}

pub fn configured_gtfs_feed_dir() -> Option<String> {
    std::env::var("COACH_GTFS_FEED_DIR")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn configured_gtfs_feed_option_dirs() -> Vec<String> {
    let raw = std::env::var(GTFS_FEED_OPTIONS_ENV).unwrap_or_default();
    let mut results = Vec::new();
    for entry in raw
        .split(['\n', ',', ';'])
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        let value = entry.to_string();
        if !results.contains(&value) {
            results.push(value);
        }
    }
    results
}

fn configured_gtfs_upload_root() -> PathBuf {
    let configured = std::env::var(GTFS_UPLOAD_ROOT_ENV)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());
    configured
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("shamell_coach_gtfs_uploads"))
}

fn required_gtfs_file_names() -> &'static [&'static str] {
    &[
        "agency.txt",
        "stops.txt",
        "routes.txt",
        "trips.txt",
        "stop_times.txt",
        "calendar.txt",
    ]
}

fn sanitize_gtfs_archive_file_name(file_name: &str) -> Result<String, DynError> {
    let trimmed = file_name.trim();
    if trimmed.is_empty() {
        return Err("GTFS upload file name required".into());
    }
    if !trimmed.to_ascii_lowercase().ends_with(".zip") {
        return Err("GTFS upload must be a .zip archive".into());
    }
    let file_name = Path::new(trimmed)
        .file_name()
        .and_then(|value| value.to_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or("invalid GTFS upload file name")?;
    Ok(file_name.to_string())
}

fn sanitize_gtfs_archive_entry_path(name: &str) -> Result<PathBuf, DynError> {
    let path = Path::new(name);
    let mut relative = PathBuf::new();
    for component in path.components() {
        match component {
            std::path::Component::Normal(value) => relative.push(value),
            std::path::Component::CurDir => {}
            std::path::Component::RootDir
            | std::path::Component::ParentDir
            | std::path::Component::Prefix(_) => {
                return Err(format!("invalid GTFS archive entry path: {name}").into());
            }
        }
    }
    if relative.as_os_str().is_empty() {
        return Err(format!("invalid GTFS archive entry path: {name}").into());
    }
    Ok(relative)
}

fn validate_gtfs_upload_extract(target_dir: &Path) -> Result<(), DynError> {
    for file_name in required_gtfs_file_names() {
        if !target_dir.join(file_name).is_file() {
            return Err(format!("required GTFS file missing after upload: {file_name}").into());
        }
    }
    Ok(())
}

fn inspect_gtfs_uploaded_operator_ids(target_dir: &Path) -> Vec<String> {
    read_required_csv::<GtfsAgencyRow>(target_dir, "agency.txt")
        .map(|agencies| {
            let values = agencies
                .iter()
                .map(operator_id_from_agency)
                .collect::<Vec<_>>();
            let mut unique = std::collections::BTreeSet::new();
            for value in values {
                let normalized = value.trim();
                if normalized.is_empty() {
                    continue;
                }
                unique.insert(normalized.to_string());
            }
            unique.into_iter().collect()
        })
        .unwrap_or_default()
}

pub async fn upload_gtfs_catalog_archive(
    _auth: &AuthRuntime,
    file_name: &str,
    file_bytes: &[u8],
    account_id: &str,
) -> Result<CoachGtfsUploadedSource, DynError> {
    if file_bytes.is_empty() {
        return Err("uploaded GTFS archive is empty".into());
    }
    if file_bytes.len() > GTFS_UPLOAD_MAX_ARCHIVE_BYTES {
        return Err("uploaded GTFS archive is too large".into());
    }
    let sanitized_file_name = sanitize_gtfs_archive_file_name(file_name)?;
    let upload_root = configured_gtfs_upload_root();
    fs::create_dir_all(&upload_root)?;

    let mut file_checksum_hasher = Sha256::new();
    file_checksum_hasher.update(file_bytes);
    let file_checksum_sha256 = format!("{:x}", file_checksum_hasher.finalize());

    let mut hasher = Sha256::new();
    hasher.update(file_bytes);
    hasher.update(account_id.as_bytes());
    hasher.update(sanitized_file_name.as_bytes());
    let upload_hash = format!("{:x}", hasher.finalize());
    let hash_prefix = &upload_hash[..12];
    let file_stem = sanitized_file_name
        .strip_suffix(".zip")
        .unwrap_or(sanitized_file_name.as_str())
        .trim();
    let stem = if file_stem.is_empty() {
        "gtfs_upload"
    } else {
        file_stem
    };
    let safe_stem = stem
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_') {
                ch
            } else {
                '_'
            }
        })
        .collect::<String>();
    let target_dir = upload_root.join(format!("{safe_stem}_{hash_prefix}"));
    if target_dir.exists() {
        fs::remove_dir_all(&target_dir)?;
    }
    fs::create_dir_all(&target_dir)?;

    let extraction_result = (|| -> Result<usize, DynError> {
        let cursor = Cursor::new(file_bytes);
        let mut archive = ZipArchive::new(cursor)?;
        if archive.len() > GTFS_UPLOAD_MAX_ARCHIVE_ENTRIES {
            return Err("uploaded GTFS archive contains too many files".into());
        }
        let mut extracted_files = 0usize;
        let mut extracted_bytes = 0u64;
        for index in 0..archive.len() {
            let mut entry = archive.by_index(index)?;
            let entry_name = entry.name().to_string();
            let relative_path = sanitize_gtfs_archive_entry_path(entry_name.as_str())?;
            let output_path = target_dir.join(relative_path);
            if entry.is_dir() {
                fs::create_dir_all(&output_path)?;
                continue;
            }
            if let Some(parent) = output_path.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut output_file = fs::File::create(&output_path)?;
            let bytes_written = copy(&mut entry, &mut output_file)?;
            extracted_bytes += bytes_written;
            if extracted_bytes > GTFS_UPLOAD_MAX_EXTRACTED_BYTES {
                return Err("uploaded GTFS archive expands beyond the allowed size".into());
            }
            extracted_files += 1;
        }
        validate_gtfs_upload_extract(&target_dir)?;
        Ok(extracted_files)
    })();

    match extraction_result {
        Ok(extracted_file_count) => Ok(CoachGtfsUploadedSource {
            source_artifact_id: safe_catalog_id(
                "catalog_source_artifact",
                format!(
                    "{}|{}|{}",
                    DEFAULT_SOURCE_KIND, sanitized_file_name, file_checksum_sha256
                )
                .as_str(),
            ),
            source_kind: DEFAULT_SOURCE_KIND.to_string(),
            source_label: sanitized_file_name.clone(),
            file_name: sanitized_file_name,
            file_checksum_sha256,
            content_length_bytes: file_bytes.len() as i64,
            feed_locator: target_dir.to_string_lossy().to_string(),
            extracted_file_count,
            operator_ids: inspect_gtfs_uploaded_operator_ids(&target_dir),
        }),
        Err(error) => {
            let _ = fs::remove_dir_all(&target_dir);
            Err(error)
        }
    }
}

fn inspect_gtfs_feed_locator(feed_locator: String, config_origin: String) -> CoachGtfsFeedConfig {
    let path = Path::new(feed_locator.as_str());
    if !path.exists() {
        return CoachGtfsFeedConfig {
            source_kind: DEFAULT_SOURCE_KIND.to_string(),
            configured: true,
            feed_locator: Some(feed_locator),
            status: "missing".to_string(),
            detail: "Configured GTFS feed directory does not exist.".to_string(),
            config_origin,
        };
    }
    if !path.is_dir() {
        return CoachGtfsFeedConfig {
            source_kind: DEFAULT_SOURCE_KIND.to_string(),
            configured: true,
            feed_locator: Some(feed_locator),
            status: "missing".to_string(),
            detail: "Configured GTFS feed locator is not a directory.".to_string(),
            config_origin,
        };
    }
    CoachGtfsFeedConfig {
        source_kind: DEFAULT_SOURCE_KIND.to_string(),
        configured: true,
        feed_locator: Some(feed_locator),
        status: "ready".to_string(),
        detail: "GTFS feed directory is configured.".to_string(),
        config_origin,
    }
}

pub fn current_gtfs_feed_config_with_override(
    feed_locator_override: Option<&str>,
) -> CoachGtfsFeedConfig {
    let override_locator = feed_locator_override
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string);
    let (feed_locator, config_origin, unconfigured_detail) = if let Some(locator) = override_locator
    {
        (
            Some(locator),
            "database".to_string(),
            "Persisted GTFS feed locator is not configured.".to_string(),
        )
    } else {
        (
            configured_gtfs_feed_dir(),
            "environment".to_string(),
            "COACH_GTFS_FEED_DIR is not configured.".to_string(),
        )
    };
    let Some(feed_locator) = feed_locator else {
        return CoachGtfsFeedConfig {
            source_kind: DEFAULT_SOURCE_KIND.to_string(),
            configured: false,
            feed_locator: None,
            status: "missing".to_string(),
            detail: unconfigured_detail,
            config_origin,
        };
    };
    inspect_gtfs_feed_locator(feed_locator, config_origin)
}

pub fn current_gtfs_feed_config() -> CoachGtfsFeedConfig {
    current_gtfs_feed_config_with_override(None)
}

pub fn available_gtfs_feed_sources(
    persisted_feed_locator: Option<&str>,
    persisted_source_label: Option<&str>,
) -> Vec<CoachGtfsFeedSourceOption> {
    let effective_config = current_gtfs_feed_config_with_override(persisted_feed_locator);
    let selected_locator = effective_config.feed_locator.clone();
    let mut candidates: Vec<(String, String, String)> = Vec::new();

    if let Some(locator) = persisted_feed_locator
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        candidates.push((
            locator.to_string(),
            "database_saved".to_string(),
            persisted_source_label
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or("Saved feed locator")
                .to_string(),
        ));
    }

    if let Some(locator) = configured_gtfs_feed_dir() {
        candidates.push((
            locator,
            "environment_default".to_string(),
            "Environment default".to_string(),
        ));
    }

    for (index, locator) in configured_gtfs_feed_option_dirs().into_iter().enumerate() {
        candidates.push((
            locator,
            "environment_option".to_string(),
            format!("Configured source {}", index + 1),
        ));
    }

    let mut seen = std::collections::HashSet::new();
    let mut sources = Vec::new();
    for (feed_locator, source_origin, source_label) in candidates {
        if !seen.insert(feed_locator.clone()) {
            continue;
        }
        let config = inspect_gtfs_feed_locator(feed_locator.clone(), source_origin.clone());
        sources.push(CoachGtfsFeedSourceOption {
            source_kind: config.source_kind,
            feed_locator,
            source_origin,
            source_label,
            status: config.status,
            detail: config.detail,
            selected: selected_locator.as_deref()
                == Some(config.feed_locator.as_deref().unwrap_or_default()),
        });
    }
    sources
}

pub async fn trigger_gtfs_catalog_import(
    auth: &AuthRuntime,
    feed_dir: &str,
    context: &'static str,
    source_artifact_id: Option<&str>,
    replayed_from_import_run_id: Option<&str>,
) -> Result<CoachCatalogImportRun, DynError> {
    execute_gtfs_catalog_import(
        auth,
        feed_dir,
        context,
        source_artifact_id,
        replayed_from_import_run_id,
    )
    .await
}

async fn execute_gtfs_catalog_import(
    auth: &AuthRuntime,
    feed_dir: &str,
    context: &'static str,
    source_artifact_id: Option<&str>,
    replayed_from_import_run_id: Option<&str>,
) -> Result<CoachCatalogImportRun, DynError> {
    let repo = CoachCatalogRepository::new(auth.pool().clone());
    let source_artifact = match source_artifact_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        Some(artifact_id) => repo.find_source_artifact_by_id(artifact_id).await?,
        None => None,
    };
    let started_at_iso = chrono::Utc::now().to_rfc3339();
    let import_run_id = gtfs_import_run_id(feed_dir, started_at_iso.as_str());
    let running_import_run = CoachCatalogImportRun {
        import_run_id: import_run_id.clone(),
        feed_kind: "static_catalog".to_string(),
        source_kind: DEFAULT_SOURCE_KIND.to_string(),
        trigger_kind: normalized_import_trigger_kind(context).to_string(),
        feed_locator: Some(feed_dir.to_string()),
        operator_ids: source_artifact
            .as_ref()
            .map(|entry| entry.operator_ids.clone())
            .unwrap_or_default(),
        replayed_from_import_run_id: replayed_from_import_run_id.map(str::to_string),
        source_artifact_id: source_artifact
            .as_ref()
            .map(|entry| entry.artifact_id.clone()),
        source_artifact: source_artifact.clone(),
        status: "running".to_string(),
        started_at_iso: started_at_iso.clone(),
        finished_at_iso: None,
        counts: CoachCatalogCounts::default(),
        error_message: None,
        issues: Vec::new(),
    };
    repo.insert_import_run(&running_import_run).await?;

    match import_gtfs_catalog_from_dir(&repo, feed_dir).await {
        Ok(bundle) => {
            let counts = gtfs_bundle_counts(&bundle);
            let operator_ids = bundle
                .operators
                .iter()
                .map(|entry| entry.operator_id.clone())
                .collect::<Vec<_>>();
            if let Some(source_artifact) = source_artifact.as_ref() {
                let mut updated_source_artifact = source_artifact.clone();
                updated_source_artifact.operator_ids = operator_ids.clone();
                repo.upsert_source_artifact(&updated_source_artifact)
                    .await?;
            }
            let finished_at_iso = chrono::Utc::now().to_rfc3339();
            repo.finalize_import_run(
                import_run_id.as_str(),
                "succeeded",
                finished_at_iso.as_str(),
                &counts,
                &operator_ids,
                None,
            )
            .await?;
            tracing::info!(
                context,
                feed_dir,
                import_run_id,
                operators = bundle.operators.len(),
                trips = bundle.trips.len(),
                fares = bundle.fare_products.len(),
                total_records = counts.total_records(),
                "imported coach GTFS catalog feed"
            );
            Ok(CoachCatalogImportRun {
                import_run_id,
                feed_kind: "static_catalog".to_string(),
                source_kind: DEFAULT_SOURCE_KIND.to_string(),
                trigger_kind: normalized_import_trigger_kind(context).to_string(),
                feed_locator: Some(feed_dir.to_string()),
                operator_ids,
                replayed_from_import_run_id: replayed_from_import_run_id.map(str::to_string),
                source_artifact_id: source_artifact
                    .as_ref()
                    .map(|entry| entry.artifact_id.clone()),
                source_artifact: source_artifact.clone(),
                status: "succeeded".to_string(),
                started_at_iso,
                finished_at_iso: Some(finished_at_iso),
                counts,
                error_message: None,
                issues: Vec::new(),
            })
        }
        Err(error) => {
            let error_detail = error.to_string();
            let finished_at_iso = chrono::Utc::now().to_rfc3339();
            let counts = CoachCatalogCounts::default();
            let operator_ids = source_artifact
                .as_ref()
                .map(|entry| entry.operator_ids.clone())
                .unwrap_or_default();
            let issues = derive_import_run_issues(import_run_id.as_str(), error_detail.as_str());
            repo.finalize_import_run(
                import_run_id.as_str(),
                "failed",
                finished_at_iso.as_str(),
                &counts,
                &operator_ids,
                Some(error_detail.as_str()),
            )
            .await?;
            repo.replace_import_run_issues(import_run_id.as_str(), &issues)
                .await?;
            tracing::warn!(
                error = %error,
                context,
                feed_dir,
                import_run_id,
                "coach GTFS import failed"
            );
            Ok(CoachCatalogImportRun {
                import_run_id,
                feed_kind: "static_catalog".to_string(),
                source_kind: DEFAULT_SOURCE_KIND.to_string(),
                trigger_kind: normalized_import_trigger_kind(context).to_string(),
                feed_locator: Some(feed_dir.to_string()),
                operator_ids,
                replayed_from_import_run_id: replayed_from_import_run_id.map(str::to_string),
                source_artifact_id: source_artifact
                    .as_ref()
                    .map(|entry| entry.artifact_id.clone()),
                source_artifact: source_artifact.clone(),
                status: "failed".to_string(),
                started_at_iso,
                finished_at_iso: Some(finished_at_iso),
                counts,
                error_message: Some(error_detail),
                issues,
            })
        }
    }
}

async fn import_gtfs_catalog_from_dir(
    repo: &CoachCatalogRepository,
    feed_dir: &str,
) -> Result<CoachGtfsImportBundle, DynError> {
    let feed_path = Path::new(feed_dir);
    let default_currency = std::env::var("COACH_GTFS_DEFAULT_CURRENCY")
        .ok()
        .map(|value| value.trim().to_uppercase())
        .filter(|value| value.len() == 3)
        .unwrap_or_else(|| "EUR".to_string());
    let default_price_minor_units = std::env::var("COACH_GTFS_DEFAULT_PRICE_MINOR_UNITS")
        .ok()
        .and_then(|value| value.trim().parse::<i64>().ok())
        .filter(|value| *value >= 0)
        .unwrap_or(0);

    let bundle =
        load_gtfs_import_bundle_from_dir(feed_path, &default_currency, default_price_minor_units)?;

    for operator in &bundle.operators {
        repo.upsert_operator(operator).await?;
    }
    for city in &bundle.cities {
        repo.upsert_city(city).await?;
    }
    for stop_cluster in &bundle.stop_clusters {
        repo.upsert_stop_cluster(stop_cluster).await?;
    }
    for stop in &bundle.stops {
        repo.upsert_stop(stop).await?;
    }
    for line in &bundle.lines {
        repo.upsert_line(line).await?;
    }
    for calendar in &bundle.service_calendars {
        repo.upsert_service_calendar(calendar).await?;
    }
    for trip in &bundle.trips {
        repo.upsert_trip(trip).await?;
    }
    for fare_product in &bundle.fare_products {
        repo.upsert_fare_product(fare_product).await?;
    }

    let imported_at = chrono::Utc::now();
    let imported_at_iso = imported_at.to_rfc3339();
    let expires_at_iso = (imported_at + chrono::Duration::hours(24)).to_rfc3339();
    for (operator_id, records_ingested) in &bundle.operator_trip_counts {
        repo.upsert_operator_feed_health(&CoachOperatorFeedHealthUpsert {
            operator_id,
            feed_kind: "static_catalog",
            source_kind: DEFAULT_SOURCE_KIND,
            sync_status: "ok",
            freshness_status: "fresh",
            last_attempted_at_iso: Some(imported_at_iso.as_str()),
            last_succeeded_at_iso: Some(imported_at_iso.as_str()),
            freshness_expires_at_iso: Some(expires_at_iso.as_str()),
            records_ingested: *records_ingested,
            error_message: None,
        })
        .await?;
    }

    Ok(bundle)
}

fn normalized_import_trigger_kind(context: &str) -> &str {
    match context.trim().to_ascii_lowercase().as_str() {
        "manual" => "manual",
        "scheduled" => "scheduled",
        _ => "startup",
    }
}

fn gtfs_import_run_id(feed_dir: &str, started_at_iso: &str) -> String {
    safe_catalog_id(
        "catalogimportrun",
        format!(
            "{}|{}|{}",
            DEFAULT_SOURCE_KIND,
            feed_dir.trim(),
            started_at_iso.trim()
        )
        .as_str(),
    )
}

fn derive_import_run_issues(
    import_run_id: &str,
    error_detail: &str,
) -> Vec<CoachCatalogImportRunIssue> {
    classify_import_issue_specs(error_detail)
        .into_iter()
        .enumerate()
        .map(|(index, spec)| CoachCatalogImportRunIssue {
            issue_id: safe_catalog_id(
                "catalogimportissue",
                format!(
                    "{}|{}|{}|{}|{}",
                    import_run_id,
                    index,
                    spec.stage,
                    spec.code,
                    spec.file_name.as_deref().unwrap_or("none")
                )
                .as_str(),
            ),
            import_run_id: import_run_id.to_string(),
            severity: spec.severity.to_string(),
            stage: spec.stage.to_string(),
            code: spec.code.to_string(),
            message: spec.message,
            file_name: spec.file_name,
            row_reference: spec.row_reference,
        })
        .collect()
}

fn classify_import_issue_specs(error_detail: &str) -> Vec<CoachGtfsImportIssueSpec> {
    let normalized = error_detail.trim();
    let missing_prefix = "required GTFS file missing: ";
    if let Some(path) = normalized.strip_prefix(missing_prefix) {
        let file_name = Path::new(path)
            .file_name()
            .and_then(|value| value.to_str())
            .map(ToString::to_string);
        return vec![CoachGtfsImportIssueSpec {
            severity: "error",
            stage: "load_feed",
            code: "required_file_missing",
            message: normalized.to_string(),
            file_name,
            row_reference: None,
        }];
    }
    if normalized.contains("CSV deserialize error")
        || normalized.contains("CSV error")
        || normalized.contains("UnequalLengths")
    {
        return vec![CoachGtfsImportIssueSpec {
            severity: "error",
            stage: "parse_csv",
            code: "csv_parse_failed",
            message: normalized.to_string(),
            file_name: None,
            row_reference: None,
        }];
    }
    if normalized.contains("invalid float literal")
        || normalized.contains("ParseFloatError")
        || normalized.contains("invalid digit found in string")
    {
        return vec![CoachGtfsImportIssueSpec {
            severity: "error",
            stage: "build_catalog",
            code: "invalid_numeric_value",
            message: normalized.to_string(),
            file_name: None,
            row_reference: None,
        }];
    }
    vec![CoachGtfsImportIssueSpec {
        severity: "error",
        stage: "load_feed",
        code: "import_failed",
        message: normalized.to_string(),
        file_name: None,
        row_reference: None,
    }]
}

fn load_gtfs_import_bundle_from_dir(
    feed_dir: &Path,
    default_currency: &str,
    default_price_minor_units: i64,
) -> Result<CoachGtfsImportBundle, DynError> {
    let agencies = read_required_csv::<GtfsAgencyRow>(feed_dir, "agency.txt")?;
    let routes = read_required_csv::<GtfsRouteRow>(feed_dir, "routes.txt")?;
    let trips = read_required_csv::<GtfsTripRow>(feed_dir, "trips.txt")?;
    let stop_times = read_required_csv::<GtfsStopTimeRow>(feed_dir, "stop_times.txt")?;
    let stops = read_required_csv::<GtfsStopRow>(feed_dir, "stops.txt")?;
    let calendars = read_required_csv::<GtfsCalendarRow>(feed_dir, "calendar.txt")?;
    let fare_attributes =
        read_optional_csv::<GtfsFareAttributeRow>(feed_dir, "fare_attributes.txt")?;
    let fare_rules = read_optional_csv::<GtfsFareRuleRow>(feed_dir, "fare_rules.txt")?;

    let default_operator_id = agencies
        .first()
        .map(operator_id_from_agency)
        .unwrap_or_else(|| safe_catalog_id("operator", "default"));
    let operators = build_operators(&agencies);
    let calendars_out = build_calendars(&calendars);

    let stop_rows_by_id = stops
        .iter()
        .cloned()
        .map(|stop| (stop.stop_id.clone(), stop))
        .collect::<HashMap<_, _>>();
    let imported_stops = build_imported_stops(&stops, &stop_rows_by_id);
    let cities = collect_cities(&imported_stops);
    let stop_clusters = collect_stop_clusters(&imported_stops);
    let stops_out = collect_stops(&imported_stops);

    let route_lines = build_lines(&routes, &agencies, &default_operator_id);
    let route_line_by_raw_id = route_lines
        .iter()
        .map(|(route_id, line)| (route_id.clone(), line.clone()))
        .collect::<HashMap<_, _>>();

    let calendars_by_raw_id = calendars_out
        .iter()
        .map(|calendar| (calendar.service_calendar_id.clone(), calendar.clone()))
        .collect::<HashMap<_, _>>();

    let times_by_trip = group_stop_times(stop_times);
    let fare_lookup = build_fare_lookup(
        &fare_attributes,
        &fare_rules,
        default_currency,
        default_price_minor_units,
    )?;

    let mut trips_out = Vec::<CoachCatalogTrip>::new();
    let mut fares_out = Vec::<CoachCatalogFareProduct>::new();
    let mut operator_trip_counts = BTreeMap::<String, i64>::new();
    for trip in trips {
        let Some(line) = route_line_by_raw_id.get(&trip.route_id) else {
            continue;
        };
        let Some(calendar) =
            calendars_by_raw_id.get(&safe_catalog_id("calendar", &trip.service_id))
        else {
            continue;
        };
        let Some(stop_time_rows) = times_by_trip.get(&trip.trip_id) else {
            continue;
        };
        let Some((origin, destination, departure_time_local, arrival_time_local, duration_minutes)) =
            resolve_trip_terminals(stop_time_rows, &imported_stops)
        else {
            continue;
        };

        let trip_id = safe_catalog_id("trip", &trip.trip_id);
        let seats_total = default_seats_total_for_route(line.vehicle_class.as_deref());
        let seats_available = seats_total;
        trips_out.push(CoachCatalogTrip {
            trip_id: trip_id.clone(),
            operator_id: line.operator_id.clone(),
            line_id: line.line_id.clone(),
            service_calendar_id: calendar.service_calendar_id.clone(),
            origin_stop_cluster_id: origin.cluster_id.clone(),
            destination_stop_cluster_id: destination.cluster_id.clone(),
            departure_time_local,
            arrival_time_local,
            duration_minutes,
            service_timezone: city_timezone_for_stop(origin, &cities)
                .unwrap_or_else(|| "UTC".to_string()),
            seats_total,
            seats_available,
            active: true,
        });

        let resolved_fare = resolve_route_fare(
            &trip.route_id,
            &fare_lookup,
            default_currency,
            default_price_minor_units,
        );
        fares_out.push(CoachCatalogFareProduct {
            fare_product_id: safe_catalog_id(
                "fare",
                &format!("{}-{}", trip.trip_id, resolved_fare.fare_name),
            ),
            trip_id,
            fare_name: resolved_fare.fare_name,
            passenger_type: "adult".to_string(),
            currency: resolved_fare.currency,
            price_minor_units: resolved_fare.price_minor_units,
            hold_supported: true,
            changeable: true,
            refundable: resolved_fare.price_minor_units > 0,
            baggage_rule: Some("GTFS import default baggage policy".to_string()),
            active: true,
        });
        *operator_trip_counts
            .entry(line.operator_id.clone())
            .or_insert(0) += 1;
    }

    Ok(CoachGtfsImportBundle {
        operators,
        cities,
        stop_clusters,
        stops: stops_out,
        lines: route_line_by_raw_id.into_values().collect(),
        service_calendars: calendars_out,
        trips: trips_out,
        fare_products: fares_out,
        operator_trip_counts,
    })
}

fn build_operators(agencies: &[GtfsAgencyRow]) -> Vec<CoachCatalogOperator> {
    agencies
        .iter()
        .map(|agency| CoachCatalogOperator {
            operator_id: operator_id_from_agency(agency),
            display_name: agency.agency_name.trim().to_string(),
            integration_mode: "feed".to_string(),
            country_code: None,
            active: true,
        })
        .collect()
}

fn operator_id_from_agency(agency: &GtfsAgencyRow) -> String {
    safe_catalog_id(
        "operator",
        agency
            .agency_id
            .as_deref()
            .unwrap_or(agency.agency_name.as_str()),
    )
}

fn build_lines(
    routes: &[GtfsRouteRow],
    agencies: &[GtfsAgencyRow],
    default_operator_id: &str,
) -> Vec<(String, CoachCatalogLine)> {
    let operator_by_agency = agencies
        .iter()
        .map(|agency| {
            (
                agency.agency_id.clone().unwrap_or_default(),
                operator_id_from_agency(agency),
            )
        })
        .collect::<HashMap<_, _>>();

    routes
        .iter()
        .map(|route| {
            let operator_id = route
                .agency_id
                .as_deref()
                .and_then(|agency_id| operator_by_agency.get(agency_id))
                .cloned()
                .unwrap_or_else(|| default_operator_id.to_string());
            let marketing_name = route
                .route_long_name
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .or_else(|| {
                    route
                        .route_short_name
                        .as_deref()
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                })
                .unwrap_or(route.route_id.as_str())
                .to_string();
            let public_code = route
                .route_short_name
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToString::to_string);
            let vehicle_class = Some(vehicle_class_for_route_type(route.route_type).to_string());
            let amenities = if route.route_type == Some(3) || route.route_type == Some(200) {
                vec!["wifi".to_string(), "power_outlet".to_string()]
            } else {
                vec!["standard_seating".to_string()]
            };
            (
                route.route_id.clone(),
                CoachCatalogLine {
                    line_id: safe_catalog_id("line", &route.route_id),
                    operator_id,
                    public_code,
                    marketing_name,
                    vehicle_class,
                    amenities,
                    active: true,
                },
            )
        })
        .collect()
}

fn build_calendars(rows: &[GtfsCalendarRow]) -> Vec<CoachCatalogServiceCalendar> {
    rows.iter()
        .map(|row| CoachCatalogServiceCalendar {
            service_calendar_id: safe_catalog_id("calendar", &row.service_id),
            start_date: yyyy_mm_dd(&row.start_date).unwrap_or_else(|| "2026-01-01".to_string()),
            end_date: yyyy_mm_dd(&row.end_date).unwrap_or_else(|| "2026-12-31".to_string()),
            monday: row.monday == 1,
            tuesday: row.tuesday == 1,
            wednesday: row.wednesday == 1,
            thursday: row.thursday == 1,
            friday: row.friday == 1,
            saturday: row.saturday == 1,
            sunday: row.sunday == 1,
            active: true,
        })
        .collect()
}

fn build_imported_stops(
    rows: &[GtfsStopRow],
    all_stops: &HashMap<String, GtfsStopRow>,
) -> HashMap<String, GtfsImportedStop> {
    rows.iter()
        .map(|row| {
            let cluster_source_id = row
                .parent_station
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or(row.stop_id.as_str());
            let cluster_row = all_stops
                .get(cluster_source_id)
                .cloned()
                .unwrap_or_else(|| row.clone());
            let cluster_name = cluster_row.stop_name.trim().to_string();
            let city_name = derive_city_name(row, &cluster_row);
            let city_id = safe_catalog_id("city", &city_name);
            let platform_code = extract_platform_code(row.stop_name.as_str());
            (
                row.stop_id.clone(),
                GtfsImportedStop {
                    stop_id: safe_catalog_id("stop", &row.stop_id),
                    city_id,
                    city_name,
                    cluster_id: safe_catalog_id("cluster", cluster_source_id),
                    cluster_name,
                    stop_name: row.stop_name.trim().to_string(),
                    platform_code,
                    lat: row.stop_lat,
                    lon: row.stop_lon,
                },
            )
        })
        .collect()
}

fn collect_cities(imported_stops: &HashMap<String, GtfsImportedStop>) -> Vec<CoachCatalogCity> {
    let mut unique = BTreeMap::<String, CoachCatalogCity>::new();
    for stop in imported_stops.values() {
        unique
            .entry(stop.city_id.clone())
            .or_insert(CoachCatalogCity {
                city_id: stop.city_id.clone(),
                display_name: stop.city_name.clone(),
                country_code: "SY".to_string(),
                timezone_name: "Asia/Damascus".to_string(),
                active: true,
            });
    }
    unique.into_values().collect()
}

fn collect_stop_clusters(
    imported_stops: &HashMap<String, GtfsImportedStop>,
) -> Vec<CoachCatalogStopCluster> {
    let mut unique = BTreeMap::<String, CoachCatalogStopCluster>::new();
    for stop in imported_stops.values() {
        unique
            .entry(stop.cluster_id.clone())
            .or_insert(CoachCatalogStopCluster {
                stop_cluster_id: stop.cluster_id.clone(),
                city_id: stop.city_id.clone(),
                canonical_name: stop.cluster_name.clone(),
                lat: stop.lat,
                lon: stop.lon,
                active: true,
            });
    }
    unique.into_values().collect()
}

fn collect_stops(imported_stops: &HashMap<String, GtfsImportedStop>) -> Vec<CoachCatalogStop> {
    imported_stops
        .values()
        .map(|stop| CoachCatalogStop {
            stop_id: stop.stop_id.clone(),
            stop_cluster_id: stop.cluster_id.clone(),
            city_id: stop.city_id.clone(),
            canonical_name: stop.stop_name.clone(),
            platform_code: stop.platform_code.clone(),
            lat: stop.lat,
            lon: stop.lon,
            active: true,
        })
        .collect()
}

fn group_stop_times(rows: Vec<GtfsStopTimeRow>) -> HashMap<String, Vec<GtfsStopTimeRow>> {
    let mut grouped = HashMap::<String, Vec<GtfsStopTimeRow>>::new();
    for row in rows {
        grouped.entry(row.trip_id.clone()).or_default().push(row);
    }
    for rows in grouped.values_mut() {
        rows.sort_by_key(|row| row.stop_sequence);
    }
    grouped
}

fn resolve_trip_terminals<'a>(
    stop_times: &'a [GtfsStopTimeRow],
    imported_stops: &'a HashMap<String, GtfsImportedStop>,
) -> Option<(
    &'a GtfsImportedStop,
    &'a GtfsImportedStop,
    String,
    String,
    i32,
)> {
    let origin_time = stop_times.iter().find_map(|row| {
        let stop = imported_stops.get(&row.stop_id)?;
        let departure = row
            .departure_time
            .as_deref()
            .or(row.arrival_time.as_deref())
            .and_then(parse_gtfs_time)?;
        Some((stop, departure))
    })?;
    let destination_time = stop_times.iter().rev().find_map(|row| {
        let stop = imported_stops.get(&row.stop_id)?;
        let arrival = row
            .arrival_time
            .as_deref()
            .or(row.departure_time.as_deref())
            .and_then(parse_gtfs_time)?;
        Some((stop, arrival))
    })?;
    if origin_time.0.cluster_id == destination_time.0.cluster_id {
        return None;
    }
    let duration_minutes = (destination_time.1 - origin_time.1).max(1);
    Some((
        origin_time.0,
        destination_time.0,
        format_gtfs_time(origin_time.1),
        format_gtfs_time(destination_time.1),
        duration_minutes,
    ))
}

fn build_fare_lookup(
    attributes: &[GtfsFareAttributeRow],
    rules: &[GtfsFareRuleRow],
    default_currency: &str,
    default_price_minor_units: i64,
) -> Result<HashMap<String, Vec<GtfsResolvedFare>>, DynError> {
    let fare_attributes = attributes
        .iter()
        .map(|row| {
            Ok((
                row.fare_id.clone(),
                GtfsResolvedFare {
                    currency: row.currency_type.trim().to_uppercase(),
                    price_minor_units: decimal_price_to_minor_units(
                        row.currency_type.as_str(),
                        row.price.as_str(),
                    )?,
                    fare_name: row.fare_id.trim().to_string(),
                },
            ))
        })
        .collect::<Result<HashMap<_, _>, DynError>>()?;

    let mut by_route = HashMap::<String, Vec<GtfsResolvedFare>>::new();
    for rule in rules {
        let Some(route_id) = rule
            .route_id
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            continue;
        };
        let Some(fare) = fare_attributes.get(rule.fare_id.as_str()).cloned() else {
            continue;
        };
        by_route.entry(route_id.to_string()).or_default().push(fare);
    }

    if by_route.is_empty() && fare_attributes.len() == 1 {
        let fare = fare_attributes
            .values()
            .next()
            .cloned()
            .expect("single fare exists");
        by_route.insert("*".to_string(), vec![fare]);
    }

    if by_route.is_empty() {
        by_route.insert(
            "*".to_string(),
            vec![GtfsResolvedFare {
                currency: default_currency.to_string(),
                price_minor_units: default_price_minor_units,
                fare_name: "Standard".to_string(),
            }],
        );
    }

    Ok(by_route)
}

fn resolve_route_fare(
    route_id: &str,
    fare_lookup: &HashMap<String, Vec<GtfsResolvedFare>>,
    default_currency: &str,
    default_price_minor_units: i64,
) -> GtfsResolvedFare {
    fare_lookup
        .get(route_id)
        .or_else(|| fare_lookup.get("*"))
        .and_then(|items| items.iter().min_by_key(|item| item.price_minor_units))
        .cloned()
        .unwrap_or(GtfsResolvedFare {
            currency: default_currency.to_string(),
            price_minor_units: default_price_minor_units,
            fare_name: "Standard".to_string(),
        })
}

fn city_timezone_for_stop(stop: &GtfsImportedStop, cities: &[CoachCatalogCity]) -> Option<String> {
    cities
        .iter()
        .find(|city| city.city_id == stop.city_id)
        .map(|city| city.timezone_name.clone())
}

fn vehicle_class_for_route_type(route_type: Option<i32>) -> &'static str {
    match route_type {
        Some(3) | Some(200) => "coach",
        _ => "standard",
    }
}

fn default_seats_total_for_route(vehicle_class: Option<&str>) -> i32 {
    match vehicle_class.unwrap_or("coach") {
        "coach" => DEFAULT_SEATS_TOTAL,
        _ => 32,
    }
}

fn derive_city_name(row: &GtfsStopRow, cluster_row: &GtfsStopRow) -> String {
    if let Some(city) = row
        .municipality
        .as_deref()
        .or(cluster_row.municipality.as_deref())
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return city.to_string();
    }
    for candidate in [cluster_row.stop_name.as_str(), row.stop_name.as_str()] {
        if let Some(value) = split_city_candidate(candidate) {
            return value;
        }
    }
    cluster_row.stop_name.trim().to_string()
}

fn split_city_candidate(value: &str) -> Option<String> {
    let normalized = value.trim();
    if normalized.is_empty() {
        return None;
    }
    for delimiter in [" - ", " – ", ", "] {
        if let Some((city, _rest)) = normalized.split_once(delimiter) {
            let city = city.trim();
            if !city.is_empty() {
                return Some(city.to_string());
            }
        }
    }
    None
}

fn extract_platform_code(stop_name: &str) -> Option<String> {
    stop_name
        .rsplit_once("Bay ")
        .map(|(_, suffix)| suffix.trim())
        .filter(|suffix| !suffix.is_empty())
        .map(ToString::to_string)
}

fn yyyy_mm_dd(raw: &str) -> Option<String> {
    let normalized = raw.trim();
    if normalized.len() != 8 || !normalized.chars().all(|ch| ch.is_ascii_digit()) {
        return None;
    }
    Some(format!(
        "{}-{}-{}",
        &normalized[0..4],
        &normalized[4..6],
        &normalized[6..8]
    ))
}

fn parse_gtfs_time(raw: &str) -> Option<i32> {
    let normalized = raw.trim();
    let mut parts = normalized.split(':');
    let hours = parts.next()?.parse::<i32>().ok()?;
    let minutes = parts.next()?.parse::<i32>().ok()?;
    let seconds = parts
        .next()
        .and_then(|value| value.parse::<i32>().ok())
        .unwrap_or(0);
    if !(0..60).contains(&minutes) || !(0..60).contains(&seconds) || hours < 0 {
        return None;
    }
    Some(hours * 60 + minutes + i32::from(seconds >= 30))
}

fn format_gtfs_time(total_minutes: i32) -> String {
    let hours = total_minutes.div_euclid(60);
    let minutes = total_minutes.rem_euclid(60);
    format!("{hours:02}:{minutes:02}")
}

fn decimal_price_to_minor_units(currency: &str, raw: &str) -> Result<i64, DynError> {
    let normalized = raw.trim();
    let exponent = currency_minor_exponent(currency);
    if exponent == 0 {
        return Ok(normalized.parse::<i64>()?);
    }
    let factor = 10_i64.pow(exponent);
    let value = normalized.parse::<f64>()?;
    Ok((value * factor as f64).round() as i64)
}

fn currency_minor_exponent(currency: &str) -> u32 {
    match currency.trim().to_uppercase().as_str() {
        "BIF" | "CLP" | "DJF" | "GNF" | "JPY" | "KMF" | "KRW" | "MGA" | "PYG" | "RWF" | "UGX"
        | "VND" | "VUV" | "XAF" | "XOF" | "XPF" => 0,
        _ => 2,
    }
}

fn safe_catalog_id(prefix: &str, raw: &str) -> String {
    let trimmed = raw.trim();
    let digest = {
        let mut hasher = Sha256::new();
        hasher.update(trimmed.as_bytes());
        let digest = hasher.finalize();
        digest
            .iter()
            .take(4)
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>()
    };
    let cleaned = trimmed
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() {
                ch.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .collect::<String>();
    let compact = cleaned
        .split('_')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("_");
    let suffix = if compact.is_empty() {
        digest.clone()
    } else {
        compact.chars().take(40).collect::<String>()
    };
    format!("{prefix}_{suffix}_{digest}")
}

fn read_required_csv<T: DeserializeOwned>(
    feed_dir: &Path,
    file_name: &str,
) -> Result<Vec<T>, DynError> {
    let path = feed_dir.join(file_name);
    if !path.is_file() {
        return Err(format!("required GTFS file missing: {}", path.display()).into());
    }
    read_csv(&path)
}

fn read_optional_csv<T: DeserializeOwned>(
    feed_dir: &Path,
    file_name: &str,
) -> Result<Vec<T>, DynError> {
    let path = feed_dir.join(file_name);
    if !path.is_file() {
        return Ok(Vec::new());
    }
    read_csv(&path)
}

fn read_csv<T: DeserializeOwned>(path: &PathBuf) -> Result<Vec<T>, DynError> {
    let contents = fs::read_to_string(path)?;
    let mut reader = csv::ReaderBuilder::new()
        .trim(Trim::All)
        .flexible(true)
        .from_reader(contents.as_bytes());
    let mut rows = Vec::new();
    for row in reader.deserialize() {
        rows.push(row?);
    }
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_suffix() -> String {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time before epoch")
            .as_nanos();
        format!("{:016x}", nanos & 0xffff_ffff_ffff_ffff)
    }

    struct TempFeedDir {
        path: PathBuf,
    }

    impl TempFeedDir {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!("shamell_gtfs_{}", unique_suffix()));
            fs::create_dir_all(&path).expect("create temp gtfs dir");
            Self { path }
        }

        fn write(&self, file_name: &str, body: &str) {
            fs::write(self.path.join(file_name), body).expect("write gtfs file");
        }
    }

    impl Drop for TempFeedDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    #[test]
    fn parse_gtfs_time_supports_over_midnight_values() {
        assert_eq!(parse_gtfs_time("08:15:00"), Some(495));
        assert_eq!(parse_gtfs_time("25:10:00"), Some(1510));
        assert_eq!(format_gtfs_time(1510), "25:10");
    }

    #[test]
    fn load_gtfs_import_bundle_builds_catalog_from_minimal_feed() {
        let dir = TempFeedDir::new();
        dir.write(
            "agency.txt",
            "agency_id,agency_name,agency_timezone\nDX,Demo Express,Asia/Damascus\n",
        );
        dir.write(
            "stops.txt",
            "stop_id,stop_name,stop_lat,stop_lon,parent_station\nDAM_C, Damascus - Central,33.5,36.2,\nALE_T,Aleppo - Terminal,36.2,37.1,\n",
        );
        dir.write(
            "routes.txt",
            "route_id,agency_id,route_short_name,route_long_name,route_type\nR1,DX,DX100,Damascus to Aleppo Express,3\n",
        );
        dir.write("trips.txt", "route_id,service_id,trip_id\nR1,SVC1,TRIP1\n");
        dir.write(
            "stop_times.txt",
            "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nTRIP1,08:00:00,08:00:00,DAM_C,1\nTRIP1,12:30:00,12:30:00,ALE_T,2\n",
        );
        dir.write(
            "calendar.txt",
            "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nSVC1,1,1,1,1,1,1,1,20260401,20260430\n",
        );
        dir.write(
            "fare_attributes.txt",
            "fare_id,price,currency_type\nF1,45.90,EUR\n",
        );
        dir.write("fare_rules.txt", "fare_id,route_id\nF1,R1\n");

        let bundle =
            load_gtfs_import_bundle_from_dir(&dir.path, "EUR", 0).expect("load gtfs import bundle");

        assert_eq!(bundle.operators.len(), 1);
        assert_eq!(bundle.cities.len(), 2);
        assert_eq!(bundle.stop_clusters.len(), 2);
        assert_eq!(bundle.lines.len(), 1);
        assert_eq!(bundle.service_calendars.len(), 1);
        assert_eq!(bundle.trips.len(), 1);
        assert_eq!(bundle.fare_products.len(), 1);
        assert_eq!(bundle.trips[0].duration_minutes, 270);
        assert_eq!(bundle.fare_products[0].price_minor_units, 4590);
        assert_eq!(bundle.cities[0].display_name, "Aleppo");
        assert_eq!(bundle.cities[1].display_name, "Damascus");
    }

    #[test]
    fn derive_import_run_issues_classifies_missing_required_file() {
        let issues = derive_import_run_issues(
            "catalogimportrun_demo_missing",
            "required GTFS file missing: /srv/feeds/demo/stops.txt",
        );

        assert_eq!(issues.len(), 1);
        assert_eq!(issues[0].stage, "load_feed");
        assert_eq!(issues[0].code, "required_file_missing");
        assert_eq!(issues[0].file_name.as_deref(), Some("stops.txt"));
    }
}
