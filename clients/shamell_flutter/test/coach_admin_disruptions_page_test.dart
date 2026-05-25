import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_admin_disruptions_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';

Future<void> _dragUntilVisible(
  WidgetTester tester,
  Finder finder,
) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
    await tester.pumpAndSettle();
  }
}

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1400, 3200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

CoachAdminDisruptionTrip _buildTrip({
  required String tripId,
  required String operatorName,
  required String from,
  required String to,
  required String departureAtIso,
  required String workflowStatus,
  required String? disruptionKind,
  required String severity,
  required int affectedBookingCount,
  required int eligibleReaccommodationCount,
  required int queuedReaccommodationCount,
  required int feedIssueCount,
  required int pendingCount,
  required String nextAction,
  int manifestCount = 12,
  int boardedCount = 0,
  int deniedCount = 0,
  int noShowCount = 0,
  int? delayMinutes,
  String? note,
  String? reason,
  List<String> blockers = const <String>['timeout on realtime pull'],
}) {
  return CoachAdminDisruptionTrip(
    tripId: tripId,
    journeyId: 'journey_$tripId',
    bookingId: 'booking_$tripId',
    operatorId: 'op_$tripId',
    operatorName: operatorName,
    from: from,
    to: to,
    departureAtIso: departureAtIso,
    arrivalAtIso: '2026-04-14T12:15:00Z',
    gateLabel: 'Bay C1',
    vehicleLabel: 'Bus ${operatorName.substring(0, 2).toUpperCase()}-118',
    manifestCount: manifestCount,
    boardedCount: boardedCount,
    deniedCount: deniedCount,
    noShowCount: noShowCount,
    pendingCount: pendingCount,
    workflowStatus: workflowStatus,
    disruptionKind: disruptionKind,
    delayMinutes: delayMinutes,
    severity: severity,
    affectedBookingCount: affectedBookingCount,
    eligibleReaccommodationCount: eligibleReaccommodationCount,
    queuedReaccommodationCount: queuedReaccommodationCount,
    feedIssueCount: feedIssueCount,
    lastAction: queuedReaccommodationCount > 0
        ? 'queue_reaccommodation'
        : disruptionKind == 'cancelled'
            ? 'mark_cancelled'
            : 'mark_delayed',
    updatedAtIso: '2026-04-14T10:00:00Z',
    updatedByAccountId: 'acct_admin_demo',
    reason: reason,
    note: note,
    blockers: blockers,
    nextAction: nextAction,
  );
}

class _FakeCoachAdminDisruptionsApi extends CoachMobilityApi {
  _FakeCoachAdminDisruptionsApi({
    List<CoachAdminDisruptionTrip>? trips,
  })  : _trips = List<CoachAdminDisruptionTrip>.from(
          trips ??
              <CoachAdminDisruptionTrip>[
                _buildTrip(
                  tripId: 'trip_demo_border_runner',
                  operatorName: 'Border Runner',
                  from: 'Homs',
                  to: 'Amman',
                  departureAtIso: '2026-04-14T05:30:00Z',
                  workflowStatus: 'monitoring',
                  disruptionKind: 'delay',
                  severity: 'medium',
                  affectedBookingCount: 1,
                  eligibleReaccommodationCount: 1,
                  queuedReaccommodationCount: 0,
                  feedIssueCount: 1,
                  pendingCount: 1,
                  delayMinutes: 45,
                  reason: 'operator delay above service threshold',
                  note: 'Monitoring live delay.',
                  nextAction: 'Queue reaccommodation if the delay persists',
                ),
              ],
        ),
        super(baseUrl: 'https://api.shamell.online');

  int disruptionsCalls = 0;
  int actionCalls = 0;
  final List<CoachAdminDisruptionTrip> _trips;

  CoachAdminDisruptionSummary _summaryFor(
      List<CoachAdminDisruptionTrip> trips) {
    return CoachAdminDisruptionSummary(
      tripCount: trips.length,
      scheduledTrips:
          trips.where((trip) => trip.workflowStatus == 'scheduled').length,
      monitoringTrips:
          trips.where((trip) => trip.workflowStatus == 'monitoring').length,
      actionRequiredTrips: trips
          .where((trip) => trip.workflowStatus == 'action_required')
          .length,
      resolvedTrips:
          trips.where((trip) => trip.workflowStatus == 'resolved').length,
      delayedTrips:
          trips.where((trip) => trip.disruptionKind == 'delay').length,
      cancelledTrips:
          trips.where((trip) => trip.disruptionKind == 'cancelled').length,
      criticalTrips: trips.where((trip) => trip.severity == 'critical').length,
      affectedBookingCount:
          trips.fold(0, (sum, trip) => sum + trip.affectedBookingCount),
      eligibleReaccommodationCount: trips.fold(
        0,
        (sum, trip) => sum + trip.eligibleReaccommodationCount,
      ),
      queuedReaccommodationCount: trips.fold(
        0,
        (sum, trip) => sum + trip.queuedReaccommodationCount,
      ),
    );
  }

