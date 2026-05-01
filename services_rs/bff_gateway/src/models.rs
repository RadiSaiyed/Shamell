use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize)]
pub struct HealthOut {
    pub status: &'static str,
    pub env: String,
    pub service: &'static str,
    pub version: &'static str,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsCreateUserIn {
    pub account_id: Option<String>,
    pub currency: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsTopupIn {
    pub amount_cents: Option<i64>,
    pub amount: Option<serde_json::Number>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsAdminCreditIn {
    pub wallet_id: Option<String>,
    pub shamell_id: Option<String>,
    pub amount_cents: Option<i64>,
    pub amount: Option<serde_json::Number>,
    pub reason: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsAdminCreditApproveIn {}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsAdminCreditListQuery {
    pub wallet_id: Option<String>,
    pub shamell_id: Option<String>,
    pub operator_account_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsTransferIn {
    pub from_wallet_id: Option<String>,
    pub to_wallet_id: Option<String>,
    pub to_alias: Option<String>,
    pub amount_cents: Option<i64>,
    pub amount: Option<serde_json::Number>,
    pub reference: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsFavoriteCreateIn {
    pub owner_wallet_id: Option<String>,
    pub favorite_wallet_id: String,
    pub alias: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsRequestCreateIn {
    pub from_wallet_id: Option<String>,
    pub to_wallet_id: Option<String>,
    pub to_alias: Option<String>,
    pub amount_cents: i64,
    pub message: Option<String>,
    pub expires_in_secs: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaymentsRequestAcceptIn {
    pub to_wallet_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RequestsListQuery {
    pub wallet_id: Option<String>,
    pub kind: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FavoritesListQuery {
    pub owner_wallet_id: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletSnapshotQuery {
    pub dir: Option<String>,
    pub kind: Option<String>,
    pub from_iso: Option<String>,
    pub to_iso: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalletStatementQuery {
    pub dir: Option<String>,
    pub kind: Option<String>,
    pub from_iso: Option<String>,
    pub to_iso: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
    pub format: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdminRolesListQuery {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdminRolesCheckQuery {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdminRoleMutationIn {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorkforceSessionExchangeIn {
    pub jwt_assertion: Option<String>,
    pub device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AccessAssignmentsListQuery {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role_id: Option<String>,
    pub operator_id: Option<String>,
    pub official_account_id: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AccessAssignmentScopeIn {
    pub platform: Option<bool>,
    pub operator_id: Option<String>,
    pub official_account_id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AccessAssignmentMutationIn {
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role_id: String,
    pub scope: Option<AccessAssignmentScopeIn>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatInboxQuery {
    pub device_id: Option<String>,
    pub since_iso: Option<String>,
    pub since_id: Option<String>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatThreadQuery {
    pub device_id: Option<String>,
    pub peer_id: Option<String>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatPrefsQuery {
    pub limit: Option<i64>,
    pub after_peer_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupPrefsQuery {
    pub limit: Option<i64>,
    pub after_group_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatHiddenQuery {
    pub limit: Option<i64>,
    pub after_peer_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatStreamQuery {
    pub device_id: Option<String>,
    pub since_iso: Option<String>,
    pub since_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupListQuery {
    pub device_id: Option<String>,
    pub limit: Option<i64>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupInboxQuery {
    pub device_id: Option<String>,
    pub since_iso: Option<String>,
    pub since_id: Option<String>,
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupMembersQuery {
    pub device_id: Option<String>,
    pub limit: Option<i64>,
    pub after_joined_at: Option<String>,
    pub after_device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupKeyEventsQuery {
    pub device_id: Option<String>,
    pub limit: Option<i64>,
    pub before_version: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatRegisterIn {
    pub device_id: String,
    pub client_device_id: Option<String>,
    pub public_key_b64: String,
    pub name: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMarkReadIn {
    pub device_id: Option<String>,
    pub read: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMessageReactionIn {
    pub device_id: Option<String>,
    pub emoji: Option<String>,
    pub remove: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMessageReactionQuery {
    pub device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMessagePinIn {
    pub device_id: Option<String>,
    pub pinned: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMessagePinsQuery {
    pub device_id: Option<String>,
    pub peer_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMessageReportIn {
    pub device_id: Option<String>,
    pub reason: String,
    pub note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMessageEditIn {
    pub device_id: Option<String>,
    pub protocol_version: Option<String>,
    pub sender_dh_pub_b64: Option<String>,
    pub nonce_b64: String,
    pub box_b64: String,
    pub key_id: Option<String>,
    pub prev_key_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMessageDeleteIn {
    pub device_id: Option<String>,
    pub delete_for_everyone: Option<bool>,
    pub reason: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatEventsQuery {
    pub device_id: Option<String>,
    pub after_event_id: Option<i64>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatCallLogIn {
    pub device_id: Option<String>,
    pub call_id: Option<String>,
    pub peer_id: String,
    pub direction: String,
    pub kind: String,
    pub accepted: Option<bool>,
    pub duration_seconds: Option<i64>,
    pub started_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatCallLogsQuery {
    pub device_id: Option<String>,
    pub peer_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatVoiceTranscriptIn {
    pub device_id: Option<String>,
    pub message_id: String,
    pub transcript: String,
    pub language: Option<String>,
    pub confidence: Option<f64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatVoiceTranscriptQuery {
    pub device_id: Option<String>,
    pub message_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatVoiceTranscriptJobIn {
    pub device_id: Option<String>,
    pub message_id: String,
    pub language: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatVoiceTranscriptJobsQuery {
    pub device_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatVoiceTranscriptJobCompleteIn {
    pub device_id: Option<String>,
    pub status: String,
    pub transcript: Option<String>,
    pub language: Option<String>,
    pub confidence: Option<f64>,
    pub error: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatModerationReportsQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatModerationActionIn {
    pub moderator_device_id: Option<String>,
    pub status: String,
    pub note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatPushTokenIn {
    pub token: String,
    pub platform: Option<String>,
    #[serde(rename = "ts")]
    pub _ts: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatSendIn {
    pub sender_id: String,
    pub recipient_id: String,
    pub protocol_version: Option<String>,
    pub sender_pubkey_b64: String,
    pub sender_dh_pub_b64: Option<String>,
    pub nonce_b64: String,
    pub box_b64: String,
    pub expire_after_seconds: Option<i64>,
    pub sealed_sender: Option<bool>,
    pub sender_hint: Option<String>,
    pub sender_fingerprint: Option<String>,
    pub key_id: Option<String>,
    pub prev_key_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupSendIn {
    pub sender_id: String,
    pub protocol_version: Option<String>,
    pub nonce_b64: Option<String>,
    pub box_b64: Option<String>,
    pub expire_after_seconds: Option<i64>,
    pub kind: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatKeyRegisterIn {
    pub device_id: String,
    pub identity_key_b64: String,
    pub identity_signing_pubkey_b64: Option<String>,
    pub signed_prekey_id: i64,
    pub signed_prekey_b64: String,
    pub signed_prekey_sig_b64: String,
    pub signed_prekey_sig_alg: Option<String>,
    pub v2_only: Option<bool>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatOneTimePrekeyIn {
    pub key_id: i64,
    pub key_b64: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatPrekeysUploadIn {
    pub device_id: String,
    pub prekeys: Vec<ChatOneTimePrekeyIn>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatKeyBootstrapIn {
    pub device_id: String,
    pub identity_key_b64: String,
    pub identity_signing_pubkey_b64: Option<String>,
    pub signed_prekey_id: i64,
    pub signed_prekey_b64: String,
    pub signed_prekey_sig_b64: String,
    pub signed_prekey_sig_alg: Option<String>,
    pub v2_only: Option<bool>,
    pub prekeys: Vec<ChatOneTimePrekeyIn>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMailboxIssueIn {
    pub device_id: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMailboxWriteIn {
    pub mailbox_token: String,
    pub envelope_b64: String,
    pub expire_after_seconds: Option<i64>,
    pub sender_hint: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMailboxPollReq {
    pub device_id: String,
    pub mailbox_token: String,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatMailboxRotateIn {
    pub device_id: String,
    pub mailbox_token: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatBlockIn {
    pub peer_id: String,
    pub blocked: Option<bool>,
    pub hidden: Option<bool>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatSetPrefsIn {
    pub peer_id: String,
    pub muted: Option<bool>,
    pub starred: Option<bool>,
    pub pinned: Option<bool>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatSetGroupPrefsIn {
    pub group_id: String,
    pub muted: Option<bool>,
    pub pinned: Option<bool>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupCreateIn {
    pub device_id: String,
    pub name: String,
    pub member_ids: Option<Vec<String>>,
    pub group_id: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupUpdateIn {
    pub actor_id: String,
    pub name: Option<String>,
    pub avatar_b64: Option<String>,
    pub avatar_mime: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupInviteIn {
    pub inviter_id: String,
    pub member_ids: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupLeaveIn {
    pub device_id: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupSetRoleIn {
    pub actor_id: String,
    pub target_id: String,
    pub role: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChatGroupRotateKeyIn {
    pub actor_id: String,
    pub key_fp: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct MeAccessContextOut {
    pub shamell_id: String,
    pub roles: Vec<String>,
    pub products: Vec<String>,
    pub operator_ids: Vec<String>,
    pub official_account_ids: Vec<String>,
    pub official_account_wildcard: bool,
    pub has_platform_scope: bool,
    pub is_admin: bool,
    pub is_superadmin: bool,
}

#[derive(Debug, Serialize)]
pub struct MePermissionsOut {
    pub shamell_id: String,
    pub roles: Vec<String>,
    pub permissions: Vec<String>,
    pub products: Vec<String>,
    pub operator_ids: Vec<String>,
    pub official_account_ids: Vec<String>,
    pub official_account_wildcard: bool,
    pub has_platform_scope: bool,
    pub is_admin: bool,
    pub is_superadmin: bool,
}

#[derive(Debug, Serialize)]
pub struct WorkforceIdentityOut {
    pub provider: String,
    pub issuer: String,
    pub subject: String,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub display_name: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct WorkforceSessionExchangeOut {
    pub ok: bool,
    pub account_id: String,
    pub shamell_id: String,
    pub roles: Vec<String>,
    pub permissions: Vec<String>,
    pub products: Vec<String>,
    pub operator_ids: Vec<String>,
    pub official_account_ids: Vec<String>,
    pub official_account_wildcard: bool,
    pub has_platform_scope: bool,
    pub is_admin: bool,
    pub is_superadmin: bool,
    pub identity: WorkforceIdentityOut,
}

#[derive(Debug, Clone, Serialize)]
pub struct AccessAssignmentScopeOut {
    pub platform: bool,
    pub operator_id: Option<String>,
    pub official_account_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct AccessAssignmentOut {
    pub cursor_id: Option<i64>,
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub role_id: String,
    pub legacy_role: String,
    pub created_at: Option<String>,
    pub scope: AccessAssignmentScopeOut,
}

#[derive(Debug, Serialize)]
pub struct AccessAssignmentsListOut {
    pub assignments: Vec<AccessAssignmentOut>,
}

#[derive(Debug, Serialize)]
pub struct AccessAssignmentMutationOut {
    pub ok: bool,
    pub assignment: AccessAssignmentOut,
}
