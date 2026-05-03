# Frontend Feature Crawl (2026-03-06)

## Scope
- Client examined: `clients/shamell_flutter/lib` (home shell, chat, payments, official-owner, settings, ops, v2).
- Runtime/API validation used during crawl:
  - `./scripts/ops.sh pipg health`
  - `./scripts/ops.sh pipg smoke-api`
  - `./scripts/ops.sh pipg smoke-mailbox`
  - `./scripts/ops.sh pipg matrix-api` (15/15 PASS)

## Findings (current after quick fixes)

### 1) Closed in this pass: removed consumer surfaces were still reachable behind dead-end pages
- Current status:
  - Legacy removed widgets/files were deleted:
    - `clients/shamell_flutter/lib/core/official_accounts_page.dart`
    - `clients/shamell_flutter/lib/core/moments_page.dart`
    - `clients/shamell_flutter/lib/core/channels_page.dart`
  - `main_home` paths now dispatch removed-state snackbars directly (official/moments/channels) instead of pushing removed pages.
- Impact: dead-end page routes are no longer part of the active app graph.

### 2) Medium: Capability contract and UI surface are out of sync
- Evidence:
  - Moments is hard-disabled in capabilities (`_kMomentsForcedOff=false`) at `clients/shamell_flutter/lib/core/capabilities.dart:64` and applied in defaults/compose at `clients/shamell_flutter/lib/core/capabilities.dart:41`.
  - Service modules are hard-disabled and now routed to unified removed-state snackbars (no page push):
    - capabilities: `clients/shamell_flutter/lib/core/capabilities.dart:65`
    - removed-state messaging: `clients/shamell_flutter/lib/core/removed_modules_nav.dart`
- Impact: backend routes can be healthy while frontend remains permanently unavailable for those domains.

### 3) Medium: Ops/Operator UI still mounted but effectively in removed-mode
- Evidence:
  - Operator dead-end entries were removed/redirected (no dedicated removed-only operator dashboard entry in Home/Superadmin tiles).
  - `ModuleHealthPage` still exists as legacy stub fallback at `clients/shamell_flutter/lib/src/main_ops.dart`.
- Impact: admin/operator entry points are present but limited; this can confuse role-based users.

### 4) Medium: Test coverage gap for currently active owner/admin screens
- Evidence:
  - Existing tests cover utilities/hardening/widgets. `HomeRouteGrid` routing
    now has dedicated coverage in `clients/shamell_flutter/test/home_route_grid_test.dart`.
  - Remaining active owner/admin pages still have no direct widget coverage:
    - `OfficialOwnerConsolePage`
    - `OfficialOwnersAccessPage`
    - `OfficialServiceInboxPage`
  - Confirmed by grep over `clients/shamell_flutter/test` (no direct page-level matches for those three classes).
- Impact: regressions in owner/admin flows are unlikely to be caught early.

## What is currently working (validated)
- API runtime checks are green (`health`, `smoke-api`, `smoke-mailbox`, `matrix-api` all PASS).
- Rust backend tests pass for BFF/chat/payments/bus.
- Selected Flutter tests pass (journey/more/payments widgets, owner input validation, payments utils).

## Applied in this pass
1. Owner console dead-end buttons removed (feed/channels/moments links that targeted removed pages).
2. Home `Wallet` quick action remapped from `HistoryPage` to `PaymentsPage(initialSection: 'overview')`.
3. Official deep-link handlers changed to explicit availability snackbar instead of navigating to removed pages.
4. Added `home_route_grid_test.dart` to lock quick-action callback wiring and finance hub wallet/history routing.
5. Extracted official/moments deep-link parsing into `core/deep_link_parsing.dart` with unit coverage in `test/deep_link_parsing_test.dart`.
6. Added deep-link resolution tests for capability-gated fallback (`unavailable`) vs open-target behavior.
7. Added injectable `httpClient` + `sessionCookieProvider` seams to owner/admin pages, with API-flow widget tests in `test/official_owner_admin_pages_test.dart`.
8. Expanded owner/admin widget coverage to interaction flows (add owner, remove owner, close session, send template message).
9. Added deep-link dispatch helpers (`dispatchOfficialDeepLink`, `dispatchMomentsDeepLink`) and dispatch-level tests in `test/deep_link_handler_dispatch_test.dart`.
10. Added `HomePage` deep-link widget tests in `test/home_deep_link_widget_test.dart` to assert snackbar fallback and navigation behavior.
11. Added a central navigation guard in `main_home` (`_navPushGuarded`) to keep auth-gated navigation consistent for active guarded surfaces.
12. Closed remaining non-`HomePage` entry points by routing chat/contact/admin/bootstrap navigations for removed official/moments/channels surfaces to unified removed-state snackbars.
13. Added focused widget coverage for chat/contact/admin removed-entry snackbar behavior in `test/removed_entrypoints_widgets_test.dart`.
14. Physically deleted removed page widgets/files for official accounts, moments, and channels, and migrated `main_home` call sites to direct removed-surface snackbar dispatch.
15. Extracted `OfficialAccountHandle` into `core/official_account_models.dart` so active data flows remain decoupled from removed page widgets.
16. Trimmed removed-module compatibility dead paths:
    - removed unused `ModuleAppRegistry` wrapper and unused `ModuleAppDescriptor` category/entry helpers in `core/removed_modules_compat.dart`
    - removed unreachable `ModuleAppRegistry.byId(...).entry(...)` branch from `_openMod` in `main_home`