  CoachAdminDisruptionsResponse _responseFor(
      List<CoachAdminDisruptionTrip> trips) {
    return CoachAdminDisruptionsResponse(
      generatedAtIso: '2026-04-14T10:00:00Z',
      summary: _summaryFor(trips),
      trips: trips,
    );
  }

  @override
  Future<CoachAdminDisruptionsResponse> adminDisruptions({
    String? query,
    String? workflowStatus,
    String? disruptionKind,
    int limit = 20,
  }) async {
    disruptionsCalls++;
    final normalizedQuery = query?.trim().toLowerCase() ?? '';
    final filtered = _trips
        .where((trip) {
          if (workflowStatus != null &&
              workflowStatus.trim().isNotEmpty &&
              trip.workflowStatus != workflowStatus) {
            return false;
          }
          if (disruptionKind != null &&
              disruptionKind.trim().isNotEmpty &&
              trip.disruptionKind != disruptionKind) {
            return false;
          }
          if (normalizedQuery.isEmpty) {
            return true;
          }
          return trip.operatorName.toLowerCase().contains(normalizedQuery) ||
              trip.from.toLowerCase().contains(normalizedQuery) ||
              trip.to.toLowerCase().contains(normalizedQuery) ||
              trip.nextAction.toLowerCase().contains(normalizedQuery);
        })
        .take(limit)
        .toList(growable: false);
    return _responseFor(filtered);
  }

  @override
  Future<CoachAdminDisruptionMutationResult> adminDisruptionAction({
    required String tripId,
    required String action,
    int? delayMinutes,
    String? reason,
    String? note,
    String? idempotencyKey,
  }) async {
    actionCalls++;
    final index = _trips.indexWhere((trip) => trip.tripId == tripId);
    final current = _trips[index];
    final updatedTrip = switch (action) {
      'queue_reaccommodation' => _buildTrip(
          tripId: current.tripId,
          operatorName: current.operatorName,
          from: current.from,
          to: current.to,
          departureAtIso: current.departureAtIso,
          workflowStatus: 'action_required',
          disruptionKind: 'cancelled',
          severity: 'critical',
          affectedBookingCount: current.affectedBookingCount,
          eligibleReaccommodationCount: current.eligibleReaccommodationCount,
          queuedReaccommodationCount: 1,
          feedIssueCount: current.feedIssueCount,
          pendingCount: current.pendingCount,
          reason: 'service was cancelled by operator',
          note: 'Queued change request for affected booking.',
          nextAction: 'Monitor the reissue queue and operator confirmation',
        ),
      'resolve' => _buildTrip(
          tripId: current.tripId,
          operatorName: current.operatorName,
          from: current.from,
          to: current.to,
          departureAtIso: current.departureAtIso,
          workflowStatus: 'resolved',
          disruptionKind: current.disruptionKind,
          severity: current.severity,
          affectedBookingCount: current.affectedBookingCount,
          eligibleReaccommodationCount: current.eligibleReaccommodationCount,
          queuedReaccommodationCount: current.queuedReaccommodationCount,
          feedIssueCount: current.feedIssueCount,
          pendingCount: current.pendingCount,
          delayMinutes: current.delayMinutes,
          reason: current.reason,
          note: current.note,
          nextAction: current.nextAction,
          blockers: current.blockers,
        ),
      _ => _buildTrip(
          tripId: current.tripId,
          operatorName: current.operatorName,
          from: current.from,
          to: current.to,
          departureAtIso: current.departureAtIso,
          workflowStatus: 'action_required',
          disruptionKind: action == 'mark_cancelled' ? 'cancelled' : 'delay',
          severity: action == 'mark_cancelled' ? 'critical' : current.severity,
          affectedBookingCount: current.affectedBookingCount,
          eligibleReaccommodationCount: current.eligibleReaccommodationCount,
          queuedReaccommodationCount: current.queuedReaccommodationCount,
          feedIssueCount: current.feedIssueCount,
          pendingCount: current.pendingCount,
          delayMinutes: action == 'mark_delayed' ? (delayMinutes ?? 45) : null,
          reason: reason,
          note: note ?? current.note,
          nextAction: current.nextAction,
          blockers: current.blockers,
        ),
    };
    _trips[index] = updatedTrip;
    return CoachAdminDisruptionMutationResult(
      tripId: tripId,
      action: action,
      updatedAtIso: '2026-04-14T10:05:00Z',
      queuedChangeRequestIds: action == 'queue_reaccommodation'
          ? const <String>['changereq_demo_border_runner']
          : const <String>[],
      trip: updatedTrip,
    );
  }
}

