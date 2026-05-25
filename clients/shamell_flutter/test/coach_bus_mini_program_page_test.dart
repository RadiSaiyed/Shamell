import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_bus_mini_program_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_platform_contracts.dart';

class _FakeCoachMobilityApi extends CoachMobilityApi {
  _FakeCoachMobilityApi() : super(baseUrl: 'https://api.shamell.online');

  int bootstrapCalls = 0;
  int bookingListCalls = 0;
  int journeyLiveCalls = 0;
  int refundEligibilityCalls = 0;
  int refundRequestCalls = 0;
  int changeOptionsCalls = 0;
  int rebookRequestCalls = 0;
  int selfServiceReissueCalls = 0;
  int resolvePaymentFailureCalls = 0;
  int searchCalls = 0;
  int offerCalls = 0;
  int holdCalls = 0;
  int bookingCalls = 0;
  int ticketCalls = 0;
  List<String>? lastHoldPassengerIds;
  List<String>? lastHoldPreferredSeatNumbers;
  List<String>? lastBookingPassengerIds;
  List<String>? lastBookingPreferredSeatNumbers;
  List<CoachPassengerManifest>? lastBookingPassengerManifests;
  String? lastBookingPaymentMethod;
  String? lastBookingContactEmail;
  List<String>? lastTicketPassengerIds;
  List<CoachPassengerManifest>? lastTicketPassengerManifests;
  List<String>? lastTicketDeliveryChannels;
  CoachRefundKind? lastRefundKind;
  List<String>? lastRefundTicketIds;
  String? lastRefundReason;
  String? lastRebookTargetOfferId;
  List<String>? lastRebookPreferredSeatNumbers;
  String? lastRebookReason;
  String? lastReissueTargetOfferId;
  List<String>? lastReissuePreferredSeatNumbers;
  List<String>? lastReissueDeliveryChannels;
  String? lastReissuePaymentMethod;
  String? lastReissueReason;
  String? lastResolvePaymentFailureMethod;
  bool _ticketReissued = false;

  @override
  Future<CoachPlatformBootstrap> bootstrap() async {
    bootstrapCalls++;
    return const CoachPlatformBootstrap(
      version: '2026-04-07',
      surfaces: <String>['passenger', 'operator', 'crew', 'admin'],
      commercialBoundaries: <String>[
        'offer',
        'booking',
        'ticket',
        'boarding',
        'settlement',
      ],
      integrationModes: <String>['feed', 'api', 'hybrid'],
      staticCatalogFeeds: <String>['gtfs', 'netex'],
      realtimeFeeds: <String>['gtfs_rt_trip_updates', 'siri'],
      bookingStates: <String>['offer_created', 'ticketed'],
      walletBuckets: <String>[
        'cash_balance',
        'promo_credit',
        'refund_credit',
        'gift_card_credit',
        'corporate_credit',
      ],
      settlementBases: <String>['ticketed', 'boarded'],
      tripUpdatesFreshnessSeconds: 90,
      vehiclePositionsFreshnessSeconds: 90,
      serviceAlertsFreshnessSeconds: 600,
      operatorFeedHealth: <CoachOperatorFeedHealth>[
        CoachOperatorFeedHealth(
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          operatorIntegrationMode: 'hybrid',
          feedKind: 'gtfs_rt_trip_updates',
          sourceKind: 'gtfs_rt',
          syncStatus: 'ok',
          freshnessStatus: 'fresh',
          lastAttemptedAtIso: '2026-04-09T07:55:00Z',
          lastSucceededAtIso: '2026-04-09T07:55:00Z',
          freshnessExpiresAtIso: '2026-04-09T07:56:30Z',
          recordsIngested: 4,
          errorMessage: null,
        ),
        CoachOperatorFeedHealth(
          operatorId: 'op_northern_connector',
          operatorName: 'Northern Connector',
          operatorIntegrationMode: 'feed',
          feedKind: 'gtfs_rt_vehicle_positions',
          sourceKind: 'gtfs_rt',
          syncStatus: 'degraded',
          freshnessStatus: 'missing',
          lastAttemptedAtIso: '2026-04-09T07:40:00Z',
          lastSucceededAtIso: null,
          freshnessExpiresAtIso: null,
          recordsIngested: 0,
          errorMessage: 'vehicle positions not exposed',
        ),
      ],
    );
  }

