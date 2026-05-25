enum CoachRealtimeFeedKind {
  tripUpdates,
  vehiclePositions,
  serviceAlerts,
}

const _coachCurrencySyp = 'SYP';

bool _isCoachCurrency(String currency) => currency == _coachCurrencySyp;

Duration coachRealtimeFreshnessBudget(CoachRealtimeFeedKind kind) {
  switch (kind) {
    case CoachRealtimeFeedKind.tripUpdates:
    case CoachRealtimeFeedKind.vehiclePositions:
      return const Duration(seconds: 90);
    case CoachRealtimeFeedKind.serviceAlerts:
      return const Duration(minutes: 10);
  }
}

bool coachRealtimeFeedIsFresh({
  required CoachRealtimeFeedKind kind,
  required DateTime observedAt,
  DateTime? now,
}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final normalizedObservedAt = observedAt.toUtc();
  if (normalizedObservedAt.isAfter(reference)) {
    return false;
  }
  return reference.difference(normalizedObservedAt) <=
      coachRealtimeFreshnessBudget(kind);
}

enum CoachOperatorIntegrationMode { feed, api, hybrid }

String coachOperatorIntegrationModeWireValue(
    CoachOperatorIntegrationMode mode) {
  switch (mode) {
    case CoachOperatorIntegrationMode.feed:
      return 'feed';
    case CoachOperatorIntegrationMode.api:
      return 'api';
    case CoachOperatorIntegrationMode.hybrid:
      return 'hybrid';
  }
}

CoachOperatorIntegrationMode? coachOperatorIntegrationModeFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'feed':
      return CoachOperatorIntegrationMode.feed;
    case 'api':
      return CoachOperatorIntegrationMode.api;
    case 'hybrid':
      return CoachOperatorIntegrationMode.hybrid;
    default:
      return null;
  }
}

enum CoachWalletBucketType {
  cashBalance,
  promoCredit,
  refundCredit,
  giftCardCredit,
  corporateCredit,
}

String coachWalletBucketTypeWireValue(CoachWalletBucketType type) {
  switch (type) {
    case CoachWalletBucketType.cashBalance:
      return 'cash_balance';
    case CoachWalletBucketType.promoCredit:
      return 'promo_credit';
    case CoachWalletBucketType.refundCredit:
      return 'refund_credit';
    case CoachWalletBucketType.giftCardCredit:
      return 'gift_card_credit';
    case CoachWalletBucketType.corporateCredit:
      return 'corporate_credit';
  }
}

CoachWalletBucketType? coachWalletBucketTypeFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'cash_balance':
      return CoachWalletBucketType.cashBalance;
    case 'promo_credit':
      return CoachWalletBucketType.promoCredit;
    case 'refund_credit':
      return CoachWalletBucketType.refundCredit;
    case 'gift_card_credit':
      return CoachWalletBucketType.giftCardCredit;
    case 'corporate_credit':
      return CoachWalletBucketType.corporateCredit;
    default:
      return null;
  }
}

class CoachWalletBucket {
  final CoachWalletBucketType type;
  final String currency;
  final int balanceMinorUnits;
  final String? expiresAtIso;

  const CoachWalletBucket({
    required this.type,
    required this.currency,
    required this.balanceMinorUnits,
    this.expiresAtIso,
  });

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': coachWalletBucketTypeWireValue(type),
      'currency': currency,
      'balance_minor_units': balanceMinorUnits,
      if ((expiresAtIso ?? '').trim().isNotEmpty) 'expires_at': expiresAtIso,
    };
  }

  static CoachWalletBucket? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type =
        coachWalletBucketTypeFromWire((raw['type'] ?? '').toString().trim());
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final balanceMinorUnits = raw['balance_minor_units'];
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    if (type == null ||
        !_isCoachCurrency(currency) ||
        balanceMinorUnits is! int ||
        balanceMinorUnits < 0) {
      return null;
    }
    return CoachWalletBucket(
      type: type,
      currency: currency,
      balanceMinorUnits: balanceMinorUnits,
      expiresAtIso: expiresAtIso.isEmpty ? null : expiresAtIso,
    );
  }
}

class CoachWalletSnapshot {
  final String customerId;
  final List<CoachWalletBucket> buckets;

  const CoachWalletSnapshot({
    required this.customerId,
    required this.buckets,
  });

  bool hasStrictBucketSegregation() {
    final seen = <CoachWalletBucketType>{};
    for (final bucket in buckets) {
      if (!seen.add(bucket.type)) {
        return false;
      }
    }
    return true;
  }

  int bucketBalance(CoachWalletBucketType type) {
    for (final bucket in buckets) {
      if (bucket.type == type) return bucket.balanceMinorUnits;
    }
    return 0;
  }

  static CoachWalletSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final customerId = (raw['customer_id'] ?? '').toString().trim();
    final bucketsRaw = raw['buckets'];
    if (customerId.isEmpty || bucketsRaw is! List) return null;
    final buckets = bucketsRaw
        .map(CoachWalletBucket.fromJson)
        .whereType<CoachWalletBucket>()
        .toList(growable: false);
    if (buckets.isEmpty) return null;
    final snapshot = CoachWalletSnapshot(
      customerId: customerId,
      buckets: buckets,
    );
    if (!snapshot.hasStrictBucketSegregation()) {
      return null;
    }
    return snapshot;
  }
}

enum CoachBookingLifecycleState {
  searchResulted,
  offerCreated,
  holdCreated,
  paymentPending,
  paymentAuthorized,
  bookingPending,
  ticketed,
  partiallyTicketed,
  cancelled,
  refundRequested,
  refundApproved,
  refunded,
  boarded,
  noShow,
}

