# Staging DAST Setup

This guide configures the `Staging DAST Smoke` workflow:

- `.github/workflows/staging-dast-smoke.yml`
- `.github/scripts/staging_dast_smoke.sh`

## 1) Required Secrets

Set these repository secrets (or environment `staging` secrets):

- `STAGING_BFF_BASE_URL`
- `STAGING_PAYMENTS_BASE_URL`
- `STAGING_CHAT_BASE_URL`
- `SECURITY_ALERT_WEBHOOK_URL` (optional; Slack/Teams webhook)
- `TRUSTED_REVIEW_BOT_TOKEN` (optional; token from a dedicated second GitHub reviewer account)

Example:

```bash
gh secret set STAGING_BFF_BASE_URL --repo RadiSaiyed/Shamell --body "https://staging-api.example.com"
gh secret set STAGING_PAYMENTS_BASE_URL --repo RadiSaiyed/Shamell --body "https://staging-payments.example.com"
gh secret set STAGING_CHAT_BASE_URL --repo RadiSaiyed/Shamell --body "https://staging-chat.example.com"
```

Single-host/monolith staging is supported too (all three secrets can point to the same API host).
In that mode, the smoke script automatically uses:
- payments admin check path: `/payments/admin/debug/tables`
- payments webhook path: `/payments/webhooks/psp`

## 2) Alerting Threshold Variables

Set repository variables:

- `DAST_MAX_FAILED_CHECKS` (default: `0`)
- `DAST_MAX_RESPONSE_MS` (default: `2500`)
- `DAST_ALERT_CONSECUTIVE_FAILURES` (default: `2`)
- `DAST_PAYMENTS_ADMIN_PATH` (optional override path)
- `DAST_PAYMENTS_WEBHOOK_PATH` (optional override path)
- `TRUSTED_REVIEW_BOT_ENABLED` (default: `true`)
- `TRUSTED_REVIEWER_LOGIN` (optional; fallback reviewer username when bot token is not set)

Example:

```bash
gh variable set DAST_MAX_FAILED_CHECKS --repo RadiSaiyed/Shamell --body "0"
gh variable set DAST_MAX_RESPONSE_MS --repo RadiSaiyed/Shamell --body "2500"
gh variable set DAST_ALERT_CONSECUTIVE_FAILURES --repo RadiSaiyed/Shamell --body "2"
gh variable set TRUSTED_REVIEW_BOT_ENABLED --repo RadiSaiyed/Shamell --body "true"
gh variable set TRUSTED_REVIEWER_LOGIN --repo RadiSaiyed/Shamell --body "your-second-reviewer-username"
```

## 3) Failure Handling

When DAST fails, workflow job `alert-on-failure`:

1. computes consecutive failures,
2. creates/updates an open security incident issue after threshold is reached,
3. sends webhook notification if `SECURITY_ALERT_WEBHOOK_URL` is configured.

Recommended labels:

- `security`
- `incident`
- `dast`

## 4) Validation

1. Run workflow manually from Actions tab (`workflow_dispatch`).
2. Confirm:
   - check output includes `Staging DAST Summary`,
   - failures create/update a labeled incident issue after threshold,
   - webhook notification fires when configured.
