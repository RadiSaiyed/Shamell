# Shamell

Security project bootstrap (2026-02-06).

## Security Runbook

- Incident response playbook: `docs/security/incident-runbook.md`

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
