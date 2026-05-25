import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_admin_support_cases_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_platform_contracts.dart';

Future<void> _dragUntilTextVisible(
  WidgetTester tester,
  String text,
) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -280));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeCoachAdminSupportApi extends CoachMobilityApi {
  _FakeCoachAdminSupportApi() : super(baseUrl: 'https://api.shamell.online');

  int listCalls = 0;
  int detailCalls = 0;
  int resolvePaymentFailureCalls = 0;
  String? lastResolvePaymentFailureMethod;
  bool _paymentFailureResolved = false;

  @override
  Future<CoachAdminSupportCasesResponse> adminSupportCases({
    String? query,
    int limit = 20,
  }) async {
    listCalls++;
    return CoachAdminSupportCasesResponse(
      generatedAtIso: '2026-04-13T11:00:00Z',
      summary: CoachAdminSupportCasesSummary(
        totalCases: 3,
        urgentCases: 3,
        refundCases: 1,
        changeCases: 1,
        attentionCases: 2,
        boardedCases: 0,
      ),
      cases: <CoachAdminSupportCaseSummaryRecord>[
        CoachAdminSupportCaseSummaryRecord(
          caseId: 'booking_demo_express_direct',
          bookingId: 'booking_demo_express_direct',
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-13T08:00:00Z',
          arrivalAtIso: '2026-04-13T12:30:00Z',
          bookingState: 'refund_requested',
          caseStatus: 'refund_requested',
          priority: 'high',
          passengerDisplayName: 'Lina Haddad',
          passengerCount: 2,
          contactEmail: 'lina@example.com',
          operatorBookingReference:
              'operator-booking-booking_demo_express_direct',
          paymentAuthorizationReference: 'payauth_demo_express',
          ticketIds: <String>['ticket_demo_1'],
          operatorTicketReferences: <String>['operator-ticket-demo-1'],
          openRequestKinds: <String>['refund_request'],
          needsAttention: true,
          latestActivityAtIso: '2026-04-13T07:15:00Z',
        ),
        CoachAdminSupportCaseSummaryRecord(
          caseId: 'booking_demo_change_payment_failed',
          bookingId: 'booking_demo_change_payment_failed',
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-13T08:00:00Z',
          arrivalAtIso: '2026-04-13T12:30:00Z',
          bookingState: 'ticketed',
          caseStatus: _paymentFailureResolved
              ? 'change_reissued'
              : 'change_payment_failed',
          priority: 'high',
          passengerDisplayName: 'Omar Darwish',
          passengerCount: 1,
          contactEmail: 'omar@example.com',
          operatorBookingReference:
              'operator-booking-booking_demo_change_payment_failed',
          paymentAuthorizationReference: _paymentFailureResolved
              ? 'payauth_demo_change_recovered'
              : 'payauth_demo_change_failed',
          ticketIds: <String>['ticket_change_demo_1'],
          operatorTicketReferences: <String>['operator-ticket-change-demo-1'],
          openRequestKinds: _paymentFailureResolved
              ? const <String>[]
              : const <String>['change_request'],
          needsAttention: !_paymentFailureResolved,
          latestActivityAtIso: _paymentFailureResolved
              ? '2026-04-13T08:12:00Z'
              : '2026-04-13T08:05:00Z',
        ),
        CoachAdminSupportCaseSummaryRecord(
          caseId: 'riskcase_risk_boarding_boarding_demo_1_1234567890',
          bookingId: 'booking_demo_express_direct',
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-13T08:00:00Z',
          arrivalAtIso: '2026-04-13T12:30:00Z',
          bookingState: 'ticketed',
          caseStatus: 'risk_follow_up',
          priority: 'high',
          passengerDisplayName: 'Lina Haddad',
          passengerCount: 2,
          contactEmail: 'lina@example.com',
          operatorBookingReference:
              'operator-booking-booking_demo_express_direct',
          paymentAuthorizationReference: 'payauth_demo_express',
          ticketIds: <String>['ticket_demo_1'],
          operatorTicketReferences: <String>['operator-ticket-demo-1'],
          openRequestKinds: <String>['risk_follow_up'],
          needsAttention: true,
          latestActivityAtIso: '2026-04-13T09:15:00Z',
        ),
      ],
    );
  }

  @override
  Future<CoachAdminSupportCaseDetailResponse> adminSupportCaseDetail(
    String caseId,
  ) async {
    detailCalls++;
    if (caseId == 'booking_demo_change_payment_failed') {
      if (_paymentFailureResolved) {
        return const CoachAdminSupportCaseDetailResponse(
          generatedAtIso: '2026-04-13T11:06:00Z',
          supportCase: CoachAdminSupportCaseSummaryRecord(
            caseId: 'booking_demo_change_payment_failed',
            bookingId: 'booking_demo_change_payment_failed',
            journeyId: 'journey_demo_express_direct',
            operatorName: 'Demo Express',
            from: 'Damascus',
            to: 'Aleppo',
            departureAtIso: '2026-04-13T08:00:00Z',
            arrivalAtIso: '2026-04-13T12:30:00Z',
            bookingState: 'ticketed',
            caseStatus: 'change_reissued',
            priority: 'high',
            passengerDisplayName: 'Omar Darwish',
            passengerCount: 1,
            contactEmail: 'omar@example.com',
            operatorBookingReference:
                'operator-booking-booking_demo_change_payment_failed',
            paymentAuthorizationReference: 'payauth_demo_change_recovered',
            ticketIds: <String>['ticket_change_demo_1_reissued'],
            operatorTicketReferences: <String>[
              'operator-ticket-change-demo-1-reissued',
            ],
            openRequestKinds: <String>[],
            needsAttention: false,
            latestActivityAtIso: '2026-04-13T08:12:00Z',
          ),
          journey: CoachBookedJourneySummary(
            journeyId: 'journey_demo_express_direct',
            operatorName: 'Demo Express',
            from: 'Damascus',
            to: 'Aleppo',
            departureAtIso: '2026-04-13T08:00:00Z',
            arrivalAtIso: '2026-04-13T12:30:00Z',
            statusLabel: 'Change reissued',
          ),
          offer: CoachOffer(
            offerId: 'offer_demo_express_midday',
            operatorId: 'op_demo_express',
            itineraryId: 'journey_demo_express_direct',
            currency: 'SYP',
            totalMinorUnits: 9980,
            seatsRequested: 1,
            holdSupported: true,
            changeable: true,
            refundable: true,
            expiresAtIso: '2026-04-13T07:00:00Z',
          ),
          hold: CoachHold(
            holdId: 'hold_demo_change_payment_failed',
            offerId: 'offer_demo_express_midday',
            operatorReference: 'operator-hold_demo_change_payment_failed',
            expiresAtIso: '2026-04-13T07:10:00Z',
            status: CoachHoldStatus.converted,
            seatAssignments: <CoachSeatAssignment>[
              CoachSeatAssignment(passengerId: 'adult_2', seatNumber: '5B'),
            ],
          ),
          booking: CoachBooking(
            bookingId: 'booking_demo_change_payment_failed',
            offerId: 'offer_demo_express_midday',
            holdId: 'hold_demo_change_payment_failed',
            operatorBookingReference:
                'operator-booking-booking_demo_change_payment_failed',
            state: CoachBookingLifecycleState.ticketed,
            currency: 'SYP',
            totalMinorUnits: 9980,
            passengerCount: 1,
            createdAtIso: '2026-04-13T06:30:00Z',
          ),
          payment: CoachPaymentAuthorization(
            status: 'authorized',
            method: 'card',
            authorizationReference: 'payauth_demo_change_recovered',
            currency: 'SYP',
            chargedMinorUnits: 1300,
          ),
          compensation: CoachCompensationState(
            state: 'resolved',
            action: 'reissue_completed',
            supportQueue: 'coach_rebook_queue',
            triggered: false,
            reason: null,
            recoveryReference: null,
          ),
          passengerManifests: <CoachPassengerManifest>[
            CoachPassengerManifest(
              passengerId: 'adult_2',
              givenName: 'Omar',
              familyName: 'Darwish',
              riderCategory: CoachPassengerRiderCategory.student,
              nationalityCode: 'DE',
            ),
          ],
          tickets: <CoachTicketCoupon>[
            CoachTicketCoupon(
              ticketId: 'ticket_change_demo_1_reissued',
              bookingId: 'booking_demo_change_payment_failed',
              couponId: 'coupon-ticket_change_demo_1_reissued',
              passengerId: 'adult_2',
              segmentIds: <String>['seg_change_demo_midday_1'],
              status: CoachTicketStatus.active,
              operatorTicketReference: 'operator-ticket-change-demo-1-reissued',
              qrPayloadRef:
                  'object://coach/tickets/ticket_change_demo_1_reissued/qr',
              issuedAtIso: '2026-04-13T08:10:30Z',
              revokedAtIso: null,
            ),
          ],
          ticketArtifacts: <CoachTicketArtifact>[],
          refundRequest: null,
          changeRequest: CoachChangeRequestRecord(
            changeRequestId: 'changereq_demo_failed_1',
            bookingId: 'booking_demo_change_payment_failed',
            status: 'reissued',
            targetOfferId: 'offer_demo_express_midday',
            currency: 'SYP',
            fareDifferenceMinorUnits: 800,
            changeFeeMinorUnits: 500,
            totalDueMinorUnits: 1300,
            reason: 'move to midday departure',
            createdAtIso: '2026-04-13T08:10:00Z',
          ),
          recentBoardingEvents: <CoachBoardingEvent>[],
          operatorFeedHealth: <CoachOperatorFeedHealth>[],
          timeline: <CoachSupportCaseTimelineEvent>[
            CoachSupportCaseTimelineEvent(
              eventId: 'booking_demo_change_payment_failed|change_reissued',
              eventType: 'change_reissued',
              title: 'Change reissued',
              occurredAtIso: '2026-04-13T08:10:00Z',
              statusLabel: 'reissued',
              detailLines: <String>[
                'Target offer offer_demo_express_midday',
                'Total due 1300 SYP',
                'Payment collected via card',
              ],
            ),
          ],
        );
      }
      return const CoachAdminSupportCaseDetailResponse(
        generatedAtIso: '2026-04-13T11:03:00Z',
        supportCase: CoachAdminSupportCaseSummaryRecord(
          caseId: 'booking_demo_change_payment_failed',
          bookingId: 'booking_demo_change_payment_failed',
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-13T08:00:00Z',
          arrivalAtIso: '2026-04-13T12:30:00Z',
          bookingState: 'ticketed',
          caseStatus: 'change_payment_failed',
          priority: 'high',
          passengerDisplayName: 'Omar Darwish',
          passengerCount: 1,
          contactEmail: 'omar@example.com',
          operatorBookingReference:
              'operator-booking-booking_demo_change_payment_failed',
          paymentAuthorizationReference: 'payauth_demo_change_failed',
          ticketIds: <String>['ticket_change_demo_1'],
          operatorTicketReferences: <String>['operator-ticket-change-demo-1'],
          openRequestKinds: <String>['change_request'],
          needsAttention: false,
          latestActivityAtIso: '2026-04-13T08:05:00Z',
        ),
        journey: CoachBookedJourneySummary(
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-13T08:00:00Z',
          arrivalAtIso: '2026-04-13T12:30:00Z',
          statusLabel: 'Change payment failed',
        ),
        offer: CoachOffer(
          offerId: 'offer_demo_express_direct',
          operatorId: 'op_demo_express',
          itineraryId: 'journey_demo_express_direct',
          currency: 'SYP',
          totalMinorUnits: 9180,
          seatsRequested: 1,
          holdSupported: true,
          changeable: true,
          refundable: true,
          expiresAtIso: '2026-04-13T07:00:00Z',
        ),
        hold: CoachHold(
          holdId: 'hold_demo_change_payment_failed',
          offerId: 'offer_demo_express_direct',
          operatorReference: 'operator-hold_demo_change_payment_failed',
          expiresAtIso: '2026-04-13T07:10:00Z',
          status: CoachHoldStatus.converted,
          seatAssignments: <CoachSeatAssignment>[
            CoachSeatAssignment(passengerId: 'adult_2', seatNumber: '5B'),
          ],
        ),
        booking: CoachBooking(
          bookingId: 'booking_demo_change_payment_failed',
          offerId: 'offer_demo_express_direct',
          holdId: 'hold_demo_change_payment_failed',
          operatorBookingReference:
              'operator-booking-booking_demo_change_payment_failed',
          state: CoachBookingLifecycleState.ticketed,
          currency: 'SYP',
          totalMinorUnits: 9180,
          passengerCount: 1,
          createdAtIso: '2026-04-13T06:30:00Z',
        ),
        payment: CoachPaymentAuthorization(
          status: 'failed',
          method: 'wallet_credit',
          authorizationReference: 'payauth_demo_change_failed',
          currency: 'SYP',
          chargedMinorUnits: 0,
        ),
        compensation: CoachCompensationState(
          state: 'triggered',
          action: 'retry_collection_or_raise_support_case',
          supportQueue: 'coach_rebook_queue',
          triggered: true,
          reason: 'wallet_credit_insufficient',
          recoveryReference: 'recovery_demo_change_payment',
        ),
        passengerManifests: <CoachPassengerManifest>[
          CoachPassengerManifest(
            passengerId: 'adult_2',
            givenName: 'Omar',
            familyName: 'Darwish',
            riderCategory: CoachPassengerRiderCategory.student,
            nationalityCode: 'DE',
          ),
        ],
        tickets: <CoachTicketCoupon>[
          CoachTicketCoupon(
            ticketId: 'ticket_change_demo_1',
            bookingId: 'booking_demo_change_payment_failed',
            couponId: 'coupon-ticket_change_demo_1',
            passengerId: 'adult_2',
            segmentIds: <String>['seg_change_demo_1'],
            status: CoachTicketStatus.active,
            operatorTicketReference: 'operator-ticket-change-demo-1',
            qrPayloadRef: 'object://coach/tickets/ticket_change_demo_1/qr',
            issuedAtIso: '2026-04-13T06:35:00Z',
            revokedAtIso: null,
          ),
        ],
        ticketArtifacts: <CoachTicketArtifact>[],
        refundRequest: null,
        changeRequest: CoachChangeRequestRecord(
          changeRequestId: 'changereq_demo_failed_1',
          bookingId: 'booking_demo_change_payment_failed',
          status: 'payment_failed',
          targetOfferId: 'offer_demo_express_midday',
          currency: 'SYP',
          fareDifferenceMinorUnits: 800,
          changeFeeMinorUnits: 500,
          totalDueMinorUnits: 1300,
          reason: 'move to midday departure',
          createdAtIso: '2026-04-13T08:00:00Z',
        ),
        recentBoardingEvents: <CoachBoardingEvent>[],
        operatorFeedHealth: <CoachOperatorFeedHealth>[],
        timeline: <CoachSupportCaseTimelineEvent>[
          CoachSupportCaseTimelineEvent(
            eventId: 'booking_demo_change_payment_failed|change_payment_failed',
            eventType: 'change_payment_failed',
            title: 'Change payment failed',
            occurredAtIso: '2026-04-13T08:00:00Z',
            statusLabel: 'payment_failed',
            detailLines: <String>[
              'Target offer offer_demo_express_midday',
              'Total due 1300 SYP',
              'Reason move to midday departure',
              'Failure reason wallet_credit_insufficient',
              'Recovery recovery_demo_change_payment',
            ],
          ),
        ],
      );
    }
    if (caseId == 'riskcase_risk_boarding_boarding_demo_1_1234567890') {
      return const CoachAdminSupportCaseDetailResponse(
        generatedAtIso: '2026-04-13T11:05:00Z',
        supportCase: CoachAdminSupportCaseSummaryRecord(
          caseId: 'riskcase_risk_boarding_boarding_demo_1_1234567890',
          bookingId: 'booking_demo_express_direct',
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-13T08:00:00Z',
          arrivalAtIso: '2026-04-13T12:30:00Z',
          bookingState: 'ticketed',
          caseStatus: 'risk_follow_up',
          priority: 'high',
          passengerDisplayName: 'Lina Haddad',
          passengerCount: 2,
          contactEmail: 'lina@example.com',
          operatorBookingReference:
              'operator-booking-booking_demo_express_direct',
          paymentAuthorizationReference: 'payauth_demo_express',
          ticketIds: <String>['ticket_demo_1'],
          operatorTicketReferences: <String>['operator-ticket-demo-1'],
          openRequestKinds: <String>['risk_follow_up'],
          needsAttention: true,
          latestActivityAtIso: '2026-04-13T09:15:00Z',
        ),
        journey: CoachBookedJourneySummary(
          journeyId: 'journey_demo_express_direct',
          operatorName: 'Demo Express',
          from: 'Damascus',
          to: 'Aleppo',
          departureAtIso: '2026-04-13T08:00:00Z',
          arrivalAtIso: '2026-04-13T12:30:00Z',
          statusLabel: 'Boarding follow-up',
        ),
        offer: CoachOffer(
          offerId: 'offer_demo_express_direct',
          operatorId: 'op_demo_express',
          itineraryId: 'journey_demo_express_direct',
          currency: 'SYP',
          totalMinorUnits: 9180,
          seatsRequested: 2,
          holdSupported: true,
          changeable: true,
          refundable: true,
          expiresAtIso: '2026-04-13T07:00:00Z',
        ),
        hold: null,
        booking: CoachBooking(
          bookingId: 'booking_demo_express_direct',
          offerId: 'offer_demo_express_direct',
          holdId: 'hold_demo_express_direct',
          operatorBookingReference:
              'operator-booking-booking_demo_express_direct',
          state: CoachBookingLifecycleState.ticketed,
          currency: 'SYP',
          totalMinorUnits: 9180,
          passengerCount: 2,
          createdAtIso: '2026-04-13T06:30:00Z',
        ),
        payment: null,
        compensation: null,
        passengerManifests: <CoachPassengerManifest>[],
        tickets: <CoachTicketCoupon>[],
        ticketArtifacts: <CoachTicketArtifact>[],
        refundRequest: null,
        changeRequest: null,
        recentBoardingEvents: <CoachBoardingEvent>[],
        operatorFeedHealth: <CoachOperatorFeedHealth>[],
        timeline: <CoachSupportCaseTimelineEvent>[
          CoachSupportCaseTimelineEvent(
            eventId: 'riskcase_risk_boarding_boarding_demo_1_1234567890',
            eventType: 'risk_follow_up_auto_case',
            title: 'Risk follow-up auto-case created',
            occurredAtIso: '2026-04-13T09:15:00Z',
            statusLabel: 'overdue',
            detailLines: <String>[
              'Risk risk_boarding_boarding_demo_1',
              'Duplicate boarding scan detected',
            ],
          ),
        ],
      );
    }
    return const CoachAdminSupportCaseDetailResponse(
      generatedAtIso: '2026-04-13T11:01:00Z',
      supportCase: CoachAdminSupportCaseSummaryRecord(
        caseId: 'booking_demo_express_direct',
        bookingId: 'booking_demo_express_direct',
        journeyId: 'journey_demo_express_direct',
        operatorName: 'Demo Express',
        from: 'Damascus',
        to: 'Aleppo',
        departureAtIso: '2026-04-13T08:00:00Z',
        arrivalAtIso: '2026-04-13T12:30:00Z',
        bookingState: 'refund_requested',
        caseStatus: 'refund_requested',
        priority: 'high',
        passengerDisplayName: 'Lina Haddad',
        passengerCount: 2,
        contactEmail: 'lina@example.com',
        operatorBookingReference:
            'operator-booking-booking_demo_express_direct',
        paymentAuthorizationReference: 'payauth_demo_express',
        ticketIds: <String>['ticket_demo_1'],
        operatorTicketReferences: <String>['operator-ticket-demo-1'],
        openRequestKinds: <String>['refund_request'],
        needsAttention: true,
        latestActivityAtIso: '2026-04-13T07:15:00Z',
      ),
      journey: CoachBookedJourneySummary(
        journeyId: 'journey_demo_express_direct',
        operatorName: 'Demo Express',
        from: 'Damascus',
        to: 'Aleppo',
        departureAtIso: '2026-04-13T08:00:00Z',
        arrivalAtIso: '2026-04-13T12:30:00Z',
        statusLabel: 'Refund pending',
      ),
      offer: CoachOffer(
        offerId: 'offer_demo_express_direct',
        operatorId: 'op_demo_express',
        itineraryId: 'journey_demo_express_direct',
        currency: 'SYP',
        totalMinorUnits: 9180,
        seatsRequested: 2,
        holdSupported: true,
        changeable: true,
        refundable: true,
        expiresAtIso: '2026-04-13T07:00:00Z',
      ),
      hold: CoachHold(
        holdId: 'hold_demo_express_direct',
        offerId: 'offer_demo_express_direct',
        operatorReference: 'operator-hold_demo_express_direct',
        expiresAtIso: '2026-04-13T07:10:00Z',
        status: CoachHoldStatus.converted,
        seatAssignments: <CoachSeatAssignment>[
          CoachSeatAssignment(passengerId: 'adult_1', seatNumber: '4A'),
        ],
      ),
      booking: CoachBooking(
        bookingId: 'booking_demo_express_direct',
        offerId: 'offer_demo_express_direct',
        holdId: 'hold_demo_express_direct',
        operatorBookingReference:
            'operator-booking-booking_demo_express_direct',
        state: CoachBookingLifecycleState.refundRequested,
        currency: 'SYP',
        totalMinorUnits: 9180,
        passengerCount: 2,
        createdAtIso: '2026-04-13T06:30:00Z',
      ),
      payment: CoachPaymentAuthorization(
        status: 'authorized',
        method: 'card',
        authorizationReference: 'payauth_demo_express',
        currency: 'SYP',
        chargedMinorUnits: 9180,
      ),
      compensation: CoachCompensationState(
        state: 'armed',
        action: 'issue_refund_credit_or_raise_finance_case',
        supportQueue: 'coach_refund_queue',
        triggered: false,
        reason: null,
        recoveryReference: null,
      ),
      passengerManifests: <CoachPassengerManifest>[
        CoachPassengerManifest(
          passengerId: 'adult_1',
          givenName: 'Lina',
          familyName: 'Haddad',
          riderCategory: CoachPassengerRiderCategory.adult,
          nationalityCode: 'SY',
        ),
      ],
      tickets: <CoachTicketCoupon>[
        CoachTicketCoupon(
          ticketId: 'ticket_demo_1',
          bookingId: 'booking_demo_express_direct',
          couponId: 'coupon-ticket_demo_1',
          passengerId: 'adult_1',
          segmentIds: <String>['seg_1'],
          status: CoachTicketStatus.active,
          boardingState: CoachManifestBoardingState.denied,
          operatorTicketReference: 'operator-ticket-demo-1',
          qrPayloadRef: 'object://coach/tickets/ticket_demo_1/qr',
          issuedAtIso: '2026-04-13T06:35:00Z',
          revokedAtIso: null,
        ),
      ],
      ticketArtifacts: <CoachTicketArtifact>[
        CoachTicketArtifact(
          artifactId: 'ticketartifact_demo_1',
          ticketId: 'ticket_demo_1',
          bookingId: 'booking_demo_express_direct',
          artifactKind: 'pdf',
          deliveryChannel: 'pdf',
          fileName: 'ticket_demo_1.pdf',
          mimeType: 'application/pdf',
          contentLengthBytes: 32768,
          downloadPath: '/downloads/coach/tickets/ticket_demo_1.pdf',
        ),
      ],
      refundRequest: CoachRefundRequestRecord(
        refundRequestId: 'refundreq_demo_1',
        bookingId: 'booking_demo_express_direct',
        status: 'requested',
        selectedKind: CoachRefundKind.refundCredit,
        currency: 'SYP',
        requestedMinorUnits: 9180,
        feeMinorUnits: 0,
        ticketIds: <String>['ticket_demo_1'],
        reason: 'customer changed plans',
        createdAtIso: '2026-04-13T06:40:00Z',
      ),
      changeRequest: null,
      recentBoardingEvents: <CoachBoardingEvent>[
        CoachBoardingEvent(
          boardingEventId: 'boarding_demo_1',
          ticketId: 'ticket_demo_1',
          tripId: 'trip_demo_express_direct',
          scanStatus: CoachBoardingScanStatus.denied,
          capturedAtIso: '2026-04-13T07:15:00Z',
          offlineCaptured: false,
          deviceId: 'scanner-1',
          note: 'duplicate screenshot',
        ),
      ],
      operatorFeedHealth: <CoachOperatorFeedHealth>[
        CoachOperatorFeedHealth(
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          operatorIntegrationMode: 'hybrid',
          feedKind: 'gtfs_rt_trip_updates',
          sourceKind: 'gtfs_rt',
          syncStatus: 'ok',
          freshnessStatus: 'fresh',
          lastAttemptedAtIso: '2026-04-13T10:25:00Z',
          lastSucceededAtIso: '2026-04-13T10:25:00Z',
          freshnessExpiresAtIso: '2026-04-13T10:26:30Z',
          recordsIngested: 4,
          errorMessage: null,
        ),
      ],
      timeline: <CoachSupportCaseTimelineEvent>[
        CoachSupportCaseTimelineEvent(
          eventId: 'booking_created',
          eventType: 'booking_created',
          title: 'Booking created',
          occurredAtIso: '2026-04-13T06:30:00Z',
          statusLabel: 'Boarding pass ready',
          detailLines: <String>[
            'Booking booking_demo_express_direct',
            'Payment payauth_demo_express via card',
          ],
        ),
        CoachSupportCaseTimelineEvent(
          eventId: 'refund_requested',
          eventType: 'refund_requested',
          title: 'Refund requested',
          occurredAtIso: '2026-04-13T06:40:00Z',
          statusLabel: 'pending_review',
          detailLines: <String>[
            '9180 SYP requested',
            'Reason customer changed plans',
          ],
        ),
      ],
    );
  }

  @override
  Future<CoachSelfServiceReissueResult> adminResolveSupportCasePaymentFailure({
    required String caseId,
    required String paymentMethod,
    List<String>? deliveryChannels,
    String? note,
    String? idempotencyKey,
  }) async {
    resolvePaymentFailureCalls++;
    lastResolvePaymentFailureMethod = paymentMethod;
    _paymentFailureResolved = paymentMethod == 'card';
    return CoachSelfServiceReissueResult(
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-admin-support-recovery-fake',
        scope: 'coach_ticket_reissue_recovery',
        requestFingerprint: 'fp_ticket_reissue_recovery_admin_fake',
        replayed: false,
        derivedKeys: const <String, String>{
          'ticket_reissue': 'coach_ticket_reissue_upstream.fake',
          'wallet_artifact': 'coach_wallet_artifact.fake',
        },
      ),
      booking: CoachBooking(
        bookingId: caseId,
        offerId: _paymentFailureResolved
            ? 'offer_demo_express_midday'
            : 'offer_demo_express_direct',
        holdId: 'hold_demo_change_payment_failed',
        operatorBookingReference:
            'operator-booking-booking_demo_change_payment_failed',
        state: CoachBookingLifecycleState.ticketed,
        currency: 'SYP',
        totalMinorUnits: _paymentFailureResolved ? 9980 : 9180,
        passengerCount: 1,
        createdAtIso: '2026-04-13T06:30:00Z',
      ),
      changeRequest: CoachChangeRequestRecord(
        changeRequestId: 'changereq_demo_failed_1',
        bookingId: caseId,
        status: _paymentFailureResolved ? 'reissued' : 'payment_failed',
        targetOfferId: 'offer_demo_express_midday',
        currency: 'SYP',
        fareDifferenceMinorUnits: 800,
        changeFeeMinorUnits: 500,
        totalDueMinorUnits: 1300,
        reason: 'move to midday departure',
        createdAtIso: '2026-04-13T08:10:00Z',
      ),
      passengerManifests: const <CoachPassengerManifest>[
        CoachPassengerManifest(
          passengerId: 'adult_2',
          givenName: 'Omar',
          familyName: 'Darwish',
          riderCategory: CoachPassengerRiderCategory.student,
          nationalityCode: 'DE',
        ),
      ],
      tickets: const <CoachTicketCoupon>[
        CoachTicketCoupon(
          ticketId: 'ticket_change_demo_1_reissued',
          bookingId: 'booking_demo_change_payment_failed',
          couponId: 'coupon-ticket_change_demo_1_reissued',
          passengerId: 'adult_2',
          segmentIds: <String>['seg_change_demo_midday_1'],
          status: CoachTicketStatus.active,
          operatorTicketReference: 'operator-ticket-change-demo-1-reissued',
          qrPayloadRef:
              'object://coach/tickets/ticket_change_demo_1_reissued/qr',
          issuedAtIso: '2026-04-13T08:10:30Z',
          revokedAtIso: null,
        ),
      ],
      deliveryChannels:
          deliveryChannels ?? const <String>['wallet_pass', 'pdf'],
      payment: CoachPaymentAuthorization(
        status: _paymentFailureResolved ? 'authorized' : 'failed',
        method: paymentMethod,
        authorizationReference: _paymentFailureResolved
            ? 'payauth_demo_change_recovered'
            : 'payauth_demo_change_failed',
        currency: 'SYP',
        chargedMinorUnits: _paymentFailureResolved ? 1300 : 0,
      ),
      compensation: CoachCompensationState(
        state: _paymentFailureResolved ? 'resolved' : 'triggered',
        action: _paymentFailureResolved
            ? 'reissue_completed'
            : 'retry_collection_or_raise_support_case',
        supportQueue: 'coach_rebook_queue',
        triggered: !_paymentFailureResolved,
        reason: _paymentFailureResolved ? null : 'wallet_credit_insufficient',
        recoveryReference:
            _paymentFailureResolved ? null : 'recovery_demo_change_payment',
      ),
      nextAction:
          _paymentFailureResolved ? 'completed' : 'resolve_payment_failure',
    );
  }
}

