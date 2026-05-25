import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_typing_indicator.dart';
import 'package:shamell_flutter/core/l10n.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<String> names,
    Locale locale = const Locale('en'),
    Duration dotCycle = const Duration(milliseconds: 1200),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
        // Same delegate stack as `main.dart` — needed so the framework
        // doesn't log a "locale not supported" warning when we force
        // `ar` from a test.
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ChatTypingIndicator(typingNames: names, dotCycle: dotCycle),
        ),
      ),
    );
    // `GlobalMaterialLocalizations.delegate.load` is async — without
    // this pump, the first frame is the loading placeholder and no
    // `Text` widget is in the tree yet.
    await tester.pump();
  }

  testWidgets('hides itself when nobody is typing', (tester) async {
    await pump(tester, names: const <String>[]);
    expect(find.byType(Text), findsNothing);
    // SizedBox.shrink renders with zero size — assert no typing copy.
    expect(find.textContaining('typing'), findsNothing);
    expect(find.textContaining('يكتب'), findsNothing);
  });

  testWidgets('shows "<name> is typing…" for one user (EN)', (tester) async {
    await pump(tester, names: const <String>['Alice']);
    expect(find.text('Alice is typing...'), findsOneWidget);
  });

  testWidgets('shows the two-name "and … are typing" form (EN)',
      (tester) async {
    await pump(tester, names: const <String>['Alice', 'Bob']);
    expect(find.text('Alice and Bob are typing'), findsOneWidget);
  });

  testWidgets('collapses 3+ typers to a generic phrase (EN)', (tester) async {
    await pump(tester, names: const <String>['A', 'B', 'C']);
    expect(find.text('Several people are typing...'), findsOneWidget);
  });

  testWidgets('uses Arabic single-typer form when locale is ar',
      (tester) async {
    await pump(
      tester,
      names: const <String>['أحمد'],
      locale: const Locale('ar'),
    );
    expect(find.text('يكتب أحمد الآن...'), findsOneWidget);
  });

  testWidgets('uses Arabic two-typer form when locale is ar', (tester) async {
    await pump(
      tester,
      names: const <String>['أحمد', 'سامي'],
      locale: const Locale('ar'),
    );
    expect(find.text('أحمد و سامي يكتبان'), findsOneWidget);
  });

  testWidgets('falls back to "Typing…" when single name is blank',
      (tester) async {
    await pump(tester, names: const <String>['']);
    expect(find.text('Typing...'), findsOneWidget);
  });

  testWidgets('dots animate through 0–3 trailing dots', (tester) async {
    // Use a short cycle so the test runs quickly.
    await pump(
      tester,
      names: const <String>['Alice'],
      dotCycle: const Duration(milliseconds: 400),
    );

    // Collect the dot strings we observe over one full cycle (4 phases).
    final seen = <String>{};
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      // Find the dots Text — it's the second Text (after the label),
      // identified by being inside a SizedBox of width 18.
      final dotsFinder = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 18,
        ),
        matching: find.byType(Text),
      );
      // dotsFinder may match multiple if MaterialApp wraps things, so
      // grab whichever Text is inside our specific SizedBox.
      final widgets = tester.widgetList<Text>(dotsFinder).toList();
      if (widgets.isNotEmpty) {
        seen.add(widgets.first.data ?? '');
      }
    }
    // We should have observed at least 2 distinct dot frames over a
    // 400ms cycle sampled every 100ms.
    expect(seen.length, greaterThanOrEqualTo(2));
    // And every observed value must be a valid dot frame.
    for (final v in seen) {
      expect(['', '.', '..', '...'].contains(v), isTrue,
          reason: 'unexpected dot frame: "$v"');
    }
    // Force the controller to stop before the test ends to avoid the
    // "pending timers" warning from pumpAndSettle's caller.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
