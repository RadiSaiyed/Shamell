# Shamell Pi Deployment Notes

This folder contains the monolith compose file for Pi/edge deployments:

- `docker-compose.yml`

Security baseline env templates are provided for staged rollout:

- `env.staging.example`
- `env.prod.example`

Both templates focus on:

- payments edge rate limits (`PAY_API_*`)
- runtime security alerting (`SECURITY_ALERT_*`)
- disabling OTP/alias code exposure in non-dev environments

## Recommended Rollout

1. Copy one template into `ops/pi/.env` and keep existing secrets unchanged.
2. Enable `SECURITY_ALERT_WEBHOOK_URL` before tightening limits.
3. Deploy to staging first and run smoke + core payment flows for at least 24h.
4. Deploy to production with canary traffic first, then full rollout after clean metrics.

Suggested canary gates:

1. 10% traffic for 30-60 minutes.
2. 50% traffic for 2-4 hours.
3. 100% traffic if no sustained alert spikes or elevated `429` on legit flows.

## Tuning Heuristics

Use a 60-second limiter window (`PAY_API_RATE_WINDOW_SECS=60`) and tune by observed p95:

1. If legitimate `429` exceeds 0.3% for an action family over 15 minutes, raise that family by 15-25%.
2. If abuse telemetry stays low for 7 days, lower high-risk families (`resolve`, write paths) by 10-15%.
3. Keep `*_PER_IP` roughly 4x `*_PER_WALLET` to curb spray attacks while preserving NAT users.
4. Keep staging stricter than prod to catch regressions early.
