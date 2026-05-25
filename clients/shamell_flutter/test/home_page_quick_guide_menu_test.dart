import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/mini_app_registry.dart';
import 'package:shamell_flutter/main.dart';

Widget _testApp(HomePage home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

ShamellCapabilities _caps({bool friends = false, bool coach = false}) {
  return ShamellCapabilities(
    chat: true,
    payments: true,
    coach: coach,
    friends: friends,
    moments: false,
    officialAccounts: false,
    channels: false,
    serviceNotifications: false,
    paymentsPhoneTargets: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'HomePage contacts add menu shows SyrChat ID and Scan without legacy entries',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(friends: true),
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Add friend'), findsNothing);
    expect(find.text('SyrChat ID'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Help'), findsNothing);
  });

  testWidgets(
      'HomePage Discover tab no longer shows Taxi or Coach Bus as standalone cards',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        HomePage(
          lockedMode: AppMode.user,
          runStartupTasks: false,
          initialCapabilities: _caps(coach: false),
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    // Taxi + Coach Bus moved into the Mini Programs surface (see
    // `MiniAppRegistry`: `ride` + `bus` entries); both standalone
    // Discover tiles are gone. The Mini Programs tile itself still
    // appears, so guard against false negatives from that label.
    expect(find.text('Taxi'), findsNothing);
    expect(find.text('Coach bus'), findsNothing);
    expect(find.text('Coach Bus'), findsNothing);
  });

  test('MiniAppRegistry registers Taxi and Coach Bus under Mobility', () {
    final mobility = MiniAppRegistry.descriptors
        .where((d) => d.categoryEn == 'Mobility')
        .map((d) => d.id)
        .toSet();
    expect(mobility, containsAll(<String>{'ride', 'bus'}));
    expect(MiniAppRegistry.byId('taxi'), isNotNull,
        reason: 'taxi alias should resolve to the ride mini-program');
    expect(MiniAppRegistry.byId('coach'), isNotNull,
        reason: 'coach alias should resolve to the bus mini-program');
  });
}
