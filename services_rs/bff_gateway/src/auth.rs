use crate::error::{ApiError, ApiResult};
use crate::state::AppState;
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::response::{Html, IntoResponse, Redirect, Response};
use axum::Json;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use hmac::{Hmac, Mac};
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use qrcode::render::svg;
use qrcode::QrCode;
use rand::Rng;
use rand::RngCore;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use shamell_common::secret_policy;
use sqlx::{PgPool, Row};
use std::env;
use std::net::{IpAddr, SocketAddr};
use std::time::{SystemTime, UNIX_EPOCH};
use subtle::ConstantTimeEq;

#[derive(Clone)]
struct AppleDeviceCheckConfig {
    team_id: String,
    key_id: String,
    private_key_p8: Vec<u8>,
}

#[derive(Clone)]
struct PlayIntegrityConfig {
    // Allow multiple flavors (user/operator/admin) without weakening integrity checks.
    allowed_package_names: Vec<String>,
    service_account_email: String,
    service_account_private_key_pem: Vec<u8>,
    token_uri: String,
    require_strong_integrity: bool,
    require_play_recognized: bool,
    require_licensed: bool,
}

#[derive(Clone)]
pub struct AuthRuntime {
    pool: PgPool,
    auth_session_ttl_secs: i64,
    auth_session_idle_ttl_secs: i64,
    account_create_window_secs: i64,
    account_create_max_per_ip: i64,
    account_create_max_per_device: i64,
    account_create_challenge_window_secs: i64,
    account_create_challenge_max_per_ip: i64,
    account_create_challenge_max_per_device: i64,
    account_create_enabled: bool,
    account_create_pow_enabled: bool,
    account_create_pow_ttl_secs: i64,
    account_create_pow_difficulty_bits: u8,
    account_create_pow_secret: Option<String>,
    account_create_hw_attestation_enabled: bool,
    account_create_hw_attestation_required: bool,
    account_create_apple_devicecheck: Option<AppleDeviceCheckConfig>,
    account_create_play_integrity: Option<PlayIntegrityConfig>,
    biometric_token_ttl_secs: i64,
    biometric_login_window_secs: i64,
    biometric_login_max_per_ip: i64,
    biometric_login_max_per_device: i64,
    device_login_ttl_secs: i64,
    contact_invite_ttl_secs: i64,
    contact_invite_window_secs: i64,
    contact_invite_create_max_per_ip: i64,
    contact_invite_create_max_per_phone: i64,
    contact_invite_redeem_max_per_ip: i64,
    contact_invite_redeem_max_per_phone: i64,
    contact_invite_redeem_max_per_token: i64,
    chat_register_window_secs: i64,
    chat_register_max_per_ip: i64,
    chat_register_max_per_device: i64,
    chat_get_device_window_secs: i64,
    chat_get_device_max_per_ip: i64,
    chat_get_device_max_per_device: i64,
    chat_send_window_secs: i64,
    chat_send_max_per_ip: i64,
    chat_send_max_per_device: i64,
    // Direct message anti-spam: require a server-side "contact edge" (created via invite redemption)
    // before allowing direct sends. Defaults to enabled in prod/staging.
    chat_send_require_contacts: bool,
    chat_group_send_window_secs: i64,
    chat_group_send_max_per_ip: i64,
    chat_group_send_max_per_device: i64,
    chat_mailbox_write_window_secs: i64,
    chat_mailbox_write_max_per_ip: i64,
    chat_mailbox_write_max_per_device: i64,
    chat_mailbox_write_max_per_mailbox: i64,
    device_login_window_secs: i64,
    device_login_start_max_per_ip: i64,
    device_login_redeem_max_per_ip: i64,
    device_login_approve_max_per_phone: i64,
    device_login_redeem_max_per_token: i64,
    device_login_approve_max_per_token: i64,
    maintenance_interval_secs: i64,
    session_cleanup_grace_secs: i64,
    device_login_cleanup_grace_secs: i64,
    device_session_retention_secs: i64,
    rate_limit_retention_secs: i64,
}

const SESSION_COOKIE_NAME: &str = "__Host-sa_session";
const LEGACY_SESSION_COOKIE_NAME: &str = "sa_session";

const DEVICE_LOGIN_DEMO_HTML: &str = r#"<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Shamell · Device login</title>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      body { font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; padding: 0; background: #020617; color: #e5e7eb; }
      .page { min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 24px; }
      .card { max-width: 480px; width: 100%; background: rgba(15,23,42,0.95); border-radius: 12px; padding: 20px 20px 16px; box-shadow: 0 18px 45px rgba(0,0,0,0.45); border: 1px solid rgba(148,163,184,0.45); }
      h1 { font-size: 20px; margin: 0 0 4px; }
      p { margin: 4px 0; font-size: 14px; color: #9ca3af; }
      label { display: block; font-size: 13px; margin-top: 10px; margin-bottom: 4px; color: #e5e7eb; }
      input[type="text"] { width: 100%; padding: 6px 8px; border-radius: 6px; border: 1px solid #4b5563; background: #020617; color: #e5e7eb; font-size: 14px; }
      button { margin-top: 12px; padding: 8px 14px; border-radius: 999px; border: none; background: #22c55e; color: #022c22; font-weight: 600; font-size: 14px; cursor: pointer; }
      button:disabled { opacity: .6; cursor: default; }
      .qr-wrap { margin-top: 14px; display: flex; align-items: center; justify-content: center; }
      .qr-wrap img { border-radius: 8px; border: 1px solid rgba(75,85,99,0.8); background: white; }
      .status { margin-top: 10px; font-size: 13px; color: #9ca3af; }
      .payload { margin-top: 6px; font-size: 11px; color: #6b7280; word-break: break-all; }
      a { color: #38bdf8; text-decoration: none; }
    </style>
  </head>
  <body>
    <div class="page">
      <div class="card">
        <h1>Shamell · Device login</h1>
        <p>Scan this code with Shamell on your phone (Scan &gt; Scan QR). Confirm the login on the phone to sign in this browser.</p>
        <label for="dl_label">Device label (optional)</label>
        <input id="dl_label" type="text" value="Web" autocomplete="off" />
        <button id="dl_btn" type="button">Start new login QR</button>
        <div class="qr-wrap">
          <img id="dl_qr_img" src="" alt="Device login QR" width="220" height="220" />
        </div>
        <div id="dl_status" class="status">No active login yet.</div>
        <div id="dl_payload" class="payload"></div>
      </div>
    </div>
    <script>
      let dlToken = null;
      let dlPollTimer = null;
      let dlQrUrl = null;
      function svgToDataUrl(svgText) {
        try {
          // Prefer base64 to avoid issues with special characters in data URLs.
          const b64 = btoa(unescape(encodeURIComponent(svgText)));
          return 'data:image/svg+xml;base64,' + b64;
        } catch (_) {
          try {
            return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgText);
          } catch (_) {
            return null;
          }
        }
      }
      async function dlStart() {
        const btn = document.getElementById('dl_btn');
        const labEl = document.getElementById('dl_label');
        const statusEl = document.getElementById('dl_status');
        const payloadEl = document.getElementById('dl_payload');
        const img = document.getElementById('dl_qr_img');
        const label = (labEl.value || '').trim();
        btn.disabled = true;
        statusEl.textContent = 'Requesting login token…';
        payloadEl.textContent = '';
        if (dlPollTimer) { clearInterval(dlPollTimer); dlPollTimer = null; }
        try {
          const resp = await fetch('/auth/device_login/start', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({label: label || null}) });
          const data = await resp.json();
          if (!resp.ok || !data.token) { statusEl.textContent = 'Failed to start device login.'; btn.disabled = false; return; }
          dlToken = data.token;
          const payload = 'shamell://device_login?token=' + encodeURIComponent(dlToken) + (label ? '&label=' + encodeURIComponent(label) : '');
          if (dlQrUrl) { try { URL.revokeObjectURL(dlQrUrl); } catch (_) {} dlQrUrl = null; }
          try {
            const qrResp = await fetch('/auth/device_login/qr.svg', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({token: dlToken, size: 220}) });
            if (qrResp.ok) {
              const svg = await qrResp.text();
              // Use a data: URL to satisfy our CSP (img-src allows data: but not blob:).
              const dataUrl = svgToDataUrl(svg);
              if (dataUrl) {
                img.src = dataUrl;
              } else {
                img.src = '';
              }
            } else {
              img.src = '';
            }
          } catch (_) {
            img.src = '';
          }
          statusEl.textContent = 'Waiting for scan and approval on phone…';
          payloadEl.textContent = payload;
          dlPollTimer = setInterval(dlPoll, 2000);
        } catch (e) {
          statusEl.textContent = 'Failed to start device login.';
        } finally {
          btn.disabled = false;
        }
      }
      async function dlPoll() {
        if (!dlToken) return;
        const statusEl = document.getElementById('dl_status');
        try {
          const resp = await fetch('/auth/device_login/redeem', { method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({token: dlToken}) });
          if (!resp.ok) {
            let detail = '';
            try { const err = await resp.json(); detail = (err && err.detail) || ''; } catch (_) {}
            if (detail && (detail.indexOf('expired') !== -1 || detail.indexOf('not found') !== -1)) {
              statusEl.textContent = 'Login token expired. Start a new QR.';
              clearInterval(dlPollTimer);
              dlPollTimer = null;
              dlToken = null;
            }
            return;
          }
          const data = await resp.json();
          const who = (data && (data.shamell_id || data.phone)) || '';
          statusEl.textContent = who ? ('Login successful for ' + who + '. This browser is now signed in.') : 'Login successful.';
          clearInterval(dlPollTimer);
          dlPollTimer = null;
        } catch (e) {}
      }
      document.getElementById('dl_btn').addEventListener('click', dlStart);
    </script>
  </body>
</html>"#;

#[derive(Debug, Deserialize)]
pub struct MobilityHistoryQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct BiometricEnrollIn {
    device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BiometricLoginIn {
    device_id: Option<String>,
    token: Option<String>,
    rotate: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct AccountCreateIn {
    device_id: Option<String>,
    // Prefer `challenge_token`; keep `pow_token` for backwards compatibility.
    challenge_token: Option<String>,
    pow_token: Option<String>,
    pow_solution: Option<String>,
    ios_devicecheck_token_b64: Option<String>,
    android_play_integrity_token: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct AccountCreateChallengeIn {
    device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct DeviceLoginStartIn {
    label: Option<String>,
    device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct DeviceLoginTokenIn {
    token: Option<String>,
    device_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct DeviceRegisterIn {
    device_id: Option<String>,
    device_type: Option<String>,
    device_name: Option<String>,
    platform: Option<String>,
    app_version: Option<String>,
}

impl AuthRuntime {
    pub async fn from_env(env_name: &str) -> Result<Option<Self>, String> {
        let env_lower = env_name.trim().to_ascii_lowercase();
        let db_url = env::var("DB_URL").unwrap_or_default();
        let db_url = db_url.trim().to_string();
        if db_url.is_empty() {
            if matches!(env_lower.as_str(), "prod" | "production" | "staging") {
                return Err("DB_URL must be configured in prod/staging for auth".to_string());
            }
            return Ok(None);
        }

        let auth_session_ttl_secs = parse_int_env("AUTH_SESSION_TTL_SECS", 86_400, 60, 604_800);
        let auth_session_idle_ttl_secs = parse_int_env(
            "AUTH_SESSION_IDLE_TTL_SECS",
            43_200.min(auth_session_ttl_secs),
            60,
            auth_session_ttl_secs,
        );
        let account_create_window_secs =
            parse_int_env("AUTH_ACCOUNT_CREATE_WINDOW_SECS", 86_400, 60, 604_800);
        // Best-practice defaults:
        // - keep IP bucket high to avoid breaking carrier NATs
        // - keep per-device bucket tight to discourage automated account farming
        let account_create_max_per_ip =
            parse_int_env("AUTH_ACCOUNT_CREATE_MAX_PER_IP", 500, 1, 200_000);
        let account_create_max_per_device =
            parse_int_env("AUTH_ACCOUNT_CREATE_MAX_PER_DEVICE", 3, 1, 1000);
        let account_create_pow_enabled = {
            let raw = env::var("AUTH_ACCOUNT_CREATE_POW_ENABLED").unwrap_or_default();
            let v = raw.trim().to_ascii_lowercase();
            if v.is_empty() {
                matches!(env_lower.as_str(), "prod" | "production" | "staging")
            } else {
                !matches!(v.as_str(), "0" | "false" | "no" | "off")
            }
        };
        let account_create_pow_ttl_secs =
            parse_int_env("AUTH_ACCOUNT_CREATE_POW_TTL_SECS", 300, 30, 3600);
        let account_create_pow_difficulty_bits =
            parse_int_env("AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS", 18, 0, 30) as u8;
        let account_create_pow_secret = env::var("AUTH_ACCOUNT_CREATE_POW_SECRET")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());
        secret_policy::validate_secret_for_env(
            env_name,
            "AUTH_ACCOUNT_CREATE_POW_SECRET",
            account_create_pow_secret.as_deref(),
            account_create_pow_enabled,
        )?;

        let account_create_hw_attestation_enabled = {
            let raw =
                env::var("AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED").unwrap_or_default();
            let v = raw.trim().to_ascii_lowercase();
            if v.is_empty() {
                matches!(env_lower.as_str(), "prod" | "production" | "staging")
            } else {
                !matches!(v.as_str(), "0" | "false" | "no" | "off")
            }
        };
        let account_create_hw_attestation_required = {
            let raw =
                env::var("AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION").unwrap_or_default();
            let v = raw.trim().to_ascii_lowercase();
            if v.is_empty() {
                account_create_hw_attestation_enabled
                    && matches!(env_lower.as_str(), "prod" | "production" | "staging")
            } else {
                !matches!(v.as_str(), "0" | "false" | "no" | "off")
            }
        };
        // Re-validate: the HMAC secret is required in prod/staging when either PoW or
        // hardware attestation is enabled (challenge token binding / nonce binding).
        secret_policy::validate_secret_for_env(
            env_name,
            "AUTH_ACCOUNT_CREATE_POW_SECRET",
            account_create_pow_secret.as_deref(),
            account_create_pow_enabled || account_create_hw_attestation_enabled,
        )?;

        let apple_team_id = env::var("AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());
        let apple_key_id = env::var("AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());
        let apple_p8_b64 = env::var("AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());

        let account_create_apple_devicecheck = if !account_create_hw_attestation_enabled {
            if apple_team_id.is_some() || apple_key_id.is_some() || apple_p8_b64.is_some() {
                tracing::warn!(
                    security_event = "account_create_hw_attestation",
                    outcome = "ignored_config",
                    provider = "apple_devicecheck",
                    "hardware attestation disabled; ignoring Apple DeviceCheck configuration"
                );
            }
            None
        } else {
            let any = apple_team_id.is_some() || apple_key_id.is_some() || apple_p8_b64.is_some();
            if !any {
                None
            } else {
                let (Some(team_id), Some(key_id), Some(p8_b64)) =
                    (apple_team_id, apple_key_id, apple_p8_b64)
                else {
                    return Err("Apple DeviceCheck attestation configured partially; set AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID, AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID and AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64".to_string());
                };
                let p8 = STANDARD.decode(p8_b64.as_bytes()).map_err(|_| {
                    "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 must be base64"
                        .to_string()
                })?;
                if p8.is_empty() {
                    return Err(
                        "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 empty"
                            .to_string(),
                    );
                }
                let _ = EncodingKey::from_ec_pem(p8.as_slice()).map_err(|_| {
                    "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 invalid key"
                        .to_string()
                })?;
                Some(AppleDeviceCheckConfig {
                    team_id,
                    key_id,
                    private_key_p8: p8,
                })
            }
        };

        let play_svc_json_b64 =
            env::var("AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64")
                .ok()
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty());
        let play_pkgs_raw =
            env::var("AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES")
                .ok()
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty());
        let play_require_strong_integrity_raw =
            env::var("AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY")
                .unwrap_or_default();
        let play_require_play_recognized_raw =
            env::var("AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED")
                .unwrap_or_default();
        let play_require_licensed_raw =
            env::var("AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED")
                .unwrap_or_default();

        let play_require_strong_integrity = {
            let v = play_require_strong_integrity_raw
                .trim()
                .to_ascii_lowercase();
            if v.is_empty() {
                matches!(env_lower.as_str(), "prod" | "production" | "staging")
            } else {
                !matches!(v.as_str(), "0" | "false" | "no" | "off")
            }
        };
        let play_require_play_recognized = {
            let v = play_require_play_recognized_raw.trim().to_ascii_lowercase();
            if v.is_empty() {
                matches!(env_lower.as_str(), "prod" | "production" | "staging")
            } else {
                !matches!(v.as_str(), "0" | "false" | "no" | "off")
            }
        };
        let play_require_licensed = {
            let v = play_require_licensed_raw.trim().to_ascii_lowercase();
            if v.is_empty() {
                false
            } else {
                !matches!(v.as_str(), "0" | "false" | "no" | "off")
            }
        };

        let account_create_play_integrity = if !account_create_hw_attestation_enabled {
            let play_config_present = play_svc_json_b64.is_some()
                || play_pkgs_raw.is_some()
                || !play_require_strong_integrity_raw.trim().is_empty()
                || !play_require_play_recognized_raw.trim().is_empty()
                || !play_require_licensed_raw.trim().is_empty();
            if play_config_present {
                tracing::warn!(
                    security_event = "account_create_hw_attestation",
                    outcome = "ignored_config",
                    provider = "google_play_integrity",
                    "hardware attestation disabled; ignoring Play Integrity configuration"
                );
            }
            None
        } else {
            let any = play_svc_json_b64.is_some() || play_pkgs_raw.is_some();
            if !any {
                None
            } else {
                let Some(svc_json_b64) = play_svc_json_b64 else {
                    return Err("Play Integrity attestation configured partially; missing AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64".to_string());
                };
                let pkgs_raw = play_pkgs_raw.unwrap_or_else(|| {
                    // Repo defaults (user/operator/admin flavors).
                    "online.shamell.app,online.shamell.app.operator,online.shamell.app.admin"
                        .to_string()
                });
                let allowed_package_names = pkgs_raw
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>();
                if allowed_package_names.is_empty() {
                    return Err("AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES must list at least one package name".to_string());
                }

                let svc_json_bytes = STANDARD
                    .decode(svc_json_b64.as_bytes())
                    .map_err(|_| "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 must be base64".to_string())?;
                let svc: serde_json::Value = serde_json::from_slice(&svc_json_bytes).map_err(|_| {
                    "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 must be base64(json)".to_string()
                })?;
                let client_email = svc
                    .get("client_email")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_string();
                let private_key = svc
                    .get("private_key")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_string();
                let token_uri = svc
                    .get("token_uri")
                    .and_then(|v| v.as_str())
                    .unwrap_or("https://oauth2.googleapis.com/token")
                    .trim()
                    .to_string();
                if client_email.is_empty() || private_key.is_empty() {
                    return Err(
                        "Play Integrity service account JSON missing client_email/private_key"
                            .to_string(),
                    );
                }
                let _ = EncodingKey::from_rsa_pem(private_key.as_bytes()).map_err(|_| {
                    "Play Integrity service account private_key invalid PEM".to_string()
                })?;
                Some(PlayIntegrityConfig {
                    allowed_package_names,
                    service_account_email: client_email,
                    service_account_private_key_pem: private_key.into_bytes(),
                    token_uri,
                    require_strong_integrity: play_require_strong_integrity,
                    require_play_recognized: play_require_play_recognized,
                    require_licensed: play_require_licensed,
                })
            }
        };

        if secret_policy::is_production_like(env_name)
            && account_create_hw_attestation_enabled
            && account_create_hw_attestation_required
            && account_create_apple_devicecheck.is_none()
            && account_create_play_integrity.is_none()
        {
            return Err("AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=true but no providers configured (Apple DeviceCheck / Google Play Integrity)".to_string());
        }

        let account_create_challenge_window_secs =
            parse_int_env("AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS", 300, 30, 3600);
        // Best practice: allow challenges to be fetched more often than actual account creation,
        // but keep per-device limits tight to reduce abuse/scanning.
        let account_create_challenge_max_per_ip =
            parse_int_env("AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP", 2000, 1, 200_000);
        let account_create_challenge_max_per_device =
            parse_int_env("AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE", 60, 1, 5000);
        let hw_provider_configured =
            account_create_apple_devicecheck.is_some() || account_create_play_integrity.is_some();
        let account_create_enabled = {
            let raw = env::var("AUTH_ACCOUNT_CREATE_ENABLED").unwrap_or_default();
            let v = raw.trim().to_ascii_lowercase();
            let default_enabled = if matches!(env_lower.as_str(), "prod" | "production" | "staging")
            {
                account_create_hw_attestation_enabled
                    && account_create_hw_attestation_required
                    && hw_provider_configured
            } else {
                true
            };
            if v.is_empty() {
                default_enabled
            } else {
                !matches!(v.as_str(), "0" | "false" | "no" | "off")
            }
        };
        if secret_policy::is_production_like(env_name)
            && account_create_enabled
            && (!account_create_hw_attestation_enabled
                || !account_create_hw_attestation_required
                || !hw_provider_configured)
        {
            return Err("AUTH_ACCOUNT_CREATE_ENABLED=true in prod/staging requires hardware attestation enabled+required and at least one configured provider".to_string());
        }
        let biometric_token_ttl_secs = parse_int_env(
            "AUTH_BIOMETRIC_TOKEN_TTL_SECS",
            31_536_000,
            86_400,
            315_360_000,
        );
        let biometric_login_window_secs =
            parse_int_env("AUTH_BIOMETRIC_LOGIN_WINDOW_SECS", 300, 30, 3600);
        let biometric_login_max_per_ip =
            parse_int_env("AUTH_BIOMETRIC_LOGIN_MAX_PER_IP", 60, 1, 5000);
        let biometric_login_max_per_device =
            parse_int_env("AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE", 30, 1, 5000);
        let device_login_ttl_secs = parse_int_env("DEVICE_LOGIN_TTL_SECS", 300, 30, 3600);
        let contact_invite_ttl_secs =
            parse_int_env("AUTH_CONTACT_INVITE_TTL_SECS", 86_400, 300, 604_800);
        let contact_invite_window_secs =
            parse_int_env("AUTH_CONTACT_INVITE_WINDOW_SECS", 300, 30, 3600);
        let contact_invite_create_max_per_ip =
            parse_int_env("AUTH_CONTACT_INVITE_CREATE_MAX_PER_IP", 120, 1, 50_000);
        let contact_invite_create_max_per_phone =
            parse_int_env("AUTH_CONTACT_INVITE_CREATE_MAX_PER_PHONE", 60, 1, 50_000);
        // Best-practice defaults:
        // - keep IP bucket high to avoid breaking carrier NATs
        // - keep per-phone/per-token buckets tighter to deter scanning abuse
        let contact_invite_redeem_max_per_ip =
            parse_int_env("AUTH_CONTACT_INVITE_REDEEM_MAX_PER_IP", 500, 1, 200_000);
        let contact_invite_redeem_max_per_phone =
            parse_int_env("AUTH_CONTACT_INVITE_REDEEM_MAX_PER_PHONE", 120, 1, 50_000);
        let contact_invite_redeem_max_per_token =
            parse_int_env("AUTH_CONTACT_INVITE_REDEEM_MAX_PER_TOKEN", 10, 1, 50_000);
        let chat_register_window_secs =
            parse_int_env("AUTH_CHAT_REGISTER_WINDOW_SECS", 300, 30, 3600);
        let chat_register_max_per_ip = parse_int_env("AUTH_CHAT_REGISTER_MAX_PER_IP", 40, 1, 5000);
        let chat_register_max_per_device =
            parse_int_env("AUTH_CHAT_REGISTER_MAX_PER_DEVICE", 20, 1, 5000);
        let chat_get_device_window_secs =
            parse_int_env("AUTH_CHAT_GET_DEVICE_WINDOW_SECS", 300, 30, 3600);
        let chat_get_device_max_per_ip =
            parse_int_env("AUTH_CHAT_GET_DEVICE_MAX_PER_IP", 120, 1, 5000);
        let chat_get_device_max_per_device =
            parse_int_env("AUTH_CHAT_GET_DEVICE_MAX_PER_DEVICE", 60, 1, 5000);
        let chat_send_window_secs = parse_int_env("AUTH_CHAT_SEND_WINDOW_SECS", 60, 10, 3600);
        // Best-practice defaults:
        // - keep IP bucket high to avoid breaking carrier NATs
        // - keep per-device bucket tight enough to deter spam
        let chat_send_max_per_ip = parse_int_env("AUTH_CHAT_SEND_MAX_PER_IP", 5000, 1, 200_000);
        let chat_send_max_per_device =
            parse_int_env("AUTH_CHAT_SEND_MAX_PER_DEVICE", 240, 1, 200_000);
        let chat_send_require_contacts = {
            let raw = env::var("AUTH_CHAT_SEND_REQUIRE_CONTACTS").unwrap_or_default();
            let v = raw.trim().to_ascii_lowercase();
            if v.is_empty() {
                matches!(env_lower.as_str(), "prod" | "production" | "staging")
            } else {
                !matches!(v.as_str(), "0" | "false" | "no" | "off")
            }
        };
        let chat_group_send_window_secs =
            parse_int_env("AUTH_CHAT_GROUP_SEND_WINDOW_SECS", 60, 10, 3600);
        // Best-practice defaults:
        // - keep IP bucket high to avoid breaking carrier NATs
        // - keep per-device bucket tight enough to deter spam
        let chat_group_send_max_per_ip =
            parse_int_env("AUTH_CHAT_GROUP_SEND_MAX_PER_IP", 5000, 1, 200_000);
        let chat_group_send_max_per_device =
            parse_int_env("AUTH_CHAT_GROUP_SEND_MAX_PER_DEVICE", 240, 1, 200_000);
        let chat_mailbox_write_window_secs =
            parse_int_env("AUTH_CHAT_MAILBOX_WRITE_WINDOW_SECS", 60, 10, 3600);
        // Best-practice defaults:
        // - keep IP bucket high to avoid breaking carrier NATs
        // - keep per-device and per-mailbox buckets tighter for spam control
        let chat_mailbox_write_max_per_ip =
            parse_int_env("AUTH_CHAT_MAILBOX_WRITE_MAX_PER_IP", 2000, 1, 50_000);
        let chat_mailbox_write_max_per_device =
            parse_int_env("AUTH_CHAT_MAILBOX_WRITE_MAX_PER_DEVICE", 120, 1, 50_000);
        let chat_mailbox_write_max_per_mailbox =
            parse_int_env("AUTH_CHAT_MAILBOX_WRITE_MAX_PER_MAILBOX", 60, 1, 50_000);
        let device_login_window_secs =
            parse_int_env("AUTH_DEVICE_LOGIN_WINDOW_SECS", 300, 30, 3600);
        let device_login_start_max_per_ip =
            parse_int_env("AUTH_DEVICE_LOGIN_START_MAX_PER_IP", 30, 1, 5000);
        let device_login_redeem_max_per_ip =
            parse_int_env("AUTH_DEVICE_LOGIN_REDEEM_MAX_PER_IP", 60, 1, 5000);
        let device_login_approve_max_per_phone =
            parse_int_env("AUTH_DEVICE_LOGIN_APPROVE_MAX_PER_PHONE", 30, 1, 500);
        let device_login_redeem_max_per_token =
            parse_int_env("AUTH_DEVICE_LOGIN_REDEEM_MAX_PER_TOKEN", 30, 1, 5000);
        let device_login_approve_max_per_token =
            parse_int_env("AUTH_DEVICE_LOGIN_APPROVE_MAX_PER_TOKEN", 20, 1, 5000);
        let maintenance_interval_secs =
            parse_int_env("AUTH_MAINTENANCE_INTERVAL_SECS", 3600, 60, 86_400);
        let session_cleanup_grace_secs =
            parse_int_env("AUTH_SESSION_CLEANUP_GRACE_SECS", 86_400, 0, 31_536_000);
        let device_login_cleanup_grace_secs = parse_int_env(
            "AUTH_DEVICE_LOGIN_CLEANUP_GRACE_SECS",
            86_400,
            0,
            31_536_000,
        );
        let device_session_retention_secs = parse_int_env(
            "AUTH_DEVICE_SESSION_RETENTION_SECS",
            7_776_000,
            86_400,
            63_072_000,
        );
        let rate_limit_retention_secs =
            parse_int_env("AUTH_RATE_LIMIT_RETENTION_SECS", 86_400, 60, 31_536_000);

        let pool = PgPool::connect(&db_url)
            .await
            .map_err(|e| format!("auth postgres connect failed: {e}"))?;
        ensure_auth_schema(&pool)
            .await
            .map_err(|e| format!("auth schema init failed: {e}"))?;

        Ok(Some(Self {
            pool,
            auth_session_ttl_secs,
            auth_session_idle_ttl_secs,
            account_create_window_secs,
            account_create_max_per_ip,
            account_create_max_per_device,
            account_create_challenge_window_secs,
            account_create_challenge_max_per_ip,
            account_create_challenge_max_per_device,
            account_create_enabled,
            account_create_pow_enabled,
            account_create_pow_ttl_secs,
            account_create_pow_difficulty_bits,
            account_create_pow_secret,
            account_create_hw_attestation_enabled,
            account_create_hw_attestation_required,
            account_create_apple_devicecheck,
            account_create_play_integrity,
            biometric_token_ttl_secs,
            biometric_login_window_secs,
            biometric_login_max_per_ip,
            biometric_login_max_per_device,
            device_login_ttl_secs,
            contact_invite_ttl_secs,
            contact_invite_window_secs,
            contact_invite_create_max_per_ip,
            contact_invite_create_max_per_phone,
            contact_invite_redeem_max_per_ip,
            contact_invite_redeem_max_per_phone,
            contact_invite_redeem_max_per_token,
            chat_register_window_secs,
            chat_register_max_per_ip,
            chat_register_max_per_device,
            chat_get_device_window_secs,
            chat_get_device_max_per_ip,
            chat_get_device_max_per_device,
            chat_send_window_secs,
            chat_send_max_per_ip,
            chat_send_max_per_device,
            chat_send_require_contacts,
            chat_group_send_window_secs,
            chat_group_send_max_per_ip,
            chat_group_send_max_per_device,
            chat_mailbox_write_window_secs,
            chat_mailbox_write_max_per_ip,
            chat_mailbox_write_max_per_device,
            chat_mailbox_write_max_per_mailbox,
            device_login_window_secs,
            device_login_start_max_per_ip,
            device_login_redeem_max_per_ip,
            device_login_approve_max_per_phone,
            device_login_redeem_max_per_token,
            device_login_approve_max_per_token,
            maintenance_interval_secs,
            session_cleanup_grace_secs,
            device_login_cleanup_grace_secs,
            device_session_retention_secs,
            rate_limit_retention_secs,
        }))
    }
}

pub fn spawn_maintenance_task(auth: Option<AuthRuntime>) {
    let Some(auth) = auth else {
        return;
    };
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(std::time::Duration::from_secs(
            auth.maintenance_interval_secs as u64,
        ));
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            ticker.tick().await;
            if let Err(e) = run_maintenance_once(&auth).await {
                tracing::error!(error = %e, "auth maintenance failed");
            }
        }
    });
}

async fn run_maintenance_once(auth: &AuthRuntime) -> Result<(), sqlx::Error> {
    let session_idle_cleanup_secs = auth
        .auth_session_idle_ttl_secs
        .saturating_add(auth.session_cleanup_grace_secs);
    sqlx::query(
        "DELETE FROM auth_sessions WHERE last_seen_at < NOW() - ($1::bigint * INTERVAL '1 second')",
    )
    .bind(session_idle_cleanup_secs)
    .execute(&auth.pool)
    .await?;

    sqlx::query(
        "DELETE FROM auth_sessions WHERE expires_at < NOW() - ($1::bigint * INTERVAL '1 second')",
    )
    .bind(auth.session_cleanup_grace_secs)
    .execute(&auth.pool)
    .await?;

    sqlx::query(
        "DELETE FROM device_login_challenges WHERE expires_at < NOW() - ($1::bigint * INTERVAL '1 second')",
    )
    .bind(auth.device_login_cleanup_grace_secs)
    .execute(&auth.pool)
    .await?;

    sqlx::query(
        "DELETE FROM device_sessions WHERE last_seen_at < NOW() - ($1::bigint * INTERVAL '1 second')",
    )
    .bind(auth.device_session_retention_secs)
    .execute(&auth.pool)
    .await?;

    sqlx::query(
        "DELETE FROM auth_biometric_tokens WHERE expires_at < NOW() - ($1::bigint * INTERVAL '1 second')",
    )
    .bind(auth.session_cleanup_grace_secs)
    .execute(&auth.pool)
    .await?;

    sqlx::query(
        "DELETE FROM auth_contact_invites WHERE expires_at < NOW() - ($1::bigint * INTERVAL '1 second')",
    )
    .bind(auth.session_cleanup_grace_secs)
    .execute(&auth.pool)
    .await?;

    sqlx::query(
        "DELETE FROM auth_rate_limits WHERE updated_at < NOW() - ($1::bigint * INTERVAL '1 second')",
    )
    .bind(auth.rate_limit_retention_secs)
    .execute(&auth.pool)
    .await?;

    Ok(())
}

pub async fn login_page() -> Html<String> {
    Html(legacy_console_removed_page("Shamell Login"))
}

pub async fn root_redirect(State(state): State<AppState>, headers: HeaderMap) -> Response {
    if auth_principal_from_headers(&state, &headers)
        .await
        .is_some()
    {
        return Redirect::to("/app").into_response();
    }
    Redirect::to("/login").into_response()
}

pub async fn home_page(State(state): State<AppState>, headers: HeaderMap) -> Response {
    if auth_principal_from_headers(&state, &headers)
        .await
        .is_some()
    {
        return Redirect::to("/app").into_response();
    }
    Redirect::to("/login").into_response()
}

pub async fn app_shell(State(state): State<AppState>, headers: HeaderMap) -> Response {
    if auth_principal_from_headers(&state, &headers)
        .await
        .is_none()
    {
        return Redirect::to("/login").into_response();
    }
    Html(legacy_console_removed_page("Shamell BFF")).into_response()
}

pub async fn device_login_page(State(state): State<AppState>) -> ApiResult<Html<&'static str>> {
    if !state.auth_device_login_web_enabled {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "Not Found"));
    }
    Ok(Html(DEVICE_LOGIN_DEMO_HTML))
}

pub async fn device_login_demo(State(state): State<AppState>) -> ApiResult<Html<&'static str>> {
    if !state.auth_device_login_web_enabled {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "Not Found"));
    }
    Ok(Html(DEVICE_LOGIN_DEMO_HTML))
}

#[derive(Debug, Deserialize)]
pub struct QrSvgIn {
    pub data: Option<String>,
    pub size: Option<u32>,
}

pub async fn qr_svg(
    State(state): State<AppState>,
    Json(body): Json<QrSvgIn>,
) -> ApiResult<Response> {
    // Keep this endpoint dev/test-only: it is only used by local demo pages.
    let env_lower = state.env_name.trim().to_ascii_lowercase();
    if matches!(env_lower.as_str(), "prod" | "production" | "staging") {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "Not Found"));
    }

    let raw = body.data.unwrap_or_default();
    let data = raw.trim();
    if data.is_empty() || data.len() > 2048 {
        return Err(ApiError::bad_request("invalid data"));
    }

    let size = body.size.unwrap_or(220).clamp(96, 512);
    let code = QrCode::new(data.as_bytes()).map_err(|_| ApiError::bad_request("invalid data"))?;
    let svg_str = code
        .render::<svg::Color>()
        .min_dimensions(size, size)
        .quiet_zone(true)
        .build();

    let mut resp = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "image/svg+xml; charset=utf-8")
        .body(Body::from(svg_str))
        .map_err(|_| ApiError::internal("failed to build response"))?;
    append_no_store(&mut resp);
    Ok(resp)
}

