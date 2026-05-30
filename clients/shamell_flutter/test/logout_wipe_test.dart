import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/logout_wipe.dart';
import 'package:shamell_flutter/core/shamell_user_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wipeLocalAccountData preserves device prefs but wipes Shamell-ID',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      kStableDeviceIdPrefKey: 'stable123',
      // Valid 8-char Shamell-ID.
      kShamellUserIdPrefKey: 'ABCDEFGH',
      'wallet_id': 'w1',
      'roles': <String>['admin'],
    });

    await wipeLocalAccountData(preserveDevicePrefs: true);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('base_url'), 'https://api.example.com');
    expect(sp.getString(kStableDeviceIdPrefKey), 'stable123');

    // Account-scoped identifier must not survive logout.
    expect(sp.getString(kShamellUserIdPrefKey), isNull);

    // Account/session scoped prefs should be wiped.
    expect(sp.getString('wallet_id'), isNull);
    expect(sp.getStringList('roles'), isNull);
  });
}

