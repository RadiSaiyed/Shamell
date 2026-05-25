import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/plugin_visibility_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('plugin visibility stays isolated across canonical API origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.alpha.example',
    });

    await saveScopedPluginVisibilityPreference(
      key: 'shamell.plugins.show_scan',
      value: false,
    );
    expect(
      await loadScopedPluginVisibilityPreference(
        key: 'shamell.plugins.show_scan',
        fallback: true,
      ),
      isFalse,
    );

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.beta.example');
    expect(
      await loadScopedPluginVisibilityPreference(
        key: 'shamell.plugins.show_scan',
        fallback: true,
      ),
      isTrue,
    );

    await saveScopedPluginVisibilityPreference(
      key: 'shamell.plugins.show_scan',
      value: true,
    );

    await sp.setString('base_url', 'https://api.alpha.example');
    expect(
      await loadScopedPluginVisibilityPreference(
        key: 'shamell.plugins.show_scan',
        fallback: true,
      ),
      isFalse,
    );
  });

  test('legacy global plugin visibility migrates only in unknown scope',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'shamell.plugins.show_scan': false,
    });

    expect(
      await loadScopedPluginVisibilityPreference(
        key: 'shamell.plugins.show_scan',
        fallback: true,
      ),
      isFalse,
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('shamell.plugins.show_scan'), isNull);
    expect(
      sp.getBool(
        'plugin_visibility.v2.shamell.plugins.show_scan@unknown',
      ),
      isFalse,
    );
  });

  test('legacy global plugin visibility does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'shamell.plugins.show_scan': false,
    });

    expect(
      await loadScopedPluginVisibilityPreference(
        key: 'shamell.plugins.show_scan',
        fallback: true,
      ),
      isTrue,
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('shamell.plugins.show_scan'), isNull);
    expect(
      sp.getBool(
        'plugin_visibility.v2.shamell.plugins.show_scan@https://api.example.com',
      ),
      isNull,
    );
  });
}
