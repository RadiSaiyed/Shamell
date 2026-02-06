# Shamell

Security project bootstrap (2026-02-06).

## Security Runbook

- Incident response playbook: `docs/security/incident-runbook.md`
- Staging DAST setup: `docs/security/staging-dast-setup.md`

## Semgrep AuthZ/IDOR Rules

Custom regression rules live in `.semgrep/rules/authz-idor.yml` and target:
- wallet-scoped queries without actor/user ownership checks
- trust of client-provided internal headers
- unsafe token query construction patterns

Run locally:

```bash
python -m pip install semgrep
semgrep --config .semgrep/rules/authz-idor.yml --error .
```

## Trusted Review Bot

- Workflow: `.github/workflows/trusted-review-bot.yml`
- Purpose: keeps branch protection at `required_approving_review_count=1` by adding `github-actions[bot]` approval for trusted in-repo PRs.
- Toggle: repository variable `TRUSTED_REVIEW_BOT_ENABLED` (`true`/`false`, default `true`).

<!-- review-bot-smoke -->
