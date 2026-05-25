import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_schedule_picker.dart';

void main() {
  Future<void> openPicker(
    WidgetTester tester, {
    required void Function(DateTime? result) onResult,
    bool offerCancelExisting = false,
  }) async {
    // Phone-sized viewport: the sheet's default half-height needs
    // room for all 4 quick options + Custom + (optional) Cancel.
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    // ignore: discarded_futures
    ChatSchedulePickerSheet.show(
      navKey.currentContext!,
      offerCancelExisting: offerCancelExisting,
    ).then(onResult);
    await tester.pumpAndSettle();
  }

  testWidgets('renders the 4 default quick options + Custom row',
      (tester) async {
    DateTime? picked;
    await openPicker(tester, onResult: (r) => picked = r);
    expect(find.text('In 1 hour'), findsOneWidget);
    expect(find.text('In 4 hours'), findsOneWidget);
    expect(find.text('Tomorrow at 09:00'), findsOneWidget);
    expect(find.text('Tomorrow at 18:00'), findsOneWidget);
    expect(find.text('Custom date & time'), findsOneWidget);
    // Cancel row only when caller asks for it.
    expect(find.text('Cancel schedule'), findsNothing);
    expect(picked, isNull);
  });

  testWidgets('tapping "In 1 hour" returns ~now+1h in UTC', (tester) async {
    DateTime? picked;
    await openPicker(tester, onResult: (r) => picked = r);
    final before = DateTime.now().toUtc();
    await tester.tap(find.text('In 1 hour'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.isUtc, isTrue);
    final delta = picked!.difference(before);
    // Allow generous slack for test framework jitter.
    expect(delta.inMinutes, inInclusiveRange(58, 62));
  });

  testWidgets('Cancel-schedule row shows when offered and returns sentinel',
      (tester) async {
    DateTime? picked;
    await openPicker(
      tester,
      onResult: (r) => picked = r,
      offerCancelExisting: true,
    );
    expect(find.text('Cancel schedule'), findsOneWidget);
    await tester.tap(find.text('Cancel schedule'));
    await tester.pumpAndSettle();
    expect(picked, equals(chatScheduleCancelSentinel));
  });

  testWidgets('dismiss via barrier returns null', (tester) async {
    DateTime? picked = DateTime.utc(2099, 1, 1);
    await openPicker(tester, onResult: (r) => picked = r);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  group('ChatScheduleOption.resolve', () {
    test('relative offset lands at now+offset', () {
      const opt = ChatScheduleOption(
        labelEn: 'In 1 hour',
        labelAr: 'بعد ساعة',
        offset: Duration(hours: 1),
      );
      final now = DateTime(2026, 5, 14, 12, 30);
      final resolved = opt.resolve(now);
      expect(resolved, DateTime(2026, 5, 14, 13, 30));
    });

    test('pinned-time-of-day lands at today if still in the future', () {
      const opt = ChatScheduleOption(
        labelEn: 'Today at 18:00',
        labelAr: 'اليوم 18:00',
        pinnedTimeOfDay: TimeOfDay(hour: 18, minute: 0),
        nextDay: false,
      );
      final now = DateTime(2026, 5, 14, 12, 30);
      final resolved = opt.resolve(now);
      expect(resolved, DateTime(2026, 5, 14, 18, 0));
    });

    test('pinned-time-of-day rolls to tomorrow when nextDay=true', () {
      const opt = ChatScheduleOption(
        labelEn: 'Tomorrow at 09:00',
        labelAr: 'غدًا 09:00',
        pinnedTimeOfDay: TimeOfDay(hour: 9, minute: 0),
        nextDay: true,
      );
      final now = DateTime(2026, 5, 14, 12, 30);
      final resolved = opt.resolve(now);
      expect(resolved, DateTime(2026, 5, 15, 9, 0));
    });

    test('pinned-time-of-day in the past rolls forward a day', () {
      // 09:00 today is in the past relative to 12:30 now → roll to
      // tomorrow even when `nextDay` is false.
      const opt = ChatScheduleOption(
        labelEn: 'Today at 09:00',
        labelAr: 'اليوم 09:00',
        pinnedTimeOfDay: TimeOfDay(hour: 9, minute: 0),
        nextDay: false,
      );
      final now = DateTime(2026, 5, 14, 12, 30);
      final resolved = opt.resolve(now);
      expect(resolved, DateTime(2026, 5, 15, 9, 0));
    });
  });

  test('default option palette has 4 entries with proper i18n labels', () {
    expect(defaultChatScheduleOptions.length, 4);
    for (final opt in defaultChatScheduleOptions) {
      expect(opt.labelEn.isNotEmpty, isTrue);
      expect(opt.labelAr.isNotEmpty, isTrue);
    }
  });

  test('cancel sentinel is identifiable + idempotent', () {
    expect(chatScheduleCancelSentinel.isUtc, isTrue);
    expect(chatScheduleCancelSentinel.year, 1970);
  });
}
