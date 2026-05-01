use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateUserReq {
    pub account_id: String,
    #[serde(default)]
    pub phone: Option<String>,
    #[serde(default)]
    pub currency: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UserResp {
    pub user_id: String,
    pub wallet_id: String,
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub balance_cents: i64,
    pub currency: String,
    pub wallets: Vec<WalletResp>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UserLookupParams {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub wallet_id: Option<String>,
    pub currency: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TopupReq {
    pub amount_cents: i64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdminCreditReq {
    pub wallet_id: Option<String>,
    pub account_id: Option<String>,
    pub amount_cents: i64,
    pub reason: Option<String>,
    pub note: Option<String>,
    pub operator_account_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdminCreditApproveReq {
    pub approved_by_account_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdminCreditListParams {
    pub wallet_id: Option<String>,
    pub account_id: Option<String>,
    pub operator_account_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WalletResp {
    pub wallet_id: String,
    pub balance_cents: i64,
    pub currency: String,
}

#[derive(Debug, Serialize)]
pub struct AdminCreditResp {
    pub wallet_id: String,
    pub account_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub balance_cents: Option<i64>,
    pub currency: String,
    pub amount_cents: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub txn_id: Option<String>,
    pub reason: String,
    pub note: Option<String>,
    pub operator_account_id: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approval_request_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approved_by_account_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct AdminCreditMetricsResp {
    pub window_hours: i64,
    pub credited_count: i64,
    pub credited_amount_cents: i64,
    pub pending_approval_count: i64,
    pub pending_approval_amount_cents: i64,
    pub largest_credit_cents: i64,
    pub max_amount_cents: i64,
    pub operator_daily_limit_cents: i64,
    pub approval_threshold_cents: i64,
    pub alerts: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct AdminCreditListResp {
    pub items: Vec<AdminCreditResp>,
    pub metrics: AdminCreditMetricsResp,
}

#[derive(Debug, Serialize)]
pub struct AdminCreditReconciliationMismatch {
    pub kind: String,
    pub count: i64,
}

#[derive(Debug, Serialize)]
pub struct AdminCreditReconciliationResp {
    pub checked_at: String,
    pub status: String,
    pub mismatches: Vec<AdminCreditReconciliationMismatch>,
}

#[derive(Debug, Serialize)]
pub struct TransferResp {
    pub wallet_id: String,
    pub balance_cents: i64,
    pub currency: String,
    pub to_wallet_id: String,
}

#[derive(Debug, Serialize)]
pub struct WalletBucketsResp {
    pub wallet_id: String,
    pub currency: String,
    pub cash_balance_cents: i64,
    pub promo_credit_cents: i64,
    pub refund_credit_cents: i64,
    pub corporate_credit_cents: i64,
}

#[derive(Debug, Serialize)]
pub struct DriverWalletLedgerResp {
    pub wallet_id: String,
    pub currency: String,
    pub earnings_available_cents: i64,
    pub held_reserve_cents: i64,
    pub debt_cents: i64,
    pub payout_pending_cents: i64,
    pub bonuses_cents: i64,
    pub cash_collected_cents: i64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DriverRideFeeMutationReq {
    pub ride_id: String,
    pub amount_cents: i64,
    pub action: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DriverRideFeeHoldListParams {
    pub wallet_id: Option<String>,
    pub ride_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct DriverRideFeeHoldItem {
    pub ride_id: String,
    pub wallet_id: String,
    pub amount_cents: i64,
    pub status: String,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub reserved_at: Option<String>,
    pub released_at: Option<String>,
    pub settled_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletSnapshotParams {
    pub limit: Option<i64>,
    pub dir: Option<String>,
    pub kind: Option<String>,
    pub from_iso: Option<String>,
    pub to_iso: Option<String>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct WalletSnapshotResp {
    pub wallet: WalletResp,
    pub txns: Vec<TxnItem>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TransferReq {
    pub from_wallet_id: String,
    pub to_wallet_id: Option<String>,
    pub to_alias: Option<String>,
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
#[serde(deny_unknown_fields)]
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FavoritesParams {
    pub owner_wallet_id: String,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FavoriteScopeParams {
    pub owner_wallet_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
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
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RequestsParams {
    pub wallet_id: String,
    pub kind: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RequestScopeParams {
    pub wallet_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
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

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IdempotencyStatusParams {
    pub endpoint: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExchangeQuoteCreate {
    pub from_wallet_id: String,
    pub to_wallet_id: String,
    pub amount_cents: i64,
    pub expected_amount_cents: i64,
    pub rate_bps: i64,
    pub fee_bps: Option<i64>,
    pub expires_in_secs: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct ExchangeQuoteOut {
    pub id: String,
    pub from_wallet_id: String,
    pub to_wallet_id: String,
    pub from_currency: String,
    pub to_currency: String,
    pub amount_cents: i64,
    pub expected_amount_cents: i64,
    pub rate_bps: i64,
    pub fee_bps: i64,
    pub status: String,
    pub created_at: Option<String>,
    pub expires_at: Option<String>,
    pub debit_txn_id: Option<String>,
    pub credit_txn_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExchangeQuoteExecuteReq {
    pub from_wallet_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExchangeQuoteListParams {
    pub wallet_id: String,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RefundCreateReq {
    pub original_txn_id: String,
    pub requester_wallet_id: String,
    pub amount_cents: Option<i64>,
    pub reason: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RefundResolveReq {
    pub approver_account_id: String,
    pub action: String,
    pub note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RefundListParams {
    pub wallet_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct RefundOut {
    pub id: String,
    pub original_txn_id: String,
    pub requester_wallet_id: String,
    pub from_wallet_id: String,
    pub to_wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub reason: Option<String>,
    pub status: String,
    pub created_at: Option<String>,
    pub resolved_at: Option<String>,
    pub refund_txn_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletHoldCreateReq {
    pub amount_cents: i64,
    pub reason: Option<String>,
    pub expires_in_secs: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletHoldResolveReq {
    pub action: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletHoldListParams {
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct WalletHoldOut {
    pub id: String,
    pub wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub reason: Option<String>,
    pub status: String,
    pub created_at: Option<String>,
    pub expires_at: Option<String>,
    pub released_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RecurringPaymentCreateReq {
    pub from_wallet_id: String,
    pub to_wallet_id: String,
    pub amount_cents: i64,
    pub interval_days: i64,
    pub note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RecurringPaymentListParams {
    pub wallet_id: String,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct RecurringPaymentOut {
    pub id: String,
    pub from_wallet_id: String,
    pub to_wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub interval_days: i64,
    pub note: Option<String>,
    pub status: String,
    pub next_run_at: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MerchantProfileUpsertReq {
    pub wallet_id: String,
    pub merchant_name: String,
    pub category: Option<String>,
    pub settlement_wallet_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct MerchantProfileOut {
    pub wallet_id: String,
    pub merchant_name: String,
    pub category: Option<String>,
    pub settlement_wallet_id: Option<String>,
    pub status: String,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MiniPaymentIntentCreateReq {
    pub wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub merchant_reference: Option<String>,
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct MiniPaymentIntentOut {
    pub id: String,
    pub wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub merchant_reference: Option<String>,
    pub status: String,
    pub metadata: Option<serde_json::Value>,
    pub paid_txn_id: Option<String>,
    pub created_at: Option<String>,
    pub expires_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletControlReq {
    pub wallet_id: String,
    pub frozen: bool,
    pub reason: Option<String>,
    pub operator_account_id: String,
}

#[derive(Debug, Serialize)]
pub struct WalletControlOut {
    pub wallet_id: String,
    pub frozen: bool,
    pub reason: Option<String>,
    pub operator_account_id: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KycUpdateReq {
    pub wallet_id: String,
    pub kyc_level: i32,
    pub status: Option<String>,
    pub operator_account_id: String,
}

#[derive(Debug, Serialize)]
pub struct WalletLimitsOut {
    pub wallet_id: String,
    pub currency: String,
    pub kyc_level: i32,
    pub kyc_status: String,
    pub daily_transfer_limit_cents: i64,
    pub daily_exchange_limit_cents: i64,
    pub frozen: bool,
    pub active_hold_cents: i64,
    pub available_balance_cents: i64,
}

#[derive(Debug, Serialize)]
pub struct RiskMetricsOut {
    pub checked_at: String,
    pub txn_24h_count: i64,
    pub txn_24h_amount_cents: i64,
    pub high_value_txn_24h_count: i64,
    pub active_holds_count: i64,
    pub frozen_wallets_count: i64,
    pub pending_refunds_count: i64,
    pub alerts: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentLinkCreateReq {
    pub wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub purpose: Option<String>,
    pub expires_in_secs: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentLinkPayReq {
    pub payer_wallet_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentLinkListParams {
    pub wallet_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct PaymentLinkOut {
    pub id: String,
    pub wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub purpose: Option<String>,
    pub status: String,
    pub url_path: String,
    pub paid_txn_id: Option<String>,
    pub created_at: Option<String>,
    pub expires_at: Option<String>,
    pub paid_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MiniPaymentIntentConfirmReq {
    pub payer_wallet_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MerchantWebhookCreateReq {
    pub wallet_id: String,
    pub url: String,
    pub events: Vec<String>,
    pub secret_hint: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MerchantWebhookListParams {
    pub wallet_id: String,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct MerchantWebhookOut {
    pub id: String,
    pub wallet_id: String,
    pub url: String,
    pub events: Vec<String>,
    pub secret_hint: Option<String>,
    pub status: String,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MerchantSettlementCreateReq {
    pub wallet_id: String,
    pub amount_cents: i64,
    pub destination_ref: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MerchantSettlementResolveReq {
    pub action: String,
    pub operator_account_id: String,
    pub note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MerchantSettlementListParams {
    pub wallet_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct MerchantSettlementOut {
    pub id: String,
    pub wallet_id: String,
    pub amount_cents: i64,
    pub currency: String,
    pub destination_ref: Option<String>,
    pub status: String,
    pub created_at: Option<String>,
    pub resolved_at: Option<String>,
    pub operator_account_id: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct LedgerReconciliationOut {
    pub checked_at: String,
    pub wallet_count: i64,
    pub mismatch_count: i64,
    pub mismatches: Vec<LedgerReconciliationMismatch>,
}

#[derive(Debug, Serialize)]
pub struct LedgerReconciliationMismatch {
    pub wallet_id: String,
    pub wallet_balance_cents: i64,
    pub ledger_balance_cents: i64,
    pub delta_cents: i64,
    pub currency: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RiskRuleCreateReq {
    pub name: String,
    pub rule_type: String,
    pub threshold_cents: Option<i64>,
    pub threshold_count: Option<i64>,
    pub action: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RiskRuleListParams {
    pub enabled: Option<bool>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct RiskRuleOut {
    pub id: String,
    pub name: String,
    pub rule_type: String,
    pub threshold_cents: Option<i64>,
    pub threshold_count: Option<i64>,
    pub action: String,
    pub enabled: bool,
    pub created_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RiskEvaluationOut {
    pub checked_at: String,
    pub triggered: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentDisputeCreateReq {
    pub wallet_id: String,
    pub txn_id: String,
    pub reason: String,
    pub evidence_text: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentDisputeListParams {
    pub wallet_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct PaymentDisputeOut {
    pub id: String,
    pub wallet_id: String,
    pub txn_id: String,
    pub reason: String,
    pub evidence_text: Option<String>,
    pub status: String,
    pub created_at: Option<String>,
    pub resolved_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletAliasUpsertReq {
    pub wallet_id: String,
    pub alias: String,
    pub alias_type: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletAliasListParams {
    pub wallet_id: Option<String>,
    pub alias: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct WalletAliasOut {
    pub alias: String,
    pub wallet_id: String,
    pub alias_type: String,
    pub verified: bool,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KycDocumentCreateReq {
    pub wallet_id: String,
    pub document_type: String,
    pub reference: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KycDocumentListParams {
    pub wallet_id: String,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct KycDocumentOut {
    pub id: String,
    pub wallet_id: String,
    pub document_type: String,
    pub reference: String,
    pub status: String,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FxRateUpsertReq {
    pub from_currency: String,
    pub to_currency: String,
    pub rate_bps: i64,
    pub fee_bps: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FxRateListParams {
    pub from_currency: Option<String>,
    pub to_currency: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct FxRateOut {
    pub id: String,
    pub from_currency: String,
    pub to_currency: String,
    pub rate_bps: i64,
    pub fee_bps: i64,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OfflinePaymentSubmitReq {
    pub wallet_id: String,
    pub operation: String,
    pub payload: serde_json::Value,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OfflinePaymentListParams {
    pub wallet_id: String,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct OfflinePaymentOut {
    pub id: String,
    pub wallet_id: String,
    pub operation: String,
    pub payload: serde_json::Value,
    pub status: String,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentEventListParams {
    pub wallet_id: String,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct PaymentEventOut {
    pub id: String,
    pub wallet_id: String,
    pub event_type: String,
    pub title: String,
    pub payload: serde_json::Value,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AuditTimelineParams {
    pub wallet_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct RecurringRunOut {
    pub checked_at: String,
    pub executed_count: i64,
    pub failed_count: i64,
    pub txn_ids: Vec<String>,
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
    pub cursor_id: Option<String>,
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: String,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RolesParams {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RoleUpsert {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RoleCheckParams {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: String,
}

#[derive(Debug, Serialize)]
pub struct RoleCheckOut {
    pub ok: bool,
}
