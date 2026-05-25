import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/privacy_preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  var throwOnSecureRead = false;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = (args['value'] ?? '').toString();
            return null;
          case 'read':
            if (throwOnSecureRead) {
              throw PlatformException(
                code: 'secure-read-failed',
                message: 'simulated secure storage read failure',
              );
            }
            return secStore[key];
          case 'delete':
            secStore.remove(key);
            return null;
          case 'deleteAll':
            secStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secStore);
          case 'containsKey':
            return secStore.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    throwOnSecureRead = false;
    await clearPrivacyPreferenceState();
  });

  test(
      'active privacy preferences ignore legacy SharedPreferences when secure storage is readable and fallback is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kPrivacyFriendVerificationPrefKey: false,
    });

    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isTrue,
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool(kPrivacyFriendVerificationPrefKey), isNull);
    expect(secStore, isEmpty);
  });

  test(
      'active privacy preferences allow legacy SharedPreferences when secure storage read fails',
      () async {
    throwOnSecureRead = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      kPrivacyFriendVerificationPrefKey: false,
    });

    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isFalse,
    );
  });

  test('privacy preferences are isolated per canonical api origin', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await savePrivacyPreferenceValue(
        kPrivacyFriendVerificationPrefKey,
        false,
      ),
      isTrue,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isTrue,
    );
    expect(
      await savePrivacyPreferenceValue(
        kPrivacyFriendVerificationPrefKey,
        true,
      ),
      isTrue,
    );

    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isFalse,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isTrue,
    );
  });

  test('privacy preferences honor explicit baseUrl override scope', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');

    expect(
      await savePrivacyPreferenceValue(
        kPrivacyFriendVerificationPrefKey,
        false,
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );

    expect(
      await loadPrivacyPreferenceValue(
        kPrivacyFriendVerificationPrefKey,
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isFalse,
    );
    expect(
      await loadPrivacyPreferenceValue(
        kPrivacyFriendVerificationPrefKey,
        sp: sp,
      ),
      isTrue,
    );
  });

  test(
      'legacy global privacy preferences do not rebind into canonical api origin',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      kPrivacyFriendVerificationPrefKey: false,
    });

    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isTrue,
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool(kPrivacyFriendVerificationPrefKey), isNull);
  });

  test('privacy preferences save and clear through secure storage', () async {
    expect(
      await savePrivacyPreferenceValue(
          kPrivacyFriendVerificationPrefKey, false),
      isTrue,
    );

    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isFalse,
    );

    await clearPrivacyPreferenceState();
    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isTrue,
    );
  });

  test('clearPrivacyPreferenceState removes scoped values across all origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await savePrivacyPreferenceValue(
        kPrivacyFriendVerificationPrefKey,
        false,
      ),
      isTrue,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await savePrivacyPreferenceValue(
        kPrivacyFriendVerificationPrefKey,
        false,
      ),
      isTrue,
    );

    await clearPrivacyPreferenceState(sp: sp);

    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isTrue,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await loadPrivacyPreferenceValue(kPrivacyFriendVerificationPrefKey),
      isTrue,
    );
  });

  test(
      'clearPrivacyPreferenceState removes deprecated add-me and moments compatibility keys',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'shamell.privacy.search_by_id': false,
      'shamell.privacy.add_me.by_id': false,
      'shamell.privacy.add_me.by_qr': false,
      kPrivacyMomentsAllowStrangersTenPostsPrefKey: false,
      kPrivacyMomentsUpdateRemindersPrefKey: false,
      kPrivacyStatusVisibleToOthersPrefKey: false,
      'privacy.add_me.by_id.v2.scope': false,
      'privacy.add_me.by_qr.v2.scope': false,
      'privacy.moments.allow_strangers_ten_posts.v2.scope': false,
      'privacy.moments.update_reminders.v2.scope': false,
      'privacy.status.visible_to_others.v2.scope': false,
    });
    secStore['privacy.add_me.by_id.v1'] = '1';
    secStore['privacy.add_me.by_qr.v2.scope'] = '0';
    secStore['privacy.moments.allow_strangers_ten_posts.v1'] = '1';
    secStore['privacy.status.visible_to_others.v2.scope'] = '0';

    final sp = await SharedPreferences.getInstance();
    await clearPrivacyPreferenceState(sp: sp);

    expect(sp.getBool('shamell.privacy.search_by_id'), isNull);
    expect(sp.getBool('shamell.privacy.add_me.by_id'), isNull);
    expect(sp.getBool('shamell.privacy.add_me.by_qr'), isNull);
    expect(sp.getBool(kPrivacyMomentsAllowStrangersTenPostsPrefKey), isNull);
    expect(sp.getBool(kPrivacyMomentsUpdateRemindersPrefKey), isNull);
    expect(sp.getBool(kPrivacyStatusVisibleToOthersPrefKey), isNull);
    expect(sp.getBool('privacy.add_me.by_id.v2.scope'), isNull);
    expect(sp.getBool('privacy.add_me.by_qr.v2.scope'), isNull);
    expect(sp.getBool('privacy.moments.allow_strangers_ten_posts.v2.scope'),
        isNull);
    expect(sp.getBool('privacy.moments.update_reminders.v2.scope'), isNull);
    expect(sp.getBool('privacy.status.visible_to_others.v2.scope'), isNull);
    expect(secStore.containsKey('privacy.add_me.by_id.v1'), isFalse);
    expect(secStore.containsKey('privacy.add_me.by_qr.v2.scope'), isFalse);
    expect(
      secStore.containsKey('privacy.moments.allow_strangers_ten_posts.v1'),
      isFalse,
    );
    expect(secStore.containsKey('privacy.status.visible_to_others.v2.scope'),
        isFalse);
  });
}