  @override
  Future<CoachBookingShelfResponse> listBookings() async {
    bookingListCalls++;
    final reissuedSeatNumbers =
        lastReissuePreferredSeatNumbers ?? const <String>['4A', '4B'];
    final reissueToMidday =
        lastReissueTargetOfferId == 'offer_demo_express_midday';
    final firstJourney = _ticketReissued
        ? CoachBookedJourneySummary(
            journeyId: reissueToMidday
                ? 'journey_demo_express_midday'
                : 'journey_demo_express_evening',
            operatorName: 'Demo Express',
            from: 'Damascus',
            to: 'Aleppo',
            departureAtIso: reissueToMidday
                ? '2026-04-08T12:00:00Z'
                : '2026-04-08T18:00:00Z',
            arrivalAtIso: reissueToMidday
                ? '2026-04-08T16:30:00Z'
                : '2026-04-08T22:30:00Z',
            statusLabel: 'Boarding pass reissued',
          )
        : const CoachBookedJourneySummary(
            journeyId: 'journey_demo_express_direct',
            operatorName: 'Demo Express',
            from: 'Damascus',
            to: 'Aleppo',
            departureAtIso: '2026-04-08T08:00:00Z',
            arrivalAtIso: '2026-04-08T12:30:00Z',
            statusLabel: 'Boarding pass ready',
          );
    final firstOffer = _ticketReissued
        ? CoachOffer(
            offerId: reissueToMidday
                ? 'offer_demo_express_midday'
                : 'offer_demo_express_evening',
            operatorId: 'op_demo_express',
            itineraryId: 'iti_demo_direct',
            currency: 'SYP',
            totalMinorUnits: reissueToMidday ? 9980 : 8880,
            seatsRequested: 2,
            holdSupported: true,
            changeable: true,
            refundable: true,
            expiresAtIso: '2026-04-07T12:05:00Z',
          )
        : const CoachOffer(
            offerId: 'offer_demo_express_direct',
            operatorId: 'op_demo_express',
            itineraryId: 'iti_demo_direct',
            currency: 'SYP',
            totalMinorUnits: 9180,
            seatsRequested: 2,
            holdSupported: true,
            changeable: true,
            refundable: true,
            expiresAtIso: '2026-04-07T12:05:00Z',
          );
    final firstHold = CoachHold(
      holdId: _ticketReissued
          ? 'hold_booking_demo_express_direct_reissue'
          : 'hold_demo_express_direct',
      offerId: _ticketReissued
          ? (reissueToMidday
              ? 'offer_demo_express_midday'
              : 'offer_demo_express_evening')
          : 'offer_demo_express_direct',
      operatorReference: _ticketReissued
          ? 'operator-hold_booking_demo_express_direct_reissue'
          : 'operator-hold_demo_express_direct',
      expiresAtIso: '2026-04-07T12:04:30Z',
      status: CoachHoldStatus.converted,
      seatAssignments: <CoachSeatAssignment>[
        CoachSeatAssignment(
          passengerId: 'adult_1',
          seatNumber: reissuedSeatNumbers[0],
        ),
        CoachSeatAssignment(
          passengerId: 'adult_2',
          seatNumber:
              reissuedSeatNumbers.length > 1 ? reissuedSeatNumbers[1] : '4B',
        ),
      ],
    );
    final firstBooking = _ticketReissued
        ? CoachBooking(
            bookingId: 'booking_demo_express_direct',
            offerId: reissueToMidday
                ? 'offer_demo_express_midday'
                : 'offer_demo_express_evening',
            holdId: 'hold_booking_demo_express_direct_reissue',
            operatorBookingReference:
                'operator-booking-booking_demo_express_direct',
            state: CoachBookingLifecycleState.ticketed,
            currency: 'SYP',
            totalMinorUnits: reissueToMidday ? 9980 : 8880,
            passengerCount: 2,
            createdAtIso: '2026-04-07T12:06:00Z',
          )
        : const CoachBooking(
            bookingId: 'booking_demo_express_direct',
            offerId: 'offer_demo_express_direct',
            holdId: 'hold_demo_express_direct',
            operatorBookingReference:
                'operator-booking-booking_demo_express_direct',
            state: CoachBookingLifecycleState.ticketed,
            currency: 'SYP',
            totalMinorUnits: 9180,
            passengerCount: 2,
            createdAtIso: '2026-04-07T12:06:00Z',
          );
    final firstTickets = _ticketReissued
        ? <CoachTicketCoupon>[
            CoachTicketCoupon(
              ticketId: 'ticket_booking_demo_express_direct_reissue_1',
              bookingId: 'booking_demo_express_direct',
              couponId: 'coupon-ticket_booking_demo_express_direct_reissue_1',
              passengerId: 'adult_1',
              segmentIds: <String>[
                reissueToMidday
                    ? 'seg_booking_demo_express_midday_1'
                    : 'seg_booking_demo_express_evening_1',
              ],
              status: CoachTicketStatus.active,
              operatorTicketReference:
                  'operator-ticket-ticket_booking_demo_express_direct_reissue_1',
              qrPayloadRef:
                  'object://coach/tickets/ticket_booking_demo_express_direct_reissue_1/qr',
              issuedAtIso: '2026-04-07T13:20:00Z',
              revokedAtIso: null,
            ),
            CoachTicketCoupon(
              ticketId: 'ticket_booking_demo_express_direct_reissue_2',
              bookingId: 'booking_demo_express_direct',
              couponId: 'coupon-ticket_booking_demo_express_direct_reissue_2',
              passengerId: 'adult_2',
              segmentIds: <String>[
                reissueToMidday
                    ? 'seg_booking_demo_express_midday_2'
                    : 'seg_booking_demo_express_evening_2',
              ],
              status: CoachTicketStatus.active,
              operatorTicketReference:
                  'operator-ticket-ticket_booking_demo_express_direct_reissue_2',
              qrPayloadRef:
                  'object://coach/tickets/ticket_booking_demo_express_direct_reissue_2/qr',
              issuedAtIso: '2026-04-07T13:20:00Z',
              revokedAtIso: null,
            ),
          ]
        : const <CoachTicketCoupon>[
            CoachTicketCoupon(
              ticketId: 'ticket_booking_demo_express_direct_1',
              bookingId: 'booking_demo_express_direct',
              couponId: 'coupon-ticket_booking_demo_express_direct_1',
              passengerId: 'adult_1',
              segmentIds: <String>['seg_booking_demo_express_direct_1'],
              status: CoachTicketStatus.active,
              operatorTicketReference:
                  'operator-ticket-ticket_booking_demo_express_direct_1',
              qrPayloadRef:
                  'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
              issuedAtIso: '2026-04-07T12:06:30Z',
              revokedAtIso: null,
            ),
            CoachTicketCoupon(
              ticketId: 'ticket_booking_demo_express_direct_2',
              bookingId: 'booking_demo_express_direct',
              couponId: 'coupon-ticket_booking_demo_express_direct_2',
              passengerId: 'adult_2',
              segmentIds: <String>['seg_booking_demo_express_direct_2'],
              status: CoachTicketStatus.active,
              operatorTicketReference:
                  'operator-ticket-ticket_booking_demo_express_direct_2',
              qrPayloadRef:
                  'object://coach/tickets/ticket_booking_demo_express_direct_2/qr',
              issuedAtIso: '2026-04-07T12:06:30Z',
              revokedAtIso: null,
            ),
          ];
    return CoachBookingShelfResponse(
      summary: const CoachBookingShelfSummary(
        upcomingCount: 2,
        ticketedCount: 1,
        needsActionCount: 1,
      ),
      bookings: <CoachBookingShelfEntry>[
        CoachBookingShelfEntry(
          journey: firstJourney,
          offer: firstOffer,
          hold: firstHold,
          booking: firstBooking,
          passengerManifests: const <CoachPassengerManifest>[
            CoachPassengerManifest(
              passengerId: 'adult_1',
              givenName: 'Lina',
              familyName: 'Haddad',
              riderCategory: CoachPassengerRiderCategory.adult,
              nationalityCode: 'SY',
            ),
            CoachPassengerManifest(
              passengerId: 'adult_2',
              givenName: 'Omar',
              familyName: 'Darwish',
              riderCategory: CoachPassengerRiderCategory.student,
              nationalityCode: 'DE',
            ),
          ],
          tickets: firstTickets,
        ),
        CoachBookingShelfEntry(
          journey: const CoachBookedJourneySummary(
            journeyId: 'journey_northern_connector_night',
            operatorName: 'Northern Connector',
            from: 'Aleppo',
            to: 'Latakia',
            departureAtIso: '2026-04-09T22:15:00Z',
            arrivalAtIso: '2026-04-10T03:45:00Z',
            statusLabel: 'Issue tickets',
          ),
          offer: const CoachOffer(
            offerId: 'offer_night_connector',
            operatorId: 'op_northern_connector',
            itineraryId: 'iti_night_connector',
            currency: 'SYP',
            totalMinorUnits: 3990,
            seatsRequested: 1,
            holdSupported: true,
            changeable: true,
            refundable: false,
            expiresAtIso: '2026-04-07T12:05:00Z',
          ),
          hold: const CoachHold(
            holdId: 'hold_night_connector',
            offerId: 'offer_night_connector',
            operatorReference: 'operator-hold_night_connector',
            expiresAtIso: '2026-04-07T12:04:30Z',
            status: CoachHoldStatus.converted,
            seatAssignments: <CoachSeatAssignment>[
              CoachSeatAssignment(passengerId: 'senior_1', seatNumber: '2C'),
            ],
          ),
          booking: const CoachBooking(
            bookingId: 'booking_night_connector',
            offerId: 'offer_night_connector',
            holdId: 'hold_night_connector',
            operatorBookingReference:
                'operator-booking-booking_night_connector',
            state: CoachBookingLifecycleState.bookingPending,
            currency: 'SYP',
            totalMinorUnits: 3990,
            passengerCount: 1,
            createdAtIso: '2026-04-07T12:06:00Z',
          ),
          passengerManifests: const <CoachPassengerManifest>[
            CoachPassengerManifest(
              passengerId: 'senior_1',
              givenName: 'Maha',
              familyName: 'Khalil',
              riderCategory: CoachPassengerRiderCategory.senior,
              nationalityCode: 'SY',
            ),
          ],
          tickets: const <CoachTicketCoupon>[],
        ),
      ],
    );
  }

  @override
  Future<CoachJourneySearchResponse> search({
    required String from,
    required String to,
    required String departureDate,
    int passengers = 1,
  }) async {
    searchCalls++;
    return CoachJourneySearchResponse(
      from: from,
      to: to,
      departureDate: departureDate,
      passengers: passengers,
      journeys: <CoachJourneyOption>[
        CoachJourneyOption(
          journeyId: 'journey_demo_express_direct',
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          integrationMode: CoachOperatorIntegrationMode.hybrid,
          departureAtIso: '${departureDate}T08:00:00Z',
          arrivalAtIso: '${departureDate}T12:30:00Z',
          durationMinutes: 270,
          transferCount: 0,
          seatsAvailable: 8,
          lowAvailability: false,
          currency: 'SYP',
          priceFromMinorUnits: 4590 * passengers,
          amenities: const <String>['wifi', 'power_outlet', 'toilet'],
          changeable: true,
          refundable: true,
          bestOffer: CoachOffer(
            offerId: 'offer_demo_express_direct',
            operatorId: 'op_demo_express',
            itineraryId: 'iti_demo_direct',
            currency: 'SYP',
            totalMinorUnits: 4590 * passengers,
            seatsRequested: passengers,
            holdSupported: true,
            changeable: true,
            refundable: true,
            expiresAtIso: '2026-04-07T12:05:00Z',
          ),
          live: const CoachJourneyLiveSnapshot(
            delayMinutes: 5,
            tripUpdatesFresh: true,
            vehiclePositionsFresh: true,
            serviceAlertsFresh: true,
          ),
        ),
        CoachJourneyOption(
          journeyId: 'journey_budget_connector',
          operatorId: 'op_budget_connector',
          operatorName: 'Budget Connector',
          integrationMode: CoachOperatorIntegrationMode.feed,
          departureAtIso: '${departureDate}T08:35:00Z',
          arrivalAtIso: '${departureDate}T14:05:00Z',
          durationMinutes: 330,
          transferCount: 1,
          seatsAvailable: 21,
          lowAvailability: false,
          currency: 'SYP',
          priceFromMinorUnits: 3990 * passengers,
          amenities: const <String>['wifi', 'toilet', 'snacks'],
          changeable: false,
          refundable: false,
          bestOffer: CoachOffer(
            offerId: 'offer_budget_connector',
            operatorId: 'op_budget_connector',
            itineraryId: 'iti_budget_connector',
            currency: 'SYP',
            totalMinorUnits: 3990 * passengers,
            seatsRequested: passengers,
            holdSupported: false,
            changeable: false,
            refundable: false,
            expiresAtIso: '2026-04-07T12:05:00Z',
          ),
          live: const CoachJourneyLiveSnapshot(
            delayMinutes: 0,
            tripUpdatesFresh: true,
            vehiclePositionsFresh: false,
            serviceAlertsFresh: true,
          ),
        ),
        CoachJourneyOption(
          journeyId: 'journey_rapid_link_direct',
          operatorId: 'op_rapid_link',
          operatorName: 'Rapid Link',
          integrationMode: CoachOperatorIntegrationMode.api,
          departureAtIso: '${departureDate}T09:10:00Z',
          arrivalAtIso: '${departureDate}T13:00:00Z',
          durationMinutes: 230,
          transferCount: 0,
          seatsAvailable: 4,
          lowAvailability: true,
          currency: 'SYP',
          priceFromMinorUnits: 4990 * passengers,
          amenities: const <String>['wifi', 'power_outlet', 'toilet'],
          changeable: true,
          refundable: false,
          bestOffer: CoachOffer(
            offerId: 'offer_rapid_link_direct',
            operatorId: 'op_rapid_link',
            itineraryId: 'iti_rapid_link_direct',
            currency: 'SYP',
            totalMinorUnits: 4990 * passengers,
            seatsRequested: passengers,
            holdSupported: true,
            changeable: true,
            refundable: false,
            expiresAtIso: '2026-04-07T12:05:00Z',
          ),
          live: const CoachJourneyLiveSnapshot(
            delayMinutes: 2,
            tripUpdatesFresh: true,
            vehiclePositionsFresh: true,
            serviceAlertsFresh: true,
          ),
        ),
      ],
    );
  }

