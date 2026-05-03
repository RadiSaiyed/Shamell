use crate::auth::AuthRuntime;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogOperator {
    pub operator_id: String,
    pub display_name: String,
    pub integration_mode: String,
    pub country_code: Option<String>,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogCity {
    pub city_id: String,
    pub display_name: String,
    pub country_code: String,
    pub timezone_name: String,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogCityAlias {
    pub city_alias_id: String,
    pub city_id: String,
    pub alias_name: String,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CoachCatalogStopCluster {
    pub stop_cluster_id: String,
    pub city_id: String,
    pub canonical_name: String,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogStopClusterAlias {
    pub stop_cluster_alias_id: String,
    pub stop_cluster_id: String,
    pub city_id: String,
    pub alias_name: String,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CoachCatalogStop {
    pub stop_id: String,
    pub stop_cluster_id: String,
    pub city_id: String,
    pub canonical_name: String,
    pub platform_code: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogLine {
    pub line_id: String,
    pub operator_id: String,
    pub public_code: Option<String>,
    pub marketing_name: String,
    pub vehicle_class: Option<String>,
    pub amenities: Vec<String>,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogServiceCalendar {
    pub service_calendar_id: String,
    pub start_date: String,
    pub end_date: String,
    pub monday: bool,
    pub tuesday: bool,
    pub wednesday: bool,
    pub thursday: bool,
    pub friday: bool,
    pub saturday: bool,
    pub sunday: bool,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogTrip {
    pub trip_id: String,
    pub operator_id: String,
    pub line_id: String,
    pub service_calendar_id: String,
    pub origin_stop_cluster_id: String,
    pub destination_stop_cluster_id: String,
    pub departure_time_local: String,
    pub arrival_time_local: String,
    pub duration_minutes: i32,
    pub service_timezone: String,
    pub seats_total: i32,
    pub seats_available: i32,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogFareProduct {
    pub fare_product_id: String,
    pub trip_id: String,
    pub fare_name: String,
    pub passenger_type: String,
    pub currency: String,
    pub price_minor_units: i64,
    pub hold_supported: bool,
    pub changeable: bool,
    pub refundable: bool,
    pub baggage_rule: Option<String>,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CoachCatalogCounts {
    pub operators: i64,
    pub cities: i64,
    pub stop_clusters: i64,
    pub stops: i64,
    pub lines: i64,
    pub service_calendars: i64,
    pub trips: i64,
    pub fare_products: i64,
}

impl CoachCatalogCounts {
    pub fn ready(&self) -> bool {
        self.operators > 0
            && self.cities > 0
            && self.stop_clusters > 0
            && self.stops > 0
            && self.lines > 0
            && self.service_calendars > 0
            && self.trips > 0
            && self.fare_products > 0
    }

    pub fn total_records(&self) -> i64 {
        self.operators
            + self.cities
            + self.stop_clusters
            + self.stops
            + self.lines
            + self.service_calendars
            + self.trips
            + self.fare_products
    }

    pub fn as_json(&self) -> Value {
        json!({
            "operators": self.operators,
            "cities": self.cities,
            "stop_clusters": self.stop_clusters,
            "stops": self.stops,
            "lines": self.lines,
            "service_calendars": self.service_calendars,
            "trips": self.trips,
            "fare_products": self.fare_products,
            "total_records": self.total_records(),
            "ready": self.ready(),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogDirectJourney {
    pub trip_id: String,
    pub operator_id: String,
    pub operator_name: String,
    pub operator_integration_mode: String,
    pub line_id: String,
    pub line_name: String,
    pub origin_city_name: String,
    pub destination_city_name: String,
    pub origin_stop_cluster_id: String,
    pub destination_stop_cluster_id: String,
    pub departure_time_local: String,
    pub arrival_time_local: String,
    pub duration_minutes: i32,
    pub service_timezone: String,
    pub seats_available: i32,
    pub amenities: Vec<String>,
    pub fare_product_id: String,
    pub currency: String,
    pub price_minor_units: i64,
    pub hold_supported: bool,
    pub changeable: bool,
    pub refundable: bool,
    pub baggage_rule: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogOfferBasis {
    pub fare_product_id: String,
    pub trip_id: String,
    pub operator_id: String,
    pub operator_name: String,
    pub operator_integration_mode: String,
    pub currency: String,
    pub price_minor_units: i64,
    pub hold_supported: bool,
    pub changeable: bool,
    pub refundable: bool,
    pub baggage_rule: Option<String>,
    pub seats_available: i32,
    pub amenities: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CoachStoredOfferSnapshot {
    pub offer_payload: Value,
    pub journey_payload: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CoachStoredBookingSnapshot {
    pub account_id: String,
    pub booking_payload: Value,
    pub offer_payload: Option<Value>,
    pub hold_payload: Option<Value>,
    pub journey_summary_payload: Option<Value>,
    pub passengers_manifest_payload: Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CoachOperatorFeedHealthUpsert<'a> {
    pub operator_id: &'a str,
    pub feed_kind: &'a str,
    pub source_kind: &'a str,
    pub sync_status: &'a str,
    pub freshness_status: &'a str,
    pub last_attempted_at_iso: Option<&'a str>,
    pub last_succeeded_at_iso: Option<&'a str>,
    pub freshness_expires_at_iso: Option<&'a str>,
    pub records_ingested: i64,
    pub error_message: Option<&'a str>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CoachOfferSnapshotUpsert<'a> {
    pub account_id: &'a str,
    pub offer_id: &'a str,
    pub seats_requested: i16,
    pub source_kind: &'a str,
    pub source_reference: Option<&'a str>,
    pub expires_at_iso: &'a str,
    pub offer_payload: &'a Value,
    pub journey_payload: Option<&'a Value>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CoachHoldPayloadUpsert<'a> {
    pub account_id: &'a str,
    pub hold_id: &'a str,
    pub offer_id: &'a str,
    pub seats_requested: i16,
    pub operator_reference: &'a str,
    pub status: &'a str,
    pub request_fingerprint: &'a str,
    pub hold_ttl_seconds: i32,
    pub expires_at_iso: &'a str,
    pub hold_payload: &'a Value,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CoachBookingPayloadUpsert<'a> {
    pub account_id: &'a str,
    pub booking_id: &'a str,
    pub offer_id: &'a str,
    pub hold_id: Option<&'a str>,
    pub state: &'a str,
    pub request_fingerprint: &'a str,
    pub booking_payload: &'a Value,
    pub offer_payload: Option<&'a Value>,
    pub hold_payload: Option<&'a Value>,
    pub journey_summary_payload: Option<&'a Value>,
    pub passengers_manifest_payload: Option<&'a Value>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogJourneySummaryBasis {
    pub trip_id: String,
    pub operator_name: String,
    pub origin_city_name: String,
    pub destination_city_name: String,
    pub departure_time_local: String,
    pub arrival_time_local: String,
    pub duration_minutes: i32,
    pub service_timezone: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogOperatorFeedHealth {
    pub operator_id: String,
    pub operator_name: String,
    pub operator_integration_mode: String,
    pub feed_kind: String,
    pub source_kind: String,
    pub sync_status: String,
    pub freshness_status: String,
    pub last_attempted_at_iso: Option<String>,
    pub last_succeeded_at_iso: Option<String>,
    pub freshness_expires_at_iso: Option<String>,
    pub records_ingested: i64,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogSourceArtifact {
    pub artifact_id: String,
    pub feed_kind: String,
    pub source_kind: String,
    pub source_label: String,
    pub file_name: String,
    pub file_checksum_sha256: String,
    pub content_length_bytes: i64,
    pub extracted_file_count: i64,
    pub feed_locator: String,
    pub operator_ids: Vec<String>,
    pub created_by_account_id: String,
    pub created_at_iso: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogImportRun {
    pub import_run_id: String,
    pub feed_kind: String,
    pub source_kind: String,
    pub trigger_kind: String,
    pub feed_locator: Option<String>,
    pub operator_ids: Vec<String>,
    pub replayed_from_import_run_id: Option<String>,
    pub source_artifact_id: Option<String>,
    pub source_artifact: Option<CoachCatalogSourceArtifact>,
    pub status: String,
    pub started_at_iso: String,
    pub finished_at_iso: Option<String>,
    pub counts: CoachCatalogCounts,
    pub error_message: Option<String>,
    pub issues: Vec<CoachCatalogImportRunIssue>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogImportRunIssue {
    pub issue_id: String,
    pub import_run_id: String,
    pub severity: String,
    pub stage: String,
    pub code: String,
    pub message: String,
    pub file_name: Option<String>,
    pub row_reference: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoachCatalogImportConfig {
    pub feed_kind: String,
    pub source_kind: String,
    pub feed_locator: String,
    pub source_artifact_id: Option<String>,
    pub source_artifact: Option<CoachCatalogSourceArtifact>,
    pub updated_by_account_id: String,
    pub updated_at_iso: String,
}

#[derive(Clone, Debug)]
pub struct CoachCatalogImportRunSavedView {
    pub view_id: String,
    pub account_id: String,
    pub visibility_scope: String,
    pub name: String,
    pub operator_ids: Vec<String>,
    pub status_filter: String,
    pub replay_scope_filter: String,
    pub issue_severity_filter: String,
    pub issue_stage_filter: String,
    pub is_default: bool,
    pub created_at_iso: String,
    pub updated_at_iso: String,
}

#[derive(Clone, Debug)]
pub struct CoachCatalogImportRunIssueSavedView {
    pub view_id: String,
    pub account_id: String,
    pub visibility_scope: String,
    pub name: String,
    pub operator_ids: Vec<String>,
    pub severity_filter: String,
    pub stage_filter: String,
    pub is_default: bool,
    pub created_at_iso: String,
    pub updated_at_iso: String,
}

#[derive(Clone, Debug)]
pub struct CoachPayoutImportBatchSavedView {
    pub view_id: String,
    pub account_id: String,
    pub visibility_scope: String,
    pub name: String,
    pub operator_id: String,
    pub is_default: bool,
    pub created_at_iso: String,
    pub updated_at_iso: String,
}

#[derive(Clone, Debug)]
pub struct CoachPayoutImportPreviewSavedView {
    pub view_id: String,
    pub account_id: String,
    pub visibility_scope: String,
    pub name: String,
    pub status_filter: String,
    pub from_created_at_iso: Option<String>,
    pub to_created_at_iso: Option<String>,
    pub operator_id: String,
    pub is_default: bool,
    pub created_at_iso: String,
    pub updated_at_iso: String,
}

#[derive(Clone, Debug)]
pub struct CoachCatalogRepository {
    pool: PgPool,
}

const PILOT_SERVICE_CALENDAR_ID: &str = "cal_pilot_daily_2026_2027";

fn coach_catalog_normalize_string_list(values: &[String]) -> Vec<String> {
    let mut ordered = std::collections::BTreeSet::new();
    for value in values {
        let normalized = value.trim();
        if normalized.is_empty() {
            continue;
        }
        ordered.insert(normalized.to_string());
    }
    ordered.into_iter().collect()
}

fn coach_catalog_string_array_from_json(value: Value) -> Result<Vec<String>, sqlx::Error> {
    let values = value
        .as_array()
        .ok_or_else(|| {
            sqlx::Error::Decode(Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "expected json array",
            )))
        })?
        .iter()
        .filter_map(|entry| entry.as_str())
        .map(|entry| entry.trim().to_string())
        .filter(|entry| !entry.is_empty())
        .collect::<Vec<_>>();
    Ok(coach_catalog_normalize_string_list(&values))
}

fn coach_catalog_json_value_from_text(value: &str) -> Result<Value, sqlx::Error> {
    serde_json::from_str(value.trim()).map_err(|error| {
        sqlx::Error::Decode(Box::new(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("invalid json payload: {error}"),
        )))
    })
}

fn coach_catalog_optional_json_value_from_text(
    value: Option<String>,
) -> Result<Option<Value>, sqlx::Error> {
    value
        .as_deref()
        .map(coach_catalog_json_value_from_text)
        .transpose()
}

fn coach_catalog_saved_view_matches_operator_scope(
    operator_ids: &[String],
    operator_id: Option<&str>,
) -> bool {
    let Some(operator_id) = operator_id.map(str::trim).filter(|value| !value.is_empty()) else {
        return true;
    };
    operator_ids.is_empty() || operator_ids.iter().any(|value| value == operator_id)
}

impl CoachCatalogRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn counts_best_effort(&self) -> Result<CoachCatalogCounts, sqlx::Error> {
        if !self.catalog_schema_present().await? {
            return Ok(CoachCatalogCounts::default());
        }

        Ok(CoachCatalogCounts {
            operators: self.count_rows("auth_coach_catalog_operators").await?,
            cities: self.count_rows("auth_coach_catalog_cities").await?,
            stop_clusters: self.count_rows("auth_coach_catalog_stop_clusters").await?,
            stops: self.count_rows("auth_coach_catalog_stops").await?,
            lines: self.count_rows("auth_coach_catalog_lines").await?,
            service_calendars: self
                .count_rows("auth_coach_catalog_service_calendars")
                .await?,
            trips: self.count_rows("auth_coach_catalog_trips").await?,
            fare_products: self.count_rows("auth_coach_catalog_fare_products").await?,
        })
    }

    pub async fn upsert_operator(&self, value: &CoachCatalogOperator) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_operators \
             (operator_id, display_name, integration_mode, country_code, active) \
             VALUES ($1, $2, $3, $4, $5) \
             ON CONFLICT (operator_id) DO UPDATE SET \
               display_name=EXCLUDED.display_name, \
               integration_mode=EXCLUDED.integration_mode, \
               country_code=EXCLUDED.country_code, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.operator_id.trim())
        .bind(value.display_name.trim())
        .bind(value.integration_mode.trim())
        .bind(value.country_code.as_deref().map(str::trim))
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_city(&self, value: &CoachCatalogCity) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_cities \
             (city_id, display_name, country_code, timezone_name, active) \
             VALUES ($1, $2, $3, $4, $5) \
             ON CONFLICT (city_id) DO UPDATE SET \
               display_name=EXCLUDED.display_name, \
               country_code=EXCLUDED.country_code, \
               timezone_name=EXCLUDED.timezone_name, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.city_id.trim())
        .bind(value.display_name.trim())
        .bind(value.country_code.trim())
        .bind(value.timezone_name.trim())
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_city_alias(
        &self,
        value: &CoachCatalogCityAlias,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_city_aliases \
             (city_alias_id, city_id, alias_name, active) \
             VALUES ($1, $2, $3, $4) \
             ON CONFLICT (city_alias_id) DO UPDATE SET \
               city_id=EXCLUDED.city_id, \
               alias_name=EXCLUDED.alias_name, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.city_alias_id.trim())
        .bind(value.city_id.trim())
        .bind(value.alias_name.trim())
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_stop_cluster(
        &self,
        value: &CoachCatalogStopCluster,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_stop_clusters \
             (stop_cluster_id, city_id, canonical_name, lat, lon, active) \
             VALUES ($1, $2, $3, $4, $5, $6) \
             ON CONFLICT (stop_cluster_id) DO UPDATE SET \
               city_id=EXCLUDED.city_id, \
               canonical_name=EXCLUDED.canonical_name, \
               lat=EXCLUDED.lat, \
               lon=EXCLUDED.lon, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.stop_cluster_id.trim())
        .bind(value.city_id.trim())
        .bind(value.canonical_name.trim())
        .bind(value.lat)
        .bind(value.lon)
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_stop_cluster_alias(
        &self,
        value: &CoachCatalogStopClusterAlias,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_stop_cluster_aliases \
             (stop_cluster_alias_id, stop_cluster_id, city_id, alias_name, active) \
             VALUES ($1, $2, $3, $4, $5) \
             ON CONFLICT (stop_cluster_alias_id) DO UPDATE SET \
               stop_cluster_id=EXCLUDED.stop_cluster_id, \
               city_id=EXCLUDED.city_id, \
               alias_name=EXCLUDED.alias_name, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.stop_cluster_alias_id.trim())
        .bind(value.stop_cluster_id.trim())
        .bind(value.city_id.trim())
        .bind(value.alias_name.trim())
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_stop(&self, value: &CoachCatalogStop) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_stops \
             (stop_id, stop_cluster_id, city_id, canonical_name, platform_code, lat, lon, active) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8) \
             ON CONFLICT (stop_id) DO UPDATE SET \
               stop_cluster_id=EXCLUDED.stop_cluster_id, \
               city_id=EXCLUDED.city_id, \
               canonical_name=EXCLUDED.canonical_name, \
               platform_code=EXCLUDED.platform_code, \
               lat=EXCLUDED.lat, \
               lon=EXCLUDED.lon, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.stop_id.trim())
        .bind(value.stop_cluster_id.trim())
        .bind(value.city_id.trim())
        .bind(value.canonical_name.trim())
        .bind(value.platform_code.as_deref().map(str::trim))
        .bind(value.lat)
        .bind(value.lon)
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_line(&self, value: &CoachCatalogLine) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_lines \
             (line_id, operator_id, public_code, marketing_name, vehicle_class, amenities_json, active) \
             VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7) \
             ON CONFLICT (line_id) DO UPDATE SET \
               operator_id=EXCLUDED.operator_id, \
               public_code=EXCLUDED.public_code, \
               marketing_name=EXCLUDED.marketing_name, \
               vehicle_class=EXCLUDED.vehicle_class, \
               amenities_json=EXCLUDED.amenities_json, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.line_id.trim())
        .bind(value.operator_id.trim())
        .bind(value.public_code.as_deref().map(str::trim))
        .bind(value.marketing_name.trim())
        .bind(value.vehicle_class.as_deref().map(str::trim))
        .bind(json!(value.amenities))
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_service_calendar(
        &self,
        value: &CoachCatalogServiceCalendar,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_service_calendars \
             (service_calendar_id, start_date, end_date, monday, tuesday, wednesday, thursday, friday, saturday, sunday, active) \
             VALUES ($1, $2::date, $3::date, $4, $5, $6, $7, $8, $9, $10, $11) \
             ON CONFLICT (service_calendar_id) DO UPDATE SET \
               start_date=EXCLUDED.start_date, \
               end_date=EXCLUDED.end_date, \
               monday=EXCLUDED.monday, \
               tuesday=EXCLUDED.tuesday, \
               wednesday=EXCLUDED.wednesday, \
               thursday=EXCLUDED.thursday, \
               friday=EXCLUDED.friday, \
               saturday=EXCLUDED.saturday, \
               sunday=EXCLUDED.sunday, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.service_calendar_id.trim())
        .bind(value.start_date.trim())
        .bind(value.end_date.trim())
        .bind(value.monday)
        .bind(value.tuesday)
        .bind(value.wednesday)
        .bind(value.thursday)
        .bind(value.friday)
        .bind(value.saturday)
        .bind(value.sunday)
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_trip(&self, value: &CoachCatalogTrip) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_trips \
             (trip_id, operator_id, line_id, service_calendar_id, origin_stop_cluster_id, destination_stop_cluster_id, \
              departure_time_local, arrival_time_local, duration_minutes, service_timezone, seats_total, seats_available, active) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) \
             ON CONFLICT (trip_id) DO UPDATE SET \
               operator_id=EXCLUDED.operator_id, \
               line_id=EXCLUDED.line_id, \
               service_calendar_id=EXCLUDED.service_calendar_id, \
               origin_stop_cluster_id=EXCLUDED.origin_stop_cluster_id, \
               destination_stop_cluster_id=EXCLUDED.destination_stop_cluster_id, \
               departure_time_local=EXCLUDED.departure_time_local, \
               arrival_time_local=EXCLUDED.arrival_time_local, \
               duration_minutes=EXCLUDED.duration_minutes, \
               service_timezone=EXCLUDED.service_timezone, \
               seats_total=EXCLUDED.seats_total, \
               seats_available=EXCLUDED.seats_available, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.trip_id.trim())
        .bind(value.operator_id.trim())
        .bind(value.line_id.trim())
        .bind(value.service_calendar_id.trim())
        .bind(value.origin_stop_cluster_id.trim())
        .bind(value.destination_stop_cluster_id.trim())
        .bind(value.departure_time_local.trim())
        .bind(value.arrival_time_local.trim())
        .bind(value.duration_minutes)
        .bind(value.service_timezone.trim())
        .bind(value.seats_total)
        .bind(value.seats_available)
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_fare_product(
        &self,
        value: &CoachCatalogFareProduct,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_fare_products \
             (fare_product_id, trip_id, fare_name, passenger_type, currency, price_minor_units, \
              hold_supported, changeable, refundable, baggage_rule, active) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) \
             ON CONFLICT (fare_product_id) DO UPDATE SET \
               trip_id=EXCLUDED.trip_id, \
               fare_name=EXCLUDED.fare_name, \
               passenger_type=EXCLUDED.passenger_type, \
               currency=EXCLUDED.currency, \
               price_minor_units=EXCLUDED.price_minor_units, \
               hold_supported=EXCLUDED.hold_supported, \
               changeable=EXCLUDED.changeable, \
               refundable=EXCLUDED.refundable, \
               baggage_rule=EXCLUDED.baggage_rule, \
               active=EXCLUDED.active, \
               updated_at=NOW()",
        )
        .bind(value.fare_product_id.trim())
        .bind(value.trip_id.trim())
        .bind(value.fare_name.trim())
        .bind(value.passenger_type.trim())
        .bind(value.currency.trim())
        .bind(value.price_minor_units)
        .bind(value.hold_supported)
        .bind(value.changeable)
        .bind(value.refundable)
        .bind(value.baggage_rule.as_deref().map(str::trim))
        .bind(value.active)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn upsert_operator_feed_health(
        &self,
        value: &CoachOperatorFeedHealthUpsert<'_>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO auth_coach_catalog_operator_feed_health \
             (operator_id, feed_kind, source_kind, sync_status, freshness_status, \
              last_attempted_at, last_succeeded_at, freshness_expires_at, records_ingested, error_message) \
             VALUES ($1, $2, $3, $4, $5, $6::timestamptz, $7::timestamptz, $8::timestamptz, $9, $10) \
             ON CONFLICT (operator_id, feed_kind) DO UPDATE SET \
               source_kind=EXCLUDED.source_kind, \
               sync_status=EXCLUDED.sync_status, \
               freshness_status=EXCLUDED.freshness_status, \
               last_attempted_at=EXCLUDED.last_attempted_at, \
               last_succeeded_at=EXCLUDED.last_succeeded_at, \
               freshness_expires_at=EXCLUDED.freshness_expires_at, \
               records_ingested=EXCLUDED.records_ingested, \
               error_message=EXCLUDED.error_message, \
               updated_at=NOW()",
        )
        .bind(value.operator_id.trim())
        .bind(value.feed_kind.trim())
        .bind(value.source_kind.trim())
        .bind(value.sync_status.trim())
        .bind(value.freshness_status.trim())
        .bind(value.last_attempted_at_iso.map(str::trim))
        .bind(value.last_succeeded_at_iso.map(str::trim))
        .bind(value.freshness_expires_at_iso.map(str::trim))
        .bind(value.records_ingested)
        .bind(value.error_message.map(str::trim))
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_direct_journeys_by_city_names(
        &self,
        from_city_name: &str,
        to_city_name: &str,
        departure_date: &str,
        min_seats: i32,
    ) -> Result<Vec<CoachCatalogDirectJourney>, sqlx::Error> {
        if !self.catalog_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT \
                trip.trip_id, trip.operator_id, operator.display_name AS operator_name, operator.integration_mode, \
                trip.line_id, line.marketing_name AS line_name, \
                origin_city.display_name AS origin_city_name, destination_city.display_name AS destination_city_name, \
                trip.origin_stop_cluster_id, trip.destination_stop_cluster_id, \
                trip.departure_time_local, trip.arrival_time_local, trip.duration_minutes, trip.service_timezone, \
                trip.seats_available, line.amenities_json, \
                fare.fare_product_id, fare.currency, fare.price_minor_units, fare.hold_supported, \
                fare.changeable, fare.refundable, fare.baggage_rule \
             FROM auth_coach_catalog_trips trip \
             JOIN auth_coach_catalog_operators operator \
               ON operator.operator_id = trip.operator_id AND operator.active = TRUE \
             JOIN auth_coach_catalog_lines line \
               ON line.line_id = trip.line_id AND line.active = TRUE \
             JOIN auth_coach_catalog_service_calendars cal \
               ON cal.service_calendar_id = trip.service_calendar_id AND cal.active = TRUE \
             JOIN auth_coach_catalog_stop_clusters origin_cluster \
               ON origin_cluster.stop_cluster_id = trip.origin_stop_cluster_id AND origin_cluster.active = TRUE \
             JOIN auth_coach_catalog_stop_clusters destination_cluster \
               ON destination_cluster.stop_cluster_id = trip.destination_stop_cluster_id AND destination_cluster.active = TRUE \
             JOIN auth_coach_catalog_cities origin_city \
               ON origin_city.city_id = origin_cluster.city_id AND origin_city.active = TRUE \
             JOIN auth_coach_catalog_cities destination_city \
               ON destination_city.city_id = destination_cluster.city_id AND destination_city.active = TRUE \
             JOIN LATERAL ( \
                SELECT fare_product_id, currency, price_minor_units, hold_supported, changeable, refundable, baggage_rule \
                FROM auth_coach_catalog_fare_products fare \
                WHERE fare.trip_id = trip.trip_id AND fare.active = TRUE \
                ORDER BY fare.price_minor_units ASC, fare.fare_product_id ASC \
                LIMIT 1 \
             ) fare ON TRUE \
             WHERE trip.active = TRUE \
               AND trip.seats_available >= $4 \
               AND ( \
                    LOWER(origin_city.display_name) = LOWER($1) \
                    OR LOWER(origin_cluster.canonical_name) = LOWER($1) \
                    OR EXISTS ( \
                        SELECT 1 \
                        FROM auth_coach_catalog_city_aliases origin_alias \
                        WHERE origin_alias.city_id = origin_city.city_id \
                          AND origin_alias.active = TRUE \
                          AND LOWER(origin_alias.alias_name) = LOWER($1) \
                    ) \
                    OR EXISTS ( \
                        SELECT 1 \
                        FROM auth_coach_catalog_stop_cluster_aliases origin_cluster_alias \
                        WHERE origin_cluster_alias.stop_cluster_id = origin_cluster.stop_cluster_id \
                          AND origin_cluster_alias.active = TRUE \
                          AND LOWER(origin_cluster_alias.alias_name) = LOWER($1) \
                    ) \
               ) \
               AND ( \
                    LOWER(destination_city.display_name) = LOWER($2) \
                    OR LOWER(destination_cluster.canonical_name) = LOWER($2) \
                    OR EXISTS ( \
                        SELECT 1 \
                        FROM auth_coach_catalog_city_aliases destination_alias \
                        WHERE destination_alias.city_id = destination_city.city_id \
                          AND destination_alias.active = TRUE \
                          AND LOWER(destination_alias.alias_name) = LOWER($2) \
                    ) \
                    OR EXISTS ( \
                        SELECT 1 \
                        FROM auth_coach_catalog_stop_cluster_aliases destination_cluster_alias \
                        WHERE destination_cluster_alias.stop_cluster_id = destination_cluster.stop_cluster_id \
                          AND destination_cluster_alias.active = TRUE \
                          AND LOWER(destination_cluster_alias.alias_name) = LOWER($2) \
                    ) \
               ) \
               AND $3::date BETWEEN cal.start_date AND cal.end_date \
               AND CASE EXTRACT(ISODOW FROM $3::date)::int \
                   WHEN 1 THEN cal.monday \
                   WHEN 2 THEN cal.tuesday \
                   WHEN 3 THEN cal.wednesday \
                   WHEN 4 THEN cal.thursday \
                   WHEN 5 THEN cal.friday \
                   WHEN 6 THEN cal.saturday \
                   WHEN 7 THEN cal.sunday \
                   ELSE FALSE \
               END \
             ORDER BY fare.price_minor_units ASC, trip.departure_time_local ASC, trip.trip_id ASC",
        )
        .bind(from_city_name.trim())
        .bind(to_city_name.trim())
        .bind(departure_date.trim())
        .bind(min_seats)
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter().map(Self::map_direct_journey_row).collect()
    }

    pub async fn find_offer_basis_by_fare_product_id(
        &self,
        fare_product_id: &str,
    ) -> Result<Option<CoachCatalogOfferBasis>, sqlx::Error> {
        if !self.catalog_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT \
                fare.fare_product_id, trip.trip_id, trip.operator_id, operator.display_name AS operator_name, \
                operator.integration_mode, fare.currency, fare.price_minor_units, fare.hold_supported, \
                fare.changeable, fare.refundable, fare.baggage_rule, trip.seats_available, line.amenities_json \
             FROM auth_coach_catalog_fare_products fare \
             JOIN auth_coach_catalog_trips trip \
               ON trip.trip_id = fare.trip_id AND trip.active = TRUE \
             JOIN auth_coach_catalog_operators operator \
               ON operator.operator_id = trip.operator_id AND operator.active = TRUE \
             JOIN auth_coach_catalog_lines line \
               ON line.line_id = trip.line_id AND line.active = TRUE \
             WHERE fare.fare_product_id = $1 AND fare.active = TRUE \
             LIMIT 1",
        )
        .bind(fare_product_id.trim())
        .fetch_optional(&self.pool)
        .await?;

        row.map(Self::map_offer_basis_row).transpose()
    }

    pub async fn find_journey_summary_basis_by_fare_product_id(
        &self,
        fare_product_id: &str,
    ) -> Result<Option<CoachCatalogJourneySummaryBasis>, sqlx::Error> {
        if !self.catalog_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT \
                trip.trip_id, operator.display_name AS operator_name, \
                origin_city.display_name AS origin_city_name, \
                destination_city.display_name AS destination_city_name, \
                trip.departure_time_local, trip.arrival_time_local, \
                trip.duration_minutes, trip.service_timezone \
             FROM auth_coach_catalog_fare_products fare \
             JOIN auth_coach_catalog_trips trip \
               ON trip.trip_id = fare.trip_id AND trip.active = TRUE \
             JOIN auth_coach_catalog_operators operator \
               ON operator.operator_id = trip.operator_id AND operator.active = TRUE \
             JOIN auth_coach_catalog_stop_clusters origin_cluster \
               ON origin_cluster.stop_cluster_id = trip.origin_stop_cluster_id AND origin_cluster.active = TRUE \
             JOIN auth_coach_catalog_cities origin_city \
               ON origin_city.city_id = origin_cluster.city_id AND origin_city.active = TRUE \
             JOIN auth_coach_catalog_stop_clusters destination_cluster \
               ON destination_cluster.stop_cluster_id = trip.destination_stop_cluster_id AND destination_cluster.active = TRUE \
             JOIN auth_coach_catalog_cities destination_city \
               ON destination_city.city_id = destination_cluster.city_id AND destination_city.active = TRUE \
             WHERE fare.fare_product_id = $1 AND fare.active = TRUE \
             LIMIT 1",
        )
        .bind(fare_product_id.trim())
        .fetch_optional(&self.pool)
        .await?;

        row.map(Self::map_journey_summary_basis_row).transpose()
    }

    pub async fn upsert_offer_snapshot(
        &self,
        value: &CoachOfferSnapshotUpsert<'_>,
    ) -> Result<(), sqlx::Error> {
        if !self.offer_snapshot_schema_present().await? {
            return Ok(());
        }

        sqlx::query(
            "INSERT INTO auth_coach_offer_snapshots \
             (account_id, offer_id, seats_requested, source_kind, source_reference, expires_at, offer_payload, journey_payload) \
             VALUES ($1, $2, $3, $4, $5, $6::timestamptz, $7::jsonb, $8::jsonb) \
             ON CONFLICT (account_id, offer_id, seats_requested) DO UPDATE SET \
               source_kind=EXCLUDED.source_kind, \
               source_reference=EXCLUDED.source_reference, \
               expires_at=EXCLUDED.expires_at, \
               offer_payload=EXCLUDED.offer_payload, \
               journey_payload=COALESCE(EXCLUDED.journey_payload, auth_coach_offer_snapshots.journey_payload), \
               updated_at=NOW()",
        )
        .bind(value.account_id.trim().to_ascii_lowercase())
        .bind(value.offer_id.trim())
        .bind(value.seats_requested)
        .bind(value.source_kind.trim())
        .bind(value.source_reference.map(str::trim))
        .bind(value.expires_at_iso.trim())
        .bind(value.offer_payload.to_string())
        .bind(value.journey_payload.map(Value::to_string))
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_offer_snapshot(
        &self,
        account_id: &str,
        offer_id: &str,
        seats_requested: i16,
    ) -> Result<Option<CoachStoredOfferSnapshot>, sqlx::Error> {
        if !self.offer_snapshot_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT \
                offer_payload::text AS offer_payload_text, \
                journey_payload::text AS journey_payload_text \
             FROM auth_coach_offer_snapshots \
             WHERE account_id=$1 AND offer_id=$2 AND seats_requested=$3 AND expires_at > NOW() \
             LIMIT 1",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(offer_id.trim())
        .bind(seats_requested)
        .fetch_optional(&self.pool)
        .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        let offer_payload_text: String = row.try_get("offer_payload_text")?;
        let journey_payload_text: Option<String> = row.try_get("journey_payload_text")?;
        Ok(Some(CoachStoredOfferSnapshot {
            offer_payload: coach_catalog_json_value_from_text(&offer_payload_text)?,
            journey_payload: coach_catalog_optional_json_value_from_text(journey_payload_text)?,
        }))
    }

    pub async fn find_offer_snapshot_payload(
        &self,
        account_id: &str,
        offer_id: &str,
        seats_requested: i16,
    ) -> Result<Option<Value>, sqlx::Error> {
        Ok(self
            .find_offer_snapshot(account_id, offer_id, seats_requested)
            .await?
            .map(|snapshot| snapshot.offer_payload))
    }

    pub async fn upsert_hold_payload(
        &self,
        value: &CoachHoldPayloadUpsert<'_>,
    ) -> Result<(), sqlx::Error> {
        if !self.hold_schema_present().await? {
            return Ok(());
        }

        sqlx::query(
            "INSERT INTO auth_coach_holds \
             (hold_id, account_id, offer_id, seats_requested, operator_reference, status, request_fingerprint, hold_ttl_seconds, expires_at, hold_payload) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::timestamptz, $10::jsonb) \
             ON CONFLICT (hold_id) DO UPDATE SET \
               account_id=EXCLUDED.account_id, \
               offer_id=EXCLUDED.offer_id, \
               seats_requested=EXCLUDED.seats_requested, \
               operator_reference=EXCLUDED.operator_reference, \
               status=EXCLUDED.status, \
               request_fingerprint=EXCLUDED.request_fingerprint, \
               hold_ttl_seconds=EXCLUDED.hold_ttl_seconds, \
               expires_at=EXCLUDED.expires_at, \
               hold_payload=EXCLUDED.hold_payload, \
               updated_at=NOW()",
        )
        .bind(value.hold_id.trim())
        .bind(value.account_id.trim().to_ascii_lowercase())
        .bind(value.offer_id.trim())
        .bind(value.seats_requested)
        .bind(value.operator_reference.trim())
        .bind(value.status.trim())
        .bind(value.request_fingerprint.trim())
        .bind(value.hold_ttl_seconds)
        .bind(value.expires_at_iso.trim())
        .bind(value.hold_payload.to_string())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_hold_payload(
        &self,
        account_id: &str,
        hold_id: &str,
    ) -> Result<Option<Value>, sqlx::Error> {
        if !self.hold_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT hold_payload::text AS hold_payload_text \
             FROM auth_coach_holds \
             WHERE account_id=$1 AND hold_id=$2 \
             LIMIT 1",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(hold_id.trim())
        .fetch_optional(&self.pool)
        .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        let payload_text: String = row.try_get("hold_payload_text")?;
        Ok(Some(coach_catalog_json_value_from_text(&payload_text)?))
    }

    pub async fn update_hold_payload_status(
        &self,
        account_id: &str,
        hold_id: &str,
        status: &str,
        hold_payload: &Value,
    ) -> Result<bool, sqlx::Error> {
        if !self.hold_schema_present().await? {
            return Ok(false);
        }

        let result = sqlx::query(
            "UPDATE auth_coach_holds \
             SET status=$3, \
                 hold_payload=$4::jsonb, \
                 updated_at=NOW(), \
                 converted_at=CASE WHEN $3 = 'converted' THEN NOW() ELSE converted_at END, \
                 released_at=CASE WHEN $3 = 'released' THEN NOW() ELSE released_at END, \
                 expired_at=CASE WHEN $3 = 'expired' THEN NOW() ELSE expired_at END \
             WHERE account_id=$1 AND hold_id=$2",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(hold_id.trim())
        .bind(status.trim())
        .bind(hold_payload.to_string())
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn upsert_booking_payload(
        &self,
        value: &CoachBookingPayloadUpsert<'_>,
    ) -> Result<(), sqlx::Error> {
        if !self.booking_schema_present().await? {
            return Ok(());
        }

        sqlx::query(
            "INSERT INTO auth_coach_bookings \
             (booking_id, account_id, offer_id, hold_id, state, request_fingerprint, booking_payload, offer_payload, hold_payload, journey_summary_payload, passengers_manifest_payload) \
             VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9::jsonb, $10::jsonb, $11::jsonb) \
             ON CONFLICT (booking_id) DO UPDATE SET \
               account_id=EXCLUDED.account_id, \
               offer_id=EXCLUDED.offer_id, \
               hold_id=EXCLUDED.hold_id, \
               state=EXCLUDED.state, \
               request_fingerprint=EXCLUDED.request_fingerprint, \
               booking_payload=EXCLUDED.booking_payload, \
               offer_payload=COALESCE(EXCLUDED.offer_payload, auth_coach_bookings.offer_payload), \
               hold_payload=COALESCE(EXCLUDED.hold_payload, auth_coach_bookings.hold_payload), \
               journey_summary_payload=COALESCE(EXCLUDED.journey_summary_payload, auth_coach_bookings.journey_summary_payload), \
               passengers_manifest_payload=COALESCE(EXCLUDED.passengers_manifest_payload, auth_coach_bookings.passengers_manifest_payload), \
               updated_at=NOW(), \
               ticketed_at=CASE WHEN EXCLUDED.state = 'ticketed' THEN NOW() ELSE auth_coach_bookings.ticketed_at END, \
               cancelled_at=CASE WHEN EXCLUDED.state = 'cancelled' THEN NOW() ELSE auth_coach_bookings.cancelled_at END, \
               refunded_at=CASE WHEN EXCLUDED.state = 'refunded' THEN NOW() ELSE auth_coach_bookings.refunded_at END",
        )
        .bind(value.booking_id.trim())
        .bind(value.account_id.trim().to_ascii_lowercase())
        .bind(value.offer_id.trim())
        .bind(value.hold_id.map(str::trim))
        .bind(value.state.trim())
        .bind(value.request_fingerprint.trim())
        .bind(value.booking_payload.to_string())
        .bind(value.offer_payload.map(Value::to_string))
        .bind(value.hold_payload.map(Value::to_string))
        .bind(value.journey_summary_payload.map(Value::to_string))
        .bind(value.passengers_manifest_payload.map(Value::to_string))
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_booking_payload(
        &self,
        account_id: &str,
        booking_id: &str,
    ) -> Result<Option<Value>, sqlx::Error> {
        if !self.booking_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT booking_payload::text AS booking_payload_text \
             FROM auth_coach_bookings \
             WHERE account_id=$1 AND booking_id=$2 \
             LIMIT 1",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(booking_id.trim())
        .fetch_optional(&self.pool)
        .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        let payload_text: String = row.try_get("booking_payload_text")?;
        Ok(Some(coach_catalog_json_value_from_text(&payload_text)?))
    }

    pub async fn find_booking_snapshot(
        &self,
        account_id: &str,
        booking_id: &str,
    ) -> Result<Option<CoachStoredBookingSnapshot>, sqlx::Error> {
        if !self.booking_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT \
                account_id, \
                booking_payload::text AS booking_payload_text, \
                offer_payload::text AS offer_payload_text, \
                hold_payload::text AS hold_payload_text, \
                journey_summary_payload::text AS journey_summary_payload_text, \
                COALESCE(passengers_manifest_payload, '[]'::jsonb)::text AS passengers_manifest_payload_text \
             FROM auth_coach_bookings \
             WHERE account_id=$1 AND booking_id=$2 \
             LIMIT 1",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(booking_id.trim())
        .fetch_optional(&self.pool)
        .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(CoachStoredBookingSnapshot {
            account_id: row.try_get::<String, _>("account_id")?,
            booking_payload: coach_catalog_json_value_from_text(
                &row.try_get::<String, _>("booking_payload_text")?,
            )?,
            offer_payload: coach_catalog_optional_json_value_from_text(
                row.try_get("offer_payload_text")?,
            )?,
            hold_payload: coach_catalog_optional_json_value_from_text(
                row.try_get("hold_payload_text")?,
            )?,
            journey_summary_payload: coach_catalog_optional_json_value_from_text(
                row.try_get("journey_summary_payload_text")?,
            )?,
            passengers_manifest_payload: coach_catalog_json_value_from_text(
                &row.try_get::<String, _>("passengers_manifest_payload_text")?,
            )?,
        }))
    }

    pub async fn list_booking_snapshots(
        &self,
        account_id: &str,
    ) -> Result<Vec<CoachStoredBookingSnapshot>, sqlx::Error> {
        if !self.booking_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT \
                account_id, \
                booking_payload::text AS booking_payload_text, \
                offer_payload::text AS offer_payload_text, \
                hold_payload::text AS hold_payload_text, \
                journey_summary_payload::text AS journey_summary_payload_text, \
                COALESCE(passengers_manifest_payload, '[]'::jsonb)::text AS passengers_manifest_payload_text \
             FROM auth_coach_bookings \
             WHERE account_id=$1 \
             ORDER BY created_at DESC, booking_id DESC",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|row| {
                Ok(CoachStoredBookingSnapshot {
                    account_id: row.try_get::<String, _>("account_id")?,
                    booking_payload: coach_catalog_json_value_from_text(
                        &row.try_get::<String, _>("booking_payload_text")?,
                    )?,
                    offer_payload: coach_catalog_optional_json_value_from_text(
                        row.try_get("offer_payload_text")?,
                    )?,
                    hold_payload: coach_catalog_optional_json_value_from_text(
                        row.try_get("hold_payload_text")?,
                    )?,
                    journey_summary_payload: coach_catalog_optional_json_value_from_text(
                        row.try_get("journey_summary_payload_text")?,
                    )?,
                    passengers_manifest_payload: coach_catalog_json_value_from_text(
                        &row.try_get::<String, _>("passengers_manifest_payload_text")?,
                    )?,
                })
            })
            .collect()
    }

    pub async fn list_booking_snapshots_global(
        &self,
    ) -> Result<Vec<CoachStoredBookingSnapshot>, sqlx::Error> {
        if !self.booking_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT \
                account_id, \
                booking_payload::text AS booking_payload_text, \
                offer_payload::text AS offer_payload_text, \
                hold_payload::text AS hold_payload_text, \
                journey_summary_payload::text AS journey_summary_payload_text, \
                COALESCE(passengers_manifest_payload, '[]'::jsonb)::text AS passengers_manifest_payload_text \
             FROM auth_coach_bookings \
             ORDER BY created_at DESC, booking_id DESC",
        )
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|row| {
                Ok(CoachStoredBookingSnapshot {
                    account_id: row.try_get::<String, _>("account_id")?,
                    booking_payload: coach_catalog_json_value_from_text(
                        &row.try_get::<String, _>("booking_payload_text")?,
                    )?,
                    offer_payload: coach_catalog_optional_json_value_from_text(
                        row.try_get("offer_payload_text")?,
                    )?,
                    hold_payload: coach_catalog_optional_json_value_from_text(
                        row.try_get("hold_payload_text")?,
                    )?,
                    journey_summary_payload: coach_catalog_optional_json_value_from_text(
                        row.try_get("journey_summary_payload_text")?,
                    )?,
                    passengers_manifest_payload: coach_catalog_json_value_from_text(
                        &row.try_get::<String, _>("passengers_manifest_payload_text")?,
                    )?,
                })
            })
            .collect()
    }

    pub async fn replace_booking_tickets(
        &self,
        account_id: &str,
        booking_id: &str,
        tickets: &[Value],
    ) -> Result<(), sqlx::Error> {
        if !self.ticket_schema_present().await? {
            return Ok(());
        }

        sqlx::query("DELETE FROM auth_coach_tickets WHERE account_id=$1 AND booking_id=$2")
            .bind(account_id.trim().to_ascii_lowercase())
            .bind(booking_id.trim())
            .execute(&self.pool)
            .await?;

        for ticket in tickets {
            let ticket_id = ticket
                .get("ticket_id")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let passenger_id = ticket
                .get("passenger_id")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let status = ticket
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("active");
            let boarding_state = ticket
                .get("boarding_state")
                .and_then(Value::as_str)
                .unwrap_or("not_boarded");
            let issued_at = ticket.get("issued_at").and_then(Value::as_str);
            sqlx::query(
                "INSERT INTO auth_coach_tickets \
                 (ticket_id, account_id, booking_id, passenger_id, status, boarding_state, ticket_payload, issued_at) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::timestamptz) \
                 ON CONFLICT (ticket_id) DO UPDATE SET \
                   account_id=EXCLUDED.account_id, \
                   booking_id=EXCLUDED.booking_id, \
                   passenger_id=EXCLUDED.passenger_id, \
                   status=EXCLUDED.status, \
                   boarding_state=EXCLUDED.boarding_state, \
                   ticket_payload=EXCLUDED.ticket_payload, \
                   updated_at=NOW(), \
                   issued_at=COALESCE(EXCLUDED.issued_at, auth_coach_tickets.issued_at), \
                   voided_at=CASE WHEN EXCLUDED.status = 'voided' THEN NOW() ELSE auth_coach_tickets.voided_at END, \
                   refunded_at=CASE WHEN EXCLUDED.status = 'refunded' THEN NOW() ELSE auth_coach_tickets.refunded_at END",
            )
            .bind(ticket_id.trim())
            .bind(account_id.trim().to_ascii_lowercase())
            .bind(booking_id.trim())
            .bind(passenger_id.trim())
            .bind(status.trim())
            .bind(boarding_state.trim())
            .bind(ticket.to_string())
            .bind(issued_at.map(str::trim))
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    pub async fn find_ticket_payload(
        &self,
        account_id: &str,
        ticket_id: &str,
    ) -> Result<Option<Value>, sqlx::Error> {
        if !self.ticket_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT ticket_payload::text AS ticket_payload_text \
             FROM auth_coach_tickets \
             WHERE account_id=$1 AND ticket_id=$2 \
             LIMIT 1",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(ticket_id.trim())
        .fetch_optional(&self.pool)
        .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        let payload_text: String = row.try_get("ticket_payload_text")?;
        Ok(Some(coach_catalog_json_value_from_text(&payload_text)?))
    }

    pub async fn list_ticket_payloads_for_booking(
        &self,
        account_id: &str,
        booking_id: &str,
    ) -> Result<Vec<Value>, sqlx::Error> {
        if !self.ticket_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT ticket_payload::text AS ticket_payload_text \
             FROM auth_coach_tickets \
             WHERE account_id=$1 AND booking_id=$2 \
             ORDER BY created_at ASC, ticket_id ASC",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(booking_id.trim())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|row| {
                let payload_text: String = row.try_get("ticket_payload_text")?;
                coach_catalog_json_value_from_text(&payload_text)
            })
            .collect()
    }

    pub async fn list_ticket_payloads_for_booking_any_account(
        &self,
        booking_id: &str,
    ) -> Result<Vec<Value>, sqlx::Error> {
        if !self.ticket_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT ticket_payload::text AS ticket_payload_text \
             FROM auth_coach_tickets \
             WHERE booking_id=$1 \
             ORDER BY created_at ASC, ticket_id ASC",
        )
        .bind(booking_id.trim())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|row| {
                let payload_text: String = row.try_get("ticket_payload_text")?;
                coach_catalog_json_value_from_text(&payload_text)
            })
            .collect()
    }

    pub async fn replace_ticket_artifacts(
        &self,
        account_id: &str,
        booking_id: &str,
        artifacts: &[Value],
    ) -> Result<(), sqlx::Error> {
        if !self.ticket_artifact_schema_present().await? {
            return Ok(());
        }

        sqlx::query(
            "DELETE FROM auth_coach_ticket_artifacts WHERE account_id=$1 AND booking_id=$2",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(booking_id.trim())
        .execute(&self.pool)
        .await?;

        for artifact in artifacts {
            let artifact_id = artifact
                .get("artifact_id")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let ticket_id = artifact
                .get("ticket_id")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let artifact_kind = artifact
                .get("artifact_kind")
                .and_then(Value::as_str)
                .unwrap_or("qr");
            let delivery_channel = artifact
                .get("delivery_channel")
                .and_then(Value::as_str)
                .unwrap_or(artifact_kind);
            let file_name = artifact
                .get("file_name")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let mime_type = artifact
                .get("mime_type")
                .and_then(Value::as_str)
                .unwrap_or("application/octet-stream");
            let content_length_bytes = artifact
                .get("content_length_bytes")
                .and_then(Value::as_i64)
                .unwrap_or(0);
            let download_path = artifact
                .get("download_path")
                .and_then(Value::as_str)
                .unwrap_or_default();
            sqlx::query(
                "INSERT INTO auth_coach_ticket_artifacts \
                 (artifact_id, account_id, booking_id, ticket_id, artifact_kind, delivery_channel, file_name, mime_type, content_length_bytes, download_path, artifact_payload) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb) \
                 ON CONFLICT (ticket_id, artifact_kind) DO UPDATE SET \
                   artifact_id=EXCLUDED.artifact_id, \
                   account_id=EXCLUDED.account_id, \
                   booking_id=EXCLUDED.booking_id, \
                   delivery_channel=EXCLUDED.delivery_channel, \
                   file_name=EXCLUDED.file_name, \
                   mime_type=EXCLUDED.mime_type, \
                   content_length_bytes=EXCLUDED.content_length_bytes, \
                   download_path=EXCLUDED.download_path, \
                   artifact_payload=EXCLUDED.artifact_payload, \
                   updated_at=NOW()",
            )
            .bind(artifact_id.trim())
            .bind(account_id.trim().to_ascii_lowercase())
            .bind(booking_id.trim())
            .bind(ticket_id.trim())
            .bind(artifact_kind.trim())
            .bind(delivery_channel.trim())
            .bind(file_name.trim())
            .bind(mime_type.trim())
            .bind(content_length_bytes)
            .bind(download_path.trim())
            .bind(artifact.to_string())
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    pub async fn list_ticket_artifact_payloads_for_booking(
        &self,
        account_id: &str,
        booking_id: &str,
    ) -> Result<Vec<Value>, sqlx::Error> {
        if !self.ticket_artifact_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT artifact_payload::text AS artifact_payload_text \
             FROM auth_coach_ticket_artifacts \
             WHERE account_id=$1 AND booking_id=$2 \
             ORDER BY created_at ASC, artifact_id ASC",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(booking_id.trim())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|row| {
                let payload_text: String = row.try_get("artifact_payload_text")?;
                coach_catalog_json_value_from_text(&payload_text)
            })
            .collect()
    }

    pub async fn list_ticket_artifact_payloads_for_ticket(
        &self,
        account_id: &str,
        ticket_id: &str,
    ) -> Result<Vec<Value>, sqlx::Error> {
        if !self.ticket_artifact_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT artifact_payload::text AS artifact_payload_text \
             FROM auth_coach_ticket_artifacts \
             WHERE account_id=$1 AND ticket_id=$2 \
             ORDER BY created_at ASC, artifact_id ASC",
        )
        .bind(account_id.trim().to_ascii_lowercase())
        .bind(ticket_id.trim())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|row| {
                let payload_text: String = row.try_get("artifact_payload_text")?;
                coach_catalog_json_value_from_text(&payload_text)
            })
            .collect()
    }

    pub async fn list_operator_feed_health(
        &self,
    ) -> Result<Vec<CoachCatalogOperatorFeedHealth>, sqlx::Error> {
        if !self.catalog_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT \
                health.operator_id, operator.display_name AS operator_name, operator.integration_mode, \
                health.feed_kind, health.source_kind, health.sync_status, health.freshness_status, \
                health.last_attempted_at::text AS last_attempted_at_iso, \
                health.last_succeeded_at::text AS last_succeeded_at_iso, \
                health.freshness_expires_at::text AS freshness_expires_at_iso, \
                health.records_ingested, health.error_message \
             FROM auth_coach_catalog_operator_feed_health health \
             JOIN auth_coach_catalog_operators operator \
               ON operator.operator_id = health.operator_id AND operator.active = TRUE \
             ORDER BY operator.display_name ASC, health.feed_kind ASC",
        )
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(Self::map_operator_feed_health_row)
            .collect()
    }

    pub async fn list_operators_by_ids(
        &self,
        operator_ids: &[String],
    ) -> Result<Vec<CoachCatalogOperator>, sqlx::Error> {
        if !self.catalog_schema_present().await? {
            return Ok(Vec::new());
        }

        let normalized_operator_ids = coach_catalog_normalize_string_list(operator_ids);
        if normalized_operator_ids.is_empty() {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT operator_id, display_name, integration_mode, country_code, active \
             FROM auth_coach_catalog_operators \
             WHERE active = TRUE AND operator_id = ANY($1) \
             ORDER BY display_name ASC, operator_id ASC",
        )
        .bind(&normalized_operator_ids)
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter().map(Self::map_operator_row).collect()
    }

    pub async fn upsert_source_artifact(
        &self,
        artifact: &CoachCatalogSourceArtifact,
    ) -> Result<(), sqlx::Error> {
        if !self.source_artifact_schema_present().await? {
            return Ok(());
        }

        sqlx::query(
            "INSERT INTO auth_coach_catalog_source_artifacts \
             (artifact_id, feed_kind, source_kind, source_label, file_name, file_checksum_sha256, \
              content_length_bytes, extracted_file_count, feed_locator, operator_ids, created_by_account_id, created_at) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11, $12::timestamptz) \
             ON CONFLICT (artifact_id) DO UPDATE SET \
               feed_kind=EXCLUDED.feed_kind, \
               source_kind=EXCLUDED.source_kind, \
               source_label=EXCLUDED.source_label, \
               file_name=EXCLUDED.file_name, \
               file_checksum_sha256=EXCLUDED.file_checksum_sha256, \
               content_length_bytes=EXCLUDED.content_length_bytes, \
               extracted_file_count=EXCLUDED.extracted_file_count, \
               feed_locator=EXCLUDED.feed_locator, \
               operator_ids=EXCLUDED.operator_ids, \
               created_by_account_id=EXCLUDED.created_by_account_id, \
               created_at=EXCLUDED.created_at, \
               updated_at=NOW()",
        )
        .bind(artifact.artifact_id.trim())
        .bind(artifact.feed_kind.trim())
        .bind(artifact.source_kind.trim())
        .bind(artifact.source_label.trim())
        .bind(artifact.file_name.trim())
        .bind(artifact.file_checksum_sha256.trim())
        .bind(artifact.content_length_bytes)
        .bind(artifact.extracted_file_count)
        .bind(artifact.feed_locator.trim())
        .bind(json!(coach_catalog_normalize_string_list(&artifact.operator_ids)))
        .bind(artifact.created_by_account_id.trim())
        .bind(artifact.created_at_iso.trim())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_source_artifact_by_feed_locator(
        &self,
        feed_kind: &str,
        source_kind: &str,
        feed_locator: &str,
    ) -> Result<Option<CoachCatalogSourceArtifact>, sqlx::Error> {
        if !self.source_artifact_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT \
                artifact_id, feed_kind, source_kind, source_label, file_name, file_checksum_sha256, \
                content_length_bytes, extracted_file_count, feed_locator, operator_ids, created_by_account_id, \
                created_at::text AS created_at_iso \
             FROM auth_coach_catalog_source_artifacts \
             WHERE feed_kind = $1 AND source_kind = $2 AND feed_locator = $3 \
             LIMIT 1",
        )
        .bind(feed_kind.trim())
        .bind(source_kind.trim())
        .bind(feed_locator.trim())
        .fetch_optional(&self.pool)
        .await?;

        row.map(Self::map_source_artifact_row).transpose()
    }

    pub async fn find_source_artifact_by_id(
        &self,
        artifact_id: &str,
    ) -> Result<Option<CoachCatalogSourceArtifact>, sqlx::Error> {
        if !self.source_artifact_schema_present().await? {
            return Ok(None);
        }

        let row = sqlx::query(
            "SELECT \
                artifact_id, feed_kind, source_kind, source_label, file_name, file_checksum_sha256, \
                content_length_bytes, extracted_file_count, feed_locator, operator_ids, created_by_account_id, \
                created_at::text AS created_at_iso \
             FROM auth_coach_catalog_source_artifacts \
             WHERE artifact_id = $1 \
             LIMIT 1",
        )
        .bind(artifact_id.trim())
        .fetch_optional(&self.pool)
        .await?;

        row.map(Self::map_source_artifact_row).transpose()
    }

    pub async fn list_source_artifacts(
        &self,
        feed_kind: &str,
        source_kind: &str,
    ) -> Result<Vec<CoachCatalogSourceArtifact>, sqlx::Error> {
        if !self.source_artifact_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT \
                artifact_id, feed_kind, source_kind, source_label, file_name, file_checksum_sha256, \
                content_length_bytes, extracted_file_count, feed_locator, operator_ids, created_by_account_id, \
                created_at::text AS created_at_iso \
             FROM auth_coach_catalog_source_artifacts \
             WHERE feed_kind = $1 AND source_kind = $2 \
             ORDER BY created_at DESC, artifact_id DESC",
        )
        .bind(feed_kind.trim())
        .bind(source_kind.trim())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(Self::map_source_artifact_row)
            .collect()
    }

    pub async fn upsert_import_config(
        &self,
        config: &CoachCatalogImportConfig,
    ) -> Result<(), sqlx::Error> {
        if !self.import_config_schema_present().await? {
            return Ok(());
        }

        sqlx::query(
            "INSERT INTO auth_coach_catalog_import_configs \
             (feed_kind, source_kind, feed_locator, source_artifact_id, updated_by_account_id) \
             VALUES ($1, $2, $3, $4, $5) \
             ON CONFLICT (feed_kind, source_kind) DO UPDATE SET \
               feed_locator=EXCLUDED.feed_locator, \
               source_artifact_id=EXCLUDED.source_artifact_id, \
               updated_by_account_id=EXCLUDED.updated_by_account_id, \
               updated_at=NOW()",
        )
        .bind(config.feed_kind.trim())
        .bind(config.source_kind.trim())
        .bind(config.feed_locator.trim())
        .bind(config.source_artifact_id.as_deref().map(str::trim))
        .bind(config.updated_by_account_id.trim())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_import_config(
        &self,
        feed_kind: &str,
        source_kind: &str,
    ) -> Result<Option<CoachCatalogImportConfig>, sqlx::Error> {
        if !self.import_config_schema_present().await? {
            return Ok(None);
        }

        let row = if self.source_artifact_schema_present().await? {
            sqlx::query(
                "SELECT \
                    config.feed_kind, config.source_kind, config.feed_locator, config.source_artifact_id, \
                    config.updated_by_account_id, config.updated_at::text AS updated_at_iso, \
                    artifact.artifact_id AS source_artifact_artifact_id, \
                    artifact.feed_kind AS source_artifact_feed_kind, \
                    artifact.source_kind AS source_artifact_source_kind, \
                    artifact.source_label AS source_artifact_source_label, \
                    artifact.file_name AS source_artifact_file_name, \
                    artifact.file_checksum_sha256 AS source_artifact_file_checksum_sha256, \
                    artifact.content_length_bytes AS source_artifact_content_length_bytes, \
                    artifact.extracted_file_count AS source_artifact_extracted_file_count, \
                    artifact.feed_locator AS source_artifact_feed_locator, \
                    artifact.operator_ids AS source_artifact_operator_ids, \
                    artifact.created_by_account_id AS source_artifact_created_by_account_id, \
                    artifact.created_at::text AS source_artifact_created_at_iso \
                 FROM auth_coach_catalog_import_configs config \
                 LEFT JOIN auth_coach_catalog_source_artifacts artifact \
                   ON artifact.artifact_id = config.source_artifact_id \
                 WHERE config.feed_kind = $1 AND config.source_kind = $2 \
                 LIMIT 1",
            )
            .bind(feed_kind.trim())
            .bind(source_kind.trim())
            .fetch_optional(&self.pool)
            .await?
        } else {
            sqlx::query(
                "SELECT \
                    feed_kind, source_kind, feed_locator, updated_by_account_id, updated_at::text AS updated_at_iso \
                 FROM auth_coach_catalog_import_configs \
                 WHERE feed_kind = $1 AND source_kind = $2 \
                 LIMIT 1",
            )
            .bind(feed_kind.trim())
            .bind(source_kind.trim())
            .fetch_optional(&self.pool)
            .await?
        };

        row.map(Self::map_import_config_row).transpose()
    }

    pub async fn list_import_run_saved_views(
        &self,
        account_id: &str,
        visibility_scope: Option<&str>,
        owner_account_id: Option<&str>,
        operator_id: Option<&str>,
    ) -> Result<Vec<CoachCatalogImportRunSavedView>, sqlx::Error> {
        if !self.import_run_saved_view_schema_present().await? {
            return Ok(Vec::new());
        }

        let owner_account_id = owner_account_id
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let rows = match visibility_scope.map(str::trim) {
            Some("personal") => {
                sqlx::query(
                    "SELECT \
                        view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                        created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                     FROM auth_coach_catalog_import_run_saved_views \
                     WHERE account_id = $1 AND visibility_scope = 'personal' \
                     ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                )
                .bind(account_id.trim())
                .fetch_all(&self.pool)
                .await?
            }
            Some("shared_ops") => {
                if let Some(owner_account_id) = owner_account_id {
                    sqlx::query(
                        "SELECT \
                            view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                            created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                         FROM auth_coach_catalog_import_run_saved_views \
                         WHERE visibility_scope = 'shared_ops' AND account_id = $1 \
                         ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                    )
                    .bind(owner_account_id)
                    .fetch_all(&self.pool)
                    .await?
                } else {
                    sqlx::query(
                        "SELECT \
                            view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                            created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                         FROM auth_coach_catalog_import_run_saved_views \
                         WHERE visibility_scope = 'shared_ops' \
                         ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                    )
                    .fetch_all(&self.pool)
                    .await?
                }
            }
            _ => {
                if let Some(owner_account_id) = owner_account_id {
                    sqlx::query(
                        "SELECT \
                            view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                            created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                         FROM auth_coach_catalog_import_run_saved_views \
                         WHERE visibility_scope = 'shared_ops' AND account_id = $1 \
                         ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                    )
                    .bind(owner_account_id)
                    .fetch_all(&self.pool)
                    .await?
                } else {
                    sqlx::query(
                        "SELECT \
                            view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                            created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                         FROM auth_coach_catalog_import_run_saved_views \
                         WHERE account_id = $1 OR visibility_scope = 'shared_ops' \
                         ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                    )
                    .bind(account_id.trim())
                    .fetch_all(&self.pool)
                    .await?
                }
            }
        };

        let mut views = rows
            .into_iter()
            .map(Self::map_import_run_saved_view_row)
            .collect::<Result<Vec<_>, _>>()?;
        if let Some(operator_id) = operator_id.map(str::trim).filter(|value| !value.is_empty()) {
            views.retain(|entry| {
                entry.visibility_scope != "shared_ops"
                    || coach_catalog_saved_view_matches_operator_scope(
                        &entry.operator_ids,
                        Some(operator_id),
                    )
            });
        }
        Ok(views)
    }

    pub async fn upsert_import_run_saved_view(
        &self,
        view: &CoachCatalogImportRunSavedView,
    ) -> Result<CoachCatalogImportRunSavedView, sqlx::Error> {
        if !self.import_run_saved_view_schema_present().await? {
            return Ok(view.clone());
        }

        let mut tx = self.pool.begin().await?;
        let account_id = view.account_id.trim();
        let view_id = view.view_id.trim();
        let visibility_scope = view.visibility_scope.trim();
        let name = view.name.trim();
        let operator_ids = if visibility_scope == "shared_ops" {
            coach_catalog_normalize_string_list(&view.operator_ids)
        } else {
            Vec::new()
        };
        let status_filter = view.status_filter.trim();
        let replay_scope_filter = view.replay_scope_filter.trim();
        let issue_severity_filter = view.issue_severity_filter.trim();
        let issue_stage_filter = view.issue_stage_filter.trim();
        let is_default = view.is_default && visibility_scope == "personal";
        let created_at_iso = view.created_at_iso.trim();
        let updated_at_iso = view.updated_at_iso.trim();

        let existing_by_id = sqlx::query(
            "SELECT \
                view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
             FROM auth_coach_catalog_import_run_saved_views \
             WHERE view_id = $2 AND account_id = $1 \
             LIMIT 1",
        )
        .bind(account_id)
        .bind(view_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(Self::map_import_run_saved_view_row)
        .transpose()?;

        let existing_by_name = if existing_by_id.is_some() {
            None
        } else {
            sqlx::query(
                "SELECT \
                    view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                 FROM auth_coach_catalog_import_run_saved_views \
                 WHERE LOWER(name) = LOWER($2) AND \
                       ((visibility_scope = 'personal' AND account_id = $1) OR visibility_scope = 'shared_ops') AND \
                       visibility_scope = $3 \
                 LIMIT 1",
            )
            .bind(account_id)
            .bind(name)
            .bind(visibility_scope)
            .fetch_optional(&mut *tx)
            .await?
            .map(Self::map_import_run_saved_view_row)
            .transpose()?
        };

        let target_view_id = existing_by_id
            .as_ref()
            .map(|value| value.view_id.as_str())
            .or(existing_by_name
                .as_ref()
                .map(|value| value.view_id.as_str()))
            .unwrap_or(view_id);

        if is_default {
            sqlx::query(
                "UPDATE auth_coach_catalog_import_run_saved_views \
                 SET is_default = FALSE \
                 WHERE account_id = $1 AND visibility_scope = 'personal' AND view_id <> $2 AND is_default = TRUE",
            )
            .bind(account_id)
            .bind(target_view_id)
            .execute(&mut *tx)
            .await?;
        }

        let row = if existing_by_id.is_some() {
            sqlx::query(
                "UPDATE auth_coach_catalog_import_run_saved_views \
                 SET visibility_scope = $3, \
                     name = $4, \
                     operator_ids = $5::jsonb, \
                     status_filter = $6, \
                     replay_scope_filter = $7, \
                     issue_severity_filter = $8, \
                     issue_stage_filter = $9, \
                     is_default = $10, \
                     updated_at = $11::timestamptz \
                 WHERE view_id = $2 AND account_id = $1 \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(account_id)
            .bind(view_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(json!(operator_ids))
            .bind(status_filter)
            .bind(replay_scope_filter)
            .bind(issue_severity_filter)
            .bind(issue_stage_filter)
            .bind(is_default)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        } else if let Some(existing) = existing_by_name {
            sqlx::query(
                "UPDATE auth_coach_catalog_import_run_saved_views \
                 SET visibility_scope = $3, \
                     name = $4, \
                     operator_ids = $5::jsonb, \
                     status_filter = $6, \
                     replay_scope_filter = $7, \
                     issue_severity_filter = $8, \
                     issue_stage_filter = $9, \
                     is_default = $10, \
                     updated_at = $11::timestamptz \
                 WHERE view_id = $2 AND account_id = $1 \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(account_id)
            .bind(existing.view_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(json!(operator_ids))
            .bind(status_filter)
            .bind(replay_scope_filter)
            .bind(issue_severity_filter)
            .bind(issue_stage_filter)
            .bind(is_default)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        } else {
            sqlx::query(
                "INSERT INTO auth_coach_catalog_import_run_saved_views \
                 (view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, created_at, updated_at) \
                 VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8, $9, $10, $11::timestamptz, $12::timestamptz) \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_ids, status_filter, replay_scope_filter, issue_severity_filter, issue_stage_filter, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(view_id)
            .bind(account_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(json!(operator_ids))
            .bind(status_filter)
            .bind(replay_scope_filter)
            .bind(issue_severity_filter)
            .bind(issue_stage_filter)
            .bind(is_default)
            .bind(created_at_iso)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        };

        tx.commit().await?;
        Self::map_import_run_saved_view_row(row)
    }

    pub async fn delete_import_run_saved_view(
        &self,
        account_id: &str,
        view_id: &str,
    ) -> Result<bool, sqlx::Error> {
        if !self.import_run_saved_view_schema_present().await? {
            return Ok(false);
        }

        let result = sqlx::query(
            "DELETE FROM auth_coach_catalog_import_run_saved_views \
             WHERE view_id = $2 AND account_id = $1",
        )
        .bind(account_id.trim())
        .bind(view_id.trim())
        .execute(&self.pool)
        .await?;
        if result.rows_affected() > 0 {
            self.delete_saved_view_favorites_for_view(
                "catalog_import_run_saved_views",
                view_id.trim(),
            )
            .await?;
            self.delete_saved_view_usage_for_view("catalog_import_run_saved_views", view_id.trim())
                .await?;
        }
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_import_run_issue_saved_views(
        &self,
        account_id: &str,
        visibility_scope: Option<&str>,
        owner_account_id: Option<&str>,
        operator_id: Option<&str>,
    ) -> Result<Vec<CoachCatalogImportRunIssueSavedView>, sqlx::Error> {
        if !self.import_run_issue_saved_view_schema_present().await? {
            return Ok(Vec::new());
        }

        let owner_account_id = owner_account_id
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let rows = match visibility_scope.map(str::trim) {
            Some("personal") => {
                sqlx::query(
                    "SELECT \
                        view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                        created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                     FROM auth_coach_catalog_import_run_issue_saved_views \
                     WHERE account_id = $1 AND visibility_scope = 'personal' \
                     ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                )
                .bind(account_id.trim())
                .fetch_all(&self.pool)
                .await?
            }
            Some("shared_ops") => {
                if let Some(owner_account_id) = owner_account_id {
                    sqlx::query(
                        "SELECT \
                            view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                            created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                         FROM auth_coach_catalog_import_run_issue_saved_views \
                         WHERE visibility_scope = 'shared_ops' AND account_id = $1 \
                         ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                    )
                    .bind(owner_account_id)
                    .fetch_all(&self.pool)
                    .await?
                } else {
                    sqlx::query(
                        "SELECT \
                            view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                            created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                         FROM auth_coach_catalog_import_run_issue_saved_views \
                         WHERE visibility_scope = 'shared_ops' \
                         ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                    )
                    .fetch_all(&self.pool)
                    .await?
                }
            }
            _ => {
                if let Some(owner_account_id) = owner_account_id {
                    sqlx::query(
                        "SELECT \
                            view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                            created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                         FROM auth_coach_catalog_import_run_issue_saved_views \
                         WHERE visibility_scope = 'shared_ops' AND account_id = $1 \
                         ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                    )
                    .bind(owner_account_id)
                    .fetch_all(&self.pool)
                    .await?
                } else {
                    sqlx::query(
                        "SELECT \
                            view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                            created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                         FROM auth_coach_catalog_import_run_issue_saved_views \
                         WHERE account_id = $1 OR visibility_scope = 'shared_ops' \
                         ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
                    )
                    .bind(account_id.trim())
                    .fetch_all(&self.pool)
                    .await?
                }
            }
        };

        let mut views = rows
            .into_iter()
            .map(Self::map_import_run_issue_saved_view_row)
            .collect::<Result<Vec<_>, _>>()?;
        if let Some(operator_id) = operator_id.map(str::trim).filter(|value| !value.is_empty()) {
            views.retain(|entry| {
                entry.visibility_scope != "shared_ops"
                    || coach_catalog_saved_view_matches_operator_scope(
                        &entry.operator_ids,
                        Some(operator_id),
                    )
            });
        }
        Ok(views)
    }

    pub async fn upsert_import_run_issue_saved_view(
        &self,
        view: &CoachCatalogImportRunIssueSavedView,
    ) -> Result<CoachCatalogImportRunIssueSavedView, sqlx::Error> {
        if !self.import_run_issue_saved_view_schema_present().await? {
            return Ok(view.clone());
        }

        let mut tx = self.pool.begin().await?;
        let account_id = view.account_id.trim();
        let view_id = view.view_id.trim();
        let visibility_scope = view.visibility_scope.trim();
        let name = view.name.trim();
        let operator_ids = if visibility_scope == "shared_ops" {
            coach_catalog_normalize_string_list(&view.operator_ids)
        } else {
            Vec::new()
        };
        let severity_filter = view.severity_filter.trim();
        let stage_filter = view.stage_filter.trim();
        let is_default = view.is_default && visibility_scope == "personal";
        let created_at_iso = view.created_at_iso.trim();
        let updated_at_iso = view.updated_at_iso.trim();

        let existing_by_id = sqlx::query(
            "SELECT \
                view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
             FROM auth_coach_catalog_import_run_issue_saved_views \
             WHERE view_id = $2 AND account_id = $1 \
             LIMIT 1",
        )
        .bind(account_id)
        .bind(view_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(Self::map_import_run_issue_saved_view_row)
        .transpose()?;

        let existing_by_name = if existing_by_id.is_some() {
            None
        } else {
            sqlx::query(
                "SELECT \
                    view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                 FROM auth_coach_catalog_import_run_issue_saved_views \
                 WHERE LOWER(name) = LOWER($2) AND \
                       ((visibility_scope = 'personal' AND account_id = $1) OR visibility_scope = 'shared_ops') AND \
                       visibility_scope = $3 \
                 LIMIT 1",
            )
            .bind(account_id)
            .bind(name)
            .bind(visibility_scope)
            .fetch_optional(&mut *tx)
            .await?
            .map(Self::map_import_run_issue_saved_view_row)
            .transpose()?
        };

        let target_view_id = existing_by_id
            .as_ref()
            .map(|value| value.view_id.as_str())
            .or(existing_by_name
                .as_ref()
                .map(|value| value.view_id.as_str()))
            .unwrap_or(view_id);

        if is_default {
            sqlx::query(
                "UPDATE auth_coach_catalog_import_run_issue_saved_views \
                 SET is_default = FALSE \
                 WHERE account_id = $1 AND visibility_scope = 'personal' AND view_id <> $2 AND is_default = TRUE",
            )
            .bind(account_id)
            .bind(target_view_id)
            .execute(&mut *tx)
            .await?;
        }

        let row = if existing_by_id.is_some() {
            sqlx::query(
                "UPDATE auth_coach_catalog_import_run_issue_saved_views \
                 SET visibility_scope = $3, \
                     name = $4, \
                     operator_ids = $5::jsonb, \
                     severity_filter = $6, \
                     stage_filter = $7, \
                     is_default = $8, \
                     updated_at = $9::timestamptz \
                 WHERE view_id = $2 AND account_id = $1 \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(account_id)
            .bind(view_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(json!(operator_ids))
            .bind(severity_filter)
            .bind(stage_filter)
            .bind(is_default)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        } else if let Some(existing) = existing_by_name {
            sqlx::query(
                "UPDATE auth_coach_catalog_import_run_issue_saved_views \
                 SET visibility_scope = $3, \
                     name = $4, \
                     operator_ids = $5::jsonb, \
                     severity_filter = $6, \
                     stage_filter = $7, \
                     is_default = $8, \
                     updated_at = $9::timestamptz \
                 WHERE view_id = $2 AND account_id = $1 \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(account_id)
            .bind(existing.view_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(json!(operator_ids))
            .bind(severity_filter)
            .bind(stage_filter)
            .bind(is_default)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        } else {
            sqlx::query(
                "INSERT INTO auth_coach_catalog_import_run_issue_saved_views \
                    (view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, created_at, updated_at) \
                 VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8, $9::timestamptz, $10::timestamptz) \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_ids, severity_filter, stage_filter, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(view_id)
            .bind(account_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(json!(operator_ids))
            .bind(severity_filter)
            .bind(stage_filter)
            .bind(is_default)
            .bind(created_at_iso)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        };

        tx.commit().await?;
        Self::map_import_run_issue_saved_view_row(row)
    }

    pub async fn delete_import_run_issue_saved_view(
        &self,
        account_id: &str,
        view_id: &str,
    ) -> Result<bool, sqlx::Error> {
        if !self.import_run_issue_saved_view_schema_present().await? {
            return Ok(false);
        }

        let result = sqlx::query(
            "DELETE FROM auth_coach_catalog_import_run_issue_saved_views \
             WHERE view_id = $2 AND account_id = $1",
        )
        .bind(account_id.trim())
        .bind(view_id.trim())
        .execute(&self.pool)
        .await?;
        if result.rows_affected() > 0 {
            self.delete_saved_view_favorites_for_view(
                "catalog_import_run_issue_saved_views",
                view_id.trim(),
            )
            .await?;
            self.delete_saved_view_usage_for_view(
                "catalog_import_run_issue_saved_views",
                view_id.trim(),
            )
            .await?;
        }
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_payout_import_batch_saved_views(
        &self,
        account_id: &str,
    ) -> Result<Vec<CoachPayoutImportBatchSavedView>, sqlx::Error> {
        if !self.payout_import_batch_saved_view_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT \
                view_id, account_id, visibility_scope, name, operator_id, is_default, \
                created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
             FROM auth_coach_settlement_payout_import_batch_saved_views \
             WHERE account_id = $1 OR visibility_scope = 'shared_ops' \
             ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
        )
        .bind(account_id.trim())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(Self::map_payout_import_batch_saved_view_row)
            .collect()
    }

    pub async fn upsert_payout_import_batch_saved_view(
        &self,
        view: &CoachPayoutImportBatchSavedView,
    ) -> Result<CoachPayoutImportBatchSavedView, sqlx::Error> {
        if !self.payout_import_batch_saved_view_schema_present().await? {
            return Ok(view.clone());
        }

        let mut tx = self.pool.begin().await?;
        let account_id = view.account_id.trim();
        let view_id = view.view_id.trim();
        let visibility_scope = view.visibility_scope.trim();
        let name = view.name.trim();
        let operator_id = view.operator_id.trim();
        let is_default = view.is_default && visibility_scope == "personal";
        let created_at_iso = view.created_at_iso.trim();
        let updated_at_iso = view.updated_at_iso.trim();

        let existing_by_id = sqlx::query(
            "SELECT \
                view_id, account_id, visibility_scope, name, operator_id, is_default, \
                created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
             FROM auth_coach_settlement_payout_import_batch_saved_views \
             WHERE ((visibility_scope = 'personal' AND account_id = $1) OR visibility_scope = 'shared_ops') \
               AND view_id = $2 \
             LIMIT 1",
        )
        .bind(account_id)
        .bind(view_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(Self::map_payout_import_batch_saved_view_row)
        .transpose()?;

        let existing_by_name = if existing_by_id.is_some() {
            None
        } else {
            sqlx::query(
                "SELECT \
                    view_id, account_id, visibility_scope, name, operator_id, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                 FROM auth_coach_settlement_payout_import_batch_saved_views \
                 WHERE ((visibility_scope = 'personal' AND account_id = $1) OR visibility_scope = 'shared_ops') \
                   AND visibility_scope = $3 \
                   AND LOWER(name) = LOWER($2) \
                 LIMIT 1",
            )
            .bind(account_id)
            .bind(name)
            .bind(visibility_scope)
            .fetch_optional(&mut *tx)
            .await?
            .map(Self::map_payout_import_batch_saved_view_row)
            .transpose()?
        };

        if is_default {
            sqlx::query(
                "UPDATE auth_coach_settlement_payout_import_batch_saved_views \
                 SET is_default = FALSE \
                 WHERE account_id = $1 AND visibility_scope = 'personal' AND view_id <> $2 AND is_default = TRUE",
            )
            .bind(account_id)
            .bind(view_id)
            .execute(&mut *tx)
            .await?;
        }

        let row = if existing_by_id.is_some() {
            sqlx::query(
                "UPDATE auth_coach_settlement_payout_import_batch_saved_views \
                 SET visibility_scope = $3, name = $4, operator_id = $5, is_default = $6, updated_at = $7::timestamptz \
                 WHERE view_id = $2 AND account_id = $1 \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_id, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(account_id)
            .bind(view_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(operator_id)
            .bind(is_default)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        } else if let Some(existing) = existing_by_name {
            sqlx::query(
                "UPDATE auth_coach_settlement_payout_import_batch_saved_views \
                 SET visibility_scope = $3, name = $4, operator_id = $5, is_default = $6, updated_at = $7::timestamptz \
                 WHERE view_id = $2 AND account_id = $1 \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_id, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(account_id)
            .bind(existing.view_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(operator_id)
            .bind(is_default)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        } else {
            sqlx::query(
                "INSERT INTO auth_coach_settlement_payout_import_batch_saved_views \
                 (view_id, account_id, visibility_scope, name, operator_id, is_default, created_at, updated_at) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7::timestamptz, $8::timestamptz) \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, operator_id, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(view_id)
            .bind(account_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(operator_id)
            .bind(is_default)
            .bind(created_at_iso)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        };

        tx.commit().await?;
        Self::map_payout_import_batch_saved_view_row(row)
    }

    pub async fn delete_payout_import_batch_saved_view(
        &self,
        account_id: &str,
        view_id: &str,
    ) -> Result<bool, sqlx::Error> {
        if !self.payout_import_batch_saved_view_schema_present().await? {
            return Ok(false);
        }

        let result = sqlx::query(
            "DELETE FROM auth_coach_settlement_payout_import_batch_saved_views \
             WHERE account_id = $1 AND view_id = $2",
        )
        .bind(account_id.trim())
        .bind(view_id.trim())
        .execute(&self.pool)
        .await?;
        if result.rows_affected() > 0 {
            self.delete_saved_view_favorites_for_view(
                "payout_import_batch_saved_views",
                view_id.trim(),
            )
            .await?;
            self.delete_saved_view_usage_for_view(
                "payout_import_batch_saved_views",
                view_id.trim(),
            )
            .await?;
        }
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_payout_import_preview_saved_views(
        &self,
        account_id: &str,
    ) -> Result<Vec<CoachPayoutImportPreviewSavedView>, sqlx::Error> {
        if !self
            .payout_import_preview_saved_view_schema_present()
            .await?
        {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT \
                view_id, account_id, visibility_scope, name, status_filter, \
                from_created_at::text AS from_created_at_iso, \
                to_created_at::text AS to_created_at_iso, \
                operator_id, is_default, \
                created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
             FROM auth_coach_settlement_payout_import_preview_saved_views \
             WHERE account_id = $1 OR visibility_scope = 'shared_ops' \
             ORDER BY is_default DESC, visibility_scope ASC, updated_at DESC, view_id DESC",
        )
        .bind(account_id.trim())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(Self::map_payout_import_preview_saved_view_row)
            .collect()
    }

    pub async fn upsert_payout_import_preview_saved_view(
        &self,
        view: &CoachPayoutImportPreviewSavedView,
    ) -> Result<CoachPayoutImportPreviewSavedView, sqlx::Error> {
        if !self
            .payout_import_preview_saved_view_schema_present()
            .await?
        {
            return Ok(view.clone());
        }

        let mut tx = self.pool.begin().await?;
        let account_id = view.account_id.trim();
        let view_id = view.view_id.trim();
        let visibility_scope = view.visibility_scope.trim();
        let name = view.name.trim();
        let status_filter = view.status_filter.trim();
        let operator_id = view.operator_id.trim();
        let is_default = view.is_default && visibility_scope == "personal";
        let from_created_at_iso = view.from_created_at_iso.as_deref().map(str::trim);
        let to_created_at_iso = view.to_created_at_iso.as_deref().map(str::trim);
        let created_at_iso = view.created_at_iso.trim();
        let updated_at_iso = view.updated_at_iso.trim();

        let existing_by_id = sqlx::query(
            "SELECT \
                view_id, account_id, visibility_scope, name, status_filter, \
                from_created_at::text AS from_created_at_iso, \
                to_created_at::text AS to_created_at_iso, \
                operator_id, is_default, \
                created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
             FROM auth_coach_settlement_payout_import_preview_saved_views \
             WHERE ((visibility_scope = 'personal' AND account_id = $1) OR visibility_scope = 'shared_ops') \
               AND view_id = $2 \
             LIMIT 1",
        )
        .bind(account_id)
        .bind(view_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(Self::map_payout_import_preview_saved_view_row)
        .transpose()?;

        let existing_by_name = if existing_by_id.is_some() {
            None
        } else {
            sqlx::query(
                "SELECT \
                    view_id, account_id, visibility_scope, name, status_filter, \
                    from_created_at::text AS from_created_at_iso, \
                    to_created_at::text AS to_created_at_iso, \
                    operator_id, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso \
                 FROM auth_coach_settlement_payout_import_preview_saved_views \
                 WHERE ((visibility_scope = 'personal' AND account_id = $1) OR visibility_scope = 'shared_ops') \
                   AND visibility_scope = $3 \
                   AND LOWER(name) = LOWER($2) \
                 LIMIT 1",
            )
            .bind(account_id)
            .bind(name)
            .bind(visibility_scope)
            .fetch_optional(&mut *tx)
            .await?
            .map(Self::map_payout_import_preview_saved_view_row)
            .transpose()?
        };

        if is_default {
            sqlx::query(
                "UPDATE auth_coach_settlement_payout_import_preview_saved_views \
                 SET is_default = FALSE \
                 WHERE account_id = $1 AND visibility_scope = 'personal' AND view_id <> $2 AND is_default = TRUE",
            )
            .bind(account_id)
            .bind(view_id)
            .execute(&mut *tx)
            .await?;
        }

        let row = if existing_by_id.is_some() {
            sqlx::query(
                "UPDATE auth_coach_settlement_payout_import_preview_saved_views \
                 SET visibility_scope = $3, name = $4, status_filter = $5, from_created_at = $6::timestamptz, \
                     to_created_at = $7::timestamptz, operator_id = $8, is_default = $9, updated_at = $10::timestamptz \
                 WHERE view_id = $2 AND account_id = $1 \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, status_filter, \
                    from_created_at::text AS from_created_at_iso, \
                    to_created_at::text AS to_created_at_iso, \
                    operator_id, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(account_id)
            .bind(view_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(status_filter)
            .bind(from_created_at_iso)
            .bind(to_created_at_iso)
            .bind(operator_id)
            .bind(is_default)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        } else if let Some(existing) = existing_by_name {
            sqlx::query(
                "UPDATE auth_coach_settlement_payout_import_preview_saved_views \
                 SET visibility_scope = $3, name = $4, status_filter = $5, from_created_at = $6::timestamptz, \
                     to_created_at = $7::timestamptz, operator_id = $8, is_default = $9, updated_at = $10::timestamptz \
                 WHERE view_id = $2 AND account_id = $1 \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, status_filter, \
                    from_created_at::text AS from_created_at_iso, \
                    to_created_at::text AS to_created_at_iso, \
                    operator_id, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(account_id)
            .bind(existing.view_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(status_filter)
            .bind(from_created_at_iso)
            .bind(to_created_at_iso)
            .bind(operator_id)
            .bind(is_default)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        } else {
            sqlx::query(
                "INSERT INTO auth_coach_settlement_payout_import_preview_saved_views \
                 (view_id, account_id, visibility_scope, name, status_filter, from_created_at, to_created_at, operator_id, is_default, created_at, updated_at) \
                 VALUES ($1, $2, $3, $4, $5, $6::timestamptz, $7::timestamptz, $8, $9, $10::timestamptz, $11::timestamptz) \
                 RETURNING \
                    view_id, account_id, visibility_scope, name, status_filter, \
                    from_created_at::text AS from_created_at_iso, \
                    to_created_at::text AS to_created_at_iso, \
                    operator_id, is_default, \
                    created_at::text AS created_at_iso, updated_at::text AS updated_at_iso",
            )
            .bind(view_id)
            .bind(account_id)
            .bind(visibility_scope)
            .bind(name)
            .bind(status_filter)
            .bind(from_created_at_iso)
            .bind(to_created_at_iso)
            .bind(operator_id)
            .bind(is_default)
            .bind(created_at_iso)
            .bind(updated_at_iso)
            .fetch_one(&mut *tx)
            .await?
        };

        tx.commit().await?;
        Self::map_payout_import_preview_saved_view_row(row)
    }

    pub async fn delete_payout_import_preview_saved_view(
        &self,
        account_id: &str,
        view_id: &str,
    ) -> Result<bool, sqlx::Error> {
        if !self
            .payout_import_preview_saved_view_schema_present()
            .await?
        {
            return Ok(false);
        }

        let result = sqlx::query(
            "DELETE FROM auth_coach_settlement_payout_import_preview_saved_views \
             WHERE account_id = $1 AND view_id = $2",
        )
        .bind(account_id.trim())
        .bind(view_id.trim())
        .execute(&self.pool)
        .await?;
        if result.rows_affected() > 0 {
            self.delete_saved_view_favorites_for_view(
                "payout_import_preview_saved_views",
                view_id.trim(),
            )
            .await?;
            self.delete_saved_view_usage_for_view(
                "payout_import_preview_saved_views",
                view_id.trim(),
            )
            .await?;
        }
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_saved_view_favorites(
        &self,
        account_id: &str,
        collection_key: &str,
    ) -> Result<Vec<String>, sqlx::Error> {
        if !self.saved_view_favorite_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = sqlx::query(
            "SELECT view_id \
             FROM auth_coach_saved_view_favorites \
             WHERE account_id = $1 AND collection_key = $2 \
             ORDER BY updated_at DESC, view_id DESC",
        )
        .bind(account_id.trim())
        .bind(collection_key.trim())
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .filter_map(|row| row.try_get::<String, _>("view_id").ok())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .collect())
    }

    pub async fn set_saved_view_favorite(
        &self,
        account_id: &str,
        collection_key: &str,
        view_id: &str,
        favorite: bool,
        updated_at_iso: &str,
    ) -> Result<Vec<String>, sqlx::Error> {
        if !self.saved_view_favorite_schema_present().await? {
            return Ok(Vec::new());
        }

        let account_id = account_id.trim();
        let collection_key = collection_key.trim();
        let view_id = view_id.trim();
        if account_id.is_empty() || collection_key.is_empty() || view_id.is_empty() {
            return Ok(self
                .list_saved_view_favorites(account_id, collection_key)
                .await
                .unwrap_or_default());
        }

        if favorite {
            sqlx::query(
                "INSERT INTO auth_coach_saved_view_favorites \
                 (account_id, collection_key, view_id, created_at, updated_at) \
                 VALUES ($1, $2, $3, $4::timestamptz, $5::timestamptz) \
                 ON CONFLICT (account_id, collection_key, view_id) DO UPDATE SET \
                    updated_at = EXCLUDED.updated_at",
            )
            .bind(account_id)
            .bind(collection_key)
            .bind(view_id)
            .bind(updated_at_iso.trim())
            .bind(updated_at_iso.trim())
            .execute(&self.pool)
            .await?;
        } else {
            sqlx::query(
                "DELETE FROM auth_coach_saved_view_favorites \
                 WHERE account_id = $1 AND collection_key = $2 AND view_id = $3",
            )
            .bind(account_id)
            .bind(collection_key)
            .bind(view_id)
            .execute(&self.pool)
            .await?;
        }
        self.list_saved_view_favorites(account_id, collection_key)
            .await
    }

    pub async fn delete_saved_view_favorites_for_view(
        &self,
        collection_key: &str,
        view_id: &str,
    ) -> Result<(), sqlx::Error> {
        if !self.saved_view_favorite_schema_present().await? {
            return Ok(());
        }
        sqlx::query(
            "DELETE FROM auth_coach_saved_view_favorites \
             WHERE collection_key = $1 AND view_id = $2",
        )
        .bind(collection_key.trim())
        .bind(view_id.trim())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn list_saved_view_usage(
        &self,
        account_id: &str,
        collection_key: &str,
    ) -> Result<HashMap<String, String>, sqlx::Error> {
        if !self.saved_view_usage_schema_present().await? {
            return Ok(HashMap::new());
        }

        let rows = sqlx::query(
            "SELECT view_id, used_at::text AS used_at_iso \
             FROM auth_coach_saved_view_usage \
             WHERE account_id = $1 AND collection_key = $2 \
             ORDER BY used_at DESC, view_id DESC",
        )
        .bind(account_id.trim())
        .bind(collection_key.trim())
        .fetch_all(&self.pool)
        .await?;
        let mut usage = HashMap::new();
        for row in rows {
            let view_id = row
                .try_get::<String, _>("view_id")
                .unwrap_or_default()
                .trim()
                .to_string();
            let used_at_iso = row
                .try_get::<String, _>("used_at_iso")
                .unwrap_or_default()
                .trim()
                .to_string();
            if view_id.is_empty() || used_at_iso.is_empty() {
                continue;
            }
            usage.insert(view_id, used_at_iso);
        }
        Ok(usage)
    }

    pub async fn mark_saved_view_used(
        &self,
        account_id: &str,
        collection_key: &str,
        view_id: &str,
        used_at_iso: &str,
    ) -> Result<HashMap<String, String>, sqlx::Error> {
        if !self.saved_view_usage_schema_present().await? {
            return Ok(HashMap::new());
        }

        let account_id = account_id.trim();
        let collection_key = collection_key.trim();
        let view_id = view_id.trim();
        let used_at_iso = used_at_iso.trim();
        if account_id.is_empty() || collection_key.is_empty() || view_id.is_empty() {
            return self.list_saved_view_usage(account_id, collection_key).await;
        }

        sqlx::query(
            "INSERT INTO auth_coach_saved_view_usage \
             (account_id, collection_key, view_id, created_at, used_at, updated_at) \
             VALUES ($1, $2, $3, $4::timestamptz, $5::timestamptz, $6::timestamptz) \
             ON CONFLICT (account_id, collection_key, view_id) DO UPDATE SET \
                used_at = EXCLUDED.used_at, \
                updated_at = EXCLUDED.updated_at",
        )
        .bind(account_id)
        .bind(collection_key)
        .bind(view_id)
        .bind(used_at_iso)
        .bind(used_at_iso)
        .bind(used_at_iso)
        .execute(&self.pool)
        .await?;

        self.list_saved_view_usage(account_id, collection_key).await
    }

    pub async fn delete_saved_view_usage_for_view(
        &self,
        collection_key: &str,
        view_id: &str,
    ) -> Result<(), sqlx::Error> {
        if !self.saved_view_usage_schema_present().await? {
            return Ok(());
        }
        sqlx::query(
            "DELETE FROM auth_coach_saved_view_usage \
             WHERE collection_key = $1 AND view_id = $2",
        )
        .bind(collection_key.trim())
        .bind(view_id.trim())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn insert_import_run(
        &self,
        import_run: &CoachCatalogImportRun,
    ) -> Result<(), sqlx::Error> {
        if !self.import_run_schema_present().await? {
            return Ok(());
        }

        sqlx::query(
            "INSERT INTO auth_coach_catalog_import_runs \
             (import_run_id, feed_kind, source_kind, trigger_kind, feed_locator, operator_ids, replayed_from_import_run_id, source_artifact_id, status, \
              started_at, finished_at, operator_count, city_count, stop_cluster_count, stop_count, \
              line_count, service_calendar_count, trip_count, fare_product_count, error_message) \
             VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9, $10::timestamptz, $11::timestamptz, $12, $13, $14, $15, \
                     $16, $17, $18, $19, $20) \
             ON CONFLICT (import_run_id) DO UPDATE SET \
               feed_kind=EXCLUDED.feed_kind, \
               source_kind=EXCLUDED.source_kind, \
               trigger_kind=EXCLUDED.trigger_kind, \
               feed_locator=EXCLUDED.feed_locator, \
               operator_ids=EXCLUDED.operator_ids, \
               replayed_from_import_run_id=EXCLUDED.replayed_from_import_run_id, \
               source_artifact_id=EXCLUDED.source_artifact_id, \
               status=EXCLUDED.status, \
               started_at=EXCLUDED.started_at, \
               finished_at=EXCLUDED.finished_at, \
               operator_count=EXCLUDED.operator_count, \
               city_count=EXCLUDED.city_count, \
               stop_cluster_count=EXCLUDED.stop_cluster_count, \
               stop_count=EXCLUDED.stop_count, \
               line_count=EXCLUDED.line_count, \
               service_calendar_count=EXCLUDED.service_calendar_count, \
               trip_count=EXCLUDED.trip_count, \
               fare_product_count=EXCLUDED.fare_product_count, \
               error_message=EXCLUDED.error_message, \
               updated_at=NOW()",
        )
        .bind(import_run.import_run_id.trim())
        .bind(import_run.feed_kind.trim())
        .bind(import_run.source_kind.trim())
        .bind(import_run.trigger_kind.trim())
        .bind(import_run.feed_locator.as_deref().map(str::trim))
        .bind(json!(coach_catalog_normalize_string_list(&import_run.operator_ids)))
        .bind(
            import_run
                .replayed_from_import_run_id
                .as_deref()
                .map(str::trim),
        )
        .bind(import_run.source_artifact_id.as_deref().map(str::trim))
        .bind(import_run.status.trim())
        .bind(import_run.started_at_iso.trim())
        .bind(import_run.finished_at_iso.as_deref().map(str::trim))
        .bind(import_run.counts.operators)
        .bind(import_run.counts.cities)
        .bind(import_run.counts.stop_clusters)
        .bind(import_run.counts.stops)
        .bind(import_run.counts.lines)
        .bind(import_run.counts.service_calendars)
        .bind(import_run.counts.trips)
        .bind(import_run.counts.fare_products)
        .bind(import_run.error_message.as_deref().map(str::trim))
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn finalize_import_run(
        &self,
        import_run_id: &str,
        status: &str,
        finished_at_iso: &str,
        counts: &CoachCatalogCounts,
        operator_ids: &[String],
        error_message: Option<&str>,
    ) -> Result<(), sqlx::Error> {
        if !self.import_run_schema_present().await? {
            return Ok(());
        }

        let normalized_operator_ids = coach_catalog_normalize_string_list(operator_ids);

        sqlx::query(
            "UPDATE auth_coach_catalog_import_runs \
             SET status=$2, \
                 finished_at=$3::timestamptz, \
                 operator_count=$4, \
                 city_count=$5, \
                 stop_cluster_count=$6, \
                 stop_count=$7, \
                 line_count=$8, \
                 service_calendar_count=$9, \
                 trip_count=$10, \
                 fare_product_count=$11, \
                 error_message=$12, \
                 operator_ids=$13::jsonb, \
                 updated_at=NOW() \
             WHERE import_run_id=$1",
        )
        .bind(import_run_id.trim())
        .bind(status.trim())
        .bind(finished_at_iso.trim())
        .bind(counts.operators)
        .bind(counts.cities)
        .bind(counts.stop_clusters)
        .bind(counts.stops)
        .bind(counts.lines)
        .bind(counts.service_calendars)
        .bind(counts.trips)
        .bind(counts.fare_products)
        .bind(error_message.map(str::trim))
        .bind(json!(normalized_operator_ids))
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn replace_import_run_issues(
        &self,
        import_run_id: &str,
        issues: &[CoachCatalogImportRunIssue],
    ) -> Result<(), sqlx::Error> {
        if !self.import_run_issue_schema_present().await? {
            return Ok(());
        }

        sqlx::query("DELETE FROM auth_coach_catalog_import_run_issues WHERE import_run_id = $1")
            .bind(import_run_id.trim())
            .execute(&self.pool)
            .await?;

        for issue in issues {
            sqlx::query(
                "INSERT INTO auth_coach_catalog_import_run_issues \
                 (issue_id, import_run_id, severity, stage, code, message, file_name, row_reference) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
            )
            .bind(issue.issue_id.trim())
            .bind(issue.import_run_id.trim())
            .bind(issue.severity.trim())
            .bind(issue.stage.trim())
            .bind(issue.code.trim())
            .bind(issue.message.trim())
            .bind(issue.file_name.as_deref().map(str::trim))
            .bind(issue.row_reference.as_deref().map(str::trim))
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    pub async fn list_import_runs(&self) -> Result<Vec<CoachCatalogImportRun>, sqlx::Error> {
        if !self.import_run_schema_present().await? {
            return Ok(Vec::new());
        }

        let rows = if self.source_artifact_schema_present().await? {
            sqlx::query(
                "SELECT \
                    import_run.import_run_id, import_run.feed_kind, import_run.source_kind, import_run.trigger_kind, \
                    import_run.feed_locator, import_run.operator_ids, import_run.replayed_from_import_run_id, import_run.source_artifact_id, import_run.status, \
                    import_run.started_at::text AS started_at_iso, import_run.finished_at::text AS finished_at_iso, \
                    import_run.operator_count, import_run.city_count, import_run.stop_cluster_count, import_run.stop_count, \
                    import_run.line_count, import_run.service_calendar_count, import_run.trip_count, \
                    import_run.fare_product_count, import_run.error_message, \
                    artifact.artifact_id AS source_artifact_artifact_id, \
                    artifact.feed_kind AS source_artifact_feed_kind, \
                    artifact.source_kind AS source_artifact_source_kind, \
                    artifact.source_label AS source_artifact_source_label, \
                    artifact.file_name AS source_artifact_file_name, \
                    artifact.file_checksum_sha256 AS source_artifact_file_checksum_sha256, \
                    artifact.content_length_bytes AS source_artifact_content_length_bytes, \
                    artifact.extracted_file_count AS source_artifact_extracted_file_count, \
                    artifact.feed_locator AS source_artifact_feed_locator, \
                    artifact.operator_ids AS source_artifact_operator_ids, \
                    artifact.created_by_account_id AS source_artifact_created_by_account_id, \
                    artifact.created_at::text AS source_artifact_created_at_iso \
                 FROM auth_coach_catalog_import_runs import_run \
                 LEFT JOIN auth_coach_catalog_source_artifacts artifact \
                   ON artifact.artifact_id = import_run.source_artifact_id \
                 ORDER BY import_run.started_at DESC, import_run.import_run_id DESC",
            )
            .fetch_all(&self.pool)
            .await?
        } else {
            sqlx::query(
                "SELECT \
                    import_run_id, feed_kind, source_kind, trigger_kind, feed_locator, operator_ids, replayed_from_import_run_id, status, \
                    started_at::text AS started_at_iso, finished_at::text AS finished_at_iso, \
                    operator_count, city_count, stop_cluster_count, stop_count, line_count, \
                    service_calendar_count, trip_count, fare_product_count, error_message \
                 FROM auth_coach_catalog_import_runs \
                 ORDER BY started_at DESC, import_run_id DESC",
            )
            .fetch_all(&self.pool)
            .await?
        };

        let mut import_runs = rows
            .into_iter()
            .map(Self::map_import_run_row)
            .collect::<Result<Vec<_>, _>>()?;

        if !self.import_run_issue_schema_present().await? || import_runs.is_empty() {
            return Ok(import_runs);
        }

        let import_run_ids = import_runs
            .iter()
            .map(|entry| entry.import_run_id.clone())
            .collect::<Vec<_>>();
        let issue_rows = sqlx::query(
            "SELECT \
                issue_id, import_run_id, severity, stage, code, message, file_name, row_reference \
             FROM auth_coach_catalog_import_run_issues \
             WHERE import_run_id = ANY($1) \
             ORDER BY import_run_id ASC, created_at ASC, issue_id ASC",
        )
        .bind(&import_run_ids)
        .fetch_all(&self.pool)
        .await?;

        let mut issues_by_run =
            std::collections::HashMap::<String, Vec<CoachCatalogImportRunIssue>>::new();
        for row in issue_rows {
            let issue = Self::map_import_run_issue_row(row)?;
            issues_by_run
                .entry(issue.import_run_id.clone())
                .or_default()
                .push(issue);
        }

        for import_run in &mut import_runs {
            import_run.issues = issues_by_run
                .remove(import_run.import_run_id.as_str())
                .unwrap_or_default();
        }

        Ok(import_runs)
    }

    pub async fn find_import_run_by_id(
        &self,
        import_run_id: &str,
    ) -> Result<Option<CoachCatalogImportRun>, sqlx::Error> {
        let Some(mut import_run) = self.find_import_run_head_by_id(import_run_id).await? else {
            return Ok(None);
        };

        import_run.issues = self
            .list_import_run_issues(import_run.import_run_id.as_str())
            .await?;

        Ok(Some(import_run))
    }

    pub async fn find_import_run_head_by_id(
        &self,
        import_run_id: &str,
    ) -> Result<Option<CoachCatalogImportRun>, sqlx::Error> {
        if !self.import_run_schema_present().await? {
            return Ok(None);
        }

        let row = if self.source_artifact_schema_present().await? {
            sqlx::query(
                "SELECT \
                    import_run.import_run_id, import_run.feed_kind, import_run.source_kind, import_run.trigger_kind, \
                    import_run.feed_locator, import_run.operator_ids, import_run.replayed_from_import_run_id, import_run.source_artifact_id, import_run.status, \
                    import_run.started_at::text AS started_at_iso, import_run.finished_at::text AS finished_at_iso, \
                    import_run.operator_count, import_run.city_count, import_run.stop_cluster_count, import_run.stop_count, \
                    import_run.line_count, import_run.service_calendar_count, import_run.trip_count, \
                    import_run.fare_product_count, import_run.error_message, \
                    artifact.artifact_id AS source_artifact_artifact_id, \
                    artifact.feed_kind AS source_artifact_feed_kind, \
                    artifact.source_kind AS source_artifact_source_kind, \
                    artifact.source_label AS source_artifact_source_label, \
                    artifact.file_name AS source_artifact_file_name, \
                    artifact.file_checksum_sha256 AS source_artifact_file_checksum_sha256, \
                    artifact.content_length_bytes AS source_artifact_content_length_bytes, \
                    artifact.extracted_file_count AS source_artifact_extracted_file_count, \
                    artifact.feed_locator AS source_artifact_feed_locator, \
                    artifact.operator_ids AS source_artifact_operator_ids, \
                    artifact.created_by_account_id AS source_artifact_created_by_account_id, \
                    artifact.created_at::text AS source_artifact_created_at_iso \
                 FROM auth_coach_catalog_import_runs import_run \
                 LEFT JOIN auth_coach_catalog_source_artifacts artifact \
                   ON artifact.artifact_id = import_run.source_artifact_id \
                 WHERE import_run.import_run_id = $1 \
                 LIMIT 1",
            )
            .bind(import_run_id.trim())
            .fetch_optional(&self.pool)
            .await?
        } else {
            sqlx::query(
                "SELECT \
                    import_run_id, feed_kind, source_kind, trigger_kind, feed_locator, operator_ids, replayed_from_import_run_id, status, \
                    started_at::text AS started_at_iso, finished_at::text AS finished_at_iso, \
                    operator_count, city_count, stop_cluster_count, stop_count, line_count, \
                    service_calendar_count, trip_count, fare_product_count, error_message \
                 FROM auth_coach_catalog_import_runs \
                 WHERE import_run_id = $1 \
                 LIMIT 1",
            )
            .bind(import_run_id.trim())
            .fetch_optional(&self.pool)
            .await?
        };

        row.map(Self::map_import_run_row).transpose()
    }

    pub async fn list_import_run_issues(
        &self,
        import_run_id: &str,
    ) -> Result<Vec<CoachCatalogImportRunIssue>, sqlx::Error> {
        if !self.import_run_issue_schema_present().await? {
            return Ok(Vec::new());
        }

        let issue_rows = sqlx::query(
            "SELECT \
                issue_id, import_run_id, severity, stage, code, message, file_name, row_reference \
             FROM auth_coach_catalog_import_run_issues \
             WHERE import_run_id = $1 \
             ORDER BY issue_id ASC",
        )
        .bind(import_run_id.trim())
        .fetch_all(&self.pool)
        .await?;

        issue_rows
            .into_iter()
            .map(Self::map_import_run_issue_row)
            .collect::<Result<Vec<_>, _>>()
    }

    async fn catalog_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_catalog_operators").await
    }

    async fn import_run_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_catalog_import_runs").await
    }

    async fn import_run_issue_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_catalog_import_run_issues")
            .await
    }

    async fn import_config_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_catalog_import_configs")
            .await
    }

    async fn source_artifact_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_catalog_source_artifacts")
            .await
    }

    async fn import_run_saved_view_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_catalog_import_run_saved_views")
            .await
    }

    async fn import_run_issue_saved_view_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_catalog_import_run_issue_saved_views")
            .await
    }

    async fn payout_import_batch_saved_view_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_settlement_payout_import_batch_saved_views")
            .await
    }

    async fn payout_import_preview_saved_view_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_settlement_payout_import_preview_saved_views")
            .await
    }

    async fn saved_view_favorite_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_saved_view_favorites").await
    }

    async fn saved_view_usage_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_saved_view_usage").await
    }

    async fn offer_snapshot_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_offer_snapshots").await
    }

    async fn hold_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_holds").await
    }

    async fn booking_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_bookings").await
    }

    async fn ticket_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_tickets").await
    }

    async fn ticket_artifact_schema_present(&self) -> Result<bool, sqlx::Error> {
        self.table_present("auth_coach_ticket_artifacts").await
    }

    async fn table_present(&self, table: &str) -> Result<bool, sqlx::Error> {
        let row = sqlx::query("SELECT to_regclass($1) IS NOT NULL AS ok")
            .bind(format!("public.{table}"))
            .fetch_one(&self.pool)
            .await?;
        row.try_get("ok")
    }

    async fn count_rows(&self, table: &str) -> Result<i64, sqlx::Error> {
        let sql = format!("SELECT COUNT(*)::bigint AS count FROM {table}");
        let row = sqlx::query(&sql).fetch_one(&self.pool).await?;
        row.try_get("count")
    }

    async fn record_exists_by_key(
        &self,
        table: &str,
        column: &str,
        value: &str,
    ) -> Result<bool, sqlx::Error> {
        let sql =
            format!("SELECT EXISTS (SELECT 1 FROM {table} WHERE {column} = $1) AS exists_flag");
        let row = sqlx::query(&sql)
            .bind(value.trim())
            .fetch_one(&self.pool)
            .await?;
        row.try_get("exists_flag")
    }

    async fn operator_feed_health_exists(
        &self,
        operator_id: &str,
        feed_kind: &str,
    ) -> Result<bool, sqlx::Error> {
        let row = sqlx::query(
            "SELECT EXISTS ( \
                 SELECT 1 FROM auth_coach_catalog_operator_feed_health \
                 WHERE operator_id = $1 AND feed_kind = $2 \
             ) AS exists_flag",
        )
        .bind(operator_id.trim())
        .bind(feed_kind.trim())
        .fetch_one(&self.pool)
        .await?;
        row.try_get("exists_flag")
    }

    fn map_direct_journey_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogDirectJourney, sqlx::Error> {
        Ok(CoachCatalogDirectJourney {
            trip_id: row.try_get("trip_id")?,
            operator_id: row.try_get("operator_id")?,
            operator_name: row.try_get("operator_name")?,
            operator_integration_mode: row.try_get("integration_mode")?,
            line_id: row.try_get("line_id")?,
            line_name: row.try_get("line_name")?,
            origin_city_name: row.try_get("origin_city_name")?,
            destination_city_name: row.try_get("destination_city_name")?,
            origin_stop_cluster_id: row.try_get("origin_stop_cluster_id")?,
            destination_stop_cluster_id: row.try_get("destination_stop_cluster_id")?,
            departure_time_local: row.try_get("departure_time_local")?,
            arrival_time_local: row.try_get("arrival_time_local")?,
            duration_minutes: row.try_get("duration_minutes")?,
            service_timezone: row.try_get("service_timezone")?,
            seats_available: row.try_get("seats_available")?,
            amenities: json_string_vec_from_value(
                row.try_get::<Value, _>("amenities_json")
                    .unwrap_or_else(|_| json!([])),
            ),
            fare_product_id: row.try_get("fare_product_id")?,
            currency: row.try_get("currency")?,
            price_minor_units: row.try_get("price_minor_units")?,
            hold_supported: row.try_get("hold_supported")?,
            changeable: row.try_get("changeable")?,
            refundable: row.try_get("refundable")?,
            baggage_rule: row.try_get("baggage_rule")?,
        })
    }

    fn map_offer_basis_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogOfferBasis, sqlx::Error> {
        Ok(CoachCatalogOfferBasis {
            fare_product_id: row.try_get("fare_product_id")?,
            trip_id: row.try_get("trip_id")?,
            operator_id: row.try_get("operator_id")?,
            operator_name: row.try_get("operator_name")?,
            operator_integration_mode: row.try_get("integration_mode")?,
            currency: row.try_get("currency")?,
            price_minor_units: row.try_get("price_minor_units")?,
            hold_supported: row.try_get("hold_supported")?,
            changeable: row.try_get("changeable")?,
            refundable: row.try_get("refundable")?,
            baggage_rule: row.try_get("baggage_rule")?,
            seats_available: row.try_get("seats_available")?,
            amenities: json_string_vec_from_value(
                row.try_get::<Value, _>("amenities_json")
                    .unwrap_or_else(|_| json!([])),
            ),
        })
    }

    fn map_journey_summary_basis_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogJourneySummaryBasis, sqlx::Error> {
        Ok(CoachCatalogJourneySummaryBasis {
            trip_id: row.try_get("trip_id")?,
            operator_name: row.try_get("operator_name")?,
            origin_city_name: row.try_get("origin_city_name")?,
            destination_city_name: row.try_get("destination_city_name")?,
            departure_time_local: row.try_get("departure_time_local")?,
            arrival_time_local: row.try_get("arrival_time_local")?,
            duration_minutes: row.try_get("duration_minutes")?,
            service_timezone: row.try_get("service_timezone")?,
        })
    }

    fn map_operator_feed_health_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogOperatorFeedHealth, sqlx::Error> {
        Ok(CoachCatalogOperatorFeedHealth {
            operator_id: row.try_get("operator_id")?,
            operator_name: row.try_get("operator_name")?,
            operator_integration_mode: row.try_get("integration_mode")?,
            feed_kind: row.try_get("feed_kind")?,
            source_kind: row.try_get("source_kind")?,
            sync_status: row.try_get("sync_status")?,
            freshness_status: row.try_get("freshness_status")?,
            last_attempted_at_iso: row.try_get("last_attempted_at_iso")?,
            last_succeeded_at_iso: row.try_get("last_succeeded_at_iso")?,
            freshness_expires_at_iso: row.try_get("freshness_expires_at_iso")?,
            records_ingested: row.try_get("records_ingested")?,
            error_message: row.try_get("error_message")?,
        })
    }

    fn map_operator_row(row: sqlx::postgres::PgRow) -> Result<CoachCatalogOperator, sqlx::Error> {
        Ok(CoachCatalogOperator {
            operator_id: row.try_get("operator_id")?,
            display_name: row.try_get("display_name")?,
            integration_mode: row.try_get("integration_mode")?,
            country_code: row.try_get("country_code")?,
            active: row.try_get("active")?,
        })
    }

    fn map_source_artifact_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogSourceArtifact, sqlx::Error> {
        Ok(CoachCatalogSourceArtifact {
            artifact_id: row.try_get("artifact_id")?,
            feed_kind: row.try_get("feed_kind")?,
            source_kind: row.try_get("source_kind")?,
            source_label: row.try_get("source_label")?,
            file_name: row.try_get("file_name")?,
            file_checksum_sha256: row.try_get("file_checksum_sha256")?,
            content_length_bytes: row.try_get("content_length_bytes")?,
            extracted_file_count: row.try_get("extracted_file_count")?,
            feed_locator: row.try_get("feed_locator")?,
            operator_ids: coach_catalog_string_array_from_json(
                row.try_get::<Value, _>("operator_ids")
                    .unwrap_or_else(|_| json!([])),
            )?,
            created_by_account_id: row.try_get("created_by_account_id")?,
            created_at_iso: row.try_get("created_at_iso")?,
        })
    }

    fn map_source_artifact_from_prefixed_row(
        row: &sqlx::postgres::PgRow,
        prefix: &str,
    ) -> Option<CoachCatalogSourceArtifact> {
        let artifact_id = row
            .try_get::<Option<String>, _>(format!("{prefix}artifact_id").as_str())
            .ok()
            .flatten()?;
        Some(CoachCatalogSourceArtifact {
            artifact_id,
            feed_kind: row
                .try_get::<Option<String>, _>(format!("{prefix}feed_kind").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            source_kind: row
                .try_get::<Option<String>, _>(format!("{prefix}source_kind").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            source_label: row
                .try_get::<Option<String>, _>(format!("{prefix}source_label").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            file_name: row
                .try_get::<Option<String>, _>(format!("{prefix}file_name").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            file_checksum_sha256: row
                .try_get::<Option<String>, _>(format!("{prefix}file_checksum_sha256").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            content_length_bytes: row
                .try_get::<Option<i64>, _>(format!("{prefix}content_length_bytes").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            extracted_file_count: row
                .try_get::<Option<i64>, _>(format!("{prefix}extracted_file_count").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            feed_locator: row
                .try_get::<Option<String>, _>(format!("{prefix}feed_locator").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            operator_ids: coach_catalog_string_array_from_json(
                row.try_get::<Option<Value>, _>(format!("{prefix}operator_ids").as_str())
                    .ok()
                    .flatten()
                    .unwrap_or_else(|| json!([])),
            )
            .ok()
            .unwrap_or_default(),
            created_by_account_id: row
                .try_get::<Option<String>, _>(format!("{prefix}created_by_account_id").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
            created_at_iso: row
                .try_get::<Option<String>, _>(format!("{prefix}created_at_iso").as_str())
                .ok()
                .flatten()
                .unwrap_or_default(),
        })
    }

    fn map_import_run_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogImportRun, sqlx::Error> {
        let source_artifact_id = row
            .try_get::<Option<String>, _>("source_artifact_id")
            .ok()
            .flatten();
        let replayed_from_import_run_id = row
            .try_get::<Option<String>, _>("replayed_from_import_run_id")
            .ok()
            .flatten();
        let source_artifact = Self::map_source_artifact_from_prefixed_row(&row, "source_artifact_");
        let operator_ids = coach_catalog_string_array_from_json(
            row.try_get::<Value, _>("operator_ids")
                .unwrap_or_else(|_| json!([])),
        )?;
        Ok(CoachCatalogImportRun {
            import_run_id: row.try_get("import_run_id")?,
            feed_kind: row.try_get("feed_kind")?,
            source_kind: row.try_get("source_kind")?,
            trigger_kind: row.try_get("trigger_kind")?,
            feed_locator: row.try_get("feed_locator")?,
            operator_ids,
            replayed_from_import_run_id,
            source_artifact_id: source_artifact_id.or_else(|| {
                source_artifact
                    .as_ref()
                    .map(|value| value.artifact_id.clone())
            }),
            source_artifact,
            status: row.try_get("status")?,
            started_at_iso: row.try_get("started_at_iso")?,
            finished_at_iso: row.try_get("finished_at_iso")?,
            counts: CoachCatalogCounts {
                operators: row.try_get("operator_count")?,
                cities: row.try_get("city_count")?,
                stop_clusters: row.try_get("stop_cluster_count")?,
                stops: row.try_get("stop_count")?,
                lines: row.try_get("line_count")?,
                service_calendars: row.try_get("service_calendar_count")?,
                trips: row.try_get("trip_count")?,
                fare_products: row.try_get("fare_product_count")?,
            },
            error_message: row.try_get("error_message")?,
            issues: Vec::new(),
        })
    }

    fn map_import_run_issue_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogImportRunIssue, sqlx::Error> {
        Ok(CoachCatalogImportRunIssue {
            issue_id: row.try_get("issue_id")?,
            import_run_id: row.try_get("import_run_id")?,
            severity: row.try_get("severity")?,
            stage: row.try_get("stage")?,
            code: row.try_get("code")?,
            message: row.try_get("message")?,
            file_name: row.try_get("file_name")?,
            row_reference: row.try_get("row_reference")?,
        })
    }

    fn map_import_config_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogImportConfig, sqlx::Error> {
        let source_artifact_id = row
            .try_get::<Option<String>, _>("source_artifact_id")
            .ok()
            .flatten();
        let source_artifact = Self::map_source_artifact_from_prefixed_row(&row, "source_artifact_");
        Ok(CoachCatalogImportConfig {
            feed_kind: row.try_get("feed_kind")?,
            source_kind: row.try_get("source_kind")?,
            feed_locator: row.try_get("feed_locator")?,
            source_artifact_id: source_artifact_id.or_else(|| {
                source_artifact
                    .as_ref()
                    .map(|value| value.artifact_id.clone())
            }),
            source_artifact,
            updated_by_account_id: row.try_get("updated_by_account_id")?,
            updated_at_iso: row.try_get("updated_at_iso")?,
        })
    }

    fn map_import_run_saved_view_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogImportRunSavedView, sqlx::Error> {
        Ok(CoachCatalogImportRunSavedView {
            view_id: row.try_get("view_id")?,
            account_id: row.try_get("account_id")?,
            visibility_scope: row.try_get("visibility_scope")?,
            name: row.try_get("name")?,
            operator_ids: coach_catalog_string_array_from_json(row.try_get("operator_ids")?)?,
            status_filter: row.try_get("status_filter")?,
            replay_scope_filter: row.try_get("replay_scope_filter")?,
            issue_severity_filter: row.try_get("issue_severity_filter")?,
            issue_stage_filter: row.try_get("issue_stage_filter")?,
            is_default: row.try_get("is_default")?,
            created_at_iso: row.try_get("created_at_iso")?,
            updated_at_iso: row.try_get("updated_at_iso")?,
        })
    }

    fn map_import_run_issue_saved_view_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachCatalogImportRunIssueSavedView, sqlx::Error> {
        Ok(CoachCatalogImportRunIssueSavedView {
            view_id: row.try_get("view_id")?,
            account_id: row.try_get("account_id")?,
            visibility_scope: row.try_get("visibility_scope")?,
            name: row.try_get("name")?,
            operator_ids: coach_catalog_string_array_from_json(row.try_get("operator_ids")?)?,
            severity_filter: row.try_get("severity_filter")?,
            stage_filter: row.try_get("stage_filter")?,
            is_default: row.try_get("is_default")?,
            created_at_iso: row.try_get("created_at_iso")?,
            updated_at_iso: row.try_get("updated_at_iso")?,
        })
    }

    fn map_payout_import_batch_saved_view_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachPayoutImportBatchSavedView, sqlx::Error> {
        Ok(CoachPayoutImportBatchSavedView {
            view_id: row.try_get("view_id")?,
            account_id: row.try_get("account_id")?,
            visibility_scope: row.try_get("visibility_scope")?,
            name: row.try_get("name")?,
            operator_id: row.try_get("operator_id")?,
            is_default: row.try_get("is_default")?,
            created_at_iso: row.try_get("created_at_iso")?,
            updated_at_iso: row.try_get("updated_at_iso")?,
        })
    }

    fn map_payout_import_preview_saved_view_row(
        row: sqlx::postgres::PgRow,
    ) -> Result<CoachPayoutImportPreviewSavedView, sqlx::Error> {
        Ok(CoachPayoutImportPreviewSavedView {
            view_id: row.try_get("view_id")?,
            account_id: row.try_get("account_id")?,
            visibility_scope: row.try_get("visibility_scope")?,
            name: row.try_get("name")?,
            status_filter: row.try_get("status_filter")?,
            from_created_at_iso: row.try_get("from_created_at_iso")?,
            to_created_at_iso: row.try_get("to_created_at_iso")?,
            operator_id: row.try_get("operator_id")?,
            is_default: row.try_get("is_default")?,
            created_at_iso: row.try_get("created_at_iso")?,
            updated_at_iso: row.try_get("updated_at_iso")?,
        })
    }
}

fn coach_catalog_counts_total(counts: &CoachCatalogCounts) -> i64 {
    counts.total_records()
}

fn pilot_city_aliases() -> Vec<CoachCatalogCityAlias> {
    vec![
        CoachCatalogCityAlias {
            city_alias_id: "city_alias_damascus_native".to_string(),
            city_id: "city_damascus".to_string(),
            alias_name: "دمشق".to_string(),
            active: true,
        },
        CoachCatalogCityAlias {
            city_alias_id: "city_alias_damascus_dimashq".to_string(),
            city_id: "city_damascus".to_string(),
            alias_name: "Dimashq".to_string(),
            active: true,
        },
        CoachCatalogCityAlias {
            city_alias_id: "city_alias_homs_native".to_string(),
            city_id: "city_homs".to_string(),
            alias_name: "حمص".to_string(),
            active: true,
        },
        CoachCatalogCityAlias {
            city_alias_id: "city_alias_aleppo_native".to_string(),
            city_id: "city_aleppo".to_string(),
            alias_name: "حلب".to_string(),
            active: true,
        },
        CoachCatalogCityAlias {
            city_alias_id: "city_alias_aleppo_halab".to_string(),
            city_id: "city_aleppo".to_string(),
            alias_name: "Halab".to_string(),
            active: true,
        },
    ]
}

fn pilot_stop_cluster_aliases() -> Vec<CoachCatalogStopClusterAlias> {
    vec![
        CoachCatalogStopClusterAlias {
            stop_cluster_alias_id: "cluster_alias_damascus_bus_station".to_string(),
            stop_cluster_id: "cluster_damascus_central".to_string(),
            city_id: "city_damascus".to_string(),
            alias_name: "Damascus Bus Station".to_string(),
            active: true,
        },
        CoachCatalogStopClusterAlias {
            stop_cluster_alias_id: "cluster_alias_damascus_native".to_string(),
            stop_cluster_id: "cluster_damascus_central".to_string(),
            city_id: "city_damascus".to_string(),
            alias_name: "محطة دمشق المركزية".to_string(),
            active: true,
        },
        CoachCatalogStopClusterAlias {
            stop_cluster_alias_id: "cluster_alias_homs_bus_station".to_string(),
            stop_cluster_id: "cluster_homs_gateway".to_string(),
            city_id: "city_homs".to_string(),
            alias_name: "Homs Bus Station".to_string(),
            active: true,
        },
        CoachCatalogStopClusterAlias {
            stop_cluster_alias_id: "cluster_alias_aleppo_terminal_marketing".to_string(),
            stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            city_id: "city_aleppo".to_string(),
            alias_name: "Aleppo Central Bus Terminal".to_string(),
            active: true,
        },
        CoachCatalogStopClusterAlias {
            stop_cluster_alias_id: "cluster_alias_aleppo_native".to_string(),
            stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            city_id: "city_aleppo".to_string(),
            alias_name: "محطة حلب المركزية".to_string(),
            active: true,
        },
    ]
}

type PilotFeedHealthRow = (
    &'static str,
    &'static str,
    &'static str,
    &'static str,
    &'static str,
    Option<&'static str>,
    Option<&'static str>,
    Option<&'static str>,
    i64,
    Option<&'static str>,
);

fn pilot_operator_feed_health() -> Vec<PilotFeedHealthRow> {
    vec![
        (
            "op_demo_express",
            "static_catalog",
            "manual_seed",
            "ok",
            "fresh",
            Some("2026-04-09T07:00:00Z"),
            Some("2026-04-09T07:00:00Z"),
            Some("2026-04-10T07:00:00Z"),
            4,
            None,
        ),
        (
            "op_demo_express",
            "gtfs_rt_trip_updates",
            "manual_seed",
            "ok",
            "fresh",
            Some("2026-04-09T07:55:00Z"),
            Some("2026-04-09T07:55:00Z"),
            Some("2026-04-09T07:56:30Z"),
            4,
            None,
        ),
        (
            "op_demo_express",
            "gtfs_rt_vehicle_positions",
            "manual_seed",
            "ok",
            "fresh",
            Some("2026-04-09T07:55:10Z"),
            Some("2026-04-09T07:55:10Z"),
            Some("2026-04-09T07:56:40Z"),
            2,
            None,
        ),
        (
            "op_demo_express",
            "gtfs_rt_service_alerts",
            "manual_seed",
            "ok",
            "fresh",
            Some("2026-04-09T07:45:00Z"),
            Some("2026-04-09T07:45:00Z"),
            Some("2026-04-09T17:45:00Z"),
            1,
            None,
        ),
        (
            "op_northern_connector",
            "static_catalog",
            "manual_seed",
            "ok",
            "fresh",
            Some("2026-04-09T07:00:00Z"),
            Some("2026-04-09T07:00:00Z"),
            Some("2026-04-10T07:00:00Z"),
            4,
            None,
        ),
        (
            "op_northern_connector",
            "gtfs_rt_trip_updates",
            "manual_seed",
            "ok",
            "fresh",
            Some("2026-04-09T07:54:30Z"),
            Some("2026-04-09T07:54:30Z"),
            Some("2026-04-09T07:56:00Z"),
            2,
            None,
        ),
        (
            "op_northern_connector",
            "gtfs_rt_vehicle_positions",
            "manual_seed",
            "degraded",
            "missing",
            Some("2026-04-09T07:40:00Z"),
            None,
            None,
            0,
            Some("vehicle positions not exposed by feed-only pilot operator"),
        ),
        (
            "op_northern_connector",
            "gtfs_rt_service_alerts",
            "manual_seed",
            "ok",
            "fresh",
            Some("2026-04-09T07:40:00Z"),
            Some("2026-04-09T07:40:00Z"),
            Some("2026-04-09T17:40:00Z"),
            0,
            None,
        ),
    ]
}

async fn ensure_seed_pilot_aliases(repo: &CoachCatalogRepository) -> Result<bool, sqlx::Error> {
    let mut wrote_any = false;

    for alias in pilot_city_aliases() {
        if repo
            .record_exists_by_key("auth_coach_catalog_cities", "city_id", &alias.city_id)
            .await?
            && !repo
                .record_exists_by_key(
                    "auth_coach_catalog_city_aliases",
                    "city_alias_id",
                    &alias.city_alias_id,
                )
                .await?
        {
            repo.upsert_city_alias(&alias).await?;
            wrote_any = true;
        }
    }

    for alias in pilot_stop_cluster_aliases() {
        if repo
            .record_exists_by_key(
                "auth_coach_catalog_stop_clusters",
                "stop_cluster_id",
                &alias.stop_cluster_id,
            )
            .await?
            && !repo
                .record_exists_by_key(
                    "auth_coach_catalog_stop_cluster_aliases",
                    "stop_cluster_alias_id",
                    &alias.stop_cluster_alias_id,
                )
                .await?
        {
            repo.upsert_stop_cluster_alias(&alias).await?;
            wrote_any = true;
        }
    }

    Ok(wrote_any)
}

async fn ensure_seed_pilot_feed_health(repo: &CoachCatalogRepository) -> Result<bool, sqlx::Error> {
    let mut wrote_any = false;

    for (
        operator_id,
        feed_kind,
        source_kind,
        sync_status,
        freshness_status,
        last_attempted_at_iso,
        last_succeeded_at_iso,
        freshness_expires_at_iso,
        records_ingested,
        error_message,
    ) in pilot_operator_feed_health()
    {
        if repo
            .record_exists_by_key("auth_coach_catalog_operators", "operator_id", operator_id)
            .await?
            && !repo
                .operator_feed_health_exists(operator_id, feed_kind)
                .await?
        {
            repo.upsert_operator_feed_health(&CoachOperatorFeedHealthUpsert {
                operator_id,
                feed_kind,
                source_kind,
                sync_status,
                freshness_status,
                last_attempted_at_iso,
                last_succeeded_at_iso,
                freshness_expires_at_iso,
                records_ingested,
                error_message,
            })
            .await?;
            wrote_any = true;
        }
    }

    Ok(wrote_any)
}

async fn ensure_seed_pilot_catalog(repo: &CoachCatalogRepository) -> Result<bool, sqlx::Error> {
    let counts = repo.counts_best_effort().await?;
    if coach_catalog_counts_total(&counts) > 0 {
        let alias_seeded = ensure_seed_pilot_aliases(repo).await?;
        let feed_health_seeded = ensure_seed_pilot_feed_health(repo).await?;
        return Ok(alias_seeded || feed_health_seeded);
    }

    for operator in [
        CoachCatalogOperator {
            operator_id: "op_demo_express".to_string(),
            display_name: "Demo Express".to_string(),
            integration_mode: "hybrid".to_string(),
            country_code: Some("SY".to_string()),
            active: true,
        },
        CoachCatalogOperator {
            operator_id: "op_northern_connector".to_string(),
            display_name: "Northern Connector".to_string(),
            integration_mode: "feed".to_string(),
            country_code: Some("SY".to_string()),
            active: true,
        },
    ] {
        repo.upsert_operator(&operator).await?;
    }

    for city in [
        CoachCatalogCity {
            city_id: "city_damascus".to_string(),
            display_name: "Damascus".to_string(),
            country_code: "SY".to_string(),
            timezone_name: "Asia/Damascus".to_string(),
            active: true,
        },
        CoachCatalogCity {
            city_id: "city_homs".to_string(),
            display_name: "Homs".to_string(),
            country_code: "SY".to_string(),
            timezone_name: "Asia/Damascus".to_string(),
            active: true,
        },
        CoachCatalogCity {
            city_id: "city_aleppo".to_string(),
            display_name: "Aleppo".to_string(),
            country_code: "SY".to_string(),
            timezone_name: "Asia/Damascus".to_string(),
            active: true,
        },
    ] {
        repo.upsert_city(&city).await?;
    }

    for city_alias in pilot_city_aliases() {
        repo.upsert_city_alias(&city_alias).await?;
    }

    for cluster in [
        CoachCatalogStopCluster {
            stop_cluster_id: "cluster_damascus_central".to_string(),
            city_id: "city_damascus".to_string(),
            canonical_name: "Damascus Central".to_string(),
            lat: Some(33.5138),
            lon: Some(36.2765),
            active: true,
        },
        CoachCatalogStopCluster {
            stop_cluster_id: "cluster_homs_gateway".to_string(),
            city_id: "city_homs".to_string(),
            canonical_name: "Homs Gateway".to_string(),
            lat: Some(34.7308),
            lon: Some(36.7090),
            active: true,
        },
        CoachCatalogStopCluster {
            stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            city_id: "city_aleppo".to_string(),
            canonical_name: "Aleppo Terminal".to_string(),
            lat: Some(36.2021),
            lon: Some(37.1343),
            active: true,
        },
    ] {
        repo.upsert_stop_cluster(&cluster).await?;
    }

    for cluster_alias in pilot_stop_cluster_aliases() {
        repo.upsert_stop_cluster_alias(&cluster_alias).await?;
    }

    for stop in [
        CoachCatalogStop {
            stop_id: "stop_damascus_central_1".to_string(),
            stop_cluster_id: "cluster_damascus_central".to_string(),
            city_id: "city_damascus".to_string(),
            canonical_name: "Damascus Central Bay 1".to_string(),
            platform_code: Some("1".to_string()),
            lat: Some(33.5138),
            lon: Some(36.2765),
            active: true,
        },
        CoachCatalogStop {
            stop_id: "stop_homs_gateway_3".to_string(),
            stop_cluster_id: "cluster_homs_gateway".to_string(),
            city_id: "city_homs".to_string(),
            canonical_name: "Homs Gateway Bay 3".to_string(),
            platform_code: Some("3".to_string()),
            lat: Some(34.7308),
            lon: Some(36.7090),
            active: true,
        },
        CoachCatalogStop {
            stop_id: "stop_aleppo_terminal_2".to_string(),
            stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            city_id: "city_aleppo".to_string(),
            canonical_name: "Aleppo Terminal Bay 2".to_string(),
            platform_code: Some("2".to_string()),
            lat: Some(36.2021),
            lon: Some(37.1343),
            active: true,
        },
    ] {
        repo.upsert_stop(&stop).await?;
    }

    for line in [
        CoachCatalogLine {
            line_id: "line_demo_dam_ale".to_string(),
            operator_id: "op_demo_express".to_string(),
            public_code: Some("DX100".to_string()),
            marketing_name: "Damascus to Aleppo Express".to_string(),
            vehicle_class: Some("coach".to_string()),
            amenities: vec![
                "wifi".to_string(),
                "power_outlet".to_string(),
                "toilet".to_string(),
            ],
            active: true,
        },
        CoachCatalogLine {
            line_id: "line_northern_dam_ale".to_string(),
            operator_id: "op_northern_connector".to_string(),
            public_code: Some("NC220".to_string()),
            marketing_name: "Damascus to Aleppo Connector".to_string(),
            vehicle_class: Some("coach".to_string()),
            amenities: vec!["wifi".to_string(), "toilet".to_string()],
            active: true,
        },
        CoachCatalogLine {
            line_id: "line_demo_ale_dam".to_string(),
            operator_id: "op_demo_express".to_string(),
            public_code: Some("DX101".to_string()),
            marketing_name: "Aleppo to Damascus Express".to_string(),
            vehicle_class: Some("coach".to_string()),
            amenities: vec![
                "wifi".to_string(),
                "power_outlet".to_string(),
                "toilet".to_string(),
            ],
            active: true,
        },
        CoachCatalogLine {
            line_id: "line_demo_dam_homs".to_string(),
            operator_id: "op_demo_express".to_string(),
            public_code: Some("DX030".to_string()),
            marketing_name: "Damascus to Homs Shuttle".to_string(),
            vehicle_class: Some("coach".to_string()),
            amenities: vec!["wifi".to_string(), "legroom".to_string()],
            active: true,
        },
    ] {
        repo.upsert_line(&line).await?;
    }

    repo.upsert_service_calendar(&CoachCatalogServiceCalendar {
        service_calendar_id: PILOT_SERVICE_CALENDAR_ID.to_string(),
        start_date: "2026-01-01".to_string(),
        end_date: "2027-12-31".to_string(),
        monday: true,
        tuesday: true,
        wednesday: true,
        thursday: true,
        friday: true,
        saturday: true,
        sunday: true,
        active: true,
    })
    .await?;

    for trip in [
        CoachCatalogTrip {
            trip_id: "trip_demo_dam_ale_0800".to_string(),
            operator_id: "op_demo_express".to_string(),
            line_id: "line_demo_dam_ale".to_string(),
            service_calendar_id: PILOT_SERVICE_CALENDAR_ID.to_string(),
            origin_stop_cluster_id: "cluster_damascus_central".to_string(),
            destination_stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            departure_time_local: "08:00".to_string(),
            arrival_time_local: "12:30".to_string(),
            duration_minutes: 270,
            service_timezone: "Asia/Damascus".to_string(),
            seats_total: 49,
            seats_available: 8,
            active: true,
        },
        CoachCatalogTrip {
            trip_id: "trip_northern_dam_ale_1030".to_string(),
            operator_id: "op_northern_connector".to_string(),
            line_id: "line_northern_dam_ale".to_string(),
            service_calendar_id: PILOT_SERVICE_CALENDAR_ID.to_string(),
            origin_stop_cluster_id: "cluster_damascus_central".to_string(),
            destination_stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            departure_time_local: "10:30".to_string(),
            arrival_time_local: "15:05".to_string(),
            duration_minutes: 275,
            service_timezone: "Asia/Damascus".to_string(),
            seats_total: 45,
            seats_available: 4,
            active: true,
        },
        CoachCatalogTrip {
            trip_id: "trip_demo_ale_dam_1700".to_string(),
            operator_id: "op_demo_express".to_string(),
            line_id: "line_demo_ale_dam".to_string(),
            service_calendar_id: PILOT_SERVICE_CALENDAR_ID.to_string(),
            origin_stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            destination_stop_cluster_id: "cluster_damascus_central".to_string(),
            departure_time_local: "17:00".to_string(),
            arrival_time_local: "21:30".to_string(),
            duration_minutes: 270,
            service_timezone: "Asia/Damascus".to_string(),
            seats_total: 49,
            seats_available: 11,
            active: true,
        },
        CoachCatalogTrip {
            trip_id: "trip_demo_dam_homs_0915".to_string(),
            operator_id: "op_demo_express".to_string(),
            line_id: "line_demo_dam_homs".to_string(),
            service_calendar_id: PILOT_SERVICE_CALENDAR_ID.to_string(),
            origin_stop_cluster_id: "cluster_damascus_central".to_string(),
            destination_stop_cluster_id: "cluster_homs_gateway".to_string(),
            departure_time_local: "09:15".to_string(),
            arrival_time_local: "11:05".to_string(),
            duration_minutes: 110,
            service_timezone: "Asia/Damascus".to_string(),
            seats_total: 33,
            seats_available: 16,
            active: true,
        },
    ] {
        repo.upsert_trip(&trip).await?;
    }

    for fare in [
        CoachCatalogFareProduct {
            fare_product_id: "fare_demo_dam_ale_standard".to_string(),
            trip_id: "trip_demo_dam_ale_0800".to_string(),
            fare_name: "Standard".to_string(),
            passenger_type: "adult".to_string(),
            currency: "EUR".to_string(),
            price_minor_units: 4590,
            hold_supported: true,
            changeable: true,
            refundable: true,
            baggage_rule: Some("1 cabin bag and 1 checked bag included".to_string()),
            active: true,
        },
        CoachCatalogFareProduct {
            fare_product_id: "fare_northern_dam_ale_saver".to_string(),
            trip_id: "trip_northern_dam_ale_1030".to_string(),
            fare_name: "Saver".to_string(),
            passenger_type: "adult".to_string(),
            currency: "EUR".to_string(),
            price_minor_units: 3990,
            hold_supported: false,
            changeable: false,
            refundable: false,
            baggage_rule: Some("1 cabin bag included".to_string()),
            active: true,
        },
        CoachCatalogFareProduct {
            fare_product_id: "fare_demo_ale_dam_standard".to_string(),
            trip_id: "trip_demo_ale_dam_1700".to_string(),
            fare_name: "Standard".to_string(),
            passenger_type: "adult".to_string(),
            currency: "EUR".to_string(),
            price_minor_units: 4690,
            hold_supported: true,
            changeable: true,
            refundable: true,
            baggage_rule: Some("1 cabin bag and 1 checked bag included".to_string()),
            active: true,
        },
        CoachCatalogFareProduct {
            fare_product_id: "fare_demo_dam_homs_flex".to_string(),
            trip_id: "trip_demo_dam_homs_0915".to_string(),
            fare_name: "Flex".to_string(),
            passenger_type: "adult".to_string(),
            currency: "EUR".to_string(),
            price_minor_units: 2490,
            hold_supported: true,
            changeable: true,
            refundable: false,
            baggage_rule: Some("1 cabin bag included, checked bag extra".to_string()),
            active: true,
        },
    ] {
        repo.upsert_fare_product(&fare).await?;
    }

    let _ = ensure_seed_pilot_feed_health(repo).await?;

    Ok(true)
}

pub async fn seed_coach_catalog_best_effort(auth: Option<&AuthRuntime>, context: &'static str) {
    let Some(auth) = auth else {
        return;
    };
    let repo = CoachCatalogRepository::new(auth.pool().clone());
    match ensure_seed_pilot_catalog(&repo).await {
        Ok(true) => {
            tracing::info!(
                context,
                "seeded or refreshed pilot coach catalog fixtures for startup discovery and search"
            );
        }
        Ok(false) => {}
        Err(e) => {
            tracing::warn!(
                error = %e,
                context,
                "coach catalog seed failed during startup; continuing without blocking service startup"
            );
        }
    }
}

fn json_string_vec_from_value(value: Value) -> Vec<String> {
    value
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str())
                .map(str::trim)
                .filter(|item| !item.is_empty())
                .map(ToString::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::apply_versioned_auth_schema_migrations;
    use reqwest::Url;
    use sqlx::postgres::PgPoolOptions;
    use std::env;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn catalog_counts_ready_requires_all_core_tables_to_have_rows() {
        let counts = CoachCatalogCounts {
            operators: 1,
            cities: 1,
            stop_clusters: 1,
            stops: 1,
            lines: 1,
            service_calendars: 1,
            trips: 1,
            fare_products: 1,
        };
        assert!(counts.ready());

        let counts = CoachCatalogCounts {
            fare_products: 0,
            ..counts
        };
        assert!(!counts.ready());
    }

    #[test]
    fn catalog_counts_json_exposes_ready_flag_and_counts() {
        let counts = CoachCatalogCounts {
            operators: 1,
            cities: 2,
            stop_clusters: 3,
            stops: 4,
            lines: 5,
            service_calendars: 6,
            trips: 7,
            fare_products: 8,
        };
        let value = counts.as_json();
        assert_eq!(value["operators"], 1);
        assert_eq!(value["fare_products"], 8);
        assert_eq!(value["ready"], true);
    }

    #[test]
    fn catalog_counts_total_is_zero_only_for_empty_catalog() {
        assert_eq!(
            coach_catalog_counts_total(&CoachCatalogCounts::default()),
            0
        );
        assert_eq!(
            coach_catalog_counts_total(&CoachCatalogCounts {
                cities: 1,
                ..CoachCatalogCounts::default()
            }),
            1
        );
    }

    struct LiveCatalogTestDb {
        admin_pool: PgPool,
        pool: PgPool,
        db_name: String,
    }

    impl LiveCatalogTestDb {
        async fn provision_from_env() -> Self {
            let admin_url = env::var("SHAMELL_AUTH_TEST_DB_URL")
                .expect("SHAMELL_AUTH_TEST_DB_URL required for live coach catalog DB tests");
            let admin_pool = PgPoolOptions::new()
                .max_connections(1)
                .connect(&admin_url)
                .await
                .expect("connect live auth admin pool");
            let db_name = format!("shamell_coach_catalog_{}", unique_suffix());
            sqlx::query(&format!("CREATE DATABASE {db_name}"))
                .execute(&admin_pool)
                .await
                .expect("create isolated coach catalog test database");

            let mut parsed = Url::parse(&admin_url).expect("parse SHAMELL_AUTH_TEST_DB_URL");
            parsed.set_path(&db_name);
            parsed.set_query(None);
            parsed.set_fragment(None);
            let pool = PgPoolOptions::new()
                .max_connections(4)
                .connect(parsed.as_str())
                .await
                .expect("connect isolated coach catalog database");
            apply_versioned_auth_schema_migrations(&pool)
                .await
                .expect("apply versioned auth migrations");
            Self {
                admin_pool,
                pool,
                db_name,
            }
        }

        async fn cleanup(self) {
            let Self {
                admin_pool,
                pool,
                db_name,
            } = self;
            pool.close().await;
            sqlx::query(&format!("DROP DATABASE IF EXISTS {db_name} WITH (FORCE)"))
                .execute(&admin_pool)
                .await
                .expect("drop isolated coach catalog database");
            admin_pool.close().await;
        }
    }

    fn unique_suffix() -> String {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time before epoch")
            .as_nanos();
        format!("{:016x}", nanos & 0xffff_ffff_ffff_ffff)
    }

    #[tokio::test]
    #[ignore = "requires SHAMELL_AUTH_TEST_DB_URL and live postgres"]
    async fn repository_upserts_catalog_rows_and_queries_direct_journeys() {
        let db = LiveCatalogTestDb::provision_from_env().await;
        let repo = CoachCatalogRepository::new(db.pool.clone());

        repo.upsert_operator(&CoachCatalogOperator {
            operator_id: "op_demo_express".to_string(),
            display_name: "Demo Express".to_string(),
            integration_mode: "hybrid".to_string(),
            country_code: Some("SY".to_string()),
            active: true,
        })
        .await
        .expect("upsert operator");
        repo.upsert_city(&CoachCatalogCity {
            city_id: "city_damascus".to_string(),
            display_name: "Damascus".to_string(),
            country_code: "SY".to_string(),
            timezone_name: "Asia/Damascus".to_string(),
            active: true,
        })
        .await
        .expect("upsert damascus");
        repo.upsert_city(&CoachCatalogCity {
            city_id: "city_aleppo".to_string(),
            display_name: "Aleppo".to_string(),
            country_code: "SY".to_string(),
            timezone_name: "Asia/Damascus".to_string(),
            active: true,
        })
        .await
        .expect("upsert aleppo");
        repo.upsert_city_alias(&CoachCatalogCityAlias {
            city_alias_id: "city_alias_damascus_native".to_string(),
            city_id: "city_damascus".to_string(),
            alias_name: "دمشق".to_string(),
            active: true,
        })
        .await
        .expect("upsert damascus alias");
        repo.upsert_city_alias(&CoachCatalogCityAlias {
            city_alias_id: "city_alias_aleppo_native".to_string(),
            city_id: "city_aleppo".to_string(),
            alias_name: "حلب".to_string(),
            active: true,
        })
        .await
        .expect("upsert aleppo alias");
        repo.upsert_stop_cluster(&CoachCatalogStopCluster {
            stop_cluster_id: "cluster_damascus_central".to_string(),
            city_id: "city_damascus".to_string(),
            canonical_name: "Damascus Central".to_string(),
            lat: Some(33.5138),
            lon: Some(36.2765),
            active: true,
        })
        .await
        .expect("upsert origin cluster");
        repo.upsert_stop_cluster(&CoachCatalogStopCluster {
            stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            city_id: "city_aleppo".to_string(),
            canonical_name: "Aleppo Terminal".to_string(),
            lat: Some(36.2021),
            lon: Some(37.1343),
            active: true,
        })
        .await
        .expect("upsert destination cluster");
        repo.upsert_stop_cluster_alias(&CoachCatalogStopClusterAlias {
            stop_cluster_alias_id: "cluster_alias_damascus_bus_station".to_string(),
            stop_cluster_id: "cluster_damascus_central".to_string(),
            city_id: "city_damascus".to_string(),
            alias_name: "Damascus Bus Station".to_string(),
            active: true,
        })
        .await
        .expect("upsert origin cluster alias");
        repo.upsert_stop_cluster_alias(&CoachCatalogStopClusterAlias {
            stop_cluster_alias_id: "cluster_alias_aleppo_terminal_marketing".to_string(),
            stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            city_id: "city_aleppo".to_string(),
            alias_name: "Aleppo Central Bus Terminal".to_string(),
            active: true,
        })
        .await
        .expect("upsert destination cluster alias");
        repo.upsert_stop(&CoachCatalogStop {
            stop_id: "stop_damascus_central_1".to_string(),
            stop_cluster_id: "cluster_damascus_central".to_string(),
            city_id: "city_damascus".to_string(),
            canonical_name: "Damascus Central Bay 1".to_string(),
            platform_code: Some("1".to_string()),
            lat: Some(33.5138),
            lon: Some(36.2765),
            active: true,
        })
        .await
        .expect("upsert origin stop");
        repo.upsert_stop(&CoachCatalogStop {
            stop_id: "stop_aleppo_terminal_2".to_string(),
            stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            city_id: "city_aleppo".to_string(),
            canonical_name: "Aleppo Terminal Bay 2".to_string(),
            platform_code: Some("2".to_string()),
            lat: Some(36.2021),
            lon: Some(37.1343),
            active: true,
        })
        .await
        .expect("upsert destination stop");
        repo.upsert_line(&CoachCatalogLine {
            line_id: "line_demo_dam_ale".to_string(),
            operator_id: "op_demo_express".to_string(),
            public_code: Some("DX100".to_string()),
            marketing_name: "Damascus to Aleppo Express".to_string(),
            vehicle_class: Some("coach".to_string()),
            amenities: vec![
                "wifi".to_string(),
                "power_outlet".to_string(),
                "toilet".to_string(),
            ],
            active: true,
        })
        .await
        .expect("upsert line");
        repo.upsert_service_calendar(&CoachCatalogServiceCalendar {
            service_calendar_id: "cal_everyday_apr_2026".to_string(),
            start_date: "2026-04-01".to_string(),
            end_date: "2026-04-30".to_string(),
            monday: true,
            tuesday: true,
            wednesday: true,
            thursday: true,
            friday: true,
            saturday: true,
            sunday: true,
            active: true,
        })
        .await
        .expect("upsert calendar");
        repo.upsert_trip(&CoachCatalogTrip {
            trip_id: "trip_demo_dam_ale_0800".to_string(),
            operator_id: "op_demo_express".to_string(),
            line_id: "line_demo_dam_ale".to_string(),
            service_calendar_id: "cal_everyday_apr_2026".to_string(),
            origin_stop_cluster_id: "cluster_damascus_central".to_string(),
            destination_stop_cluster_id: "cluster_aleppo_terminal".to_string(),
            departure_time_local: "08:00".to_string(),
            arrival_time_local: "12:30".to_string(),
            duration_minutes: 270,
            service_timezone: "Asia/Damascus".to_string(),
            seats_total: 49,
            seats_available: 8,
            active: true,
        })
        .await
        .expect("upsert trip");
        repo.upsert_fare_product(&CoachCatalogFareProduct {
            fare_product_id: "fare_demo_dam_ale_standard".to_string(),
            trip_id: "trip_demo_dam_ale_0800".to_string(),
            fare_name: "Standard".to_string(),
            passenger_type: "adult".to_string(),
            currency: "EUR".to_string(),
            price_minor_units: 4590,
            hold_supported: true,
            changeable: true,
            refundable: true,
            baggage_rule: Some("1 cabin bag and 1 checked bag included".to_string()),
            active: true,
        })
        .await
        .expect("upsert fare");

        let counts = repo.counts_best_effort().await.expect("catalog counts");
        assert!(counts.ready());
        assert_eq!(counts.trips, 1);
        assert_eq!(counts.fare_products, 1);

        let journeys = repo
            .find_direct_journeys_by_city_names("Damascus", "Aleppo", "2026-04-08", 2)
            .await
            .expect("direct journeys");
        assert_eq!(journeys.len(), 1);
        assert_eq!(journeys[0].operator_name, "Demo Express");
        assert_eq!(journeys[0].line_name, "Damascus to Aleppo Express");
        assert_eq!(journeys[0].seats_available, 8);
        assert_eq!(journeys[0].currency, "EUR");
        assert_eq!(journeys[0].price_minor_units, 4590);
        assert_eq!(
            journeys[0].amenities,
            vec!["wifi", "power_outlet", "toilet"]
        );

        let journeys_by_city_alias = repo
            .find_direct_journeys_by_city_names("دمشق", "حلب", "2026-04-08", 2)
            .await
            .expect("direct journeys by city alias");
        assert_eq!(journeys_by_city_alias.len(), 1);
        assert_eq!(journeys_by_city_alias[0].trip_id, "trip_demo_dam_ale_0800");

        let journeys_by_cluster_alias = repo
            .find_direct_journeys_by_city_names(
                "Damascus Bus Station",
                "Aleppo Central Bus Terminal",
                "2026-04-08",
                2,
            )
            .await
            .expect("direct journeys by stop cluster alias");
        assert_eq!(journeys_by_cluster_alias.len(), 1);
        assert_eq!(
            journeys_by_cluster_alias[0].trip_id,
            "trip_demo_dam_ale_0800"
        );

        let offer_basis = repo
            .find_offer_basis_by_fare_product_id("fare_demo_dam_ale_standard")
            .await
            .expect("offer basis")
            .expect("catalog offer basis row");
        assert_eq!(offer_basis.trip_id, "trip_demo_dam_ale_0800");
        assert_eq!(offer_basis.operator_name, "Demo Express");
        assert_eq!(offer_basis.price_minor_units, 4590);
        assert_eq!(
            offer_basis.amenities,
            vec!["wifi", "power_outlet", "toilet"]
        );

        db.cleanup().await;
    }

    #[tokio::test]
    #[ignore = "requires SHAMELL_AUTH_TEST_DB_URL and live postgres"]
    async fn pilot_seed_populates_empty_catalog_once_and_stays_idempotent() {
        let db = LiveCatalogTestDb::provision_from_env().await;
        let repo = CoachCatalogRepository::new(db.pool.clone());

        let first_seed = ensure_seed_pilot_catalog(&repo)
            .await
            .expect("first pilot seed");
        assert!(first_seed);

        let counts = repo.counts_best_effort().await.expect("catalog counts");
        assert!(counts.ready());
        assert_eq!(counts.operators, 2);
        assert_eq!(counts.cities, 3);
        assert_eq!(counts.trips, 4);
        assert_eq!(counts.fare_products, 4);

        let damascus_to_aleppo = repo
            .find_direct_journeys_by_city_names("Damascus", "Aleppo", "2026-04-08", 1)
            .await
            .expect("damascus to aleppo journeys");
        assert_eq!(damascus_to_aleppo.len(), 2);
        assert_eq!(
            damascus_to_aleppo[0].fare_product_id,
            "fare_northern_dam_ale_saver"
        );
        assert_eq!(
            damascus_to_aleppo[1].fare_product_id,
            "fare_demo_dam_ale_standard"
        );

        let alias_resolved = repo
            .find_direct_journeys_by_city_names(
                "دمشق",
                "Aleppo Central Bus Terminal",
                "2026-04-08",
                1,
            )
            .await
            .expect("alias-resolved journeys");
        assert_eq!(alias_resolved.len(), 2);

        let feed_health = repo
            .list_operator_feed_health()
            .await
            .expect("operator feed health");
        assert_eq!(feed_health.len(), 8);
        assert!(feed_health.iter().any(|entry| {
            entry.operator_id == "op_demo_express"
                && entry.feed_kind == "gtfs_rt_trip_updates"
                && entry.freshness_status == "fresh"
        }));
        assert!(feed_health.iter().any(|entry| {
            entry.operator_id == "op_northern_connector"
                && entry.feed_kind == "gtfs_rt_vehicle_positions"
                && entry.sync_status == "degraded"
                && entry.freshness_status == "missing"
        }));

        let second_seed = ensure_seed_pilot_catalog(&repo)
            .await
            .expect("second pilot seed");
        assert!(!second_seed);

        let counts_after_second_seed = repo
            .counts_best_effort()
            .await
            .expect("catalog counts after second seed");
        assert_eq!(counts_after_second_seed.trips, 4);
        assert_eq!(counts_after_second_seed.fare_products, 4);

        db.cleanup().await;
    }

    #[tokio::test]
    #[ignore = "requires SHAMELL_AUTH_TEST_DB_URL and live postgres"]
    async fn repository_persists_catalog_import_run_audit_history() {
        let db = LiveCatalogTestDb::provision_from_env().await;
        let repo = CoachCatalogRepository::new(db.pool.clone());

        repo.insert_import_run(&CoachCatalogImportRun {
            import_run_id: "catalogimportrun_demo_gtfs_1".to_string(),
            feed_kind: "static_catalog".to_string(),
            source_kind: "gtfs".to_string(),
            trigger_kind: "startup".to_string(),
            feed_locator: Some("/srv/feeds/demo".to_string()),
            operator_ids: vec!["op_demo_express".to_string()],
            replayed_from_import_run_id: None,
            source_artifact_id: None,
            source_artifact: None,
            status: "running".to_string(),
            started_at_iso: "2026-04-09T09:00:00Z".to_string(),
            finished_at_iso: None,
            counts: CoachCatalogCounts::default(),
            error_message: None,
            issues: Vec::new(),
        })
        .await
        .expect("insert running import run");

        repo.finalize_import_run(
            "catalogimportrun_demo_gtfs_1",
            "succeeded",
            "2026-04-09T09:00:30Z",
            &CoachCatalogCounts {
                operators: 1,
                cities: 2,
                stop_clusters: 2,
                stops: 4,
                lines: 1,
                service_calendars: 1,
                trips: 2,
                fare_products: 2,
            },
            &["op_demo_express".to_string()],
            None,
        )
        .await
        .expect("finalize import run");

        repo.replace_import_run_issues(
            "catalogimportrun_demo_gtfs_1",
            &[CoachCatalogImportRunIssue {
                issue_id: "catalogimportissue_demo_gtfs_1".to_string(),
                import_run_id: "catalogimportrun_demo_gtfs_1".to_string(),
                severity: "warning".to_string(),
                stage: "build_catalog".to_string(),
                code: "partial_trip_skip".to_string(),
                message: "one trip was skipped because it had no valid terminal pair".to_string(),
                file_name: Some("stop_times.txt".to_string()),
                row_reference: Some("trip_id=TRIP1".to_string()),
            }],
        )
        .await
        .expect("replace import run issues");

        let import_runs = repo.list_import_runs().await.expect("list import runs");
        assert_eq!(import_runs.len(), 1);
        assert_eq!(import_runs[0].import_run_id, "catalogimportrun_demo_gtfs_1");
        assert_eq!(import_runs[0].status, "succeeded");
        assert_eq!(import_runs[0].counts.total_records(), 15);
        assert_eq!(import_runs[0].issues.len(), 1);
        assert_eq!(import_runs[0].issues[0].code, "partial_trip_skip");
        assert_eq!(
            import_runs[0].finished_at_iso.as_deref(),
            Some("2026-04-09 09:00:30+00")
        );

        db.cleanup().await;
    }
}
