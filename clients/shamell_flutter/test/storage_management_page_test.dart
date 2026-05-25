import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/shamell_settings_general_page.dart';

Widget _testApp(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: home,
    ),
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

  testWidgets(
      'ShamellSettingsStorageManagementPage shows favorites as static storage info',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();

    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsStorageManagementPage(
          baseUrl: 'https://api.example.com',
        ),
      ),
    );

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Favorites are managed from the Me tab.'), findsNothing);
    expect(find.text('Favorites'), findsOneWidget);
    expect(
      find.text('Local storage used by saved favorite items.'),
      findsOneWidget,
    );

    final tile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Favorites'));
    expect(tile.onTap, isNull);
  });
}
