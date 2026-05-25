import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/mini_app_registry.dart';
import 'package:shamell_flutter/core/mini_apps_config.dart';

/// Pins the operator-only mini-app contract:
///   * `MiniAppRegistry.descriptors` (single source of truth) still
///     contains the operator surface, so `byId` lookups + deep-link
///     routing keep working for an authenticated operator client.
///   * `visibleMiniApps()` — the consumer-facing filter used by the
///     Discover directory and recent-modules chips — must EXCLUDE
///     operator-only descriptors so a consumer user never even sees
///     the tile.
void main() {
  group('operator-only mini-app visibility', () {
    test('hotels_admin is registered in the runtime registry', () {
      // Routing path: a partner deep-link that hits the runtime
      // resolver must still resolve to the admin app.
      expect(MiniAppRegistry.byId('hotels_admin'), isNotNull,
          reason: 'operator deep-links must keep resolving');
    });

    test('hotels_admin descriptor exists and is flagged operatorOnly', () {
      final descriptor = MiniAppRegistry.descriptors
          .firstWhere((d) => d.id == 'hotels_admin');
      expect(descriptor.operatorOnly, isTrue,
          reason: 'hotels_admin must be marked operator-only');
    });

    test('hotels_admin is hidden from the consumer Discover surface', () {
      final visible = visibleMiniApps();
      expect(
        visible.any((d) => d.id == 'hotels_admin'),
        isFalse,
        reason:
            'consumer Discover must not surface the operator admin tile',
      );
    });

    test('regular consumer mini-apps stay visible', () {
      // Smoke check: the filter must not over-shoot and hide
      // legitimate consumer surfaces.
      final visible = visibleMiniApps();
      expect(visible.any((d) => d.id == 'hotels'), isTrue,
          reason: 'public Hotels tile must stay visible');
      expect(visible.any((d) => d.id == 'payments'), isTrue,
          reason: 'public Payments tile must stay visible');
    });
  });
}