String coachBookingLifecycleWireValue(CoachBookingLifecycleState state) {
  switch (state) {
    case CoachBookingLifecycleState.searchResulted:
      return 'search_resulted';
    case CoachBookingLifecycleState.offerCreated:
      return 'offer_created';
    case CoachBookingLifecycleState.holdCreated:
      return 'hold_created';
    case CoachBookingLifecycleState.paymentPending:
      return 'payment_pending';
    case CoachBookingLifecycleState.paymentAuthorized:
      return 'payment_authorized';
    case CoachBookingLifecycleState.bookingPending:
      return 'booking_pending';
    case CoachBookingLifecycleState.ticketed:
      return 'ticketed';
    case CoachBookingLifecycleState.partiallyTicketed:
      return 'partially_ticketed';
    case CoachBookingLifecycleState.cancelled:
      return 'cancelled';
    case CoachBookingLifecycleState.refundRequested:
      return 'refund_requested';
    case CoachBookingLifecycleState.refundApproved:
      return 'refund_approved';
    case CoachBookingLifecycleState.refunded:
      return 'refunded';
    case CoachBookingLifecycleState.boarded:
      return 'boarded';
    case CoachBookingLifecycleState.noShow:
      return 'no_show';
  }
}

CoachBookingLifecycleState? coachBookingLifecycleFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'search_resulted':
      return CoachBookingLifecycleState.searchResulted;
    case 'offer_created':
      return CoachBookingLifecycleState.offerCreated;
    case 'hold_created':
      return CoachBookingLifecycleState.holdCreated;
    case 'payment_pending':
      return CoachBookingLifecycleState.paymentPending;
    case 'payment_authorized':
      return CoachBookingLifecycleState.paymentAuthorized;
    case 'booking_pending':
      return CoachBookingLifecycleState.bookingPending;
    case 'ticketed':
      return CoachBookingLifecycleState.ticketed;
    case 'partially_ticketed':
      return CoachBookingLifecycleState.partiallyTicketed;
    case 'cancelled':
    case 'canceled':
      return CoachBookingLifecycleState.cancelled;
    case 'refund_requested':
      return CoachBookingLifecycleState.refundRequested;
    case 'refund_approved':
      return CoachBookingLifecycleState.refundApproved;
    case 'refunded':
      return CoachBookingLifecycleState.refunded;
    case 'boarded':
      return CoachBookingLifecycleState.boarded;
    case 'no_show':
      return CoachBookingLifecycleState.noShow;
    default:
      return null;
  }
}

bool coachBookingLifecycleCanTransition({
  required CoachBookingLifecycleState from,
  required CoachBookingLifecycleState to,
}) {
  if (from == to) return true;
  switch (from) {
    case CoachBookingLifecycleState.searchResulted:
      return to == CoachBookingLifecycleState.offerCreated;
    case CoachBookingLifecycleState.offerCreated:
      return to == CoachBookingLifecycleState.holdCreated ||
          to == CoachBookingLifecycleState.cancelled;
    case CoachBookingLifecycleState.holdCreated:
      return to == CoachBookingLifecycleState.paymentPending ||
          to == CoachBookingLifecycleState.cancelled;
    case CoachBookingLifecycleState.paymentPending:
      return to == CoachBookingLifecycleState.paymentAuthorized ||
          to == CoachBookingLifecycleState.cancelled;
    case CoachBookingLifecycleState.paymentAuthorized:
      return to == CoachBookingLifecycleState.bookingPending ||
          to == CoachBookingLifecycleState.cancelled;
    case CoachBookingLifecycleState.bookingPending:
      return to == CoachBookingLifecycleState.ticketed ||
          to == CoachBookingLifecycleState.partiallyTicketed ||
          to == CoachBookingLifecycleState.cancelled;
    case CoachBookingLifecycleState.ticketed:
      return to == CoachBookingLifecycleState.refundRequested ||
          to == CoachBookingLifecycleState.boarded ||
          to == CoachBookingLifecycleState.noShow;
    case CoachBookingLifecycleState.partiallyTicketed:
      return to == CoachBookingLifecycleState.ticketed ||
          to == CoachBookingLifecycleState.refundRequested ||
          to == CoachBookingLifecycleState.cancelled;
    case CoachBookingLifecycleState.refundRequested:
      return to == CoachBookingLifecycleState.refundApproved ||
          to == CoachBookingLifecycleState.cancelled;
    case CoachBookingLifecycleState.refundApproved:
      return to == CoachBookingLifecycleState.refunded;
    case CoachBookingLifecycleState.refunded:
    case CoachBookingLifecycleState.boarded:
    case CoachBookingLifecycleState.noShow:
    case CoachBookingLifecycleState.cancelled:
      return false;
  }
}

enum CoachHoldStatus { active, expired, converted, released }

String coachHoldStatusWireValue(CoachHoldStatus status) {
  switch (status) {
    case CoachHoldStatus.active:
      return 'active';
    case CoachHoldStatus.expired:
      return 'expired';
    case CoachHoldStatus.converted:
      return 'converted';
    case CoachHoldStatus.released:
      return 'released';
  }
}

CoachHoldStatus? coachHoldStatusFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'active':
      return CoachHoldStatus.active;
    case 'expired':
      return CoachHoldStatus.expired;
    case 'converted':
      return CoachHoldStatus.converted;
    case 'released':
      return CoachHoldStatus.released;
    default:
      return null;
  }
}

class CoachOffer {
  final String offerId;
  final String operatorId;
  final String itineraryId;
  final String currency;
  final int totalMinorUnits;
  final int seatsRequested;
  final bool holdSupported;
  final bool changeable;
  final bool refundable;
  final String expiresAtIso;

  const CoachOffer({
    required this.offerId,
    required this.operatorId,
    required this.itineraryId,
    required this.currency,
    required this.totalMinorUnits,
    required this.seatsRequested,
    required this.holdSupported,
    required this.changeable,
    required this.refundable,
    required this.expiresAtIso,
  });

