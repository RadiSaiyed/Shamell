import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/capabilities.dart';
import 'package:shamell_flutter/core/coach_bus/coach_boarding_console_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_boarding_offline_queue.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_platform_contracts.dart';
import 'package:shamell_flutter/core/dashboard_policy_scope.dart';
import 'package:shamell_flutter/core/offline_queue.dart';

class _FakeCoachBoardingApi extends CoachMobilityApi {
  _FakeCoachBoardingApi({required super.baseUrl});

  int recordBoardingCalls = 0;
  int getCrewManifestCalls = 0;
  CoachBoardingScanStatus? lastScanStatus;

  CoachCrewTripSummary _trip({
    int boardedCount = 0,
    int deniedCount = 0,
    int noShowCount = 0,
    int pendingCount = 2,
  }) {
    return CoachCrewTripSummary(
      tripId: 'trip_demo_express_direct',
      journeyId: 'journey_demo_express_direct',
      bookingId: 'booking_demo_express_direct',
      operatorName: 'Demo Express',
      from: 'Damascus',
      to: 'Aleppo',
      departureAtIso: '2026-04-08T08:00:00Z',
      arrivalAtIso: '2026-04-08T12:30:00Z',
      boardingOpensAtIso: '2026-04-08T07:20:00Z',
      boardingClosesAtIso: '2026-04-08T07:55:00Z',
      gateLabel: 'Bay A4',
      vehicleLabel: 'Bus DX-402',
      manifestCount: 2,
      boardedCount: boardedCount,
      deniedCount: deniedCount,
      noShowCount: noShowCount,
      pendingCount: pendingCount,
    );
  }

  CoachCrewManifestEntry _entry({
    required String ticketId,
    required String passengerId,
    required String givenName,
    required String familyName,
    required String seatNumber,
    required CoachManifestBoardingState boardingState,
    CoachBoardingEvent? lastEvent,
    bool needsAttention = false,
  }) {
    return CoachCrewManifestEntry(
      passenger: CoachPassengerManifest(
        passengerId: passengerId,
        givenName: givenName,
        familyName: familyName,
        riderCategory: CoachPassengerRiderCategory.adult,
        nationalityCode: 'SY',
      ),
      ticket: CoachTicketCoupon(
        ticketId: ticketId,
        bookingId: 'booking_demo_express_direct',
        couponId: 'coupon-$ticketId',
        passengerId: passengerId,
        segmentIds: const <String>['seg_1'],
        status: CoachTicketStatus.active,
        operatorTicketReference: 'operator-$ticketId',
        qrPayloadRef: 'object://coach/tickets/$ticketId/qr',
        issuedAtIso: '2026-04-07T12:06:30Z',
        revokedAtIso: null,
      ),
      seatNumber: seatNumber,
      boardingState: boardingState,
      lastEvent: lastEvent,
      needsAttention: needsAttention,
    );
  }

  CoachBoardingEvent _event({
    required String ticketId,
    required CoachBoardingScanStatus status,
    String? note,
  }) {
    return CoachBoardingEvent(
      boardingEventId: 'boardevt_$ticketId',
      ticketId: ticketId,
      tripId: 'trip_demo_express_direct',
      scanStatus: status,
      capturedAtIso: '2026-04-08T07:41:00Z',
      offlineCaptured: false,
      deviceId: 'coach_crew_console',
      note: note,
    );
  }

  @override
  Future<CoachCrewDepartureBoardResponse> crewDepartures({
    int limit = 12,
  }) async {
    return CoachCrewDepartureBoardResponse(
      generatedAtIso: '2026-04-07T15:00:00Z',
      departures: <CoachCrewTripSummary>[_trip()],
    );
  }

