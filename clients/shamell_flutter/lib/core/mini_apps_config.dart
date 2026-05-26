import 'mini_app_descriptor.dart';
import 'mini_app_registry.dart';

export 'mini_app_descriptor.dart';

/// Global mini-app registry for the enduser SyrChat app.
///
/// SyrChat Super-App: this list is derived from the single MiniAppRegistry
/// source of truth.
List<MiniAppDescriptor> get kMiniApps => MiniAppRegistry.descriptors;

MiniAppDescriptor? miniAppById(String id) {
  for (final m in kMiniApps) {
    if (m.id == id && m.enabled) return m;
  }
  return null;
}

// Feature flags for visibility of partner/beta mini-apps in the
// enduser build. These can be tightened in hardened builds by
// flipping the booleans or using compile-time environment values.
const bool kMiniAppsShowPartner = true;
const bool kMiniAppsShowBeta =
    bool.fromEnvironment('MINIAPPS_SHOW_BETA', defaultValue: false);

/// Returns mini-apps visible in consumer-facing surfaces.
///
/// [includeGaming] — set to `true` only for surfaces that explicitly
/// curate the Gaming category (the Discover "Gaming" tile opens the
/// directory with this flag, and global search uses it so the user can
/// search for games by name). Default `false` keeps games out of the
/// generic Mini Programs hub / quick-shelf / directory listing — games
/// have their own discovery surface and shouldn't dilute the regular
/// services grid.
List<MiniAppDescriptor> visibleMiniApps({bool includeGaming = false}) {
  return kMiniApps.where((m) {
    if (!m.enabled) return false;
    if (!kMiniAppsShowPartner && !m.official) return false;
    if (!kMiniAppsShowBeta && m.beta) return false;
    // Operator-side surfaces (e.g. hotel-staff admin console) must
    // not surface in the consumer Discover directory. The runtime
    // still resolves them via MiniAppRegistry.byId, so deep-link
    // routing for an authenticated operator client continues to
    // work — only the consumer tile-grid hides them.
    if (m.operatorOnly) return false;
    // Gaming category is gated to its own surface (the Discover
    // "Gaming" tile / directory filtered by category=='Gaming').
    // Callers that genuinely want to enumerate games pass
    // `includeGaming: true`.
    if (!includeGaming && m.categoryEn == 'Gaming') return false;
    return true;
  }).toList();
}
