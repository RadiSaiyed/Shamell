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

## Monitoring & Alerting Baseline

- Alert on:
  - secret scanning findings
  - admin auth anomalies
  - webhook signature failures and replay detections
- Dashboards should include:
  - auth failures by endpoint/role
  - token issuance and revocation rates
  - webhook accepted/rejected counts by reason

## Post-Incident Closure

1. Timeline complete (UTC timestamps).
2. Root cause and contributing factors documented.
3. Permanent fixes tracked as issues with owners and due dates.
4. Runbook and detection rules updated from lessons learned.
5. Stakeholder/compliance notifications completed if required.

