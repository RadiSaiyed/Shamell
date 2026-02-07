# Courier Hardening (Ingress / VPN / Admin)

This service should not be exposed directly to the public Internet. Use a private ingress and a Zero Trust/IAP layer for admin/KPI endpoints.

## Network posture
- **Private ingress**: terminate TLS on an internal load balancer or private Ingress (e.g., GCP Internal HTTPS LB, AWS internal ALB/NLB) in a VPC. Do not expose courier pods via public IP/DNS.
- **Allowlists**: restrict ingress to trusted CIDRs (VPN egress, office IPs) and BFF connector ranges. Block everything else by default.
- **mTLS**: enforce mTLS for service-to-service traffic (BFF → courier) via mesh/Ingress. Use client certs; rotate regularly.
- **IAP/Zero Trust**: front admin/KPI endpoints with an Identity-Aware Proxy (Cloud IAP, Verified Access, Cloudflare Access, Tailscale). Require SSO + MFA for ops users. Prefer short-lived OIDC tokens over static headers.

## Secrets & config
- Store `COURIER_ADMIN_TOKEN`, `COURIER_INTERNAL_SECRET`, Mapbox/PTV tokens in a secrets manager (KMS/SM/Secrets Manager). Inject via env; rotate on schedule.
- Do not bake secrets into images or logs. Use per-env values.

## Ingress examples (Ingress annotations)
- Allowlist CIDRs (Nginx ingress):
  ```yaml
  nginx.ingress.kubernetes.io/whitelist-source-range: "203.0.113.0/24,198.51.100.0/24"
  ```
- Require mTLS (Nginx):
  ```yaml
  nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
  nginx.ingress.kubernetes.io/auth-tls-secret: "ops/courier-client-ca"
  ```
- Path split: expose only `/courier/track/public/*` publicly (if needed); keep `/courier/stats`, `/courier/kpis/*`, `/courier/stats/export`, `/courier/kpis/partners/export` behind private ingress/IAP.

## Logging & monitoring
- Ship ingress/mTLS/IAP logs to SIEM; alert on repeated 403/429 bursts or access from unexpected IPs/regions.
- Keep `/health` cluster-only; expose `/metrics` to Prometheus via ServiceMonitor, not public ingress.

## Verification checklist
- No public IP/DNS resolves to courier pods.
- Admin/KPI paths return 403 from the Internet.
- mTLS handshake required for BFF → courier.
- IAP/SSO enforced with MFA for ops users.
- Secrets rotated and only present via env at runtime.

## BFF considerations
- BFF should talk to courier via private DNS (mesh or VPC) only.
- Apply WAF/rate limits on BFF ingress; BFF inherits courier attack surface for end-user paths.