17. Cut over remaining service-module navigation surfaces to removed-state snackbars:
    - replaced `ServiceModulePage` / `ServiceModulesDiscoverPage` / `MyServiceModulesPage` / `ServiceModulesReviewPage` navigations across `main_home`, `main_shamell`, `main_ops`, chat, and group chat
    - deleted those removed compat page classes from `core/removed_modules_compat.dart`
    - extended `RemovedModuleSurface` with `serviceModules` and added widget assertions for the new removed-state message
18. Removed remaining service-module metadata compatibility helpers:
    - deleted `moduleAppById`, `visibleModuleApps`, and `ModuleAppDescriptor` from `core/removed_modules_compat.dart`
    - migrated chat/home/template-message call sites to id-based icon/label fallbacks and unified removed-state snackbar behavior
19. Reduced Ops/Operator dead-end surfaces:
    - removed `Mini‑program review` tile from `OpsPage`
    - removed legacy `OperatorDashboardPage` and routed Home operator-console entry to active `OpsPage`
    - hid removed-only `My mini‑programs` developer entry from Shamell account sheet and Home mini-program dev center
20. Hid remaining user-facing mini-program entry points in chat/group/settings surfaces:
    - removed mini-program actions from chat “Add” menu, chat composer “More” panel, and group-chat “More” panel
    - removed standalone mini-program tile/chips from the Shamell chat tab
    - removed mini-program guidance/toggle rows from Shamell settings pages
21. Removed dormant chat pull-down service-module internals that no longer had a visible surface:
    - deleted hidden pull-down mini-program state, badge tracking, and pinned/recents action handlers from `shamell_chat_page.dart`
    - simplified the chats pull-down panel to archived-chats only while keeping global search and removed-state entry behavior unchanged
22. Removed dormant service-module state/telemetry plumbing from Home + Settings:
    - deleted unused `ShamellSettingsPage` service-module constructor fields (`count/usage/moments30d`) and unused `onOpenMod` dependency
    - removed Home’s service-module trending/badge/stats fetch paths and persisted badge bookkeeping (`service_modules.*seen*` / `trending_seen_sig`)
    - simplified Home discover/service-module guards to capability-only and kept removed-surface fallback behavior
23. Removed final visible service-module UI remnants from Home:
    - deleted service-module tiles/chips from Discover strict mode, Discover classic list, and Me tab overview blocks
    - removed Home-only pinned/recent mini-program preview strips and related dead helper methods
    - kept scan/deeplink fallback handling in `_openMod` temporarily (removed in follow-up item 24)
24. Removed legacy service-module scan/deeplink compatibility in Home routing:
    - dropped dedicated URI host handling for `shamell://service_module` / `shamell://service_modules`
    - dropped scan-prefix handling for `SERVICEMODULE|` / `SERVICE_MODULE|`
    - simplified `_openMod` fallback so non-native module shortcuts now show an unsupported-shortcut snackbar instead of removed-surface service-module messaging
25. Removed dead service-module capability plumbing:
    - deleted the unused `serviceModules` field from `ShamellCapabilities` and updated callsites/tests
    - removed unused `_kShamellPluginShowServiceModules` constant from `main_bootstrap`
26. Removed stale removed-surface variant for service-modules:
    - deleted `RemovedModuleSurface.serviceModules` and replaced its callsites with generic unsupported-shortcut snackbar handling
    - updated home/deep-link and removed-entry widget tests to stop asserting the retired enum/message path
27. Retired last `removed_modules_compat.dart` dependency:
    - moved the remaining `ServiceModuleInsightChip` UI helper into `official_owner_console_page.dart` as a local private widget
    - deleted `core/removed_modules_compat.dart` entirely (no runtime references remain)