#[derive(Debug, Deserialize)]
pub struct DeviceLoginQrSvgIn {
    pub token: Option<String>,
    pub size: Option<u32>,
}

pub async fn auth_device_login_qr_svg(
    State(state): State<AppState>,
    Json(body): Json<DeviceLoginQrSvgIn>,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    let token = normalize_hex_32(&body.token.unwrap_or_default())
        .ok_or_else(|| ApiError::bad_request("token required"))?;
    let token_hash = sha256_hex(&token);

    // Avoid becoming a generic QR generator: only emit QRs for an active device-login challenge.
    let row = sqlx::query(
        "SELECT label, (expires_at > NOW()) AS alive FROM device_login_challenges WHERE token_hash=$1 LIMIT 1",
    )
    .bind(&token_hash)
    .fetch_optional(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "device_login qr lookup failed");
        ApiError::internal("device login lookup failed")
    })?;
    let Some(row) = row else {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "challenge not found"));
    };
    let alive: bool = row.try_get("alive").unwrap_or(false);
    if !alive {
        return Err(ApiError::bad_request("challenge expired"));
    }
    let label: Option<String> = row.try_get("label").unwrap_or(None);
    let label = label.unwrap_or_default();
    let label = label.trim();

    let mut payload = format!("shamell://device_login?token={token}");
    if !label.is_empty() {
        payload.push_str("&label=");
        payload.push_str(&url_escape_component(label));
    }

    let size = body.size.unwrap_or(220).clamp(96, 512);
    let code =
        QrCode::new(payload.as_bytes()).map_err(|_| ApiError::bad_request("invalid data"))?;
    let svg_str = code
        .render::<svg::Color>()
        .min_dimensions(size, size)
        .quiet_zone(true)
        .build();

    let mut resp = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "image/svg+xml; charset=utf-8")
        .body(Body::from(svg_str))
        .map_err(|_| ApiError::internal("failed to build response"))?;
    append_no_store(&mut resp);
    Ok(resp)
}

pub async fn auth_biometric_enroll(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<BiometricEnrollIn>,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    let principal = require_session_principal(&state, &headers).await?;
    let account_id = principal.account_id.trim().to_string();
    let phone = principal
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let device_id = normalize_device_id(body.device_id.as_deref())
        .ok_or_else(|| ApiError::bad_request("device_id required"))?;

    let token = generate_token_hex_32();
    let token_hash = sha256_hex(&format!("bio:{device_id}:{token}"));
    let token_hash_pref = token_hash_prefix(&token_hash);
    sqlx::query(
        r#"
        INSERT INTO auth_biometric_tokens
          (token_hash, account_id, phone, device_id, created_at, last_used_at, expires_at, revoked_at)
        VALUES
          ($1, $2, $3, $4, NOW(), NULL, NOW() + ($5::bigint * INTERVAL '1 second'), NULL)
        ON CONFLICT (account_id, device_id)
        DO UPDATE SET
          token_hash = EXCLUDED.token_hash,
          phone = COALESCE(EXCLUDED.phone, auth_biometric_tokens.phone),
          created_at = NOW(),
          last_used_at = NULL,
          expires_at = EXCLUDED.expires_at,
          revoked_at = NULL
        "#,
    )
    .bind(&token_hash)
    .bind(&account_id)
    .bind(phone)
    .bind(&device_id)
    .bind(auth.biometric_token_ttl_secs)
    .execute(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            account_hash = %hash_prefix(&account_id),
            device_id = %device_id,
            token_hash_prefix = %token_hash_pref,
            "biometric enroll upsert failed"
        );
        ApiError::internal("failed to enroll biometrics")
    })?;

    Ok(json_no_store(json!({
        "ok": true,
        "device_id": device_id,
        "token": token,
        "ttl": auth.biometric_token_ttl_secs,
    })))
}