  @override
  Future<CoachJourneyLiveResponse> getJourneyLive(String journeyId) async {
    journeyLiveCalls++;
    return CoachJourneyLiveResponse(
      journey: const CoachBookedJourneySummary(
        journeyId: 'journey_demo_express_direct',
        operatorName: 'Demo Express',
        from: 'Damascus',
        to: 'Aleppo',
        departureAtIso: '2026-04-08T08:00:00Z',
        arrivalAtIso: '2026-04-08T12:30:00Z',
        statusLabel: 'Boarding pass ready',
      ),
      offer: const CoachOffer(
        offerId: 'offer_demo_express_direct',
        operatorId: 'op_demo_express',
        itineraryId: 'iti_demo_direct',
        currency: 'SYP',
        totalMinorUnits: 9180,
        seatsRequested: 2,
        holdSupported: true,
        changeable: true,
        refundable: true,
        expiresAtIso: '2026-04-07T12:05:00Z',
      ),
      hold: const CoachHold(
        holdId: 'hold_demo_express_direct',
        offerId: 'offer_demo_express_direct',
        operatorReference: 'operator-hold_demo_express_direct',
        expiresAtIso: '2026-04-07T12:04:30Z',
        status: CoachHoldStatus.converted,
        seatAssignments: <CoachSeatAssignment>[
          CoachSeatAssignment(passengerId: 'adult_1', seatNumber: '4A'),
          CoachSeatAssignment(passengerId: 'adult_2', seatNumber: '4B'),
        ],
      ),
      booking: const CoachBooking(
        bookingId: 'booking_demo_express_direct',
        offerId: 'offer_demo_express_direct',
        holdId: 'hold_demo_express_direct',
        operatorBookingReference:
            'operator-booking-booking_demo_express_direct',
        state: CoachBookingLifecycleState.ticketed,
        currency: 'SYP',
        totalMinorUnits: 9180,
        passengerCount: 2,
        createdAtIso: '2026-04-07T12:06:00Z',
      ),
      passengerManifests: const <CoachPassengerManifest>[
        CoachPassengerManifest(
          passengerId: 'adult_1',
          givenName: 'Lina',
          familyName: 'Haddad',
          riderCategory: CoachPassengerRiderCategory.adult,
          nationalityCode: 'SY',
        ),
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
          ticketId: 'ticket_booking_demo_express_direct_1',
          bookingId: 'booking_demo_express_direct',
          couponId: 'coupon-ticket_booking_demo_express_direct_1',
          passengerId: 'adult_1',
          segmentIds: <String>['seg_booking_demo_express_direct_1'],
          status: CoachTicketStatus.active,
          operatorTicketReference:
              'operator-ticket-ticket_booking_demo_express_direct_1',
          qrPayloadRef:
              'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
          issuedAtIso: '2026-04-07T12:06:30Z',
          revokedAtIso: null,
          boardingState: CoachManifestBoardingState.boarded,
        ),
      ],
      trip: const CoachCrewTripSummary(
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
        boardedCount: 1,
        deniedCount: 0,
        noShowCount: 0,
        pendingCount: 1,
      ),
      recentEvents: const <CoachBoardingEvent>[
        CoachBoardingEvent(
          boardingEventId: 'boardevt_demo_1',
          ticketId: 'ticket_booking_demo_express_direct_1',
          tripId: 'trip_demo_express_direct',
          scanStatus: CoachBoardingScanStatus.scanned,
          capturedAtIso: '2026-04-08T07:41:00Z',
          offlineCaptured: false,
          deviceId: 'device_demo_1',
          note: 'gate cleared',
        ),
      ],
      operatorFeedHealth: const <CoachOperatorFeedHealth>[
        CoachOperatorFeedHealth(
          operatorId: 'op_demo_express',
          operatorName: 'Demo Express',
          operatorIntegrationMode: 'hybrid',
          feedKind: 'gtfs_rt_trip_updates',
          sourceKind: 'gtfs_rt',
          syncStatus: 'ok',
          freshnessStatus: 'fresh',
          lastAttemptedAtIso: '2026-04-08T07:40:00Z',
          lastSucceededAtIso: '2026-04-08T07:40:00Z',
          freshnessExpiresAtIso: '2026-04-08T07:41:30Z',
          recordsIngested: 2,
          errorMessage: null,
        ),
      ],
    );
  }

  @override
  Future<CoachChangeOptionsResponse> getChangeOptions(String bookingId) async {
    changeOptionsCalls++;
    return CoachChangeOptionsResponse(
      booking: const CoachBooking(
        bookingId: 'booking_demo_express_direct',
        offerId: 'offer_demo_express_direct',
        holdId: 'hold_demo_express_direct',
        operatorBookingReference:
            'operator-booking-booking_demo_express_direct',
        state: CoachBookingLifecycleState.ticketed,
        currency: 'SYP',
        totalMinorUnits: 9180,
        passengerCount: 2,
        createdAtIso: '2026-04-07T12:06:00Z',
      ),
      passengerManifests: const <CoachPassengerManifest>[
        CoachPassengerManifest(
          passengerId: 'adult_1',
          givenName: 'Lina',
          familyName: 'Haddad',
          riderCategory: CoachPassengerRiderCategory.adult,
          nationalityCode: 'SY',
        ),
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
          ticketId: 'ticket_booking_demo_express_direct_1',
          bookingId: 'booking_demo_express_direct',
          couponId: 'coupon-ticket_booking_demo_express_direct_1',
          passengerId: 'adult_1',
          segmentIds: <String>['seg_booking_demo_express_direct_1'],
          status: CoachTicketStatus.active,
          operatorTicketReference:
              'operator-ticket-ticket_booking_demo_express_direct_1',
          qrPayloadRef:
              'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
          issuedAtIso: '2026-04-07T12:06:30Z',
          revokedAtIso: null,
        ),
        CoachTicketCoupon(
          ticketId: 'ticket_booking_demo_express_direct_2',
          bookingId: 'booking_demo_express_direct',
          couponId: 'coupon-ticket_booking_demo_express_direct_2',
          passengerId: 'adult_2',
          segmentIds: <String>['seg_booking_demo_express_direct_2'],
          status: CoachTicketStatus.active,
          operatorTicketReference:
              'operator-ticket-ticket_booking_demo_express_direct_2',
          qrPayloadRef:
              'object://coach/tickets/ticket_booking_demo_express_direct_2/qr',
          issuedAtIso: '2026-04-07T12:06:30Z',
          revokedAtIso: null,
        ),
      ],
      eligibility: const CoachChangeEligibility(
        bookingId: 'booking_demo_express_direct',
        bookingState: CoachBookingLifecycleState.ticketed,
        changeable: true,
        reason: null,
        changeCutoffAtIso: '2026-04-08T06:30:00Z',
        options: <CoachChangeOption>[
          CoachChangeOption(
            targetOfferId: 'offer_demo_express_midday',
            journeyId: 'journey_demo_express_midday',
            departureAtIso: '2026-04-08T12:00:00Z',
            arrivalAtIso: '2026-04-08T16:30:00Z',
            currency: 'SYP',
            fareDifferenceMinorUnits: 800,
            changeFeeMinorUnits: 500,
            totalDueMinorUnits: 1300,
            seatMapAvailable: true,
            expiresAtIso: '2026-04-07T14:00:00Z',
          ),
          CoachChangeOption(
            targetOfferId: 'offer_demo_express_evening',
            journeyId: 'journey_demo_express_evening',
            departureAtIso: '2026-04-08T18:00:00Z',
            arrivalAtIso: '2026-04-08T22:30:00Z',
            currency: 'SYP',
            fareDifferenceMinorUnits: -300,
            changeFeeMinorUnits: 300,
            totalDueMinorUnits: 0,
            seatMapAvailable: true,
            expiresAtIso: '2026-04-07T14:00:00Z',
          ),
        ],
      ),
    );
  }

  @override
  Future<CoachRefundEligibilityResponse> getRefundEligibility(
    String bookingId,
  ) async {
    refundEligibilityCalls++;
    return CoachRefundEligibilityResponse(
      booking: const CoachBooking(
        bookingId: 'booking_demo_express_direct',
        offerId: 'offer_demo_express_direct',
        holdId: 'hold_demo_express_direct',
        operatorBookingReference:
            'operator-booking-booking_demo_express_direct',
        state: CoachBookingLifecycleState.ticketed,
        currency: 'SYP',
        totalMinorUnits: 9180,
        passengerCount: 2,
        createdAtIso: '2026-04-07T12:06:00Z',
      ),
      passengerManifests: const <CoachPassengerManifest>[
        CoachPassengerManifest(
          passengerId: 'adult_1',
          givenName: 'Lina',
          familyName: 'Haddad',
          riderCategory: CoachPassengerRiderCategory.adult,
          nationalityCode: 'SY',
        ),
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
          ticketId: 'ticket_booking_demo_express_direct_1',
          bookingId: 'booking_demo_express_direct',
          couponId: 'coupon-ticket_booking_demo_express_direct_1',
          passengerId: 'adult_1',
          segmentIds: <String>['seg_booking_demo_express_direct_1'],
          status: CoachTicketStatus.active,
          operatorTicketReference:
              'operator-ticket-ticket_booking_demo_express_direct_1',
          qrPayloadRef:
              'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
          issuedAtIso: '2026-04-07T12:06:30Z',
          revokedAtIso: null,
        ),
        CoachTicketCoupon(
          ticketId: 'ticket_booking_demo_express_direct_2',
          bookingId: 'booking_demo_express_direct',
          couponId: 'coupon-ticket_booking_demo_express_direct_2',
          passengerId: 'adult_2',
          segmentIds: <String>['seg_booking_demo_express_direct_2'],
          status: CoachTicketStatus.active,
          operatorTicketReference:
              'operator-ticket-ticket_booking_demo_express_direct_2',
          qrPayloadRef:
              'object://coach/tickets/ticket_booking_demo_express_direct_2/qr',
          issuedAtIso: '2026-04-07T12:06:30Z',
          revokedAtIso: null,
        ),
      ],
      eligibility: const CoachRefundEligibility(
        bookingId: 'booking_demo_express_direct',
        bookingState: CoachBookingLifecycleState.ticketed,
        refundable: true,
        currency: 'SYP',
        reason: null,
        refundCutoffAtIso: '2026-04-08T06:00:00Z',
        recommendedKind: CoachRefundKind.refundCredit,
        ticketsVoidRequired: true,
        options: <CoachRefundOption>[
          CoachRefundOption(
            kind: CoachRefundKind.refundCredit,
            label: 'Travel credit',
            currency: 'SYP',
            refundMinorUnits: 9180,
            feeMinorUnits: 0,
            expiresAtIso: '2027-04-08T00:00:00Z',
          ),
          CoachRefundOption(
            kind: CoachRefundKind.originalPayment,
            label: 'Original payment',
            currency: 'SYP',
            refundMinorUnits: 8190,
            feeMinorUnits: 990,
            expiresAtIso: null,
          ),
        ],
      ),
    );
  }

  @override
  Future<CoachOffer> getOffer({
    required String offerId,
    int passengers = 1,
  }) async {
    offerCalls++;
    return CoachOffer(
      offerId: offerId,
      operatorId: 'op_demo_express',
      itineraryId: 'iti_demo_direct',
      currency: 'SYP',
      totalMinorUnits: 4990 * passengers,
      seatsRequested: passengers,
      holdSupported: true,
      changeable: true,
      refundable: true,
      expiresAtIso: '2026-04-07T12:06:00Z',
    );
  }

  @override
  Future<CoachHold> getHold(String holdId) async {
    holdCalls++;
    return CoachHold(
      holdId: holdId,
      offerId: 'offer_demo_express_direct',
      operatorReference: 'operator-$holdId',
      expiresAtIso: '2026-04-07T12:04:30Z',
      status: CoachHoldStatus.active,
      seatAssignments: const <CoachSeatAssignment>[
        CoachSeatAssignment(passengerId: 'pax_1', seatNumber: '4A'),
      ],
    );
  }

  @override
  Future<CoachBooking> getBooking(String bookingId) async {
    bookingCalls++;
    return CoachBooking(
      bookingId: bookingId,
      offerId: 'offer_demo_express_direct',
      holdId: 'hold_offer_demo_express_direct',
      operatorBookingReference: 'operator-booking-$bookingId',
      state: CoachBookingLifecycleState.ticketed,
      currency: 'SYP',
      totalMinorUnits: 4990,
      passengerCount: 1,
      createdAtIso: '2026-04-07T12:06:00Z',
    );
  }

  @override
  Future<CoachTicketCoupon> getTicket(String ticketId) async {
    ticketCalls++;
    return CoachTicketCoupon(
      ticketId: ticketId,
      bookingId: 'booking_offer_demo_express_direct',
      couponId: 'coupon-$ticketId',
      passengerId: 'pax_1',
      segmentIds: const <String>['seg_demo_direct_1'],
      status: CoachTicketStatus.active,
      operatorTicketReference: 'operator-ticket-$ticketId',
      qrPayloadRef: 'object://coach/tickets/$ticketId/qr',
      artifacts: <CoachTicketArtifact>[
        CoachTicketArtifact(
          artifactId: 'ticketartifact_${ticketId}_qr',
          ticketId: ticketId,
          bookingId: 'booking_offer_demo_express_direct',
          artifactKind: 'qr',
          deliveryChannel: 'qr',
          fileName: '$ticketId-qr.svg',
          mimeType: 'image/svg+xml',
          contentLengthBytes: 2048,
          downloadPath:
              '/downloads/coach/tickets/ticketartifact_${ticketId}_qr.svg',
        ),
        CoachTicketArtifact(
          artifactId: 'ticketartifact_${ticketId}_pdf',
          ticketId: ticketId,
          bookingId: 'booking_offer_demo_express_direct',
          artifactKind: 'pdf',
          deliveryChannel: 'pdf',
          fileName: '$ticketId.pdf',
          mimeType: 'application/pdf',
          contentLengthBytes: 32768,
          downloadPath:
              '/downloads/coach/tickets/ticketartifact_${ticketId}_pdf.pdf',
        ),
      ],
      issuedAtIso: '2026-04-07T12:06:30Z',
      revokedAtIso: null,
    );
  }

  @override
  Future<CoachHoldDraft> createHold({
    required String offerId,
    int passengers = 1,
    List<String>? passengerIds,
    List<String>? preferredSeatNumbers,
    String? idempotencyKey,
  }) async {
    holdCalls++;
    lastHoldPassengerIds = passengerIds;
    lastHoldPreferredSeatNumbers = preferredSeatNumbers;
    return CoachHoldDraft(
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-hold-fake',
        scope: 'coach_hold_create',
        requestFingerprint: 'fp_hold_create_fake',
        replayed: false,
        derivedKeys: const <String, String>{
          'inventory_hold': 'coach_hold_inventory.fake',
        },
      ),
      offer: CoachOffer(
        offerId: offerId,
        operatorId: 'op_demo_express',
        itineraryId: 'iti_demo_direct',
        currency: 'SYP',
        totalMinorUnits: 4990 * passengers,
        seatsRequested: passengers,
        holdSupported: true,
        changeable: true,
        refundable: true,
        expiresAtIso: '2026-04-07T12:06:00Z',
      ),
      hold: CoachHold(
        holdId: 'hold_$offerId',
        offerId: offerId,
        operatorReference: 'operator-hold-$offerId',
        expiresAtIso: '2026-04-07T12:04:30Z',
        status: CoachHoldStatus.active,
        seatAssignments: List<CoachSeatAssignment>.generate(
          passengers,
          (index) => CoachSeatAssignment(
            passengerId: (passengerIds != null && passengerIds.length > index)
                ? passengerIds[index]
                : 'pax_${index + 1}',
            seatNumber: (preferredSeatNumbers != null &&
                    preferredSeatNumbers.length > index)
                ? preferredSeatNumbers[index]
                : '${4 + index}A',
          ),
          growable: false,
        ),
      ),
      bookingState: 'hold_created',
      holdTtlSeconds: 300,
    );
  }

  @override
  Future<CoachBookingDraft> createBooking({
    required String offerId,
    String? holdId,
    int passengers = 1,
    List<String>? passengerIds,
    List<String>? preferredSeatNumbers,
    List<CoachPassengerManifest>? passengerManifests,
    String paymentMethod = 'card',
    String? contactEmail,
    bool acceptTerms = true,
    String? idempotencyKey,
  }) async {
    bookingCalls++;
    lastBookingPassengerIds = passengerIds;
    lastBookingPreferredSeatNumbers = preferredSeatNumbers;
    lastBookingPassengerManifests = passengerManifests;
    lastBookingPaymentMethod = paymentMethod;
    lastBookingContactEmail = contactEmail;
    final ids = passengerIds ??
        List<String>.generate(
          passengers,
          (index) => 'pax_${index + 1}',
          growable: false,
        );
    return CoachBookingDraft(
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-booking-fake',
        scope: 'coach_booking_create',
        requestFingerprint: 'fp_booking_create_fake',
        replayed: false,
        derivedKeys: const <String, String>{
          'payment_authorize': 'coach_payment_authorize.fake',
          'booking_finalize': 'coach_booking_finalize.fake',
        },
      ),
      offer: CoachOffer(
        offerId: offerId,
        operatorId: 'op_demo_express',
        itineraryId: 'iti_demo_direct',
        currency: 'SYP',
        totalMinorUnits: 4990 * passengers,
        seatsRequested: passengers,
        holdSupported: true,
        changeable: true,
        refundable: true,
        expiresAtIso: '2026-04-07T12:06:00Z',
      ),
      hold: holdId == null
          ? null
          : CoachHold(
              holdId: holdId,
              offerId: offerId,
              operatorReference: 'operator-$holdId',
              expiresAtIso: '2026-04-07T12:04:30Z',
              status: CoachHoldStatus.converted,
              seatAssignments: List<CoachSeatAssignment>.generate(
                ids.length,
                (index) => CoachSeatAssignment(
                  passengerId: ids[index],
                  seatNumber: (preferredSeatNumbers != null &&
                          preferredSeatNumbers.length > index)
                      ? preferredSeatNumbers[index]
                      : '${4 + index}A',
                ),
                growable: false,
              ),
            ),
      booking: CoachBooking(
        bookingId: 'booking_$offerId',
        offerId: offerId,
        holdId: holdId,
        operatorBookingReference: 'operator-booking-$offerId',
        state: CoachBookingLifecycleState.bookingPending,
        currency: 'SYP',
        totalMinorUnits: 4990 * ids.length,
        passengerCount: ids.length,
        createdAtIso: '2026-04-07T12:06:00Z',
      ),
      passengerManifests:
          passengerManifests ?? const <CoachPassengerManifest>[],
      payment: CoachPaymentAuthorization(
        status: 'authorized',
        method: paymentMethod,
        authorizationReference: 'payauth_$offerId',
        currency: 'SYP',
        chargedMinorUnits: 4990 * ids.length,
      ),
      compensation: const CoachCompensationState(
        state: 'armed',
        action: 'void_payment_or_issue_refund_credit',
        supportQueue: 'coach_ticketing_failures',
        triggered: false,
        reason: null,
        recoveryReference: null,
      ),
      nextAction: 'issue_tickets',
    );
  }

  @override
  Future<CoachTicketingResult> issueTickets({
    required String bookingId,
    required String offerId,
    String? holdId,
    List<String>? passengerIds,
    List<CoachPassengerManifest>? passengerManifests,
    List<String>? deliveryChannels,
    String? idempotencyKey,
  }) async {
    ticketCalls++;
    lastTicketPassengerIds = passengerIds;
    lastTicketPassengerManifests = passengerManifests;
    lastTicketDeliveryChannels = deliveryChannels;
    final ids = passengerIds ?? const <String>['pax_1'];
    return CoachTicketingResult(
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-ticket-fake',
        scope: 'coach_ticket_issue',
        requestFingerprint: 'fp_ticket_issue_fake',
        replayed: false,
        derivedKeys: const <String, String>{
          'ticket_issue': 'coach_ticket_issue_upstream.fake',
          'wallet_artifact': 'coach_wallet_artifact.fake',
        },
      ),
      booking: CoachBooking(
        bookingId: bookingId,
        offerId: offerId,
        holdId: holdId,
        operatorBookingReference: 'operator-booking-$bookingId',
        state: CoachBookingLifecycleState.ticketed,
        currency: 'SYP',
        totalMinorUnits: 4990 * ids.length,
        passengerCount: ids.length,
        createdAtIso: '2026-04-07T12:06:00Z',
      ),
      passengerManifests:
          passengerManifests ?? const <CoachPassengerManifest>[],
      tickets: List<CoachTicketCoupon>.generate(
        ids.length,
        (index) => CoachTicketCoupon(
          ticketId: 'ticket_${index + 1}_$bookingId',
          bookingId: bookingId,
          couponId: 'coupon_${index + 1}_$bookingId',
          passengerId: ids[index],
          segmentIds: <String>['seg_demo_direct_${index + 1}'],
          status: CoachTicketStatus.active,
          operatorTicketReference: 'operator-ticket-${index + 1}-$bookingId',
          qrPayloadRef: 'object://coach/tickets/$bookingId/${index + 1}/qr',
          artifacts: <CoachTicketArtifact>[
            CoachTicketArtifact(
              artifactId: 'ticketartifact_${index + 1}_${bookingId}_qr',
              ticketId: 'ticket_${index + 1}_$bookingId',
              bookingId: bookingId,
              artifactKind: 'qr',
              deliveryChannel: 'qr',
              fileName: 'ticket_${index + 1}_$bookingId-qr.svg',
              mimeType: 'image/svg+xml',
              contentLengthBytes: 2048,
              downloadPath:
                  '/downloads/coach/tickets/ticketartifact_${index + 1}_${bookingId}_qr.svg',
            ),
            CoachTicketArtifact(
              artifactId: 'ticketartifact_${index + 1}_${bookingId}_wallet',
              ticketId: 'ticket_${index + 1}_$bookingId',
              bookingId: bookingId,
              artifactKind: 'wallet_pass',
              deliveryChannel: 'wallet_pass',
              fileName: 'ticket_${index + 1}_$bookingId.pkpass',
              mimeType: 'application/vnd.apple.pkpass',
              contentLengthBytes: 8192,
              downloadPath:
                  '/downloads/coach/tickets/ticketartifact_${index + 1}_${bookingId}_wallet.pkpass',
            ),
            CoachTicketArtifact(
              artifactId: 'ticketartifact_${index + 1}_${bookingId}_pdf',
              ticketId: 'ticket_${index + 1}_$bookingId',
              bookingId: bookingId,
              artifactKind: 'pdf',
              deliveryChannel: 'pdf',
              fileName: 'ticket_${index + 1}_$bookingId.pdf',
              mimeType: 'application/pdf',
              contentLengthBytes: 32768,
              downloadPath:
                  '/downloads/coach/tickets/ticketartifact_${index + 1}_${bookingId}_pdf.pdf',
            ),
          ],
          issuedAtIso: '2026-04-07T12:06:30Z',
          revokedAtIso: null,
        ),
        growable: false,
      ),
      deliveryChannels:
          deliveryChannels ?? const <String>['wallet_pass', 'pdf'],
      compensation: const CoachCompensationState(
        state: 'not_triggered',
        action: 'void_payment_or_issue_refund_credit',
        supportQueue: 'coach_ticketing_failures',
        triggered: false,
        reason: null,
        recoveryReference: null,
      ),
    );
  }

  @override
  Future<CoachRefundRequestResult> requestRefund({
    required String bookingId,
    required CoachRefundKind refundKind,
    List<String>? ticketIds,
    String? reason,
    String? idempotencyKey,
  }) async {
    refundRequestCalls++;
    lastRefundKind = refundKind;
    lastRefundTicketIds = ticketIds;
    lastRefundReason = reason;
    return CoachRefundRequestResult(
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-refund-fake',
        scope: 'coach_refund_request',
        requestFingerprint: 'fp_refund_request_fake',
        replayed: false,
        derivedKeys: const <String, String>{
          'refund_authorize': 'coach_refund_authorize.fake',
          'ledger_posting': 'coach_refund_ledger_posting.fake',
        },
      ),
      booking: const CoachBooking(
        bookingId: 'booking_demo_express_direct',
        offerId: 'offer_demo_express_direct',
        holdId: 'hold_demo_express_direct',
        operatorBookingReference:
            'operator-booking-booking_demo_express_direct',
        state: CoachBookingLifecycleState.refundRequested,
        currency: 'SYP',
        totalMinorUnits: 9180,
        passengerCount: 2,
        createdAtIso: '2026-04-07T12:06:00Z',
      ),
      refundRequest: CoachRefundRequestRecord(
        refundRequestId: 'refundreq_demo_1',
        bookingId: bookingId,
        status: 'requested',
        selectedKind: refundKind,
        currency: 'SYP',
        requestedMinorUnits:
            refundKind == CoachRefundKind.refundCredit ? 9180 : 8190,
        feeMinorUnits: refundKind == CoachRefundKind.refundCredit ? 0 : 990,
        ticketIds: ticketIds ?? const <String>[],
        reason: reason,
        createdAtIso: '2026-04-07T13:00:00Z',
      ),
      compensation: const CoachCompensationState(
        state: 'armed',
        action: 'issue_refund_credit_or_raise_finance_case',
        supportQueue: 'coach_refund_queue',
        triggered: false,
        reason: null,
        recoveryReference: null,
      ),
      nextAction: 'await_refund_review',
    );
  }

  @override
  Future<CoachRebookRequestResult> requestRebook({
    required String bookingId,
    required String targetOfferId,
    List<String>? preferredSeatNumbers,
    String? reason,
    String? idempotencyKey,
  }) async {
    rebookRequestCalls++;
    lastRebookTargetOfferId = targetOfferId;
    lastRebookPreferredSeatNumbers = preferredSeatNumbers;
    lastRebookReason = reason;
    final totalDueMinorUnits =
        targetOfferId == 'offer_demo_express_midday' ? 1300 : 0;
    return CoachRebookRequestResult(
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-rebook-fake',
        scope: 'coach_rebook_request',
        requestFingerprint: 'fp_rebook_request_fake',
        replayed: false,
        derivedKeys: const <String, String>{
          'change_authorize': 'coach_change_authorize.fake',
          'reissue_tickets': 'coach_reissue_tickets.fake',
        },
      ),
      booking: const CoachBooking(
        bookingId: 'booking_demo_express_direct',
        offerId: 'offer_demo_express_direct',
        holdId: 'hold_demo_express_direct',
        operatorBookingReference:
            'operator-booking-booking_demo_express_direct',
        state: CoachBookingLifecycleState.ticketed,
        currency: 'SYP',
        totalMinorUnits: 9180,
        passengerCount: 2,
        createdAtIso: '2026-04-07T12:06:00Z',
      ),
      changeRequest: CoachChangeRequestRecord(
        changeRequestId: 'changereq_demo_1',
        bookingId: bookingId,
        status: 'requested',
        targetOfferId: targetOfferId,
        currency: 'SYP',
        fareDifferenceMinorUnits:
            targetOfferId == 'offer_demo_express_midday' ? 800 : -300,
        changeFeeMinorUnits:
            targetOfferId == 'offer_demo_express_midday' ? 500 : 300,
        totalDueMinorUnits: totalDueMinorUnits,
        reason: reason,
        createdAtIso: '2026-04-07T13:05:00Z',
      ),
      compensation: const CoachCompensationState(
        state: 'armed',
        action: 'reissue_tickets_or_raise_support_case',
        supportQueue: 'coach_rebook_queue',
        triggered: false,
        reason: null,
        recoveryReference: null,
      ),
      nextAction: 'await_reissue',
    );
  }

  @override
  Future<CoachSelfServiceReissueResult> selfServiceReissue({
    required String bookingId,
    required String targetOfferId,
    List<String>? preferredSeatNumbers,
    List<String>? deliveryChannels,
    String? paymentMethod,
    String? reason,
    String? idempotencyKey,
  }) async {
    selfServiceReissueCalls++;
    lastReissueTargetOfferId = targetOfferId;
    lastReissuePreferredSeatNumbers = preferredSeatNumbers;
    lastReissueDeliveryChannels = deliveryChannels;
    lastReissuePaymentMethod = paymentMethod;
    lastReissueReason = reason;
    final reissueToMidday = targetOfferId == 'offer_demo_express_midday';
    final totalDueMinorUnits = reissueToMidday ? 1300 : 0;
    final paymentFailed = reissueToMidday &&
        paymentMethod == 'wallet_credit' &&
        totalDueMinorUnits > 1000;
    _ticketReissued = !paymentFailed;
    return _buildReissueResult(
      bookingId: bookingId,
      targetOfferId: targetOfferId,
      deliveryChannels: deliveryChannels,
      paymentMethod: paymentMethod,
      idempotencyKey: idempotencyKey,
      totalDueMinorUnits: totalDueMinorUnits,
      paymentFailed: paymentFailed,
      reason: reason,
    );
  }

  @override
  Future<CoachSelfServiceReissueResult> resolveReissuePaymentFailure({
    required String bookingId,
    required String paymentMethod,
    List<String>? deliveryChannels,
    String? note,
    String? idempotencyKey,
  }) async {
    resolvePaymentFailureCalls++;
    lastResolvePaymentFailureMethod = paymentMethod;
    final targetOfferId =
        lastReissueTargetOfferId ?? 'offer_demo_express_midday';
    final totalDueMinorUnits =
        targetOfferId == 'offer_demo_express_midday' ? 1300 : 0;
    final paymentFailed =
        paymentMethod == 'wallet_credit' && totalDueMinorUnits > 1000;
    _ticketReissued = !paymentFailed;
    return _buildReissueResult(
      bookingId: bookingId,
      targetOfferId: targetOfferId,
      deliveryChannels: deliveryChannels ?? lastReissueDeliveryChannels,
      paymentMethod: paymentMethod,
      idempotencyKey: idempotencyKey ?? 'coach-reissue-recovery-fake',
      totalDueMinorUnits: totalDueMinorUnits,
      paymentFailed: paymentFailed,
      reason: lastReissueReason,
    );
  }

  CoachSelfServiceReissueResult _buildReissueResult({
    required String bookingId,
    required String targetOfferId,
    required List<String>? deliveryChannels,
    required String? paymentMethod,
    required String? idempotencyKey,
    required int totalDueMinorUnits,
    required bool paymentFailed,
    required String? reason,
  }) {
    final reissueToMidday = targetOfferId == 'offer_demo_express_midday';
    return CoachSelfServiceReissueResult(
      idempotency: CoachCommandIdempotencyMeta(
        key: idempotencyKey ?? 'coach-reissue-fake',
        scope: 'coach_ticket_reissue',
        requestFingerprint: 'fp_ticket_reissue_fake',
        replayed: false,
        derivedKeys: const <String, String>{
          'ticket_reissue': 'coach_ticket_reissue_upstream.fake',
          'wallet_artifact': 'coach_wallet_artifact.fake',
        },
      ),
      booking: CoachBooking(
        bookingId: 'booking_demo_express_direct',
        offerId: paymentFailed
            ? 'offer_demo_express_direct'
            : reissueToMidday
                ? 'offer_demo_express_midday'
                : 'offer_demo_express_evening',
        holdId: paymentFailed
            ? 'hold_demo_express_direct'
            : 'hold_booking_demo_express_direct_reissue',
        operatorBookingReference:
            'operator-booking-booking_demo_express_direct',
        state: CoachBookingLifecycleState.ticketed,
        currency: 'SYP',
        totalMinorUnits: paymentFailed
            ? 9180
            : reissueToMidday
                ? 9980
                : 8880,
        passengerCount: 2,
        createdAtIso: '2026-04-07T12:06:00Z',
      ),
      changeRequest: CoachChangeRequestRecord(
        changeRequestId: 'changereq_demo_reissue_1',
        bookingId: bookingId,
        status: paymentFailed ? 'payment_failed' : 'reissued',
        targetOfferId: targetOfferId,
        currency: 'SYP',
        fareDifferenceMinorUnits: reissueToMidday ? 800 : -300,
        changeFeeMinorUnits: reissueToMidday ? 500 : 300,
        totalDueMinorUnits: totalDueMinorUnits,
        reason: reason,
        createdAtIso: '2026-04-07T13:20:00Z',
      ),
      passengerManifests: const <CoachPassengerManifest>[
        CoachPassengerManifest(
          passengerId: 'adult_1',
          givenName: 'Lina',
          familyName: 'Haddad',
          riderCategory: CoachPassengerRiderCategory.adult,
          nationalityCode: 'SY',
        ),
        CoachPassengerManifest(
          passengerId: 'adult_2',
          givenName: 'Omar',
          familyName: 'Darwish',
          riderCategory: CoachPassengerRiderCategory.student,
          nationalityCode: 'DE',
        ),
      ],
      tickets: paymentFailed
          ? const <CoachTicketCoupon>[
              CoachTicketCoupon(
                ticketId: 'ticket_booking_demo_express_direct_1',
                bookingId: 'booking_demo_express_direct',
                couponId: 'coupon-ticket_booking_demo_express_direct_1',
                passengerId: 'adult_1',
                segmentIds: <String>['seg_booking_demo_express_direct_1'],
                status: CoachTicketStatus.active,
                operatorTicketReference:
                    'operator-ticket-ticket_booking_demo_express_direct_1',
                qrPayloadRef:
                    'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
                issuedAtIso: '2026-04-07T12:06:30Z',
                revokedAtIso: null,
              ),
              CoachTicketCoupon(
                ticketId: 'ticket_booking_demo_express_direct_2',
                bookingId: 'booking_demo_express_direct',
                couponId: 'coupon-ticket_booking_demo_express_direct_2',
                passengerId: 'adult_2',
                segmentIds: <String>['seg_booking_demo_express_direct_2'],
                status: CoachTicketStatus.active,
                operatorTicketReference:
                    'operator-ticket-ticket_booking_demo_express_direct_2',
                qrPayloadRef:
                    'object://coach/tickets/ticket_booking_demo_express_direct_2/qr',
                issuedAtIso: '2026-04-07T12:06:30Z',
                revokedAtIso: null,
              ),
            ]
          : const <CoachTicketCoupon>[
              CoachTicketCoupon(
                ticketId: 'ticket_booking_demo_express_direct_reissue_1',
                bookingId: 'booking_demo_express_direct',
                couponId: 'coupon-ticket_booking_demo_express_direct_reissue_1',
                passengerId: 'adult_1',
                segmentIds: <String>['seg_booking_demo_express_evening_1'],
                status: CoachTicketStatus.active,
                operatorTicketReference:
                    'operator-ticket-ticket_booking_demo_express_direct_reissue_1',
                qrPayloadRef:
                    'object://coach/tickets/ticket_booking_demo_express_direct_reissue_1/qr',
                issuedAtIso: '2026-04-07T13:20:00Z',
                revokedAtIso: null,
              ),
              CoachTicketCoupon(
                ticketId: 'ticket_booking_demo_express_direct_reissue_2',
                bookingId: 'booking_demo_express_direct',
                couponId: 'coupon-ticket_booking_demo_express_direct_reissue_2',
                passengerId: 'adult_2',
                segmentIds: <String>['seg_booking_demo_express_evening_2'],
                status: CoachTicketStatus.active,
                operatorTicketReference:
                    'operator-ticket-ticket_booking_demo_express_direct_reissue_2',
                qrPayloadRef:
                    'object://coach/tickets/ticket_booking_demo_express_direct_reissue_2/qr',
                issuedAtIso: '2026-04-07T13:20:00Z',
                revokedAtIso: null,
              ),
            ],
      deliveryChannels:
          deliveryChannels ?? const <String>['wallet_pass', 'pdf'],
      payment: totalDueMinorUnits > 0
          ? CoachPaymentAuthorization(
              status: paymentFailed ? 'failed' : 'authorized',
              method: paymentMethod ?? 'card',
              authorizationReference: 'payauth_demo_reissue_change',
              currency: 'SYP',
              chargedMinorUnits: paymentFailed ? 0 : totalDueMinorUnits,
            )
          : null,
      compensation: CoachCompensationState(
        state: paymentFailed ? 'triggered' : 'resolved',
        action: paymentFailed
            ? 'retry_collection_or_raise_support_case'
            : 'reissue_completed',
        supportQueue: 'coach_rebook_queue',
        triggered: paymentFailed,
        reason: paymentFailed ? 'wallet_credit_insufficient' : null,
        recoveryReference:
            paymentFailed ? 'recovery_demo_change_payment' : null,
      ),
      nextAction: paymentFailed ? 'resolve_payment_failure' : 'completed',
    );
  }
}

