import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_snooze_picker.dart';

void main() {
  // Drives the sheet off a stable `navigatorKey.currentContext` rather than
  // a Builder context inside an async button handler — the latter goes stale
  // once the sheet pops (`Looking up a deactivated widget's ancestor is
  // unsafe`). Using `.then(onResult)` also avoids capturing the button ctx
  // for the resume of the await.
  Future<void> openSheet(
    WidgetTester tester, {
    required void Function(int? result) onResult,
    bool currentlySnoozed = false,
    String? currentSnoozeLabel,
  }) async {
    // Phone-sized viewport so the sheet (which gets half-height) has room
    // for all 5 options + clear row without scrolling them offscreen — the
    // default test surface is only 600px tall.
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    // ignore: discarded_futures
    ChatSnoozePickerSheet.show(
      navKey.currentContext!,
      currentlySnoozed: currentlySnoozed,
      currentSnoozeLabel: currentSnoozeLabel,
    ).then(onResult);
    await tester.pumpAndSettle();
  }

  testWidgets('renders all 5 default options', (tester) async {
    int? picked;
    await openSheet(tester, onResult: (r) => picked = r);
    expect(find.text('15 minutes'), findsOneWidget);
    expect(find.text('1 hour'), findsOneWidget);
    expect(find.text('8 hours'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('1 week'), findsOneWidget);
    // Clear option NOT shown when not currently snoozed.
    expect(find.text('Clear snooze'), findsNothing);
    expect(picked, isNull);
  });

  testWidgets('tapping an option returns seconds + dismisses', (tester) async {
    int? picked;
    await openSheet(tester, onResult: (r) => picked = r);
    await tester.tap(find.text('1 hour'));
    await tester.pumpAndSettle();
    expect(picked, 60 * 60);
  });

  testWidgets('"Clear snooze" only shown when currentlySnoozed=true',
      (tester) async {
    int? picked;
    await openSheet(
      tester,
      onResult: (r) => picked = r,
      currentlySnoozed: true,
      currentSnoozeLabel: 'Snoozed until 18:00',
    );
    expect(find.text('Snoozed until 18:00'), findsOneWidget);
    expect(find.text('Clear snooze'), findsOneWidget);
    await tester.tap(find.text('Clear snooze'));
    await tester.pumpAndSettle();
    expect(picked, 0);
  });

  testWidgets('dismiss via barrier tap returns null', (tester) async {
    int? picked = -1;
    await openSheet(tester, onResult: (r) => picked = r);
    // Tap barrier at top of screen (outside the sheet).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