pub async fn auth_biometric_login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<BiometricLoginIn>,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    let client_ip = rate_limit_client_ip(&state, &headers)?;
    let rotate_token = body.rotate.unwrap_or(false);
    let device_id = normalize_device_id(body.device_id.as_deref())
        .ok_or_else(|| ApiError::bad_request("device_id required"))?;
    let token_raw = body.token.as_deref().unwrap_or_default();
    let token =
        normalize_hex_64(token_raw).ok_or_else(|| ApiError::bad_request("invalid token"))?;

    consume_rate_limit(
        auth,
        &format!("bio_login_ip:{client_ip}"),
        auth.biometric_login_window_secs,
        auth.biometric_login_max_per_ip,
    )
    .await?;
    consume_rate_limit(
        auth,
        &format!("bio_login_device:{device_id}"),
        auth.biometric_login_window_secs,
        auth.biometric_login_max_per_device,
    )
    .await?;

    let token_hash = sha256_hex(&format!("bio:{device_id}:{token}"));
    let token_hash_pref = token_hash_prefix(&token_hash);
    let row = sqlx::query(
        "SELECT account_id, phone, (revoked_at IS NULL AND expires_at > NOW()) AS alive FROM auth_biometric_tokens WHERE token_hash=$1 AND device_id=$2 LIMIT 1",
    )
    .bind(&token_hash)
    .bind(&device_id)
    .fetch_optional(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            token_hash_prefix = %token_hash_pref,
            device_id = %device_id,
            "biometric login select failed"
        );
        ApiError::internal("failed to sign in")
    })?;
    let Some(row) = row else {
        tracing::warn!(
            token_hash_prefix = %token_hash_pref,
            device_id = %device_id,
            ip = %client_ip,
            "biometric login unauthorized"
        );
        audit_device_login_event(
            "biometric_login",
            "blocked",
            Some(client_ip.as_str()),
            None,
            Some(token_hash.as_str()),
            Some("unauthorized"),
        );
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    };
    let account_id: Option<String> = row.try_get("account_id").ok();
    let phone: Option<String> = row.try_get("phone").ok();
    let alive: bool = row.try_get("alive").unwrap_or(false);
    let phone_opt = phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string);
    if !alive {
        tracing::warn!(
            token_hash_prefix = %token_hash_pref,
            device_id = %device_id,
            ip = %client_ip,
            "biometric login rejected"
        );
        audit_device_login_event(
            "biometric_login",
            "blocked",
            Some(client_ip.as_str()),
            phone_opt.as_deref(),
            Some(token_hash.as_str()),
            Some("revoked_or_expired"),
        );
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }
    let account_id = account_id.unwrap_or_default().trim().to_string();
    let account_id = if !account_id.is_empty() {
        account_id
    } else if let Some(phone) = phone_opt.as_deref() {
        // Legacy tokens may be bound by phone only.
        let id = ensure_account_id_for_phone(auth, phone).await?;
        let _ = sqlx::query(
            "UPDATE auth_biometric_tokens SET account_id=$1 WHERE token_hash=$2 AND device_id=$3 AND account_id IS NULL",
        )
        .bind(&id)
        .bind(&token_hash)
        .bind(&device_id)
        .execute(&auth.pool)
        .await;
        id
    } else {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    };

    let _wallet =
        ensure_wallet_for_account(&state, &headers, &account_id, phone_opt.as_deref()).await?;

    let sid = generate_token_hex_16();
    let sid_hash = sha256_hex(&sid);
    sqlx::query(
        r#"
        INSERT INTO auth_sessions
          (sid_hash, account_id, phone, device_id, expires_at, created_at, last_seen_at, revoked_at)
        VALUES
          ($1, $2, $3, $4, NOW() + ($5::bigint * INTERVAL '1 second'), NOW(), NOW(), NULL)
        "#,
    )
    .bind(&sid_hash)
    .bind(&account_id)
    .bind(phone_opt.as_deref())
    .bind(Some(device_id.as_str()))
    .bind(auth.auth_session_ttl_secs)
    .execute(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "biometric login insert session failed");
        ApiError::internal("failed to sign in")
    })?;

    let mut new_token: Option<String> = None;
    if rotate_token {
        let t = generate_token_hex_32();
        let t_hash = sha256_hex(&format!("bio:{device_id}:{t}"));
        match sqlx::query(
            "UPDATE auth_biometric_tokens SET token_hash=$1, last_used_at=NOW() WHERE account_id=$2 AND device_id=$3 AND token_hash=$4 AND revoked_at IS NULL AND expires_at > NOW()",
        )
        .bind(&t_hash)
        .bind(&account_id)
        .bind(&device_id)
        .bind(&token_hash)
        .execute(&auth.pool)
        .await
        {
            Ok(r) => {
                if r.rows_affected() == 1 {
                    new_token = Some(t);
                }
            }
            Err(e) => {
                tracing::error!(
                    security_event = "biometric_token_rotate",
                    outcome = "failed",
                    error = %e,
                    account_hash = %hash_prefix(&account_id),
                    device_id = %device_id,
                    client_ip = %client_ip,
                    token_hash_prefix = %token_hash_pref,
                    "biometric token rotation failed"
                );
            }
        }
    }
    if new_token.is_none() {
        let _ =
            sqlx::query("UPDATE auth_biometric_tokens SET last_used_at=NOW() WHERE token_hash=$1")
                .bind(&token_hash)
                .execute(&auth.pool)
                .await;
    }

    let mut payload = json!({"ok": true});
    if let Some(t) = new_token {
        payload["token"] = Value::String(t);
        payload["ttl"] = json!(auth.biometric_token_ttl_secs);
    }

    let mut resp = Json(payload).into_response();
    append_set_cookie(
        &mut resp,
        &session_cookie_value(&sid, auth.auth_session_ttl_secs),
    );
    append_set_cookie(&mut resp, &clear_legacy_session_cookie_value());
    append_no_store(&mut resp);
    Ok(resp)
}

pub async fn auth_account_create_challenge(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<AccountCreateChallengeIn>,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    if !auth.account_create_enabled {
        tracing::warn!(
            security_event = "account_create",
            outcome = "disabled",
            "account creation challenge disabled by policy"
        );
        return Err(ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "account creation temporarily unavailable",
        ));
    }
    let client_ip = rate_limit_client_ip(&state, &headers)?;
    consume_rate_limit(
        auth,
        &format!("auth_account_create_challenge_ip:{client_ip}"),
        auth.account_create_challenge_window_secs,
        auth.account_create_challenge_max_per_ip,
    )
    .await?;

    let device_id = normalize_device_id(body.device_id.as_deref())
        .ok_or_else(|| ApiError::bad_request("device_id required"))?;
    consume_rate_limit(
        auth,
        &format!("auth_account_create_challenge_device:{device_id}"),
        auth.account_create_challenge_window_secs,
        auth.account_create_challenge_max_per_device,
    )
    .await?;

    let hw_providers = {
        let mut out = Vec::new();
        if auth.account_create_apple_devicecheck.is_some() {
            out.push("apple_devicecheck");
        }
        if auth.account_create_play_integrity.is_some() {
            out.push("google_play_integrity");
        }
        out
    };
    let hw_attestation_enabled =
        auth.account_create_hw_attestation_enabled && !hw_providers.is_empty();
    let hw_attestation_required =
        hw_attestation_enabled && auth.account_create_hw_attestation_required;

    if !auth.account_create_pow_enabled && !hw_attestation_enabled {
        let mut resp = Json(json!({
            "ok": true,
            "enabled": false,
            "hw_attestation_enabled": false,
            "hw_attestation_required": false,
        }))
        .into_response();
        append_no_store(&mut resp);
        return Ok(resp);
    }

    let Some(secret) = auth.account_create_pow_secret.as_deref() else {
        tracing::error!(
            account_create_pow_enabled = auth.account_create_pow_enabled,
            hw_attestation_enabled,
            "account-create attestation enabled but missing secret"
        );
        return Err(ApiError::internal("account create unavailable"));
    };

    let nonce = generate_token_hex_16();
    let now = unix_now_secs();
    let exp = now.saturating_add(auth.account_create_pow_ttl_secs);
    let payload = AccountCreatePowPayload {
        v: 1,
        device_id: device_id.clone(),
        nonce: nonce.clone(),
        difficulty: auth.account_create_pow_difficulty_bits,
        exp,
    };
    let token = encode_pow_token(secret, &payload)
        .ok_or_else(|| ApiError::internal("account create unavailable"))?;

    tracing::info!(
        security_event = "account_create_challenge",
        outcome = "ok",
        client_ip = %client_ip,
        device_id = %device_id,
        difficulty = payload.difficulty,
        "issued account-create attestation challenge"
    );

    let att_nonce_b64 = account_create_attestation_nonce_b64(&token).unwrap_or_default();
    let mut resp = Json(json!({
        "ok": true,
        "enabled": auth.account_create_pow_enabled,
        "token": token,
        "challenge_token": token,
        "nonce": nonce,
        "difficulty_bits": payload.difficulty,
        "expires_at": payload.exp,
        "hw_attestation_enabled": hw_attestation_enabled,
        "hw_attestation_required": hw_attestation_required,
        "hw_attestation_nonce_b64": att_nonce_b64,
        "hw_attestation_providers": hw_providers,
    }))
    .into_response();
    append_no_store(&mut resp);
    Ok(resp)
}

pub async fn auth_account_create(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<AccountCreateIn>,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    if !auth.account_create_enabled {
        tracing::warn!(
            security_event = "account_create",
            outcome = "disabled",
            "account creation disabled by policy"
        );
        return Err(ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "account creation temporarily unavailable",
        ));
    }
    let client_ip = rate_limit_client_ip(&state, &headers)?;
    consume_rate_limit(
        auth,
        &format!("auth_account_create_ip:{client_ip}"),
        auth.account_create_window_secs,
        auth.account_create_max_per_ip,
    )
    .await?;

    let device_id = normalize_device_id(body.device_id.as_deref())
        .ok_or_else(|| ApiError::bad_request("device_id required"))?;
    consume_rate_limit(
        auth,
        &format!("auth_account_create_device:{device_id}"),
        auth.account_create_window_secs,
        auth.account_create_max_per_device,
    )
    .await?;

    let hw_attestation_enabled = auth.account_create_hw_attestation_enabled
        && (auth.account_create_apple_devicecheck.is_some()
            || auth.account_create_play_integrity.is_some());
    let hw_attestation_required =
        hw_attestation_enabled && auth.account_create_hw_attestation_required;

    // When either PoW or hardware attestation is enabled, require a signed challenge token so:
    // - it can be expired server-side
    // - it can be bound to hardware attestation nonces (Android Play Integrity)
    // - it cannot be forged without the HMAC secret
    let pow_required = auth.account_create_pow_enabled;
    let needs_challenge = pow_required || hw_attestation_enabled;
    let challenge_token = body
        .challenge_token
        .as_deref()
        .or(body.pow_token.as_deref())
        .unwrap_or_default()
        .trim()
        .to_string();

    let mut expected_hw_nonce_b64: Option<String> = None;
    if needs_challenge {
        let Some(secret) = auth.account_create_pow_secret.as_deref() else {
            tracing::error!(
                account_create_pow_enabled = pow_required,
                hw_attestation_enabled,
                "account-create attestation enabled but missing secret"
            );
            return Err(ApiError::internal("account create unavailable"));
        };
        if challenge_token.is_empty() {
            tracing::warn!(
                security_event = "account_create_attestation",
                outcome = "missing_token",
                client_ip = %client_ip,
                device_id = %device_id,
                "account create missing challenge token"
            );
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "attestation required",
            ));
        }
        let now = unix_now_secs();
        let payload = decode_pow_token(secret, &challenge_token).ok_or_else(|| {
            tracing::warn!(
                security_event = "account_create_attestation",
                outcome = "invalid_token",
                client_ip = %client_ip,
                device_id = %device_id,
                "account create invalid challenge token"
            );
            ApiError::new(StatusCode::UNAUTHORIZED, "attestation required")
        })?;
        if payload.exp <= now || payload.device_id.trim() != device_id.trim() {
            tracing::warn!(
                security_event = "account_create_attestation",
                outcome = "expired_or_mismatch",
                client_ip = %client_ip,
                device_id = %device_id,
                "account create expired or mismatched challenge token"
            );
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "attestation required",
            ));
        }
        expected_hw_nonce_b64 = account_create_attestation_nonce_b64(&challenge_token);
    }

    if pow_required {
        let Some(secret) = auth.account_create_pow_secret.as_deref() else {
            tracing::error!("account-create pow enabled but missing secret");
            return Err(ApiError::internal("account create unavailable"));
        };
        let solution = body.pow_solution.as_deref().unwrap_or_default();
        if solution.trim().is_empty() {
            tracing::warn!(
                security_event = "account_create_attestation",
                outcome = "missing_pow",
                client_ip = %client_ip,
                device_id = %device_id,
                "account create missing PoW solution"
            );
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "attestation required",
            ));
        }
        if !verify_pow_solution(secret, &device_id, &challenge_token, solution) {
            tracing::warn!(
                security_event = "account_create_attestation",
                outcome = "invalid_pow",
                client_ip = %client_ip,
                device_id = %device_id,
                "account create invalid PoW solution"
            );
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "attestation required",
            ));
        }
    }

    if hw_attestation_enabled {
        let ios_tok = body
            .ios_devicecheck_token_b64
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty());
        let android_tok = body
            .android_play_integrity_token
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty());
        let has_any = ios_tok.is_some() || android_tok.is_some();
        if hw_attestation_required && !has_any {
            tracing::warn!(
                security_event = "account_create_hw_attestation",
                outcome = "missing",
                client_ip = %client_ip,
                device_id = %device_id,
                "account create missing hardware attestation"
            );
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "attestation required",
            ));
        }

        let mut ok = false;
        let mut attempted = false;

        if let Some(tok) = ios_tok {
            attempted = true;
            let Some(cfg) = auth.account_create_apple_devicecheck.as_ref() else {
                tracing::error!(
                    security_event = "account_create_hw_attestation",
                    outcome = "misconfigured",
                    provider = "apple_devicecheck",
                    "hardware attestation token provided but provider not configured"
                );
                return Err(ApiError::new(
                    StatusCode::UNAUTHORIZED,
                    "attestation required",
                ));
            };
            ok = verify_apple_devicecheck_token(&state.http, cfg, tok).await?;
            if !ok {
                tracing::warn!(
                    security_event = "account_create_hw_attestation",
                    outcome = "invalid",
                    provider = "apple_devicecheck",
                    client_ip = %client_ip,
                    device_id = %device_id,
                    "hardware attestation invalid"
                );
            }
        }

        if !ok {
            if let Some(tok) = android_tok {
                attempted = true;
                let Some(cfg) = auth.account_create_play_integrity.as_ref() else {
                    tracing::error!(
                        security_event = "account_create_hw_attestation",
                        outcome = "misconfigured",
                        provider = "google_play_integrity",
                        "hardware attestation token provided but provider not configured"
                    );
                    return Err(ApiError::new(
                        StatusCode::UNAUTHORIZED,
                        "attestation required",
                    ));
                };
                let Some(expected_nonce_b64) = expected_hw_nonce_b64.as_deref() else {
                    tracing::error!(
                        security_event = "account_create_hw_attestation",
                        outcome = "missing_nonce",
                        provider = "google_play_integrity",
                        "missing expected nonce"
                    );
                    return Err(ApiError::internal("account create unavailable"));
                };
                ok = verify_play_integrity_token(&state.http, cfg, tok, expected_nonce_b64).await?;
                if !ok {
                    tracing::warn!(
                        security_event = "account_create_hw_attestation",
                        outcome = "invalid",
                        provider = "google_play_integrity",
                        client_ip = %client_ip,
                        device_id = %device_id,
                        "hardware attestation invalid"
                    );
                }
            }
        }

        if (hw_attestation_required || attempted) && !ok {
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "attestation required",
            ));
        }
    }

    // Allocate a new account + Shamell ID, then create a fresh server session.
    // Best practice: do it in a transaction so we don't leave orphaned sessions.
    for _ in 0..12 {
        let account_id = generate_token_hex_32();
        let shamell_id = generate_shamell_user_id();
        let sid = generate_token_hex_16();
        let sid_hash = sha256_hex(&sid);

        let mut tx = auth.pool.begin().await.map_err(|e| {
            tracing::error!(error = %e, "account_create tx begin failed");
            ApiError::internal("account create unavailable")
        })?;

        let inserted = sqlx::query(
            "INSERT INTO auth_accounts (account_id, shamell_user_id, phone) VALUES ($1, $2, NULL)",
        )
        .bind(&account_id)
        .bind(&shamell_id)
        .execute(&mut *tx)
        .await;

        match inserted {
            Ok(r) => {
                if r.rows_affected() != 1 {
                    let _ = tx.rollback().await;
                    continue;
                }
            }
            Err(e) => {
                let unique_violation = match &e {
                    sqlx::Error::Database(db) => db.code().as_deref() == Some("23505"),
                    _ => false,
                };
                let _ = tx.rollback().await;
                if unique_violation {
                    continue;
                }
                tracing::error!(error = %e, "auth_accounts insert failed for account_create");
                return Err(ApiError::internal("failed to create account"));
            }
        }

        if let Err(e) = sqlx::query(
            r#"
            INSERT INTO auth_sessions
              (sid_hash, account_id, phone, device_id, expires_at, created_at, last_seen_at, revoked_at)
            VALUES
              ($1, $2, NULL, $3, NOW() + ($4::bigint * INTERVAL '1 second'), NOW(), NOW(), NULL)
            "#,
        )
        .bind(&sid_hash)
        .bind(&account_id)
        .bind(&device_id)
        .bind(auth.auth_session_ttl_secs)
        .execute(&mut *tx)
        .await
        {
            let _ = tx.rollback().await;
            tracing::error!(error = %e, "auth_sessions insert failed for account_create");
            return Err(ApiError::internal("failed to create session"));
        }

        tx.commit().await.map_err(|e| {
            tracing::error!(error = %e, "account_create tx commit failed");
            ApiError::internal("account create unavailable")
        })?;

        tracing::info!(
            security_event = "account_create",
            outcome = "ok",
            client_ip = %client_ip,
            account_hash = %hash_prefix(&account_id),
            device_id = %device_id,
            "new account created"
        );

        let mut resp = Json(json!({"ok": true, "shamell_id": shamell_id})).into_response();
        append_set_cookie(
            &mut resp,
            &session_cookie_value(&sid, auth.auth_session_ttl_secs),
        );
        append_set_cookie(&mut resp, &clear_legacy_session_cookie_value());
        append_no_store(&mut resp);
        return Ok(resp);
    }

    Err(ApiError::internal("failed to allocate account"))
}

pub async fn auth_logout(State(state): State<AppState>, headers: HeaderMap) -> ApiResult<Response> {
    if let Some(auth) = state.auth.as_ref() {
        if let Some(sid) = extract_session_token(&headers, state.accept_legacy_session_cookie) {
            let sid_hash = sha256_hex(&sid);
            let _ = sqlx::query("DELETE FROM auth_sessions WHERE sid_hash=$1")
                .bind(&sid_hash)
                .execute(&auth.pool)
                .await;
        }
    }
    let mut resp = Json(json!({"ok": true})).into_response();
    append_set_cookie(&mut resp, &clear_session_cookie_value());
    append_set_cookie(&mut resp, &clear_legacy_session_cookie_value());
    append_no_store(&mut resp);
    Ok(resp)
}

pub async fn auth_device_login_start(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<DeviceLoginStartIn>,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    let client_ip = rate_limit_client_ip(&state, &headers)?;
    consume_rate_limit(
        auth,
        &format!("auth_device_start_ip:{client_ip}"),
        auth.device_login_window_secs,
        auth.device_login_start_max_per_ip,
    )
    .await?;

    let token = generate_token_hex_16();
    let token_hash = sha256_hex(&token);
    let mut label = body.label.unwrap_or_default().trim().to_string();
    if label.len() > 64 {
        label.truncate(64);
    }
    let device_id = normalize_device_id(body.device_id.as_deref());

    sqlx::query(
        r#"
        INSERT INTO device_login_challenges
          (token_hash, label, status, phone, device_id, created_at, expires_at, approved_at)
        VALUES
          ($1, $2, 'pending', NULL, $3, NOW(), NOW() + ($4::bigint * INTERVAL '1 second'), NULL)
        "#,
    )
    .bind(&token_hash)
    .bind(if label.is_empty() {
        None::<String>
    } else {
        Some(label.clone())
    })
    .bind(device_id.as_deref())
    .bind(auth.device_login_ttl_secs)
    .execute(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "device_login start insert failed");
        ApiError::internal("failed to start device login")
    })?;
    audit_device_login_event(
        "device_login_start",
        "issued",
        Some(client_ip.as_str()),
        None,
        Some(token_hash.as_str()),
        None,
    );

    Ok(json_no_store(
        json!({"ok": true, "token": token, "label": label}),
    ))
}