  bool isExpired({DateTime? now}) {
    final expiresAt = DateTime.tryParse(expiresAtIso);
    if (expiresAt == null) return true;
    final reference = (now ?? DateTime.now()).toUtc();
    return !expiresAt.toUtc().isAfter(reference);
  }

  static CoachOffer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final offerId = (raw['offer_id'] ?? '').toString().trim();
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final itineraryId = (raw['itinerary_id'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final totalMinorUnits = raw['total_minor_units'];
    final seatsRequested = raw['seats_requested'];
    final holdSupported = raw['hold_supported'];
    final changeable = raw['changeable'];
    final refundable = raw['refundable'];
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    if (offerId.isEmpty ||
        operatorId.isEmpty ||
        itineraryId.isEmpty ||
        !_isCoachCurrency(currency) ||
        totalMinorUnits is! int ||
        totalMinorUnits < 0 ||
        seatsRequested is! int ||
        seatsRequested <= 0 ||
        holdSupported is! bool ||
        changeable is! bool ||
        refundable is! bool ||
        expiresAtIso.isEmpty) {
      return null;
    }
    return CoachOffer(
      offerId: offerId,
      operatorId: operatorId,
      itineraryId: itineraryId,
      currency: currency,
      totalMinorUnits: totalMinorUnits,
      seatsRequested: seatsRequested,
      holdSupported: holdSupported,
      changeable: changeable,
      refundable: refundable,
      expiresAtIso: expiresAtIso,
    );
  }
}

class CoachSeatAssignment {
  final String passengerId;
  final String seatNumber;

  const CoachSeatAssignment({
    required this.passengerId,
    required this.seatNumber,
  });

  static CoachSeatAssignment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final passengerId = (raw['passenger_id'] ?? '').toString().trim();
    final seatNumber = (raw['seat_number'] ?? '').toString().trim();
    if (passengerId.isEmpty || seatNumber.isEmpty) {
      return null;
    }
    return CoachSeatAssignment(
      passengerId: passengerId,
      seatNumber: seatNumber,
    );
  }
}

class CoachHold {
  final String holdId;
  final String offerId;
  final String? operatorReference;
  final String expiresAtIso;
  final CoachHoldStatus status;
  final List<CoachSeatAssignment> seatAssignments;

  const CoachHold({
    required this.holdId,
    required this.offerId,
    required this.operatorReference,
    required this.expiresAtIso,
    required this.status,
    required this.seatAssignments,
  });

  static CoachHold? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final holdId = (raw['hold_id'] ?? '').toString().trim();
    final offerId = (raw['offer_id'] ?? '').toString().trim();
    final operatorReference =
        (raw['operator_reference'] ?? '').toString().trim();
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    final status =
        coachHoldStatusFromWire((raw['status'] ?? '').toString().trim());
    final seatAssignmentsRaw = raw['seat_assignments'];
    if (holdId.isEmpty ||
        offerId.isEmpty ||
        expiresAtIso.isEmpty ||
        status == null) {
      return null;
    }
    final seatAssignments = seatAssignmentsRaw is List
        ? seatAssignmentsRaw
            .map(CoachSeatAssignment.fromJson)
            .whereType<CoachSeatAssignment>()
            .toList(growable: false)
        : const <CoachSeatAssignment>[];
    return CoachHold(
      holdId: holdId,
      offerId: offerId,
      operatorReference: operatorReference.isEmpty ? null : operatorReference,
      expiresAtIso: expiresAtIso,
      status: status,
      seatAssignments: seatAssignments,
    );
  }
}

class CoachBooking {
  final String bookingId;
  final String offerId;
  final String? holdId;
  final String? operatorBookingReference;
  final CoachBookingLifecycleState state;
  final String currency;
  final int totalMinorUnits;
  final int passengerCount;
  final String createdAtIso;

  const CoachBooking({
    required this.bookingId,
    required this.offerId,
    required this.holdId,
    required this.operatorBookingReference,
    required this.state,
    required this.currency,
    required this.totalMinorUnits,
    required this.passengerCount,
    required this.createdAtIso,
  });

  static CoachBooking? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final offerId = (raw['offer_id'] ?? '').toString().trim();
    final holdId = (raw['hold_id'] ?? '').toString().trim();
    final operatorBookingReference =
        (raw['operator_booking_reference'] ?? '').toString().trim();
    final state =
        coachBookingLifecycleFromWire((raw['state'] ?? '').toString().trim());
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final totalMinorUnits = raw['total_minor_units'];
    final passengerCount = raw['passenger_count'];
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    if (bookingId.isEmpty ||
        offerId.isEmpty ||
        state == null ||
        !_isCoachCurrency(currency) ||
        totalMinorUnits is! int ||
        totalMinorUnits < 0 ||
        passengerCount is! int ||
        passengerCount <= 0 ||
        createdAtIso.isEmpty) {
      return null;
    }
    return CoachBooking(
      bookingId: bookingId,
      offerId: offerId,
      holdId: holdId.isEmpty ? null : holdId,
      operatorBookingReference:
          operatorBookingReference.isEmpty ? null : operatorBookingReference,
      state: state,
      currency: currency,
      totalMinorUnits: totalMinorUnits,
      passengerCount: passengerCount,
      createdAtIso: createdAtIso,
    );
  }
}

enum CoachPassengerRiderCategory { adult, child, student, senior }

String coachPassengerRiderCategoryWireValue(
    CoachPassengerRiderCategory category) {
  switch (category) {
    case CoachPassengerRiderCategory.adult:
      return 'adult';
    case CoachPassengerRiderCategory.child:
      return 'child';
    case CoachPassengerRiderCategory.student:
      return 'student';
    case CoachPassengerRiderCategory.senior:
      return 'senior';
  }
}

