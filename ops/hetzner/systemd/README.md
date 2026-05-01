# Shamell Periodic Timers (Hetzner)

This folder contains `systemd` units for periodic runtime checks:

- security event report + alert evaluation
- ride ops audit / stale-flow detection
- encrypted ride/auth database backup

## Security Timer

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
If `APP_DIR` is omitted there, the shell wrapper falls back to `/opt/shamell`; the unit itself no
longer hardcodes `APP_DIR`, so sync-time remote path detection can actually override it.
When using the in-host BFF webhook target, set `SECURITY_ALERT_WEBHOOK_SIGNING_SEED_B64`
so the timer posts signed internal identity headers instead of relying on legacy secrets.
If a previous run still holds the lock, the service now exits with code `75` and systemd treats that
as a benign skipped run rather than a failed unit.

## Install / Update On Host

From your local repo:

```bash
scripts/sync_hetzner_security_timer.sh shamell --run-now
```

Options:

- `--run-now`: trigger one immediate execution after installing timer
- `--drill`: run webhook drill once (`scripts/security_alert_webhook_drill.sh`) using the same resolved `REMOTE_ENV_FILE` as the timer service
- `REMOTE_APP_DIR=/path`: force remote app dir (otherwise auto-detected)
- `REMOTE_COMPOSE_FILE=/path`: override remote compose file path
- `REMOTE_ENV_FILE=/path`: override remote env file path
- `REMOTE_ALERT_STATE_FILE=/path`: override alert state file path
- `SECURITY_ALERT_DRILL_ALERTS=...`: optional comma-separated alert list forwarded to `--drill`
- `SECURITY_ALERT_DRILL_SEVERITY=warning|high|critical|info`: optional severity override for `--drill`
- `SECURITY_ALERT_DRILL_SERVICE=name`: optional service label override for `--drill`
- `SECURITY_ALERT_DRILL_NOTE=text`: optional note override for `--drill`

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

Remote app-dir auto-detection also treats any of those three env-file names as a valid deployed repo.
That avoids selecting an older compose checkout just because it has no plain `.env` file.

It also syncs latest local security scripts to the remote app dir:

- `scripts/security_events_report.sh`
- `scripts/security_alert_webhook_drill.sh`

Targeted drill example:

```bash
SECURITY_ALERT_DRILL_ALERTS='chat_prekey_inventory.low:3/3,chat_key_bootstrap_policy.blocked:1/1' \
SECURITY_ALERT_DRILL_SEVERITY=warning \
scripts/sync_hetzner_security_timer.sh shamell --drill
```

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

## Ride Ops Timer

This folder also contains:

- `shamell-ride-ops-report.service`
- `shamell-ride-ops-report.timer`

The service runs:

```bash
$APP_DIR/scripts/ride_ops_report.sh
```

with defaults derived from `APP_DIR`:

- `COMPOSE_FILE=$APP_DIR/ops/pi/docker-compose.postgres.yml`
- `ENV_FILE=$APP_DIR/ops/pi/.env`

Values are loaded from `/etc/default/shamell-ride-ops-report` (managed by sync script).
If `APP_DIR` is omitted there, the shell wrapper falls back to `/opt/shamell`; the unit itself no
longer hardcodes `APP_DIR`, so sync-time remote path detection can actually override it.
The ride timer defaults `RIDE_REPORT_FAIL_ON_FINDINGS=1`, so stale ride state causes the service
to fail for monitoring purposes instead of silently passing.
If a previous run still holds the lock, the ride timer exits with code `75` and systemd treats that
as a benign skipped run rather than a failed unit.

### Install / Update On Host

From your local repo:

```bash
./scripts/ops.sh pipg sync-ride-report-timer shamell --run-now
```

Options:

- `--run-now`: trigger one immediate execution after installing timer
- `REMOTE_APP_DIR=/path`: force remote app dir (otherwise auto-detected)
- `REMOTE_COMPOSE_FILE=/path`: override remote compose file path
- `REMOTE_ENV_FILE=/path`: override remote env file path
- `RIDE_REPORT_*`: optional threshold overrides copied into `/etc/default/shamell-ride-ops-report`

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

Remote app-dir auto-detection also treats any of those three env-file names as a valid deployed repo.
That avoids selecting an older compose checkout just because it has no plain `.env` file.
`--run-now` executes the timer service on-host using the same resolved `REMOTE_ENV_FILE` as the timer service.

### Verify

```bash
ssh shamell "sudo systemctl status shamell-ride-ops-report.timer --no-pager"
ssh shamell "sudo systemctl list-timers --all shamell-ride-ops-report.timer --no-pager"
ssh shamell "sudo journalctl -u shamell-ride-ops-report.service -n 100 --no-pager"
```

### Disable

```bash
ssh shamell "sudo systemctl disable --now shamell-ride-ops-report.timer"
```

## Ride/Auth Backup Timer

This folder also contains:

- `shamell-ride-db-backup.service`
- `shamell-ride-db-backup.timer`

The service runs:

```bash
$APP_DIR/scripts/ride_db_backup.sh
```

with defaults derived from `APP_DIR`:

- `COMPOSE_FILE=$APP_DIR/ops/pi/docker-compose.postgres.yml`
- `ENV_FILE=$APP_DIR/ops/pi/.env`
- `RIDE_DB_BACKUP_OUTPUT_DIR=/var/backups/shamell`

Values are loaded from `/etc/default/shamell-ride-db-backup` (managed by sync script).
The backup script is fail-closed for encryption: it only accepts `age` or `gpg`
and exits if the configured recipient is missing.

### Install / Update On Host

From your local repo:

```bash
./scripts/sync_hetzner_ride_backup_timer.sh shamell --run-now
```

Options:

- `--run-now`: trigger one immediate backup after installing timer
- `REMOTE_APP_DIR=/path`: force remote app dir
- `REMOTE_COMPOSE_FILE=/path`: override remote compose file path
- `REMOTE_ENV_FILE=/path`: override remote env file path
- `RIDE_DB_BACKUP_*`: optional backup overrides copied into `/etc/default/shamell-ride-db-backup`

### Verify

```bash
ssh shamell "sudo systemctl status shamell-ride-db-backup.timer --no-pager"
ssh shamell "sudo systemctl list-timers --all shamell-ride-db-backup.timer --no-pager"
ssh shamell "sudo journalctl -u shamell-ride-db-backup.service -n 100 --no-pager"
```

### Disable

```bash
ssh shamell "sudo systemctl disable --now shamell-ride-db-backup.timer"
```