void main() {
  testWidgets(
    'coach admin disruptions page renders and queues reaccommodation',
    (tester) async {
      configureLargeViewport(tester);
      final api = _FakeCoachAdminDisruptionsApi();

      await tester.pumpWidget(
        MaterialApp(
          home: CoachAdminDisruptionsPage(
            baseUrl: 'https://api.shamell.online',
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.disruptionsCalls, 1);
      expect(find.text('Coach disruptions'), findsOneWidget);
      expect(find.text('Disruption command desk'), findsOneWidget);
      expect(find.textContaining('Border Runner'), findsOneWidget);
      expect(find.text('Queued reaccommodation 0'), findsWidgets);

      final queueButton =
          find.widgetWithText(FilledButton, 'Queue reaccommodation');
      await _dragUntilVisible(tester, queueButton);
      await tester.tap(queueButton);
      await tester.pumpAndSettle();

      expect(api.actionCalls, 1);
      expect(find.text('Queued reaccommodation 1'), findsWidgets);
      expect(find.text('Cancelled'), findsWidgets);
      expect(
        find.text('Monitor the reissue queue and operator confirmation'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'coach admin disruptions page filters local queues and sorts by departure',
    (tester) async {
      configureLargeViewport(tester);
      final api = _FakeCoachAdminDisruptionsApi(
        trips: <CoachAdminDisruptionTrip>[
          _buildTrip(
            tripId: 'trip_border_runner',
            operatorName: 'Border Runner',
            from: 'Homs',
            to: 'Amman',
            departureAtIso: '2026-04-14T05:30:00Z',
            workflowStatus: 'monitoring',
            disruptionKind: 'delay',
            severity: 'medium',
            affectedBookingCount: 1,
            eligibleReaccommodationCount: 1,
            queuedReaccommodationCount: 0,
            feedIssueCount: 1,
            pendingCount: 1,
            delayMinutes: 45,
            reason: 'operator delay above service threshold',
            note: 'Monitoring live delay.',
            nextAction: 'Queue reaccommodation if the delay persists',
          ),
          _buildTrip(
            tripId: 'trip_desert_lines',
            operatorName: 'Desert Lines',
            from: 'Damascus',
            to: 'Aleppo',
            departureAtIso: '2026-04-14T04:30:00Z',
            workflowStatus: 'action_required',
            disruptionKind: 'cancelled',
            severity: 'critical',
            affectedBookingCount: 3,
            eligibleReaccommodationCount: 2,
            queuedReaccommodationCount: 1,
            feedIssueCount: 0,
            pendingCount: 0,
            reason: 'service was cancelled by operator',
            note: 'Queued change request for affected booking.',
            nextAction: 'Confirm passenger fallout and alternate routing',
          ),
          _buildTrip(
            tripId: 'trip_city_link',
            operatorName: 'City Link',
            from: 'Latakia',
            to: 'Tartus',
            departureAtIso: '2026-04-14T03:30:00Z',
            workflowStatus: 'monitoring',
            disruptionKind: 'delay',
            severity: 'low',
            affectedBookingCount: 1,
            eligibleReaccommodationCount: 0,
            queuedReaccommodationCount: 0,
            feedIssueCount: 0,
            pendingCount: 0,
            delayMinutes: 15,
            reason: 'minor traffic delay',
            note: 'Watching departure board.',
            blockers: const <String>[],
            nextAction: 'Watch departure board and operator ETA',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CoachAdminDisruptionsPage(
            baseUrl: 'https://api.shamell.online',
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('coachDisruptionFocus_critical')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Showing 1 of 3 trips'), findsOneWidget);
      expect(find.textContaining('Desert Lines'), findsOneWidget);
      expect(find.textContaining('Border Runner'), findsNothing);
      expect(find.textContaining('City Link'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Departure first'));
      await tester.pumpAndSettle();

      final cityLinkCard = find.byKey(
        const ValueKey('coachDisruptionCard_trip_city_link'),
      );
      final borderRunnerCard = find.byKey(
        const ValueKey('coachDisruptionCard_trip_border_runner'),
      );

      expect(
        tester.getTopLeft(cityLinkCard).dy,
        lessThan(tester.getTopLeft(borderRunnerCard).dy),
      );
      expect(find.textContaining('Showing 3 of 3 trips'), findsOneWidget);
    },
  );
}