CoachPassengerRiderCategory? coachPassengerRiderCategoryFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'adult':
      return CoachPassengerRiderCategory.adult;
    case 'child':
      return CoachPassengerRiderCategory.child;
    case 'student':
      return CoachPassengerRiderCategory.student;
    case 'senior':
      return CoachPassengerRiderCategory.senior;
    default:
      return null;
  }
}

class CoachPassengerManifest {
  final String passengerId;
  final String givenName;
  final String familyName;
  final CoachPassengerRiderCategory riderCategory;
  final String? nationalityCode;

  const CoachPassengerManifest({
    required this.passengerId,
    required this.givenName,
    required this.familyName,
    required this.riderCategory,
    required this.nationalityCode,
  });

  String get displayName => '$givenName $familyName'.trim();

  Map<String, Object?> toJson() {
    final nationality = (nationalityCode ?? '').trim().toUpperCase();
    return <String, Object?>{
      'passenger_id': passengerId,
      'given_name': givenName,
      'family_name': familyName,
      'rider_category': coachPassengerRiderCategoryWireValue(riderCategory),
      if (nationality.isNotEmpty) 'nationality_code': nationality,
    };
  }

  static CoachPassengerManifest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final passengerId = (raw['passenger_id'] ?? '').toString().trim();
    final givenName = (raw['given_name'] ?? '').toString().trim();
    final familyName = (raw['family_name'] ?? '').toString().trim();
    final riderCategory = coachPassengerRiderCategoryFromWire(
      (raw['rider_category'] ?? '').toString().trim(),
    );
    final nationalityCode =
        (raw['nationality_code'] ?? '').toString().trim().toUpperCase();
    if (passengerId.isEmpty ||
        givenName.isEmpty ||
        familyName.isEmpty ||
        riderCategory == null ||
        (nationalityCode.isNotEmpty &&
            !RegExp(r'^[A-Z]{2}$').hasMatch(nationalityCode))) {
      return null;
    }
    return CoachPassengerManifest(
      passengerId: passengerId,
      givenName: givenName,
      familyName: familyName,
      riderCategory: riderCategory,
      nationalityCode: nationalityCode.isEmpty ? null : nationalityCode,
    );
  }
}

enum CoachTicketStatus { active, voided, used }

String coachTicketStatusWireValue(CoachTicketStatus status) {
  switch (status) {
    case CoachTicketStatus.active:
      return 'active';
    case CoachTicketStatus.voided:
      return 'voided';
    case CoachTicketStatus.used:
      return 'used';
  }
}

CoachTicketStatus? coachTicketStatusFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'active':
      return CoachTicketStatus.active;
    case 'voided':
      return CoachTicketStatus.voided;
    case 'used':
      return CoachTicketStatus.used;
    default:
      return null;
  }
}

List<String>? _coachStringList(Object? raw) {
  if (raw is! List) return null;
  final values = raw
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (values.isEmpty) return null;
  return values;
}

class CoachTicketCoupon {
  final String ticketId;
  final String bookingId;
  final String couponId;
  final String passengerId;
  final List<String> segmentIds;
  final CoachTicketStatus status;
  final CoachManifestBoardingState? boardingState;
  final String? operatorTicketReference;
  final String? qrPayloadRef;
  final List<CoachTicketArtifact> artifacts;
  final String issuedAtIso;
  final String? revokedAtIso;

  const CoachTicketCoupon({
    required this.ticketId,
    required this.bookingId,
    required this.couponId,
    required this.passengerId,
    required this.segmentIds,
    required this.status,
    this.boardingState,
    required this.operatorTicketReference,
    required this.qrPayloadRef,
    this.artifacts = const <CoachTicketArtifact>[],
    required this.issuedAtIso,
    required this.revokedAtIso,
  });

  CoachTicketArtifact? artifactByKind(String kind) {
    final normalized = kind.trim().toLowerCase();
    for (final artifact in artifacts) {
      if (artifact.artifactKind.toLowerCase() == normalized ||
          artifact.deliveryChannel.toLowerCase() == normalized) {
        return artifact;
      }
    }
    return null;
  }

  static CoachTicketCoupon? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ticketId = (raw['ticket_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final couponId = (raw['coupon_id'] ?? '').toString().trim();
    final passengerId = (raw['passenger_id'] ?? '').toString().trim();
    final segmentIds = _coachStringList(raw['segment_ids']);
    final status =
        coachTicketStatusFromWire((raw['status'] ?? '').toString().trim());
    final boardingState = coachManifestBoardingStateFromWire(
      (raw['boarding_state'] ?? '').toString().trim(),
    );
    final operatorTicketReference =
        (raw['operator_ticket_reference'] ?? '').toString().trim();
    final qrPayloadRef = (raw['qr_payload_ref'] ?? '').toString().trim();
    final artifactsRaw = raw['artifacts'];
    final issuedAtIso = (raw['issued_at'] ?? '').toString().trim();
    final revokedAtIso = (raw['revoked_at'] ?? '').toString().trim();
    if (ticketId.isEmpty ||
        bookingId.isEmpty ||
        couponId.isEmpty ||
        passengerId.isEmpty ||
        segmentIds == null ||
        status == null ||
        issuedAtIso.isEmpty) {
      return null;
    }
    final artifacts = artifactsRaw is List
        ? artifactsRaw
            .map(CoachTicketArtifact.fromJson)
            .whereType<CoachTicketArtifact>()
            .toList(growable: false)
        : const <CoachTicketArtifact>[];
    return CoachTicketCoupon(
      ticketId: ticketId,
      bookingId: bookingId,
      couponId: couponId,
      passengerId: passengerId,
      segmentIds: segmentIds,
      status: status,
      boardingState: boardingState,
      operatorTicketReference:
          operatorTicketReference.isEmpty ? null : operatorTicketReference,
      qrPayloadRef: qrPayloadRef.isEmpty ? null : qrPayloadRef,
      artifacts: artifacts,
      issuedAtIso: issuedAtIso,
      revokedAtIso: revokedAtIso.isEmpty ? null : revokedAtIso,
    );
  }
}

class CoachTicketArtifact {
  final String artifactId;
  final String ticketId;
  final String bookingId;
  final String artifactKind;
  final String deliveryChannel;
  final String fileName;
  final String mimeType;
  final int contentLengthBytes;
  final String downloadPath;

