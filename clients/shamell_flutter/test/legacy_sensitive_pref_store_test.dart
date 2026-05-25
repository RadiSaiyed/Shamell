import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/legacy_sensitive_pref_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  var throwOnSecureRead = false;

  String scopedLegacySensitiveKey(String prefix, String scope) {
    final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return '$prefix$suffix';
  }

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
    await clearLegacySensitivePrefState();
  });

  test(
      'legacy sensitive prefs are ignored from SharedPreferences when secure storage is readable and fallback is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'last_login_name': 'Alice',
      'last_login_phone': '+1234567',
      'official.default_account_id': 'official-1',
      'official.default_account_name': 'Ops Console',
      'contact_shortlist': <String>[
        '{"name":"Bob","phone":"+222"}',
        '+333',
      ],
    });

    final profile = await loadLegacyProfileSummary();
    final official = await loadLegacyDefaultOfficialAccountContext();
    final shortlist = await loadLegacyContactShortlistEntries();
    final sp = await SharedPreferences.getInstance();

    expect(profile.name, isEmpty);
    expect(profile.phone, isEmpty);
    expect(official.accountId, isEmpty);
    expect(official.accountName, isEmpty);
    expect(shortlist, isEmpty);
    expect(sp.getString('last_login_name'), isNull);
    expect(sp.getString('last_login_phone'), isNull);
    expect(sp.getString('official.default_account_id'), isNull);
    expect(sp.getString('official.default_account_name'), isNull);
    expect(sp.getStringList('contact_shortlist'), isNull);
    expect(secStore, isEmpty);
  });

  test(
      'legacy sensitive prefs are allowed from SharedPreferences when secure storage read fails',
      () async {
    throwOnSecureRead = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'last_login_name': 'Alice',
      'last_login_phone': '+1234567',
      'official.default_account_id': 'official-1',
      'official.default_account_name': 'Ops Console',
      'contact_shortlist': <String>['+333'],
    });

    expect((await loadLegacyProfileSummary()).name, 'Alice');
    expect((await loadLegacyProfileSummary()).phone, '+1234567');
    expect(
      (await loadLegacyDefaultOfficialAccountContext()).accountId,
      'official-1',
    );
    expect(await loadLegacyContactShortlistEntries(), <String>['+333']);
  });

  test('legacy sensitive prefs reload from secure storage and clear', () async {
    secStore[scopedLegacySensitiveKey('legacy.profile.name.v2.', 'unknown')] =
        'Alice';
    secStore[scopedLegacySensitiveKey('legacy.profile.phone.v2.', 'unknown')] =
        '+1234567';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.id.v2.',
      'unknown',
    )] = 'official-1';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.name.v2.',
      'unknown',
    )] = 'Ops Console';
    secStore[scopedLegacySensitiveKey(
      'legacy.contact_shortlist.v2.',
      'unknown',
    )] = jsonEncode(<String>['+333']);

    SharedPreferences.setMockInitialValues(<String, Object>{});

    expect((await loadLegacyProfileSummary()).phone, '+1234567');
    expect(
      (await loadLegacyDefaultOfficialAccountContext()).accountId,
      'official-1',
    );
    expect(await loadLegacyContactShortlistEntries(), <String>['+333']);
    expect(
      secStore.containsKey(
        scopedLegacySensitiveKey('legacy.profile.phone.v2.', 'unknown'),
      ),
      isTrue,
    );

    await clearLegacySensitivePrefState();

    expect((await loadLegacyProfileSummary()).name, isEmpty);
    expect((await loadLegacyProfileSummary()).phone, isEmpty);
    expect(
      (await loadLegacyDefaultOfficialAccountContext()).accountId,
      isEmpty,
    );
    expect(await loadLegacyContactShortlistEntries(), isEmpty);
  });

  test('default official account saves to scoped secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'official.default_account_id': 'legacy-official',
      'official.default_account_name': 'Legacy Console',
    });
    final sp = await SharedPreferences.getInstance();

    await saveLegacyDefaultOfficialAccountContext(
      accountId: 'official-2',
      accountName: 'Console Two',
      sp: sp,
      baseUrlOverride: 'https://api.example.com',
    );

    final loaded = await loadLegacyDefaultOfficialAccountContext(
      sp: sp,
      baseUrlOverride: 'https://api.example.com',
    );

    expect(loaded.accountId, 'official-2');
    expect(loaded.accountName, 'Console Two');
    expect(sp.getString('official.default_account_id'), isNull);
    expect(sp.getString('official.default_account_name'), isNull);
    expect(
      secStore[scopedLegacySensitiveKey(
        'legacy.official.default_account.id.v2.',
        'https://api.example.com',
      )],
      'official-2',
    );
    expect(
      secStore[scopedLegacySensitiveKey(
        'legacy.official.default_account.name.v2.',
        'https://api.example.com',
      )],
      'Console Two',
    );
  });

  test('legacy sensitive prefs stay isolated across canonical API origins',
      () async {
    secStore[scopedLegacySensitiveKey(
      'legacy.profile.name.v2.',
      'https://api.one.example',
    )] = 'Alice One';
    secStore[scopedLegacySensitiveKey(
      'legacy.profile.phone.v2.',
      'https://api.one.example',
    )] = '+111';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.id.v2.',
      'https://api.one.example',
    )] = 'official-1';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.name.v2.',
      'https://api.one.example',
    )] = 'Console One';
    secStore[scopedLegacySensitiveKey(
      'legacy.contact_shortlist.v2.',
      'https://api.one.example',
    )] = jsonEncode(<String>['+111']);
    secStore[scopedLegacySensitiveKey(
      'legacy.profile.name.v2.',
      'https://api.two.example',
    )] = 'Alice Two';
    secStore[scopedLegacySensitiveKey(
      'legacy.profile.phone.v2.',
      'https://api.two.example',
    )] = '+222';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.id.v2.',
      'https://api.two.example',
    )] = 'official-2';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.name.v2.',
      'https://api.two.example',
    )] = 'Console Two';
    secStore[scopedLegacySensitiveKey(
      'legacy.contact_shortlist.v2.',
      'https://api.two.example',
    )] = jsonEncode(<String>['+222']);

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect((await loadLegacyProfileSummary()).phone, '+111');
    expect(
      (await loadLegacyDefaultOfficialAccountContext()).accountId,
      'official-1',
    );
    expect(await loadLegacyContactShortlistEntries(), <String>['+111']);

    await sp.setString('base_url', 'https://api.two.example');
    expect((await loadLegacyProfileSummary()).phone, '+222');
    expect(
      (await loadLegacyDefaultOfficialAccountContext()).accountId,
      'official-2',
    );
    expect(await loadLegacyContactShortlistEntries(), <String>['+222']);
  });

  test('legacy sensitive prefs honor explicit baseUrl override scope',
      () async {
    secStore[scopedLegacySensitiveKey(
      'legacy.profile.name.v2.',
      'https://api.one.example',
    )] = 'Alice One';
    secStore[scopedLegacySensitiveKey(
      'legacy.profile.phone.v2.',
      'https://api.one.example',
    )] = '+111';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.id.v2.',
      'https://api.one.example',
    )] = 'official-1';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.name.v2.',
      'https://api.one.example',
    )] = 'Console One';
    secStore[scopedLegacySensitiveKey(
      'legacy.contact_shortlist.v2.',
      'https://api.one.example',
    )] = jsonEncode(<String>['+111']);
    secStore[scopedLegacySensitiveKey(
      'legacy.profile.name.v2.',
      'https://api.two.example',
    )] = 'Alice Two';
    secStore[scopedLegacySensitiveKey(
      'legacy.profile.phone.v2.',
      'https://api.two.example',
    )] = '+222';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.id.v2.',
      'https://api.two.example',
    )] = 'official-2';
    secStore[scopedLegacySensitiveKey(
      'legacy.official.default_account.name.v2.',
      'https://api.two.example',
    )] = 'Console Two';
    secStore[scopedLegacySensitiveKey(
      'legacy.contact_shortlist.v2.',
      'https://api.two.example',
    )] = jsonEncode(<String>['+222']);

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');

    expect(
      (await loadLegacyProfileSummary(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ))
          .phone,
      '+222',
    );
    expect(
      (await loadLegacyDefaultOfficialAccountContext(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ))
          .accountId,
      'official-2',
    );
    expect(
      await loadLegacyContactShortlistEntries(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      <String>['+222'],
    );
  });

  test(
      'legacy global secure sensitive prefs do not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'last_login_name': 'Alice',
      'last_login_phone': '+1234567',
      'official.default_account_id': 'official-1',
      'official.default_account_name': 'Ops Console',
      'contact_shortlist': <String>['+333'],
    });
    secStore['legacy.profile.name.v1'] = 'Alice';
    secStore['legacy.profile.phone.v1'] = '+1234567';
    secStore['legacy.official.default_account.id.v1'] = 'official-1';
    secStore['legacy.official.default_account.name.v1'] = 'Ops Console';
    secStore['legacy.contact_shortlist.v1'] = jsonEncode(<String>['+333']);

    expect((await loadLegacyProfileSummary()).name, isEmpty);
    expect((await loadLegacyProfileSummary()).phone, isEmpty);
    expect(
      (await loadLegacyDefaultOfficialAccountContext()).accountId,
      isEmpty,
    );
    expect(await loadLegacyContactShortlistEntries(), isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('last_login_name'), isNull);
    expect(sp.getString('last_login_phone'), isNull);
    expect(sp.getString('official.default_account_id'), isNull);
    expect(sp.getString('official.default_account_name'), isNull);
    expect(sp.getStringList('contact_shortlist'), isNull);
    expect(secStore.containsKey('legacy.profile.name.v1'), isFalse);
    expect(secStore.containsKey('legacy.profile.phone.v1'), isFalse);
    expect(
      secStore.containsKey('legacy.official.default_account.id.v1'),
      isFalse,
    );
    expect(
      secStore.containsKey('legacy.official.default_account.name.v1'),
      isFalse,
    );
    expect(secStore.containsKey('legacy.contact_shortlist.v1'), isFalse);
    expect(
      secStore.containsKey(
        scopedLegacySensitiveKey(
          'legacy.profile.phone.v2.',
          'https://api.example.com',
        ),
      ),
      isFalse,
    );
  });
}
