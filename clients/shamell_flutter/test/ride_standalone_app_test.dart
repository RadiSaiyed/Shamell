import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/app_surface.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/rides/ride_driver_page.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_page.dart';
import 'package:shamell_flutter/core/rides/ride_mobility_api.dart';
import 'package:shamell_flutter/core/rides/ride_operator_console_page.dart';
import 'package:shamell_flutter/main.dart';

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
    home: home,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'base_url': 'https://api.example.com',
    });
  });

  test('ride surface parser recognizes standalone aliases', () {
    expect(shamellParseAppSurface('ride'), ShamellAppSurface.ride);
    expect(shamellParseAppSurface('taxi'), ShamellAppSurface.ride);
    expect(shamellParseAppSurface('driver'), ShamellAppSurface.driver);
    expect(shamellParseAppSurface('ride_operator'), ShamellAppSurface.operator);
    expect(shamellParseAppSurface('superapp'), ShamellAppSurface.superapp);
  });

  test('ride map starts at current location when no route preview exists', () {
    const currentLocation = RideGeoPoint(lat: 40.7128, lon: -74.0060);

    final target = rideHailingInitialMapTarget(
      routePreviewPoints: const <maplibre.LatLng>[],
      currentLocation: currentLocation,
    );
    final zoom = rideHailingInitialMapZoom(
      routePreviewPoints: const <maplibre.LatLng>[],
      currentLocation: currentLocation,
    );

    expect(target.latitude, closeTo(40.7128, 1e-6));
    expect(target.longitude, closeTo(-74.0060, 1e-6));
    expect(zoom, 14.5);
  });

  test('ride map keeps route preview focus ahead of current location', () {
    const currentLocation = RideGeoPoint(lat: 40.7128, lon: -74.0060);
    final routePreviewPoints = <maplibre.LatLng>[
      const maplibre.LatLng(33.5138, 36.2765),
      const maplibre.LatLng(33.5200, 36.3000),
    ];

    final target = rideHailingInitialMapTarget(
      routePreviewPoints: routePreviewPoints,
      currentLocation: currentLocation,
    );
    final zoom = rideHailingInitialMapZoom(
      routePreviewPoints: routePreviewPoints,
      currentLocation: currentLocation,
    );

    expect(target.latitude, closeTo(33.5138, 1e-6));
    expect(target.longitude, closeTo(36.2765, 1e-6));
    expect(zoom, 11.5);
  });

  test('ride surface labels are ride-specific', () {
    expect(
      shamellSurfaceAppTitle(
        isArabic: false,
        surface: ShamellAppSurface.ride,
      ),
      'SyrChat Ride',
    );
    expect(
      shamellRidePageTitle(isArabic: false, standaloneApp: true),
      'SyrChat Ride',
    );
    expect(
      shamellSurfaceAutomaticSetupDescription(
        isArabic: false,
        surface: ShamellAppSurface.ride,
      ),
      'Create your SyrChat rider account or sign in with your username and password.',
    );
    expect(
      shamellSurfaceAppTitle(
        isArabic: false,
        surface: ShamellAppSurface.driver,
      ),
      'SyrChat Driver',
    );
    expect(
      shamellSurfaceAppTitle(
        isArabic: false,
        surface: ShamellAppSurface.operator,
      ),
      'SyrChat Control',
    );
    expect(shamellSurfaceAllowsPublicAccountCreate(ShamellAppSurface.ride),
        isTrue);
    expect(
      shamellSurfaceUsesUsernamePasswordAuth(ShamellAppSurface.ride),
      isTrue,
    );
    expect(
      shamellSurfaceAllowsPublicAccountCreate(ShamellAppSurface.operator),
      isFalse,
    );
    expect(
      shamellSurfaceSetupActionLabel(
        isArabic: false,
        surface: ShamellAppSurface.driver,
      ),
      'Set up SyrChat Driver',
    );
    expect(
      shamellSurfaceManagedSignInActionLabel(
        isArabic: false,
        surface: ShamellAppSurface.operator,
      ),
      'Open approved sign-in',
    );
  });

  testWidgets('ride surface login page shows standalone ride branding',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const LoginPage(
          hasSession: true,
          appSurface: ShamellAppSurface.ride,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('SyrChat Ride'), findsOneWidget);
    expect(find.byIcon(Icons.local_taxi_outlined), findsOneWidget);
  });

  testWidgets('ride surface login page uses username/password auth',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const LoginPage(
          appSurface: ShamellAppSurface.ride,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sign in to SyrChat Ride'), findsOneWidget);
    expect(
      find.text(
        'Create your account or sign in using only a username and password.',
      ),
      findsOneWidget,
    );
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Create new ID'), findsNothing);
    expect(find.text('Set up SyrChat Ride'), findsNothing);
  });

  testWidgets(
      'operator surface login page uses approved sign-in instead of public signup',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const LoginPage(
          appSurface: ShamellAppSurface.operator,
          baseUrlOverride: 'https://api.example.com',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Open approved sign-in'), findsWidgets);
    expect(
      find.textContaining('Public operations accounts cannot be created'),
      findsOneWidget,
    );
    expect(find.text('Create new ID'), findsNothing);
    expect(find.text('Set up SyrChat Control'), findsNothing);
  });

  testWidgets('ride surface signed-in home uses standalone ride page',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        shamellBuildSignedInHome(
          appSurface: ShamellAppSurface.ride,
          baseUrlOverride: 'https://api.example.com',
          runStartupTasks: false,
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(RideHailingPage), findsOneWidget);
    expect(find.text('SyrChat Ride'), findsOneWidget);
    expect(find.text('Taxi mini program'), findsNothing);
  });

  testWidgets('superapp signed-in home still uses the existing HomePage',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        shamellBuildSignedInHome(
          appSurface: ShamellAppSurface.superapp,
          baseUrlOverride: 'https://api.example.com',
          runStartupTasks: false,
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(RideHailingPage), findsNothing);
  });

  testWidgets('driver surface signed-in home uses standalone driver page',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        shamellBuildSignedInHome(
          appSurface: ShamellAppSurface.driver,
          baseUrlOverride: 'https://api.example.com',
          runStartupTasks: false,
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(RideDriverPage), findsOneWidget);
    expect(find.text('SyrChat Driver'), findsOneWidget);
  });

  testWidgets('ride booking surface exposes current-location and pin actions',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const RideHailingPage(
          baseUrl: 'https://api.example.com',
          runStartupTasks: false,
          standaloneApp: true,
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Use current location'), findsOneWidget);
    expect(find.text('Pin pickup on map'), findsOneWidget);
    expect(find.text('Pin destination on map'), findsOneWidget);
  });

  testWidgets('standalone ride menu exposes saved route action in debug builds',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const RideHailingPage(
          baseUrl: 'https://api.example.com',
          runStartupTasks: false,
          standaloneApp: true,
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('ride-saved-route-tile')),
        findsOneWidget);
    expect(find.text('Use saved route'), findsOneWidget);
  });

  testWidgets('embedded ride menu keeps saved route action hidden',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const RideHailingPage(
          baseUrl: 'https://api.example.com',
          runStartupTasks: false,
          standaloneApp: false,
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('ride-saved-route-tile')),
        findsNothing);
    expect(find.text('Use saved route'), findsNothing);
  });

  testWidgets(
      'operator surface signed-in home uses standalone operator console',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        shamellBuildSignedInHome(
          appSurface: ShamellAppSurface.operator,
          baseUrlOverride: 'https://api.example.com',
          runStartupTasks: false,
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(RideOperatorConsolePage), findsOneWidget);
    expect(find.text('SyrChat Control'), findsOneWidget);
  });
}