  const CoachTicketArtifact({
    required this.artifactId,
    required this.ticketId,
    required this.bookingId,
    required this.artifactKind,
    required this.deliveryChannel,
    required this.fileName,
    required this.mimeType,
    required this.contentLengthBytes,
    required this.downloadPath,
  });

  static CoachTicketArtifact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final artifactId = (raw['artifact_id'] ?? '').toString().trim();
    final ticketId = (raw['ticket_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final artifactKind = (raw['artifact_kind'] ?? '').toString().trim();
    final deliveryChannel = (raw['delivery_channel'] ?? '').toString().trim();
    final fileName = (raw['file_name'] ?? '').toString().trim();
    final mimeType = (raw['mime_type'] ?? '').toString().trim();
    final downloadPath = (raw['download_path'] ?? '').toString().trim();
    final rawContentLength = raw['content_length_bytes'];
    final contentLengthBytes = rawContentLength is int
        ? rawContentLength
        : rawContentLength is num
            ? rawContentLength.toInt()
            : -1;
    if (artifactId.isEmpty ||
        ticketId.isEmpty ||
        bookingId.isEmpty ||
        artifactKind.isEmpty ||
        deliveryChannel.isEmpty ||
        fileName.isEmpty ||
        mimeType.isEmpty ||
        downloadPath.isEmpty ||
        contentLengthBytes < 0) {
      return null;
    }
    return CoachTicketArtifact(
      artifactId: artifactId,
      ticketId: ticketId,
      bookingId: bookingId,
      artifactKind: artifactKind,
      deliveryChannel: deliveryChannel,
      fileName: fileName,
      mimeType: mimeType,
      contentLengthBytes: contentLengthBytes,
      downloadPath: downloadPath,
    );
  }
}

enum CoachRefundKind { originalPayment, refundCredit }

String coachRefundKindWireValue(CoachRefundKind kind) {
  switch (kind) {
    case CoachRefundKind.originalPayment:
      return 'original_payment';
    case CoachRefundKind.refundCredit:
      return 'refund_credit';
  }
}

CoachRefundKind? coachRefundKindFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'original_payment':
      return CoachRefundKind.originalPayment;
    case 'refund_credit':
      return CoachRefundKind.refundCredit;
    default:
      return null;
  }
}

class CoachRefundOption {
  final CoachRefundKind kind;
  final String label;
  final String currency;
  final int refundMinorUnits;
  final int feeMinorUnits;
  final String? expiresAtIso;

  const CoachRefundOption({
    required this.kind,
    required this.label,
    required this.currency,
    required this.refundMinorUnits,
    required this.feeMinorUnits,
    required this.expiresAtIso,
  });

  static CoachRefundOption? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = coachRefundKindFromWire((raw['kind'] ?? '').toString().trim());
    final label = (raw['label'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final refundMinorUnits = raw['refund_minor_units'];
    final feeMinorUnits = raw['fee_minor_units'];
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    if (kind == null ||
        label.isEmpty ||
        !_isCoachCurrency(currency) ||
        refundMinorUnits is! int ||
        refundMinorUnits < 0 ||
        feeMinorUnits is! int ||
        feeMinorUnits < 0) {
      return null;
    }
    return CoachRefundOption(
      kind: kind,
      label: label,
      currency: currency,
      refundMinorUnits: refundMinorUnits,
      feeMinorUnits: feeMinorUnits,
      expiresAtIso: expiresAtIso.isEmpty ? null : expiresAtIso,
    );
  }
}

class CoachRefundEligibility {
  final String bookingId;
  final CoachBookingLifecycleState bookingState;
  final bool refundable;
  final String currency;
  final String? reason;
  final String? refundCutoffAtIso;
  final CoachRefundKind? recommendedKind;
  final bool ticketsVoidRequired;
  final List<CoachRefundOption> options;

  const CoachRefundEligibility({
    required this.bookingId,
    required this.bookingState,
    required this.refundable,
    required this.currency,
    required this.reason,
    required this.refundCutoffAtIso,
    required this.recommendedKind,
    required this.ticketsVoidRequired,
    required this.options,
  });

  CoachRefundOption? optionForKind(CoachRefundKind kind) {
    for (final option in options) {
      if (option.kind == kind) {
        return option;
      }
    }
    return null;
  }

  static CoachRefundEligibility? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final bookingState = coachBookingLifecycleFromWire(
      (raw['booking_state'] ?? '').toString().trim(),
    );
    final refundable = raw['refundable'];
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final reason = (raw['reason'] ?? '').toString().trim();
    final refundCutoffAtIso = (raw['refund_cutoff_at'] ?? '').toString().trim();
    final recommendedKind = coachRefundKindFromWire(
      (raw['recommended_kind'] ?? '').toString().trim(),
    );
    final ticketsVoidRequired = raw['tickets_void_required'];
    final optionsRaw = raw['options'];
    if (bookingId.isEmpty ||
        bookingState == null ||
        refundable is! bool ||
        !_isCoachCurrency(currency) ||
        ticketsVoidRequired is! bool ||
        optionsRaw is! List) {
      return null;
    }
    final options = optionsRaw
        .map(CoachRefundOption.fromJson)
        .whereType<CoachRefundOption>()
        .toList(growable: false);
    if (refundable && options.isEmpty) {
      return null;
    }
    return CoachRefundEligibility(
      bookingId: bookingId,
      bookingState: bookingState,
      refundable: refundable,
      currency: currency,
      reason: reason.isEmpty ? null : reason,
      refundCutoffAtIso: refundCutoffAtIso.isEmpty ? null : refundCutoffAtIso,
      recommendedKind: recommendedKind,
      ticketsVoidRequired: ticketsVoidRequired,
      options: options,
    );
  }
}

