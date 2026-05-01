# Human Identity & Access Target Architecture

## 1. Goal
Establish one consistent access model for all Shamell workforce and partner surfaces:

- Shamell owner access
- employee admin access
- operations dashboards
- coach operator portals
- crew and boarding apps
- cash-in and cash-out agent surfaces
- future partner and regulator surfaces

This document is about human access and partner access. It is separate from the
existing service-to-service identity roadmap in
`docs/security/workload-identity-roadmap.md`.

## 2. Non-Negotiable Rules

### 2.1 Identity
- No shared accounts.
- No permanent login bypasses in production.
- No single daily-use "god account".
- Every human must have a unique identity.
- Machine access must use service accounts, never human credentials.

### 2.2 Authorization
- Cloudflare or any other edge layer may decide whether a request may reach the
  origin, but Shamell BFF remains the final authorization authority.
- Frontends may hide buttons, but they must never be the source of truth for
  permissions.
- Every privileged action must be checked server-side.
- Every privileged write must emit an immutable audit event.

### 2.3 Scope
- Partner access must always be constrained by scope.
- A bus operator must only see its own operator data.
- A cash agent must only see the assigned branch, till, or cash point.
- Internal staff must only see the products and regions required for their job.

### 2.4 Owner access
- The platform owner should have:
  - one daily admin identity for normal work
  - one break-glass identity for emergencies only
- The break-glass identity must require stronger authentication and a shorter
  session duration than the daily admin identity.

## 3. Current Repo Baseline
Shamell already has several useful building blocks:

- BFF privileged route protection can be enforced with edge-attested roles and
  a required application session:
  `services_rs/bff_gateway/src/authz.rs`
- Production config already expects route authz hardening:
  `BFF_ENFORCE_ROUTE_AUTHZ` and `BFF_ROLE_HEADER_SECRET` in `.env.example`
- Current account roles are fetched server-side and exposed via `/me/roles`:
  `services_rs/bff_gateway/src/auth.rs`
- There is already a role-management UI for coarse admin roles:
  `clients/shamell_flutter/lib/core/superadmin_control_access_page.dart`
- Several Flutter surfaces still make local allow/deny decisions from raw role
  strings:
  - `clients/shamell_flutter/lib/core/coach_bus/coach_admin_console_page.dart`
  - `clients/shamell_flutter/lib/core/coach_bus/coach_boarding_console_page.dart`
  - `clients/shamell_flutter/lib/src/main_bootstrap.dart`

That baseline is good enough to migrate without rewriting everything from
scratch, but it is not sufficient for a multi-tenant, partner-heavy platform.

## 4. Recommended Target Stack

### 4.1 Identity provider
Use ZITADEL as the central human identity platform for:

- employees
- owner identities
- partner operator users
- cash agent users
- machine and automation identities

Why:
- it is multi-tenant by design
- it supports Organizations and Granted Projects for B2B access delegation
- it supports MFA and Passkeys
- it supports human users and service accounts

### 4.2 Edge access gateway
Use Cloudflare Access as the gateway for all web dashboards and portals.

Cloudflare Access should:
- authenticate users against ZITADEL through OIDC
- enforce coarse entry policies before traffic reaches the origin
- inject a signed application token for the origin to validate
- apply MFA, session duration, and device posture policies per application

### 4.3 Shamell BFF authorization
Use the Shamell BFF as the final authority for permissions and scope.

The BFF should:
- validate workforce identity coming from Cloudflare Access or staff-mobile OIDC
- exchange that identity into a first-party Shamell session
- resolve role assignments and scope assignments
- derive a permission snapshot
- enforce authorization on every privileged route

## 5. What Must Be Separated
Do not mix these user populations into one login and role model:

- consumer passenger accounts
- internal Shamell workforce users
- partner organization users
- machine and automation users

Required separation:

- Passenger auth remains the current consumer account path.
- Workforce and partner auth move to the new workforce IAM path.
- Machines use service accounts only.

The passenger Shamell app and the workforce/partner control plane may share
backend infrastructure, but they must not share the same identity semantics.