28. Removed dead Ops legacy health stub:
    - deleted unreferenced `ModuleHealthPage` from `main_ops.dart` after confirming zero callsites
    - revalidated affected Ops/Owner widget suites (`more_widgets_test.dart`, `official_owner_admin_pages_test.dart`)
29. Removed dead mini-program localization leftovers:
    - deleted unused `moduleApps*` getters from `core/l10n.dart` (`moduleAppsTitle`, search/recent/all labels, and badge labels)
    - revalidated localization/widget coverage (`journey_widgets_test.dart`, `more_widgets_test.dart`)
30. Updated remaining user-facing copy to remove mini-app terminology:
    - changed scan subtitle text in `core/l10n.dart` from “mini-apps” to Web-login + payments only
    - updated Home Me-tab search subtitle in `main_home.dart` to “services and official accounts”
31. Aligned Moments/Channels user copy with removed-state behavior:
    - updated Home + Chat labels/subtitles that still advertised Moments/Channels capabilities while routing to removed-state snackbars
    - simplified Home “My Channels” entry to direct removed-state handling (removed stale default-account precheck messaging)
    - updated Owner Console + owner comments page labels from Moments/Channels wording to neutral content/publishing terminology
    - updated `l10n` Moments subtitle to explicit unavailable-state wording and removed unused `shamellMomentsAudienceHint`
32. Forced Channels capability to fail-closed:
    - `ShamellCapabilities` now hard-disables `channels` during compose/merge/read and persists `cap.channels=false` for compatibility
    - updated capability scoping tests to assert that scoped/global channels flags are ignored
33. Removed dead Moments/Channels UI branches from Home/Chat:
    - deleted removed-state-only `_caps.channels` and `_caps.moments` tile/chip branches in `main_home.dart` and `_buildChannelTab` in `shamell_chat_page.dart`
    - removed now-unused Home trending-topics loader/state and unused strict-UI badge helper introduced by branch removal
34. Removed remaining Moments background/badge plumbing from Home:
    - deleted Home’s moments notifications/stats fetch paths (`/moments/notifications`, `/me/official_moments_stats`) and related state fields
    - removed Moments unread contribution from Discover tab badge and simplified official-account subtitle/chip decorations that depended on moments-derived stats
35. Removed stale Channels plugin toggle:
    - deleted Channels toggle state/UI from `ShamellPluginsPage` in `main_shamell.dart`
    - removed now-unused `_kShamellPluginShowChannels` preference key constant from `main_bootstrap.dart`
36. Simplified Home Moments deep-link path to one central handler:
    - replaced the `dispatchMomentsDeepLink` callback path in `main_home.dart` with a single local `_handleMomentsDeepLink` branch
    - kept effective UX unchanged: capability-off shows server-unavailable snackbar; capability-on still routes to removed-surface snackbar
37. Removed dead Moments deep-link parsing utilities:
    - deleted unused `parse/resolve/dispatch` Moments helpers from `core/deep_link_parsing.dart` after runtime callsites were removed
    - trimmed dispatch/parsing unit tests to official-link coverage only and kept Home widget tests as the remaining Moments deep-link behavior guard
38. Reduced deep-link parsing API to official-only minimal surface:
    - removed `resolveOfficialDeepLink` + `DeepLinkDecision` abstraction and inlined parse/capability logic into `dispatchOfficialDeepLink`
    - updated parsing tests to validate `parseOfficialDeepLink` while dispatch behavior remains covered in `deep_link_handler_dispatch_test.dart`
39. Hid removed-only Official Account directory surfaces in Ops/Admin modes:
    - introduced `_showOfficialDirectoryEntrypoints` guard in `main_home.dart` (`_caps.officialAccounts && _appMode == AppMode.user`)
    - gated Contacts/Services/Me Official-directory entry points and previews behind user mode so operator/admin paths no longer expose taps that only show removed-state snackbars
40. Removed remaining removed-only global Search/Media entry points from Home:
    - deleted AppBar search action (Services tab), Contacts-tab search bar tap, Services search rows/chips, and Me-tab search row that all routed to removed-state snackbars
    - removed the Me-tab global media/files row and its dead `_openGlobalMedia` handler, keeping only wallet history as an active entry
    - deleted dead `_openGlobalSearch` / `_openGlobalMedia` helpers in `main_home.dart`
41. Disabled all remaining removed-only Official-directory UI entry points (including user mode):
    - changed `main_home.dart` guard `_showOfficialDirectoryEntrypoints` to fail-closed (`false`) so no Official-directory placeholder tiles/chips/buttons render anywhere
    - retained deep-link removed-state handlers for official routes as a non-UI safety fallback
