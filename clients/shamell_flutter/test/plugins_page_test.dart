import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/plugin_visibility_store.dart';
import 'package:shamell_flutter/main.dart' show ShamellPluginsPage;

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

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('ShamellPluginsPage only exposes runtime-backed plugin toggles',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const ShamellPluginsPage(baseUrl: 'https://api.shamell.online'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Cards & Offers'), findsNothing);
    expect(find.text('Moments'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
    expect(
      find.text(
        'Plugins currently control Scan in the Apps tab.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('ShamellPluginsPage honors the explicit baseUrl scope',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.other.example',
    });

    final sp = await SharedPreferences.getInstance();
    await saveScopedPluginVisibilityPreference(
      key: 'shamell.plugins.show_scan',
      value: false,
      sp: sp,
      baseUrlOverride: 'https://api.shamell.online',
    );

    await tester.pumpWidget(
      _testApp(
        const ShamellPluginsPage(baseUrl: 'https://api.shamell.online'),
      ),
    );

    await tester.pumpAndSettle();

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(1));
    expect(switches.first.value, isFalse);
  });
}