pub async fn auth_device_login_approve(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<DeviceLoginTokenIn>,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    let client_ip = client_ip_from_headers(&state, &headers);
    let principal = require_session_principal(&state, &headers).await?;
    let account_id = principal.account_id.trim().to_string();
    let phone = principal
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    consume_rate_limit(
        auth,
        &format!("auth_device_approve_account:{}", hash_prefix(&account_id)),
        auth.device_login_window_secs,
        auth.device_login_approve_max_per_phone,
    )
    .await?;
    let token = normalize_hex_32(&body.token.unwrap_or_default())
        .ok_or_else(|| ApiError::bad_request("token required"))?;
    let token_hash = sha256_hex(&token);
    consume_rate_limit(
        auth,
        &format!("auth_device_approve_token:{token_hash}"),
        auth.device_login_window_secs,
        auth.device_login_approve_max_per_token,
    )
    .await?;

    let row = sqlx::query(
        "SELECT id, status, account_id, phone, (expires_at > NOW()) AS alive FROM device_login_challenges WHERE token_hash=$1 LIMIT 1",
    )
    .bind(&token_hash)
    .fetch_optional(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "device_login approve select failed");
        ApiError::internal("device login lookup failed")
    })?;

    let Some(row) = row else {
        audit_device_login_event(
            "device_login_approve",
            "blocked",
            client_ip.as_deref(),
            phone,
            Some(token_hash.as_str()),
            Some("challenge_not_found"),
        );
        return Err(ApiError::new(StatusCode::NOT_FOUND, "challenge not found"));
    };

    let id: i64 = row.try_get("id").unwrap_or_default();
    let status: String = row.try_get("status").unwrap_or_default();
    let bound_account_id: Option<String> = row.try_get("account_id").unwrap_or(None);
    let bound_phone: Option<String> = row.try_get("phone").unwrap_or(None);
    let alive: bool = row.try_get("alive").unwrap_or(false);
    if !alive {
        let _ = sqlx::query("DELETE FROM device_login_challenges WHERE id=$1")
            .bind(id)
            .execute(&auth.pool)
            .await;
        audit_device_login_event(
            "device_login_approve",
            "blocked",
            client_ip.as_deref(),
            phone,
            Some(token_hash.as_str()),
            Some("challenge_expired"),
        );
        return Err(ApiError::bad_request("challenge expired"));
    }

    let status_l = status.trim().to_ascii_lowercase();
    if status_l == "approved" {
        if let Some(bound) = bound_account_id
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            if bound != account_id {
                audit_device_login_event(
                    "device_login_approve",
                    "blocked",
                    client_ip.as_deref(),
                    phone,
                    Some(token_hash.as_str()),
                    Some("challenge_already_bound_to_other_account"),
                );
                return Err(ApiError::new(
                    StatusCode::CONFLICT,
                    "challenge already approved",
                ));
            }
        }
        if let Some(bound) = bound_phone {
            if let Some(p) = phone {
                if !bound.trim().is_empty() && bound.trim() != p {
                    audit_device_login_event(
                        "device_login_approve",
                        "blocked",
                        client_ip.as_deref(),
                        Some(p),
                        Some(token_hash.as_str()),
                        Some("challenge_already_bound_to_other_phone"),
                    );
                    return Err(ApiError::new(
                        StatusCode::CONFLICT,
                        "challenge already approved",
                    ));
                }
            }
        }

        // Best-effort migration: attach account_id when legacy approve only stored phone.
        if bound_account_id.as_deref().unwrap_or("").trim().is_empty() {
            let _ = sqlx::query(
                "UPDATE device_login_challenges SET account_id=$1 WHERE id=$2 AND account_id IS NULL",
            )
            .bind(&account_id)
            .bind(id)
            .execute(&auth.pool)
            .await;
        }

        audit_device_login_event(
            "device_login_approve",
            "already_approved",
            client_ip.as_deref(),
            phone,
            Some(token_hash.as_str()),
            None,
        );
        return Ok(json_no_store(json!({"ok": true, "token": token})));
    }
    if status_l != "pending" {
        audit_device_login_event(
            "device_login_approve",
            "blocked",
            client_ip.as_deref(),
            phone,
            Some(token_hash.as_str()),
            Some("challenge_not_pending"),
        );
        return Err(ApiError::bad_request("challenge not pending"));
    }

    sqlx::query(
        "UPDATE device_login_challenges SET status='approved', account_id=$1, phone=$2, approved_at=NOW() WHERE id=$3",
    )
    .bind(&account_id)
    .bind(phone)
    .bind(id)
    .execute(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "device_login approve update failed");
        ApiError::internal("failed to approve device login")
    })?;
    audit_device_login_event(
        "device_login_approve",
        "approved",
        client_ip.as_deref(),
        phone,
        Some(token_hash.as_str()),
        None,
    );

    Ok(json_no_store(json!({"ok": true, "token": token})))
}

pub async fn auth_device_login_redeem(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<DeviceLoginTokenIn>,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    let client_ip = rate_limit_client_ip(&state, &headers)?;
    consume_rate_limit(
        auth,
        &format!("auth_device_redeem_ip:{client_ip}"),
        auth.device_login_window_secs,
        auth.device_login_redeem_max_per_ip,
    )
    .await?;

    let token = normalize_hex_32(&body.token.unwrap_or_default())
        .ok_or_else(|| ApiError::bad_request("token required"))?;
    let token_hash = sha256_hex(&token);
    consume_rate_limit(
        auth,
        &format!("auth_device_redeem_token:{token_hash}"),
        auth.device_login_window_secs,
        auth.device_login_redeem_max_per_token,
    )
    .await?;
    let device_id_req = normalize_device_id(body.device_id.as_deref());

    let sid = generate_token_hex_16();
    let sid_hash = sha256_hex(&sid);
    let mut tx = auth.pool.begin().await.map_err(|e| {
        tracing::error!(error = %e, "device_login redeem begin tx failed");
        ApiError::internal("failed to redeem device login")
    })?;
    let row = sqlx::query(
        "SELECT id, status, account_id, phone, device_id, (expires_at > NOW()) AS alive FROM device_login_challenges WHERE token_hash=$1 LIMIT 1 FOR UPDATE",
    )
    .bind(&token_hash)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "device_login redeem select failed");
        ApiError::internal("device login lookup failed")
    })?;
    let Some(row) = row else {
        let _ = tx.rollback().await;
        audit_device_login_event(
            "device_login_redeem",
            "blocked",
            Some(client_ip.as_str()),
            None,
            Some(token_hash.as_str()),
            Some("challenge_not_found"),
        );
        return Err(ApiError::new(StatusCode::NOT_FOUND, "challenge not found"));
    };

    let id: i64 = row.try_get("id").unwrap_or_default();
    let status: String = row.try_get("status").unwrap_or_default();
    let account_id_db: Option<String> = row.try_get("account_id").unwrap_or(None);
    let phone: Option<String> = row.try_get("phone").unwrap_or(None);
    let device_id_db: Option<String> = row.try_get("device_id").unwrap_or(None);
    let alive: bool = row.try_get("alive").unwrap_or(false);

    if !alive {
        let _ = tx.rollback().await;
        let _ = sqlx::query("DELETE FROM device_login_challenges WHERE id=$1")
            .bind(id)
            .execute(&auth.pool)
            .await;
        audit_device_login_event(
            "device_login_redeem",
            "blocked",
            Some(client_ip.as_str()),
            None,
            Some(token_hash.as_str()),
            Some("challenge_expired"),
        );
        return Err(ApiError::bad_request("challenge expired"));
    }
    if !status.trim().eq_ignore_ascii_case("approved") {
        let _ = tx.rollback().await;
        audit_device_login_event(
            "device_login_redeem",
            "blocked",
            Some(client_ip.as_str()),
            None,
            Some(token_hash.as_str()),
            Some("challenge_not_approved"),
        );
        return Err(ApiError::bad_request("challenge not approved"));
    }
    let phone = phone
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let account_id = account_id_db.unwrap_or_default().trim().to_string();
    let account_id = if !account_id.is_empty() {
        account_id
    } else if let Some(phone) = phone.as_deref() {
        // Legacy device-login approvals may still be bound by phone only.
        let acct_id = ensure_account_id_for_phone(auth, phone).await?;
        let _ = sqlx::query(
            "UPDATE device_login_challenges SET account_id=$1 WHERE id=$2 AND account_id IS NULL",
        )
        .bind(&acct_id)
        .bind(id)
        .execute(&mut *tx)
        .await;
        acct_id
    } else {
        let _ = tx.rollback().await;
        audit_device_login_event(
            "device_login_redeem",
            "blocked",
            Some(client_ip.as_str()),
            None,
            Some(token_hash.as_str()),
            Some("challenge_not_bound_to_user"),
        );
        return Err(ApiError::bad_request("challenge not bound to user"));
    };

    // If the challenge is bound to a device_id (e.g. new-device onboarding),
    // require the redeemer to present the same device_id to prevent token theft
    // races (best practice, backwards-compatible with web flows that omit it).
    let device_id_db = normalize_device_id(device_id_db.as_deref());
    if let Some(dbid) = device_id_db.as_deref() {
        let req = device_id_req.as_deref().unwrap_or("");
        if req.is_empty() {
            let _ = tx.rollback().await;
            audit_device_login_event(
                "device_login_redeem",
                "blocked",
                Some(client_ip.as_str()),
                phone.as_deref(),
                Some(token_hash.as_str()),
                Some("device_id_required"),
            );
            return Err(ApiError::bad_request("device_id required"));
        }
        if req != dbid {
            let _ = tx.rollback().await;
            audit_device_login_event(
                "device_login_redeem",
                "blocked",
                Some(client_ip.as_str()),
                phone.as_deref(),
                Some(token_hash.as_str()),
                Some("device_id_mismatch"),
            );
            return Err(ApiError::bad_request("device_id mismatch"));
        }
    }
    let device_id = device_id_db.or(device_id_req);

    sqlx::query(
        r#"
        INSERT INTO auth_sessions
          (sid_hash, account_id, phone, device_id, expires_at, created_at, last_seen_at, revoked_at)
        VALUES
          ($1, $2, $3, $4, NOW() + ($5::bigint * INTERVAL '1 second'), NOW(), NOW(), NULL)
        "#,
    )
    .bind(&sid_hash)
    .bind(&account_id)
    .bind(phone.as_deref())
    .bind(device_id.as_deref())
    .bind(auth.auth_session_ttl_secs)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "device_login redeem insert session failed");
        ApiError::internal("failed to redeem device login")
    })?;
    sqlx::query("DELETE FROM device_login_challenges WHERE id=$1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "device_login redeem consume challenge failed");
            ApiError::internal("failed to redeem device login")
        })?;
    tx.commit().await.map_err(|e| {
        tracing::error!(error = %e, "device_login redeem commit failed");
        ApiError::internal("failed to redeem device login")
    })?;

    let shamell_id = ensure_shamell_user_id_for_account(auth, &account_id)
        .await
        .unwrap_or_default();
    let mut payload = json!({"ok": true});
    if !shamell_id.trim().is_empty() {
        payload["shamell_id"] = Value::String(shamell_id);
    }
    let mut resp = Json(payload).into_response();
    append_set_cookie(
        &mut resp,
        &session_cookie_value(&sid, auth.auth_session_ttl_secs),
    );
    append_set_cookie(&mut resp, &clear_legacy_session_cookie_value());
    append_no_store(&mut resp);
    audit_device_login_event(
        "device_login_redeem",
        "redeemed",
        Some(client_ip.as_str()),
        phone.as_deref(),
        Some(token_hash.as_str()),
        None,
    );
    Ok(resp)
}

pub async fn auth_devices_register(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<DeviceRegisterIn>,
) -> ApiResult<Json<Value>> {
    let auth = require_auth_runtime(&state)?;
    let principal = require_session_principal(&state, &headers).await?;
    let account_id = principal.account_id.trim().to_string();
    let phone = principal
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let device_id = normalize_device_id(body.device_id.as_deref())
        .ok_or_else(|| ApiError::bad_request("device_id required"))?;
    let device_type = normalize_small(body.device_type.as_deref(), 32);
    let device_name = normalize_small(body.device_name.as_deref(), 128);
    let platform = normalize_small(body.platform.as_deref(), 32);
    let app_version = normalize_small(body.app_version.as_deref(), 32);
    let last_ip = client_ip_from_headers(&state, &headers);
    let user_agent = normalize_small(header_value(&headers, "user-agent").as_deref(), 255);

    let row = sqlx::query(
        r#"
        INSERT INTO device_sessions
          (account_id, phone, device_id, device_type, device_name, platform, app_version, last_ip, user_agent, created_at, last_seen_at)
        VALUES
          ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
        ON CONFLICT (account_id, device_id)
        DO UPDATE SET
          device_type = COALESCE(EXCLUDED.device_type, device_sessions.device_type),
          device_name = COALESCE(EXCLUDED.device_name, device_sessions.device_name),
          platform = COALESCE(EXCLUDED.platform, device_sessions.platform),
          app_version = COALESCE(EXCLUDED.app_version, device_sessions.app_version),
          last_ip = COALESCE(EXCLUDED.last_ip, device_sessions.last_ip),
          user_agent = COALESCE(EXCLUDED.user_agent, device_sessions.user_agent),
          last_seen_at = NOW()
        RETURNING
          id, account_id, phone, device_id, device_type, device_name, platform, app_version, last_ip, user_agent,
          created_at::text AS created_at, last_seen_at::text AS last_seen_at
        "#,
    )
    .bind(&account_id)
    .bind(phone)
    .bind(&device_id)
    .bind(device_type.as_deref())
    .bind(device_name.as_deref())
    .bind(platform.as_deref())
    .bind(app_version.as_deref())
    .bind(last_ip.as_deref())
    .bind(user_agent.as_deref())
    .fetch_one(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "device register upsert failed");
        ApiError::internal("failed to register device")
    })?;

    if let Some(sid) = extract_session_token(&headers, state.accept_legacy_session_cookie) {
        let sid_hash = sha256_hex(&sid);
        let _ = sqlx::query(
            "UPDATE auth_sessions SET device_id=$1, last_seen_at=NOW() WHERE sid_hash=$2 AND account_id=$3 AND revoked_at IS NULL AND expires_at > NOW()",
        )
        .bind(&device_id)
        .bind(&sid_hash)
        .bind(&account_id)
        .execute(&auth.pool)
        .await;
    }

    Ok(Json(row_to_device_json(&row)))
}

pub async fn auth_devices_list(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    let auth = require_auth_runtime(&state)?;
    let account_id = require_session_account_id(&state, &headers).await?;
    let rows = sqlx::query(
        r#"
        SELECT
          id, account_id, phone, device_id, device_type, device_name, platform, app_version, last_ip, user_agent,
          created_at::text AS created_at, last_seen_at::text AS last_seen_at
        FROM device_sessions
        WHERE account_id=$1
        ORDER BY last_seen_at DESC, id DESC
        "#,
    )
    .bind(&account_id)
    .fetch_all(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "device list failed");
        ApiError::internal("failed to list devices")
    })?;

    let devices: Vec<Value> = rows.iter().map(row_to_device_json).collect();
    Ok(Json(json!({ "devices": devices })))
}

pub async fn auth_devices_delete(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    let auth = require_auth_runtime(&state)?;
    let principal = require_session_principal(&state, &headers).await?;
    let account_id = principal.account_id.trim().to_string();
    let device_id = normalize_device_id(Some(&device_id))
        .ok_or_else(|| ApiError::bad_request("device_id required"))?;

    let del = sqlx::query("DELETE FROM device_sessions WHERE account_id=$1 AND device_id=$2")
        .bind(&account_id)
        .bind(&device_id)
        .execute(&auth.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "device delete failed");
            ApiError::internal("failed to remove device")
        })?;
    if del.rows_affected() == 0 {
        return Ok(Json(json!({"status": "ignored"})));
    }

    let revoked = sqlx::query(
        "DELETE FROM auth_sessions WHERE account_id=$1 AND device_id=$2 AND revoked_at IS NULL",
    )
    .bind(&account_id)
    .bind(&device_id)
    .execute(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "session revocation on device delete failed");
        ApiError::internal("failed to remove device")
    })?
    .rows_affected();

    // Best practice: revoking a device should also revoke its biometric re-login token.
    let revoked_biometric_tokens = sqlx::query(
        "UPDATE auth_biometric_tokens SET revoked_at=NOW() WHERE account_id=$1 AND device_id=$2 AND revoked_at IS NULL",
    )
    .bind(&account_id)
    .bind(&device_id)
    .execute(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "biometric token revocation on device delete failed");
        ApiError::internal("failed to remove device")
    })?
    .rows_affected();

    // Best practice: forgetting a device should also revoke any chat device(s)
    // that were registered from it (prevents stale directory mappings).
    let revoked_chat_devices = sqlx::query(
        "UPDATE auth_chat_devices SET revoked_at=NOW() WHERE account_id=$1 AND client_device_id=$2 AND revoked_at IS NULL",
    )
    .bind(&account_id)
    .bind(&device_id)
    .execute(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "chat device revocation on device delete failed");
        ApiError::internal("failed to remove device")
    })?
    .rows_affected();

    let client_ip =
        client_ip_from_headers(&state, &headers).unwrap_or_else(|| "unknown".to_string());
    tracing::info!(
        security_event = "device_removed",
        outcome = "ok",
        client_ip,
        account_hash = %hash_prefix(&account_id),
        device_id = %device_id,
        revoked_sessions = revoked,
        revoked_biometric_tokens,
        revoked_chat_devices,
        "device removed"
    );

    Ok(Json(json!({
        "status": "ok",
        "revoked_sessions": revoked,
        "revoked_biometric_tokens": revoked_biometric_tokens,
        "revoked_chat_devices": revoked_chat_devices
    })))
}

pub async fn me_roles(State(state): State<AppState>, headers: HeaderMap) -> ApiResult<Json<Value>> {
    let auth = require_auth_runtime(&state)?;
    let principal = require_session_principal(&state, &headers).await?;
    let shamell_id = ensure_shamell_user_id_for_account(auth, &principal.account_id).await?;
    let roles = fetch_roles_for_account(&state, &headers, &principal.account_id)
        .await
        .unwrap_or_default();
    Ok(Json(json!({"shamell_id": shamell_id, "roles": roles})))
}

pub async fn me_home_snapshot(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Response> {
    let auth = require_auth_runtime(&state)?;
    let principal = require_session_principal(&state, &headers).await?;
    let shamell_id = ensure_shamell_user_id_for_account(auth, &principal.account_id).await?;
    let roles = fetch_roles_for_account(&state, &headers, &principal.account_id)
        .await
        .unwrap_or_default();
    let wallet = ensure_wallet_for_account(
        &state,
        &headers,
        &principal.account_id,
        principal.phone.as_deref(),
    )
    .await?;
    let wallet_id = wallet
        .as_ref()
        .and_then(|v| v.get("wallet_id").or_else(|| v.get("id")))
        .and_then(|v| v.as_str())
        .map(ToString::to_string);

    let is_superadmin = roles.iter().any(|r| r == "superadmin");
    let is_admin = is_superadmin || roles.iter().any(|r| r == "admin");
    let mut operator_domains: Vec<String> = Vec::new();
    if roles.iter().any(|r| r == "operator_bus") {
        operator_domains.push("bus".to_string());
    }

    let mut out = json!({
        "shamell_id": shamell_id,
        "roles": roles,
        "is_admin": is_admin,
        "is_superadmin": is_superadmin,
        "operator_domains": operator_domains,
        // Feature capabilities are used by clients to fail-closed on unfinished modules.
        // Keep defaults conservative; enable explicitly once server support exists.
        "capabilities": {
            "chat": true,
            "payments": true,
            "bus": true,
            "friends": false,
            "moments": false,
            "official_accounts": false,
            "channels": false,
            "mini_programs": false,
            "service_notifications": false,
            "subscriptions": false,
            "payments_phone_targets": false
        },
    });
    if let Some(wallet) = wallet {
        out["wallet"] = wallet;
    }
    if let Some(wallet_id) = wallet_id {
        out["wallet_id"] = json!(wallet_id);
    }

    if out["operator_domains"]
        .as_array()
        .map(|arr| arr.iter().any(|v| v.as_str() == Some("bus")))
        .unwrap_or(false)
    {
        if let Ok(summary) = call_upstream_json(
            &state,
            Upstream::Bus,
            Method::GET,
            "/admin/summary",
            Vec::new(),
            None,
            &headers,
        )
        .await
        {
            out["bus_admin_summary"] = summary;
        }
    }

    let mut resp = Json(out).into_response();
    resp.headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    Ok(resp)
}

pub async fn me_mobility_history(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<MobilityHistoryQuery>,
) -> ApiResult<Response> {
    let principal = require_session_principal(&state, &headers).await?;
    let wallet = ensure_wallet_for_account(
        &state,
        &headers,
        &principal.account_id,
        principal.phone.as_deref(),
    )
    .await?;
    let wallet_id = wallet
        .as_ref()
        .and_then(|v| v.get("wallet_id").or_else(|| v.get("id")))
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::internal("payments user response missing wallet_id"))?
        .to_string();
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let status_filter = q
        .status
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());

    let rows = call_upstream_json(
        &state,
        Upstream::Bus,
        Method::GET,
        "/bookings/search",
        vec![
            ("wallet_id".to_string(), wallet_id),
            ("limit".to_string(), limit.to_string()),
        ],
        None,
        &headers,
    )
    .await?;

    let mut bus_items: Vec<Value> = match rows {
        Value::Array(items) => items,
        _ => Vec::new(),
    };
    if let Some(status) = status_filter {
        bus_items.retain(|v| {
            v.get("status")
                .and_then(|s| s.as_str())
                .map(|s| s == status)
                .unwrap_or(false)
        });
    }

    let mut resp = Json(json!({"bus": bus_items})).into_response();
    resp.headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    Ok(resp)
}