## 6. Target Runtime Architecture
```text
Human user
-> ZITADEL
   - user identity
   - organization membership
   - MFA / passkeys
   - service accounts
-> Cloudflare Access
   - per-application entry policy
   - JWT assertion to origin
   - session duration
   - device posture for high-trust apps
-> Shamell BFF
   - validate Cloudflare Access JWT or staff-mobile OIDC token
   - create or refresh Shamell workforce session
   - load role assignments + scope assignments
   - derive permission snapshot
   - enforce route-level authorization
-> Product facades
   - control
   - rides
   - coach
   - cash
   - support
   - audit
-> Domain data and downstream services
```

## 7. Identity Objects
The target model needs the following first-class concepts.

### 7.1 Human identity
One real person, regardless of how they log in.

Fields:
- `human_id`
- `idp_provider`
- `idp_subject`
- `email`
- `phone`
- `display_name`
- `status`

### 7.2 Workforce account
The Shamell-local authorization identity linked to the human.

Fields:
- `account_id`
- `human_id`
- `account_type`
- `status`
- `created_at`
- `suspended_at`

### 7.3 Organization
The tenant boundary for partner and internal structures.

Examples:
- `org_shamell_internal`
- `org_bus_demo_express`
- `org_cash_partner_north`

### 7.4 Scope
The business boundary attached to a role assignment.

Supported scope dimensions should include:
- `platform`
- `organization_id`
- `operator_id`
- `city_id`
- `branch_id`
- `cash_point_id`
- `product`

## 8. Canonical Role Catalog
Roles must be human-readable, explicit, and namespaced by domain.

### 8.1 Owner and platform roles

| Role ID | Intended users | Typical surfaces | Required scope |
| --- | --- | --- | --- |
| `owner.break_glass` | Owner only | all | `platform` |
| `owner.daily_admin` | Owner and top trusted admin | control, access admin | `platform` |
| `platform.admin` | senior internal admins | control dashboards | `platform` |
| `platform.security_admin` | security lead | sessions, access, audit, incident tools | `platform` |
| `platform.ops_manager` | operations lead | live operations, escalation, support | `platform` or `city_id` |
| `platform.support_l1` | first-line support | support tools only | `product` and optional `city_id` |
| `platform.support_l2` | advanced support | support, refunds, manual recoveries | `product` and optional `city_id` |
| `platform.finance_admin` | finance managers | finance journals, payout controls, reconciliation | `product` or `platform` |
| `platform.finance_readonly` | finance readers | finance read-only dashboards | `product` or `platform` |
| `platform.compliance_admin` | compliance and risk | KYC, risk review, export, audit | `platform` |
| `audit.readonly` | auditors and regulators | audit-only dashboards and exports | explicit scope only |

### 8.2 Ride-hailing roles

| Role ID | Intended users | Typical surfaces | Required scope |
| --- | --- | --- | --- |
| `rides.city_manager` | city-level ride managers | Shamell Control ride views | `city_id` |
| `rides.driver_ops` | dispatch and driver onboarding staff | ride driver ops dashboards | `city_id` |

### 8.3 Coach platform roles

| Role ID | Intended users | Typical surfaces | Required scope |
| --- | --- | --- | --- |
| `coach.operator_admin` | bus operator managers | operator portal | `organization_id + operator_id` |
| `coach.operator_staff` | bus operator office staff | manifests, schedules, disruptions | `organization_id + operator_id` |
| `coach.boarding_agent` | terminal staff and crew | crew and boarding app | `organization_id + operator_id` |
| `coach.settlement_readonly` | operator finance readers | statements and settlement exports | `organization_id + operator_id` |

### 8.4 Cash network roles

| Role ID | Intended users | Typical surfaces | Required scope |
| --- | --- | --- | --- |
| `wallet.cash_agent` | branch and till agents | cash in/out surfaces | `organization_id + branch_id + cash_point_id` |
| `wallet.cash_supervisor` | branch supervisors | branch cash dashboards | `organization_id + branch_id` |
| `wallet.cash_finance` | partner backoffice finance | settlement and reconciliation | `organization_id` |

## 9. Permission Model
Roles are not enough by themselves. Roles must expand into fine-grained
permissions.

