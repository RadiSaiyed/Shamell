import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/push_readiness_banner.dart';

void main() {
  testWidgets('PushReadinessBanner stays hidden when Firebase is available',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PushReadinessBanner(
            isArabic: false,
            availabilityProbe: _pushAvailable,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Push unavailable in this build'), findsNothing);
  });

  testWidgets('PushReadinessBanner warns when Firebase is unavailable',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PushReadinessBanner(
            isArabic: false,
            availabilityProbe: _pushUnavailable,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Push unavailable in this build'), findsOneWidget);
    expect(
      find.textContaining('This app currently has no usable Firebase config'),
      findsOneWidget,
    );
  });
}

Future<bool> _pushAvailable() async => true;

Future<bool> _pushUnavailable() async => false;