async fn ensure_wallet_for_account(
    state: &AppState,
    headers: &HeaderMap,
    account_id: &str,
    phone: Option<&str>,
) -> ApiResult<Option<Value>> {
    let mut payload = serde_json::Map::new();
    payload.insert("account_id".to_string(), json!(account_id));
    if let Some(p) = phone.map(str::trim).filter(|s| !s.is_empty()) {
        payload.insert("phone".to_string(), json!(p));
    }
    let out = call_upstream_json(
        state,
        Upstream::Payments,
        Method::POST,
        "/users",
        Vec::new(),
        Some(Value::Object(payload)),
        headers,
    )
    .await?;
    Ok(Some(out))
}

async fn fetch_roles_for_account(
    state: &AppState,
    headers: &HeaderMap,
    account_id: &str,
) -> ApiResult<Vec<String>> {
    let v = call_upstream_json(
        state,
        Upstream::Payments,
        Method::GET,
        "/admin/roles",
        vec![
            ("account_id".to_string(), account_id.to_string()),
            ("limit".to_string(), "200".to_string()),
        ],
        None,
        headers,
    )
    .await?;
    let mut out: Vec<String> = Vec::new();
    if let Value::Array(items) = v {
        for it in items {
            if let Some(role) = it.get("role").and_then(|r| r.as_str()) {
                let role = role.trim().to_ascii_lowercase();
                if !role.is_empty() && !out.iter().any(|r| r == &role) {
                    out.push(role);
                }
            }
        }
    }
    Ok(out)
}

#[derive(Clone, Copy)]
enum Upstream {
    Payments,
    Bus,
}

async fn call_upstream_json(
    state: &AppState,
    upstream: Upstream,
    method: Method,
    path: &str,
    query: Vec<(String, String)>,
    body: Option<Value>,
    headers: &HeaderMap,
) -> ApiResult<Value> {
    let (base_url, internal_secret, upstream_name) = match upstream {
        Upstream::Payments => (
            state.payments_base_url.as_str(),
            state.payments_internal_secret.as_deref(),
            "payments",
        ),
        Upstream::Bus => (
            state.bus_base_url.as_str(),
            state.bus_internal_secret.as_deref(),
            "bus",
        ),
    };
    let url = format!("{}{}", base_url.trim_end_matches('/'), path);
    let mut req = state.http.request(method, url);
    if let Some(secret) = internal_secret.map(str::trim).filter(|s| !s.is_empty()) {
        req = req.header("X-Internal-Secret", secret);
    }
    let caller = state.internal_service_id.trim();
    if !caller.is_empty() {
        req = req.header("X-Internal-Service-Id", caller);
    }
    if !query.is_empty() {
        req = req.query(&query);
    }
    if let Some(rid) = header_value(headers, "x-request-id") {
        req = req.header("X-Request-ID", rid);
    }
    if let Some(b) = body {
        req = req.json(&b);
    }
    let resp = req.send().await.map_err(|e| {
        tracing::error!(error = %e, upstream = upstream_name, path, "upstream call failed");
        ApiError::internal(format!("{upstream_name} upstream unavailable"))
    })?;
    let status = StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
    let text = resp.text().await.unwrap_or_default();
    let parsed: Value =
        serde_json::from_str(&text).unwrap_or_else(|_| json!({"detail": text.clone()}));
    if status.is_success() {
        return Ok(parsed);
    }
    let detail = parsed
        .get("detail")
        .and_then(|v| v.as_str())
        .map(ToString::to_string)
        .unwrap_or_else(|| {
            if text.trim().is_empty() {
                format!("{upstream_name} upstream error")
            } else {
                text
            }
        });
    if !state.expose_upstream_errors && (status.is_client_error() || status.is_server_error()) {
        return Err(ApiError::new(
            status,
            format!("{upstream_name} upstream error"),
        ));
    }
    Err(ApiError::new(status, detail))
}

fn require_auth_runtime(state: &AppState) -> ApiResult<&AuthRuntime> {
    state
        .auth
        .as_ref()
        .ok_or_else(|| ApiError::new(StatusCode::SERVICE_UNAVAILABLE, "auth not configured"))
}

pub(crate) fn chat_send_requires_contacts(state: &AppState) -> bool {
    state
        .auth
        .as_ref()
        .map(|a| a.chat_send_require_contacts)
        .unwrap_or(false)
}

#[derive(Debug, Clone)]
pub(crate) struct AuthPrincipal {
    pub account_id: String,
    pub phone: Option<String>,
}

async fn require_auth_principal(state: &AppState, headers: &HeaderMap) -> ApiResult<AuthPrincipal> {
    auth_principal_from_headers(state, headers)
        .await
        .ok_or_else(|| ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"))
}

pub(crate) async fn require_session_principal(
    state: &AppState,
    headers: &HeaderMap,
) -> ApiResult<AuthPrincipal> {
    require_auth_principal(state, headers).await
}

pub(crate) async fn require_session_account_id(
    state: &AppState,
    headers: &HeaderMap,
) -> ApiResult<String> {
    Ok(require_auth_principal(state, headers).await?.account_id)
}

pub(crate) async fn require_chat_device_owned_by_principal(
    state: &AppState,
    principal: &AuthPrincipal,
    raw_device_id: &str,
) -> ApiResult<String> {
    let auth = state
        .auth
        .as_ref()
        .ok_or_else(|| ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"))?;
    let device_id = normalize_device_id(Some(raw_device_id))
        .ok_or_else(|| ApiError::bad_request("chat device_id required"))?;
    let account_id = principal.account_id.trim();
    if account_id.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }

    let found_by_account = sqlx::query(
        "SELECT 1 FROM auth_chat_devices WHERE account_id=$1 AND chat_device_id=$2 AND revoked_at IS NULL LIMIT 1",
    )
    .bind(account_id)
    .bind(&device_id)
    .fetch_optional(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            account_hash = %hash_prefix(account_id),
            device_id,
            "chat device ownership lookup failed"
        );
        ApiError::internal("device ownership lookup failed")
    })?
    .is_some();
    if found_by_account {
        return Ok(device_id);
    }

    // Backwards-compatible fallback: legacy rows may still be bound by phone only.
    if let Some(phone) = principal
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let found_by_phone = sqlx::query(
            "SELECT 1 FROM auth_chat_devices WHERE phone=$1 AND chat_device_id=$2 AND revoked_at IS NULL LIMIT 1",
        )
        .bind(phone)
        .bind(&device_id)
        .fetch_optional(&auth.pool)
        .await
        .ok()
        .flatten()
        .is_some();
        if found_by_phone {
            let _ = sqlx::query(
                "UPDATE auth_chat_devices SET account_id=$1 WHERE phone=$2 AND chat_device_id=$3 AND account_id IS NULL",
            )
            .bind(account_id)
            .bind(phone)
            .bind(&device_id)
            .execute(&auth.pool)
            .await;
            return Ok(device_id);
        }
    }

    tracing::warn!(
        account_hash = %hash_prefix(account_id),
        device_id,
        "blocked chat request for non-owned or unregistered device"
    );
    Err(ApiError::new(
        StatusCode::FORBIDDEN,
        "device not registered for authenticated user",
    ))
}

pub(crate) async fn require_chat_contact_allowed_for_direct_send(
    state: &AppState,
    principal: &AuthPrincipal,
    raw_recipient_device_id: &str,
) -> ApiResult<()> {
    let auth = require_auth_runtime(state)?;
    let account_id = principal.account_id.trim();
    if account_id.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }
    let recipient_device_id = normalize_device_id(Some(raw_recipient_device_id))
        .ok_or_else(|| ApiError::bad_request("invalid recipient_id"))?;

    // Always allow sends to self-owned devices (multi-device sync / web login flows).
    let self_owned = sqlx::query(
        "SELECT 1 FROM auth_chat_devices WHERE account_id=$1 AND chat_device_id=$2 AND revoked_at IS NULL LIMIT 1",
    )
    .bind(account_id)
    .bind(&recipient_device_id)
    .fetch_optional(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            account_hash = %hash_prefix(account_id),
            recipient_device_id,
            "auth_chat_devices lookup failed for contact enforcement"
        );
        ApiError::internal("contact enforcement unavailable")
    })?
    .is_some();
    if self_owned {
        return Ok(());
    }

    let allowed = sqlx::query(
        "SELECT 1 FROM auth_chat_contacts WHERE owner_account_id=$1 AND peer_chat_device_id=$2 AND revoked_at IS NULL LIMIT 1",
    )
    .bind(account_id)
    .bind(&recipient_device_id)
    .fetch_optional(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            account_hash = %hash_prefix(account_id),
            recipient_device_id,
            "auth_chat_contacts lookup failed for contact enforcement"
        );
        ApiError::internal("contact enforcement unavailable")
    })?
    .is_some();
    if !allowed {
        // Fail closed: avoid revealing whether the recipient exists.
        return Err(ApiError::new(StatusCode::NOT_FOUND, "not found"));
    }
    Ok(())
}

pub(crate) async fn bind_chat_device_to_principal(
    state: &AppState,
    principal: &AuthPrincipal,
    raw_chat_device_id: &str,
    raw_client_device_id: Option<&str>,
) -> ApiResult<()> {
    let Some(auth) = state.auth.as_ref() else {
        return Ok(());
    };
    let account_id = principal.account_id.trim();
    if account_id.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }
    let phone = principal
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let chat_device_id = normalize_device_id(Some(raw_chat_device_id))
        .ok_or_else(|| ApiError::bad_request("chat device_id required"))?;
    let client_device_id = normalize_device_id(raw_client_device_id);

    let r = sqlx::query(
        r#"
        INSERT INTO auth_chat_devices
          (account_id, phone, chat_device_id, client_device_id, created_at, last_seen_at, revoked_at)
        VALUES
          ($1, $2, $3, $4, NOW(), NOW(), NULL)
        ON CONFLICT (chat_device_id)
        DO UPDATE SET
          account_id = COALESCE(auth_chat_devices.account_id, EXCLUDED.account_id),
          client_device_id = COALESCE(EXCLUDED.client_device_id, auth_chat_devices.client_device_id),
          last_seen_at = NOW(),
          revoked_at = NULL
        WHERE
          (auth_chat_devices.account_id IS NOT NULL AND auth_chat_devices.account_id = EXCLUDED.account_id)
          OR
          (auth_chat_devices.account_id IS NULL AND auth_chat_devices.phone IS NOT NULL AND auth_chat_devices.phone = EXCLUDED.phone)
        "#,
    )
    .bind(account_id)
    .bind(phone)
    .bind(&chat_device_id)
    .bind(client_device_id.as_deref())
    .execute(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            account_hash = %hash_prefix(account_id),
            chat_device_id = %chat_device_id,
            "chat device bind failed"
        );
        ApiError::internal("failed to register chat device")
    })?;

    if r.rows_affected() == 0 {
        tracing::warn!(
            security_event = "chat_device_bind_rejected",
            outcome = "blocked",
            account_hash = %hash_prefix(account_id),
            chat_device_id = %chat_device_id,
            "chat device id already bound to a different user"
        );
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "device id already in use",
        ));
    }
    Ok(())
}

pub(crate) async fn enforce_chat_register_rate_limit(
    state: &AppState,
    headers: &HeaderMap,
    device_id: Option<&str>,
) -> ApiResult<()> {
    let Some(auth) = state.auth.as_ref() else {
        return Ok(());
    };
    let client_ip = rate_limit_client_ip(state, headers)?;
    consume_rate_limit(
        auth,
        &format!("chat_register_ip:{client_ip}"),
        auth.chat_register_window_secs,
        auth.chat_register_max_per_ip,
    )
    .await?;
    if let Some(device_id) = normalize_device_id(device_id) {
        consume_rate_limit(
            auth,
            &format!("chat_register_device:{device_id}"),
            auth.chat_register_window_secs,
            auth.chat_register_max_per_device,
        )
        .await?;
    }
    Ok(())
}

pub(crate) async fn enforce_chat_get_device_rate_limit(
    state: &AppState,
    headers: &HeaderMap,
    device_id: &str,
) -> ApiResult<()> {
    let Some(auth) = state.auth.as_ref() else {
        return Ok(());
    };
    let client_ip = rate_limit_client_ip(state, headers)?;
    consume_rate_limit(
        auth,
        &format!("chat_get_device_ip:{client_ip}"),
        auth.chat_get_device_window_secs,
        auth.chat_get_device_max_per_ip,
    )
    .await?;
    if let Some(device_id) = normalize_device_id(Some(device_id)) {
        consume_rate_limit(
            auth,
            &format!("chat_get_device_device:{device_id}"),
            auth.chat_get_device_window_secs,
            auth.chat_get_device_max_per_device,
        )
        .await?;
    }
    Ok(())
}

pub(crate) async fn enforce_chat_send_rate_limit(
    state: &AppState,
    headers: &HeaderMap,
    sender_device_id: Option<&str>,
) -> ApiResult<()> {
    let Some(auth) = state.auth.as_ref() else {
        return Ok(());
    };
    let client_ip = rate_limit_client_ip(state, headers)?;
    consume_rate_limit(
        auth,
        &format!("chat_send_ip:{client_ip}"),
        auth.chat_send_window_secs,
        auth.chat_send_max_per_ip,
    )
    .await?;
    if let Some(device_id) = normalize_device_id(sender_device_id) {
        consume_rate_limit(
            auth,
            &format!("chat_send_device:{device_id}"),
            auth.chat_send_window_secs,
            auth.chat_send_max_per_device,
        )
        .await?;
    }
    Ok(())
}

pub(crate) async fn enforce_chat_group_send_rate_limit(
    state: &AppState,
    headers: &HeaderMap,
    sender_device_id: Option<&str>,
) -> ApiResult<()> {
    let Some(auth) = state.auth.as_ref() else {
        return Ok(());
    };
    let client_ip = rate_limit_client_ip(state, headers)?;
    consume_rate_limit(
        auth,
        &format!("chat_group_send_ip:{client_ip}"),
        auth.chat_group_send_window_secs,
        auth.chat_group_send_max_per_ip,
    )
    .await?;
    if let Some(device_id) = normalize_device_id(sender_device_id) {
        consume_rate_limit(
            auth,
            &format!("chat_group_send_device:{device_id}"),
            auth.chat_group_send_window_secs,
            auth.chat_group_send_max_per_device,
        )
        .await?;
    }
    Ok(())
}

pub(crate) async fn enforce_contact_invite_create_rate_limit(
    state: &AppState,
    headers: &HeaderMap,
    principal: &AuthPrincipal,
) -> ApiResult<()> {
    let Some(auth) = state.auth.as_ref() else {
        return Ok(());
    };
    let client_ip = rate_limit_client_ip(state, headers)?;
    let account_id = principal.account_id.trim();
    if account_id.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }
    consume_rate_limit(
        auth,
        &format!("contact_invite_create_ip:{client_ip}"),
        auth.contact_invite_window_secs,
        auth.contact_invite_create_max_per_ip,
    )
    .await?;
    consume_rate_limit(
        auth,
        &format!("contact_invite_create_account:{}", hash_prefix(account_id)),
        auth.contact_invite_window_secs,
        auth.contact_invite_create_max_per_phone,
    )
    .await?;
    if let Some(p) = principal
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        consume_rate_limit(
            auth,
            &format!("contact_invite_create_phone:{}", hash_prefix(p)),
            auth.contact_invite_window_secs,
            auth.contact_invite_create_max_per_phone,
        )
        .await?;
    }
    Ok(())
}

pub(crate) async fn enforce_contact_invite_redeem_rate_limit(
    state: &AppState,
    headers: &HeaderMap,
    principal: &AuthPrincipal,
    token: &str,
) -> ApiResult<()> {
    let Some(auth) = state.auth.as_ref() else {
        return Ok(());
    };
    let client_ip = rate_limit_client_ip(state, headers)?;
    let account_id = principal.account_id.trim();
    if account_id.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }
    consume_rate_limit(
        auth,
        &format!("contact_invite_redeem_ip:{client_ip}"),
        auth.contact_invite_window_secs,
        auth.contact_invite_redeem_max_per_ip,
    )
    .await?;
    consume_rate_limit(
        auth,
        &format!("contact_invite_redeem_account:{}", hash_prefix(account_id)),
        auth.contact_invite_window_secs,
        auth.contact_invite_redeem_max_per_phone,
    )
    .await?;
    if let Some(p) = principal
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        consume_rate_limit(
            auth,
            &format!("contact_invite_redeem_phone:{}", hash_prefix(p)),
            auth.contact_invite_window_secs,
            auth.contact_invite_redeem_max_per_phone,
        )
        .await?;
    }
    let tok_hash = sha256_hex(token);
    consume_rate_limit(
        auth,
        &format!("contact_invite_redeem_token:{tok_hash}"),
        auth.contact_invite_window_secs,
        auth.contact_invite_redeem_max_per_token,
    )
    .await?;
    Ok(())
}

pub(crate) async fn create_contact_invite(
    state: &AppState,
    headers: &HeaderMap,
    principal: &AuthPrincipal,
    requested_max_uses: i64,
) -> ApiResult<(String, String, i64)> {
    let auth = require_auth_runtime(state)?;
    let account_id = principal.account_id.trim();
    if account_id.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }

    enforce_contact_invite_create_rate_limit(state, headers, principal).await?;

    // Require an active chat device for this account: invite redemption returns a chat device id.
    let mut row = sqlx::query(
        r#"
        SELECT chat_device_id
        FROM auth_chat_devices
        WHERE account_id=$1 AND revoked_at IS NULL
        ORDER BY last_seen_at DESC, id DESC
        LIMIT 1
        "#,
    )
    .bind(account_id)
    .fetch_optional(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            account_hash = %hash_prefix(account_id),
            "auth_chat_devices lookup failed for contact invite"
        );
        ApiError::internal("failed to create invite")
    })?;
    if row.is_none() {
        if let Some(p) = principal
            .phone
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            row = sqlx::query(
                r#"
                SELECT chat_device_id
                FROM auth_chat_devices
                WHERE phone=$1 AND revoked_at IS NULL
                ORDER BY last_seen_at DESC, id DESC
                LIMIT 1
                "#,
            )
            .bind(p)
            .fetch_optional(&auth.pool)
            .await
            .ok()
            .flatten();
        }
    }
    let Some(row) = row else {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "chat device not registered",
        ));
    };
    let issuer_chat_device_id: String = row.try_get("chat_device_id").unwrap_or_default();
    let issuer_chat_device_id = issuer_chat_device_id.trim().to_string();
    if issuer_chat_device_id.is_empty() {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "chat device not registered",
        ));
    }

    // High-entropy capability token: never store plaintext, only its hash.
    let token = generate_token_hex_32();
    let token_hash = sha256_hex(&token);
    let max_uses = requested_max_uses.clamp(1, 20);

    let inserted = sqlx::query(
        r#"
        INSERT INTO auth_contact_invites
          (token_hash, issuer_account_id, issuer_phone, issuer_chat_device_id, max_uses, use_count, created_at, last_redeemed_at, expires_at, revoked_at)
        VALUES
          ($1, $2, NULL, $3, $4, 0, NOW(), NULL, NOW() + ($5::bigint * INTERVAL '1 second'), NULL)
        RETURNING expires_at::text as expires_at
        "#,
    )
    .bind(&token_hash)
    .bind(account_id)
    .bind(&issuer_chat_device_id)
    .bind(max_uses as i32)
    .bind(auth.contact_invite_ttl_secs)
    .fetch_one(&auth.pool)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            account_hash = %hash_prefix(account_id),
            token_hash = %token_hash_prefix(&token_hash),
            "auth_contact_invites insert failed"
        );
        ApiError::internal("failed to create invite")
    })?;

    let expires_at: String = inserted.try_get("expires_at").unwrap_or_default();
    Ok((token, expires_at, max_uses))
}