42. Removed dead Official-directory scaffolding from Home after UI hide:
    - deleted all hidden Official-directory widget blocks (Contacts/Services/Me) and related removed-state `Perf.action(...)` hooks
    - removed Home-only Official directory loading/state plumbing (`_loadOfficialStrip`, `_openOfficialFromStrip`, strip/followed/latest counters, unread recompute helper)
    - simplified unread indicators to service-notification unread only and kept subscription entry points active without Official-directory dependency
    - removed now-unused `_MiniOfficialUpdate` type from `main_bootstrap.dart`
43. Switched Official deep links to unsupported-shortcut behavior:
    - changed `_openOfficialDeepLink` / `_openOfficialItemDeepLink` in `main_home.dart` to route through `_openMod('official')`
    - this aligns official deep links with the generic unsupported module shortcut snackbar instead of removed-surface official messaging
    - updated `home_deep_link_widget_test.dart` expectation to assert unsupported-shortcut copy when official capability is enabled
44. Hid remaining Home/Me subscriptions feed entry points:
    - removed Discover subscriptions promo chip from Home services tab
    - removed Me-tab “View subscription updates” tile and its chat deeplink push to `__official_subscriptions__`
    - removed related `Perf.action(...)` hooks and `_caps.subscriptions` UI guards from `main_home.dart`
45. Reduced stale capability gating in Home startup loads:
    - removed redundant `officialAccounts` gate from `_loadDefaultOfficialAccountFlag` and now refresh this flag unconditionally in `_kickOffCapabilityLoads`
    - kept `officialAccounts` capability checks only where they still control visible UI/deeplink behavior (owner/admin pages, notifications, and official-link availability)
46. Removed `subscriptions` from capability model and re-bound chat gating:
    - deleted `subscriptions` field/key/plumbing from `ShamellCapabilities` (`core/capabilities.dart`) including compose/merge/persist/read paths
    - updated remaining chat-side subscriptions guards in `shamell_chat_page.dart` to use `serviceNotifications` capability instead
    - updated capability construction in affected widget/unit tests (`capabilities_scoping_test.dart`, `home_deep_link_widget_test.dart`)
47. Fully removed chat-side Subscriptions system thread implementation:
    - deleted `__official_subscriptions__` special-peer flow from `shamell_chat_page.dart` (open/switch/draft exclusions/forward-filter handling)
    - removed Subscriptions system-thread UI/state/actions in chats list (swipe tile, read/delete toggles, "Subscriptions only" filter chip/switch, and empty-state branch)
    - removed Subscriptions feed-only chat card implementation and related persistence flags (`chat.hide_subscriptions_thread`, `official.subscriptions_force_unread`)
    - preserved official-feed unread detection for real official peers and existing non-thread subscription entry points
48. Removed dead Subscriptions feed localization strings:
    - deleted unused Subscriptions feed/card L10n getters from `core/l10n.dart` (`shamellSubscriptionsFeed*`, `shamellSubscriptionsTitle`, `shamellSubscriptionsEmpty`, filter labels, mark-all-read label)
    - kept still-used Discover/Channels subscription-account labels (`shamellChannelSubscriptionAccountsTitle`, `shamellChannelSubscriptionAccountsSubtitle`)
49. Removed remaining Discover subscription-accounts placeholder tile and state:
    - deleted the removed-only Subscription Accounts list tile from `shamell_chat_page.dart` Discover/Channels section
    - removed now-unused `_hasUnreadSubscriptionFeeds` chat state and simplified `_loadOfficialPeers` unread handling to generic official unread feeds
    - removed now-unused L10n keys `shamellChannelSubscriptionAccountsTitle` / `shamellChannelSubscriptionAccountsSubtitle` from `core/l10n.dart`
50. Renamed stale subscription analytics event ID for Favorites entry:
    - updated chat Discover/Channels favorites tile `Perf.action(...)` from `official_open_directory_from_chats_subscription_tile` to `official_open_directory_from_chats_favorites_tile`
    - keeps analytics naming aligned with current UI semantics after subscription-tile removal
51. Generalized remaining Discover copy away from subscription wording:
    - updated chat Discover service-accounts subtitle text in `shamell_chat_page.dart` from "service and subscription accounts" phrasing to generic official-service account phrasing (Arabic + English)
    - aligns user-facing Discover copy with removed subscription-specific tiles
