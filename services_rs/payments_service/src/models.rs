use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct CreateUserReq {
    pub account_id: String,
    #[serde(default)]
    pub phone: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UserResp {
    pub user_id: String,
    pub wallet_id: String,
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub balance_cents: i64,
    pub currency: String,
}

#[derive(Debug, Deserialize)]
pub struct TopupReq {
    pub amount_cents: i64,
}

#[derive(Debug, Serialize)]
pub struct WalletResp {
    pub wallet_id: String,
    pub balance_cents: i64,
    pub currency: String,
}

#[derive(Debug, Deserialize)]
pub struct TransferReq {
    pub from_wallet_id: String,
    pub to_wallet_id: Option<String>,
    pub to_alias: Option<String>,
    pub amount_cents: i64,
}

#[derive(Debug, Deserialize)]
pub struct BusBookingTransferReq {
    pub booking_id: String,
    pub action: Option<String>,
    pub from_wallet_id: String,
    pub to_wallet_id: String,
    pub amount_cents: i64,
}

#[derive(Debug, Serialize)]
pub struct TxnItem {
    pub id: String,
    pub from_wallet_id: Option<String>,
    pub to_wallet_id: String,
    pub amount_cents: i64,
    pub fee_cents: i64,
    pub kind: String,
    pub created_at: Option<String>,
    pub meta: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct TxnParams {
    pub wallet_id: String,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct FavoriteCreate {
    pub owner_wallet_id: String,
    pub favorite_wallet_id: String,
    pub alias: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct FavoriteOut {
    pub id: String,
    pub owner_wallet_id: String,
    pub favorite_wallet_id: String,
    pub alias: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct FavoritesParams {
    pub owner_wallet_id: String,
}

#[derive(Debug, Deserialize)]
pub struct PaymentRequestCreate {
    pub from_wallet_id: String,
    pub to_wallet_id: Option<String>,
    pub to_alias: Option<String>,
    pub amount_cents: i64,
    pub message: Option<String>,
    pub expires_in_secs: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct PaymentRequestOut {
    pub id: String,
    pub from_wallet_id: String,
    pub to_wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub message: Option<String>,
    pub status: String,
}

#[derive(Debug, Deserialize)]
pub struct RequestsParams {
    pub wallet_id: String,
    pub kind: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct AcceptRequestReq {
    pub to_wallet_id: String,
}

#[derive(Debug, Serialize)]
pub struct IdempotencyExistsOut {
    pub exists: bool,
    pub txn_id: Option<String>,
    pub endpoint: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct HealthOut {
    pub status: &'static str,
    pub env: String,
    pub service: &'static str,
    pub version: &'static str,
}

#[derive(Debug, Serialize)]
pub struct OkOut {
    pub ok: bool,
}

#[derive(Debug, Serialize)]
pub struct RoleItem {
    pub id: String,
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: String,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RolesParams {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct RoleUpsert {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: String,
}

#[derive(Debug, Deserialize)]
pub struct RoleCheckParams {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: String,
}

#[derive(Debug, Serialize)]
pub struct RoleCheckOut {
    pub ok: bool,
}
