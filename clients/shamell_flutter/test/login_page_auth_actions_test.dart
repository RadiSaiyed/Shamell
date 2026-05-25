import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LoginPage shows username/password actions on mobile',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginPage(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sign in to SyrChat'), findsOneWidget);
    expect(
      find.text(
        'Create your account or sign in using only a username and password.',
      ),
      findsOneWidget,
    );
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Confirm password'), findsNothing);
    expect(find.text('Sign in with biometrics'), findsNothing);
    expect(find.text('Create new ID'), findsNothing);
    expect(find.text('Automatic setup'), findsNothing);
  });

  testWidgets('LoginPage reveals confirm password in sign-up mode',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginPage(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Sign up'));
    await tester.pump();

    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Wallet currency'), findsNothing);
    expect(find.text('Create account'), findsOneWidget);
  });
}