pub(crate) async fn redeem_contact_invite(
    state: &AppState,
    headers: &HeaderMap,
    principal: &AuthPrincipal,
    raw_token: &str,
) -> ApiResult<String> {
    let auth = require_auth_runtime(state)?;
    let account_id = principal.account_id.trim();
    if account_id.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }

    let token =
        normalize_hex_64(raw_token).ok_or_else(|| ApiError::bad_request("invalid token"))?;
    enforce_contact_invite_redeem_rate_limit(state, headers, principal, &token).await?;

    let token_hash = sha256_hex(&token);
    let mut tx = auth.pool.begin().await.map_err(|e| {
        tracing::error!(
            error = %e,
            token_hash = %token_hash_prefix(&token_hash),
            "contact invite redeem tx begin failed"
        );
        ApiError::internal("invite redeem unavailable")
    })?;

    let row = sqlx::query(
        r#"
        SELECT
          id,
          issuer_account_id,
          issuer_phone,
          issuer_chat_device_id,
          use_count,
          max_uses,
          (revoked_at IS NOT NULL) AS revoked,
          (expires_at > NOW()) AS alive
        FROM auth_contact_invites
        WHERE token_hash=$1
        LIMIT 1
        FOR UPDATE
        "#,
    )
    .bind(&token_hash)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            token_hash = %token_hash_prefix(&token_hash),
            "contact invite redeem select failed"
        );
        ApiError::internal("invite redeem unavailable")
    })?;

    let Some(row) = row else {
        // Fail closed: do not reveal whether the token ever existed.
        let _ = tx.rollback().await;
        return Err(ApiError::new(StatusCode::NOT_FOUND, "not found"));
    };

    let id: i64 = row.try_get("id").unwrap_or_default();
    let issuer_account_id: Option<String> = row.try_get("issuer_account_id").unwrap_or(None);
    let issuer_phone: String = row.try_get("issuer_phone").unwrap_or_default();
    let issuer_chat_device_id: String = row.try_get("issuer_chat_device_id").unwrap_or_default();
    let use_count: i64 = row.try_get("use_count").unwrap_or(0);
    let max_uses: i64 = row.try_get("max_uses").unwrap_or(1);
    let revoked: bool = row.try_get("revoked").unwrap_or(false);
    let alive: bool = row.try_get("alive").unwrap_or(false);

    if revoked || !alive || use_count >= max_uses {
        let _ = tx.rollback().await;
        return Err(ApiError::new(StatusCode::NOT_FOUND, "not found"));
    }
    if issuer_account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .is_some_and(|id| id == account_id)
    {
        let _ = tx.rollback().await;
        return Err(ApiError::bad_request("cannot redeem own invite"));
    }
    if issuer_account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .is_none()
    {
        if let Some(p) = principal
            .phone
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            if issuer_phone.trim() == p {
                let _ = tx.rollback().await;
                return Err(ApiError::bad_request("cannot redeem own invite"));
            }
        }
    }

    let issuer_chat_device_id = issuer_chat_device_id.trim().to_string();
    if issuer_chat_device_id.is_empty() {
        let _ = tx.rollback().await;
        return Err(ApiError::new(StatusCode::NOT_FOUND, "not found"));
    }

    // Best practice: bind the redeemed invite to the current chat device so
    // the issuer can reply without requiring an additional invite.
    let redeemer_chat_device_id = header_value(headers, "x-chat-device-id")
        .and_then(|v| normalize_device_id(Some(&v)))
        .ok_or_else(|| ApiError::new(StatusCode::CONFLICT, "chat device not registered"))?;
    let redeemer_chat_device_id =
        require_chat_device_owned_by_principal(state, principal, &redeemer_chat_device_id).await?;

    let _ = sqlx::query(
        r#"
        UPDATE auth_contact_invites
        SET
          use_count = use_count + 1,
          last_redeemed_at = NOW(),
          revoked_at = CASE WHEN use_count + 1 >= max_uses THEN NOW() ELSE revoked_at END
        WHERE id=$1
        "#,
    )
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            token_hash = %token_hash_prefix(&token_hash),
            "contact invite redeem update failed"
        );
        ApiError::internal("invite redeem unavailable")
    })?;

    // Create/refresh contact edges for both sides (account-level).
    // This enables strict "invite-only first contact" enforcement on direct sends.
    let _ = sqlx::query(
        r#"
        INSERT INTO auth_chat_contacts
          (owner_account_id, peer_chat_device_id, created_at, last_used_at, revoked_at)
        VALUES
          ($1, $2, NOW(), NOW(), NULL)
        ON CONFLICT (owner_account_id, peer_chat_device_id)
        DO UPDATE SET
          last_used_at = NOW(),
          revoked_at = NULL
        "#,
    )
    .bind(account_id)
    .bind(&issuer_chat_device_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(
            error = %e,
            token_hash = %token_hash_prefix(&token_hash),
            account_hash = %hash_prefix(account_id),
            "auth_chat_contacts upsert failed (redeemer->issuer)"
        );
        ApiError::internal("invite redeem unavailable")
    })?;

    // Resolve issuer account id (prefer invite row, fall back to chat-device mapping).
    let mut issuer_account_id_opt = issuer_account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string);
    if issuer_account_id_opt.is_none() {
        issuer_account_id_opt = sqlx::query(
            "SELECT account_id FROM auth_chat_devices WHERE chat_device_id=$1 AND revoked_at IS NULL LIMIT 1",
        )
        .bind(&issuer_chat_device_id)
        .fetch_optional(&mut *tx)
        .await
        .ok()
        .flatten()
        .and_then(|r| r.try_get::<String, _>("account_id").ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    }
    if let Some(issuer_acc) = issuer_account_id_opt.as_deref() {
        if issuer_acc != account_id {
            let _ = sqlx::query(
                r#"
                INSERT INTO auth_chat_contacts
                  (owner_account_id, peer_chat_device_id, created_at, last_used_at, revoked_at)
                VALUES
                  ($1, $2, NOW(), NOW(), NULL)
                ON CONFLICT (owner_account_id, peer_chat_device_id)
                DO UPDATE SET
                  last_used_at = NOW(),
                  revoked_at = NULL
                "#,
            )
            .bind(issuer_acc)
            .bind(&redeemer_chat_device_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                tracing::error!(
                    error = %e,
                    token_hash = %token_hash_prefix(&token_hash),
                    issuer_account_hash = %hash_prefix(issuer_acc),
                    "auth_chat_contacts upsert failed (issuer->redeemer)"
                );
                ApiError::internal("invite redeem unavailable")
            })?;
        }
    }

    tx.commit().await.map_err(|e| {
        tracing::error!(
            error = %e,
            token_hash = %token_hash_prefix(&token_hash),
            "contact invite redeem tx commit failed"
        );
        ApiError::internal("invite redeem unavailable")
    })?;

    Ok(issuer_chat_device_id)
}

pub(crate) async fn enforce_chat_mailbox_write_rate_limit(
    state: &AppState,
    headers: &HeaderMap,
    sender_device_id: Option<&str>,
    mailbox_token: Option<&str>,
) -> ApiResult<()> {
    let Some(auth) = state.auth.as_ref() else {
        return Ok(());
    };
    let client_ip = rate_limit_client_ip(state, headers)?;
    consume_rate_limit(
        auth,
        &format!("chat_mailbox_write_ip:{client_ip}"),
        auth.chat_mailbox_write_window_secs,
        auth.chat_mailbox_write_max_per_ip,
    )
    .await?;
    if let Some(device_id) = normalize_device_id(sender_device_id) {
        consume_rate_limit(
            auth,
            &format!("chat_mailbox_write_device:{device_id}"),
            auth.chat_mailbox_write_window_secs,
            auth.chat_mailbox_write_max_per_device,
        )
        .await?;
    }
    if let Some(tok) = mailbox_token.map(str::trim).filter(|s| !s.is_empty()) {
        // Never store raw mailbox tokens in rate-limit keys.
        let tok_hash = sha256_hex(tok);
        consume_rate_limit(
            auth,
            &format!("chat_mailbox_write_mailbox:{tok_hash}"),
            auth.chat_mailbox_write_window_secs,
            auth.chat_mailbox_write_max_per_mailbox,
        )
        .await?;
    }
    Ok(())
}

async fn auth_principal_from_headers(
    state: &AppState,
    headers: &HeaderMap,
) -> Option<AuthPrincipal> {
    let auth = state.auth.as_ref()?;
    let sid = extract_session_token(headers, state.accept_legacy_session_cookie)?;
    let sid_hash = sha256_hex(&sid);
    let row = sqlx::query(
        "SELECT account_id, phone FROM auth_sessions WHERE sid_hash=$1 AND revoked_at IS NULL AND expires_at > NOW() AND last_seen_at > NOW() - ($2::bigint * INTERVAL '1 second') LIMIT 1",
    )
    .bind(&sid_hash)
    .bind(auth.auth_session_idle_ttl_secs)
    .fetch_optional(&auth.pool)
    .await
    .ok()??;
    let _ = sqlx::query("UPDATE auth_sessions SET last_seen_at=NOW() WHERE sid_hash=$1")
        .bind(&sid_hash)
        .execute(&auth.pool)
        .await;

    let account_id: Option<String> = row.try_get("account_id").ok();
    let account_id = account_id.unwrap_or_default();
    let account_id = account_id.trim().to_string();

    let phone: Option<String> = row.try_get("phone").ok();
    let phone = phone
        .unwrap_or_default()
        .trim()
        .to_string()
        .trim()
        .to_string();
    let phone = phone.trim().to_string();
    let phone_opt = if phone.is_empty() { None } else { Some(phone) };

    let account_id = if !account_id.is_empty() {
        account_id
    } else if let Some(phone) = phone_opt.as_deref() {
        // Backwards-compatible migration: legacy sessions may only have phone.
        match ensure_account_id_for_phone(auth, phone).await {
            Ok(id) => {
                let _ = sqlx::query("UPDATE auth_sessions SET account_id=$1 WHERE sid_hash=$2 AND account_id IS NULL")
                    .bind(&id)
                    .bind(&sid_hash)
                    .execute(&auth.pool)
                    .await;
                id
            }
            Err(e) => {
                tracing::error!(error = ?e, "failed to ensure account mapping for phone session");
                return None;
            }
        }
    } else {
        return None;
    };

    Some(AuthPrincipal {
        account_id,
        phone: phone_opt,
    })
}

fn extract_session_token(
    headers: &HeaderMap,
    accept_legacy_session_cookie: bool,
) -> Option<String> {
    header_value(headers, "cookie")
        .as_deref()
        .and_then(|raw| parse_session_cookie_header(raw, accept_legacy_session_cookie))
}

fn parse_session_cookie_header(raw: &str, accept_legacy_session_cookie: bool) -> Option<String> {
    parse_named_cookie_token(raw, SESSION_COOKIE_NAME).or_else(|| {
        if accept_legacy_session_cookie {
            parse_named_cookie_token(raw, LEGACY_SESSION_COOKIE_NAME)
        } else {
            None
        }
    })
}

fn parse_named_cookie_token(raw: &str, cookie_name: &str) -> Option<String> {
    for part in raw.split(';') {
        let part = part.trim();
        if let Some(rest) = part
            .strip_prefix(cookie_name)
            .and_then(|tail| tail.strip_prefix('='))
        {
            if let Some(tok) = normalize_hex_32(rest) {
                return Some(tok);
            }
        }
    }
    None
}

fn generate_token_hex_16() -> String {
    let mut buf = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut buf);
    buf.iter().map(|b| format!("{b:02x}")).collect::<String>()
}

fn generate_token_hex_32() -> String {
    let mut buf = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut buf);
    buf.iter().map(|b| format!("{b:02x}")).collect::<String>()
}

fn unix_now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn generate_shamell_user_id() -> String {
    // Base32-ish alphabet excluding ambiguous chars: I, O, 0, 1.
    const ALPHABET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut rng = rand::thread_rng();
    let mut out = String::with_capacity(8);
    for _ in 0..8 {
        let idx = rng.gen_range(0..ALPHABET.len());
        out.push(ALPHABET[idx] as char);
    }
    out
}

#[derive(Debug, Deserialize, serde::Serialize)]
struct AccountCreatePowPayload {
    v: u8,
    device_id: String,
    nonce: String,
    difficulty: u8,
    exp: i64,
}

fn encode_pow_token(secret: &str, payload: &AccountCreatePowPayload) -> Option<String> {
    let payload_bytes = serde_json::to_vec(payload).ok()?;
    let mut mac = Hmac::<Sha256>::new_from_slice(secret.as_bytes()).ok()?;
    mac.update(&payload_bytes);
    let sig = mac.finalize().into_bytes();

    let payload_b64 = URL_SAFE_NO_PAD.encode(&payload_bytes);
    let sig_b64 = URL_SAFE_NO_PAD.encode(sig.as_slice());
    Some(format!("v1.{payload_b64}.{sig_b64}"))
}

fn decode_pow_token(secret: &str, raw: &str) -> Option<AccountCreatePowPayload> {
    let token = raw.trim();
    if token.is_empty() || token.len() > 2048 {
        return None;
    }
    let mut parts = token.split('.');
    let ver = parts.next()?;
    let payload_b64 = parts.next()?;
    let sig_b64 = parts.next()?;
    if parts.next().is_some() {
        return None;
    }
    if ver != "v1" {
        return None;
    }

    let payload_bytes = URL_SAFE_NO_PAD.decode(payload_b64).ok()?;
    if payload_bytes.is_empty() || payload_bytes.len() > 1024 {
        return None;
    }
    let sig = URL_SAFE_NO_PAD.decode(sig_b64).ok()?;
    if sig.len() != 32 {
        return None;
    }

    let mut mac = Hmac::<Sha256>::new_from_slice(secret.as_bytes()).ok()?;
    mac.update(&payload_bytes);
    let expected = mac.finalize().into_bytes();
    if expected.as_slice().ct_eq(sig.as_slice()).unwrap_u8() != 1 {
        return None;
    }

    let payload: AccountCreatePowPayload = serde_json::from_slice(&payload_bytes).ok()?;
    if payload.v != 1 {
        return None;
    }
    let did = payload.device_id.trim();
    if did.is_empty() || did.len() > 128 {
        return None;
    }
    if payload.nonce.trim().is_empty() || payload.nonce.len() > 128 {
        return None;
    }
    if payload.difficulty > 30 {
        return None;
    }
    Some(payload)
}

fn has_leading_zero_bits(bytes: &[u8], bits: u8) -> bool {
    if bits == 0 {
        return true;
    }
    let full = (bits / 8) as usize;
    let rem = (bits % 8) as usize;
    if full > bytes.len() {
        return false;
    }
    for i in 0..full {
        if bytes[i] != 0 {
            return false;
        }
    }
    if rem == 0 {
        return true;
    }
    if full >= bytes.len() {
        return false;
    }
    // Require the most significant `rem` bits of the next byte to be zero.
    (bytes[full] >> (8 - rem)) == 0
}

fn verify_pow_solution(secret: &str, device_id: &str, token: &str, raw_solution: &str) -> bool {
    let now = unix_now_secs();
    let Some(payload) = decode_pow_token(secret, token) else {
        return false;
    };
    if payload.exp <= now {
        return false;
    }
    if payload.device_id.trim() != device_id.trim() {
        return false;
    }

    let sol = raw_solution.trim();
    if sol.is_empty() || sol.len() > 32 {
        return false;
    }
    if !sol.chars().all(|c| c.is_ascii_digit()) {
        return false;
    }
    let Ok(nonce) = u64::from_str_radix(sol, 10) else {
        return false;
    };

    let msg = format!("{}:{}:{}", payload.nonce.trim(), device_id.trim(), nonce);
    let digest = Sha256::digest(msg.as_bytes());
    has_leading_zero_bits(digest.as_slice(), payload.difficulty)
}

fn unix_now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn account_create_attestation_nonce_b64(challenge_token: &str) -> Option<String> {
    let tok = challenge_token.trim();
    if tok.is_empty() || tok.len() > 2048 {
        return None;
    }
    let digest = Sha256::digest(tok.as_bytes());
    Some(URL_SAFE_NO_PAD.encode(digest.as_slice()))
}

#[derive(serde::Serialize)]
struct AppleDeviceCheckJwtClaims<'a> {
    iss: &'a str,
    iat: usize,
    exp: usize,
}

async fn verify_apple_devicecheck_token(
    http: &reqwest::Client,
    cfg: &AppleDeviceCheckConfig,
    device_token_b64: &str,
) -> ApiResult<bool> {
    let tok = device_token_b64.trim();
    if tok.is_empty() || tok.len() > 4096 {
        return Ok(false);
    }

    // Apple DeviceCheck: https://api.devicecheck.apple.com/v1/validate_device_token
    let now = unix_now_secs().max(0) as usize;
    let mut header = Header::new(Algorithm::ES256);
    header.kid = Some(cfg.key_id.clone());
    let claims = AppleDeviceCheckJwtClaims {
        iss: cfg.team_id.as_str(),
        iat: now,
        exp: now.saturating_add(20 * 60),
    };
    let jwt = jsonwebtoken::encode(
        &header,
        &claims,
        &EncodingKey::from_ec_pem(cfg.private_key_p8.as_slice())
            .map_err(|_| ApiError::internal("apple devicecheck key misconfigured"))?,
    )
    .map_err(|_| ApiError::internal("apple devicecheck key misconfigured"))?;

    #[derive(serde::Serialize)]
    struct DcValidateReq<'a> {
        device_token: &'a str,
        timestamp: i64,
        transaction_id: &'a str,
    }

    let txid = generate_token_hex_16();
    let req = DcValidateReq {
        device_token: tok,
        timestamp: unix_now_millis(),
        transaction_id: txid.as_str(),
    };

    let resp = http
        .post("https://api.devicecheck.apple.com/v1/validate_device_token")
        .timeout(std::time::Duration::from_secs(6))
        .bearer_auth(jwt)
        .json(&req)
        .send()
        .await
        .map_err(|_| ApiError::new(StatusCode::SERVICE_UNAVAILABLE, "attestation unavailable"))?;

    if resp.status() == StatusCode::OK {
        return Ok(true);
    }
    if resp.status().is_client_error() {
        return Ok(false);
    }
    Err(ApiError::new(
        StatusCode::SERVICE_UNAVAILABLE,
        "attestation unavailable",
    ))
}

#[derive(Deserialize)]
struct GoogleOauthTokenResponse {
    access_token: String,
}

#[derive(serde::Serialize)]
struct GoogleServiceAccountJwtClaims<'a> {
    iss: &'a str,
    sub: &'a str,
    aud: &'a str,
    iat: usize,
    exp: usize,
    scope: &'a str,
}

async fn google_service_account_access_token(
    http: &reqwest::Client,
    cfg: &PlayIntegrityConfig,
) -> ApiResult<String> {
    let now = unix_now_secs().max(0) as usize;
    let header = Header::new(Algorithm::RS256);
    let claims = GoogleServiceAccountJwtClaims {
        iss: cfg.service_account_email.as_str(),
        sub: cfg.service_account_email.as_str(),
        aud: cfg.token_uri.as_str(),
        iat: now,
        exp: now.saturating_add(55 * 60),
        scope: "https://www.googleapis.com/auth/playintegrity",
    };
    let jwt = jsonwebtoken::encode(
        &header,
        &claims,
        &EncodingKey::from_rsa_pem(cfg.service_account_private_key_pem.as_slice())
            .map_err(|_| ApiError::internal("play integrity key misconfigured"))?,
    )
    .map_err(|_| ApiError::internal("play integrity key misconfigured"))?;

    let resp = http
        .post(cfg.token_uri.as_str())
        .timeout(std::time::Duration::from_secs(6))
        .form(&[
            ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            ("assertion", jwt.as_str()),
        ])
        .send()
        .await
        .map_err(|_| ApiError::new(StatusCode::SERVICE_UNAVAILABLE, "attestation unavailable"))?;

    if !resp.status().is_success() {
        if resp.status().is_client_error() {
            tracing::warn!(
                status = %resp.status(),
                "play integrity oauth rejected service-account request"
            );
        }
        return Err(ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "attestation unavailable",
        ));
    }
    let parsed: GoogleOauthTokenResponse = resp
        .json()
        .await
        .map_err(|_| ApiError::internal("play integrity oauth parse failed"))?;
    let tok = parsed.access_token.trim().to_string();
    if tok.is_empty() {
        return Err(ApiError::internal("play integrity oauth failed"));
    }
    Ok(tok)
}

#[derive(Deserialize)]
struct PlayIntegrityDecodeResponse {
    #[serde(rename = "tokenPayloadExternal")]
    token_payload_external: Option<PlayIntegrityTokenPayloadExternal>,
}

