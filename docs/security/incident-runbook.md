# Shamell Security Incident Runbook

## Purpose

This runbook defines detection, containment, credential rotation, recovery, and post-incident steps for:
- internal secret leak
- admin token exposure
- webhook abuse

It is written for Shamell-owned systems only (repository, CI, staging, production, and managed integrations).

## Severity & Response Targets

| Severity | Examples | First Triage | Full Containment |
| --- | --- | --- | --- |
| SEV-1 | Active admin account takeover, confirmed webhook fraud in progress | 15 minutes | 2 hours |
| SEV-2 | Exposed credential with no confirmed abuse yet | 30 minutes | 8 hours |
| SEV-3 | Suspicious signal, low confidence | 4 hours | 24 hours |

## Roles

- Incident Commander (IC): owns timeline and decisions.
- Security Lead: owns technical containment and forensic scope.
- Service Owner (BFF/Payments/Chat): executes code/config changes.
- Platform/DevOps: executes secret rotation and deployment rollout.
- Communications Owner: coordinates internal and customer/legal updates.

## Shared Playbook (All Incident Types)

1. Open an incident channel and assign IC + note-taker.
2. Freeze risky changes: pause deploys for affected services.
3. Preserve evidence:
   - CI logs
   - auth/access logs
   - webhook logs
   - recent config and secret-change history
4. Define blast radius:
   - which environments
   - which tenants/users
   - which credentials/tokens/keys
5. Apply temporary guardrails first (rate limits, deny rules, endpoint disable switches).
6. Rotate/replace compromised trust material.
7. Verify remediation with explicit regression checks.
8. Publish status update every 30-60 minutes until resolved.

## Scenario A: Internal Secret Leak

### Detection Signals

- Secret scanning alert (GitHub push protection/secret scanning).
- Unexpected auth usage from unknown IP, region, or user-agent.
- Spike in denied/accepted requests using one credential fingerprint.

### Containment

1. Revoke exposed key/token immediately in origin system.
2. Block known abusing origins at WAF/API gateway.
3. Disable affected automation jobs until replacement credentials exist.

### Rotation

1. Generate new credential with least privilege.
2. Update secret manager and CI/repository secrets.
3. Redeploy affected services in rolling order:
   - auth gateway
   - backend services
   - async workers/webhooks
4. Confirm old credential is hard-disabled (not just unused).

### Recovery Validation

- Smoke check all affected endpoints with new credential.
- Ensure old credential authentication fails.
- Confirm no fallback/default secret remains in code/config.

### Regression Test

- Add/update CI secret scanning policies and deny-list patterns.
- Add alert on credential usage outside expected source ranges.

## Scenario B: Admin Token Exposure

### Detection Signals

- Admin action logs from unknown device or impossible travel.
- Privilege changes without change request.
- Token reuse across multiple clients or sudden surge in admin API calls.

### Containment

1. Invalidate all active admin sessions/tokens.
2. Temporarily enforce step-up auth for all admin actions.
3. Lock affected admin accounts pending verification.

### Rotation

1. Rotate admin signing keys or token secrets if system-wide compromise is possible.
2. Re-issue admin sessions after identity re-verification.
3. Enforce shortened token TTL and refresh rotation.

### Recovery Validation

- Verify privileged endpoints require fresh auth and expected role claims.
- Review last 24-72 hours of admin actions; rollback unauthorized changes.

### Regression Test

- Add test coverage for:
  - role-check middleware on critical admin routes
  - token revocation list enforcement
  - no trust of client-provided internal headers

## Scenario C: Webhook Abuse

### Detection Signals

- Signature verification failures increase sharply.
- Replay-like patterns (same event ID/signature timestamp).
- Abnormal webhook source IP ranges or payload schema drift.

### Containment

1. Enforce strict webhook signature validation and timestamp tolerance.
2. Reject unsigned/invalid-signature events with explicit metrics.
3. Enable idempotency guard on event IDs and replay window checks.
4. If active abuse persists, temporarily disable webhook ingress and process from trusted queue/replay source.

### Rotation

1. Rotate webhook signing secret with provider and application.
2. Deploy secret change atomically (support dual-secret window if required by provider).
3. Decommission old secret after verification window.

### Recovery Validation

- Send provider test webhook and confirm:
  - valid signature accepted
  - invalid signature rejected
  - duplicate event ID rejected
- Reconcile payment/order/chat states for incident window.

### Regression Test

- CI/staging smoke must include invalid-signature negative test.
- Alert on signature-failure rate and replay-block count thresholds.

## Scenario D: `502 Bad Gateway` (Reverse-Proxy Upstream Drift)

### Detection Signals

- Cloudflare/edge returns `502` for multiple API paths.
- `nginx error.log` shows: `connect() failed (111: Connection refused) while connecting to upstream`.
- App container health is green on `127.0.0.1:8080/health`, but Nginx points to a different upstream (for example `127.0.0.1:8000`).

### Containment

1. Confirm scope quickly:
   - edge path (`https://api.../health`)
   - local Nginx path (`curl -k -H "Host: api..." https://127.0.0.1/health`)
   - direct app path (`http://127.0.0.1:8080/health`)
2. Keep firewall/WAF unchanged; treat as config drift first, not credential compromise.

### Recovery

