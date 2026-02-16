use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize)]
pub struct HealthOut {
    pub status: &'static str,
    pub env: String,
    pub service: &'static str,
    pub version: &'static str,
}

#[derive(Debug, Deserialize)]
pub struct RequestsListQuery {
    pub wallet_id: Option<String>,
    pub kind: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct FavoritesListQuery {
    pub owner_wallet_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct AdminRolesListQuery {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct AdminRolesCheckQuery {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ChatInboxQuery {
    pub device_id: Option<String>,
    pub since_iso: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct ChatStreamQuery {
    pub device_id: Option<String>,
    pub since_iso: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct ChatGroupListQuery {
    pub device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ChatGroupInboxQuery {
    pub device_id: Option<String>,
    pub since_iso: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct ChatGroupMembersQuery {
    pub device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ChatGroupKeyEventsQuery {
    pub device_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct ChatMailboxPollReq {
    pub device_id: String,
    pub mailbox_token: String,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct BusCitiesQuery {
    pub q: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct BusRoutesQuery {
    pub origin_city_id: Option<String>,
    pub dest_city_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BusTripsSearchQuery {
    pub origin_city_id: Option<String>,
    pub dest_city_id: Option<String>,
    pub date: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BusListOperatorsQuery {
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct BusOperatorStatsQuery {
    pub period: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BusOperatorTripsQuery {
    pub status: Option<String>,
    pub from_date: Option<String>,
    pub to_date: Option<String>,
    pub limit: Option<i64>,
    pub order: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BusBookingSearchQuery {
    pub wallet_id: Option<String>,
    pub limit: Option<i64>,
}
