import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/coach_bus/coach_boarding_offline_queue.dart';
import 'package:shamell_flutter/core/coach_bus/coach_platform_contracts.dart';
import 'package:shamell_flutter/core/offline_queue.dart';

const _apiBaseUrl = 'https://api.shamell.online';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = (args['value'] ?? '').toString();
            return null;
          case 'read':
            return secStore[key];
          case 'delete':
            secStore.remove(key);
            return null;
          case 'deleteAll':
            secStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secStore);
          case 'containsKey':
            return secStore.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
    await OfflineQueue.clearPersistentState();
  });

  test('coach boarding offline queue persists and filters queued scans',
      () async {
    await enqueuePendingCoachBoardingScan(
      baseUrl: _apiBaseUrl,
      tripId: 'trip_demo_express_direct',
      ticketId: 'ticket_booking_demo_express_direct_1',
      scanStatus: CoachBoardingScanStatus.scanned,
      offlineCaptured: true,
      deviceId: 'coach_crew_console',
      note: 'queued during outage',
      idempotencyKey: 'coach-crew-offline-1',
    );
    await enqueuePendingCoachBoardingScan(
      baseUrl: _apiBaseUrl,
      tripId: 'trip_demo_border_runner',
      ticketId: 'ticket_booking_demo_border_runner_1',
      scanStatus: CoachBoardingScanStatus.noShow,
      offlineCaptured: true,
      deviceId: 'coach_crew_console',
      idempotencyKey: 'coach-crew-offline-2',
    );

    final all = await loadPendingCoachBoardingScans(baseUrl: _apiBaseUrl);
    final expressOnly = await loadPendingCoachBoardingScans(
      baseUrl: _apiBaseUrl,
      tripId: 'trip_demo_express_direct',
    );

    expect(all.length, 2);
    expect(expressOnly.length, 1);
    expect(expressOnly.single.tripId, 'trip_demo_express_direct');
    expect(expressOnly.single.ticketId, 'ticket_booking_demo_express_direct_1');
    expect(expressOnly.single.scanStatus, CoachBoardingScanStatus.scanned);
    expect(expressOnly.single.offlineCaptured, isTrue);
    expect(expressOnly.single.idempotencyKey, 'coach-crew-offline-1');
    expect(expressOnly.single.note, 'queued during outage');
  });
}
