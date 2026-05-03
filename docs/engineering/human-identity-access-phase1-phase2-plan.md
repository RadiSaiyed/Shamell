# Human Identity & Access Phase 1 / Phase 2 Plan

## 1. Purpose
Turn the target architecture from
`docs/security/human-identity-access-target-architecture.md` into executable
work for the current Shamell repository.

This plan is intentionally repo-specific. It names the files and modules that
should change during the first two delivery phases.

## 2. Delivery Principles
- Phase 1 establishes the new identity foundation without breaking current
  passenger login flows.
- Phase 2 migrates existing Shamell Control, coach, and future partner surfaces
  away from coarse role checks and onto explicit permission snapshots.
- Backward compatibility is allowed during migration, but only behind an
  explicit transition layer.
- No privileged production surface should depend on Flutter-only role checks
  after Phase 2.

## 3. Phase 1 Scope
Phase 1 delivers:

- workforce IAM foundation
- Cloudflare Access plus OIDC integration model
- new BFF workforce session exchange
- explicit role assignments and scope assignments in Shamell auth storage
- permission snapshot API
- compatibility bridge for existing dashboards

Phase 1 does not yet deliver:

- full UI migration of every privileged page
- final removal of legacy coarse roles
- complete partner self-service onboarding

## 4. Phase 2 Scope
Phase 2 delivers:

- migration of current privileged Flutter surfaces to permission snapshots
- operator and crew scope enforcement everywhere
- refined domain roles for coach, ride, and cash
- removal of frontend-only authorization as the primary gate
- rollout of dedicated partner and staff dashboard hostnames

## 5. Current Baseline To Reuse
The following existing pieces should be reused instead of discarded:

- BFF route authz middleware:
  `services_rs/bff_gateway/src/authz.rs`
- BFF role cache:
  `services_rs/bff_gateway/src/state.rs`
- current role fetch path:
  `services_rs/bff_gateway/src/auth.rs`
- existing admin role management routes:
  `services_rs/bff_gateway/src/handlers.rs`
- current coarse admin access UI:
  `clients/shamell_flutter/lib/core/superadmin_control_access_page.dart`
- current privilege storage:
  `clients/shamell_flutter/lib/core/account_privilege_store.dart`
- current operator and admin pages:
  `clients/shamell_flutter/lib/core/coach_bus/*`

## 6. Target Data Model
Phase 1 should add new auth-side tables in the BFF auth database.

Recommended new tables:
- `auth_human_identities`
- `auth_workforce_accounts`
- `auth_organizations`
- `auth_workforce_memberships`
- `auth_role_definitions`
- `auth_role_assignments`
- `auth_scope_assignments`
- `auth_idp_subject_links`
- `auth_permission_snapshots`
- `auth_access_audit_events`
- `auth_break_glass_events`

Compatibility note:
- current `/admin/roles` can remain readable during migration
- new assignments become the source of truth
- legacy role strings are materialized only for compatibility consumers

## 7. Phase 1 Workstreams

### 7.1 Identity and edge configuration
Create the new workforce identity configuration surface.

Files to change:
- `.env.example`
- `ops/pi/env.prod.example`
- `ops/pi/env.staging.example`
- `services_rs/bff_gateway/src/config.rs`

Add config families for:
- ZITADEL issuer URL
- ZITADEL client IDs
- workforce OIDC audience
- Cloudflare Access team domain
- Cloudflare Access audience tags
- Cloudflare Access JWKS or certs URL
- workforce session TTLs
- break-glass session TTL
- step-up policy toggles

Expected result:
- staging and production can validate workforce identity without hardcoding
  environment-specific logic.

### 7.2 BFF workforce auth foundation
Introduce a dedicated workforce login exchange and permission snapshot.

Files to change:
- `services_rs/bff_gateway/src/auth.rs`
- `services_rs/bff_gateway/src/authz.rs`
- `services_rs/bff_gateway/src/main.rs`
- `services_rs/bff_gateway/src/models.rs`
- `services_rs/bff_gateway/src/state.rs`