void main() {
  void configureLargeViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tapVisibleText(WidgetTester tester, String text) async {
    final finder = find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  Future<void> tapNavigationLabel(WidgetTester tester, String text) async {
    final finder = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(text),
    );
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  Finder labeledTextField(String label) {
    return find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
  }

  Finder labeledDropdown(String label) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration?.labelText == label,
    );
  }

  testWidgets('mobility hub dispatches taxi and coach actions', (tester) async {
    configureLargeViewport(tester);
    var rideTapped = 0;
    var coachTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MobilityHubPage(
          onOpenRide: () {
            rideTapped++;
          },
          onOpenCoach: () {
            coachTapped++;
          },
        ),
      ),
    );

    await tapVisibleText(tester, 'Open taxi');
    await tapVisibleText(tester, 'Open coach');

    expect(rideTapped, 1);
    expect(coachTapped, 1);
  });

  testWidgets('mobility hub hides coach action when capability is off',
      (tester) async {
    configureLargeViewport(tester);
    var rideTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MobilityHubPage(
          onOpenRide: () {
            rideTapped++;
          },
        ),
      ),
    );

    expect(find.text('Open taxi'), findsOneWidget);
    expect(find.text('Open coach'), findsNothing);

    await tapVisibleText(tester, 'Open taxi');
    expect(rideTapped, 1);
  });

  testWidgets('coach mini program loads bootstrap and renders search results',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
          initialFrom: 'Damascus',
          initialTo: 'Aleppo',
          initialDepartureDate: '2026-04-08',
          initialPassengers: 2,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('offer'), findsOneWidget);
    expect(api.bootstrapCalls, 1);
    expect(api.bookingListCalls, 1);
    expect(find.text('Plan'), findsAtLeastNWidgets(1));
    expect(find.text('Trips'), findsAtLeastNWidgets(1));
    expect(find.text('Coach travel board'), findsOneWidget);
    expect(find.text('Fill common Syria corridors with one tap.'),
        findsOneWidget);
    expect(find.text('Quick routes'), findsOneWidget);
    expect(find.text('Feed health'), findsOneWidget);
    expect(find.textContaining('Operational warning: Northern Connector'),
        findsOneWidget);

    await tapVisibleText(tester, 'Search');

    expect(api.searchCalls, 1);
    expect(find.text('Best fare'), findsOneWidget);
    expect(find.text('Board tools'), findsOneWidget);
    expect(find.text('Direct only'), findsOneWidget);
    expect(find.text('Departure board'), findsOneWidget);
    expect(find.textContaining('2026-04-08'), findsAtLeastNWidgets(1));
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('12:30'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsAtLeastNWidgets(1));
    expect(find.text('79.80 SYP'), findsAtLeastNWidgets(2));
    expect(find.textContaining('Budget Connector'), findsOneWidget);
    expect(find.textContaining('Rapid Link'), findsOneWidget);

    await tapNavigationLabel(tester, 'Trips');
    await tester.pumpAndSettle();

    expect(find.text('My coach trips'), findsOneWidget);
    expect(find.text('Next departure'), findsAtLeastNWidgets(1));
    expect(find.text('Travel board'), findsAtLeastNWidgets(1));
    expect(find.text('Travel day actions'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Boarding pass ready'), findsAtLeastNWidgets(1));
  });

  testWidgets('coach mini program keeps Syria-only route scope in search',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
          initialFrom: 'Amman',
          initialTo: 'Paris',
          initialDepartureDate: '2026-04-08',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
        find.text(
            'This mini program currently supports Syria-only intercity routes. Search currently supports Damascus, Homs, Aleppo, and Latakia.'),
        findsOneWidget);
    expect(find.text('Damascus'), findsOneWidget);
    expect(find.text('Aleppo'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'From'), 'Amman');
    await tapVisibleText(tester, 'Search');

    expect(api.searchCalls, 0);
    expect(
        find.text(
            'Search is currently limited to Syria routes between Damascus, Homs, Aleppo, and Latakia.'),
        findsOneWidget);
  });

  testWidgets('coach mini program filters departure board to direct journeys',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
          initialFrom: 'Damascus',
          initialTo: 'Aleppo',
          initialDepartureDate: '2026-04-08',
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tapVisibleText(tester, 'Search');

    expect(find.textContaining('Budget Connector'), findsOneWidget);
    expect(find.textContaining('Rapid Link'), findsOneWidget);

    await tester.ensureVisible(find.text('Direct only').first);
    await tester.tap(find.text('Direct only').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Budget Connector'), findsNothing);
    expect(find.textContaining('Demo Express'), findsOneWidget);
    expect(find.textContaining('Rapid Link'), findsOneWidget);
    expect(find.text('2 shown'), findsOneWidget);
  });

  testWidgets(
      'coach mini program opens saved ticket details from booking shelf',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tapNavigationLabel(tester, 'Trips');
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Open ticket');

    expect(find.text('Trip and ticket detail'), findsOneWidget);
    expect(find.text('Travel board'), findsAtLeastNWidgets(1));
    expect(find.text('booking_demo_express_direct'), findsOneWidget);
    expect(
      find.textContaining(
        'QR object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
      ),
      findsOneWidget,
    );
    expect(find.text('adult_1: Lina Haddad • Adult • SY'), findsOneWidget);
  });

  testWidgets('coach mini program opens saved ticket details from tickets tab',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tapNavigationLabel(tester, 'Tickets');

    expect(find.text('Tickets and delivery'), findsOneWidget);
    expect(find.text('Ticket wallet board'), findsAtLeastNWidgets(1));
    await tapVisibleText(tester, 'Open ticket');

    expect(find.text('Trip and ticket detail'), findsOneWidget);
    expect(find.textContaining('ticket_booking_demo_express_direct_1'),
        findsAtLeastNWidgets(1));
  });

  testWidgets('coach mini program opens live journey from booking shelf',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tapNavigationLabel(tester, 'Trips');
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Live journey');
    await tester.pumpAndSettle();

    expect(api.journeyLiveCalls, 1);
    expect(find.text('Live journey'), findsWidgets);
    expect(find.text('Operations board'), findsOneWidget);
    expect(find.textContaining('Bay A4'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Scanned'), findsOneWidget);
    expect(find.textContaining('Trip updates'), findsOneWidget);
  });

  testWidgets('coach mini program requests refund from saved ticket shelf',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tapNavigationLabel(tester, 'Trips');
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Refund options');

    expect(find.text('Refund board'), findsOneWidget);
    expect(find.text('Request travel credit'), findsOneWidget);
    expect(api.refundEligibilityCalls, 1);
    expect(find.text('Travel credit'), findsAtLeastNWidgets(1));

    await tapVisibleText(tester, 'Request travel credit');

    expect(api.refundRequestCalls, 1);
    expect(api.lastRefundKind, CoachRefundKind.refundCredit);
    expect(api.lastRefundReason, 'customer changed plans');
    expect(
      api.lastRefundTicketIds,
      const <String>[
        'ticket_booking_demo_express_direct_1',
        'ticket_booking_demo_express_direct_2',
      ],
    );
    expect(find.text('Refund request submitted.'), findsOneWidget);
    expect(find.textContaining('Refund requested'), findsAtLeastNWidgets(1));
  });

  testWidgets('coach mini program pays and reissues payable trip change',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tapNavigationLabel(tester, 'Trips');
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Change trip');

    expect(find.text('Change trip options'), findsOneWidget);
    expect(find.text('Change board'), findsOneWidget);
    expect(api.changeOptionsCalls, 1);
    expect(find.text('Pay and reissue'), findsAtLeastNWidgets(1));
    expect(find.text('Reissue now'), findsAtLeastNWidgets(1));

    await tapVisibleText(tester, 'Pay and reissue');
    await tester.pumpAndSettle();

    expect(api.rebookRequestCalls, 0);
    expect(api.selfServiceReissueCalls, 1);
    expect(api.lastReissueTargetOfferId, 'offer_demo_express_midday');
    expect(api.lastReissuePreferredSeatNumbers, const <String>['5A', '5B']);
    expect(
        api.lastReissueDeliveryChannels, const <String>['wallet_pass', 'pdf']);
    expect(api.lastReissuePaymentMethod, 'card');
    expect(api.lastReissueReason, 'move to midday departure');
    expect(find.text('Tickets reissued.'), findsOneWidget);
    expect(find.textContaining('Payment: Authorized • Card'), findsOneWidget);
  });

  testWidgets('coach mini program shows payable reissue collection failure',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
        ),
      ),
    );

    await tester.pumpAndSettle();

    final initialBookingListCalls = api.bookingListCalls;
    await tapNavigationLabel(tester, 'Trips');
    await tester.pumpAndSettle();
    await tapVisibleText(tester, 'Change trip');

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallet credit').last);
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Pay and reissue');
    await tester.pumpAndSettle();

    expect(api.selfServiceReissueCalls, 1);
    expect(api.lastReissuePaymentMethod, 'wallet_credit');
    expect(api.bookingListCalls, initialBookingListCalls);
    expect(
      find.text('Payment could not be collected for this change.'),
      findsOneWidget,
    );
    expect(
        find.textContaining('Change status: Payment failed'), findsOneWidget);
    expect(
      find.textContaining('Payment: Failed • Wallet credit'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
          'Compensation: Retry collection or raise support case'),
      findsOneWidget,
    );
  });

  testWidgets(
      'coach mini program resolves payable reissue failure after retry collection',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
        ),
      ),
    );

    await tester.pumpAndSettle();

    final initialBookingListCalls = api.bookingListCalls;
    await tapNavigationLabel(tester, 'Trips');
    await tester.pumpAndSettle();
    await tapVisibleText(tester, 'Change trip');

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallet credit').last);
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Pay and reissue');
    await tester.pumpAndSettle();

    expect(api.selfServiceReissueCalls, 1);
    expect(api.resolvePaymentFailureCalls, 0);
    expect(
      find.text('Retry collection and reissue'),
      findsOneWidget,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card').last);
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Retry collection and reissue');
    await tester.pumpAndSettle();

    expect(api.resolvePaymentFailureCalls, 1);
    expect(api.lastResolvePaymentFailureMethod, 'card');
    expect(api.bookingListCalls, greaterThan(initialBookingListCalls));
    expect(find.text('Tickets reissued.'), findsOneWidget);
    expect(find.textContaining('Change status: Reissued'), findsOneWidget);
    expect(find.textContaining('Payment: Authorized • Card'), findsOneWidget);
  });

  testWidgets('coach mini program reissues zero-due changes directly',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
        ),
      ),
    );

    await tester.pumpAndSettle();

    final initialBookingListCalls = api.bookingListCalls;
    await tapNavigationLabel(tester, 'Trips');
    await tester.pumpAndSettle();
    await tapVisibleText(tester, 'Change trip');

    expect(find.text('Reissue now'), findsAtLeastNWidgets(1));

    await tapVisibleText(tester, 'Reissue now');
    await tester.pumpAndSettle();

    expect(api.selfServiceReissueCalls, 1);
    expect(api.rebookRequestCalls, 0);
    expect(api.lastReissueTargetOfferId, 'offer_demo_express_evening');
    expect(api.lastReissuePreferredSeatNumbers, const <String>['5A', '5B']);
    expect(
        api.lastReissueDeliveryChannels, const <String>['wallet_pass', 'pdf']);
    expect(api.lastReissuePaymentMethod, isNull);
    expect(api.lastReissueReason, 'move to midday departure');
    expect(find.text('Tickets reissued.'), findsOneWidget);
    expect(find.textContaining('ticket_booking_demo_express_direct_reissue_1'),
        findsAtLeastNWidgets(1));
    expect(api.bookingListCalls, greaterThan(initialBookingListCalls));
  });

  testWidgets('coach mini program runs hold booking and ticketing flow',
      (tester) async {
    configureLargeViewport(tester);
    final api = _FakeCoachMobilityApi();

    await tester.pumpWidget(
      MaterialApp(
        home: CoachBusMiniProgramPage(
          baseUrl: 'https://api.shamell.online',
          apiOverride: api,
          initialFrom: 'Damascus',
          initialTo: 'Aleppo',
          initialDepartureDate: '2026-04-08',
          initialPassengers: 2,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tapVisibleText(tester, 'Search');

    await tester
        .ensureVisible(find.textContaining('journey_demo_express_direct'));
    await tester.tap(find.textContaining('journey_demo_express_direct').first);
    await tester.pumpAndSettle();
    expect(find.text('Journey progress'), findsOneWidget);
    expect(find.text('Travel setup board'), findsOneWidget);

    await tester.enterText(
        labeledTextField('Contact email'), 'pax@shamell.test');
    await tester.enterText(labeledTextField('Passenger ID 1'), 'adult_1');
    await tester.enterText(labeledTextField('Given name 1'), 'Lina');
    await tester.enterText(labeledTextField('Family name 1'), 'Haddad');
    await tester.enterText(labeledTextField('Nationality 1'), 'SY');
    await tester.enterText(labeledTextField('Passenger ID 2'), 'adult_2');
    await tester.enterText(labeledTextField('Given name 2'), 'Omar');
    await tester.enterText(labeledTextField('Family name 2'), 'Darwish');
    await tester.enterText(labeledTextField('Nationality 2'), 'DE');
    await tester.enterText(labeledTextField('Preferred seat 1'), '3A');
    await tester.enterText(labeledTextField('Preferred seat 2'), '3B');
    await tester.dragUntilVisible(
      labeledDropdown('Payment method').first,
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    final paymentDropdown = tester.widget<DropdownButtonFormField<String>>(
      labeledDropdown('Payment method').first,
    );
    paymentDropdown.onChanged?.call('wallet_credit');
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Email delivery').first,
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.tap(find.text('Email delivery'));
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Refresh offer');
    await tapVisibleText(tester, 'Create hold');
    await tapVisibleText(tester, 'Create booking');
    await tapVisibleText(tester, 'Issue tickets');

    expect(api.offerCalls, 1);
    expect(api.holdCalls, 1);
    expect(api.bookingCalls, 1);
    expect(api.ticketCalls, 1);
    expect(find.text('Hold'), findsAtLeastNWidgets(1));
    expect(find.text('Booking'), findsAtLeastNWidgets(1));
    expect(find.text('Passengers'), findsAtLeastNWidgets(1));
    expect(find.text('Compensation'), findsOneWidget);
    expect(find.text('Tickets'), findsAtLeastNWidgets(1));
    expect(
        find.textContaining('Wallet /downloads/coach/tickets/'), findsWidgets);
    expect(find.textContaining('PDF /downloads/coach/tickets/'), findsWidgets);
    expect(api.lastHoldPassengerIds, const <String>['adult_1', 'adult_2']);
    expect(api.lastHoldPreferredSeatNumbers, const <String>['3A', '3B']);
    expect(api.lastBookingPassengerIds, const <String>['adult_1', 'adult_2']);
    expect(api.lastBookingPreferredSeatNumbers, const <String>['3A', '3B']);
    expect(api.lastBookingPassengerManifests, isNotNull);
    expect(api.lastBookingPassengerManifests!.first.displayName, 'Lina Haddad');
    expect(api.lastBookingPaymentMethod, 'wallet_credit');
    expect(api.lastBookingContactEmail, 'pax@shamell.test');
    expect(api.lastTicketPassengerIds, const <String>['adult_1', 'adult_2']);
    expect(api.lastTicketPassengerManifests, isNotNull);
    expect(api.lastTicketPassengerManifests!.last.displayName, 'Omar Darwish');
    expect(api.lastTicketDeliveryChannels,
        const <String>['wallet_pass', 'pdf', 'email']);
  });
}