class CoachRefundRequestRecord {
  final String refundRequestId;
  final String bookingId;
  final String status;
  final CoachRefundKind selectedKind;
  final String currency;
  final int requestedMinorUnits;
  final int feeMinorUnits;
  final List<String> ticketIds;
  final String? reason;
  final String createdAtIso;

  const CoachRefundRequestRecord({
    required this.refundRequestId,
    required this.bookingId,
    required this.status,
    required this.selectedKind,
    required this.currency,
    required this.requestedMinorUnits,
    required this.feeMinorUnits,
    required this.ticketIds,
    required this.reason,
    required this.createdAtIso,
  });

  static CoachRefundRequestRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final refundRequestId = (raw['refund_request_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final selectedKind = coachRefundKindFromWire(
      (raw['selected_kind'] ?? '').toString().trim(),
    );
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final requestedMinorUnits = raw['requested_minor_units'];
    final feeMinorUnits = raw['fee_minor_units'];
    final ticketIds = _coachStringList(raw['ticket_ids']);
    final reason = (raw['reason'] ?? '').toString().trim();
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    if (refundRequestId.isEmpty ||
        bookingId.isEmpty ||
        status.isEmpty ||
        selectedKind == null ||
        !_isCoachCurrency(currency) ||
        requestedMinorUnits is! int ||
        requestedMinorUnits < 0 ||
        feeMinorUnits is! int ||
        feeMinorUnits < 0 ||
        ticketIds == null ||
        createdAtIso.isEmpty) {
      return null;
    }
    return CoachRefundRequestRecord(
      refundRequestId: refundRequestId,
      bookingId: bookingId,
      status: status,
      selectedKind: selectedKind,
      currency: currency,
      requestedMinorUnits: requestedMinorUnits,
      feeMinorUnits: feeMinorUnits,
      ticketIds: ticketIds,
      reason: reason.isEmpty ? null : reason,
      createdAtIso: createdAtIso,
    );
  }
}

class CoachChangeOption {
  final String targetOfferId;
  final String journeyId;
  final String departureAtIso;
  final String arrivalAtIso;
  final String currency;
  final int fareDifferenceMinorUnits;
  final int changeFeeMinorUnits;
  final int totalDueMinorUnits;
  final bool seatMapAvailable;
  final String expiresAtIso;

  const CoachChangeOption({
    required this.targetOfferId,
    required this.journeyId,
    required this.departureAtIso,
    required this.arrivalAtIso,
    required this.currency,
    required this.fareDifferenceMinorUnits,
    required this.changeFeeMinorUnits,
    required this.totalDueMinorUnits,
    required this.seatMapAvailable,
    required this.expiresAtIso,
  });

  static CoachChangeOption? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final targetOfferId = (raw['target_offer_id'] ?? '').toString().trim();
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final arrivalAtIso = (raw['arrival_at'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final fareDifferenceMinorUnits = raw['fare_difference_minor_units'];
    final changeFeeMinorUnits = raw['change_fee_minor_units'];
    final totalDueMinorUnits = raw['total_due_minor_units'];
    final seatMapAvailable = raw['seat_map_available'];
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    if (targetOfferId.isEmpty ||
        journeyId.isEmpty ||
        departureAtIso.isEmpty ||
        arrivalAtIso.isEmpty ||
        !_isCoachCurrency(currency) ||
        fareDifferenceMinorUnits is! int ||
        changeFeeMinorUnits is! int ||
        totalDueMinorUnits is! int ||
        seatMapAvailable is! bool ||
        expiresAtIso.isEmpty) {
      return null;
    }
    return CoachChangeOption(
      targetOfferId: targetOfferId,
      journeyId: journeyId,
      departureAtIso: departureAtIso,
      arrivalAtIso: arrivalAtIso,
      currency: currency,
      fareDifferenceMinorUnits: fareDifferenceMinorUnits,
      changeFeeMinorUnits: changeFeeMinorUnits,
      totalDueMinorUnits: totalDueMinorUnits,
      seatMapAvailable: seatMapAvailable,
      expiresAtIso: expiresAtIso,
    );
  }
}

class CoachChangeEligibility {
  final String bookingId;
  final CoachBookingLifecycleState bookingState;
  final bool changeable;
  final String? reason;
  final String? changeCutoffAtIso;
  final List<CoachChangeOption> options;

  const CoachChangeEligibility({
    required this.bookingId,
    required this.bookingState,
    required this.changeable,
    required this.reason,
    required this.changeCutoffAtIso,
    required this.options,
  });

  static CoachChangeEligibility? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final bookingState = coachBookingLifecycleFromWire(
      (raw['booking_state'] ?? '').toString().trim(),
    );
    final changeable = raw['changeable'];
    final reason = (raw['reason'] ?? '').toString().trim();
    final changeCutoffAtIso = (raw['change_cutoff_at'] ?? '').toString().trim();
    final optionsRaw = raw['options'];
    if (bookingId.isEmpty ||
        bookingState == null ||
        changeable is! bool ||
        optionsRaw is! List) {
      return null;
    }
    final options = optionsRaw
        .map(CoachChangeOption.fromJson)
        .whereType<CoachChangeOption>()
        .toList(growable: false);
    if (changeable && options.isEmpty) {
      return null;
    }
    return CoachChangeEligibility(
      bookingId: bookingId,
      bookingState: bookingState,
      changeable: changeable,
      reason: reason.isEmpty ? null : reason,
      changeCutoffAtIso: changeCutoffAtIso.isEmpty ? null : changeCutoffAtIso,
      options: options,
    );
  }
}