  @override
  Future<CoachCrewManifestResponse> getCrewManifest(String tripId) async {
    getCrewManifestCalls += 1;
    return CoachCrewManifestResponse(
      trip: _trip(),
      manifest: <CoachCrewManifestEntry>[
        _entry(
          ticketId: 'ticket_booking_demo_express_direct_1',
          passengerId: 'adult_1',
          givenName: 'Lina',
          familyName: 'Haddad',
          seatNumber: '4A',
          boardingState: CoachManifestBoardingState.notBoarded,
        ),
        _entry(
          ticketId: 'ticket_booking_demo_express_direct_2',
          passengerId: 'adult_2',
          givenName: 'Omar',
          familyName: 'Darwish',
          seatNumber: '4B',
          boardingState: CoachManifestBoardingState.notBoarded,
        ),
      ],
      recentEvents: const <CoachBoardingEvent>[],
    );
  }

  @override
  Future<CoachCrewBoardingResult> recordBoarding({
    required String tripId,
    required String ticketId,
    required CoachBoardingScanStatus scanStatus,
    bool offlineCaptured = false,
    String? deviceId,
    String? note,
    String? idempotencyKey,
  }) async {
    recordBoardingCalls++;
    lastScanStatus = scanStatus;
    final event = _event(
      ticketId: ticketId,
      status: scanStatus,
      note: note ?? 'scanned via qr',
    );
    return CoachCrewBoardingResult(
      idempotency: const CoachCommandIdempotencyMeta(
        key: 'coach-crew-boarding-test-1',
        scope: 'coach_crew_boarding_record',
        requestFingerprint: 'fp_boarding_test_1',
        replayed: false,
        derivedKeys: <String, String>{},
      ),
      trip: _trip(boardedCount: 1, pendingCount: 1),
      manifestEntry: _entry(
        ticketId: ticketId,
        passengerId: 'adult_1',
        givenName: 'Lina',
        familyName: 'Haddad',
        seatNumber: '4A',
        boardingState: CoachManifestBoardingState.boarded,
        lastEvent: event,
      ),
      boardingEvent: event,
      recentEvents: <CoachBoardingEvent>[event],
    );
  }
}

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

  testWidgets('coach boarding console renders for crew-capable roles',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachBoardingApi(baseUrl: 'https://api.shamell.online');
    final initialDepartureBoard = await api.crewDepartures();
    final initialManifest =
        await api.getCrewManifest('trip_demo_express_direct');

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBoardingConsolePage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialDepartureBoard: initialDepartureBoard,
          initialManifest: initialManifest,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
          scanLauncher: (_) async =>
              'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coach boarding'), findsOneWidget);
    expect(find.byTooltip('Scan ticket'), findsOneWidget);
    expect(
      find.text('This account is not allowed to manage coach boarding.'),
      findsNothing,
    );
  });

  testWidgets('coach boarding console consumes inherited dashboard policy',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachBoardingApi(baseUrl: 'https://api.shamell.online');
    final initialDepartureBoard = await api.crewDepartures();
    final initialManifest =
        await api.getCrewManifest('trip_demo_express_direct');

    await tester.pumpWidget(
      MaterialApp(
        home: ShamellDashboardPolicyScope(
          policy: const ShamellDashboardPolicy(
            baseUrl: 'https://api.shamell.online',
            privilegeSnapshot: AccountPrivilegeSnapshot(
              permissions: <String>['coach.manifest.read'],
              products: <String>['coach'],
            ),
            capabilities: ShamellCapabilities(
              coach: true,
              chat: true,
              payments: true,
              friends: false,
              moments: false,
              officialAccounts: false,
              channels: false,
              serviceNotifications: false,
              paymentsPhoneTargets: false,
            ),
          ),
          child: CoachBoardingConsolePage(
            baseUrl: 'https://api.shamell.online',
            api: api,
            initialDepartureBoard: initialDepartureBoard,
            initialManifest: initialManifest,
            scanLauncher: (_) async =>
                'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coach boarding'), findsOneWidget);
    expect(
      find.text('This account is not allowed to manage coach boarding.'),
      findsNothing,
    );
  });

  testWidgets('coach boarding console retries queued scans when app resumes',
      (tester) async {
    configureLargeViewport(tester);
    final flushed = <CoachOfflineBoardingScan>[];
    const baseUrl = 'http://127.0.0.1:8080';
    final api = _FakeCoachBoardingApi(baseUrl: baseUrl);
    final initialDepartureBoard = await api.crewDepartures();
    final initialManifest =
        await api.getCrewManifest('trip_demo_express_direct');

    Future<int> flushOverride(String currentBaseUrl) async {
      final pending = await loadPendingCoachBoardingScans(
        baseUrl: currentBaseUrl,
      );
      flushed.addAll(pending);
      for (final scan in pending) {
        await OfflineQueue.remove(scan.queueId);
      }
      return pending.length;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBoardingConsolePage(
          baseUrl: baseUrl,
          api: api,
          pendingScanFlusher: flushOverride,
          initialDepartureBoard: initialDepartureBoard,
          initialManifest: initialManifest,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await enqueuePendingCoachBoardingScan(
      baseUrl: baseUrl,
      tripId: 'trip_demo_express_direct',
      ticketId: 'ticket_booking_demo_express_direct_2',
      scanStatus: CoachBoardingScanStatus.noShow,
      offlineCaptured: true,
      deviceId: 'coach_crew_console',
      note: 'queued while app paused',
      idempotencyKey: 'coach-crew-pending-resume',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(flushed.length, 1);
    expect(flushed.single.ticketId, 'ticket_booking_demo_express_direct_2');
    expect(flushed.single.scanStatus, CoachBoardingScanStatus.noShow);
    expect(flushed.single.offlineCaptured, isTrue);
    expect(flushed.single.deviceId, 'coach_crew_console');
    expect(flushed.single.note, 'queued while app paused');
    expect(find.text('Offline scan queue'), findsNothing);
    expect(
      await loadPendingCoachBoardingScans(baseUrl: baseUrl),
      isEmpty,
    );
  });

  testWidgets('coach boarding console syncs queued scans on refresh',
      (tester) async {
    configureLargeViewport(tester);
    final flushed = <CoachOfflineBoardingScan>[];
    const baseUrl = 'http://127.0.0.1:8080';
    final api = _FakeCoachBoardingApi(baseUrl: baseUrl);
    final initialDepartureBoard = await api.crewDepartures();
    final initialManifest =
        await api.getCrewManifest('trip_demo_express_direct');

    Future<int> flushOverride(String currentBaseUrl) async {
      final pending = await loadPendingCoachBoardingScans(
        baseUrl: currentBaseUrl,
      );
      flushed.addAll(pending);
      for (final scan in pending) {
        await OfflineQueue.remove(scan.queueId);
      }
      return pending.length;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBoardingConsolePage(
          baseUrl: baseUrl,
          api: api,
          pendingScanFlusher: flushOverride,
          initialDepartureBoard: initialDepartureBoard,
          initialManifest: initialManifest,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            roles: <String>['ops'],
            isSuperadmin: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await enqueuePendingCoachBoardingScan(
      baseUrl: baseUrl,
      tripId: 'trip_demo_express_direct',
      ticketId: 'ticket_booking_demo_express_direct_1',
      scanStatus: CoachBoardingScanStatus.scanned,
      offlineCaptured: true,
      deviceId: 'coach_crew_console',
      note: 'queued before manual refresh',
      idempotencyKey: 'coach-crew-pending-refresh',
    );

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(flushed.length, 1);
    expect(flushed.single.ticketId, 'ticket_booking_demo_express_direct_1');
    expect(flushed.single.scanStatus, CoachBoardingScanStatus.scanned);
    expect(flushed.single.offlineCaptured, isTrue);
    expect(flushed.single.deviceId, 'coach_crew_console');
    expect(flushed.single.note, 'queued before manual refresh');
    expect(find.text('Offline scan queue'), findsNothing);
    expect(
      await loadPendingCoachBoardingScans(baseUrl: baseUrl),
      isEmpty,
    );
  });
}
