// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ops_admin_flutter/main.dart';

void main() {
  setUp(() async {
    // Keep SharedPreferences in-memory for tests.
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build the Ops Admin app and expect the login screen by default.
    await tester.pumpWidget(const OpsAdminApp());

    expect(find.textContaining('Sign in'), findsWidgets);
    expect(find.byIcon(Icons.login), findsNothing); // simple smoke check
  });
}
