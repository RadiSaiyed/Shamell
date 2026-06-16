use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
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
    pub identity_key_b64: String,
    pub identity_signing_pubkey_b64: String,
    pub signed_prekey_id: i64,
    pub signed_prekey_b64: String,
    pub signed_prekey_sig_b64: String,
    pub signed_prekey_sig_alg: String,
    pub supports_v2: bool,
    pub v2_only: bool,
    pub updated_at: String,
}

#[derive(Debug, Deserialize)]
pub struct OneTimePrekeyIn {
    pub key_id: i64,
    pub key_b64: String,
}

#[derive(Debug, Deserialize)]
pub struct PrekeysUploadReq {
    pub device_id: String,
    pub prekeys: Vec<OneTimePrekeyIn>,
}

#[derive(Debug, Serialize)]
pub struct PrekeysUploadOut {
    pub device_id: String,
    pub uploaded: i64,
    pub available: i64,
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
pub struct ContactRuleReq {
    pub peer_id: String,
    pub blocked: Option<bool>,
    pub hidden: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct ContactPrefsReq {
    pub peer_id: String,
    pub muted: Option<bool>,
    pub starred: Option<bool>,
    pub pinned: Option<bool>,
}

#[derive(Debug, Deserialize)]
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
pub struct GroupInviteReq {
    pub inviter_id: String,
    pub member_ids: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct GroupLeaveReq {
    pub device_id: String,
}

#[derive(Debug, Deserialize)]
pub struct GroupRoleReq {
    pub actor_id: String,
    pub target_id: String,
    pub role: String,
}

#[derive(Debug, Deserialize)]
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
pub struct ReadReq {
    pub device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct PushTokenReq {
    pub token: String,
    pub platform: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct MailboxIssueReq {
    pub device_id: String,
}

#[derive(Debug, Serialize)]
pub struct MailboxIssueOut {
    pub mailbox_token: String,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
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
pub struct MailboxRotateReq {
    pub device_id: String,
    pub mailbox_token: String,
}

#[derive(Debug, Serialize)]
pub struct MailboxRotateOut {
    pub mailbox_token: String,
    pub created_at: String,
}