class CoachChangeRequestRecord {
  final String changeRequestId;
  final String bookingId;
  final String status;
  final String targetOfferId;
  final String currency;
  final int fareDifferenceMinorUnits;
  final int changeFeeMinorUnits;
  final int totalDueMinorUnits;
  final String? reason;
  final String createdAtIso;

  const CoachChangeRequestRecord({
    required this.changeRequestId,
    required this.bookingId,
    required this.status,
    required this.targetOfferId,
    required this.currency,
    required this.fareDifferenceMinorUnits,
    required this.changeFeeMinorUnits,
    required this.totalDueMinorUnits,
    required this.reason,
    required this.createdAtIso,
  });

  static CoachChangeRequestRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final changeRequestId = (raw['change_request_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final targetOfferId = (raw['target_offer_id'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final fareDifferenceMinorUnits = raw['fare_difference_minor_units'];
    final changeFeeMinorUnits = raw['change_fee_minor_units'];
    final totalDueMinorUnits = raw['total_due_minor_units'];
    final reason = (raw['reason'] ?? '').toString().trim();
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    if (changeRequestId.isEmpty ||
        bookingId.isEmpty ||
        status.isEmpty ||
        targetOfferId.isEmpty ||
        !_isCoachCurrency(currency) ||
        fareDifferenceMinorUnits is! int ||
        changeFeeMinorUnits is! int ||
        totalDueMinorUnits is! int ||
        createdAtIso.isEmpty) {
      return null;
    }
    return CoachChangeRequestRecord(
      changeRequestId: changeRequestId,
      bookingId: bookingId,
      status: status,
      targetOfferId: targetOfferId,
      currency: currency,
      fareDifferenceMinorUnits: fareDifferenceMinorUnits,
      changeFeeMinorUnits: changeFeeMinorUnits,
      totalDueMinorUnits: totalDueMinorUnits,
      reason: reason.isEmpty ? null : reason,
      createdAtIso: createdAtIso,
    );
  }
}

enum CoachBoardingScanStatus { scanned, denied, duplicate, revoked, noShow }

String coachBoardingScanStatusWireValue(CoachBoardingScanStatus status) {
  switch (status) {
    case CoachBoardingScanStatus.scanned:
      return 'scanned';
    case CoachBoardingScanStatus.denied:
      return 'denied';
    case CoachBoardingScanStatus.duplicate:
      return 'duplicate';
    case CoachBoardingScanStatus.revoked:
      return 'revoked';
    case CoachBoardingScanStatus.noShow:
      return 'no_show';
  }
}

CoachBoardingScanStatus? coachBoardingScanStatusFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'scanned':
      return CoachBoardingScanStatus.scanned;
    case 'denied':
      return CoachBoardingScanStatus.denied;
    case 'duplicate':
      return CoachBoardingScanStatus.duplicate;
    case 'revoked':
      return CoachBoardingScanStatus.revoked;
    case 'no_show':
      return CoachBoardingScanStatus.noShow;
    default:
      return null;
  }
}

enum CoachManifestBoardingState {
  notBoarded,
  boarded,
  denied,
  duplicateAttempt,
  revoked,
  noShow,
}

CoachManifestBoardingState? coachManifestBoardingStateFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'not_boarded':
      return CoachManifestBoardingState.notBoarded;
    case 'boarded':
      return CoachManifestBoardingState.boarded;
    case 'denied':
      return CoachManifestBoardingState.denied;
    case 'duplicate_attempt':
      return CoachManifestBoardingState.duplicateAttempt;
    case 'revoked':
      return CoachManifestBoardingState.revoked;
    case 'no_show':
      return CoachManifestBoardingState.noShow;
    default:
      return null;
  }
}

class CoachBoardingEvent {
  final String boardingEventId;
  final String ticketId;
  final String tripId;
  final CoachBoardingScanStatus scanStatus;
  final String capturedAtIso;
  final bool offlineCaptured;
  final String? deviceId;
  final String? note;

  const CoachBoardingEvent({
    required this.boardingEventId,
    required this.ticketId,
    required this.tripId,
    required this.scanStatus,
    required this.capturedAtIso,
    required this.offlineCaptured,
    required this.deviceId,
    this.note,
  });

  static CoachBoardingEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final boardingEventId = (raw['boarding_event_id'] ?? '').toString().trim();
    final ticketId = (raw['ticket_id'] ?? '').toString().trim();
    final tripId = (raw['trip_id'] ?? '').toString().trim();
    final scanStatus = coachBoardingScanStatusFromWire(
      (raw['scan_status'] ?? '').toString().trim(),
    );
    final capturedAtIso = (raw['captured_at'] ?? '').toString().trim();
    final offlineCaptured = raw['offline_captured'];
    final deviceId = (raw['device_id'] ?? '').toString().trim();
    final note = (raw['note'] ?? '').toString().trim();
    if (boardingEventId.isEmpty ||
        ticketId.isEmpty ||
        tripId.isEmpty ||
        scanStatus == null ||
        capturedAtIso.isEmpty ||
        offlineCaptured is! bool) {
      return null;
    }
    return CoachBoardingEvent(
      boardingEventId: boardingEventId,
      ticketId: ticketId,
      tripId: tripId,
      scanStatus: scanStatus,
      capturedAtIso: capturedAtIso,
      offlineCaptured: offlineCaptured,
      deviceId: deviceId.isEmpty ? null : deviceId,
      note: note.isEmpty ? null : note,
    );
  }
}

enum CoachSettlementBasis {
  ticketed,
  departure,
  boarded,
  periodClosed,
  refundWindowClosed,
}

