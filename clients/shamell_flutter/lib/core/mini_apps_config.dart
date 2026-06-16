import 'mini_app_descriptor.dart';
import 'mini_app_registry.dart';

export 'mini_app_descriptor.dart';

/// Global mini-app registry for the enduser Shamell app.
///
/// Shamell‑style: this list is derived from the single MiniAppRegistry
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
    return true;
  }).toList();
}