1. Re-apply versioned Nginx configs from repo (`ops/hetzner/nginx/sites-available/*`).
2. Validate and reload:
   - `nginx -t`
   - `systemctl reload nginx`
3. Re-run smoke checks:
   - `/health` must return `200`
   - `/payments/admin/debug/tables` must return `401` without token.

### Regression Test

- Keep Nginx vhost config in git (IaC) and deploy through scripted sync.
- CI deploy guard must assert:
  - upstream health = `200`
  - payments admin endpoint without token = `401`
  - same checks through edge host route.

## Monitoring & Alerting Baseline

- Alert on:
  - secret scanning findings
  - admin auth anomalies
  - webhook signature failures and replay detections
  - payments edge abuse signals (wallet mismatch attempts + repeated rate-limit hits)
  - staging DAST smoke failures crossing `DAST_ALERT_CONSECUTIVE_FAILURES`
- Dashboards should include:
  - auth failures by endpoint/role
  - token issuance and revocation rates
  - webhook accepted/rejected counts by reason
  - payments edge rate-limit events by scope (`requests_*`, `favorites_*`, `resolve_phone`)

### Runtime Alert Controls (BFF)

- `SECURITY_ALERT_WEBHOOK_URL`: optional webhook target for runtime security alerts.
- `SECURITY_ALERT_WINDOW_SECS`: rolling window for threshold checks (default `300`).
- `SECURITY_ALERT_COOLDOWN_SECS`: minimum resend interval per alert action (default `600`).
- `SECURITY_ALERT_THRESHOLDS`: comma-separated `action:threshold` pairs. Default covers:
  - `payments_transfer_wallet_mismatch`
  - `alias_request_wallet_mismatch`
  - `alias_request_user_override_blocked`
  - `favorites_owner_wallet_mismatch`
  - `payments_request_from_wallet_mismatch`
  - `payments_edge_rate_limit_wallet`
  - `payments_edge_rate_limit_ip`
- Payments edge limiter controls:
  - `PAY_API_RATE_WINDOW_SECS`
  - `PAY_API_REQ_WRITE_MAX_PER_WALLET`, `PAY_API_REQ_WRITE_MAX_PER_IP`
  - `PAY_API_REQ_READ_MAX_PER_WALLET`, `PAY_API_REQ_READ_MAX_PER_IP`
  - `PAY_API_FAV_WRITE_MAX_PER_WALLET`, `PAY_API_FAV_WRITE_MAX_PER_IP`
  - `PAY_API_FAV_READ_MAX_PER_WALLET`, `PAY_API_FAV_READ_MAX_PER_IP`
  - `PAY_API_RESOLVE_MAX_PER_WALLET`, `PAY_API_RESOLVE_MAX_PER_IP`
- Environment templates with concrete baseline values:
  - `ops/pi/env.staging.example`
  - `ops/pi/env.prod.example`

### Rate-Limit Rollout (Staging -> Production)

1. Apply staging template (`ops/pi/env.staging.example`) and run for at least 24h.
2. Validate zero authz regressions on payments flows and monitor legitimate `429` ratio.
3. Promote to production with canary rollout:
   - 10% traffic for 30-60 minutes
   - 50% traffic for 2-4 hours
   - 100% traffic after stable signal
4. During rollout, gate promotion on:
   - no sustained increase in `5xx`
   - no sustained increase in support-reported false blocks
   - stable security alert volume (no unexplained spike)
5. After 7 clean days, tighten high-risk limits (`resolve_phone`, write actions) by 10-15%.

### Default Profiles (Current Baseline)

`staging` (strict pre-prod):

- `PAY_API_REQ_WRITE_MAX_PER_WALLET=20`
- `PAY_API_REQ_WRITE_MAX_PER_IP=80`
- `PAY_API_REQ_READ_MAX_PER_WALLET=100`
- `PAY_API_REQ_READ_MAX_PER_IP=300`
- `PAY_API_FAV_WRITE_MAX_PER_WALLET=15`
- `PAY_API_FAV_WRITE_MAX_PER_IP=60`
- `PAY_API_FAV_READ_MAX_PER_WALLET=100`
- `PAY_API_FAV_READ_MAX_PER_IP=300`
- `PAY_API_RESOLVE_MAX_PER_WALLET=8`
- `PAY_API_RESOLVE_MAX_PER_IP=30`

`prod` (balanced low/medium traffic):

- `PAY_API_REQ_WRITE_MAX_PER_WALLET=45`
- `PAY_API_REQ_WRITE_MAX_PER_IP=180`
- `PAY_API_REQ_READ_MAX_PER_WALLET=180`
- `PAY_API_REQ_READ_MAX_PER_IP=700`
- `PAY_API_FAV_WRITE_MAX_PER_WALLET=30`
- `PAY_API_FAV_WRITE_MAX_PER_IP=120`
- `PAY_API_FAV_READ_MAX_PER_WALLET=180`
- `PAY_API_FAV_READ_MAX_PER_IP=700`
- `PAY_API_RESOLVE_MAX_PER_WALLET=15`
- `PAY_API_RESOLVE_MAX_PER_IP=90`

## Post-Incident Closure

1. Timeline complete (UTC timestamps).
2. Root cause and contributing factors documented.
3. Permanent fixes tracked as issues with owners and due dates.
4. Runbook and detection rules updated from lessons learned.
5. Stakeholder/compliance notifications completed if required.