Add endpoints:
- `POST /auth/workforce/session/exchange`
- `GET /me/permissions`
- `GET /me/access-context`
- `GET /admin/access/assignments`
- `POST /admin/access/assignments`
- `DELETE /admin/access/assignments`

Expected result:
- the BFF can exchange trusted workforce identity into a Shamell session
- frontends can request a normalized permission snapshot
- admin tools can manage assignments without relying on generic string roles

### 7.3 Cloudflare Access JWT validation
Move production web trust from injected role headers to validated Access JWTs.

Files to change:
- `services_rs/bff_gateway/src/auth.rs`
- `services_rs/bff_gateway/src/authz.rs`
- `services_rs/bff_gateway/src/config.rs`
- `ops/hetzner/nginx/snippets/shamell_bff_edge_hardening.conf`
- `ops/hetzner/nginx/snippets/shamell_bff_role_attestation.local.conf.example`

Expected result:
- production web requests carry `Cf-Access-Jwt-Assertion`
- the BFF validates issuer, audience, signature, and expiry
- `X-Auth-Roles` and `X-Role-Auth` remain local-dev or migration-only helpers

### 7.4 New auth migration
Add the auth schema migration for human and partner access control.

Files to add:
- `services_rs/bff_gateway/migrations/<next>_human_identity_access.sql`

Migration contents:
- new tables
- indexes for account, organization, operator, branch, and status lookups
- foreign keys and immutable audit append tables
- seed rows for the canonical role definitions

Expected result:
- the data model exists before UI migration starts

### 7.5 Compatibility bridge
Keep current dashboards working while introducing the new model.

Files to change:
- `services_rs/bff_gateway/src/auth.rs`
- `services_rs/bff_gateway/src/handlers.rs`

Bridge behavior:
- derive legacy coarse roles from the new assignments where required
- keep `/me/roles` operational during migration
- append operator ids and scope hints for existing consumers

Expected result:
- no forced big-bang rewrite

## 8. Phase 2 Workstreams

### 8.1 Replace raw role storage in Flutter
Migrate Flutter from coarse role strings to permission snapshots.

Files to change:
- `clients/shamell_flutter/lib/core/account_privilege_store.dart`
- `clients/shamell_flutter/lib/src/main_bootstrap.dart`
- `clients/shamell_flutter/lib/src/main_shell.dart`

Target change:
- store `permission_snapshot`, not only `roles`
- expose helper methods like:
  - `can(permission, scope)`
  - `hasProductAccess(product)`
  - `hasOperatorScope(operatorId)`

Expected result:
- the app shell and navigation stop inferring privilege from loose strings like
  `ops` or `seller`

### 8.2 Replace coarse admin access UI
Upgrade access management from raw role grant/removal to explicit assignments.

Files to change:
- `clients/shamell_flutter/lib/core/superadmin_control_access_page.dart`

Target change:
- support selecting:
  - role
  - organization
  - operator
  - city
  - branch
  - cash point
  - expiry where relevant
- require step-up auth for sensitive mutations

Expected result:
- internal access administration becomes explicit and tenant-aware

### 8.3 Migrate coach admin and operator surfaces
Stop using local static role allowlists for coach surfaces.

Files to change:
- `clients/shamell_flutter/lib/core/coach_bus/coach_admin_console_page.dart`
- `clients/shamell_flutter/lib/core/coach_bus/coach_admin_support_cases_page.dart`
- `clients/shamell_flutter/lib/core/coach_bus/coach_operator_console_page.dart`
- `clients/shamell_flutter/lib/core/coach_bus/coach_boarding_console_page.dart`
- `clients/shamell_flutter/lib/core/coach_bus/coach_mobility_api.dart`

Target change:
- gate access with explicit permissions
- enforce returned operator scope everywhere
- remove broad `admin/superadmin/ops` shortcuts where a narrower domain role is
  required

Expected result:
- coach admin, operator, and crew surfaces become properly separated

### 8.4 Prepare ride and cash surfaces
Apply the same pattern to ride and cash dashboards.

