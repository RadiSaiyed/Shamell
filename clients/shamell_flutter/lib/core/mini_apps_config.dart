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

List<MiniAppDescriptor> visibleMiniApps() {
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
    return true;
  }).toList();
}