Permission naming should be namespaced and verb-oriented:

- `access.assignment.read`
- `access.assignment.write`
- `control.dashboard.read`
- `support.case.read`
- `support.case.resolve`
- `finance.journal.read`
- `finance.payout.write`
- `coach.catalog.read`
- `coach.operator.config.write`
- `coach.manifest.read`
- `coach.boarding.scan.write`
- `wallet.cash_txn.create`
- `wallet.cash_txn.approve`
- `audit.export.read`

Rules:
- Roles grant permissions.
- Scope narrows where the permission is valid.
- The BFF enforces both permission and scope.

## 10. Access Surfaces

### 10.1 Public or consumer surfaces
- `shamell.online`
- `online.shamell.online`
- consumer Shamell app

These remain consumer-facing and must not inherit workforce roles by accident.

### 10.2 Workforce and partner surfaces
Recommended dedicated hostnames:

- `control.shamell.online`
- `ops.shamell.online`
- `coach-operators.shamell.online`
- `crew.shamell.online`
- `cash.shamell.online`
- `audit.shamell.online`

One Access application per hostname is preferred over one giant shared portal.

Reason:
- simpler policy management
- simpler session management
- less blast radius
- clearer ownership

## 11. Login Policy

### 11.1 Internal and partner humans
Preferred primary factors:
- Passkeys
- TOTP as fallback

Allowed but weaker fallback:
- password plus TOTP during migration

Not acceptable for privileged production access:
- SMS-only admin login
- shared email inbox logins
- permanent dev bypasses

### 11.2 Break-glass owner account
Requirements:
- separate identity from the daily admin account
- hardware-backed MFA or passkey required
- short session
- no use for routine operations
- every use reviewed

### 11.3 Service accounts
Use service accounts for:
- deployment automation
- CI/CD
- scheduled reconciliation jobs
- future inter-service admin automation

Never use a human admin account in scripts.

## 12. Session and Step-Up Policy
Recommended session policy:

- `owner.break_glass`: 15 minutes
- `owner.daily_admin`: 8 hours
- `platform.security_admin`: 4 hours
- `platform.finance_admin`: 4 hours
- operator and agent users: 8 to 12 hours depending on device trust

Require step-up authentication for:
- role grants and revocations
- payout approval
- refund approval over threshold
- operator onboarding approval
- branch cash limit changes
- export of sensitive audit data

## 13. Audit Requirements
Every privileged write action must record:

- actor account id
- actor human id
- effective roles
- effective scopes
- target object
- action name
- reason code
- request id
- result
- timestamp
- before/after summary where possible

Minimum privileged events:
- login
- session exchange
- role assignment add/remove
- support override
- payout approval
- refund approval
- boarding override
- cash reconciliation override
- export generation

## 14. Cloudflare Access Policy Model
Cloudflare Access should be used as the coarse access gateway for web.

Per application, configure:
- allowed identities or groups
- required MFA
- session duration
- device posture where needed

Production requirement:
- the origin must validate `Cf-Access-Jwt-Assertion`
- client-supplied privileged headers must always be stripped
- `X-Auth-Roles` and `X-Role-Auth` should remain compatibility-only or local-dev
  mechanisms, not the long-term source of human identity

## 15. Shamell-Specific Decisions

### 15.1 Keep consumer auth separate
The public Shamell consumer app should continue to use the existing consumer
session model until workforce IAM is stable.

### 15.2 Introduce a workforce session exchange
The BFF should expose a dedicated workforce login exchange that:

- validates the external identity
- links or provisions the internal workforce account
- resolves role assignments and scope assignments
- creates a Shamell session compatible with existing privileged surfaces

### 15.3 Replace coarse role strings over time
Current coarse roles such as:
- `ops`
- `seller`
- `admin`
- `operator_*`

must be migrated to explicit namespaced roles and scope-aware permissions.

## 16. Immediate Outcome Expected From This Architecture
After implementation:

- you as owner can reach everything, but through controlled identities
- employees get only the access they actually need
- each bus operator sees only its own data
- each cash agent sees only the assigned scope
- every dashboard can be protected consistently
- every privileged action becomes attributable and auditable

