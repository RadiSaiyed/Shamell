# Shamell Security Timer (Hetzner)

This folder contains `systemd` units for periodic runtime security alert evaluation:

- `shamell-security-events-report.service`
- `shamell-security-events-report.timer`

The service runs:

```bash
$APP_DIR/scripts/security_events_report.sh
```

with defaults derived from `APP_DIR`:

- `COMPOSE_FILE=$APP_DIR/ops/pi/docker-compose.postgres.yml`
- `ENV_FILE=$APP_DIR/ops/pi/.env`
- `SECURITY_ALERT_STATE_FILE=/var/lib/shamell-security/security-alert-cooldowns.state`

Values are loaded from `/etc/default/shamell-security-events-report` (managed by sync script).

## Install / Update On Host

From your local repo:

```bash
scripts/sync_hetzner_security_timer.sh shamell --run-now
```

Options:

- `--run-now`: trigger one immediate execution after installing timer
- `--drill`: run webhook drill once (`scripts/security_alert_webhook_drill.sh`)
- `REMOTE_APP_DIR=/path`: force remote app dir (otherwise auto-detected)
- `REMOTE_COMPOSE_FILE=/path`: override remote compose file path
- `REMOTE_ENV_FILE=/path`: override remote env file path
- `REMOTE_ALERT_STATE_FILE=/path`: override alert state file path

Auto-detection candidates:

- `/opt/shamell`
- `$HOME/shamell-src`
- `$HOME/shamell-pi-deploy`

The sync script auto-selects compose file priority:

- `$APP_DIR/ops/pi/docker-compose.postgres.yml` (preferred)
- fallback: `$APP_DIR/ops/pi/docker-compose.yml`

Env file auto-selection priority:

- `$APP_DIR/ops/pi/.env` (preferred)
- fallback: `$APP_DIR/ops/pi/.env.prod`
- fallback: `$APP_DIR/ops/pi/.env.staging`

It also syncs latest local security scripts to the remote app dir:

- `scripts/security_events_report.sh`
- `scripts/security_alert_webhook_drill.sh`

## Verify

```bash
ssh shamell "sudo systemctl status shamell-security-events-report.timer --no-pager"
ssh shamell "sudo systemctl list-timers --all shamell-security-events-report.timer --no-pager"
ssh shamell "sudo journalctl -u shamell-security-events-report.service -n 100 --no-pager"
```

## Disable

```bash
ssh shamell "sudo systemctl disable --now shamell-security-events-report.timer"
```
