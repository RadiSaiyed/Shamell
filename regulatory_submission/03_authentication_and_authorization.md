# Authentication and Authorization

## 1. Confirmed Authentication Methods

- Account creation with signed challenge material, device identifier, rate limiting, and optional proof-of-work plus hardware attestation
- Device-login approval/redeem flow using persisted challenge state
- Biometric re-login on supported devices
- Secure host-only session cookie issued by the backend
- Phone OTP login



## 2. Rider Authentication Flow

1. The client requests `/auth/account/create/challenge`.
2. The client submits `/auth/account/create` with `device_id`, challenge material, and attestation payload where required.
3. The backend rate limits by IP and device, validates proof-of-work and hardware attestation policy where enabled, inserts account/session/device rows, and sets `__Host-sa_session`.
4. Subsequent rider routes use session-bound `/me/...` endpoints.


## 3. Driver Authentication and Device Handling


- Driver-facing ride routes are protected by `require_ride_driver_principal`.
- Device registration binds the current session to `device_id` and upserts a `device_sessions` row.
- Device deletion removes the device inventory row, revokes matching sessions, and revokes biometric re-login tokens for that device.

## 4. Admin and Support Authentication

- Control/admin/support access still relies on the same server-side session principal model.
- Role sets are fetched server-side and checked against allowlists before protected ride-operator, support, compliance, and pricing routes are served.
- Public admin-role read and mutation paths are independently rate limited and audited.
- Granting or removing `admin` or `superadmin` requires a caller that already has `superadmin`.


## 5. Device Login Flow

1. A caller starts device login through `/auth/device_login/start`.
2. The backend persists a `device_login_challenges` row with expiry.
3. An already authenticated session approves the pending challenge through `/auth/device_login/approve`.
4. The target device redeems the challenge through `/auth/device_login/redeem`.
5. Redemption creates a fresh `auth_sessions` row and can bind browser/device metadata for replay resistance.


## 6. Biometric Re-Login

- The mobile client uses `local_auth` for local biometric approval.
- On iOS and macOS, biometric storage is configured with passcode-protected accessibility plus `biometryCurrentSet`.
- Biometric enrollment and biometric login use dedicated BFF endpoints.
- Biometric material is device-bound and revocable.


## 7. Session and Token Model


- The backend issues an opaque 32-hex session token and stores only `sid_hash` server-side.
- The session cookie name is `__Host-sa_session`.
- Cookie attributes are `HttpOnly`, `Secure`, `SameSite=Lax`, and `Path=/`.
- Legacy cookie clearing is still present for migration hygiene.
- Session TTL and idle TTL are runtime-configurable.
- Session activity is refreshed server-side through `last_seen_at`.
- Logout deletes the matching `auth_sessions` row and clears cookies.

## 8. Server-Side Authorization Model


- Route-level authorization is enforced server-side through `require_ride_driver_principal`, `require_ride_operator_principal`, `require_ride_support_principal`, `require_ride_compliance_principal`, and `require_ride_pricing_principal`.
- Role allowlists are centralized in backend auth code.
- Lower-trust roles receive redacted route text, redacted identifiers, and reduced location precision for operator/support responses.
- Rejected document review requires a review note.
- Sensitive ride and admin mutations emit structured audit events with hashed identifiers.


## 9. Client Storage and Handling of Session State


- Flutter clients use `flutter_secure_storage` with Android encrypted shared preferences and Apple secure keychain accessibility for session and security state.
- Session state is origin-scoped to avoid silent reuse across server origins.
- Mutable non-secure fallback is disabled by default on web and on mobile release builds.

## 10. Location Permissions and Background Access

- Android manifest requests foreground and background location, foreground-service location, boot-complete, wake-lock, and notification permissions.
- Android cleartext traffic is disabled and app backup is disabled.
- Rider and driver foreground location flows check service availability and runtime permission before calling `Geolocator.getCurrentPosition`.
- Driver background location flow checks service availability and existing permission before reading location.


## 11. Notification Handling

- The client requests remote-notification permission through Firebase Messaging.
- Separate Android notification channels exist for rider trip updates, driver dispatches, driver trip updates, and operator alerts.


## 12. Auditability

- Sensitive ride mutations log hashed actor and subject identifiers rather than raw identifiers.
- Admin-role reads and mutations are separately rate limited and audited.
- Security-event reporting scripts include alert thresholds for `admin_role_mutation.*` and `ride_sensitive_mutation.*`.

