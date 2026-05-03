use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RegisterReq {
    pub device_id: String,
    #[serde(rename = "public_key_b64")]
    pub public_key_b64: String,
    pub name: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct DeviceOut {
    pub device_id: String,
    #[serde(rename = "public_key_b64")]
    pub public_key_b64: String,
    pub name: Option<String>,
    pub key_version: i64,
}

#[derive(Debug, Serialize)]
pub struct DeviceRegisterOut {
    pub device_id: String,
    #[serde(rename = "public_key_b64")]
    pub public_key_b64: String,
    pub name: Option<String>,
    pub key_version: i64,
    pub auth_token: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KeyRegisterReq {
    pub device_id: String,
    pub identity_key_b64: String,
    pub identity_signing_pubkey_b64: Option<String>,
    pub signed_prekey_id: i64,
    pub signed_prekey_b64: String,
    pub signed_prekey_sig_b64: String,
    pub signed_prekey_sig_alg: Option<String>,
    pub v2_only: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct KeyRegisterOut {
    pub device_id: String,
    pub signed_prekey_id: i64,
    pub supports_v2: bool,
    pub v2_only: bool,
    pub updated_at: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OneTimePrekeyIn {
    pub key_id: i64,
    pub key_b64: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PrekeysUploadReq {
    pub device_id: String,
    pub prekeys: Vec<OneTimePrekeyIn>,
}

#[derive(Debug, Serialize)]
pub struct PrekeysUploadOut {
    pub device_id: String,
    pub uploaded: i64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KeyBootstrapReq {
    pub device_id: String,
    pub identity_key_b64: String,
    pub identity_signing_pubkey_b64: Option<String>,
    pub signed_prekey_id: i64,
    pub signed_prekey_b64: String,
    pub signed_prekey_sig_b64: String,
    pub signed_prekey_sig_alg: Option<String>,
    pub v2_only: Option<bool>,
    pub prekeys: Vec<OneTimePrekeyIn>,
}

#[derive(Debug, Serialize)]
pub struct KeyBootstrapOut {
    pub device_id: String,
    pub signed_prekey_id: i64,
    pub supports_v2: bool,
    pub v2_only: bool,
    pub uploaded: i64,
    pub updated_at: String,
}

#[derive(Debug, Serialize)]
pub struct PrekeyStatusOut {
    pub device_id: String,
    pub available_prekeys: i64,
    pub recommended_upload: i64,
}

#[derive(Debug, Serialize)]
pub struct KeyBundleOut {
    pub device_id: String,
    pub identity_key_b64: String,
    pub identity_signing_pubkey_b64: Option<String>,
    pub signed_prekey_id: i64,
    pub signed_prekey_b64: String,
    pub signed_prekey_sig_b64: String,
    pub one_time_prekey_id: Option<i64>,
    pub one_time_prekey_b64: Option<String>,
    pub protocol_floor: String,
    pub supports_v2: bool,
    pub v2_only: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SendReq {
    pub sender_id: String,
    pub recipient_id: String,
    pub protocol_version: Option<String>,
    #[serde(rename = "sender_pubkey_b64")]
    pub sender_pubkey_b64: String,
    #[serde(rename = "sender_dh_pub_b64")]
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
pub struct ContactRuleReq {
    pub peer_id: String,
    pub blocked: Option<bool>,
    pub hidden: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ContactPrefsReq {
    pub peer_id: String,
    pub muted: Option<bool>,
    pub starred: Option<bool>,
    pub pinned: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DirectPeerGuardReq {
    pub peer_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupPrefsReq {
    pub group_id: String,
    pub muted: Option<bool>,
    pub pinned: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct GroupPrefsOut {
    pub group_id: String,
    pub muted: bool,
    pub pinned: bool,
}

#[derive(Debug, Serialize)]
pub struct MsgOut {
    pub id: String,
    pub sender_id: Option<String>,
    pub recipient_id: String,
    pub protocol_version: String,
    #[serde(rename = "sender_pubkey_b64")]
    pub sender_pubkey_b64: Option<String>,
    #[serde(rename = "sender_dh_pub_b64")]
    pub sender_dh_pub_b64: Option<String>,
    pub nonce_b64: String,
    pub box_b64: String,
    pub created_at: Option<String>,
    pub delivered_at: Option<String>,
    pub read_at: Option<String>,
    pub expire_at: Option<String>,
    pub sealed_sender: bool,
    pub sender_hint: Option<String>,
    pub sender_fingerprint: Option<String>,
    pub key_id: Option<String>,
    pub prev_key_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupCreateReq {
    pub device_id: String,
    pub name: String,
    pub member_ids: Option<Vec<String>>,
    pub group_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct GroupOut {
    pub group_id: String,
    pub name: String,
    pub creator_id: String,
    pub created_at: Option<String>,
    pub member_count: i64,
    pub key_version: i64,
    pub avatar_b64: Option<String>,
    pub avatar_mime: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupSendReq {
    pub sender_id: String,
    pub protocol_version: Option<String>,
    pub nonce_b64: Option<String>,
    pub box_b64: Option<String>,
    pub expire_after_seconds: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct GroupMsgOut {
    pub id: String,
    pub group_id: String,
    pub sender_id: String,
    pub protocol_version: String,
    pub text: String,
    pub kind: Option<String>,
    pub nonce_b64: Option<String>,
    pub box_b64: Option<String>,
    pub attachment_b64: Option<String>,
    pub attachment_mime: Option<String>,
    pub voice_secs: Option<i64>,
    pub created_at: Option<String>,
    pub expire_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupInviteReq {
    pub inviter_id: String,
    pub member_ids: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupLeaveReq {
    pub device_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupRoleReq {
    pub actor_id: String,
    pub target_id: String,
    pub role: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupUpdateReq {
    pub actor_id: String,
    pub name: Option<String>,
    pub avatar_b64: Option<String>,
    pub avatar_mime: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct GroupMemberOut {
    pub device_id: String,
    pub role: Option<String>,
    pub joined_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupKeyRotateReq {
    pub actor_id: String,
    pub key_fp: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct GroupKeyEventOut {
    pub group_id: String,
    pub version: i64,
    pub actor_id: String,
    pub key_fp: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadReq {
    pub device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PushTokenReq {
    pub token: String,
    pub platform: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PushNotifyReq {
    pub device_ids: Vec<String>,
    #[serde(rename = "type")]
    pub push_type: String,
    pub ride_id: Option<String>,
    pub ride_status: Option<String>,
    pub request_id: Option<String>,
    pub wallet_id: Option<String>,
    pub call_id: Option<String>,
    pub from_device_id: Option<String>,
    pub mode: Option<String>,
    pub title: Option<String>,
    pub body: Option<String>,
    pub pickup_summary: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PushNotifyOut {
    pub ok: bool,
    pub targeted_devices: usize,
    pub targeted_tokens: usize,
    pub delivered_best_effort: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MailboxIssueReq {
    pub device_id: String,
}

#[derive(Debug, Serialize)]
pub struct MailboxIssueOut {
    pub mailbox_token: String,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MailboxWriteReq {
    pub mailbox_token: String,
    pub envelope_b64: String,
    pub expire_after_seconds: Option<i64>,
    pub sender_hint: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct MailboxWriteOut {
    pub id: String,
    pub accepted: bool,
    pub expire_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MailboxPollReq {
    pub device_id: String,
    pub mailbox_token: String,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct MailboxMsgOut {
    pub id: String,
    pub envelope_b64: String,
    pub sender_hint: Option<String>,
    pub created_at: String,
    pub expire_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MailboxRotateReq {
    pub device_id: String,
    pub mailbox_token: String,
}

#[derive(Debug, Serialize)]
pub struct MailboxRotateOut {
    pub mailbox_token: String,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MessageReactionReq {
    pub device_id: Option<String>,
    pub emoji: Option<String>,
    pub remove: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MessageReactionQuery {
    pub device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MessagePinReq {
    pub device_id: Option<String>,
    pub pinned: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MessagePinsQuery {
    pub device_id: Option<String>,
    pub peer_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MessageReportReq {
    pub device_id: Option<String>,
    pub reason: String,
    pub note: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MessageEditReq {
    pub device_id: Option<String>,
    pub protocol_version: Option<String>,
    #[serde(rename = "sender_dh_pub_b64")]
    pub sender_dh_pub_b64: Option<String>,
    pub nonce_b64: String,
    pub box_b64: String,
    pub key_id: Option<String>,
    pub prev_key_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MessageDeleteReq {
    pub device_id: Option<String>,
    pub delete_for_everyone: Option<bool>,
    pub reason: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConversationEventsQuery {
    pub device_id: Option<String>,
    pub after_event_id: Option<i64>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CallLogReq {
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
pub struct CallLogsQuery {
    pub device_id: Option<String>,
    pub peer_id: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VoiceTranscriptReq {
    pub device_id: Option<String>,
    pub message_id: String,
    pub transcript: String,
    pub language: Option<String>,
    pub confidence: Option<f64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VoiceTranscriptsQuery {
    pub device_id: Option<String>,
    pub message_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VoiceTranscriptJobReq {
    pub device_id: Option<String>,
    pub message_id: String,
    pub language: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VoiceTranscriptJobsQuery {
    pub device_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VoiceTranscriptJobCompleteReq {
    pub device_id: Option<String>,
    pub status: String,
    pub transcript: Option<String>,
    pub language: Option<String>,
    pub confidence: Option<f64>,
    pub error: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModerationReportsQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModerationReportActionReq {
    pub moderator_device_id: Option<String>,
    pub status: String,
    pub note: Option<String>,
}
