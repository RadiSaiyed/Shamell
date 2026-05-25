import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/shamell_new_message_notification_page.dart';

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
    final store = ChatLocalStore();
    await store.clearNotifyPreferences();
  });

  testWidgets(
      'ShamellNewMessageNotificationPage loads notification config from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');

    final store = ChatLocalStore();
    await store.setNotifyEnabled(
      false,
      baseUrlOverride: 'https://api.two.example',
    );

    await tester.pumpWidget(
      _testApp(
        const ShamellNewMessageNotificationPage(
          baseUrl: 'https://api.two.example',
        ),
      ),
    );

    await tester.pumpAndSettle();

    final switchWidget = tester.widget<Switch>(find.byType(Switch).first);
    expect(switchWidget.value, isFalse);
  });
}
