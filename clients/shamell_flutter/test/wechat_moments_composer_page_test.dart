import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/wechat_moments_composer_page.dart';

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

void _configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('WeChatMomentsComposerPage returns tagged audience privacy',
      (tester) async {
    _configureLargeViewport(tester);
    WeChatMomentDraft? submittedDraft;

    await tester.pumpWidget(
      _testApp(
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    submittedDraft =
                        await Navigator.of(context).push<WeChatMomentDraft>(
                      MaterialPageRoute(
                        builder: (_) => const WeChatMomentsComposerPage(
                          baseUrl: 'https://example.test',
                          availableAudienceTags: <String>['Family', 'Work'],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open composer'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'hello family');
    await tester.pump();

    await tester.tap(find.text('Who can see'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only Family').first);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Only Family'), findsOneWidget);

    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(submittedDraft, isNotNull);
    expect(submittedDraft!.text, 'hello family');
    expect(submittedDraft!.visibilityScope, 'friends');
    expect(submittedDraft!.visibilityTag, 'Family');
    expect(submittedDraft!.visibilityTagMode, 'only');
  });

  testWidgets('WeChatMomentsComposerPage returns mini program attachment',
      (tester) async {
    _configureLargeViewport(tester);
    WeChatMomentDraft? submittedDraft;

    await tester.pumpWidget(
      _testApp(
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    submittedDraft =
                        await Navigator.of(context).push<WeChatMomentDraft>(
                      MaterialPageRoute(
                        builder: (_) => const WeChatMomentsComposerPage(
                          baseUrl: 'https://example.test',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open composer'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mini Program'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SyrChat Pay').last);
    await tester.pumpAndSettle();

    expect(find.text('SyrChat Pay'), findsWidgets);

    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(submittedDraft, isNotNull);
    expect(submittedDraft!.text.trim(), isEmpty);
    expect(submittedDraft!.miniProgramId, 'payments');
  });
}