String coachSettlementBasisWireValue(CoachSettlementBasis basis) {
  switch (basis) {
    case CoachSettlementBasis.ticketed:
      return 'ticketed';
    case CoachSettlementBasis.departure:
      return 'departure';
    case CoachSettlementBasis.boarded:
      return 'boarded';
    case CoachSettlementBasis.periodClosed:
      return 'period_closed';
    case CoachSettlementBasis.refundWindowClosed:
      return 'refund_window_closed';
  }
}

CoachSettlementBasis? coachSettlementBasisFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'ticketed':
      return CoachSettlementBasis.ticketed;
    case 'departure':
      return CoachSettlementBasis.departure;
    case 'boarded':
      return CoachSettlementBasis.boarded;
    case 'period_closed':
      return CoachSettlementBasis.periodClosed;
    case 'refund_window_closed':
      return CoachSettlementBasis.refundWindowClosed;
    default:
      return null;
  }
}

class CoachSettlementLine {
  final String settlementId;
  final String operatorId;
  final String bookingId;
  final CoachSettlementBasis basis;
  final String currency;
  final int grossMinorUnits;
  final int commissionMinorUnits;
  final int refundMinorUnits;
  final int chargebackReserveMinorUnits;
  final int manualAdjustmentMinorUnits;
  final int netPayableMinorUnits;

  const CoachSettlementLine({
    required this.settlementId,
    required this.operatorId,
    required this.bookingId,
    required this.basis,
    required this.currency,
    required this.grossMinorUnits,
    required this.commissionMinorUnits,
    required this.refundMinorUnits,
    required this.chargebackReserveMinorUnits,
    required this.manualAdjustmentMinorUnits,
    required this.netPayableMinorUnits,
  });

  int get expectedNetPayableMinorUnits {
    return grossMinorUnits -
        commissionMinorUnits -
        refundMinorUnits -
        chargebackReserveMinorUnits +
        manualAdjustmentMinorUnits;
  }

  static CoachSettlementLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final settlementId = (raw['settlement_id'] ?? '').toString().trim();
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final basis =
        coachSettlementBasisFromWire((raw['basis'] ?? '').toString().trim());
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final grossMinorUnits = raw['gross_minor_units'];
    final commissionMinorUnits = raw['commission_minor_units'];
    final refundMinorUnits = raw['refund_minor_units'];
    final chargebackReserveMinorUnits = raw['chargeback_reserve_minor_units'];
    final manualAdjustmentMinorUnits = raw['manual_adjustment_minor_units'];
    final netPayableMinorUnits = raw['net_payable_minor_units'];
    if (settlementId.isEmpty ||
        operatorId.isEmpty ||
        bookingId.isEmpty ||
        basis == null ||
        !_isCoachCurrency(currency) ||
        grossMinorUnits is! int ||
        grossMinorUnits < 0 ||
        commissionMinorUnits is! int ||
        commissionMinorUnits < 0 ||
        refundMinorUnits is! int ||
        refundMinorUnits < 0 ||
        chargebackReserveMinorUnits is! int ||
        chargebackReserveMinorUnits < 0 ||
        manualAdjustmentMinorUnits is! int ||
        netPayableMinorUnits is! int) {
      return null;
    }
    final line = CoachSettlementLine(
      settlementId: settlementId,
      operatorId: operatorId,
      bookingId: bookingId,
      basis: basis,
      currency: currency,
      grossMinorUnits: grossMinorUnits,
      commissionMinorUnits: commissionMinorUnits,
      refundMinorUnits: refundMinorUnits,
      chargebackReserveMinorUnits: chargebackReserveMinorUnits,
      manualAdjustmentMinorUnits: manualAdjustmentMinorUnits,
      netPayableMinorUnits: netPayableMinorUnits,
    );
    if (line.expectedNetPayableMinorUnits != line.netPayableMinorUnits) {
      return null;
    }
    return line;
  }
}

enum CoachOpsQueueStatus {
  pendingReview,
  approved,
  rejected,
}

String coachOpsQueueStatusWireValue(CoachOpsQueueStatus status) {
  switch (status) {
    case CoachOpsQueueStatus.pendingReview:
      return 'pending_review';
    case CoachOpsQueueStatus.approved:
      return 'approved';
    case CoachOpsQueueStatus.rejected:
      return 'rejected';
  }
}

CoachOpsQueueStatus? coachOpsQueueStatusFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'pending_review':
      return CoachOpsQueueStatus.pendingReview;
    case 'approved':
      return CoachOpsQueueStatus.approved;
    case 'rejected':
      return CoachOpsQueueStatus.rejected;
    default:
      return null;
  }
}

enum CoachOpsRequestUrgency {
  medium,
  high,
  critical,
}

String coachOpsRequestUrgencyWireValue(CoachOpsRequestUrgency urgency) {
  switch (urgency) {
    case CoachOpsRequestUrgency.medium:
      return 'medium';
    case CoachOpsRequestUrgency.high:
      return 'high';
    case CoachOpsRequestUrgency.critical:
      return 'critical';
  }
}

CoachOpsRequestUrgency? coachOpsRequestUrgencyFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'medium':
      return CoachOpsRequestUrgency.medium;
    case 'high':
      return CoachOpsRequestUrgency.high;
    case 'critical':
      return CoachOpsRequestUrgency.critical;
    default:
      return null;
  }
}

enum CoachOpsRequestKind {
  refundRequest,
  changeRequest,
}

String coachOpsRequestKindWireValue(CoachOpsRequestKind kind) {
  switch (kind) {
    case CoachOpsRequestKind.refundRequest:
      return 'refund_request';
    case CoachOpsRequestKind.changeRequest:
      return 'change_request';
  }
}

CoachOpsRequestKind? coachOpsRequestKindFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'refund_request':
      return CoachOpsRequestKind.refundRequest;
    case 'change_request':
      return CoachOpsRequestKind.changeRequest;
    default:
      return null;
  }
}