void main() {
  testWidgets('coach admin support cases page renders list and detail',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminSupportApi();
    final response = await api.adminSupportCases();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminSupportCasesPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.listCalls, greaterThanOrEqualTo(1));
    expect(find.text('Coach support'), findsOneWidget);
    expect(find.text('Cases 3'), findsOneWidget);
    expect(find.text('Urgent 3'), findsOneWidget);
    expect(find.text('Changes 1'), findsOneWidget);
    expect(find.text('Payment failures 1'), findsOneWidget);
    expect(find.text('Support command desk'), findsOneWidget);
    expect(find.textContaining('Lina Haddad'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Omar Darwish'), findsOneWidget);
    expect(find.textContaining('booking_demo_express_direct'),
        findsAtLeastNWidgets(1));
    await _dragUntilTextVisible(tester, 'Risk follow-up');
    expect(find.textContaining('Risk follow-up'), findsWidgets);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'coachSupportCaseCard_riskcase_risk_boarding_boarding_demo_1_1234567890',
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.detailCalls, 1);
    expect(find.text('References'), findsOneWidget);
    expect(find.text('Risk follow-up auto-case created'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Timeline');
    expect(find.text('Timeline'), findsOneWidget);
    await _dragUntilTextVisible(tester, 'Duplicate boarding scan detected');
    expect(find.text('Duplicate boarding scan detected'), findsOneWidget);
  });

  testWidgets('coach admin support cases page surfaces change payment failure',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminSupportApi();
    final response = await api.adminSupportCases();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminSupportCasesPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'coachSupportCaseCard_booking_demo_change_payment_failed',
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Change payment failed'), findsAtLeastNWidgets(1));
    expect(
      find.text(
        'Collection failed for this change. Retry payment or move it into manual follow-up.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Payment failed • payauth_demo_change_failed'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Compensation triggered • retry_collection_or_raise_support_case',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Reason wallet_credit_insufficient'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.textContaining('Recovery recovery_demo_change_payment'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets(
      'coach admin support cases page can recover failed change collection',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminSupportApi();
    final response = await api.adminSupportCases();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminSupportCasesPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'coachSupportCaseCard_booking_demo_change_payment_failed',
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await _dragUntilTextVisible(tester, 'Retry collection and reissue');
    await tester.tap(find.text('Retry collection and reissue'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.resolvePaymentFailureCalls, 1);
    expect(api.lastResolvePaymentFailureMethod, 'card');
    expect(
        find.text('Payment recovered and tickets reissued.'), findsOneWidget);
    expect(find.textContaining('Result reissued • completed'), findsOneWidget);
    expect(
      find.textContaining('Payment authorized • card • 13.00 SYP'),
      findsOneWidget,
    );
    expect(find.text('Change reissued'), findsAtLeastNWidgets(1));
  });

  testWidgets('coach admin support cases page filters local queues',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminSupportApi();
    final response = await api.adminSupportCases();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminSupportCasesPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Showing 3 of 3 cases'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Payment failures (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 cases'), findsOneWidget);
    expect(find.textContaining('Omar Darwish'), findsOneWidget);
    expect(find.textContaining('Lina Haddad'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Risk (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 cases'), findsOneWidget);
    expect(find.textContaining('Lina Haddad'), findsOneWidget);
    expect(find.textContaining('Omar Darwish'), findsNothing);
  });

  testWidgets(
      'coach admin support cases page supports focus queues and latest activity sort',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachAdminSupportApi();
    final response = await api.adminSupportCases();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachAdminSupportCasesPage(
          baseUrl: 'https://api.shamell.online',
          api: api,
          initialResponse: response,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Support command desk'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coachSupportFocus_risk')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 cases'), findsOneWidget);
    expect(find.textContaining('Lina Haddad'), findsOneWidget);
    expect(find.textContaining('Omar Darwish'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Latest activity'));
    await tester.pumpAndSettle();

    final riskCard = find.byKey(
      const ValueKey(
        'coachSupportCaseCard_riskcase_risk_boarding_boarding_demo_1_1234567890',
      ),
    );
    final refundCard = find.byKey(
      const ValueKey('coachSupportCaseCard_booking_demo_express_direct'),
    );

    expect(
      tester.getTopLeft(riskCard).dy,
      lessThan(tester.getTopLeft(refundCard).dy),
    );
    expect(find.text('Showing 3 of 3 cases'), findsOneWidget);
  });
}
