import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/privacy_preference_store.dart';
import 'package:shamell_flutter/core/shamell_settings_privacy_page.dart';

Widget _testApp(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};

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
    await clearPrivacyPreferenceState();
  });

  testWidgets(
      'ShamellSettingsPrivacyPage loads friend verification from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await savePrivacyPreferenceValue(
      kPrivacyFriendVerificationPrefKey,
      false,
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsPrivacyPage(
          baseUrl: 'https://api.two.example',
          deviceId: 'device_1',
        ),
      ),
    );

    await tester.pumpAndSettle();

    final switchWidget = tester.widget<Switch>(find.byType(Switch).first);
    expect(switchWidget.value, isFalse);
  });

  testWidgets(
      'ShamellSettingsPrivacyPage shows invite-first add-me policy inline',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsPrivacyPage(
          baseUrl: 'https://api.example.com',
          deviceId: 'device_1',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Ways to add me'), findsOneWidget);
    expect(find.text('Moments & Status'), findsNothing);
    expect(
      find.text(
        'New contacts require an invite token or QR. SyrChat ID is for verification only.',
      ),
      findsOneWidget,
    );
  });
}