#[derive(Deserialize)]
struct PlayIntegrityTokenPayloadExternal {
    #[serde(rename = "requestDetails")]
    request_details: Option<PlayIntegrityRequestDetails>,
    #[serde(rename = "appIntegrity")]
    app_integrity: Option<PlayIntegrityAppIntegrity>,
    #[serde(rename = "deviceIntegrity")]
    device_integrity: Option<PlayIntegrityDeviceIntegrity>,
    #[serde(rename = "accountDetails")]
    account_details: Option<PlayIntegrityAccountDetails>,
}

#[derive(Deserialize)]
struct PlayIntegrityRequestDetails {
    #[serde(rename = "requestPackageName")]
    request_package_name: Option<String>,
    nonce: Option<String>,
}

#[derive(Deserialize)]
struct PlayIntegrityAppIntegrity {
    #[serde(rename = "appRecognitionVerdict")]
    app_recognition_verdict: Option<String>,
}

#[derive(Deserialize)]
struct PlayIntegrityDeviceIntegrity {
    #[serde(rename = "deviceRecognitionVerdict")]
    device_recognition_verdict: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct PlayIntegrityAccountDetails {
    #[serde(rename = "appLicensingVerdict")]
    app_licensing_verdict: Option<String>,
}

async fn verify_play_integrity_token(
    http: &reqwest::Client,
    cfg: &PlayIntegrityConfig,
    integrity_token: &str,
    expected_nonce_b64: &str,
) -> ApiResult<bool> {
    let tok = integrity_token.trim();
    if tok.is_empty() || tok.len() > 32_768 {
        return Ok(false);
    }
    let expected_nonce = expected_nonce_b64.trim();
    if expected_nonce.is_empty() || expected_nonce.len() > 512 {
        return Ok(false);
    }

    let access_token = google_service_account_access_token(http, cfg).await?;

    #[derive(serde::Serialize)]
    struct DecodeReq<'a> {
        integrity_token: &'a str,
    }

    for pkg in cfg.allowed_package_names.iter() {
        let url = format!(
            "https://playintegrity.googleapis.com/v1/{}:decodeIntegrityToken",
            pkg
        );
        let resp = http
            .post(url)
            .timeout(std::time::Duration::from_secs(8))
            .bearer_auth(access_token.as_str())
            .json(&DecodeReq {
                integrity_token: tok,
            })
            .send()
            .await
            .map_err(|_| {
                ApiError::new(StatusCode::SERVICE_UNAVAILABLE, "attestation unavailable")
            })?;

        if resp.status() == StatusCode::UNAUTHORIZED || resp.status() == StatusCode::FORBIDDEN {
            // Access token / IAM misconfig.
            return Err(ApiError::internal("play integrity unauthorized"));
        }
        if !resp.status().is_success() {
            // Try next package (token might belong to another allowed package).
            continue;
        }

        let decoded: PlayIntegrityDecodeResponse = resp
            .json()
            .await
            .map_err(|_| ApiError::internal("play integrity decode parse failed"))?;
        let Some(payload) = decoded.token_payload_external else {
            return Ok(false);
        };
        let Some(req) = payload.request_details else {
            return Ok(false);
        };

        let req_pkg = req
            .request_package_name
            .unwrap_or_default()
            .trim()
            .to_string();
        if req_pkg.is_empty() || !cfg.allowed_package_names.iter().any(|p| p == &req_pkg) {
            return Ok(false);
        }
        let nonce = req.nonce.unwrap_or_default();
        if nonce.trim() != expected_nonce {
            return Ok(false);
        }

        if cfg.require_play_recognized {
            let verdict = payload
                .app_integrity
                .as_ref()
                .and_then(|v| v.app_recognition_verdict.as_deref())
                .unwrap_or("")
                .trim()
                .to_string();
            if verdict != "PLAY_RECOGNIZED" {
                return Ok(false);
            }
        }

        let verdicts = payload
            .device_integrity
            .as_ref()
            .and_then(|v| v.device_recognition_verdict.as_ref())
            .cloned()
            .unwrap_or_default();
        if cfg.require_strong_integrity {
            if !verdicts.iter().any(|v| v == "MEETS_STRONG_INTEGRITY") {
                return Ok(false);
            }
        } else if !verdicts
            .iter()
            .any(|v| v == "MEETS_DEVICE_INTEGRITY" || v == "MEETS_STRONG_INTEGRITY")
        {
            return Ok(false);
        }

        if cfg.require_licensed {
            let verdict = payload
                .account_details
                .as_ref()
                .and_then(|v| v.app_licensing_verdict.as_deref())
                .unwrap_or("")
                .trim()
                .to_string();
            if verdict != "LICENSED" {
                return Ok(false);
            }
        }

        return Ok(true);
    }

    Ok(false)
}

async fn ensure_account_id_for_phone(auth: &AuthRuntime, phone: &str) -> ApiResult<String> {
    let phone = phone.trim();
    if phone.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }

    // Fast path: already mapped.
    if let Some(row) = sqlx::query("SELECT account_id FROM auth_accounts WHERE phone=$1 LIMIT 1")
        .bind(phone)
        .fetch_optional(&auth.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "auth_accounts select failed");
            ApiError::internal("failed to load account")
        })?
    {
        let id: String = row.try_get("account_id").unwrap_or_default();
        let id = id.trim().to_string();
        if !id.is_empty() {
            return Ok(id);
        }
    }

    // Preserve any legacy Shamell ID mapping if present.
    let legacy_shamell_id =
        sqlx::query("SELECT shamell_user_id FROM auth_user_ids WHERE phone=$1 LIMIT 1")
            .bind(phone)
            .fetch_optional(&auth.pool)
            .await
            .ok()
            .flatten()
            .and_then(|row| row.try_get::<String, _>("shamell_user_id").ok())
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

    for _ in 0..12 {
        let account_id = generate_token_hex_32();
        let shamell_id = legacy_shamell_id
            .clone()
            .unwrap_or_else(generate_shamell_user_id);
        let inserted = sqlx::query(
            "INSERT INTO auth_accounts (account_id, shamell_user_id, phone) VALUES ($1, $2, $3) ON CONFLICT (phone) DO NOTHING",
        )
        .bind(&account_id)
        .bind(&shamell_id)
        .bind(phone)
        .execute(&auth.pool)
        .await;

        match inserted {
            Ok(r) => {
                if r.rows_affected() == 1 {
                    return Ok(account_id);
                }
                // Another request won the race: load and return.
                if let Some(row) =
                    sqlx::query("SELECT account_id FROM auth_accounts WHERE phone=$1 LIMIT 1")
                        .bind(phone)
                        .fetch_optional(&auth.pool)
                        .await
                        .map_err(|e| {
                            tracing::error!(error = %e, "auth_accounts re-select failed");
                            ApiError::internal("failed to load account")
                        })?
                {
                    let id: String = row.try_get("account_id").unwrap_or_default();
                    let id = id.trim().to_string();
                    if !id.is_empty() {
                        return Ok(id);
                    }
                }
            }
            Err(e) => {
                let unique_violation = match &e {
                    sqlx::Error::Database(db) => db.code().as_deref() == Some("23505"),
                    _ => false,
                };
                if unique_violation {
                    continue;
                }
                tracing::error!(error = %e, "auth_accounts insert failed");
                return Err(ApiError::internal("failed to allocate account"));
            }
        }
    }
    Err(ApiError::internal("failed to allocate account"))
}

async fn ensure_shamell_user_id_for_account(
    auth: &AuthRuntime,
    account_id: &str,
) -> ApiResult<String> {
    let account_id = account_id.trim();
    if account_id.is_empty() {
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"));
    }
    let row = sqlx::query("SELECT shamell_user_id FROM auth_accounts WHERE account_id=$1 LIMIT 1")
        .bind(account_id)
        .fetch_optional(&auth.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "auth_accounts shamell_id lookup failed");
            ApiError::internal("failed to load Shamell ID")
        })?
        .ok_or_else(|| ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized"))?;
    let id: String = row.try_get("shamell_user_id").unwrap_or_default();
    let id = id.trim().to_string();
    if id.is_empty() {
        return Err(ApiError::internal("failed to load Shamell ID"));
    }
    Ok(id)
}

fn sha256_hex(value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_bytes());
    let digest = hasher.finalize();
    digest
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>()
}

fn hash_prefix(value: &str) -> String {
    let digest = sha256_hex(value);
    digest.chars().take(12).collect()
}

fn token_hash_prefix(token_hash: &str) -> String {
    token_hash.chars().take(12).collect()
}

fn audit_device_login_event(
    event: &'static str,
    outcome: &'static str,
    client_ip: Option<&str>,
    phone: Option<&str>,
    token_hash: Option<&str>,
    reason: Option<&str>,
) {
    let client_ip = client_ip.unwrap_or("");
    let phone_hash = phone.map(hash_prefix).unwrap_or_default();
    let token_hash = token_hash.map(token_hash_prefix).unwrap_or_default();
    let reason = reason.unwrap_or("");
    if matches!(outcome, "blocked") {
        tracing::warn!(
            security_event = event,
            outcome,
            reason,
            client_ip,
            phone_hash,
            token_hash,
            "auth device login security event"
        );
    } else {
        tracing::info!(
            security_event = event,
            outcome,
            client_ip,
            phone_hash,
            token_hash,
            "auth device login security event"
        );
    }
}

fn now_ts() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

async fn consume_rate_limit(
    auth: &AuthRuntime,
    key: &str,
    window_secs: i64,
    max_per_window: i64,
) -> ApiResult<()> {
    let now = now_ts();
    let mut tx = auth.pool.begin().await.map_err(|e| {
        tracing::error!(error = %e, limit_key = key, "rate-limit tx begin failed");
        ApiError::internal("rate-limit unavailable")
    })?;
    sqlx::query(
        r#"
        INSERT INTO auth_rate_limits (limit_key, window_start_epoch, request_count, updated_at)
        VALUES ($1, $2, 0, NOW())
        ON CONFLICT (limit_key) DO NOTHING
        "#,
    )
    .bind(key)
    .bind(now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, limit_key = key, "rate-limit insert failed");
        ApiError::internal("rate-limit unavailable")
    })?;

    let row = sqlx::query(
        "SELECT window_start_epoch, request_count FROM auth_rate_limits WHERE limit_key=$1 FOR UPDATE",
    )
    .bind(key)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, limit_key = key, "rate-limit select failed");
        ApiError::internal("rate-limit unavailable")
    })?;
    let mut window_start: i64 = row.try_get("window_start_epoch").unwrap_or(now);
    let mut request_count: i64 = row.try_get("request_count").unwrap_or_default();
    let elapsed = now.saturating_sub(window_start);
    let allowed = if elapsed >= window_secs {
        window_start = now;
        request_count = 1;
        true
    } else if request_count < max_per_window {
        request_count = request_count.saturating_add(1);
        true
    } else {
        false
    };
    sqlx::query(
        "UPDATE auth_rate_limits SET window_start_epoch=$1, request_count=$2, updated_at=NOW() WHERE limit_key=$3",
    )
    .bind(window_start)
    .bind(request_count)
    .bind(key)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, limit_key = key, "rate-limit update failed");
        ApiError::internal("rate-limit unavailable")
    })?;
    tx.commit().await.map_err(|e| {
        tracing::error!(error = %e, limit_key = key, "rate-limit tx commit failed");
        ApiError::internal("rate-limit unavailable")
    })?;

    if !allowed {
        tracing::warn!(
            security_event = "auth_rate_limit_exceeded",
            outcome = "blocked",
            limit_key_hash = hash_prefix(key),
            window_secs,
            max_per_window,
            "auth rate limit exceeded"
        );
        return Err(ApiError::new(
            StatusCode::TOO_MANY_REQUESTS,
            "too many requests",
        ));
    }
    Ok(())
}

fn normalize_hex_32(raw: &str) -> Option<String> {
    let t = raw.trim();
    if t.len() != 32 {
        return None;
    }
    if !t.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    Some(t.to_ascii_lowercase())
}

fn normalize_hex_64(raw: &str) -> Option<String> {
    let t = raw.trim();
    if t.len() != 64 {
        return None;
    }
    if !t.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    Some(t.to_ascii_lowercase())
}

fn normalize_device_id(raw: Option<&str>) -> Option<String> {
    let mut s = raw.unwrap_or_default().trim().to_string();
    if s.is_empty() {
        return None;
    }
    if s.len() > 128 {
        s.truncate(128);
    }
    if s.chars().any(|c| c.is_control()) {
        return None;
    }
    Some(s)
}

fn normalize_small(raw: Option<&str>, max: usize) -> Option<String> {
    let mut s = raw.unwrap_or_default().trim().to_string();
    if s.is_empty() {
        return None;
    }
    if s.len() > max {
        s.truncate(max);
    }
    if s.chars().any(|c| c.is_control()) {
        return None;
    }
    Some(s)
}

fn header_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string)
}

fn rate_limit_client_ip(state: &AppState, headers: &HeaderMap) -> ApiResult<String> {
    if let Some(ip) = client_ip_from_headers(state, headers) {
        return Ok(ip);
    }
    let env_lower = state.env_name.trim().to_ascii_lowercase();
    if matches!(env_lower.as_str(), "prod" | "production" | "staging") {
        tracing::error!("missing trusted client IP header (X-Shamell-Client-IP) on auth path");
        return Err(ApiError::internal("client ip unavailable"));
    }
    Ok("unknown".to_string())
}

fn client_ip_from_headers(state: &AppState, headers: &HeaderMap) -> Option<String> {
    if let Some(ip) = header_value(headers, "x-shamell-client-ip").and_then(|v| parse_ip(&v)) {
        return Some(ip);
    }

    let env_lower = state.env_name.trim().to_ascii_lowercase();
    if !matches!(env_lower.as_str(), "dev" | "test") {
        return None;
    }

    if let Some(first) = header_value(headers, "x-forwarded-for")
        .and_then(|v| v.split(',').next().map(str::trim).map(str::to_string))
    {
        if let Some(ip) = parse_ip(&first) {
            return Some(ip);
        }
    }
    header_value(headers, "x-real-ip").and_then(|v| parse_ip(&v))
}

fn parse_ip(raw: &str) -> Option<String> {
    let token = raw.trim();
    if token.is_empty() {
        return None;
    }
    let token = token
        .strip_prefix("for=")
        .or_else(|| token.strip_prefix("For="))
        .unwrap_or(token)
        .trim()
        .trim_matches('"');

    if let Ok(ip) = token.parse::<IpAddr>() {
        return Some(ip.to_string());
    }
    if let Ok(sock) = token.parse::<SocketAddr>() {
        return Some(sock.ip().to_string());
    }
    if token.starts_with('[') {
        if let Some(end) = token.find(']') {
            let inner = &token[1..end];
            if let Ok(ip) = inner.parse::<IpAddr>() {
                return Some(ip.to_string());
            }
        }
    }
    let trimmed = token.trim_matches('[').trim_matches(']');
    if let Ok(ip) = trimmed.parse::<IpAddr>() {
        return Some(ip.to_string());
    }
    None
}

fn append_set_cookie(resp: &mut Response, value: &str) {
    if let Ok(v) = HeaderValue::from_str(value) {
        resp.headers_mut().append(header::SET_COOKIE, v);
    }
}

fn append_no_store(resp: &mut Response) {
    resp.headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
}

fn json_no_store(value: Value) -> Response {
    let mut resp = Json(value).into_response();
    append_no_store(&mut resp);
    resp
}

fn session_cookie_value(session: &str, ttl_secs: i64) -> String {
    format!(
        "{SESSION_COOKIE_NAME}={session}; Max-Age={ttl_secs}; Path=/; HttpOnly; Secure; SameSite=Lax"
    )
}

fn clear_session_cookie_value() -> String {
    format!("{SESSION_COOKIE_NAME}=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Lax")
}

fn clear_legacy_session_cookie_value() -> String {
    format!("{LEGACY_SESSION_COOKIE_NAME}=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Lax")
}

