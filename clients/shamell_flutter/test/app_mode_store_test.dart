import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stored app mode stays isolated across canonical API origins', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.alpha.example',
    });

    await saveStoredAppModePreference(AppMode.admin);
    expect(await loadStoredAppModePreference(), AppMode.admin);

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.beta.example');
    expect(await loadStoredAppModePreference(), isNull);

    await saveStoredAppModePreference(AppMode.operator);
    expect(await loadStoredAppModePreference(), AppMode.operator);

    await sp.setString('base_url', 'https://api.alpha.example');
    expect(await loadStoredAppModePreference(), AppMode.admin);
  });

  test('legacy global app mode migrates only in unknown scope', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_mode': 'operator',
    });

    expect(await loadStoredAppModePreference(), AppMode.operator);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('app_mode'), isNull);
    expect(sp.getString('app_mode.v2.unknown'), 'operator');
  });

  test('legacy global app mode does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'app_mode': 'admin',
    });

    expect(await loadStoredAppModePreference(), isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('app_mode'), isNull);
    expect(sp.getString('app_mode.v2.https://api.example.com'), isNull);
  });
}