52. Generalized Home official-notification copy and analytics naming:
    - updated official-notifications sheet/user-copy in `main_home.dart` from "service and subscription accounts" wording to generic official-account wording
    - renamed non-service notification analytics event IDs from `official_notifications_subscription_*` to `official_notifications_nonservice_*`
    - kept behavior unchanged by still applying the second group to non-service official accounts
53. Standardized follow/unfollow account-kind analytics taxonomy:
    - updated chat follow/unfollow kind suffix in `shamell_chat_page.dart` from `subscription` to `nonservice`
    - resulting events now emit `official_follow_kind_nonservice` / `official_unfollow_kind_nonservice` for non-service official accounts
54. Added temporary dual-write for renamed analytics keys:
    - in `main_home.dart`, non-service notification mode actions now emit both new keys (`official_notifications_nonservice_*`) and legacy keys (`official_notifications_subscription_*`)
    - in `shamell_chat_page.dart`, non-service follow/unfollow now emits both new keys (`official_*_kind_nonservice`) and legacy keys (`official_*_kind_subscription`)
    - this preserves dashboard/backfill compatibility while migration to the new taxonomy is in progress
55. Added a hard cutoff date for legacy analytics dual-write:
    - introduced UTC cutoff gate `2026-07-01` in both `main_home.dart` and `shamell_chat_page.dart`
    - legacy `subscription` analytics keys are now emitted only before `2026-07-01T00:00:00Z`; after that, only `nonservice` keys are emitted
56. Centralized analytics migration cutoff logic and added tests:
    - added shared utility `core/analytics_migration.dart` with cutoff constant + helper (`shouldEmitLegacySubscriptionAnalytics`)
    - switched `main_home.dart` and `shamell_chat_page.dart` to use the shared helper instead of duplicated per-class date gates
    - added `test/analytics_migration_test.dart` to lock cutoff behavior before/at/after `2026-07-01` UTC
57. Centralized non-service analytics event mapping in migration utility:
    - moved non-service notification/follow event-key mapping (new + legacy) into `core/analytics_migration.dart`
    - updated `main_home.dart` and `shamell_chat_page.dart` to emit events from shared utility lists instead of duplicating key switch/case logic
    - extended `analytics_migration_test.dart` with dual-write event-list assertions before and at cutoff
58. Replaced stringly-typed notification grouping with enum in Home notifications sheet:
    - introduced `_OfficialNotifGroup` in `main_home.dart` and updated `applyGroupMode` to accept enum values instead of raw strings
    - migrated service/non-service callsites to enum usage to avoid accidental string drift/regressions
59. Typed non-service notification-mode analytics mapping:
    - replaced string mode keys (`'full'/'summary'/'muted'`) with `AnalyticsNotifMode` enum in `core/analytics_migration.dart`
    - updated `main_home.dart` and `analytics_migration_test.dart` to use the enum-based API
60. Centralized service analytics keys and typed follow-action semantics:
    - added `AnalyticsFollowAction` enum in `core/analytics_migration.dart` and switched non-service follow helper from ambiguous `currentlyFollowed` bool to explicit action enum
    - added shared service event helpers (`serviceNotificationModeEvent`, `serviceFollowKindEvent`) so service/non-service analytics keys are now emitted via one utility
    - updated `main_home.dart` and `shamell_chat_page.dart` callsites accordingly, and expanded `analytics_migration_test.dart` with stable-key assertions for service events
61. Unified official-analytics emission paths across service/non-service groups:
    - added shared group enum `AnalyticsOfficialGroup` plus helper APIs (`notificationModeEvents`, `followKindEvents`) in `core/analytics_migration.dart`
    - migrated Home notification-mode analytics and Chat follow-kind analytics to the unified helpers, removing callsite-specific service/non-service branching for emitted keys
    - expanded `analytics_migration_test.dart` with service-group assertions on the unified APIs to prevent future dual-write regressions on service events
62. Reduced migration utility surface to one official event API:
    - made non-service/internal mapping helpers private in `core/analytics_migration.dart` and removed now-redundant public single-group helpers
    - updated `analytics_migration_test.dart` to assert both service and non-service behavior through unified entrypoints (`notificationModeEvents`, `followKindEvents`) only
    - this hardens the typed facade and prevents future callsites from bypassing group-aware migration logic
63. Removed duplicate group enum in Home notification flow:
    - replaced `_OfficialNotifGroup` in `main_home.dart` with shared `AnalyticsOfficialGroup` from `core/analytics_migration.dart`
    - updated `applyGroupMode` signature and callsites to use the shared enum, so group typing now stays consistent between state-update logic and analytics emission

## Recommended next fixes
1. After `2026-07-01`, simplify migration utility outputs to new keys only and remove legacy event constants/tests.