fn legacy_console_removed_page(title: &str) -> String {
    format!(
        r#"<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <style>
      :root {{ color-scheme: light; }}
      body {{ margin: 0; font-family: "Segoe UI", Roboto, Arial, sans-serif; background: #0f172a; color: #e2e8f0; }}
      .wrap {{ min-height: 100vh; display: grid; place-items: center; padding: 24px; }}
      .card {{ max-width: 560px; width: 100%; border: 1px solid #334155; background: #111827; border-radius: 14px; padding: 20px; }}
      h1 {{ margin: 0 0 8px; font-size: 22px; }}
      p {{ margin: 0; color: #cbd5e1; line-height: 1.5; }}
      code {{ background: #1e293b; border-radius: 6px; padding: 2px 6px; }}
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="card">
        <h1>{title}</h1>
        <p>Legacy browser console was removed. Use Shamell app clients and the authenticated API endpoints.</p>
      </div>
    </div>
  </body>
</html>"#
    )
}

fn url_escape_component(raw: &str) -> String {
    fn hex(b: u8) -> char {
        match b {
            0..=9 => (b'0' + b) as char,
            10..=15 => (b'A' + (b - 10)) as char,
            _ => '0',
        }
    }

    let mut out = String::with_capacity(raw.len());
    for &b in raw.as_bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => {
                out.push('%');
                out.push(hex(b >> 4));
                out.push(hex(b & 0x0F));
            }
        }
    }
    out
}

fn row_to_device_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.try_get::<i64, _>("id").unwrap_or_default(),
        "phone": row.try_get::<String, _>("phone").unwrap_or_default(),
        "device_id": row.try_get::<String, _>("device_id").unwrap_or_default(),
        "device_type": row.try_get::<Option<String>, _>("device_type").unwrap_or(None),
        "device_name": row.try_get::<Option<String>, _>("device_name").unwrap_or(None),
        "platform": row.try_get::<Option<String>, _>("platform").unwrap_or(None),
        "app_version": row.try_get::<Option<String>, _>("app_version").unwrap_or(None),
        "last_ip": row.try_get::<Option<String>, _>("last_ip").unwrap_or(None),
        "user_agent": row.try_get::<Option<String>, _>("user_agent").unwrap_or(None),
        "created_at": row.try_get::<Option<String>, _>("created_at").unwrap_or(None),
        "last_seen_at": row.try_get::<Option<String>, _>("last_seen_at").unwrap_or(None),
    })
}

fn parse_int_env(key: &str, default: i64, min: i64, max: i64) -> i64 {
    let raw = env::var(key).unwrap_or_default();
    let parsed = raw.trim().parse::<i64>().unwrap_or(default);
    parsed.clamp(min, max)
}

async fn ensure_auth_schema(pool: &PgPool) -> Result<(), sqlx::Error> {
    // New identity model: stable account ids (no phone required).
    // We keep legacy phone-keyed tables/columns for backwards-compatible migration.
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_accounts (
          account_id VARCHAR(64) PRIMARY KEY,
          shamell_user_id VARCHAR(16) NOT NULL UNIQUE,
          phone VARCHAR(32) UNIQUE,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_auth_accounts_phone ON auth_accounts(phone)")
        .execute(pool)
        .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_accounts_shamell_user_id ON auth_accounts(shamell_user_id)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_sessions (
          id BIGSERIAL PRIMARY KEY,
          sid_hash VARCHAR(64) NOT NULL UNIQUE,
          account_id VARCHAR(64),
          phone VARCHAR(32),
          device_id VARCHAR(128),
          expires_at TIMESTAMPTZ NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          revoked_at TIMESTAMPTZ
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "ALTER TABLE auth_sessions ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
    )
    .execute(pool)
    .await?;
    sqlx::query("ALTER TABLE auth_sessions ADD COLUMN IF NOT EXISTS account_id VARCHAR(64)")
        .execute(pool)
        .await?;
    // Phone is optional: avoid using it as a stable identifier.
    let _ = sqlx::query("ALTER TABLE auth_sessions ALTER COLUMN phone DROP NOT NULL")
        .execute(pool)
        .await;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_sessions_account_id ON auth_sessions(account_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_auth_sessions_phone ON auth_sessions(phone)")
        .execute(pool)
        .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires_at ON auth_sessions(expires_at)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_sessions_device_id ON auth_sessions(device_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_sessions_last_seen_at ON auth_sessions(last_seen_at)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_user_ids (
          id BIGSERIAL PRIMARY KEY,
          phone VARCHAR(32) NOT NULL UNIQUE,
          shamell_user_id VARCHAR(16) NOT NULL UNIQUE,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
        "#,
    )
    .execute(pool)
    .await?;
    // Best practice: phone is optional globally, so avoid making it a table primary key.
    // Migrate legacy schemas where `phone` was PRIMARY KEY to an `id` primary key.
    let _ = sqlx::query("ALTER TABLE auth_user_ids ADD COLUMN IF NOT EXISTS id BIGSERIAL")
        .execute(pool)
        .await;
    let _ = sqlx::query("UPDATE auth_user_ids SET id = DEFAULT WHERE id IS NULL")
        .execute(pool)
        .await;
    let _ = sqlx::query("ALTER TABLE auth_user_ids ALTER COLUMN id SET NOT NULL")
        .execute(pool)
        .await;
    let _ = sqlx::query("ALTER TABLE auth_user_ids ALTER COLUMN phone SET NOT NULL")
        .execute(pool)
        .await;
    // Ensure `id` is the PRIMARY KEY (legacy schemas may still have phone as PK).
    let _ = sqlx::query(
        r#"
        DO $$
        DECLARE
          pk_name text;
          pk_cols text[];
        BEGIN
          SELECT
            c.conname,
            array_agg(a.attname ORDER BY a.attnum)
          INTO pk_name, pk_cols
          FROM pg_constraint c
          JOIN pg_class t ON c.conrelid = t.oid
          JOIN unnest(c.conkey) AS k(attnum) ON true
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
          WHERE t.relname = 'auth_user_ids' AND c.contype = 'p'
          GROUP BY c.conname
          LIMIT 1;

          IF pk_cols IS NULL THEN
            EXECUTE 'ALTER TABLE auth_user_ids ADD CONSTRAINT auth_user_ids_pkey PRIMARY KEY (id)';
          ELSIF array_length(pk_cols, 1) = 1 AND pk_cols[1] = 'id' THEN
            -- Already correct.
          ELSE
            EXECUTE format('ALTER TABLE auth_user_ids DROP CONSTRAINT %I', pk_name);
            EXECUTE 'ALTER TABLE auth_user_ids ADD CONSTRAINT auth_user_ids_pkey PRIMARY KEY (id)';
          END IF;
        END $$;
        "#,
    )
    .execute(pool)
    .await;
    let _ = sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_user_ids_phone ON auth_user_ids(phone)",
    )
    .execute(pool)
    .await;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_user_ids_shamell_id ON auth_user_ids(shamell_user_id)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_chat_devices (
          id BIGSERIAL PRIMARY KEY,
          account_id VARCHAR(64),
          phone VARCHAR(32),
          chat_device_id VARCHAR(128) NOT NULL UNIQUE,
          client_device_id VARCHAR(128),
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          revoked_at TIMESTAMPTZ,
          UNIQUE (phone, chat_device_id)
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query("ALTER TABLE auth_chat_devices ADD COLUMN IF NOT EXISTS account_id VARCHAR(64)")
        .execute(pool)
        .await?;
    let _ = sqlx::query("ALTER TABLE auth_chat_devices ALTER COLUMN phone DROP NOT NULL")
        .execute(pool)
        .await;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_phone ON auth_chat_devices(phone)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_account_id ON auth_chat_devices(account_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_client_device_id ON auth_chat_devices(client_device_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_last_seen_at ON auth_chat_devices(last_seen_at)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_contact_invites (
          id BIGSERIAL PRIMARY KEY,
          token_hash VARCHAR(64) NOT NULL UNIQUE,
          issuer_account_id VARCHAR(64),
          issuer_phone VARCHAR(32),
          issuer_chat_device_id VARCHAR(128) NOT NULL,
          max_uses INT NOT NULL DEFAULT 1,
          use_count INT NOT NULL DEFAULT 0,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          last_redeemed_at TIMESTAMPTZ,
          expires_at TIMESTAMPTZ NOT NULL,
          revoked_at TIMESTAMPTZ
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "ALTER TABLE auth_contact_invites ADD COLUMN IF NOT EXISTS issuer_account_id VARCHAR(64)",
    )
    .execute(pool)
    .await?;
    let _ = sqlx::query("ALTER TABLE auth_contact_invites ALTER COLUMN issuer_phone DROP NOT NULL")
        .execute(pool)
        .await;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_contact_invites_issuer_phone ON auth_contact_invites(issuer_phone)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_contact_invites_issuer_account_id ON auth_contact_invites(issuer_account_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_contact_invites_issuer_chat_device_id ON auth_contact_invites(issuer_chat_device_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_contact_invites_expires_at ON auth_contact_invites(expires_at)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_chat_contacts (
          id BIGSERIAL PRIMARY KEY,
          owner_account_id VARCHAR(64) NOT NULL,
          peer_chat_device_id VARCHAR(128) NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          revoked_at TIMESTAMPTZ,
          UNIQUE (owner_account_id, peer_chat_device_id)
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_chat_contacts_owner_account_id ON auth_chat_contacts(owner_account_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_chat_contacts_peer_chat_device_id ON auth_chat_contacts(peer_chat_device_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_chat_contacts_last_used_at ON auth_chat_contacts(last_used_at)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_biometric_tokens (
          id BIGSERIAL PRIMARY KEY,
          token_hash VARCHAR(64) NOT NULL UNIQUE,
          account_id VARCHAR(64),
          phone VARCHAR(32),
          device_id VARCHAR(128) NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          last_used_at TIMESTAMPTZ,
          expires_at TIMESTAMPTZ NOT NULL,
          revoked_at TIMESTAMPTZ,
          UNIQUE (phone, device_id)
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "ALTER TABLE auth_biometric_tokens ADD COLUMN IF NOT EXISTS account_id VARCHAR(64)",
    )
    .execute(pool)
    .await?;
    let _ = sqlx::query("ALTER TABLE auth_biometric_tokens ALTER COLUMN phone DROP NOT NULL")
        .execute(pool)
        .await;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_biometric_tokens_phone ON auth_biometric_tokens(phone)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_biometric_tokens_account_id ON auth_biometric_tokens(account_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_biometric_tokens_expires_at ON auth_biometric_tokens(expires_at)",
    )
    .execute(pool)
    .await?;
    // Enable account_id-based upserts during migration.
    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_biometric_tokens_account_device ON auth_biometric_tokens(account_id, device_id)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_rate_limits (
          limit_key VARCHAR(255) PRIMARY KEY,
          window_start_epoch BIGINT NOT NULL,
          request_count BIGINT NOT NULL DEFAULT 0,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_auth_rate_limits_updated_at ON auth_rate_limits(updated_at)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS device_login_challenges (
          id BIGSERIAL PRIMARY KEY,
          token_hash VARCHAR(64) NOT NULL UNIQUE,
          label VARCHAR(128),
          status VARCHAR(16) NOT NULL DEFAULT 'pending',
          account_id VARCHAR(64),
          phone VARCHAR(32),
          device_id VARCHAR(128),
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          expires_at TIMESTAMPTZ NOT NULL,
          approved_at TIMESTAMPTZ
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "ALTER TABLE device_login_challenges ADD COLUMN IF NOT EXISTS account_id VARCHAR(64)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_device_login_challenges_account_id ON device_login_challenges(account_id)",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_device_login_challenges_expires_at ON device_login_challenges(expires_at)",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS device_sessions (
          id BIGSERIAL PRIMARY KEY,
          account_id VARCHAR(64),
          phone VARCHAR(32),
          device_id VARCHAR(128) NOT NULL,
          device_type VARCHAR(32),
          device_name VARCHAR(128),
          platform VARCHAR(32),
          app_version VARCHAR(32),
          last_ip VARCHAR(64),
          user_agent VARCHAR(255),
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          UNIQUE (phone, device_id)
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query("ALTER TABLE device_sessions ADD COLUMN IF NOT EXISTS account_id VARCHAR(64)")
        .execute(pool)
        .await?;
    let _ = sqlx::query("ALTER TABLE device_sessions ALTER COLUMN phone DROP NOT NULL")
        .execute(pool)
        .await;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_device_sessions_phone ON device_sessions(phone)")
        .execute(pool)
        .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_device_sessions_account_id ON device_sessions(account_id)",
    )
    .execute(pool)
    .await?;
    // Enable account_id-based upserts during migration.
    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_device_sessions_account_device ON device_sessions(account_id, device_id)",
    )
    .execute(pool)
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::AppState;
    use axum::http::{header, HeaderMap, HeaderName};
    use std::env;
    use std::sync::{Mutex, OnceLock};

    static ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    struct EnvGuard {
        saved: Vec<(String, Option<String>)>,
    }

    impl EnvGuard {
        fn new(keys: &[&str]) -> Self {
            let mut saved = Vec::with_capacity(keys.len());
            for key in keys {
                saved.push(((*key).to_string(), env::var(key).ok()));
            }
            Self { saved }
        }
    }

    impl Drop for EnvGuard {
        fn drop(&mut self) {
            for (key, value) in self.saved.drain(..) {
                match value {
                    Some(v) => env::set_var(key, v),
                    None => env::remove_var(key),
                }
            }
        }
    }

    #[test]
    fn json_no_store_sets_cache_control_header() {
        let resp = json_no_store(json!({"ok": true}));
        let cache_control = resp
            .headers()
            .get(header::CACHE_CONTROL)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");
        assert_eq!(cache_control, "no-store");
    }

    #[test]
    fn parse_ip_accepts_ip_and_socket_formats() {
        assert_eq!(parse_ip("1.2.3.4"), Some("1.2.3.4".to_string()));
        assert_eq!(parse_ip("1.2.3.4:8080"), Some("1.2.3.4".to_string()));
        assert_eq!(parse_ip("[2001:db8::1]"), Some("2001:db8::1".to_string()));
        assert_eq!(
            parse_ip("for=\"[2001:db8::2]:443\""),
            Some("2001:db8::2".to_string())
        );
        assert_eq!(parse_ip("not-an-ip"), None);
    }

    #[test]
    fn client_ip_prefers_edge_attested_header() {
        let mut headers = HeaderMap::new();
        headers.insert("x-shamell-client-ip", "203.0.113.10".parse().unwrap());
        headers.insert(
            "x-forwarded-for",
            "198.51.100.20, 198.51.100.21".parse().unwrap(),
        );
        let state = test_state("prod", true);
        let ip = client_ip_from_headers(&state, &headers);
        assert_eq!(ip, Some("203.0.113.10".to_string()));
    }

    #[test]
    fn client_ip_ignores_legacy_headers_in_prod() {
        let mut headers = HeaderMap::new();
        headers.insert("x-forwarded-for", "198.51.100.20".parse().unwrap());
        headers.insert("x-real-ip", "198.51.100.21".parse().unwrap());
        let state = test_state("prod", true);
        assert_eq!(client_ip_from_headers(&state, &headers), None);
    }

    #[test]
    fn client_ip_allows_legacy_headers_in_dev() {
        let mut headers = HeaderMap::new();
        headers.insert(
            "x-forwarded-for",
            "198.51.100.20, 198.51.100.21".parse().unwrap(),
        );
        let state = test_state("dev", true);
        assert_eq!(
            client_ip_from_headers(&state, &headers),
            Some("198.51.100.20".to_string())
        );
    }

    #[test]
    fn rate_limit_client_ip_requires_attested_header_in_prod() {
        let mut headers = HeaderMap::new();
        headers.insert("x-forwarded-for", "198.51.100.20".parse().unwrap());
        let state = test_state("prod", true);
        let err = rate_limit_client_ip(&state, &headers).unwrap_err();
        assert_eq!(err.status, StatusCode::INTERNAL_SERVER_ERROR);
    }

    #[test]
    fn extract_session_token_prefers_host_cookie_name() {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::COOKIE,
            "__Host-sa_session=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                .parse()
                .unwrap(),
        );
        let token = extract_session_token(&headers, true);
        assert_eq!(token.as_deref(), Some("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"));
    }

    #[test]
    fn extract_session_token_accepts_legacy_cookie_name() {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::COOKIE,
            "sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                .parse()
                .unwrap(),
        );
        let token = extract_session_token(&headers, true);
        assert_eq!(token.as_deref(), Some("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
    }

    #[test]
    fn extract_session_token_rejects_legacy_cookie_when_disabled() {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::COOKIE,
            "sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                .parse()
                .unwrap(),
        );
        let token = extract_session_token(&headers, false);
        assert_eq!(token, None);
    }

    #[test]
    fn extract_session_token_ignores_sa_cookie_header() {
        let mut headers = HeaderMap::new();
        headers.insert(
            HeaderName::from_static("sa_cookie"),
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".parse().unwrap(),
        );
        headers.insert(
            header::ORIGIN,
            "https://online.shamell.online".parse().unwrap(),
        );
        let token = extract_session_token(&headers, false);
        assert_eq!(token, None);
    }

    #[test]
    fn session_cookie_value_uses_host_prefix() {
        let cookie = session_cookie_value("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 60);
        assert!(cookie.starts_with("__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;"));
        assert!(!cookie.starts_with("sa_session="));
    }

    #[test]
    fn clear_cookie_values_include_host_and_legacy_names() {
        let host_cookie = clear_session_cookie_value();
        let legacy_cookie = clear_legacy_session_cookie_value();
        assert!(host_cookie.starts_with("__Host-sa_session=;"));
        assert!(legacy_cookie.starts_with("sa_session=;"));
    }

    #[test]
    fn shamell_user_id_is_len_8_and_alphabet_limited() {
        let id = generate_shamell_user_id();
        assert_eq!(id.len(), 8);
        assert!(id
            .chars()
            .all(|c| "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains(c)));
    }

    #[test]
    fn account_create_pow_token_roundtrip_and_rejects_tamper() {
        let secret = "test-secret";
        let payload = AccountCreatePowPayload {
            v: 1,
            device_id: "dev_1234".to_string(),
            nonce: "abcd1234".to_string(),
            difficulty: 4,
            exp: unix_now_secs().saturating_add(300),
        };
        let token = encode_pow_token(secret, &payload).expect("token");
        let decoded = decode_pow_token(secret, &token).expect("decode must succeed");
        assert_eq!(decoded.v, 1);
        assert_eq!(decoded.device_id, payload.device_id);
        assert_eq!(decoded.nonce, payload.nonce);
        assert_eq!(decoded.difficulty, payload.difficulty);
        assert_eq!(decoded.exp, payload.exp);

        let mut bad = token.clone();
        if let Some(last) = bad.pop() {
            bad.push(if last == 'A' { 'B' } else { 'A' });
        }
        assert!(decode_pow_token(secret, &bad).is_none());
    }

    #[test]
    fn account_create_pow_verification_rejects_expired_or_mismatched_device() {
        let secret = "test-secret";
        let now = unix_now_secs();
        let payload = AccountCreatePowPayload {
            v: 1,
            device_id: "dev_1234".to_string(),
            nonce: "abcd1234".to_string(),
            difficulty: 0,
            exp: now.saturating_sub(1),
        };
        let token = encode_pow_token(secret, &payload).expect("token");
        assert!(!verify_pow_solution(secret, "dev_1234", &token, "0"));

        let payload = AccountCreatePowPayload {
            v: 1,
            device_id: "dev_1234".to_string(),
            nonce: "abcd1234".to_string(),
            difficulty: 0,
            exp: now.saturating_add(300),
        };
        let token = encode_pow_token(secret, &payload).expect("token");
        assert!(!verify_pow_solution(secret, "other_device", &token, "0"));
        assert!(!verify_pow_solution(
            secret,
            "dev_1234",
            &token,
            "not-a-number"
        ));
    }

    #[test]
    fn account_create_attestation_nonce_is_stable_and_urlsafe() {
        let token = "v1.eyJ2IjoxLCJkZXZpY2VfaWQiOiJkZXYiLCJub25jZSI6ImFiY2QiLCJkaWZmaWN1bHR5IjowLCJleHAiOjQyfQ.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let n1 = account_create_attestation_nonce_b64(token).expect("nonce");
        let n2 = account_create_attestation_nonce_b64(token).expect("nonce");
        assert_eq!(n1, n2);
        // sha256 base64url w/o padding should be 43 chars
        assert_eq!(n1.len(), 43);
        assert!(n1
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'));

        let n3 = account_create_attestation_nonce_b64(&format!("{token}x")).expect("nonce");
        assert_ne!(n1, n3);
    }

    #[tokio::test]
    async fn chat_rate_limits_noop_without_auth_runtime() {
        let state = test_state("prod", true);
        let headers = HeaderMap::new();
        enforce_chat_register_rate_limit(&state, &headers, Some("dev-1"))
            .await
            .expect("no auth runtime");
        enforce_chat_get_device_rate_limit(&state, &headers, "dev-1")
            .await
            .expect("no auth runtime");
        enforce_chat_send_rate_limit(&state, &headers, Some("dev-1"))
            .await
            .expect("no auth runtime");
        enforce_chat_group_send_rate_limit(&state, &headers, Some("dev-1"))
            .await
            .expect("no auth runtime");
    }

    #[tokio::test]
    async fn device_login_page_rejects_when_web_disabled() {
        let state = test_state("prod", false);
        let err = device_login_page(State(state)).await.unwrap_err();
        assert_eq!(err.status, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn device_login_page_allows_when_web_enabled() {
        let state = test_state("prod", true);
        let resp = device_login_page(State(state)).await.unwrap();
        assert!(resp.0.contains("Device login"));
    }

    #[tokio::test]
    async fn account_create_from_env_ignores_partial_play_config_when_hw_attestation_disabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "DB_URL",
            "AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED",
            "AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED",
        ]);

        env::set_var("DB_URL", "postgresql://127.0.0.1:1/shamell_auth_test");
        env::set_var("AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED", "false");
        env::set_var("AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION", "false");
        env::remove_var("AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64");
        env::set_var(
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES",
            "online.shamell.app",
        );
        env::set_var(
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY",
            "true",
        );
        env::set_var(
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED",
            "true",
        );
        env::set_var(
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED",
            "false",
        );

        let err = match AuthRuntime::from_env("dev").await {
            Ok(_) => panic!("expected auth runtime init to fail"),
            Err(err) => err,
        };
        assert!(
            err.contains("auth postgres connect failed"),
            "unexpected error: {err}"
        );
    }

    #[tokio::test]
    async fn account_create_from_env_fails_on_partial_play_config_when_hw_attestation_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "DB_URL",
            "AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED",
            "AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES",
        ]);

        env::set_var("DB_URL", "postgresql://127.0.0.1:1/shamell_auth_test");
        env::set_var("AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED", "true");
        env::set_var("AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION", "true");
        env::remove_var("AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64");
        env::set_var(
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES",
            "online.shamell.app",
        );

        let err = match AuthRuntime::from_env("dev").await {
            Ok(_) => panic!("expected auth runtime init to fail"),
            Err(err) => err,
        };
        assert!(
            err.contains(
                "Play Integrity attestation configured partially; missing AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64"
            ),
            "unexpected error: {err}"
        );
    }

    #[tokio::test]
    async fn account_create_from_env_fails_in_prod_when_enabled_without_required_attestation() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "DB_URL",
            "AUTH_ACCOUNT_CREATE_ENABLED",
            "AUTH_ACCOUNT_CREATE_POW_ENABLED",
            "AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED",
            "AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION",
            "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID",
            "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID",
            "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64",
            "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES",
        ]);

        env::set_var("DB_URL", "postgresql://127.0.0.1:1/shamell_auth_test");
        env::set_var("AUTH_ACCOUNT_CREATE_ENABLED", "true");
        env::set_var("AUTH_ACCOUNT_CREATE_POW_ENABLED", "false");
        env::set_var("AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED", "false");
        env::set_var("AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION", "false");

        let err = match AuthRuntime::from_env("prod").await {
            Ok(_) => panic!("expected auth runtime init to fail"),
            Err(err) => err,
        };
        assert!(
            err.contains(
                "AUTH_ACCOUNT_CREATE_ENABLED=true in prod/staging requires hardware attestation enabled+required and at least one configured provider"
            ),
            "unexpected error: {err}"
        );
    }

    fn test_state(env_name: &str, auth_device_login_web_enabled: bool) -> AppState {
        AppState {
            env_name: env_name.to_string(),
            payments_base_url: "http://payments:8082".to_string(),
            payments_internal_secret: None,
            chat_base_url: "http://chat:8081".to_string(),
            chat_internal_secret: None,
            bus_base_url: "http://bus:8083".to_string(),
            bus_internal_secret: None,
            internal_service_id: "bff".to_string(),
            enforce_route_authz: true,
            role_header_secret: None,
            max_upstream_body_bytes: 1_048_576,
            expose_upstream_errors: false,
            accept_legacy_session_cookie: false,
            auth_device_login_web_enabled,
            http: reqwest::Client::new(),
            auth: None,
        }
    }
}