Likely files:
- ride admin and ops pages under `clients/shamell_flutter/lib/core/`
- wallet and cash management pages under `clients/shamell_flutter/lib/core/`
- related BFF handlers in `services_rs/bff_gateway/src/handlers.rs`

Expected result:
- city managers, driver ops, cash agents, and finance users stop sharing the
  same coarse privilege model

### 8.5 Dedicated dashboard hostnames
Split workforce surfaces into dedicated hosts.

Files to change:
- `ops/hetzner/nginx/sites-available/shamell.online`
- `ops/hetzner/nginx/sites-available/online.shamell.online`
- add new site configs for:
  - `control.shamell.online`
  - `ops.shamell.online`
  - `coach-operators.shamell.online`
  - `crew.shamell.online`
  - `cash.shamell.online`
- `scripts/sync_hetzner_nginx.sh`
- `scripts/check_nginx_edge_hardening.sh`

Expected result:
- one Cloudflare Access application per protected hostname
- simpler policy and session management

## 9. Legacy Role Migration Map
Use a deliberate mapping instead of silently reusing old strings forever.

Recommended initial mapping:

| Legacy role | Transitional mapping |
| --- | --- |
| `superadmin` | `owner.daily_admin` or `platform.admin` depending on person |
| `ops` | `owner.daily_admin` or `platform.ops_manager` |
| `seller` | split into `owner.daily_admin`, `platform.finance_admin`, or remove |
| `admin` | `platform.admin` |
| `operator_*` | replace with explicit domain role plus scope |

Rules:
- do not auto-map every old high-privilege role to break-glass access
- review every existing admin identity manually during migration

## 10. Testing Plan

### 10.1 BFF tests
Files to add or expand:
- `services_rs/bff_gateway/src/authz.rs` tests
- `services_rs/bff_gateway/src/auth.rs` tests
- `services_rs/bff_gateway/src/handlers.rs` tests

Add coverage for:
- workforce session exchange
- Access JWT validation
- permission snapshot derivation
- scope-restricted operator access
- cash branch and till scoping
- break-glass session TTL and step-up gates

### 10.2 Flutter tests
Files to add or expand:
- `clients/shamell_flutter/test/main_bootstrap_*`
- `clients/shamell_flutter/test/main_shell_*`
- dedicated tests for coach admin, operator, and boarding pages
- tests for access-management UI

Add coverage for:
- permission snapshot caching
- role-to-permission rendering
- operator-scope filtering
- denial states for insufficient permissions

## 11. Rollout Order

### Step 1
- ship the Phase 1 schema and BFF endpoints behind flags

### Step 2
- configure ZITADEL and Cloudflare Access in staging

### Step 3
- provision owner daily admin and break-glass accounts

### Step 4
- migrate internal admin users first

### Step 5
- migrate coach operator admins and crew users

### Step 6
- migrate cash agent users

### Step 7
- remove legacy coarse-role dependencies from frontends

### Step 8
- enforce production-only Access JWT validation and remove compatibility paths

## 12. Acceptance Criteria
Phase 1 is complete when:

- workforce identity can be exchanged into a Shamell session
- the BFF can return a normalized permission snapshot
- Cloudflare-protected workforce web routes are validated at origin
- role assignments and scope assignments are stored in Shamell auth data

Phase 2 is complete when:

- current privileged Flutter surfaces use permission snapshots
- operator, crew, and cash scopes are enforced consistently
- coarse role strings are no longer the source of truth
- every privileged write emits an audit event with actor, scope, and reason

## 13. First Engineering Tickets To Open
Open these first:

1. Add workforce IAM configuration and BFF Access JWT validation.
2. Add auth migration for human identities, organizations, assignments, and audit.
3. Implement `POST /auth/workforce/session/exchange`.
4. Implement `GET /me/permissions` and `GET /me/access-context`.
5. Upgrade `account_privilege_store.dart` to cache permission snapshots.
6. Replace `superadmin_control_access_page.dart` raw role grants with scoped assignments.
7. Migrate coach admin, operator, and boarding pages to permissions plus scope.

