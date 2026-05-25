import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../payments/payments_idempotency.dart';
import '../session_cookie_store.dart';
import 'coach_catalog_import_run_filter_store.dart';
import 'coach_payout_import_batch_filter_store.dart';
import 'coach_payout_import_preview_history_filter_store.dart';
import 'coach_platform_contracts.dart';

const _coachCurrencySyp = 'SYP';

bool _isCoachCurrency(String currency) => currency == _coachCurrencySyp;

String? _coachApiErrorDetail(String body) {
  final normalized = body.trim();
  if (normalized.isEmpty) return null;
  try {
    final decoded = jsonDecode(normalized);
    if (decoded is Map) {
      for (final key in const <String>['detail', 'message', 'error']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
  } catch (_) {}
  return normalized;
}

List<String> _coachStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _coachStringMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  raw.forEach((key, value) {
    final normalizedKey = key.toString().trim();
    final normalizedValue = value.toString().trim();
    if (normalizedKey.isNotEmpty && normalizedValue.isNotEmpty) {
      out[normalizedKey] = normalizedValue;
    }
  });
  return out;
}

class CoachCatalogImportRunSavedViewOwnerSummary {
  final String accountId;
  final int sharedViewCount;

  const CoachCatalogImportRunSavedViewOwnerSummary({
    required this.accountId,
    required this.sharedViewCount,
  });

  static CoachCatalogImportRunSavedViewOwnerSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final accountId = (raw['account_id'] ?? '').toString().trim();
    final sharedViewCount = raw['shared_view_count'];
    if (accountId.isEmpty || sharedViewCount is! int) {
      return null;
    }
    return CoachCatalogImportRunSavedViewOwnerSummary(
      accountId: accountId,
      sharedViewCount: sharedViewCount,
    );
  }
}

List<CoachCatalogImportRunSavedViewOwnerSummary>
    _coachCatalogImportRunSavedViewOwnerSummariesFromPayload(
  Object? raw,
) {
  if (raw is! Map) {
    return const <CoachCatalogImportRunSavedViewOwnerSummary>[];
  }
  final summariesRaw = raw['shared_owner_summaries'];
  if (summariesRaw is! List) {
    return const <CoachCatalogImportRunSavedViewOwnerSummary>[];
  }
  return summariesRaw
      .map(CoachCatalogImportRunSavedViewOwnerSummary.fromJson)
      .whereType<CoachCatalogImportRunSavedViewOwnerSummary>()
      .toList(growable: false);
}

class CoachCatalogImportRunSavedViewOperatorSummary {
  final String operatorId;
  final String operatorName;
  final int sharedViewCount;

  const CoachCatalogImportRunSavedViewOperatorSummary({
    required this.operatorId,
    this.operatorName = '',
    required this.sharedViewCount,
  });

  static CoachCatalogImportRunSavedViewOperatorSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final sharedViewCount = raw['shared_view_count'];
    if (operatorId.isEmpty || sharedViewCount is! int) {
      return null;
    }
    return CoachCatalogImportRunSavedViewOperatorSummary(
      operatorId: operatorId,
      operatorName: operatorName,
      sharedViewCount: sharedViewCount,
    );
  }
}

List<CoachCatalogImportRunSavedViewOperatorSummary>
    _coachCatalogImportRunSavedViewOperatorSummariesFromPayload(
  Object? raw,
) {
  if (raw is! Map) {
    return const <CoachCatalogImportRunSavedViewOperatorSummary>[];
  }
  final summariesRaw = raw['shared_operator_summaries'];
  if (summariesRaw is! List) {
    return const <CoachCatalogImportRunSavedViewOperatorSummary>[];
  }
  return summariesRaw
      .map(CoachCatalogImportRunSavedViewOperatorSummary.fromJson)
      .whereType<CoachCatalogImportRunSavedViewOperatorSummary>()
      .toList(growable: false);
}

List<CoachCatalogImportRunSavedView>
    _coachCatalogImportRunSavedViewsFromPayload(
  Object? raw,
) {
  if (raw is! Map) return const <CoachCatalogImportRunSavedView>[];
  final savedViewsRaw = raw['saved_views'];
  if (savedViewsRaw is! List) return const <CoachCatalogImportRunSavedView>[];
  return savedViewsRaw
      .map((entry) {
        if (entry is! Map) return null;
        return CoachCatalogImportRunSavedView.fromJson(<String, Object?>{
          'view_id': entry['view_id'],
          'account_id': entry['account_id'],
          'name': entry['name'],
          'visibility_scope': entry['visibility_scope'],
          'operator_ids': entry['operator_ids'],
          'preferences': <String, Object?>{
            'status': entry['status'],
            'replay_scope': entry['replay_scope'],
            'severity': entry['severity'],
            'stage': entry['stage'],
          },
          'is_default': entry['is_default'],
          'is_favorite': entry['is_favorite'],
          'last_used_at': entry['last_used_at'],
          'can_manage': entry['can_manage'],
          'created_at': entry['created_at'],
          'updated_at': entry['updated_at'],
        });
      })
      .whereType<CoachCatalogImportRunSavedView>()
      .toList(growable: false);
}

List<CoachCatalogImportRunIssueSavedView>
    _coachCatalogImportRunIssueSavedViewsFromPayload(
  Object? raw,
) {
  if (raw is! Map) return const <CoachCatalogImportRunIssueSavedView>[];
  final savedViewsRaw = raw['saved_views'];
  if (savedViewsRaw is! List) {
    return const <CoachCatalogImportRunIssueSavedView>[];
  }
  return savedViewsRaw
      .map((entry) {
        if (entry is! Map) return null;
        return CoachCatalogImportRunIssueSavedView.fromJson(<String, Object?>{
          'view_id': entry['view_id'],
          'account_id': entry['account_id'],
          'name': entry['name'],
          'visibility_scope': entry['visibility_scope'],
          'operator_ids': entry['operator_ids'],
          'preferences': <String, Object?>{
            'severity': entry['severity'],
            'stage': entry['stage'],
          },
          'is_default': entry['is_default'],
          'is_favorite': entry['is_favorite'],
          'last_used_at': entry['last_used_at'],
          'can_manage': entry['can_manage'],
          'created_at': entry['created_at'],
          'updated_at': entry['updated_at'],
        });
      })
      .whereType<CoachCatalogImportRunIssueSavedView>()
      .toList(growable: false);
}

List<CoachPayoutImportBatchSavedView>
    _coachPayoutImportBatchSavedViewsFromPayload(
  Object? raw,
) {
  if (raw is! Map) return const <CoachPayoutImportBatchSavedView>[];
  final savedViewsRaw = raw['saved_views'];
  if (savedViewsRaw is! List) return const <CoachPayoutImportBatchSavedView>[];
  return savedViewsRaw
      .map((entry) {
        if (entry is! Map) return null;
        return CoachPayoutImportBatchSavedView.fromJson(<String, Object?>{
          'view_id': entry['view_id'],
          'account_id': entry['account_id'],
          'name': entry['name'],
          'visibility_scope': entry['visibility_scope'],
          'preferences': <String, Object?>{
            'operator_id': entry['operator_id'],
          },
          'is_default': entry['is_default'],
          'is_favorite': entry['is_favorite'],
          'last_used_at': entry['last_used_at'],
          'can_manage': entry['can_manage'],
          'created_at': entry['created_at'],
          'updated_at': entry['updated_at'],
        });
      })
      .whereType<CoachPayoutImportBatchSavedView>()
      .toList(growable: false);
}

List<CoachPayoutImportPreviewHistorySavedView>
    _coachPayoutImportPreviewSavedViewsFromPayload(
  Object? raw,
) {
  if (raw is! Map) return const <CoachPayoutImportPreviewHistorySavedView>[];
  final savedViewsRaw = raw['saved_views'];
  if (savedViewsRaw is! List) {
    return const <CoachPayoutImportPreviewHistorySavedView>[];
  }
  return savedViewsRaw
      .map((entry) {
        if (entry is! Map) return null;
        return CoachPayoutImportPreviewHistorySavedView.fromJson(
          <String, Object?>{
            'view_id': entry['view_id'],
            'account_id': entry['account_id'],
            'name': entry['name'],
            'visibility_scope': entry['visibility_scope'],
            'preferences': <String, Object?>{
              'status': entry['status'],
              'from_created_at': entry['from_created_at'],
              'to_created_at': entry['to_created_at'],
              'operator_id': entry['operator_id'],
            },
            'is_default': entry['is_default'],
            'is_favorite': entry['is_favorite'],
            'last_used_at': entry['last_used_at'],
            'can_manage': entry['can_manage'],
            'created_at': entry['created_at'],
            'updated_at': entry['updated_at'],
          },
        );
      })
      .whereType<CoachPayoutImportPreviewHistorySavedView>()
      .toList(growable: false);
}

class CoachApiException implements Exception {
  final String detail;
  final int? statusCode;

  const CoachApiException(this.detail, {this.statusCode});

  @override
  String toString() => detail;
}

class CoachOperatorFeedHealth {
  final String operatorId;
  final String operatorName;
  final String operatorIntegrationMode;
  final String feedKind;
  final String sourceKind;
  final String syncStatus;
  final String freshnessStatus;
  final String? lastAttemptedAtIso;
  final String? lastSucceededAtIso;
  final String? freshnessExpiresAtIso;
  final int recordsIngested;
  final String? errorMessage;

  const CoachOperatorFeedHealth({
    required this.operatorId,
    required this.operatorName,
    required this.operatorIntegrationMode,
    required this.feedKind,
    required this.sourceKind,
    required this.syncStatus,
    required this.freshnessStatus,
    required this.lastAttemptedAtIso,
    required this.lastSucceededAtIso,
    required this.freshnessExpiresAtIso,
    required this.recordsIngested,
    required this.errorMessage,
  });

  bool get isFresh => freshnessStatus == 'fresh';
  bool get isHealthy =>
      syncStatus == 'ok' && (isFresh || freshnessStatus == 'missing');

  static CoachOperatorFeedHealth? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final operatorIntegrationMode =
        (raw['operator_integration_mode'] ?? '').toString().trim();
    final feedKind = (raw['feed_kind'] ?? '').toString().trim();
    final sourceKind = (raw['source_kind'] ?? '').toString().trim();
    final syncStatus = (raw['sync_status'] ?? '').toString().trim();
    final freshnessStatus = (raw['freshness_status'] ?? '').toString().trim();
    final lastAttemptedAtIso =
        (raw['last_attempted_at'] ?? '').toString().trim();
    final lastSucceededAtIso =
        (raw['last_succeeded_at'] ?? '').toString().trim();
    final freshnessExpiresAtIso =
        (raw['freshness_expires_at'] ?? '').toString().trim();
    final recordsIngested = raw['records_ingested'];
    final errorMessage = (raw['error_message'] ?? '').toString().trim();
    if (operatorId.isEmpty ||
        operatorName.isEmpty ||
        operatorIntegrationMode.isEmpty ||
        feedKind.isEmpty ||
        sourceKind.isEmpty ||
        syncStatus.isEmpty ||
        freshnessStatus.isEmpty ||
        recordsIngested is! int ||
        recordsIngested < 0) {
      return null;
    }
    return CoachOperatorFeedHealth(
      operatorId: operatorId,
      operatorName: operatorName,
      operatorIntegrationMode: operatorIntegrationMode,
      feedKind: feedKind,
      sourceKind: sourceKind,
      syncStatus: syncStatus,
      freshnessStatus: freshnessStatus,
      lastAttemptedAtIso:
          lastAttemptedAtIso.isEmpty ? null : lastAttemptedAtIso,
      lastSucceededAtIso:
          lastSucceededAtIso.isEmpty ? null : lastSucceededAtIso,
      freshnessExpiresAtIso:
          freshnessExpiresAtIso.isEmpty ? null : freshnessExpiresAtIso,
      recordsIngested: recordsIngested,
      errorMessage: errorMessage.isEmpty ? null : errorMessage,
    );
  }
}

class CoachPlatformBootstrap {
  final String version;
  final List<String> surfaces;
  final List<String> commercialBoundaries;
  final List<String> integrationModes;
  final List<String> staticCatalogFeeds;
  final List<String> realtimeFeeds;
  final List<String> bookingStates;
  final List<String> walletBuckets;
  final List<String> settlementBases;
  final int tripUpdatesFreshnessSeconds;
  final int vehiclePositionsFreshnessSeconds;
  final int serviceAlertsFreshnessSeconds;
  final List<CoachOperatorFeedHealth> operatorFeedHealth;

  const CoachPlatformBootstrap({
    required this.version,
    required this.surfaces,
    required this.commercialBoundaries,
    required this.integrationModes,
    required this.staticCatalogFeeds,
    required this.realtimeFeeds,
    required this.bookingStates,
    required this.walletBuckets,
    required this.settlementBases,
    required this.tripUpdatesFreshnessSeconds,
    required this.vehiclePositionsFreshnessSeconds,
    required this.serviceAlertsFreshnessSeconds,
    required this.operatorFeedHealth,
  });

  static CoachPlatformBootstrap? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final version = (raw['version'] ?? '').toString().trim();
    final surfaces = _coachStringList(raw['surfaces']);
    final commercialBoundaries = _coachStringList(raw['commercial_boundaries']);
    final integrationModes = _coachStringList(raw['integration_modes']);
    final staticCatalogFeeds = _coachStringList(raw['static_catalog_feeds']);
    final realtimeFeeds = _coachStringList(raw['realtime_feeds']);
    final bookingStates = _coachStringList(raw['booking_states']);
    final walletBuckets = _coachStringList(raw['wallet_buckets']);
    final settlementBases = _coachStringList(raw['settlement_bases']);
    final freshness = raw['realtime_freshness_targets'];
    final operatorFeedHealth = (raw['operator_feed_health'] is List)
        ? (raw['operator_feed_health'] as List)
            .map(CoachOperatorFeedHealth.fromJson)
            .whereType<CoachOperatorFeedHealth>()
            .toList(growable: false)
        : const <CoachOperatorFeedHealth>[];
    if (version.isEmpty ||
        surfaces.isEmpty ||
        commercialBoundaries.isEmpty ||
        integrationModes.isEmpty ||
        staticCatalogFeeds.isEmpty ||
        realtimeFeeds.isEmpty ||
        bookingStates.isEmpty ||
        walletBuckets.isEmpty ||
        settlementBases.isEmpty ||
        freshness is! Map) {
      return null;
    }
    final tripUpdatesFreshnessSeconds = freshness['trip_updates_seconds'];
    final vehiclePositionsFreshnessSeconds =
        freshness['vehicle_positions_seconds'];
    final serviceAlertsFreshnessSeconds = freshness['service_alerts_seconds'];
    if (tripUpdatesFreshnessSeconds is! int ||
        vehiclePositionsFreshnessSeconds is! int ||
        serviceAlertsFreshnessSeconds is! int) {
      return null;
    }
    return CoachPlatformBootstrap(
      version: version,
      surfaces: surfaces,
      commercialBoundaries: commercialBoundaries,
      integrationModes: integrationModes,
      staticCatalogFeeds: staticCatalogFeeds,
      realtimeFeeds: realtimeFeeds,
      bookingStates: bookingStates,
      walletBuckets: walletBuckets,
      settlementBases: settlementBases,
      tripUpdatesFreshnessSeconds: tripUpdatesFreshnessSeconds,
      vehiclePositionsFreshnessSeconds: vehiclePositionsFreshnessSeconds,
      serviceAlertsFreshnessSeconds: serviceAlertsFreshnessSeconds,
      operatorFeedHealth: operatorFeedHealth,
    );
  }
}

class CoachJourneyLiveSnapshot {
  final int delayMinutes;
  final bool tripUpdatesFresh;
  final bool vehiclePositionsFresh;
  final bool serviceAlertsFresh;

  const CoachJourneyLiveSnapshot({
    required this.delayMinutes,
    required this.tripUpdatesFresh,
    required this.vehiclePositionsFresh,
    required this.serviceAlertsFresh,
  });

  static CoachJourneyLiveSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final delayMinutes = raw['delay_minutes'];
    final tripUpdatesFresh = raw['trip_updates_fresh'];
    final vehiclePositionsFresh = raw['vehicle_positions_fresh'];
    final serviceAlertsFresh = raw['service_alerts_fresh'];
    if (delayMinutes is! int ||
        tripUpdatesFresh is! bool ||
        vehiclePositionsFresh is! bool ||
        serviceAlertsFresh is! bool) {
      return null;
    }
    return CoachJourneyLiveSnapshot(
      delayMinutes: delayMinutes,
      tripUpdatesFresh: tripUpdatesFresh,
      vehiclePositionsFresh: vehiclePositionsFresh,
      serviceAlertsFresh: serviceAlertsFresh,
    );
  }
}

class CoachJourneyOption {
  final String journeyId;
  final String operatorId;
  final String operatorName;
  final CoachOperatorIntegrationMode integrationMode;
  final String departureAtIso;
  final String arrivalAtIso;
  final int durationMinutes;
  final int transferCount;
  final int seatsAvailable;
  final bool lowAvailability;
  final String currency;
  final int priceFromMinorUnits;
  final List<String> amenities;
  final bool changeable;
  final bool refundable;
  final CoachOffer bestOffer;
  final CoachJourneyLiveSnapshot live;

  const CoachJourneyOption({
    required this.journeyId,
    required this.operatorId,
    required this.operatorName,
    required this.integrationMode,
    required this.departureAtIso,
    required this.arrivalAtIso,
    required this.durationMinutes,
    required this.transferCount,
    required this.seatsAvailable,
    required this.lowAvailability,
    required this.currency,
    required this.priceFromMinorUnits,
    required this.amenities,
    required this.changeable,
    required this.refundable,
    required this.bestOffer,
    required this.live,
  });

  static CoachJourneyOption? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final integrationMode = coachOperatorIntegrationModeFromWire(
      (raw['operator_integration_mode'] ?? '').toString().trim(),
    );
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final arrivalAtIso = (raw['arrival_at'] ?? '').toString().trim();
    final durationMinutes = raw['duration_minutes'];
    final transferCount = raw['transfer_count'];
    final seatsAvailable = raw['seats_available'];
    final lowAvailability = raw['low_availability'];
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final priceFromMinorUnits = raw['price_from_minor_units'];
    final amenities = _coachStringList(raw['amenities']);
    final changeable = raw['changeable'];
    final refundable = raw['refundable'];
    final bestOffer = CoachOffer.fromJson(raw['best_offer']);
    final live = CoachJourneyLiveSnapshot.fromJson(raw['realtime']);
    if (journeyId.isEmpty ||
        operatorId.isEmpty ||
        operatorName.isEmpty ||
        integrationMode == null ||
        departureAtIso.isEmpty ||
        arrivalAtIso.isEmpty ||
        durationMinutes is! int ||
        transferCount is! int ||
        seatsAvailable is! int ||
        lowAvailability is! bool ||
        !_isCoachCurrency(currency) ||
        priceFromMinorUnits is! int ||
        amenities.isEmpty ||
        changeable is! bool ||
        refundable is! bool ||
        bestOffer == null ||
        live == null) {
      return null;
    }
    return CoachJourneyOption(
      journeyId: journeyId,
      operatorId: operatorId,
      operatorName: operatorName,
      integrationMode: integrationMode,
      departureAtIso: departureAtIso,
      arrivalAtIso: arrivalAtIso,
      durationMinutes: durationMinutes,
      transferCount: transferCount,
      seatsAvailable: seatsAvailable,
      lowAvailability: lowAvailability,
      currency: currency,
      priceFromMinorUnits: priceFromMinorUnits,
      amenities: amenities,
      changeable: changeable,
      refundable: refundable,
      bestOffer: bestOffer,
      live: live,
    );
  }
}

class CoachJourneySearchResponse {
  final String from;
  final String to;
  final String departureDate;
  final int passengers;
  final List<CoachJourneyOption> journeys;

  const CoachJourneySearchResponse({
    required this.from,
    required this.to,
    required this.departureDate,
    required this.passengers,
    required this.journeys,
  });

  static CoachJourneySearchResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final query = raw['query'];
    final journeysRaw = raw['journeys'];
    if (query is! Map || journeysRaw is! List) return null;
    final from = (query['from'] ?? '').toString().trim();
    final to = (query['to'] ?? '').toString().trim();
    final departureDate = (query['departure_date'] ?? '').toString().trim();
    final passengers = query['passengers'];
    final journeys = journeysRaw
        .map(CoachJourneyOption.fromJson)
        .whereType<CoachJourneyOption>()
        .toList(growable: false);
    if (from.isEmpty ||
        to.isEmpty ||
        departureDate.isEmpty ||
        passengers is! int ||
        passengers <= 0 ||
        journeys.isEmpty) {
      return null;
    }
    return CoachJourneySearchResponse(
      from: from,
      to: to,
      departureDate: departureDate,
      passengers: passengers,
      journeys: journeys,
    );
  }
}

class CoachBookedJourneySummary {
  final String journeyId;
  final String operatorName;
  final String from;
  final String to;
  final String departureAtIso;
  final String arrivalAtIso;
  final String statusLabel;

  const CoachBookedJourneySummary({
    required this.journeyId,
    required this.operatorName,
    required this.from,
    required this.to,
    required this.departureAtIso,
    required this.arrivalAtIso,
    required this.statusLabel,
  });

  static CoachBookedJourneySummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final from = (raw['from'] ?? '').toString().trim();
    final to = (raw['to'] ?? '').toString().trim();
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final arrivalAtIso = (raw['arrival_at'] ?? '').toString().trim();
    final statusLabel = (raw['status_label'] ?? '').toString().trim();
    if (journeyId.isEmpty ||
        operatorName.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        departureAtIso.isEmpty ||
        arrivalAtIso.isEmpty ||
        statusLabel.isEmpty) {
      return null;
    }
    return CoachBookedJourneySummary(
      journeyId: journeyId,
      operatorName: operatorName,
      from: from,
      to: to,
      departureAtIso: departureAtIso,
      arrivalAtIso: arrivalAtIso,
      statusLabel: statusLabel,
    );
  }
}

class CoachBookingShelfSummary {
  final int upcomingCount;
  final int ticketedCount;
  final int needsActionCount;

  const CoachBookingShelfSummary({
    required this.upcomingCount,
    required this.ticketedCount,
    required this.needsActionCount,
  });

  static CoachBookingShelfSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final upcomingCount = raw['upcoming_count'];
    final ticketedCount = raw['ticketed_count'];
    final needsActionCount = raw['needs_action_count'];
    if (upcomingCount is! int ||
        ticketedCount is! int ||
        needsActionCount is! int ||
        upcomingCount < 0 ||
        ticketedCount < 0 ||
        needsActionCount < 0) {
      return null;
    }
    return CoachBookingShelfSummary(
      upcomingCount: upcomingCount,
      ticketedCount: ticketedCount,
      needsActionCount: needsActionCount,
    );
  }
}

class CoachBookingShelfEntry {
  final CoachBookedJourneySummary journey;
  final CoachOffer offer;
  final CoachHold? hold;
  final CoachBooking booking;
  final List<CoachPassengerManifest> passengerManifests;
  final List<CoachTicketCoupon> tickets;

  const CoachBookingShelfEntry({
    required this.journey,
    required this.offer,
    required this.hold,
    required this.booking,
    required this.passengerManifests,
    required this.tickets,
  });

  static CoachBookingShelfEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final journey = CoachBookedJourneySummary.fromJson(raw['journey']);
    final offer = CoachOffer.fromJson(raw['offer']);
    final hold = CoachHold.fromJson(raw['hold']);
    final booking = CoachBooking.fromJson(raw['booking']);
    final passengerManifestsRaw = raw['passengers_manifest'];
    final ticketsRaw = raw['tickets'];
    if (journey == null ||
        offer == null ||
        booking == null ||
        ticketsRaw is! List) {
      return null;
    }
    final passengerManifests = passengerManifestsRaw is List
        ? passengerManifestsRaw
            .map(CoachPassengerManifest.fromJson)
            .whereType<CoachPassengerManifest>()
            .toList(growable: false)
        : const <CoachPassengerManifest>[];
    final tickets = ticketsRaw
        .map(CoachTicketCoupon.fromJson)
        .whereType<CoachTicketCoupon>()
        .toList(growable: false);
    return CoachBookingShelfEntry(
      journey: journey,
      offer: offer,
      hold: hold,
      booking: booking,
      passengerManifests: passengerManifests,
      tickets: tickets,
    );
  }
}

class CoachBookingShelfResponse {
  final CoachBookingShelfSummary summary;
  final List<CoachBookingShelfEntry> bookings;

  const CoachBookingShelfResponse({
    required this.summary,
    required this.bookings,
  });

  static CoachBookingShelfResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final summary = CoachBookingShelfSummary.fromJson(raw['summary']);
    final bookingsRaw = raw['bookings'];
    if (summary == null || bookingsRaw is! List) {
      return null;
    }
    final bookings = bookingsRaw
        .map(CoachBookingShelfEntry.fromJson)
        .whereType<CoachBookingShelfEntry>()
        .toList(growable: false);
    return CoachBookingShelfResponse(summary: summary, bookings: bookings);
  }
}

class CoachJourneyLiveResponse {
  final CoachBookedJourneySummary journey;
  final CoachOffer offer;
  final CoachHold? hold;
  final CoachBooking booking;
  final List<CoachPassengerManifest> passengerManifests;
  final List<CoachTicketCoupon> tickets;
  final CoachCrewTripSummary trip;
  final List<CoachBoardingEvent> recentEvents;
  final List<CoachOperatorFeedHealth> operatorFeedHealth;

  const CoachJourneyLiveResponse({
    required this.journey,
    required this.offer,
    required this.hold,
    required this.booking,
    required this.passengerManifests,
    required this.tickets,
    required this.trip,
    required this.recentEvents,
    required this.operatorFeedHealth,
  });

  static CoachJourneyLiveResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final journey = CoachBookedJourneySummary.fromJson(raw['journey']);
    final offer = CoachOffer.fromJson(raw['offer']);
    final hold = CoachHold.fromJson(raw['hold']);
    final booking = CoachBooking.fromJson(raw['booking']);
    final passengerManifestsRaw = raw['passengers_manifest'];
    final ticketsRaw = raw['tickets'];
    final trip = CoachCrewTripSummary.fromJson(raw['trip']);
    final recentEventsRaw = raw['recent_events'];
    final operatorFeedHealthRaw = raw['operator_feed_health'];
    if (journey == null ||
        offer == null ||
        booking == null ||
        trip == null ||
        recentEventsRaw is! List ||
        operatorFeedHealthRaw is! List) {
      return null;
    }
    final passengerManifests = passengerManifestsRaw is List
        ? passengerManifestsRaw
            .map(CoachPassengerManifest.fromJson)
            .whereType<CoachPassengerManifest>()
            .toList(growable: false)
        : const <CoachPassengerManifest>[];
    final tickets = ticketsRaw is List
        ? ticketsRaw
            .map(CoachTicketCoupon.fromJson)
            .whereType<CoachTicketCoupon>()
            .toList(growable: false)
        : const <CoachTicketCoupon>[];
    return CoachJourneyLiveResponse(
      journey: journey,
      offer: offer,
      hold: hold,
      booking: booking,
      passengerManifests: passengerManifests,
      tickets: tickets,
      trip: trip,
      recentEvents: recentEventsRaw
          .map(CoachBoardingEvent.fromJson)
          .whereType<CoachBoardingEvent>()
          .toList(growable: false),
      operatorFeedHealth: operatorFeedHealthRaw
          .map(CoachOperatorFeedHealth.fromJson)
          .whereType<CoachOperatorFeedHealth>()
          .toList(growable: false),
    );
  }
}

class CoachRefundEligibilityResponse {
  final CoachBooking booking;
  final List<CoachPassengerManifest> passengerManifests;
  final List<CoachTicketCoupon> tickets;
  final CoachRefundEligibility eligibility;

  const CoachRefundEligibilityResponse({
    required this.booking,
    required this.passengerManifests,
    required this.tickets,
    required this.eligibility,
  });

  static CoachRefundEligibilityResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final booking = CoachBooking.fromJson(raw['booking']);
    final passengerManifestsRaw = raw['passengers_manifest'];
    final ticketsRaw = raw['tickets'];
    final eligibility = CoachRefundEligibility.fromJson(raw['eligibility']);
    if (booking == null || ticketsRaw is! List || eligibility == null) {
      return null;
    }
    final passengerManifests = passengerManifestsRaw is List
        ? passengerManifestsRaw
            .map(CoachPassengerManifest.fromJson)
            .whereType<CoachPassengerManifest>()
            .toList(growable: false)
        : const <CoachPassengerManifest>[];
    final tickets = ticketsRaw
        .map(CoachTicketCoupon.fromJson)
        .whereType<CoachTicketCoupon>()
        .toList(growable: false);
    return CoachRefundEligibilityResponse(
      booking: booking,
      passengerManifests: passengerManifests,
      tickets: tickets,
      eligibility: eligibility,
    );
  }
}

class CoachRefundRequestResult {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachBooking booking;
  final CoachRefundRequestRecord refundRequest;
  final CoachCompensationState compensation;
  final String nextAction;

  const CoachRefundRequestResult({
    required this.idempotency,
    required this.booking,
    required this.refundRequest,
    required this.compensation,
    required this.nextAction,
  });

  static CoachRefundRequestResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final booking = CoachBooking.fromJson(raw['booking']);
    final refundRequest =
        CoachRefundRequestRecord.fromJson(raw['refund_request']);
    final compensation = CoachCompensationState.fromJson(raw['compensation']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (idempotency == null ||
        booking == null ||
        refundRequest == null ||
        compensation == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachRefundRequestResult(
      idempotency: idempotency,
      booking: booking,
      refundRequest: refundRequest,
      compensation: compensation,
      nextAction: nextAction,
    );
  }
}

class CoachChangeOptionsResponse {
  final CoachBooking booking;
  final List<CoachPassengerManifest> passengerManifests;
  final List<CoachTicketCoupon> tickets;
  final CoachChangeEligibility eligibility;

  const CoachChangeOptionsResponse({
    required this.booking,
    required this.passengerManifests,
    required this.tickets,
    required this.eligibility,
  });

  static CoachChangeOptionsResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final booking = CoachBooking.fromJson(raw['booking']);
    final passengerManifestsRaw = raw['passengers_manifest'];
    final ticketsRaw = raw['tickets'];
    final eligibility = CoachChangeEligibility.fromJson(raw['eligibility']);
    if (booking == null || ticketsRaw is! List || eligibility == null) {
      return null;
    }
    final passengerManifests = passengerManifestsRaw is List
        ? passengerManifestsRaw
            .map(CoachPassengerManifest.fromJson)
            .whereType<CoachPassengerManifest>()
            .toList(growable: false)
        : const <CoachPassengerManifest>[];
    final tickets = ticketsRaw
        .map(CoachTicketCoupon.fromJson)
        .whereType<CoachTicketCoupon>()
        .toList(growable: false);
    return CoachChangeOptionsResponse(
      booking: booking,
      passengerManifests: passengerManifests,
      tickets: tickets,
      eligibility: eligibility,
    );
  }
}

class CoachRebookRequestResult {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachBooking booking;
  final CoachChangeRequestRecord changeRequest;
  final CoachCompensationState compensation;
  final String nextAction;

  const CoachRebookRequestResult({
    required this.idempotency,
    required this.booking,
    required this.changeRequest,
    required this.compensation,
    required this.nextAction,
  });

  static CoachRebookRequestResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final booking = CoachBooking.fromJson(raw['booking']);
    final changeRequest =
        CoachChangeRequestRecord.fromJson(raw['change_request']);
    final compensation = CoachCompensationState.fromJson(raw['compensation']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (idempotency == null ||
        booking == null ||
        changeRequest == null ||
        compensation == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachRebookRequestResult(
      idempotency: idempotency,
      booking: booking,
      changeRequest: changeRequest,
      compensation: compensation,
      nextAction: nextAction,
    );
  }
}

class CoachSelfServiceReissueResult {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachBooking booking;
  final CoachChangeRequestRecord changeRequest;
  final List<CoachPassengerManifest> passengerManifests;
  final List<CoachTicketCoupon> tickets;
  final List<String> deliveryChannels;
  final CoachPaymentAuthorization? payment;
  final CoachCompensationState compensation;
  final String nextAction;

  const CoachSelfServiceReissueResult({
    required this.idempotency,
    required this.booking,
    required this.changeRequest,
    required this.passengerManifests,
    required this.tickets,
    required this.deliveryChannels,
    required this.payment,
    required this.compensation,
    required this.nextAction,
  });

  static CoachSelfServiceReissueResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final booking = CoachBooking.fromJson(raw['booking']);
    final changeRequest =
        CoachChangeRequestRecord.fromJson(raw['change_request']);
    final passengerManifestsRaw = raw['passengers_manifest'];
    final ticketsRaw = raw['tickets'];
    final deliveryChannels = _coachStringList(raw['delivery_channels']);
    final payment = CoachPaymentAuthorization.fromJson(raw['payment']);
    final compensation = CoachCompensationState.fromJson(raw['compensation']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (idempotency == null ||
        booking == null ||
        changeRequest == null ||
        ticketsRaw is! List ||
        deliveryChannels.isEmpty ||
        compensation == null ||
        nextAction.isEmpty) {
      return null;
    }
    final tickets = ticketsRaw
        .map(CoachTicketCoupon.fromJson)
        .whereType<CoachTicketCoupon>()
        .toList(growable: false);
    final passengerManifests = passengerManifestsRaw is List
        ? passengerManifestsRaw
            .map(CoachPassengerManifest.fromJson)
            .whereType<CoachPassengerManifest>()
            .toList(growable: false)
        : const <CoachPassengerManifest>[];
    if (tickets.isEmpty) return null;
    return CoachSelfServiceReissueResult(
      idempotency: idempotency,
      booking: booking,
      changeRequest: changeRequest,
      passengerManifests: passengerManifests,
      tickets: tickets,
      deliveryChannels: deliveryChannels,
      payment: payment,
      compensation: compensation,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorSettlementEffect {
  final String kind;
  final String currency;
  final int amountMinorUnits;

  const CoachOperatorSettlementEffect({
    required this.kind,
    required this.currency,
    required this.amountMinorUnits,
  });

  static CoachOperatorSettlementEffect? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = (raw['kind'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final amountMinorUnits = raw['amount_minor_units'];
    if (kind.isEmpty ||
        !_isCoachCurrency(currency) ||
        amountMinorUnits is! int ||
        amountMinorUnits < 0) {
      return null;
    }
    return CoachOperatorSettlementEffect(
      kind: kind,
      currency: currency,
      amountMinorUnits: amountMinorUnits,
    );
  }
}

class CoachOperatorRefundQueueTotals {
  final int openRequests;
  final int pendingReview;
  final int approved;
  final int rejected;
  final int creditRequests;
  final int cashRequests;

  const CoachOperatorRefundQueueTotals({
    required this.openRequests,
    required this.pendingReview,
    required this.approved,
    required this.rejected,
    required this.creditRequests,
    required this.cashRequests,
  });

  static CoachOperatorRefundQueueTotals? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final openRequests = raw['open_requests'];
    final pendingReview = raw['pending_review'];
    final approved = raw['approved'];
    final rejected = raw['rejected'];
    final creditRequests = raw['credit_requests'];
    final cashRequests = raw['cash_requests'];
    if (openRequests is! int ||
        pendingReview is! int ||
        approved is! int ||
        rejected is! int ||
        creditRequests is! int ||
        cashRequests is! int) {
      return null;
    }
    return CoachOperatorRefundQueueTotals(
      openRequests: openRequests,
      pendingReview: pendingReview,
      approved: approved,
      rejected: rejected,
      creditRequests: creditRequests,
      cashRequests: cashRequests,
    );
  }
}

class CoachOperatorRefundQueueEntry {
  final String refundRequestId;
  final String bookingId;
  final String journeyId;
  final String operatorName;
  final String from;
  final String to;
  final String departureAtIso;
  final String arrivalAtIso;
  final CoachBookingLifecycleState bookingState;
  final String requestStatus;
  final CoachRefundKind selectedKind;
  final String currency;
  final int requestedMinorUnits;
  final int feeMinorUnits;
  final List<String> ticketIds;
  final String? reason;
  final String requestedAtIso;
  final CoachOpsQueueStatus queueStatus;
  final CoachOpsRequestUrgency urgency;
  final String suggestedAction;
  final String? reviewedAtIso;
  final String? reviewedByAccountId;
  final String? reviewNote;

  const CoachOperatorRefundQueueEntry({
    required this.refundRequestId,
    required this.bookingId,
    required this.journeyId,
    required this.operatorName,
    required this.from,
    required this.to,
    required this.departureAtIso,
    required this.arrivalAtIso,
    required this.bookingState,
    required this.requestStatus,
    required this.selectedKind,
    required this.currency,
    required this.requestedMinorUnits,
    required this.feeMinorUnits,
    required this.ticketIds,
    required this.reason,
    required this.requestedAtIso,
    required this.queueStatus,
    required this.urgency,
    required this.suggestedAction,
    required this.reviewedAtIso,
    required this.reviewedByAccountId,
    required this.reviewNote,
  });

  bool get isPendingReview => queueStatus == CoachOpsQueueStatus.pendingReview;

  static CoachOperatorRefundQueueEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final refundRequestId = (raw['refund_request_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final from = (raw['from'] ?? '').toString().trim();
    final to = (raw['to'] ?? '').toString().trim();
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final arrivalAtIso = (raw['arrival_at'] ?? '').toString().trim();
    final bookingState = coachBookingLifecycleFromWire(
      (raw['booking_state'] ?? '').toString().trim(),
    );
    final requestStatus = (raw['request_status'] ?? '').toString().trim();
    final selectedKind =
        coachRefundKindFromWire((raw['selected_kind'] ?? '').toString().trim());
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final requestedMinorUnits = raw['requested_minor_units'];
    final feeMinorUnits = raw['fee_minor_units'];
    final ticketIds = _coachStringList(raw['ticket_ids']);
    final reason = (raw['reason'] ?? '').toString().trim();
    final requestedAtIso = (raw['requested_at'] ?? '').toString().trim();
    final queueStatus = coachOpsQueueStatusFromWire(
      (raw['queue_status'] ?? '').toString().trim(),
    );
    final urgency = coachOpsRequestUrgencyFromWire(
      (raw['urgency'] ?? '').toString().trim(),
    );
    final suggestedAction = (raw['suggested_action'] ?? '').toString().trim();
    final reviewedAtIso = (raw['reviewed_at'] ?? '').toString().trim();
    final reviewedByAccountId =
        (raw['reviewed_by_account_id'] ?? '').toString().trim();
    final reviewNote = (raw['review_note'] ?? '').toString().trim();
    if (refundRequestId.isEmpty ||
        bookingId.isEmpty ||
        journeyId.isEmpty ||
        operatorName.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        departureAtIso.isEmpty ||
        arrivalAtIso.isEmpty ||
        bookingState == null ||
        requestStatus.isEmpty ||
        selectedKind == null ||
        !_isCoachCurrency(currency) ||
        requestedMinorUnits is! int ||
        requestedMinorUnits < 0 ||
        feeMinorUnits is! int ||
        feeMinorUnits < 0 ||
        ticketIds.isEmpty ||
        requestedAtIso.isEmpty ||
        queueStatus == null ||
        urgency == null ||
        suggestedAction.isEmpty) {
      return null;
    }
    return CoachOperatorRefundQueueEntry(
      refundRequestId: refundRequestId,
      bookingId: bookingId,
      journeyId: journeyId,
      operatorName: operatorName,
      from: from,
      to: to,
      departureAtIso: departureAtIso,
      arrivalAtIso: arrivalAtIso,
      bookingState: bookingState,
      requestStatus: requestStatus,
      selectedKind: selectedKind,
      currency: currency,
      requestedMinorUnits: requestedMinorUnits,
      feeMinorUnits: feeMinorUnits,
      ticketIds: ticketIds,
      reason: reason.isEmpty ? null : reason,
      requestedAtIso: requestedAtIso,
      queueStatus: queueStatus,
      urgency: urgency,
      suggestedAction: suggestedAction,
      reviewedAtIso: reviewedAtIso.isEmpty ? null : reviewedAtIso,
      reviewedByAccountId:
          reviewedByAccountId.isEmpty ? null : reviewedByAccountId,
      reviewNote: reviewNote.isEmpty ? null : reviewNote,
    );
  }
}

class CoachOperatorRefundQueueResponse {
  final String generatedAtIso;
  final CoachOperatorRefundQueueTotals totals;
  final List<CoachOperatorRefundQueueEntry> requests;

  const CoachOperatorRefundQueueResponse({
    required this.generatedAtIso,
    required this.totals,
    required this.requests,
  });

  static CoachOperatorRefundQueueResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final totals = CoachOperatorRefundQueueTotals.fromJson(raw['totals']);
    final requestsRaw = raw['requests'];
    if (generatedAtIso.isEmpty || totals == null || requestsRaw is! List) {
      return null;
    }
    return CoachOperatorRefundQueueResponse(
      generatedAtIso: generatedAtIso,
      totals: totals,
      requests: requestsRaw
          .map(CoachOperatorRefundQueueEntry.fromJson)
          .whereType<CoachOperatorRefundQueueEntry>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorChangeQueueTotals {
  final int openRequests;
  final int pendingReview;
  final int approved;
  final int rejected;
  final int collectionRequiredRequests;
  final int zeroDueRequests;

  const CoachOperatorChangeQueueTotals({
    required this.openRequests,
    required this.pendingReview,
    required this.approved,
    required this.rejected,
    required this.collectionRequiredRequests,
    required this.zeroDueRequests,
  });

  static CoachOperatorChangeQueueTotals? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final openRequests = raw['open_requests'];
    final pendingReview = raw['pending_review'];
    final approved = raw['approved'];
    final rejected = raw['rejected'];
    final collectionRequiredRequests = raw['collection_required_requests'];
    final zeroDueRequests = raw['zero_due_requests'];
    if (openRequests is! int ||
        pendingReview is! int ||
        approved is! int ||
        rejected is! int ||
        collectionRequiredRequests is! int ||
        zeroDueRequests is! int) {
      return null;
    }
    return CoachOperatorChangeQueueTotals(
      openRequests: openRequests,
      pendingReview: pendingReview,
      approved: approved,
      rejected: rejected,
      collectionRequiredRequests: collectionRequiredRequests,
      zeroDueRequests: zeroDueRequests,
    );
  }
}

class CoachOperatorChangeQueueEntry {
  final String changeRequestId;
  final String bookingId;
  final String journeyId;
  final String operatorName;
  final String from;
  final String to;
  final String departureAtIso;
  final String arrivalAtIso;
  final CoachBookingLifecycleState bookingState;
  final String requestStatus;
  final String targetOfferId;
  final String targetJourneyId;
  final String currency;
  final int fareDifferenceMinorUnits;
  final int changeFeeMinorUnits;
  final int totalDueMinorUnits;
  final String? reason;
  final String requestedAtIso;
  final CoachOpsQueueStatus queueStatus;
  final CoachOpsRequestUrgency urgency;
  final String suggestedAction;
  final String? reviewedAtIso;
  final String? reviewedByAccountId;
  final String? reviewNote;

  const CoachOperatorChangeQueueEntry({
    required this.changeRequestId,
    required this.bookingId,
    required this.journeyId,
    required this.operatorName,
    required this.from,
    required this.to,
    required this.departureAtIso,
    required this.arrivalAtIso,
    required this.bookingState,
    required this.requestStatus,
    required this.targetOfferId,
    required this.targetJourneyId,
    required this.currency,
    required this.fareDifferenceMinorUnits,
    required this.changeFeeMinorUnits,
    required this.totalDueMinorUnits,
    required this.reason,
    required this.requestedAtIso,
    required this.queueStatus,
    required this.urgency,
    required this.suggestedAction,
    required this.reviewedAtIso,
    required this.reviewedByAccountId,
    required this.reviewNote,
  });

  bool get isPendingReview => queueStatus == CoachOpsQueueStatus.pendingReview;

  static CoachOperatorChangeQueueEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final changeRequestId = (raw['change_request_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final from = (raw['from'] ?? '').toString().trim();
    final to = (raw['to'] ?? '').toString().trim();
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final arrivalAtIso = (raw['arrival_at'] ?? '').toString().trim();
    final bookingState = coachBookingLifecycleFromWire(
      (raw['booking_state'] ?? '').toString().trim(),
    );
    final requestStatus = (raw['request_status'] ?? '').toString().trim();
    final targetOfferId = (raw['target_offer_id'] ?? '').toString().trim();
    final targetJourneyId = (raw['target_journey_id'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final fareDifferenceMinorUnits = raw['fare_difference_minor_units'];
    final changeFeeMinorUnits = raw['change_fee_minor_units'];
    final totalDueMinorUnits = raw['total_due_minor_units'];
    final reason = (raw['reason'] ?? '').toString().trim();
    final requestedAtIso = (raw['requested_at'] ?? '').toString().trim();
    final queueStatus = coachOpsQueueStatusFromWire(
      (raw['queue_status'] ?? '').toString().trim(),
    );
    final urgency = coachOpsRequestUrgencyFromWire(
      (raw['urgency'] ?? '').toString().trim(),
    );
    final suggestedAction = (raw['suggested_action'] ?? '').toString().trim();
    final reviewedAtIso = (raw['reviewed_at'] ?? '').toString().trim();
    final reviewedByAccountId =
        (raw['reviewed_by_account_id'] ?? '').toString().trim();
    final reviewNote = (raw['review_note'] ?? '').toString().trim();
    if (changeRequestId.isEmpty ||
        bookingId.isEmpty ||
        journeyId.isEmpty ||
        operatorName.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        departureAtIso.isEmpty ||
        arrivalAtIso.isEmpty ||
        bookingState == null ||
        requestStatus.isEmpty ||
        targetOfferId.isEmpty ||
        targetJourneyId.isEmpty ||
        !_isCoachCurrency(currency) ||
        fareDifferenceMinorUnits is! int ||
        changeFeeMinorUnits is! int ||
        totalDueMinorUnits is! int ||
        requestedAtIso.isEmpty ||
        queueStatus == null ||
        urgency == null ||
        suggestedAction.isEmpty) {
      return null;
    }
    return CoachOperatorChangeQueueEntry(
      changeRequestId: changeRequestId,
      bookingId: bookingId,
      journeyId: journeyId,
      operatorName: operatorName,
      from: from,
      to: to,
      departureAtIso: departureAtIso,
      arrivalAtIso: arrivalAtIso,
      bookingState: bookingState,
      requestStatus: requestStatus,
      targetOfferId: targetOfferId,
      targetJourneyId: targetJourneyId,
      currency: currency,
      fareDifferenceMinorUnits: fareDifferenceMinorUnits,
      changeFeeMinorUnits: changeFeeMinorUnits,
      totalDueMinorUnits: totalDueMinorUnits,
      reason: reason.isEmpty ? null : reason,
      requestedAtIso: requestedAtIso,
      queueStatus: queueStatus,
      urgency: urgency,
      suggestedAction: suggestedAction,
      reviewedAtIso: reviewedAtIso.isEmpty ? null : reviewedAtIso,
      reviewedByAccountId:
          reviewedByAccountId.isEmpty ? null : reviewedByAccountId,
      reviewNote: reviewNote.isEmpty ? null : reviewNote,
    );
  }
}

class CoachOperatorChangeQueueResponse {
  final String generatedAtIso;
  final CoachOperatorChangeQueueTotals totals;
  final List<CoachOperatorChangeQueueEntry> requests;

  const CoachOperatorChangeQueueResponse({
    required this.generatedAtIso,
    required this.totals,
    required this.requests,
  });

  static CoachOperatorChangeQueueResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final totals = CoachOperatorChangeQueueTotals.fromJson(raw['totals']);
    final requestsRaw = raw['requests'];
    if (generatedAtIso.isEmpty || totals == null || requestsRaw is! List) {
      return null;
    }
    return CoachOperatorChangeQueueResponse(
      generatedAtIso: generatedAtIso,
      totals: totals,
      requests: requestsRaw
          .map(CoachOperatorChangeQueueEntry.fromJson)
          .whereType<CoachOperatorChangeQueueEntry>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorReconciliationSummary {
  final String currency;
  final int tripCount;
  final int manifestPassengers;
  final int boardedPassengers;
  final int pendingBoardingPassengers;
  final int needsAttentionPassengers;
  final int pendingReviewRequests;
  final int reviewedRequests;
  final int approvedCreditRefundMinorUnits;
  final int approvedCashRefundMinorUnits;
  final int approvedCollectionDueMinorUnits;

  const CoachOperatorReconciliationSummary({
    required this.currency,
    required this.tripCount,
    required this.manifestPassengers,
    required this.boardedPassengers,
    required this.pendingBoardingPassengers,
    required this.needsAttentionPassengers,
    required this.pendingReviewRequests,
    required this.reviewedRequests,
    required this.approvedCreditRefundMinorUnits,
    required this.approvedCashRefundMinorUnits,
    required this.approvedCollectionDueMinorUnits,
  });

  static CoachOperatorReconciliationSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final tripCount = raw['trip_count'];
    final manifestPassengers = raw['manifest_passengers'];
    final boardedPassengers = raw['boarded_passengers'];
    final pendingBoardingPassengers = raw['pending_boarding_passengers'];
    final needsAttentionPassengers = raw['needs_attention_passengers'];
    final pendingReviewRequests = raw['pending_review_requests'];
    final reviewedRequests = raw['reviewed_requests'];
    final approvedCreditRefundMinorUnits =
        raw['approved_credit_refund_minor_units'];
    final approvedCashRefundMinorUnits =
        raw['approved_cash_refund_minor_units'];
    final approvedCollectionDueMinorUnits =
        raw['approved_collection_due_minor_units'];
    if (!_isCoachCurrency(currency) ||
        tripCount is! int ||
        manifestPassengers is! int ||
        boardedPassengers is! int ||
        pendingBoardingPassengers is! int ||
        needsAttentionPassengers is! int ||
        pendingReviewRequests is! int ||
        reviewedRequests is! int ||
        approvedCreditRefundMinorUnits is! int ||
        approvedCashRefundMinorUnits is! int ||
        approvedCollectionDueMinorUnits is! int) {
      return null;
    }
    return CoachOperatorReconciliationSummary(
      currency: currency,
      tripCount: tripCount,
      manifestPassengers: manifestPassengers,
      boardedPassengers: boardedPassengers,
      pendingBoardingPassengers: pendingBoardingPassengers,
      needsAttentionPassengers: needsAttentionPassengers,
      pendingReviewRequests: pendingReviewRequests,
      reviewedRequests: reviewedRequests,
      approvedCreditRefundMinorUnits: approvedCreditRefundMinorUnits,
      approvedCashRefundMinorUnits: approvedCashRefundMinorUnits,
      approvedCollectionDueMinorUnits: approvedCollectionDueMinorUnits,
    );
  }
}

class CoachOperatorReconciliationTripSnapshot {
  final CoachCrewTripSummary trip;
  final List<CoachBoardingEvent> recentEvents;
  final List<String> pendingTicketIds;
  final int needsAttentionCount;

  const CoachOperatorReconciliationTripSnapshot({
    required this.trip,
    required this.recentEvents,
    required this.pendingTicketIds,
    required this.needsAttentionCount,
  });

  static CoachOperatorReconciliationTripSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final trip = CoachCrewTripSummary.fromJson(raw['trip']);
    final recentEventsRaw = raw['recent_events'];
    final pendingTicketIds = _coachStringList(raw['pending_ticket_ids']);
    final needsAttentionCount = raw['needs_attention_count'];
    if (trip == null ||
        recentEventsRaw is! List ||
        needsAttentionCount is! int) {
      return null;
    }
    return CoachOperatorReconciliationTripSnapshot(
      trip: trip,
      recentEvents: recentEventsRaw
          .map(CoachBoardingEvent.fromJson)
          .whereType<CoachBoardingEvent>()
          .toList(growable: false),
      pendingTicketIds: pendingTicketIds,
      needsAttentionCount: needsAttentionCount,
    );
  }
}

class CoachOperatorReconciliationHistoryEntry {
  final CoachOpsRequestKind requestKind;
  final String requestId;
  final String bookingId;
  final String journeyId;
  final String operatorName;
  final String from;
  final String to;
  final String departureAtIso;
  final CoachOpsQueueStatus queueStatus;
  final CoachOpsRequestUrgency urgency;
  final String subjectLabel;
  final String currency;
  final int amountMinorUnits;
  final String suggestedAction;
  final String? reviewedAtIso;
  final String? reviewedByAccountId;
  final String? reviewNote;
  final CoachOperatorSettlementEffect? settlementEffect;
  final String nextAction;

  const CoachOperatorReconciliationHistoryEntry({
    required this.requestKind,
    required this.requestId,
    required this.bookingId,
    required this.journeyId,
    required this.operatorName,
    required this.from,
    required this.to,
    required this.departureAtIso,
    required this.queueStatus,
    required this.urgency,
    required this.subjectLabel,
    required this.currency,
    required this.amountMinorUnits,
    required this.suggestedAction,
    required this.reviewedAtIso,
    required this.reviewedByAccountId,
    required this.reviewNote,
    required this.settlementEffect,
    required this.nextAction,
  });

  static CoachOperatorReconciliationHistoryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final requestKind = coachOpsRequestKindFromWire(
      (raw['request_kind'] ?? '').toString().trim(),
    );
    final requestId = (raw['request_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final from = (raw['from'] ?? '').toString().trim();
    final to = (raw['to'] ?? '').toString().trim();
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final queueStatus = coachOpsQueueStatusFromWire(
      (raw['queue_status'] ?? '').toString().trim(),
    );
    final urgency = coachOpsRequestUrgencyFromWire(
      (raw['urgency'] ?? '').toString().trim(),
    );
    final subjectLabel = (raw['subject_label'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final amountMinorUnits = raw['amount_minor_units'];
    final suggestedAction = (raw['suggested_action'] ?? '').toString().trim();
    final reviewedAtIso = (raw['reviewed_at'] ?? '').toString().trim();
    final reviewedByAccountId =
        (raw['reviewed_by_account_id'] ?? '').toString().trim();
    final reviewNote = (raw['review_note'] ?? '').toString().trim();
    final settlementEffect =
        CoachOperatorSettlementEffect.fromJson(raw['settlement_effect']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (requestKind == null ||
        requestId.isEmpty ||
        bookingId.isEmpty ||
        journeyId.isEmpty ||
        operatorName.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        departureAtIso.isEmpty ||
        queueStatus == null ||
        urgency == null ||
        subjectLabel.isEmpty ||
        !_isCoachCurrency(currency) ||
        amountMinorUnits is! int ||
        suggestedAction.isEmpty ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorReconciliationHistoryEntry(
      requestKind: requestKind,
      requestId: requestId,
      bookingId: bookingId,
      journeyId: journeyId,
      operatorName: operatorName,
      from: from,
      to: to,
      departureAtIso: departureAtIso,
      queueStatus: queueStatus,
      urgency: urgency,
      subjectLabel: subjectLabel,
      currency: currency,
      amountMinorUnits: amountMinorUnits,
      suggestedAction: suggestedAction,
      reviewedAtIso: reviewedAtIso.isEmpty ? null : reviewedAtIso,
      reviewedByAccountId:
          reviewedByAccountId.isEmpty ? null : reviewedByAccountId,
      reviewNote: reviewNote.isEmpty ? null : reviewNote,
      settlementEffect: settlementEffect,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorReconciliationResponse {
  final String generatedAtIso;
  final CoachOperatorReconciliationSummary summary;
  final List<CoachOperatorReconciliationTripSnapshot> tripSnapshots;
  final List<CoachOperatorReconciliationHistoryEntry> reviewHistory;

  const CoachOperatorReconciliationResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.tripSnapshots,
    required this.reviewHistory,
  });

  static CoachOperatorReconciliationResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachOperatorReconciliationSummary.fromJson(raw['summary']);
    final tripSnapshotsRaw = raw['trip_snapshots'];
    final reviewHistoryRaw = raw['review_history'];
    if (generatedAtIso.isEmpty ||
        summary == null ||
        tripSnapshotsRaw is! List ||
        reviewHistoryRaw is! List) {
      return null;
    }
    return CoachOperatorReconciliationResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      tripSnapshots: tripSnapshotsRaw
          .map(CoachOperatorReconciliationTripSnapshot.fromJson)
          .whereType<CoachOperatorReconciliationTripSnapshot>()
          .toList(growable: false),
      reviewHistory: reviewHistoryRaw
          .map(CoachOperatorReconciliationHistoryEntry.fromJson)
          .whereType<CoachOperatorReconciliationHistoryEntry>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorSettlementStatementTotals {
  final int lineCount;
  final int grossMinorUnits;
  final int commissionMinorUnits;
  final int refundMinorUnits;
  final int chargebackReserveMinorUnits;
  final int manualAdjustmentMinorUnits;
  final int netPayableMinorUnits;

  const CoachOperatorSettlementStatementTotals({
    required this.lineCount,
    required this.grossMinorUnits,
    required this.commissionMinorUnits,
    required this.refundMinorUnits,
    required this.chargebackReserveMinorUnits,
    required this.manualAdjustmentMinorUnits,
    required this.netPayableMinorUnits,
  });

  static CoachOperatorSettlementStatementTotals? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lineCount = raw['line_count'];
    final grossMinorUnits = raw['gross_minor_units'];
    final commissionMinorUnits = raw['commission_minor_units'];
    final refundMinorUnits = raw['refund_minor_units'];
    final chargebackReserveMinorUnits = raw['chargeback_reserve_minor_units'];
    final manualAdjustmentMinorUnits = raw['manual_adjustment_minor_units'];
    final netPayableMinorUnits = raw['net_payable_minor_units'];
    if (lineCount is! int ||
        grossMinorUnits is! int ||
        commissionMinorUnits is! int ||
        refundMinorUnits is! int ||
        chargebackReserveMinorUnits is! int ||
        manualAdjustmentMinorUnits is! int ||
        netPayableMinorUnits is! int) {
      return null;
    }
    return CoachOperatorSettlementStatementTotals(
      lineCount: lineCount,
      grossMinorUnits: grossMinorUnits,
      commissionMinorUnits: commissionMinorUnits,
      refundMinorUnits: refundMinorUnits,
      chargebackReserveMinorUnits: chargebackReserveMinorUnits,
      manualAdjustmentMinorUnits: manualAdjustmentMinorUnits,
      netPayableMinorUnits: netPayableMinorUnits,
    );
  }
}

class CoachOperatorSettlementStatement {
  final String statementId;
  final String operatorId;
  final String operatorName;
  final String currency;
  final String periodStartIso;
  final String periodEndIso;
  final String nextPayoutAtIso;
  final String status;
  final List<String> downloadFormats;
  final CoachOperatorSettlementStatementTotals totals;
  final List<CoachSettlementLine> lines;

  const CoachOperatorSettlementStatement({
    required this.statementId,
    required this.operatorId,
    required this.operatorName,
    required this.currency,
    required this.periodStartIso,
    required this.periodEndIso,
    required this.nextPayoutAtIso,
    required this.status,
    required this.downloadFormats,
    required this.totals,
    required this.lines,
  });

  static CoachOperatorSettlementStatement? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final statementId = (raw['statement_id'] ?? '').toString().trim();
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final periodStartIso = (raw['period_start'] ?? '').toString().trim();
    final periodEndIso = (raw['period_end'] ?? '').toString().trim();
    final nextPayoutAtIso = (raw['next_payout_at'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final downloadFormats = _coachStringList(raw['download_formats']);
    final totals =
        CoachOperatorSettlementStatementTotals.fromJson(raw['totals']);
    final linesRaw = raw['lines'];
    if (statementId.isEmpty ||
        operatorId.isEmpty ||
        operatorName.isEmpty ||
        !_isCoachCurrency(currency) ||
        periodStartIso.isEmpty ||
        periodEndIso.isEmpty ||
        nextPayoutAtIso.isEmpty ||
        status.isEmpty ||
        downloadFormats.isEmpty ||
        totals == null ||
        linesRaw is! List) {
      return null;
    }
    return CoachOperatorSettlementStatement(
      statementId: statementId,
      operatorId: operatorId,
      operatorName: operatorName,
      currency: currency,
      periodStartIso: periodStartIso,
      periodEndIso: periodEndIso,
      nextPayoutAtIso: nextPayoutAtIso,
      status: status,
      downloadFormats: downloadFormats,
      totals: totals,
      lines: linesRaw
          .map(CoachSettlementLine.fromJson)
          .whereType<CoachSettlementLine>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorSettlementStatementsResponse {
  final String generatedAtIso;
  final List<CoachOperatorSettlementStatement> statements;
  final String? nextCursor;

  const CoachOperatorSettlementStatementsResponse({
    required this.generatedAtIso,
    required this.statements,
    this.nextCursor,
  });

  static CoachOperatorSettlementStatementsResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final statementsRaw = raw['statements'];
    if (generatedAtIso.isEmpty || statementsRaw is! List) {
      return null;
    }
    return CoachOperatorSettlementStatementsResponse(
      generatedAtIso: generatedAtIso,
      statements: statementsRaw
          .map(CoachOperatorSettlementStatement.fromJson)
          .whereType<CoachOperatorSettlementStatement>()
          .toList(growable: false),
      nextCursor: (raw['next_cursor'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['next_cursor'] ?? '').toString().trim(),
    );
  }
}

class CoachOperatorPayoutExport {
  final String exportId;
  final String payoutRunId;
  final String exportFormat;
  final String status;
  final String fileName;
  final String mimeType;
  final String downloadPath;
  final String checksumSha256;
  final int contentLengthBytes;
  final String createdAtIso;
  final String createdByAccountId;
  final List<String> statementIds;
  final List<String> operatorIds;
  final String? note;

  const CoachOperatorPayoutExport({
    required this.exportId,
    required this.payoutRunId,
    required this.exportFormat,
    required this.status,
    required this.fileName,
    required this.mimeType,
    required this.downloadPath,
    required this.checksumSha256,
    required this.contentLengthBytes,
    required this.createdAtIso,
    required this.createdByAccountId,
    required this.statementIds,
    required this.operatorIds,
    required this.note,
  });

  bool get isReady => status == 'ready';

  static CoachOperatorPayoutExport? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final exportId = (raw['export_id'] ?? '').toString().trim();
    final payoutRunId = (raw['payout_run_id'] ?? '').toString().trim();
    final exportFormat = (raw['export_format'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final fileName = (raw['file_name'] ?? '').toString().trim();
    final mimeType = (raw['mime_type'] ?? '').toString().trim();
    final downloadPath = (raw['download_path'] ?? '').toString().trim();
    final checksumSha256 = (raw['checksum_sha256'] ?? '').toString().trim();
    final contentLengthBytes = raw['content_length_bytes'];
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final createdByAccountId =
        (raw['created_by_account_id'] ?? '').toString().trim();
    final statementIds = _coachStringList(raw['statement_ids']);
    final operatorIds = _coachStringList(raw['operator_ids']);
    final note = (raw['note'] ?? '').toString().trim();
    if (exportId.isEmpty ||
        payoutRunId.isEmpty ||
        exportFormat.isEmpty ||
        status.isEmpty ||
        fileName.isEmpty ||
        mimeType.isEmpty ||
        downloadPath.isEmpty ||
        checksumSha256.isEmpty ||
        contentLengthBytes is! int ||
        createdAtIso.isEmpty ||
        createdByAccountId.isEmpty ||
        statementIds.isEmpty ||
        operatorIds.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutExport(
      exportId: exportId,
      payoutRunId: payoutRunId,
      exportFormat: exportFormat,
      status: status,
      fileName: fileName,
      mimeType: mimeType,
      downloadPath: downloadPath,
      checksumSha256: checksumSha256,
      contentLengthBytes: contentLengthBytes,
      createdAtIso: createdAtIso,
      createdByAccountId: createdByAccountId,
      statementIds: statementIds,
      operatorIds: operatorIds,
      note: note.isEmpty ? null : note,
    );
  }
}

class CoachOperatorPayoutImportReportArtifact {
  final String artifactId;
  final String batchId;
  final String artifactKind;
  final String importSource;
  final String reportName;
  final String reportFormat;
  final List<String> operatorIds;
  final String fileName;
  final String mimeType;
  final String downloadPath;
  final String checksumSha256;
  final int contentLengthBytes;
  final String createdAtIso;
  final String createdByAccountId;
  final String? note;

  const CoachOperatorPayoutImportReportArtifact({
    required this.artifactId,
    required this.batchId,
    required this.artifactKind,
    required this.importSource,
    required this.reportName,
    required this.reportFormat,
    this.operatorIds = const <String>[],
    required this.fileName,
    required this.mimeType,
    required this.downloadPath,
    required this.checksumSha256,
    required this.contentLengthBytes,
    required this.createdAtIso,
    required this.createdByAccountId,
    required this.note,
  });

  static CoachOperatorPayoutImportReportArtifact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final artifactId = (raw['artifact_id'] ?? '').toString().trim();
    final batchId = (raw['batch_id'] ?? '').toString().trim();
    final artifactKind = (raw['artifact_kind'] ?? '').toString().trim();
    final importSource = (raw['import_source'] ?? '').toString().trim();
    final reportName = (raw['report_name'] ?? '').toString().trim();
    final reportFormat = (raw['report_format'] ?? '').toString().trim();
    final operatorIds = _coachStringList(raw['operator_ids']);
    final fileName = (raw['file_name'] ?? '').toString().trim();
    final mimeType = (raw['mime_type'] ?? '').toString().trim();
    final downloadPath = (raw['download_path'] ?? '').toString().trim();
    final checksumSha256 = (raw['checksum_sha256'] ?? '').toString().trim();
    final contentLengthBytes = raw['content_length_bytes'];
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final createdByAccountId =
        (raw['created_by_account_id'] ?? '').toString().trim();
    final note = (raw['note'] ?? '').toString().trim();
    if (artifactId.isEmpty ||
        batchId.isEmpty ||
        artifactKind.isEmpty ||
        importSource.isEmpty ||
        reportName.isEmpty ||
        reportFormat.isEmpty ||
        fileName.isEmpty ||
        mimeType.isEmpty ||
        downloadPath.isEmpty ||
        checksumSha256.isEmpty ||
        contentLengthBytes is! int ||
        createdAtIso.isEmpty ||
        createdByAccountId.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportReportArtifact(
      artifactId: artifactId,
      batchId: batchId,
      artifactKind: artifactKind,
      importSource: importSource,
      reportName: reportName,
      reportFormat: reportFormat,
      operatorIds: operatorIds,
      fileName: fileName,
      mimeType: mimeType,
      downloadPath: downloadPath,
      checksumSha256: checksumSha256,
      contentLengthBytes: contentLengthBytes,
      createdAtIso: createdAtIso,
      createdByAccountId: createdByAccountId,
      note: note.isEmpty ? null : note,
    );
  }
}

class CoachOperatorPayoutRunSummary {
  final String currency;
  final int queuedRuns;
  final int paidRuns;
  final int failedRuns;
  final int queuedStatementCount;
  final int queuedNetPayableMinorUnits;
  final int paidNetPayableMinorUnits;

  const CoachOperatorPayoutRunSummary({
    required this.currency,
    required this.queuedRuns,
    required this.paidRuns,
    required this.failedRuns,
    required this.queuedStatementCount,
    required this.queuedNetPayableMinorUnits,
    required this.paidNetPayableMinorUnits,
  });

  static CoachOperatorPayoutRunSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final queuedRuns = raw['queued_runs'];
    final paidRuns = raw['paid_runs'];
    final failedRuns = raw['failed_runs'];
    final queuedStatementCount = raw['queued_statement_count'];
    final queuedNetPayableMinorUnits = raw['queued_net_payable_minor_units'];
    final paidNetPayableMinorUnits = raw['paid_net_payable_minor_units'];
    if (!_isCoachCurrency(currency) ||
        queuedRuns is! int ||
        paidRuns is! int ||
        failedRuns is! int ||
        queuedStatementCount is! int ||
        queuedNetPayableMinorUnits is! int ||
        paidNetPayableMinorUnits is! int) {
      return null;
    }
    return CoachOperatorPayoutRunSummary(
      currency: currency,
      queuedRuns: queuedRuns,
      paidRuns: paidRuns,
      failedRuns: failedRuns,
      queuedStatementCount: queuedStatementCount,
      queuedNetPayableMinorUnits: queuedNetPayableMinorUnits,
      paidNetPayableMinorUnits: paidNetPayableMinorUnits,
    );
  }
}

class CoachOperatorPayoutRun {
  final String payoutRunId;
  final String status;
  final String currency;
  final List<String> statementIds;
  final List<String> operatorIds;
  final List<String> operatorNames;
  final int statementCount;
  final int grossMinorUnits;
  final int reserveMinorUnits;
  final int netPayableMinorUnits;
  final String createdAtIso;
  final String? paidAtIso;
  final String createdByAccountId;
  final String? paidByAccountId;
  final String? paymentReference;
  final String? note;
  final List<String> availableExportFormats;
  final List<CoachOperatorPayoutExport> exports;

  const CoachOperatorPayoutRun({
    required this.payoutRunId,
    required this.status,
    required this.currency,
    required this.statementIds,
    required this.operatorIds,
    required this.operatorNames,
    required this.statementCount,
    required this.grossMinorUnits,
    required this.reserveMinorUnits,
    required this.netPayableMinorUnits,
    required this.createdAtIso,
    required this.paidAtIso,
    required this.createdByAccountId,
    required this.paidByAccountId,
    required this.paymentReference,
    required this.note,
    required this.availableExportFormats,
    required this.exports,
  });

  bool get isQueued => status == 'queued';
  bool get isPaid => status == 'paid';

  static CoachOperatorPayoutRun? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final payoutRunId = (raw['payout_run_id'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final statementIds = _coachStringList(raw['statement_ids']);
    final operatorIds = _coachStringList(raw['operator_ids']);
    final operatorNames = _coachStringList(raw['operator_names']);
    final statementCount = raw['statement_count'];
    final grossMinorUnits = raw['gross_minor_units'];
    final reserveMinorUnits = raw['reserve_minor_units'];
    final netPayableMinorUnits = raw['net_payable_minor_units'];
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final paidAtIso = (raw['paid_at'] ?? '').toString().trim();
    final createdByAccountId =
        (raw['created_by_account_id'] ?? '').toString().trim();
    final paidByAccountId = (raw['paid_by_account_id'] ?? '').toString().trim();
    final paymentReference = (raw['payment_reference'] ?? '').toString().trim();
    final note = (raw['note'] ?? '').toString().trim();
    final availableExportFormats =
        _coachStringList(raw['available_export_formats']);
    final exportsRaw = raw['exports'];
    if (payoutRunId.isEmpty ||
        status.isEmpty ||
        !_isCoachCurrency(currency) ||
        statementIds.isEmpty ||
        operatorIds.isEmpty ||
        operatorNames.isEmpty ||
        statementCount is! int ||
        grossMinorUnits is! int ||
        reserveMinorUnits is! int ||
        netPayableMinorUnits is! int ||
        createdAtIso.isEmpty ||
        createdByAccountId.isEmpty ||
        exportsRaw is! List) {
      return null;
    }
    return CoachOperatorPayoutRun(
      payoutRunId: payoutRunId,
      status: status,
      currency: currency,
      statementIds: statementIds,
      operatorIds: operatorIds,
      operatorNames: operatorNames,
      statementCount: statementCount,
      grossMinorUnits: grossMinorUnits,
      reserveMinorUnits: reserveMinorUnits,
      netPayableMinorUnits: netPayableMinorUnits,
      createdAtIso: createdAtIso,
      paidAtIso: paidAtIso.isEmpty ? null : paidAtIso,
      createdByAccountId: createdByAccountId,
      paidByAccountId: paidByAccountId.isEmpty ? null : paidByAccountId,
      paymentReference: paymentReference.isEmpty ? null : paymentReference,
      note: note.isEmpty ? null : note,
      availableExportFormats: availableExportFormats,
      exports: exportsRaw
          .map(CoachOperatorPayoutExport.fromJson)
          .whereType<CoachOperatorPayoutExport>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorPayoutRunsResponse {
  final String generatedAtIso;
  final CoachOperatorPayoutRunSummary summary;
  final List<CoachOperatorPayoutRun> runs;
  final String? nextCursor;

  const CoachOperatorPayoutRunsResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.runs,
    this.nextCursor,
  });

  static CoachOperatorPayoutRunsResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachOperatorPayoutRunSummary.fromJson(raw['summary']);
    final runsRaw = raw['runs'];
    if (generatedAtIso.isEmpty || summary == null || runsRaw is! List) {
      return null;
    }
    return CoachOperatorPayoutRunsResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      runs: runsRaw
          .map(CoachOperatorPayoutRun.fromJson)
          .whereType<CoachOperatorPayoutRun>()
          .toList(growable: false),
      nextCursor: (raw['next_cursor'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['next_cursor'] ?? '').toString().trim(),
    );
  }
}

class CoachOperatorPayoutReconciliationSummary {
  final String currency;
  final int runCount;
  final int balancedRuns;
  final int attentionRuns;
  final int queuedRuns;
  final int failedRuns;
  final int missingPaymentReferenceRuns;
  final int missingExportsRuns;
  final int partialExportRuns;
  final int paidNetPayableMinorUnits;
  final int attentionNetPayableMinorUnits;

  const CoachOperatorPayoutReconciliationSummary({
    required this.currency,
    required this.runCount,
    required this.balancedRuns,
    required this.attentionRuns,
    required this.queuedRuns,
    required this.failedRuns,
    required this.missingPaymentReferenceRuns,
    required this.missingExportsRuns,
    required this.partialExportRuns,
    required this.paidNetPayableMinorUnits,
    required this.attentionNetPayableMinorUnits,
  });

  static CoachOperatorPayoutReconciliationSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final runCount = raw['run_count'];
    final balancedRuns = raw['balanced_runs'];
    final attentionRuns = raw['attention_runs'];
    final queuedRuns = raw['queued_runs'];
    final failedRuns = raw['failed_runs'];
    final missingPaymentReferenceRuns = raw['missing_payment_reference_runs'];
    final missingExportsRuns = raw['missing_exports_runs'];
    final partialExportRuns = raw['partial_export_runs'];
    final paidNetPayableMinorUnits = raw['paid_net_payable_minor_units'];
    final attentionNetPayableMinorUnits =
        raw['attention_net_payable_minor_units'];
    if (!_isCoachCurrency(currency) ||
        runCount is! int ||
        balancedRuns is! int ||
        attentionRuns is! int ||
        queuedRuns is! int ||
        failedRuns is! int ||
        missingPaymentReferenceRuns is! int ||
        missingExportsRuns is! int ||
        partialExportRuns is! int ||
        paidNetPayableMinorUnits is! int ||
        attentionNetPayableMinorUnits is! int) {
      return null;
    }
    return CoachOperatorPayoutReconciliationSummary(
      currency: currency,
      runCount: runCount,
      balancedRuns: balancedRuns,
      attentionRuns: attentionRuns,
      queuedRuns: queuedRuns,
      failedRuns: failedRuns,
      missingPaymentReferenceRuns: missingPaymentReferenceRuns,
      missingExportsRuns: missingExportsRuns,
      partialExportRuns: partialExportRuns,
      paidNetPayableMinorUnits: paidNetPayableMinorUnits,
      attentionNetPayableMinorUnits: attentionNetPayableMinorUnits,
    );
  }
}

class CoachOperatorPayoutReconciliationRun {
  final String payoutRunId;
  final String runStatus;
  final String reconciliationStatus;
  final String currency;
  final List<String> operatorNames;
  final List<String> statementIds;
  final String? paymentReference;
  final int netPayableMinorUnits;
  final List<String> availableExportFormats;
  final List<String> readyExportFormats;
  final List<String> missingExportFormats;
  final String createdAtIso;
  final String? paidAtIso;
  final bool needsAttention;
  final List<String> attentionReasons;
  final String nextAction;

  const CoachOperatorPayoutReconciliationRun({
    required this.payoutRunId,
    required this.runStatus,
    required this.reconciliationStatus,
    required this.currency,
    required this.operatorNames,
    required this.statementIds,
    required this.paymentReference,
    required this.netPayableMinorUnits,
    required this.availableExportFormats,
    required this.readyExportFormats,
    required this.missingExportFormats,
    required this.createdAtIso,
    required this.paidAtIso,
    required this.needsAttention,
    required this.attentionReasons,
    required this.nextAction,
  });

  static CoachOperatorPayoutReconciliationRun? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final payoutRunId = (raw['payout_run_id'] ?? '').toString().trim();
    final runStatus = (raw['run_status'] ?? '').toString().trim();
    final reconciliationStatus =
        (raw['reconciliation_status'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final operatorNames = _coachStringList(raw['operator_names']);
    final statementIds = _coachStringList(raw['statement_ids']);
    final paymentReference = (raw['payment_reference'] ?? '').toString().trim();
    final netPayableMinorUnits = raw['net_payable_minor_units'];
    final availableExportFormats =
        _coachStringList(raw['available_export_formats']);
    final readyExportFormats = _coachStringList(raw['ready_export_formats']);
    final missingExportFormats =
        _coachStringList(raw['missing_export_formats']);
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final paidAtIso = (raw['paid_at'] ?? '').toString().trim();
    final needsAttention = raw['needs_attention'];
    final attentionReasons = _coachStringList(raw['attention_reasons']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (payoutRunId.isEmpty ||
        runStatus.isEmpty ||
        reconciliationStatus.isEmpty ||
        !_isCoachCurrency(currency) ||
        operatorNames.isEmpty ||
        statementIds.isEmpty ||
        netPayableMinorUnits is! int ||
        createdAtIso.isEmpty ||
        needsAttention is! bool ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutReconciliationRun(
      payoutRunId: payoutRunId,
      runStatus: runStatus,
      reconciliationStatus: reconciliationStatus,
      currency: currency,
      operatorNames: operatorNames,
      statementIds: statementIds,
      paymentReference: paymentReference.isEmpty ? null : paymentReference,
      netPayableMinorUnits: netPayableMinorUnits,
      availableExportFormats: availableExportFormats,
      readyExportFormats: readyExportFormats,
      missingExportFormats: missingExportFormats,
      createdAtIso: createdAtIso,
      paidAtIso: paidAtIso.isEmpty ? null : paidAtIso,
      needsAttention: needsAttention,
      attentionReasons: attentionReasons,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorPayoutReconciliationResponse {
  final String generatedAtIso;
  final CoachOperatorPayoutReconciliationSummary summary;
  final List<CoachOperatorPayoutReconciliationRun> runs;
  final String? nextCursor;

  const CoachOperatorPayoutReconciliationResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.runs,
    this.nextCursor,
  });

  static CoachOperatorPayoutReconciliationResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary =
        CoachOperatorPayoutReconciliationSummary.fromJson(raw['summary']);
    final runsRaw = raw['runs'];
    if (generatedAtIso.isEmpty || summary == null || runsRaw is! List) {
      return null;
    }
    return CoachOperatorPayoutReconciliationResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      runs: runsRaw
          .map(CoachOperatorPayoutReconciliationRun.fromJson)
          .whereType<CoachOperatorPayoutReconciliationRun>()
          .toList(growable: false),
      nextCursor: (raw['next_cursor'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['next_cursor'] ?? '').toString().trim(),
    );
  }
}

class CoachOperatorPayoutImportsSummary {
  final int totalImports;
  final int executedImports;
  final int failedImports;
  final int pendingImports;

  const CoachOperatorPayoutImportsSummary({
    required this.totalImports,
    required this.executedImports,
    required this.failedImports,
    required this.pendingImports,
  });

  static CoachOperatorPayoutImportsSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final totalImports = raw['total_imports'];
    final executedImports = raw['executed_imports'];
    final failedImports = raw['failed_imports'];
    final pendingImports = raw['pending_imports'];
    if (totalImports is! int ||
        executedImports is! int ||
        failedImports is! int ||
        pendingImports is! int) {
      return null;
    }
    return CoachOperatorPayoutImportsSummary(
      totalImports: totalImports,
      executedImports: executedImports,
      failedImports: failedImports,
      pendingImports: pendingImports,
    );
  }
}

class CoachOperatorPayoutImport {
  final String importId;
  final String? importBatchId;
  final String payoutRunId;
  final String importSource;
  final String externalStatus;
  final String? paymentReference;
  final String? externalReference;
  final String importedAtIso;
  final String importedByAccountId;
  final String previousRunStatus;
  final String appliedRunStatus;
  final String? note;

  const CoachOperatorPayoutImport({
    required this.importId,
    required this.importBatchId,
    required this.payoutRunId,
    required this.importSource,
    required this.externalStatus,
    required this.paymentReference,
    required this.externalReference,
    required this.importedAtIso,
    required this.importedByAccountId,
    required this.previousRunStatus,
    required this.appliedRunStatus,
    required this.note,
  });

  static CoachOperatorPayoutImport? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final importId = (raw['import_id'] ?? '').toString().trim();
    final importBatchId = (raw['import_batch_id'] ?? '').toString().trim();
    final payoutRunId = (raw['payout_run_id'] ?? '').toString().trim();
    final importSource = (raw['import_source'] ?? '').toString().trim();
    final externalStatus = (raw['external_status'] ?? '').toString().trim();
    final paymentReference = (raw['payment_reference'] ?? '').toString().trim();
    final externalReference =
        (raw['external_reference'] ?? '').toString().trim();
    final importedAtIso = (raw['imported_at'] ?? '').toString().trim();
    final importedByAccountId =
        (raw['imported_by_account_id'] ?? '').toString().trim();
    final previousRunStatus =
        (raw['previous_run_status'] ?? '').toString().trim();
    final appliedRunStatus =
        (raw['applied_run_status'] ?? '').toString().trim();
    final note = (raw['note'] ?? '').toString().trim();
    if (importId.isEmpty ||
        payoutRunId.isEmpty ||
        importSource.isEmpty ||
        externalStatus.isEmpty ||
        importedAtIso.isEmpty ||
        importedByAccountId.isEmpty ||
        previousRunStatus.isEmpty ||
        appliedRunStatus.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImport(
      importId: importId,
      importBatchId: importBatchId.isEmpty ? null : importBatchId,
      payoutRunId: payoutRunId,
      importSource: importSource,
      externalStatus: externalStatus,
      paymentReference: paymentReference.isEmpty ? null : paymentReference,
      externalReference: externalReference.isEmpty ? null : externalReference,
      importedAtIso: importedAtIso,
      importedByAccountId: importedByAccountId,
      previousRunStatus: previousRunStatus,
      appliedRunStatus: appliedRunStatus,
      note: note.isEmpty ? null : note,
    );
  }
}

class CoachOperatorPayoutImportBatchesSummary {
  final int totalBatches;
  final int totalRows;
  final int appliedRows;
  final int failedRows;

  const CoachOperatorPayoutImportBatchesSummary({
    required this.totalBatches,
    required this.totalRows,
    required this.appliedRows,
    required this.failedRows,
  });

  static CoachOperatorPayoutImportBatchesSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final totalBatches = raw['total_batches'];
    final totalRows = raw['total_rows'];
    final appliedRows = raw['applied_rows'];
    final failedRows = raw['failed_rows'];
    if (totalBatches is! int ||
        totalRows is! int ||
        appliedRows is! int ||
        failedRows is! int) {
      return null;
    }
    return CoachOperatorPayoutImportBatchesSummary(
      totalBatches: totalBatches,
      totalRows: totalRows,
      appliedRows: appliedRows,
      failedRows: failedRows,
    );
  }
}

class CoachOperatorPayoutImportBatch {
  final String batchId;
  final bool dryRun;
  final String importSource;
  final String reportName;
  final String reportFormat;
  final List<String> operatorIds;
  final String? reworkOfBatchId;
  final String? reworkOriginBatchId;
  final List<String> followUpBatchIds;
  final String reportChecksumSha256;
  final int totalRows;
  final int appliedRows;
  final int failedRows;
  final List<String> payoutRunIds;
  final List<String> failureMessages;
  final String createdAtIso;
  final String createdByAccountId;
  final CoachOperatorPayoutImportReportArtifact? reportArtifact;
  final CoachOperatorPayoutImportReportArtifact? reworkArtifact;
  final String? note;

  const CoachOperatorPayoutImportBatch({
    required this.batchId,
    required this.dryRun,
    required this.importSource,
    required this.reportName,
    required this.reportFormat,
    this.operatorIds = const <String>[],
    required this.reworkOfBatchId,
    required this.reworkOriginBatchId,
    required this.followUpBatchIds,
    required this.reportChecksumSha256,
    required this.totalRows,
    required this.appliedRows,
    required this.failedRows,
    required this.payoutRunIds,
    required this.failureMessages,
    required this.createdAtIso,
    required this.createdByAccountId,
    required this.reportArtifact,
    required this.reworkArtifact,
    required this.note,
  });

  static CoachOperatorPayoutImportBatch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final batchId = (raw['batch_id'] ?? '').toString().trim();
    final dryRun = raw['dry_run'];
    final importSource = (raw['import_source'] ?? '').toString().trim();
    final reportName = (raw['report_name'] ?? '').toString().trim();
    final reportFormat = (raw['report_format'] ?? '').toString().trim();
    final operatorIds = _coachStringList(raw['operator_ids']);
    final reworkOfBatchId = (raw['rework_of_batch_id'] ?? '').toString().trim();
    final reworkOriginBatchId =
        (raw['rework_origin_batch_id'] ?? '').toString().trim();
    final followUpBatchIdsRaw = raw['follow_up_batch_ids'];
    final reportChecksumSha256 =
        (raw['report_checksum_sha256'] ?? '').toString().trim();
    final totalRows = raw['total_rows'];
    final appliedRows = raw['applied_rows'];
    final failedRows = raw['failed_rows'];
    final payoutRunIdsRaw = raw['payout_run_ids'];
    final failureMessagesRaw = raw['failure_messages'];
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final createdByAccountId =
        (raw['created_by_account_id'] ?? '').toString().trim();
    final reportArtifact = CoachOperatorPayoutImportReportArtifact.fromJson(
      raw['report_artifact'],
    );
    final reworkArtifact = CoachOperatorPayoutImportReportArtifact.fromJson(
      raw['rework_artifact'],
    );
    final note = (raw['note'] ?? '').toString().trim();
    if (batchId.isEmpty ||
        (dryRun != null && dryRun is! bool) ||
        importSource.isEmpty ||
        reportName.isEmpty ||
        reportFormat.isEmpty ||
        (followUpBatchIdsRaw != null && followUpBatchIdsRaw is! List) ||
        reportChecksumSha256.isEmpty ||
        totalRows is! int ||
        appliedRows is! int ||
        failedRows is! int ||
        payoutRunIdsRaw is! List ||
        failureMessagesRaw is! List ||
        createdAtIso.isEmpty ||
        createdByAccountId.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportBatch(
      batchId: batchId,
      dryRun: dryRun is bool ? dryRun : false,
      importSource: importSource,
      reportName: reportName,
      reportFormat: reportFormat,
      operatorIds: operatorIds,
      reworkOfBatchId: reworkOfBatchId.isEmpty ? null : reworkOfBatchId,
      reworkOriginBatchId:
          reworkOriginBatchId.isEmpty ? null : reworkOriginBatchId,
      followUpBatchIds: (followUpBatchIdsRaw is List
              ? followUpBatchIdsRaw
              : const <Object?>[])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      reportChecksumSha256: reportChecksumSha256,
      totalRows: totalRows,
      appliedRows: appliedRows,
      failedRows: failedRows,
      payoutRunIds: payoutRunIdsRaw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      failureMessages: failureMessagesRaw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      createdAtIso: createdAtIso,
      createdByAccountId: createdByAccountId,
      reportArtifact: reportArtifact,
      reworkArtifact: reworkArtifact,
      note: note.isEmpty ? null : note,
    );
  }
}

class CoachOperatorPayoutImportBatchesResponse {
  final String generatedAtIso;
  final CoachOperatorPayoutImportBatchesSummary summary;
  final List<CoachOperatorPayoutImportBatch> batches;
  final String? nextCursor;

  const CoachOperatorPayoutImportBatchesResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.batches,
    this.nextCursor,
  });

  static CoachOperatorPayoutImportBatchesResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary =
        CoachOperatorPayoutImportBatchesSummary.fromJson(raw['summary']);
    final batchesRaw = raw['batches'];
    if (generatedAtIso.isEmpty || summary == null || batchesRaw is! List) {
      return null;
    }
    return CoachOperatorPayoutImportBatchesResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      batches: batchesRaw
          .map(CoachOperatorPayoutImportBatch.fromJson)
          .whereType<CoachOperatorPayoutImportBatch>()
          .toList(growable: false),
      nextCursor: (raw['next_cursor'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['next_cursor'] ?? '').toString().trim(),
    );
  }
}

class CoachOperatorPayoutImportPreviewsSummary {
  final int totalPreviews;
  final int activePreviews;
  final int consumedPreviews;
  final int expiredPreviews;
  final int invalidatedPreviews;

  const CoachOperatorPayoutImportPreviewsSummary({
    required this.totalPreviews,
    required this.activePreviews,
    required this.consumedPreviews,
    required this.expiredPreviews,
    required this.invalidatedPreviews,
  });

  static CoachOperatorPayoutImportPreviewsSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final totalPreviews = raw['total_previews'];
    final activePreviews = raw['active_previews'];
    final consumedPreviews = raw['consumed_previews'];
    final expiredPreviews = raw['expired_previews'];
    final invalidatedPreviews = raw['invalidated_previews'];
    if (totalPreviews is! int ||
        activePreviews is! int ||
        consumedPreviews is! int ||
        expiredPreviews is! int ||
        invalidatedPreviews is! int) {
      return null;
    }
    return CoachOperatorPayoutImportPreviewsSummary(
      totalPreviews: totalPreviews,
      activePreviews: activePreviews,
      consumedPreviews: consumedPreviews,
      expiredPreviews: expiredPreviews,
      invalidatedPreviews: invalidatedPreviews,
    );
  }
}

class CoachOperatorPayoutImportPreview {
  final String previewToken;
  final String accountId;
  final String importSource;
  final String reportName;
  final String reportFormat;
  final List<String> operatorIds;
  final String reportChecksumSha256;
  final String requestFingerprint;
  final String previewStatus;
  final String createdAtIso;
  final String expiresAtIso;
  final bool usableNow;
  final String? reworkOfBatchId;
  final String? consumedAtIso;
  final String? invalidatedAtIso;

  const CoachOperatorPayoutImportPreview({
    required this.previewToken,
    required this.accountId,
    required this.importSource,
    required this.reportName,
    required this.reportFormat,
    this.operatorIds = const <String>[],
    required this.reportChecksumSha256,
    required this.requestFingerprint,
    required this.previewStatus,
    required this.createdAtIso,
    required this.expiresAtIso,
    required this.usableNow,
    required this.reworkOfBatchId,
    required this.consumedAtIso,
    required this.invalidatedAtIso,
  });

  static CoachOperatorPayoutImportPreview? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final previewToken = (raw['preview_token'] ?? '').toString().trim();
    final accountId = (raw['account_id'] ?? '').toString().trim();
    final importSource = (raw['import_source'] ?? '').toString().trim();
    final reportName = (raw['report_name'] ?? '').toString().trim();
    final reportFormat = (raw['report_format'] ?? '').toString().trim();
    final operatorIds = _coachStringList(raw['operator_ids']);
    final reportChecksumSha256 =
        (raw['report_checksum_sha256'] ?? '').toString().trim();
    final requestFingerprint =
        (raw['request_fingerprint'] ?? '').toString().trim();
    final previewStatus = (raw['preview_status'] ?? '').toString().trim();
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    final usableNow = raw['usable_now'];
    final reworkOfBatchId = (raw['rework_of_batch_id'] ?? '').toString().trim();
    final consumedAtIso = (raw['consumed_at'] ?? '').toString().trim();
    final invalidatedAtIso = (raw['invalidated_at'] ?? '').toString().trim();
    if (previewToken.isEmpty ||
        accountId.isEmpty ||
        importSource.isEmpty ||
        reportName.isEmpty ||
        reportFormat.isEmpty ||
        reportChecksumSha256.isEmpty ||
        requestFingerprint.isEmpty ||
        previewStatus.isEmpty ||
        createdAtIso.isEmpty ||
        expiresAtIso.isEmpty ||
        usableNow is! bool) {
      return null;
    }
    return CoachOperatorPayoutImportPreview(
      previewToken: previewToken,
      accountId: accountId,
      importSource: importSource,
      reportName: reportName,
      reportFormat: reportFormat,
      operatorIds: operatorIds,
      reportChecksumSha256: reportChecksumSha256,
      requestFingerprint: requestFingerprint,
      previewStatus: previewStatus,
      createdAtIso: createdAtIso,
      expiresAtIso: expiresAtIso,
      usableNow: usableNow,
      reworkOfBatchId: reworkOfBatchId.isEmpty ? null : reworkOfBatchId,
      consumedAtIso: consumedAtIso.isEmpty ? null : consumedAtIso,
      invalidatedAtIso: invalidatedAtIso.isEmpty ? null : invalidatedAtIso,
    );
  }
}

class CoachOperatorPayoutImportProfileField {
  final String key;
  final bool required;
  final List<String> acceptedHeaders;
  final String description;

  const CoachOperatorPayoutImportProfileField({
    required this.key,
    required this.required,
    required this.acceptedHeaders,
    required this.description,
  });

  static CoachOperatorPayoutImportProfileField? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = (raw['key'] ?? '').toString().trim();
    final required = raw['required'];
    final acceptedHeadersRaw = raw['accepted_headers'];
    final description = (raw['description'] ?? '').toString().trim();
    if (key.isEmpty ||
        required is! bool ||
        acceptedHeadersRaw is! List ||
        description.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportProfileField(
      key: key,
      required: required,
      acceptedHeaders: acceptedHeadersRaw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      description: description,
    );
  }
}

class CoachOperatorPayoutImportStatusMapping {
  final String normalizedStatus;
  final List<String> acceptedValues;
  final List<String> requiredFields;
  final String description;

  const CoachOperatorPayoutImportStatusMapping({
    required this.normalizedStatus,
    required this.acceptedValues,
    required this.requiredFields,
    required this.description,
  });

  static CoachOperatorPayoutImportStatusMapping? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final normalizedStatus = (raw['normalized_status'] ?? '').toString().trim();
    final acceptedValuesRaw = raw['accepted_values'];
    final requiredFields = _coachStringList(raw['required_fields']);
    final description = (raw['description'] ?? '').toString().trim();
    if (normalizedStatus.isEmpty ||
        acceptedValuesRaw is! List ||
        description.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportStatusMapping(
      normalizedStatus: normalizedStatus,
      acceptedValues: acceptedValuesRaw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      requiredFields: requiredFields,
      description: description,
    );
  }
}

class CoachOperatorPayoutImportProfile {
  final String importSource;
  final String title;
  final String summary;
  final String reportFormat;
  final List<String> supportedDelimiters;
  final List<CoachOperatorPayoutImportStatusMapping> statusMappings;
  final String sampleBody;
  final List<CoachOperatorPayoutImportProfileField> fields;

  const CoachOperatorPayoutImportProfile({
    required this.importSource,
    required this.title,
    required this.summary,
    required this.reportFormat,
    required this.supportedDelimiters,
    required this.statusMappings,
    required this.sampleBody,
    required this.fields,
  });

  static CoachOperatorPayoutImportProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final importSource = (raw['import_source'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    final summary = (raw['summary'] ?? '').toString().trim();
    final reportFormat = (raw['report_format'] ?? '').toString().trim();
    final supportedDelimiters = _coachStringList(raw['supported_delimiters']);
    final statusMappingsRaw = raw['status_mappings'];
    final sampleBody = (raw['sample_body'] ?? '').toString();
    final fieldsRaw = raw['fields'];
    if (importSource.isEmpty ||
        title.isEmpty ||
        summary.isEmpty ||
        reportFormat.isEmpty ||
        sampleBody.isEmpty ||
        statusMappingsRaw is! List ||
        fieldsRaw is! List) {
      return null;
    }
    return CoachOperatorPayoutImportProfile(
      importSource: importSource,
      title: title,
      summary: summary,
      reportFormat: reportFormat,
      supportedDelimiters: supportedDelimiters,
      statusMappings: statusMappingsRaw
          .map(CoachOperatorPayoutImportStatusMapping.fromJson)
          .whereType<CoachOperatorPayoutImportStatusMapping>()
          .toList(growable: false),
      sampleBody: sampleBody,
      fields: fieldsRaw
          .map(CoachOperatorPayoutImportProfileField.fromJson)
          .whereType<CoachOperatorPayoutImportProfileField>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorPayoutImportProfilesResponse {
  final String generatedAtIso;
  final List<CoachOperatorPayoutImportProfile> profiles;

  const CoachOperatorPayoutImportProfilesResponse({
    required this.generatedAtIso,
    required this.profiles,
  });

  static CoachOperatorPayoutImportProfilesResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final profilesRaw = raw['profiles'];
    if (generatedAtIso.isEmpty || profilesRaw is! List) {
      return null;
    }
    return CoachOperatorPayoutImportProfilesResponse(
      generatedAtIso: generatedAtIso,
      profiles: profilesRaw
          .map(CoachOperatorPayoutImportProfile.fromJson)
          .whereType<CoachOperatorPayoutImportProfile>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorPayoutImportsResponse {
  final String generatedAtIso;
  final CoachOperatorPayoutImportsSummary summary;
  final List<CoachOperatorPayoutImport> imports;
  final String? nextCursor;

  const CoachOperatorPayoutImportsResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.imports,
    this.nextCursor,
  });

  static CoachOperatorPayoutImportsResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachOperatorPayoutImportsSummary.fromJson(raw['summary']);
    final importsRaw = raw['imports'];
    if (generatedAtIso.isEmpty || summary == null || importsRaw is! List) {
      return null;
    }
    return CoachOperatorPayoutImportsResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      imports: importsRaw
          .map(CoachOperatorPayoutImport.fromJson)
          .whereType<CoachOperatorPayoutImport>()
          .toList(growable: false),
      nextCursor: (raw['next_cursor'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['next_cursor'] ?? '').toString().trim(),
    );
  }
}

class CoachOperatorCatalogImportRunCounts {
  final int operators;
  final int cities;
  final int stopClusters;
  final int stops;
  final int lines;
  final int serviceCalendars;
  final int trips;
  final int fareProducts;
  final int totalRecords;
  final bool ready;

  const CoachOperatorCatalogImportRunCounts({
    required this.operators,
    required this.cities,
    required this.stopClusters,
    required this.stops,
    required this.lines,
    required this.serviceCalendars,
    required this.trips,
    required this.fareProducts,
    required this.totalRecords,
    required this.ready,
  });

  static CoachOperatorCatalogImportRunCounts? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final operators = raw['operators'];
    final cities = raw['cities'];
    final stopClusters = raw['stop_clusters'];
    final stops = raw['stops'];
    final lines = raw['lines'];
    final serviceCalendars = raw['service_calendars'];
    final trips = raw['trips'];
    final fareProducts = raw['fare_products'];
    final totalRecords = raw['total_records'];
    final ready = raw['ready'];
    if (operators is! int ||
        cities is! int ||
        stopClusters is! int ||
        stops is! int ||
        lines is! int ||
        serviceCalendars is! int ||
        trips is! int ||
        fareProducts is! int ||
        totalRecords is! int ||
        ready is! bool) {
      return null;
    }
    return CoachOperatorCatalogImportRunCounts(
      operators: operators,
      cities: cities,
      stopClusters: stopClusters,
      stops: stops,
      lines: lines,
      serviceCalendars: serviceCalendars,
      trips: trips,
      fareProducts: fareProducts,
      totalRecords: totalRecords,
      ready: ready,
    );
  }
}

class CoachOperatorCatalogSourceArtifact {
  final String artifactId;
  final String feedKind;
  final String sourceKind;
  final String sourceLabel;
  final String fileName;
  final String fileChecksumSha256;
  final int contentLengthBytes;
  final int extractedFileCount;
  final String feedLocator;
  final List<String> operatorIds;
  final String createdByAccountId;
  final String createdAtIso;

  const CoachOperatorCatalogSourceArtifact({
    required this.artifactId,
    required this.feedKind,
    required this.sourceKind,
    required this.sourceLabel,
    required this.fileName,
    required this.fileChecksumSha256,
    required this.contentLengthBytes,
    required this.extractedFileCount,
    required this.feedLocator,
    this.operatorIds = const <String>[],
    required this.createdByAccountId,
    required this.createdAtIso,
  });

  static CoachOperatorCatalogSourceArtifact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final artifactId = (raw['artifact_id'] ?? '').toString().trim();
    final feedKind = (raw['feed_kind'] ?? '').toString().trim();
    final sourceKind = (raw['source_kind'] ?? '').toString().trim();
    final sourceLabel = (raw['source_label'] ?? '').toString().trim();
    final fileName = (raw['file_name'] ?? '').toString().trim();
    final fileChecksumSha256 =
        (raw['file_checksum_sha256'] ?? '').toString().trim();
    final contentLengthBytes = raw['content_length_bytes'];
    final extractedFileCount = raw['extracted_file_count'];
    final feedLocator = (raw['feed_locator'] ?? '').toString().trim();
    final operatorIds = _coachStringList(raw['operator_ids']);
    final createdByAccountId =
        (raw['created_by_account_id'] ?? '').toString().trim();
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    if (artifactId.isEmpty ||
        feedKind.isEmpty ||
        sourceKind.isEmpty ||
        sourceLabel.isEmpty ||
        fileName.isEmpty ||
        fileChecksumSha256.isEmpty ||
        contentLengthBytes is! num ||
        extractedFileCount is! num ||
        feedLocator.isEmpty ||
        createdByAccountId.isEmpty ||
        createdAtIso.isEmpty) {
      return null;
    }
    return CoachOperatorCatalogSourceArtifact(
      artifactId: artifactId,
      feedKind: feedKind,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel,
      fileName: fileName,
      fileChecksumSha256: fileChecksumSha256,
      contentLengthBytes: contentLengthBytes.toInt(),
      extractedFileCount: extractedFileCount.toInt(),
      feedLocator: feedLocator,
      operatorIds: operatorIds,
      createdByAccountId: createdByAccountId,
      createdAtIso: createdAtIso,
    );
  }
}

class CoachOperatorCatalogImportRun {
  final String importRunId;
  final String feedKind;
  final String sourceKind;
  final String triggerKind;
  final String? feedLocator;
  final List<String> operatorIds;
  final String? replayedFromImportRunId;
  final CoachOperatorCatalogImportRunReplayLineageSummary? replayLineageSummary;
  final String? sourceArtifactId;
  final CoachOperatorCatalogSourceArtifact? sourceArtifact;
  final String status;
  final String startedAtIso;
  final String? finishedAtIso;
  final CoachOperatorCatalogImportRunCounts counts;
  final String? errorMessage;
  final List<CoachOperatorCatalogImportRunIssue> issues;

  const CoachOperatorCatalogImportRun({
    required this.importRunId,
    required this.feedKind,
    required this.sourceKind,
    required this.triggerKind,
    required this.feedLocator,
    this.operatorIds = const <String>[],
    this.replayedFromImportRunId,
    this.replayLineageSummary,
    this.sourceArtifactId,
    required this.sourceArtifact,
    required this.status,
    required this.startedAtIso,
    required this.finishedAtIso,
    required this.counts,
    required this.errorMessage,
    required this.issues,
  });

  bool get isFailed => status == 'failed';
  bool get isRunning => status == 'running';
  bool get isSucceeded => status == 'succeeded';

  static CoachOperatorCatalogImportRun? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final importRunId = (raw['import_run_id'] ?? '').toString().trim();
    final feedKind = (raw['feed_kind'] ?? '').toString().trim();
    final sourceKind = (raw['source_kind'] ?? '').toString().trim();
    final triggerKind = (raw['trigger_kind'] ?? '').toString().trim();
    final feedLocator = (raw['feed_locator'] ?? '').toString().trim();
    final operatorIds = _coachStringList(raw['operator_ids']);
    final replayedFromImportRunId =
        (raw['replayed_from_import_run_id'] ?? '').toString().trim();
    final replayLineageSummary =
        CoachOperatorCatalogImportRunReplayLineageSummary.fromJson(
      raw['replay_lineage_summary'],
    );
    final sourceArtifactId =
        (raw['source_artifact_id'] ?? '').toString().trim();
    final sourceArtifact =
        CoachOperatorCatalogSourceArtifact.fromJson(raw['source_artifact']);
    final status = (raw['status'] ?? '').toString().trim();
    final startedAtIso = (raw['started_at'] ?? '').toString().trim();
    final finishedAtIso = (raw['finished_at'] ?? '').toString().trim();
    final counts = CoachOperatorCatalogImportRunCounts.fromJson(raw['counts']);
    final errorMessage = (raw['error_message'] ?? '').toString().trim();
    final issuesRaw = raw['issues'];
    if (importRunId.isEmpty ||
        feedKind.isEmpty ||
        sourceKind.isEmpty ||
        triggerKind.isEmpty ||
        status.isEmpty ||
        startedAtIso.isEmpty ||
        counts == null ||
        (issuesRaw != null && issuesRaw is! List)) {
      return null;
    }
    return CoachOperatorCatalogImportRun(
      importRunId: importRunId,
      feedKind: feedKind,
      sourceKind: sourceKind,
      triggerKind: triggerKind,
      feedLocator: feedLocator.isEmpty ? null : feedLocator,
      operatorIds: operatorIds,
      replayedFromImportRunId:
          replayedFromImportRunId.isEmpty ? null : replayedFromImportRunId,
      replayLineageSummary: replayLineageSummary,
      sourceArtifactId: sourceArtifactId.isEmpty
          ? sourceArtifact?.artifactId
          : sourceArtifactId,
      sourceArtifact: sourceArtifact,
      status: status,
      startedAtIso: startedAtIso,
      finishedAtIso: finishedAtIso.isEmpty ? null : finishedAtIso,
      counts: counts,
      errorMessage: errorMessage.isEmpty ? null : errorMessage,
      issues: (issuesRaw as List? ?? const <Object?>[])
          .map(CoachOperatorCatalogImportRunIssue.fromJson)
          .whereType<CoachOperatorCatalogImportRunIssue>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorCatalogImportRunReplayLineageSummary {
  final int replayRunCount;
  final String? latestReplayRunId;
  final String? latestReplayStartedAtIso;

  const CoachOperatorCatalogImportRunReplayLineageSummary({
    required this.replayRunCount,
    required this.latestReplayRunId,
    required this.latestReplayStartedAtIso,
  });

  static CoachOperatorCatalogImportRunReplayLineageSummary? fromJson(
    Object? raw,
  ) {
    if (raw is! Map) return null;
    final replayRunCount = raw['replay_run_count'];
    final latestReplayRunId =
        (raw['latest_replay_run_id'] ?? '').toString().trim();
    final latestReplayStartedAtIso =
        (raw['latest_replay_started_at'] ?? '').toString().trim();
    if (replayRunCount is! int) {
      return null;
    }
    return CoachOperatorCatalogImportRunReplayLineageSummary(
      replayRunCount: replayRunCount,
      latestReplayRunId: latestReplayRunId.isEmpty ? null : latestReplayRunId,
      latestReplayStartedAtIso:
          latestReplayStartedAtIso.isEmpty ? null : latestReplayStartedAtIso,
    );
  }
}

class CoachOperatorCatalogImportRunIssue {
  final String issueId;
  final String severity;
  final String stage;
  final String code;
  final String message;
  final String? fileName;
  final String? rowReference;

  const CoachOperatorCatalogImportRunIssue({
    required this.issueId,
    required this.severity,
    required this.stage,
    required this.code,
    required this.message,
    required this.fileName,
    required this.rowReference,
  });

  static CoachOperatorCatalogImportRunIssue? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final issueId = (raw['issue_id'] ?? '').toString().trim();
    final severity = (raw['severity'] ?? '').toString().trim();
    final stage = (raw['stage'] ?? '').toString().trim();
    final code = (raw['code'] ?? '').toString().trim();
    final message = (raw['message'] ?? '').toString().trim();
    final fileName = (raw['file_name'] ?? '').toString().trim();
    final rowReference = (raw['row_reference'] ?? '').toString().trim();
    if (issueId.isEmpty ||
        severity.isEmpty ||
        stage.isEmpty ||
        code.isEmpty ||
        message.isEmpty) {
      return null;
    }
    return CoachOperatorCatalogImportRunIssue(
      issueId: issueId,
      severity: severity,
      stage: stage,
      code: code,
      message: message,
      fileName: fileName.isEmpty ? null : fileName,
      rowReference: rowReference.isEmpty ? null : rowReference,
    );
  }
}

class CoachOperatorCatalogImportRunsSummary {
  final int totalRuns;
  final int succeededRuns;
  final int failedRuns;
  final int runningRuns;
  final int importedRecordsTotal;
  final String? latestSucceededAtIso;

  const CoachOperatorCatalogImportRunsSummary({
    required this.totalRuns,
    required this.succeededRuns,
    required this.failedRuns,
    required this.runningRuns,
    required this.importedRecordsTotal,
    required this.latestSucceededAtIso,
  });

  static CoachOperatorCatalogImportRunsSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final totalRuns = raw['total_runs'];
    final succeededRuns = raw['succeeded_runs'];
    final failedRuns = raw['failed_runs'];
    final runningRuns = raw['running_runs'];
    final importedRecordsTotal = raw['imported_records_total'];
    final latestSucceededAtIso =
        (raw['latest_succeeded_at'] ?? '').toString().trim();
    if (totalRuns is! int ||
        succeededRuns is! int ||
        failedRuns is! int ||
        runningRuns is! int ||
        importedRecordsTotal is! int) {
      return null;
    }
    return CoachOperatorCatalogImportRunsSummary(
      totalRuns: totalRuns,
      succeededRuns: succeededRuns,
      failedRuns: failedRuns,
      runningRuns: runningRuns,
      importedRecordsTotal: importedRecordsTotal,
      latestSucceededAtIso:
          latestSucceededAtIso.isEmpty ? null : latestSucceededAtIso,
    );
  }
}

class CoachOperatorCatalogImportRunsResponse {
  final String generatedAtIso;
  final CoachOperatorCatalogImportRunsSummary summary;
  final List<CoachOperatorCatalogImportRun> importRuns;
  final String? nextCursor;

  const CoachOperatorCatalogImportRunsResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.importRuns,
    required this.nextCursor,
  });

  static CoachOperatorCatalogImportRunsResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary =
        CoachOperatorCatalogImportRunsSummary.fromJson(raw['summary']);
    final importRunsRaw = raw['import_runs'];
    final nextCursor = (raw['next_cursor'] ?? '').toString().trim();
    if (generatedAtIso.isEmpty || summary == null || importRunsRaw is! List) {
      return null;
    }
    return CoachOperatorCatalogImportRunsResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      importRuns: importRunsRaw
          .map(CoachOperatorCatalogImportRun.fromJson)
          .whereType<CoachOperatorCatalogImportRun>()
          .toList(growable: false),
      nextCursor: nextCursor.isEmpty ? null : nextCursor,
    );
  }
}

class CoachOperatorCatalogImportRunMutationResult {
  final String command;
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorCatalogImportRun importRun;
  final String nextAction;

  const CoachOperatorCatalogImportRunMutationResult({
    required this.command,
    required this.idempotency,
    required this.importRun,
    required this.nextAction,
  });

  static CoachOperatorCatalogImportRunMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] ?? '').toString().trim();
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final importRun = CoachOperatorCatalogImportRun.fromJson(raw['import_run']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (command.isEmpty ||
        idempotency == null ||
        importRun == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorCatalogImportRunMutationResult(
      command: command,
      idempotency: idempotency,
      importRun: importRun,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorCatalogImportRunDetailResponse {
  final String generatedAtIso;
  final CoachOperatorCatalogImportRunIssuesSummary issuesSummary;
  final CoachOperatorCatalogImportRunIssueFilters issuesFilters;
  final String? issuesNextCursor;
  final CoachOperatorCatalogImportRun importRun;

  const CoachOperatorCatalogImportRunDetailResponse({
    required this.generatedAtIso,
    required this.issuesSummary,
    required this.issuesFilters,
    required this.issuesNextCursor,
    required this.importRun,
  });

  static CoachOperatorCatalogImportRunDetailResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final issuesSummary = CoachOperatorCatalogImportRunIssuesSummary.fromJson(
      raw['issues_summary'],
    );
    final issuesFilters = CoachOperatorCatalogImportRunIssueFilters.fromJson(
      raw['issues_filters'],
    );
    final issuesNextCursor =
        (raw['issues_next_cursor'] ?? '').toString().trim();
    final importRun = CoachOperatorCatalogImportRun.fromJson(raw['import_run']);
    if (generatedAtIso.isEmpty ||
        issuesSummary == null ||
        issuesFilters == null ||
        importRun == null) {
      return null;
    }
    return CoachOperatorCatalogImportRunDetailResponse(
      generatedAtIso: generatedAtIso,
      issuesSummary: issuesSummary,
      issuesFilters: issuesFilters,
      issuesNextCursor: issuesNextCursor.isEmpty ? null : issuesNextCursor,
      importRun: importRun,
    );
  }
}

class CoachOperatorCatalogImportRunIssuesSummary {
  final int totalIssues;
  final int filteredIssues;
  final int errorIssues;
  final int warningIssues;

  const CoachOperatorCatalogImportRunIssuesSummary({
    required this.totalIssues,
    required this.filteredIssues,
    required this.errorIssues,
    required this.warningIssues,
  });

  static CoachOperatorCatalogImportRunIssuesSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final totalIssues = raw['total_issues'];
    final filteredIssues = raw['filtered_issues'];
    final errorIssues = raw['error_issues'];
    final warningIssues = raw['warning_issues'];
    if (totalIssues is! int ||
        filteredIssues is! int ||
        errorIssues is! int ||
        warningIssues is! int) {
      return null;
    }
    return CoachOperatorCatalogImportRunIssuesSummary(
      totalIssues: totalIssues,
      filteredIssues: filteredIssues,
      errorIssues: errorIssues,
      warningIssues: warningIssues,
    );
  }
}

class CoachOperatorCatalogImportRunIssueFilters {
  final String? severity;
  final String? stage;
  final List<String> availableSeverities;
  final List<String> availableStages;

  const CoachOperatorCatalogImportRunIssueFilters({
    required this.severity,
    required this.stage,
    required this.availableSeverities,
    required this.availableStages,
  });

  static CoachOperatorCatalogImportRunIssueFilters? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final severity = (raw['severity'] ?? '').toString().trim();
    final stage = (raw['stage'] ?? '').toString().trim();
    final availableSeverities = _coachStringList(
      raw['available_severities'],
    ).toList(growable: false);
    final availableStages = _coachStringList(
      raw['available_stages'],
    ).toList(growable: false);
    return CoachOperatorCatalogImportRunIssueFilters(
      severity: severity.isEmpty ? null : severity,
      stage: stage.isEmpty ? null : stage,
      availableSeverities: availableSeverities,
      availableStages: availableStages,
    );
  }
}

class CoachOperatorCatalogImportRunReplayRunsSummary {
  final int totalRuns;
  final int failedRuns;
  final int succeededRuns;
  final int runningRuns;
  final String? latestStartedAtIso;

  const CoachOperatorCatalogImportRunReplayRunsSummary({
    required this.totalRuns,
    required this.failedRuns,
    required this.succeededRuns,
    required this.runningRuns,
    required this.latestStartedAtIso,
  });

  static CoachOperatorCatalogImportRunReplayRunsSummary? fromJson(
    Object? raw,
  ) {
    if (raw is! Map) return null;
    final totalRuns = raw['total_runs'];
    final failedRuns = raw['failed_runs'];
    final succeededRuns = raw['succeeded_runs'];
    final runningRuns = raw['running_runs'];
    final latestStartedAtIso =
        (raw['latest_started_at'] ?? '').toString().trim();
    if (totalRuns is! int ||
        failedRuns is! int ||
        succeededRuns is! int ||
        runningRuns is! int) {
      return null;
    }
    return CoachOperatorCatalogImportRunReplayRunsSummary(
      totalRuns: totalRuns,
      failedRuns: failedRuns,
      succeededRuns: succeededRuns,
      runningRuns: runningRuns,
      latestStartedAtIso:
          latestStartedAtIso.isEmpty ? null : latestStartedAtIso,
    );
  }
}

class CoachOperatorCatalogImportRunLineageResponse {
  final String generatedAtIso;
  final CoachOperatorCatalogImportRun importRun;
  final CoachOperatorCatalogImportRunReplayRunsSummary replayRunsSummary;
  final String? replayRunsNextCursor;
  final List<CoachOperatorCatalogImportRun> replayRuns;

  const CoachOperatorCatalogImportRunLineageResponse({
    required this.generatedAtIso,
    required this.importRun,
    required this.replayRunsSummary,
    required this.replayRunsNextCursor,
    required this.replayRuns,
  });

  static CoachOperatorCatalogImportRunLineageResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final importRun = CoachOperatorCatalogImportRun.fromJson(raw['import_run']);
    final replayRunsSummary =
        CoachOperatorCatalogImportRunReplayRunsSummary.fromJson(
      raw['replay_runs_summary'],
    );
    final replayRunsNextCursor =
        (raw['replay_runs_next_cursor'] ?? '').toString().trim();
    final replayRunsRaw = raw['replay_runs'];
    if (generatedAtIso.isEmpty ||
        importRun == null ||
        replayRunsSummary == null ||
        replayRunsRaw is! List) {
      return null;
    }
    return CoachOperatorCatalogImportRunLineageResponse(
      generatedAtIso: generatedAtIso,
      importRun: importRun,
      replayRunsSummary: replayRunsSummary,
      replayRunsNextCursor:
          replayRunsNextCursor.isEmpty ? null : replayRunsNextCursor,
      replayRuns: replayRunsRaw
          .map(CoachOperatorCatalogImportRun.fromJson)
          .whereType<CoachOperatorCatalogImportRun>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorCatalogImportConfigResponse {
  final String generatedAtIso;
  final String sourceKind;
  final bool configured;
  final String? feedLocator;
  final String status;
  final String detail;
  final String configOrigin;
  final CoachOperatorCatalogSourceArtifact? sourceArtifact;
  final String? updatedAtIso;
  final String? updatedByAccountId;
  final CoachOperatorCatalogImportRun? latestImportRun;

  const CoachOperatorCatalogImportConfigResponse({
    required this.generatedAtIso,
    required this.sourceKind,
    required this.configured,
    required this.feedLocator,
    required this.status,
    required this.detail,
    required this.configOrigin,
    required this.sourceArtifact,
    required this.updatedAtIso,
    required this.updatedByAccountId,
    required this.latestImportRun,
  });

  bool get isReady => status == 'ready';

  static CoachOperatorCatalogImportConfigResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final sourceKind = (raw['source_kind'] ?? '').toString().trim();
    final configured = raw['configured'];
    final feedLocator = (raw['feed_locator'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final detail = (raw['detail'] ?? '').toString().trim();
    final configOrigin = (raw['config_origin'] ?? '').toString().trim();
    final sourceArtifact =
        CoachOperatorCatalogSourceArtifact.fromJson(raw['source_artifact']);
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    final updatedByAccountId =
        (raw['updated_by_account_id'] ?? '').toString().trim();
    final latestImportRun =
        CoachOperatorCatalogImportRun.fromJson(raw['latest_import_run']);
    if (generatedAtIso.isEmpty ||
        sourceKind.isEmpty ||
        configured is! bool ||
        status.isEmpty ||
        detail.isEmpty ||
        configOrigin.isEmpty) {
      return null;
    }
    return CoachOperatorCatalogImportConfigResponse(
      generatedAtIso: generatedAtIso,
      sourceKind: sourceKind,
      configured: configured,
      feedLocator: feedLocator.isEmpty ? null : feedLocator,
      status: status,
      detail: detail,
      configOrigin: configOrigin,
      sourceArtifact: sourceArtifact,
      updatedAtIso: updatedAtIso.isEmpty ? null : updatedAtIso,
      updatedByAccountId:
          updatedByAccountId.isEmpty ? null : updatedByAccountId,
      latestImportRun: latestImportRun,
    );
  }
}

class CoachOperatorCatalogImportConfigMutationResult {
  final String command;
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorCatalogImportConfigResponse config;
  final String nextAction;

  const CoachOperatorCatalogImportConfigMutationResult({
    required this.command,
    required this.idempotency,
    required this.config,
    required this.nextAction,
  });

  static CoachOperatorCatalogImportConfigMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] ?? '').toString().trim();
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final config =
        CoachOperatorCatalogImportConfigResponse.fromJson(raw['config']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (command.isEmpty ||
        idempotency == null ||
        config == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorCatalogImportConfigMutationResult(
      command: command,
      idempotency: idempotency,
      config: config,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorCatalogImportSourceOption {
  final String sourceKind;
  final String feedLocator;
  final String sourceOrigin;
  final String sourceLabel;
  final String status;
  final String detail;
  final bool selected;

  const CoachOperatorCatalogImportSourceOption({
    required this.sourceKind,
    required this.feedLocator,
    required this.sourceOrigin,
    required this.sourceLabel,
    required this.status,
    required this.detail,
    required this.selected,
  });

  bool get isReady => status == 'ready';

  static CoachOperatorCatalogImportSourceOption? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sourceKind = (raw['source_kind'] ?? '').toString().trim();
    final feedLocator = (raw['feed_locator'] ?? '').toString().trim();
    final sourceOrigin = (raw['source_origin'] ?? '').toString().trim();
    final sourceLabel = (raw['source_label'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final detail = (raw['detail'] ?? '').toString().trim();
    final selected = raw['selected'];
    if (sourceKind.isEmpty ||
        feedLocator.isEmpty ||
        sourceOrigin.isEmpty ||
        sourceLabel.isEmpty ||
        status.isEmpty ||
        detail.isEmpty ||
        selected is! bool) {
      return null;
    }
    return CoachOperatorCatalogImportSourceOption(
      sourceKind: sourceKind,
      feedLocator: feedLocator,
      sourceOrigin: sourceOrigin,
      sourceLabel: sourceLabel,
      status: status,
      detail: detail,
      selected: selected,
    );
  }
}

class CoachOperatorCatalogImportSourcesResponse {
  final String generatedAtIso;
  final List<CoachOperatorCatalogImportSourceOption> sources;

  const CoachOperatorCatalogImportSourcesResponse({
    required this.generatedAtIso,
    required this.sources,
  });

  static CoachOperatorCatalogImportSourcesResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final sourcesRaw = raw['sources'];
    if (generatedAtIso.isEmpty || sourcesRaw is! List) {
      return null;
    }
    return CoachOperatorCatalogImportSourcesResponse(
      generatedAtIso: generatedAtIso,
      sources: sourcesRaw
          .map(CoachOperatorCatalogImportSourceOption.fromJson)
          .whereType<CoachOperatorCatalogImportSourceOption>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorCatalogSourceArtifactsSummary {
  final int totalArtifacts;
  final int uploadedBytesTotal;
  final String? latestCreatedAtIso;

  const CoachOperatorCatalogSourceArtifactsSummary({
    required this.totalArtifacts,
    required this.uploadedBytesTotal,
    required this.latestCreatedAtIso,
  });

  static CoachOperatorCatalogSourceArtifactsSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final totalArtifacts = raw['total_artifacts'];
    final uploadedBytesTotal = raw['uploaded_bytes_total'];
    final latestCreatedAtIso =
        (raw['latest_created_at'] ?? '').toString().trim();
    if (totalArtifacts is! int || uploadedBytesTotal is! int) {
      return null;
    }
    return CoachOperatorCatalogSourceArtifactsSummary(
      totalArtifacts: totalArtifacts,
      uploadedBytesTotal: uploadedBytesTotal,
      latestCreatedAtIso:
          latestCreatedAtIso.isEmpty ? null : latestCreatedAtIso,
    );
  }
}

class CoachOperatorCatalogSourceArtifactsResponse {
  final String generatedAtIso;
  final CoachOperatorCatalogSourceArtifactsSummary summary;
  final List<CoachOperatorCatalogSourceArtifact> artifacts;
  final String? nextCursor;

  const CoachOperatorCatalogSourceArtifactsResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.artifacts,
    required this.nextCursor,
  });

  static CoachOperatorCatalogSourceArtifactsResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary =
        CoachOperatorCatalogSourceArtifactsSummary.fromJson(raw['summary']);
    final artifactsRaw = raw['artifacts'];
    final nextCursor = (raw['next_cursor'] ?? '').toString().trim();
    if (generatedAtIso.isEmpty || summary == null || artifactsRaw is! List) {
      return null;
    }
    return CoachOperatorCatalogSourceArtifactsResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      artifacts: artifactsRaw
          .map(CoachOperatorCatalogSourceArtifact.fromJson)
          .whereType<CoachOperatorCatalogSourceArtifact>()
          .toList(growable: false),
      nextCursor: nextCursor.isEmpty ? null : nextCursor,
    );
  }
}

class CoachOperatorCatalogSourceArtifactDetailResponse {
  final String generatedAtIso;
  final CoachOperatorCatalogSourceArtifact sourceArtifact;
  final CoachOperatorCatalogSourceArtifactReferencingRunsSummary
      referencingImportRunsSummary;
  final String? referencingImportRunsNextCursor;
  final List<CoachOperatorCatalogImportRun> referencingImportRuns;

  const CoachOperatorCatalogSourceArtifactDetailResponse({
    required this.generatedAtIso,
    required this.sourceArtifact,
    required this.referencingImportRunsSummary,
    required this.referencingImportRunsNextCursor,
    required this.referencingImportRuns,
  });

  static CoachOperatorCatalogSourceArtifactDetailResponse? fromJson(
    Object? raw,
  ) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final sourceArtifact =
        CoachOperatorCatalogSourceArtifact.fromJson(raw['source_artifact']);
    final referencingImportRunsSummary =
        CoachOperatorCatalogSourceArtifactReferencingRunsSummary.fromJson(
      raw['referencing_import_runs_summary'],
    );
    final referencingImportRunsNextCursor =
        (raw['referencing_import_runs_next_cursor'] ?? '').toString().trim();
    final importRunsRaw = raw['referencing_import_runs'];
    if (generatedAtIso.isEmpty ||
        sourceArtifact == null ||
        referencingImportRunsSummary == null ||
        importRunsRaw is! List) {
      return null;
    }
    return CoachOperatorCatalogSourceArtifactDetailResponse(
      generatedAtIso: generatedAtIso,
      sourceArtifact: sourceArtifact,
      referencingImportRunsSummary: referencingImportRunsSummary,
      referencingImportRunsNextCursor: referencingImportRunsNextCursor.isEmpty
          ? null
          : referencingImportRunsNextCursor,
      referencingImportRuns: importRunsRaw
          .map(CoachOperatorCatalogImportRun.fromJson)
          .whereType<CoachOperatorCatalogImportRun>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorCatalogSourceArtifactReferencingRunsSummary {
  final int totalRuns;
  final int failedRuns;
  final int succeededRuns;
  final int runningRuns;
  final String? latestStartedAtIso;

  const CoachOperatorCatalogSourceArtifactReferencingRunsSummary({
    required this.totalRuns,
    required this.failedRuns,
    required this.succeededRuns,
    required this.runningRuns,
    required this.latestStartedAtIso,
  });

  static CoachOperatorCatalogSourceArtifactReferencingRunsSummary? fromJson(
    Object? raw,
  ) {
    if (raw is! Map) return null;
    final totalRuns = raw['total_runs'];
    final failedRuns = raw['failed_runs'];
    final succeededRuns = raw['succeeded_runs'];
    final runningRuns = raw['running_runs'];
    final latestStartedAtIso =
        (raw['latest_started_at'] ?? '').toString().trim();
    if (totalRuns is! int ||
        failedRuns is! int ||
        succeededRuns is! int ||
        runningRuns is! int) {
      return null;
    }
    return CoachOperatorCatalogSourceArtifactReferencingRunsSummary(
      totalRuns: totalRuns,
      failedRuns: failedRuns,
      succeededRuns: succeededRuns,
      runningRuns: runningRuns,
      latestStartedAtIso:
          latestStartedAtIso.isEmpty ? null : latestStartedAtIso,
    );
  }
}

class CoachOperatorCatalogImportUploadedSource {
  final String sourceArtifactId;
  final String sourceKind;
  final String sourceLabel;
  final String fileName;
  final String fileChecksumSha256;
  final int contentLengthBytes;
  final String feedLocator;
  final int extractedFileCount;
  final List<String> operatorIds;

  const CoachOperatorCatalogImportUploadedSource({
    required this.sourceArtifactId,
    required this.sourceKind,
    required this.sourceLabel,
    required this.fileName,
    required this.fileChecksumSha256,
    required this.contentLengthBytes,
    required this.feedLocator,
    required this.extractedFileCount,
    this.operatorIds = const <String>[],
  });

  static CoachOperatorCatalogImportUploadedSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sourceArtifactId =
        (raw['source_artifact_id'] ?? '').toString().trim();
    final sourceKind = (raw['source_kind'] ?? '').toString().trim();
    final sourceLabel = (raw['source_label'] ?? '').toString().trim();
    final fileName = (raw['file_name'] ?? '').toString().trim();
    final fileChecksumSha256 =
        (raw['file_checksum_sha256'] ?? '').toString().trim();
    final contentLengthBytes = raw['content_length_bytes'];
    final feedLocator = (raw['feed_locator'] ?? '').toString().trim();
    final extractedFileCount = raw['extracted_file_count'];
    final operatorIds = _coachStringList(raw['operator_ids']);
    if (sourceArtifactId.isEmpty ||
        sourceKind.isEmpty ||
        sourceLabel.isEmpty ||
        fileName.isEmpty ||
        fileChecksumSha256.isEmpty ||
        contentLengthBytes is! num ||
        feedLocator.isEmpty ||
        extractedFileCount is! num) {
      return null;
    }
    return CoachOperatorCatalogImportUploadedSource(
      sourceArtifactId: sourceArtifactId,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel,
      fileName: fileName,
      fileChecksumSha256: fileChecksumSha256,
      contentLengthBytes: contentLengthBytes.toInt(),
      feedLocator: feedLocator,
      extractedFileCount: extractedFileCount.toInt(),
      operatorIds: operatorIds,
    );
  }
}

class CoachOperatorCatalogImportSourceUploadResult {
  final String command;
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorCatalogImportUploadedSource uploadedSource;
  final CoachOperatorCatalogImportConfigResponse config;
  final String nextAction;

  const CoachOperatorCatalogImportSourceUploadResult({
    required this.command,
    required this.idempotency,
    required this.uploadedSource,
    required this.config,
    required this.nextAction,
  });

  static CoachOperatorCatalogImportSourceUploadResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] ?? '').toString().trim();
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final uploadedSource = CoachOperatorCatalogImportUploadedSource.fromJson(
        raw['uploaded_source']);
    final config =
        CoachOperatorCatalogImportConfigResponse.fromJson(raw['config']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (command.isEmpty ||
        idempotency == null ||
        uploadedSource == null ||
        config == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorCatalogImportSourceUploadResult(
      command: command,
      idempotency: idempotency,
      uploadedSource: uploadedSource,
      config: config,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorFeedHealthSummary {
  final int operatorsTotal;
  final int healthyOperators;
  final int degradedFeeds;
  final int staleFeeds;

  const CoachOperatorFeedHealthSummary({
    required this.operatorsTotal,
    required this.healthyOperators,
    required this.degradedFeeds,
    required this.staleFeeds,
  });

  static CoachOperatorFeedHealthSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final operatorsTotal = raw['operators_total'];
    final healthyOperators = raw['healthy_operators'];
    final degradedFeeds = raw['degraded_feeds'];
    final staleFeeds = raw['stale_feeds'];
    if (operatorsTotal is! int ||
        healthyOperators is! int ||
        degradedFeeds is! int ||
        staleFeeds is! int) {
      return null;
    }
    return CoachOperatorFeedHealthSummary(
      operatorsTotal: operatorsTotal,
      healthyOperators: healthyOperators,
      degradedFeeds: degradedFeeds,
      staleFeeds: staleFeeds,
    );
  }
}

class CoachOperatorFeedHealthResponse {
  final String generatedAtIso;
  final CoachOperatorFeedHealthSummary summary;
  final List<CoachOperatorFeedHealth> feeds;

  const CoachOperatorFeedHealthResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.feeds,
  });

  static CoachOperatorFeedHealthResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachOperatorFeedHealthSummary.fromJson(raw['summary']);
    final feedsRaw = raw['feeds'];
    if (generatedAtIso.isEmpty || summary == null || feedsRaw is! List) {
      return null;
    }
    return CoachOperatorFeedHealthResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      feeds: feedsRaw
          .map(CoachOperatorFeedHealth.fromJson)
          .whereType<CoachOperatorFeedHealth>()
          .toList(growable: false),
    );
  }
}

class CoachAdminPartnerOnboardingSummary {
  final int operatorsTotal;
  final int draftOperators;
  final int inReviewOperators;
  final int actionRequiredOperators;
  final int approvedOperators;
  final int suspendedOperators;
  final int missingDocuments;
  final int expiringDocuments;

  const CoachAdminPartnerOnboardingSummary({
    required this.operatorsTotal,
    required this.draftOperators,
    required this.inReviewOperators,
    required this.actionRequiredOperators,
    required this.approvedOperators,
    required this.suspendedOperators,
    required this.missingDocuments,
    required this.expiringDocuments,
  });

  static CoachAdminPartnerOnboardingSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final operatorsTotal = raw['operators_total'];
    final draftOperators = raw['draft_operators'];
    final inReviewOperators = raw['in_review_operators'];
    final actionRequiredOperators = raw['action_required_operators'];
    final approvedOperators = raw['approved_operators'];
    final suspendedOperators = raw['suspended_operators'];
    final missingDocuments = raw['missing_documents'];
    final expiringDocuments = raw['expiring_documents'];
    if (operatorsTotal is! int ||
        draftOperators is! int ||
        inReviewOperators is! int ||
        actionRequiredOperators is! int ||
        approvedOperators is! int ||
        suspendedOperators is! int ||
        missingDocuments is! int ||
        expiringDocuments is! int) {
      return null;
    }
    return CoachAdminPartnerOnboardingSummary(
      operatorsTotal: operatorsTotal,
      draftOperators: draftOperators,
      inReviewOperators: inReviewOperators,
      actionRequiredOperators: actionRequiredOperators,
      approvedOperators: approvedOperators,
      suspendedOperators: suspendedOperators,
      missingDocuments: missingDocuments,
      expiringDocuments: expiringDocuments,
    );
  }
}

class CoachAdminPartnerOnboardingDocument {
  final String documentId;
  final String documentKey;
  final String label;
  final String status;
  final bool required;
  final String? expiresAtIso;

  const CoachAdminPartnerOnboardingDocument({
    required this.documentId,
    required this.documentKey,
    required this.label,
    required this.status,
    required this.required,
    required this.expiresAtIso,
  });

  static CoachAdminPartnerOnboardingDocument? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final documentId = (raw['document_id'] ?? '').toString().trim();
    final documentKey = (raw['document_key'] ?? '').toString().trim();
    final label = (raw['label'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final required = raw['required'];
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    if (documentId.isEmpty ||
        documentKey.isEmpty ||
        label.isEmpty ||
        status.isEmpty ||
        required is! bool) {
      return null;
    }
    return CoachAdminPartnerOnboardingDocument(
      documentId: documentId,
      documentKey: documentKey,
      label: label,
      status: status,
      required: required,
      expiresAtIso: expiresAtIso.isEmpty ? null : expiresAtIso,
    );
  }
}

class CoachAdminPartnerOnboardingCapability {
  final String capability;
  final String label;
  final String status;

  const CoachAdminPartnerOnboardingCapability({
    required this.capability,
    required this.label,
    required this.status,
  });

  static CoachAdminPartnerOnboardingCapability? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final capability = (raw['capability'] ?? '').toString().trim();
    final label = (raw['label'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    if (capability.isEmpty || label.isEmpty || status.isEmpty) {
      return null;
    }
    return CoachAdminPartnerOnboardingCapability(
      capability: capability,
      label: label,
      status: status,
    );
  }
}

class CoachAdminPartnerOnboardingChecklistItem {
  final String itemKey;
  final String label;
  final String status;

  const CoachAdminPartnerOnboardingChecklistItem({
    required this.itemKey,
    required this.label,
    required this.status,
  });

  static CoachAdminPartnerOnboardingChecklistItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final itemKey = (raw['item_key'] ?? '').toString().trim();
    final label = (raw['label'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    if (itemKey.isEmpty || label.isEmpty || status.isEmpty) {
      return null;
    }
    return CoachAdminPartnerOnboardingChecklistItem(
      itemKey: itemKey,
      label: label,
      status: status,
    );
  }
}

class CoachAdminPartnerOnboardingFeedSummary {
  final int feedsTotal;
  final int degradedFeeds;
  final int staleFeeds;
  final String? lastSucceededAtIso;

  const CoachAdminPartnerOnboardingFeedSummary({
    required this.feedsTotal,
    required this.degradedFeeds,
    required this.staleFeeds,
    required this.lastSucceededAtIso,
  });

  static CoachAdminPartnerOnboardingFeedSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final feedsTotal = raw['feeds_total'];
    final degradedFeeds = raw['degraded_feeds'];
    final staleFeeds = raw['stale_feeds'];
    final lastSucceededAtIso =
        (raw['last_succeeded_at'] ?? '').toString().trim();
    if (feedsTotal is! int || degradedFeeds is! int || staleFeeds is! int) {
      return null;
    }
    return CoachAdminPartnerOnboardingFeedSummary(
      feedsTotal: feedsTotal,
      degradedFeeds: degradedFeeds,
      staleFeeds: staleFeeds,
      lastSucceededAtIso:
          lastSucceededAtIso.isEmpty ? null : lastSucceededAtIso,
    );
  }
}

class CoachAdminPartnerOnboardingRecord {
  final String operatorId;
  final String operatorName;
  final String integrationMode;
  final String workflowStatus;
  final String lastAction;
  final String? ownerAccountId;
  final String? dueAtIso;
  final String updatedAtIso;
  final String? updatedByAccountId;
  final String? note;
  final int missingDocuments;
  final int expiringDocuments;
  final CoachAdminPartnerOnboardingFeedSummary feedSummary;
  final List<CoachAdminPartnerOnboardingDocument> documents;
  final List<CoachAdminPartnerOnboardingCapability> capabilities;
  final List<CoachAdminPartnerOnboardingChecklistItem> checklist;
  final List<String> blockers;
  final String nextAction;

  const CoachAdminPartnerOnboardingRecord({
    required this.operatorId,
    required this.operatorName,
    required this.integrationMode,
    required this.workflowStatus,
    required this.lastAction,
    required this.ownerAccountId,
    required this.dueAtIso,
    required this.updatedAtIso,
    required this.updatedByAccountId,
    required this.note,
    required this.missingDocuments,
    required this.expiringDocuments,
    required this.feedSummary,
    required this.documents,
    required this.capabilities,
    required this.checklist,
    required this.blockers,
    required this.nextAction,
  });

  int get enabledCapabilities =>
      capabilities.where((capability) => capability.status == 'enabled').length;

  int get pendingCapabilities =>
      capabilities.where((capability) => capability.status == 'pending').length;

  static CoachAdminPartnerOnboardingRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final integrationMode = (raw['integration_mode'] ?? '').toString().trim();
    final workflowStatus = (raw['workflow_status'] ?? '').toString().trim();
    final lastAction = (raw['last_action'] ?? '').toString().trim();
    final ownerAccountId = (raw['owner_account_id'] ?? '').toString().trim();
    final dueAtIso = (raw['due_at'] ?? '').toString().trim();
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    final updatedByAccountId =
        (raw['updated_by_account_id'] ?? '').toString().trim();
    final note = (raw['note'] ?? '').toString().trim();
    final missingDocuments = raw['missing_documents'];
    final expiringDocuments = raw['expiring_documents'];
    final feedSummary =
        CoachAdminPartnerOnboardingFeedSummary.fromJson(raw['feed_summary']);
    final documentsRaw = raw['documents'];
    final capabilitiesRaw = raw['capabilities'];
    final checklistRaw = raw['checklist'];
    final blockers = _coachStringList(raw['blockers']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (operatorId.isEmpty ||
        operatorName.isEmpty ||
        integrationMode.isEmpty ||
        workflowStatus.isEmpty ||
        lastAction.isEmpty ||
        updatedAtIso.isEmpty ||
        missingDocuments is! int ||
        expiringDocuments is! int ||
        feedSummary == null ||
        documentsRaw is! List ||
        capabilitiesRaw is! List ||
        checklistRaw is! List ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachAdminPartnerOnboardingRecord(
      operatorId: operatorId,
      operatorName: operatorName,
      integrationMode: integrationMode,
      workflowStatus: workflowStatus,
      lastAction: lastAction,
      ownerAccountId: ownerAccountId.isEmpty ? null : ownerAccountId,
      dueAtIso: dueAtIso.isEmpty ? null : dueAtIso,
      updatedAtIso: updatedAtIso,
      updatedByAccountId:
          updatedByAccountId.isEmpty ? null : updatedByAccountId,
      note: note.isEmpty ? null : note,
      missingDocuments: missingDocuments,
      expiringDocuments: expiringDocuments,
      feedSummary: feedSummary,
      documents: documentsRaw
          .map(CoachAdminPartnerOnboardingDocument.fromJson)
          .whereType<CoachAdminPartnerOnboardingDocument>()
          .toList(growable: false),
      capabilities: capabilitiesRaw
          .map(CoachAdminPartnerOnboardingCapability.fromJson)
          .whereType<CoachAdminPartnerOnboardingCapability>()
          .toList(growable: false),
      checklist: checklistRaw
          .map(CoachAdminPartnerOnboardingChecklistItem.fromJson)
          .whereType<CoachAdminPartnerOnboardingChecklistItem>()
          .toList(growable: false),
      blockers: blockers,
      nextAction: nextAction,
    );
  }
}

class CoachAdminPartnerOnboardingResponse {
  final String generatedAtIso;
  final CoachAdminPartnerOnboardingSummary summary;
  final List<CoachAdminPartnerOnboardingRecord> partners;

  const CoachAdminPartnerOnboardingResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.partners,
  });

  static CoachAdminPartnerOnboardingResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachAdminPartnerOnboardingSummary.fromJson(raw['summary']);
    final partnersRaw = raw['partners'];
    if (generatedAtIso.isEmpty || summary == null || partnersRaw is! List) {
      return null;
    }
    return CoachAdminPartnerOnboardingResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      partners: partnersRaw
          .map(CoachAdminPartnerOnboardingRecord.fromJson)
          .whereType<CoachAdminPartnerOnboardingRecord>()
          .toList(growable: false),
    );
  }
}

class CoachAdminPartnerOnboardingMutationResult {
  final String operatorId;
  final String action;
  final String updatedAtIso;
  final CoachAdminPartnerOnboardingRecord partner;

  const CoachAdminPartnerOnboardingMutationResult({
    required this.operatorId,
    required this.action,
    required this.updatedAtIso,
    required this.partner,
  });

  static CoachAdminPartnerOnboardingMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final action = (raw['action'] ?? '').toString().trim();
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    final partner = CoachAdminPartnerOnboardingRecord.fromJson(raw['partner']);
    if (operatorId.isEmpty ||
        action.isEmpty ||
        updatedAtIso.isEmpty ||
        partner == null) {
      return null;
    }
    return CoachAdminPartnerOnboardingMutationResult(
      operatorId: operatorId,
      action: action,
      updatedAtIso: updatedAtIso,
      partner: partner,
    );
  }
}

class CoachAdminDisruptionSummary {
  final int tripCount;
  final int scheduledTrips;
  final int monitoringTrips;
  final int actionRequiredTrips;
  final int resolvedTrips;
  final int delayedTrips;
  final int cancelledTrips;
  final int criticalTrips;
  final int affectedBookingCount;
  final int eligibleReaccommodationCount;
  final int queuedReaccommodationCount;

  const CoachAdminDisruptionSummary({
    required this.tripCount,
    required this.scheduledTrips,
    required this.monitoringTrips,
    required this.actionRequiredTrips,
    required this.resolvedTrips,
    required this.delayedTrips,
    required this.cancelledTrips,
    required this.criticalTrips,
    required this.affectedBookingCount,
    required this.eligibleReaccommodationCount,
    required this.queuedReaccommodationCount,
  });

  static CoachAdminDisruptionSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tripCount = raw['trip_count'];
    final scheduledTrips = raw['scheduled_trips'];
    final monitoringTrips = raw['monitoring_trips'];
    final actionRequiredTrips = raw['action_required_trips'];
    final resolvedTrips = raw['resolved_trips'];
    final delayedTrips = raw['delayed_trips'];
    final cancelledTrips = raw['cancelled_trips'];
    final criticalTrips = raw['critical_trips'];
    final affectedBookingCount = raw['affected_booking_count'];
    final eligibleReaccommodationCount = raw['eligible_reaccommodation_count'];
    final queuedReaccommodationCount = raw['queued_reaccommodation_count'];
    if (tripCount is! int ||
        scheduledTrips is! int ||
        monitoringTrips is! int ||
        actionRequiredTrips is! int ||
        resolvedTrips is! int ||
        delayedTrips is! int ||
        cancelledTrips is! int ||
        criticalTrips is! int ||
        affectedBookingCount is! int ||
        eligibleReaccommodationCount is! int ||
        queuedReaccommodationCount is! int) {
      return null;
    }
    return CoachAdminDisruptionSummary(
      tripCount: tripCount,
      scheduledTrips: scheduledTrips,
      monitoringTrips: monitoringTrips,
      actionRequiredTrips: actionRequiredTrips,
      resolvedTrips: resolvedTrips,
      delayedTrips: delayedTrips,
      cancelledTrips: cancelledTrips,
      criticalTrips: criticalTrips,
      affectedBookingCount: affectedBookingCount,
      eligibleReaccommodationCount: eligibleReaccommodationCount,
      queuedReaccommodationCount: queuedReaccommodationCount,
    );
  }
}

class CoachAdminDisruptionTrip {
  final String tripId;
  final String journeyId;
  final String bookingId;
  final String operatorId;
  final String operatorName;
  final String from;
  final String to;
  final String departureAtIso;
  final String arrivalAtIso;
  final String gateLabel;
  final String vehicleLabel;
  final int manifestCount;
  final int boardedCount;
  final int deniedCount;
  final int noShowCount;
  final int pendingCount;
  final String workflowStatus;
  final String? disruptionKind;
  final int? delayMinutes;
  final String severity;
  final int affectedBookingCount;
  final int eligibleReaccommodationCount;
  final int queuedReaccommodationCount;
  final int feedIssueCount;
  final String lastAction;
  final String updatedAtIso;
  final String? updatedByAccountId;
  final String? reason;
  final String? note;
  final List<String> blockers;
  final String nextAction;

  const CoachAdminDisruptionTrip({
    required this.tripId,
    required this.journeyId,
    required this.bookingId,
    required this.operatorId,
    required this.operatorName,
    required this.from,
    required this.to,
    required this.departureAtIso,
    required this.arrivalAtIso,
    required this.gateLabel,
    required this.vehicleLabel,
    required this.manifestCount,
    required this.boardedCount,
    required this.deniedCount,
    required this.noShowCount,
    required this.pendingCount,
    required this.workflowStatus,
    required this.disruptionKind,
    required this.delayMinutes,
    required this.severity,
    required this.affectedBookingCount,
    required this.eligibleReaccommodationCount,
    required this.queuedReaccommodationCount,
    required this.feedIssueCount,
    required this.lastAction,
    required this.updatedAtIso,
    required this.updatedByAccountId,
    required this.reason,
    required this.note,
    required this.blockers,
    required this.nextAction,
  });

  static CoachAdminDisruptionTrip? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tripId = (raw['trip_id'] ?? '').toString().trim();
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final from = (raw['from'] ?? '').toString().trim();
    final to = (raw['to'] ?? '').toString().trim();
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final arrivalAtIso = (raw['arrival_at'] ?? '').toString().trim();
    final gateLabel = (raw['gate_label'] ?? '').toString().trim();
    final vehicleLabel = (raw['vehicle_label'] ?? '').toString().trim();
    final manifestCount = raw['manifest_count'];
    final boardedCount = raw['boarded_count'];
    final deniedCount = raw['denied_count'];
    final noShowCount = raw['no_show_count'];
    final pendingCount = raw['pending_count'];
    final workflowStatus = (raw['workflow_status'] ?? '').toString().trim();
    final disruptionKind = (raw['disruption_kind'] ?? '').toString().trim();
    final delayMinutes = raw['delay_minutes'];
    final severity = (raw['severity'] ?? '').toString().trim();
    final affectedBookingCount = raw['affected_booking_count'];
    final eligibleReaccommodationCount = raw['eligible_reaccommodation_count'];
    final queuedReaccommodationCount = raw['queued_reaccommodation_count'];
    final feedIssueCount = raw['feed_issue_count'];
    final lastAction = (raw['last_action'] ?? '').toString().trim();
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    final updatedByAccountId =
        (raw['updated_by_account_id'] ?? '').toString().trim();
    final reason = (raw['reason'] ?? '').toString().trim();
    final note = (raw['note'] ?? '').toString().trim();
    final blockersRaw = raw['blockers'];
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (tripId.isEmpty ||
        journeyId.isEmpty ||
        bookingId.isEmpty ||
        operatorId.isEmpty ||
        operatorName.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        departureAtIso.isEmpty ||
        arrivalAtIso.isEmpty ||
        gateLabel.isEmpty ||
        vehicleLabel.isEmpty ||
        manifestCount is! int ||
        boardedCount is! int ||
        deniedCount is! int ||
        noShowCount is! int ||
        pendingCount is! int ||
        workflowStatus.isEmpty ||
        severity.isEmpty ||
        affectedBookingCount is! int ||
        eligibleReaccommodationCount is! int ||
        queuedReaccommodationCount is! int ||
        feedIssueCount is! int ||
        lastAction.isEmpty ||
        updatedAtIso.isEmpty ||
        blockersRaw is! List ||
        nextAction.isEmpty) {
      return null;
    }
    final typedDelayMinutes = delayMinutes is int ? delayMinutes : null;
    return CoachAdminDisruptionTrip(
      tripId: tripId,
      journeyId: journeyId,
      bookingId: bookingId,
      operatorId: operatorId,
      operatorName: operatorName,
      from: from,
      to: to,
      departureAtIso: departureAtIso,
      arrivalAtIso: arrivalAtIso,
      gateLabel: gateLabel,
      vehicleLabel: vehicleLabel,
      manifestCount: manifestCount,
      boardedCount: boardedCount,
      deniedCount: deniedCount,
      noShowCount: noShowCount,
      pendingCount: pendingCount,
      workflowStatus: workflowStatus,
      disruptionKind: disruptionKind.isEmpty ? null : disruptionKind,
      delayMinutes: typedDelayMinutes,
      severity: severity,
      affectedBookingCount: affectedBookingCount,
      eligibleReaccommodationCount: eligibleReaccommodationCount,
      queuedReaccommodationCount: queuedReaccommodationCount,
      feedIssueCount: feedIssueCount,
      lastAction: lastAction,
      updatedAtIso: updatedAtIso,
      updatedByAccountId:
          updatedByAccountId.isEmpty ? null : updatedByAccountId,
      reason: reason.isEmpty ? null : reason,
      note: note.isEmpty ? null : note,
      blockers: blockersRaw
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false),
      nextAction: nextAction,
    );
  }
}

class CoachAdminDisruptionsResponse {
  final String generatedAtIso;
  final CoachAdminDisruptionSummary summary;
  final List<CoachAdminDisruptionTrip> trips;

  const CoachAdminDisruptionsResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.trips,
  });

  static CoachAdminDisruptionsResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachAdminDisruptionSummary.fromJson(raw['summary']);
    final tripsRaw = raw['trips'];
    if (generatedAtIso.isEmpty || summary == null || tripsRaw is! List) {
      return null;
    }
    return CoachAdminDisruptionsResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      trips: tripsRaw
          .map(CoachAdminDisruptionTrip.fromJson)
          .whereType<CoachAdminDisruptionTrip>()
          .toList(growable: false),
    );
  }
}

class CoachAdminDisruptionMutationResult {
  final String tripId;
  final String action;
  final String updatedAtIso;
  final List<String> queuedChangeRequestIds;
  final CoachAdminDisruptionTrip trip;

  const CoachAdminDisruptionMutationResult({
    required this.tripId,
    required this.action,
    required this.updatedAtIso,
    required this.queuedChangeRequestIds,
    required this.trip,
  });

  static CoachAdminDisruptionMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tripId = (raw['trip_id'] ?? '').toString().trim();
    final action = (raw['action'] ?? '').toString().trim();
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    final queuedChangeRequestIdsRaw = raw['queued_change_request_ids'];
    final trip = CoachAdminDisruptionTrip.fromJson(raw['trip']);
    if (tripId.isEmpty ||
        action.isEmpty ||
        updatedAtIso.isEmpty ||
        queuedChangeRequestIdsRaw is! List ||
        trip == null) {
      return null;
    }
    return CoachAdminDisruptionMutationResult(
      tripId: tripId,
      action: action,
      updatedAtIso: updatedAtIso,
      queuedChangeRequestIds: queuedChangeRequestIdsRaw
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false),
      trip: trip,
    );
  }
}

class CoachAdminLiveOpsSummary {
  final int tripCount;
  final int boardedPassengers;
  final int pendingBoardingPassengers;
  final int needsAttentionPassengers;

  const CoachAdminLiveOpsSummary({
    required this.tripCount,
    required this.boardedPassengers,
    required this.pendingBoardingPassengers,
    required this.needsAttentionPassengers,
  });

  static CoachAdminLiveOpsSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tripCount = raw['trip_count'];
    final boardedPassengers = raw['boarded_passengers'];
    final pendingBoardingPassengers = raw['pending_boarding_passengers'];
    final needsAttentionPassengers = raw['needs_attention_passengers'];
    if (tripCount is! int ||
        boardedPassengers is! int ||
        pendingBoardingPassengers is! int ||
        needsAttentionPassengers is! int) {
      return null;
    }
    return CoachAdminLiveOpsSummary(
      tripCount: tripCount,
      boardedPassengers: boardedPassengers,
      pendingBoardingPassengers: pendingBoardingPassengers,
      needsAttentionPassengers: needsAttentionPassengers,
    );
  }
}

class CoachAdminSupportSummary {
  final int pendingReviewCount;
  final int urgentRequestCount;
  final int openRefundRequests;
  final int openChangeRequests;

  const CoachAdminSupportSummary({
    required this.pendingReviewCount,
    required this.urgentRequestCount,
    required this.openRefundRequests,
    required this.openChangeRequests,
  });

  static CoachAdminSupportSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final pendingReviewCount = raw['pending_review_count'];
    final urgentRequestCount = raw['urgent_request_count'];
    final openRefundRequests = raw['open_refund_requests'];
    final openChangeRequests = raw['open_change_requests'];
    if (pendingReviewCount is! int ||
        urgentRequestCount is! int ||
        openRefundRequests is! int ||
        openChangeRequests is! int) {
      return null;
    }
    return CoachAdminSupportSummary(
      pendingReviewCount: pendingReviewCount,
      urgentRequestCount: urgentRequestCount,
      openRefundRequests: openRefundRequests,
      openChangeRequests: openChangeRequests,
    );
  }
}

class CoachAdminFinanceSummary {
  final String currency;
  final int statementCount;
  final int queuedPayoutRuns;
  final int failedPayoutRuns;
  final int netPayableMinorUnits;

  const CoachAdminFinanceSummary({
    required this.currency,
    required this.statementCount,
    required this.queuedPayoutRuns,
    required this.failedPayoutRuns,
    required this.netPayableMinorUnits,
  });

  static CoachAdminFinanceSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final statementCount = raw['statement_count'];
    final queuedPayoutRuns = raw['queued_payout_runs'];
    final failedPayoutRuns = raw['failed_payout_runs'];
    final netPayableMinorUnits = raw['net_payable_minor_units'];
    if (!_isCoachCurrency(currency) ||
        statementCount is! int ||
        queuedPayoutRuns is! int ||
        failedPayoutRuns is! int ||
        netPayableMinorUnits is! int) {
      return null;
    }
    return CoachAdminFinanceSummary(
      currency: currency,
      statementCount: statementCount,
      queuedPayoutRuns: queuedPayoutRuns,
      failedPayoutRuns: failedPayoutRuns,
      netPayableMinorUnits: netPayableMinorUnits,
    );
  }
}

class CoachAdminOverviewResponse {
  final String generatedAtIso;
  final CoachAdminLiveOpsSummary liveOpsSummary;
  final CoachCrewDepartureBoardResponse departures;
  final CoachAdminDisruptionSummary? disruptionSummary;
  final CoachAdminSupportSummary supportSummary;
  final CoachOperatorRefundQueueResponse refundQueue;
  final CoachOperatorChangeQueueResponse changeQueue;
  final CoachAdminFinanceSummary financeSummary;
  final CoachOperatorReconciliationResponse reconciliation;
  final CoachOperatorSettlementStatementsResponse settlementStatements;
  final CoachOperatorPayoutRunsResponse payoutRuns;
  final CoachOperatorFeedHealthResponse feedHealth;
  final CoachAdminPartnerOnboardingSummary? partnerOnboardingSummary;

  const CoachAdminOverviewResponse({
    required this.generatedAtIso,
    required this.liveOpsSummary,
    required this.departures,
    this.disruptionSummary,
    required this.supportSummary,
    required this.refundQueue,
    required this.changeQueue,
    required this.financeSummary,
    required this.reconciliation,
    required this.settlementStatements,
    required this.payoutRuns,
    required this.feedHealth,
    this.partnerOnboardingSummary,
  });

  static CoachAdminOverviewResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final liveOps = raw['live_ops'];
    final support = raw['support'];
    final finance = raw['finance'];
    final partners = raw['partners'];
    if (generatedAtIso.isEmpty ||
        liveOps is! Map ||
        support is! Map ||
        finance is! Map ||
        partners is! Map) {
      return null;
    }
    final liveOpsSummary =
        CoachAdminLiveOpsSummary.fromJson(liveOps['summary']);
    final departures =
        CoachCrewDepartureBoardResponse.fromJson(liveOps['departures']);
    final disruptionSummary =
        CoachAdminDisruptionSummary.fromJson(liveOps['disruptions_summary']);
    final supportSummary =
        CoachAdminSupportSummary.fromJson(support['summary']);
    final refundQueue =
        CoachOperatorRefundQueueResponse.fromJson(support['refund_queue']);
    final changeQueue =
        CoachOperatorChangeQueueResponse.fromJson(support['change_queue']);
    final financeSummary =
        CoachAdminFinanceSummary.fromJson(finance['summary']);
    final reconciliation =
        CoachOperatorReconciliationResponse.fromJson(finance['reconciliation']);
    final settlementStatements =
        CoachOperatorSettlementStatementsResponse.fromJson(
            finance['settlement_statements']);
    final payoutRuns =
        CoachOperatorPayoutRunsResponse.fromJson(finance['payout_runs']);
    final feedHealth =
        CoachOperatorFeedHealthResponse.fromJson(partners['feed_health']);
    final partnerOnboardingSummary =
        CoachAdminPartnerOnboardingSummary.fromJson(
            partners['onboarding_summary']);
    if (liveOpsSummary == null ||
        departures == null ||
        supportSummary == null ||
        refundQueue == null ||
        changeQueue == null ||
        financeSummary == null ||
        reconciliation == null ||
        settlementStatements == null ||
        payoutRuns == null ||
        feedHealth == null) {
      return null;
    }
    return CoachAdminOverviewResponse(
      generatedAtIso: generatedAtIso,
      liveOpsSummary: liveOpsSummary,
      departures: departures,
      disruptionSummary: disruptionSummary,
      supportSummary: supportSummary,
      refundQueue: refundQueue,
      changeQueue: changeQueue,
      financeSummary: financeSummary,
      reconciliation: reconciliation,
      settlementStatements: settlementStatements,
      payoutRuns: payoutRuns,
      feedHealth: feedHealth,
      partnerOnboardingSummary: partnerOnboardingSummary,
    );
  }
}

class CoachAdminFinanceJournalSummary {
  final String currency;
  final int totalEntries;
  final int attentionEntries;
  final int accrualEntries;
  final int adjustmentEntries;
  final int payoutEntries;
  final int pspClearingMinorUnits;
  final int operatorPayableMinorUnits;
  final int platformRevenueMinorUnits;
  final int chargebackReserveMinorUnits;
  final int travelCreditLiabilityMinorUnits;
  final int cashRefundPayableMinorUnits;
  final int customerReceivableMinorUnits;
  final int settlementInTransitMinorUnits;

  const CoachAdminFinanceJournalSummary({
    required this.currency,
    required this.totalEntries,
    required this.attentionEntries,
    required this.accrualEntries,
    required this.adjustmentEntries,
    required this.payoutEntries,
    required this.pspClearingMinorUnits,
    required this.operatorPayableMinorUnits,
    required this.platformRevenueMinorUnits,
    required this.chargebackReserveMinorUnits,
    required this.travelCreditLiabilityMinorUnits,
    required this.cashRefundPayableMinorUnits,
    required this.customerReceivableMinorUnits,
    required this.settlementInTransitMinorUnits,
  });

  static CoachAdminFinanceJournalSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final totalEntries = raw['total_entries'];
    final attentionEntries = raw['attention_entries'];
    final accrualEntries = raw['accrual_entries'];
    final adjustmentEntries = raw['adjustment_entries'];
    final payoutEntries = raw['payout_entries'];
    final pspClearingMinorUnits = raw['psp_clearing_minor_units'];
    final operatorPayableMinorUnits = raw['operator_payable_minor_units'];
    final platformRevenueMinorUnits = raw['platform_revenue_minor_units'];
    final chargebackReserveMinorUnits = raw['chargeback_reserve_minor_units'];
    final travelCreditLiabilityMinorUnits =
        raw['travel_credit_liability_minor_units'];
    final cashRefundPayableMinorUnits = raw['cash_refund_payable_minor_units'];
    final customerReceivableMinorUnits = raw['customer_receivable_minor_units'];
    final settlementInTransitMinorUnits =
        raw['settlement_in_transit_minor_units'];
    if (!_isCoachCurrency(currency) ||
        totalEntries is! int ||
        attentionEntries is! int ||
        accrualEntries is! int ||
        adjustmentEntries is! int ||
        payoutEntries is! int ||
        pspClearingMinorUnits is! int ||
        operatorPayableMinorUnits is! int ||
        platformRevenueMinorUnits is! int ||
        chargebackReserveMinorUnits is! int ||
        travelCreditLiabilityMinorUnits is! int ||
        cashRefundPayableMinorUnits is! int ||
        customerReceivableMinorUnits is! int ||
        settlementInTransitMinorUnits is! int) {
      return null;
    }
    return CoachAdminFinanceJournalSummary(
      currency: currency,
      totalEntries: totalEntries,
      attentionEntries: attentionEntries,
      accrualEntries: accrualEntries,
      adjustmentEntries: adjustmentEntries,
      payoutEntries: payoutEntries,
      pspClearingMinorUnits: pspClearingMinorUnits,
      operatorPayableMinorUnits: operatorPayableMinorUnits,
      platformRevenueMinorUnits: platformRevenueMinorUnits,
      chargebackReserveMinorUnits: chargebackReserveMinorUnits,
      travelCreditLiabilityMinorUnits: travelCreditLiabilityMinorUnits,
      cashRefundPayableMinorUnits: cashRefundPayableMinorUnits,
      customerReceivableMinorUnits: customerReceivableMinorUnits,
      settlementInTransitMinorUnits: settlementInTransitMinorUnits,
    );
  }
}

class CoachAdminFinanceAccountMovement {
  final String accountCode;
  final String accountLabel;
  final String direction;
  final int amountMinorUnits;
  final int signedMinorUnits;

  const CoachAdminFinanceAccountMovement({
    required this.accountCode,
    required this.accountLabel,
    required this.direction,
    required this.amountMinorUnits,
    required this.signedMinorUnits,
  });

  static CoachAdminFinanceAccountMovement? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final accountCode = (raw['account_code'] ?? '').toString().trim();
    final accountLabel = (raw['account_label'] ?? '').toString().trim();
    final direction = (raw['direction'] ?? '').toString().trim();
    final amountMinorUnits = raw['amount_minor_units'];
    final signedMinorUnits = raw['signed_minor_units'];
    if (accountCode.isEmpty ||
        accountLabel.isEmpty ||
        direction.isEmpty ||
        amountMinorUnits is! int ||
        signedMinorUnits is! int) {
      return null;
    }
    return CoachAdminFinanceAccountMovement(
      accountCode: accountCode,
      accountLabel: accountLabel,
      direction: direction,
      amountMinorUnits: amountMinorUnits,
      signedMinorUnits: signedMinorUnits,
    );
  }
}

class CoachAdminFinanceJournalEntry {
  final String entryId;
  final String occurredAtIso;
  final String eventType;
  final String title;
  final String status;
  final String? operatorId;
  final String? operatorName;
  final String? bookingId;
  final String? statementId;
  final String? payoutRunId;
  final String? requestId;
  final String? importId;
  final String? referenceLabel;
  final String currency;
  final int primaryAmountMinorUnits;
  final bool needsAttention;
  final String? nextAction;
  final List<String> detailLines;
  final List<CoachAdminFinanceAccountMovement> accountMovements;

  const CoachAdminFinanceJournalEntry({
    required this.entryId,
    required this.occurredAtIso,
    required this.eventType,
    required this.title,
    required this.status,
    required this.operatorId,
    required this.operatorName,
    required this.bookingId,
    required this.statementId,
    required this.payoutRunId,
    required this.requestId,
    required this.importId,
    required this.referenceLabel,
    required this.currency,
    required this.primaryAmountMinorUnits,
    required this.needsAttention,
    required this.nextAction,
    required this.detailLines,
    required this.accountMovements,
  });

  static CoachAdminFinanceJournalEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final entryId = (raw['entry_id'] ?? '').toString().trim();
    final occurredAtIso = (raw['occurred_at'] ?? '').toString().trim();
    final eventType = (raw['event_type'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final statementId = (raw['statement_id'] ?? '').toString().trim();
    final payoutRunId = (raw['payout_run_id'] ?? '').toString().trim();
    final requestId = (raw['request_id'] ?? '').toString().trim();
    final importId = (raw['import_id'] ?? '').toString().trim();
    final referenceLabel = (raw['reference_label'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final primaryAmountMinorUnits = raw['primary_amount_minor_units'];
    final needsAttention = raw['needs_attention'];
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    final detailLines = _coachStringList(raw['detail_lines']);
    final accountMovementsRaw = raw['account_movements'];
    if (entryId.isEmpty ||
        occurredAtIso.isEmpty ||
        eventType.isEmpty ||
        title.isEmpty ||
        status.isEmpty ||
        !_isCoachCurrency(currency) ||
        primaryAmountMinorUnits is! int ||
        needsAttention is! bool ||
        accountMovementsRaw is! List) {
      return null;
    }
    return CoachAdminFinanceJournalEntry(
      entryId: entryId,
      occurredAtIso: occurredAtIso,
      eventType: eventType,
      title: title,
      status: status,
      operatorId: operatorId.isEmpty ? null : operatorId,
      operatorName: operatorName.isEmpty ? null : operatorName,
      bookingId: bookingId.isEmpty ? null : bookingId,
      statementId: statementId.isEmpty ? null : statementId,
      payoutRunId: payoutRunId.isEmpty ? null : payoutRunId,
      requestId: requestId.isEmpty ? null : requestId,
      importId: importId.isEmpty ? null : importId,
      referenceLabel: referenceLabel.isEmpty ? null : referenceLabel,
      currency: currency,
      primaryAmountMinorUnits: primaryAmountMinorUnits,
      needsAttention: needsAttention,
      nextAction: nextAction.isEmpty ? null : nextAction,
      detailLines: detailLines,
      accountMovements: accountMovementsRaw
          .map(CoachAdminFinanceAccountMovement.fromJson)
          .whereType<CoachAdminFinanceAccountMovement>()
          .toList(growable: false),
    );
  }
}

class CoachAdminFinanceJournalResponse {
  final String generatedAtIso;
  final CoachAdminFinanceJournalSummary summary;
  final List<CoachAdminFinanceJournalEntry> entries;

  const CoachAdminFinanceJournalResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.entries,
  });

  static CoachAdminFinanceJournalResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachAdminFinanceJournalSummary.fromJson(raw['summary']);
    final entriesRaw = raw['entries'];
    if (generatedAtIso.isEmpty || summary == null || entriesRaw is! List) {
      return null;
    }
    return CoachAdminFinanceJournalResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      entries: entriesRaw
          .map(CoachAdminFinanceJournalEntry.fromJson)
          .whereType<CoachAdminFinanceJournalEntry>()
          .toList(growable: false),
    );
  }
}

class CoachAdminShamellPayReconciliationSummary {
  final String currency;
  final int totalRuns;
  final int reconciledRuns;
  final int awaitingShamellPayRuns;
  final int operatorRailPendingRuns;
  final int failedRuns;
  final int statusMismatchRuns;
  final int escalatedRuns;
  final int attentionRuns;
  final int expectedNetPayableMinorUnits;
  final int reconciledNetPayableMinorUnits;
  final int attentionNetPayableMinorUnits;
  final int shamellPayClearingMinorUnits;
  final int settlementInTransitMinorUnits;

  const CoachAdminShamellPayReconciliationSummary({
    required this.currency,
    required this.totalRuns,
    required this.reconciledRuns,
    required this.awaitingShamellPayRuns,
    required this.operatorRailPendingRuns,
    required this.failedRuns,
    required this.statusMismatchRuns,
    required this.escalatedRuns,
    required this.attentionRuns,
    required this.expectedNetPayableMinorUnits,
    required this.reconciledNetPayableMinorUnits,
    required this.attentionNetPayableMinorUnits,
    required this.shamellPayClearingMinorUnits,
    required this.settlementInTransitMinorUnits,
  });

  static CoachAdminShamellPayReconciliationSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final totalRuns = raw['total_runs'];
    final reconciledRuns = raw['reconciled_runs'];
    final awaitingShamellPayRuns = raw['awaiting_shamell_pay_runs'];
    final operatorRailPendingRuns = raw['operator_rail_pending_runs'];
    final failedRuns = raw['failed_runs'];
    final statusMismatchRuns = raw['status_mismatch_runs'];
    final escalatedRuns = raw['escalated_runs'];
    final attentionRuns = raw['attention_runs'];
    final expectedNetPayableMinorUnits =
        raw['expected_net_payable_minor_units'];
    final reconciledNetPayableMinorUnits =
        raw['reconciled_net_payable_minor_units'];
    final attentionNetPayableMinorUnits =
        raw['attention_net_payable_minor_units'];
    final shamellPayClearingMinorUnits =
        raw['shamell_pay_clearing_minor_units'];
    final settlementInTransitMinorUnits =
        raw['settlement_in_transit_minor_units'];
    if (!_isCoachCurrency(currency) ||
        totalRuns is! int ||
        reconciledRuns is! int ||
        awaitingShamellPayRuns is! int ||
        operatorRailPendingRuns is! int ||
        failedRuns is! int ||
        statusMismatchRuns is! int ||
        (escalatedRuns != null && escalatedRuns is! int) ||
        attentionRuns is! int ||
        expectedNetPayableMinorUnits is! int ||
        reconciledNetPayableMinorUnits is! int ||
        attentionNetPayableMinorUnits is! int ||
        shamellPayClearingMinorUnits is! int ||
        settlementInTransitMinorUnits is! int) {
      return null;
    }
    return CoachAdminShamellPayReconciliationSummary(
      currency: currency,
      totalRuns: totalRuns,
      reconciledRuns: reconciledRuns,
      awaitingShamellPayRuns: awaitingShamellPayRuns,
      operatorRailPendingRuns: operatorRailPendingRuns,
      failedRuns: failedRuns,
      statusMismatchRuns: statusMismatchRuns,
      escalatedRuns: escalatedRuns is int ? escalatedRuns : 0,
      attentionRuns: attentionRuns,
      expectedNetPayableMinorUnits: expectedNetPayableMinorUnits,
      reconciledNetPayableMinorUnits: reconciledNetPayableMinorUnits,
      attentionNetPayableMinorUnits: attentionNetPayableMinorUnits,
      shamellPayClearingMinorUnits: shamellPayClearingMinorUnits,
      settlementInTransitMinorUnits: settlementInTransitMinorUnits,
    );
  }
}

class CoachAdminShamellPayReconciliationRun {
  final String entryId;
  final String occurredAtIso;
  final String payoutRunId;
  final List<String> statementIds;
  final List<String> operatorIds;
  final List<String> operatorNames;
  final String currency;
  final String runStatus;
  final String shamellPayStatus;
  final String downstreamStatus;
  final String reconciliationStatus;
  final String? latestShamellPayImportId;
  final String? latestDownstreamImportId;
  final String? paymentReference;
  final String? externalReference;
  final List<CoachOperatorPayoutImport> shamellPayAttempts;
  final List<CoachOperatorPayoutImport> downstreamAttempts;
  final int downstreamAttemptCount;
  final int downstreamFailedAttemptCount;
  final bool escalated;
  final String? escalationSeverity;
  final String? escalationReason;
  final int expectedNetPayableMinorUnits;
  final bool needsAttention;
  final String nextAction;
  final List<String> detailLines;

  const CoachAdminShamellPayReconciliationRun({
    required this.entryId,
    required this.occurredAtIso,
    required this.payoutRunId,
    required this.statementIds,
    required this.operatorIds,
    required this.operatorNames,
    required this.currency,
    required this.runStatus,
    required this.shamellPayStatus,
    required this.downstreamStatus,
    required this.reconciliationStatus,
    required this.latestShamellPayImportId,
    required this.latestDownstreamImportId,
    required this.paymentReference,
    required this.externalReference,
    required this.shamellPayAttempts,
    required this.downstreamAttempts,
    required this.downstreamAttemptCount,
    required this.downstreamFailedAttemptCount,
    required this.escalated,
    required this.escalationSeverity,
    required this.escalationReason,
    required this.expectedNetPayableMinorUnits,
    required this.needsAttention,
    required this.nextAction,
    required this.detailLines,
  });

  static CoachAdminShamellPayReconciliationRun? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final entryId = (raw['entry_id'] ?? '').toString().trim();
    final occurredAtIso = (raw['occurred_at'] ?? '').toString().trim();
    final payoutRunId = (raw['payout_run_id'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final runStatus = (raw['run_status'] ?? '').toString().trim();
    final shamellPayStatus =
        (raw['shamell_pay_status'] ?? '').toString().trim();
    final downstreamStatus = (raw['downstream_status'] ?? '').toString().trim();
    final reconciliationStatus =
        (raw['reconciliation_status'] ?? '').toString().trim();
    final latestShamellPayImportId =
        (raw['latest_shamell_pay_import_id'] ?? '').toString().trim();
    final latestDownstreamImportId =
        (raw['latest_downstream_import_id'] ?? '').toString().trim();
    final paymentReference = (raw['payment_reference'] ?? '').toString().trim();
    final externalReference =
        (raw['external_reference'] ?? '').toString().trim();
    final expectedNetPayableMinorUnits =
        raw['expected_net_payable_minor_units'];
    final needsAttention = raw['needs_attention'];
    final downstreamAttemptCount = raw['downstream_attempt_count'];
    final downstreamFailedAttemptCount = raw['downstream_failed_attempt_count'];
    final escalated = raw['escalated'];
    final escalationSeverity =
        (raw['escalation_severity'] ?? '').toString().trim();
    final escalationReason = (raw['escalation_reason'] ?? '').toString().trim();
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (entryId.isEmpty ||
        occurredAtIso.isEmpty ||
        payoutRunId.isEmpty ||
        !_isCoachCurrency(currency) ||
        runStatus.isEmpty ||
        shamellPayStatus.isEmpty ||
        downstreamStatus.isEmpty ||
        reconciliationStatus.isEmpty ||
        expectedNetPayableMinorUnits is! int ||
        needsAttention is! bool ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachAdminShamellPayReconciliationRun(
      shamellPayAttempts: (raw['shamell_pay_attempts'] as List? ?? const [])
          .map(CoachOperatorPayoutImport.fromJson)
          .whereType<CoachOperatorPayoutImport>()
          .toList(growable: false),
      downstreamAttempts: (raw['downstream_attempts'] as List? ?? const [])
          .map(CoachOperatorPayoutImport.fromJson)
          .whereType<CoachOperatorPayoutImport>()
          .toList(growable: false),
      entryId: entryId,
      occurredAtIso: occurredAtIso,
      payoutRunId: payoutRunId,
      statementIds: _coachStringList(raw['statement_ids']),
      operatorIds: _coachStringList(raw['operator_ids']),
      operatorNames: _coachStringList(raw['operator_names']),
      currency: currency,
      runStatus: runStatus,
      shamellPayStatus: shamellPayStatus,
      downstreamStatus: downstreamStatus,
      reconciliationStatus: reconciliationStatus,
      latestShamellPayImportId:
          latestShamellPayImportId.isEmpty ? null : latestShamellPayImportId,
      latestDownstreamImportId:
          latestDownstreamImportId.isEmpty ? null : latestDownstreamImportId,
      paymentReference: paymentReference.isEmpty ? null : paymentReference,
      externalReference: externalReference.isEmpty ? null : externalReference,
      downstreamAttemptCount: downstreamAttemptCount is int
          ? downstreamAttemptCount
          : (raw['downstream_attempts'] as List? ?? const []).length,
      downstreamFailedAttemptCount: downstreamFailedAttemptCount is int
          ? downstreamFailedAttemptCount
          : (raw['downstream_attempts'] as List? ?? const [])
              .whereType<Map>()
              .where((payload) =>
                  (payload['external_status'] ?? '').toString().trim() ==
                  'failed')
              .length,
      escalated: escalated is bool ? escalated : false,
      escalationSeverity:
          escalationSeverity.isEmpty ? null : escalationSeverity,
      escalationReason: escalationReason.isEmpty ? null : escalationReason,
      expectedNetPayableMinorUnits: expectedNetPayableMinorUnits,
      needsAttention: needsAttention,
      nextAction: nextAction,
      detailLines: _coachStringList(raw['detail_lines']),
    );
  }
}

class CoachAdminShamellPayReconciliationResponse {
  final String generatedAtIso;
  final CoachAdminShamellPayReconciliationSummary summary;
  final List<CoachAdminShamellPayReconciliationRun> runs;

  const CoachAdminShamellPayReconciliationResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.runs,
  });

  static CoachAdminShamellPayReconciliationResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary =
        CoachAdminShamellPayReconciliationSummary.fromJson(raw['summary']);
    final runsRaw = raw['runs'];
    if (generatedAtIso.isEmpty || summary == null || runsRaw is! List) {
      return null;
    }
    return CoachAdminShamellPayReconciliationResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      runs: runsRaw
          .map(CoachAdminShamellPayReconciliationRun.fromJson)
          .whereType<CoachAdminShamellPayReconciliationRun>()
          .toList(growable: false),
    );
  }
}

class CoachAdminRiskSummary {
  final int openRisks;
  final int activeRisks;
  final int acknowledgedRisks;
  final int snoozedRisks;
  final int ownedRisks;
  final int criticalRisks;
  final int overdueRisks;
  final int dueSoonRisks;
  final int financeAlerts;
  final int supportAlerts;
  final int partnerAlerts;
  final int boardingAlerts;

  const CoachAdminRiskSummary({
    required this.openRisks,
    required this.activeRisks,
    required this.acknowledgedRisks,
    required this.snoozedRisks,
    required this.ownedRisks,
    required this.criticalRisks,
    this.overdueRisks = 0,
    this.dueSoonRisks = 0,
    required this.financeAlerts,
    required this.supportAlerts,
    required this.partnerAlerts,
    required this.boardingAlerts,
  });

  static CoachAdminRiskSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final openRisks = raw['open_risks'];
    final activeRisks = raw['active_risks'];
    final acknowledgedRisks = raw['acknowledged_risks'];
    final snoozedRisks = raw['snoozed_risks'];
    final ownedRisks = raw['owned_risks'];
    final criticalRisks = raw['critical_risks'];
    final overdueRisks = raw['overdue_risks'];
    final dueSoonRisks = raw['due_soon_risks'];
    final financeAlerts = raw['finance_alerts'];
    final supportAlerts = raw['support_alerts'];
    final partnerAlerts = raw['partner_alerts'];
    final boardingAlerts = raw['boarding_alerts'];
    if (openRisks is! int ||
        activeRisks is! int ||
        acknowledgedRisks is! int ||
        snoozedRisks is! int ||
        ownedRisks is! int ||
        criticalRisks is! int ||
        (overdueRisks != null && overdueRisks is! int) ||
        (dueSoonRisks != null && dueSoonRisks is! int) ||
        financeAlerts is! int ||
        supportAlerts is! int ||
        partnerAlerts is! int ||
        boardingAlerts is! int) {
      return null;
    }
    return CoachAdminRiskSummary(
      openRisks: openRisks,
      activeRisks: activeRisks,
      acknowledgedRisks: acknowledgedRisks,
      snoozedRisks: snoozedRisks,
      ownedRisks: ownedRisks,
      criticalRisks: criticalRisks,
      overdueRisks: overdueRisks is int ? overdueRisks : 0,
      dueSoonRisks: dueSoonRisks is int ? dueSoonRisks : 0,
      financeAlerts: financeAlerts,
      supportAlerts: supportAlerts,
      partnerAlerts: partnerAlerts,
      boardingAlerts: boardingAlerts,
    );
  }
}

class CoachAdminRiskItem {
  final String riskId;
  final String category;
  final String severity;
  final String title;
  final String status;
  final String detectedAtIso;
  final String? operatorId;
  final String? operatorName;
  final String? bookingId;
  final String? statementId;
  final String? payoutRunId;
  final String? tripId;
  final String? referenceLabel;
  final String? currency;
  final int? amountMinorUnits;
  final String? nextAction;
  final String workflowStatus;
  final String? ownerAccountId;
  final String? ownerTeam;
  final String? suggestedTeam;
  final String? routingSource;
  final String? routingReason;
  final String? slaDueAtIso;
  final String slaStatus;
  final String? followUpTaskCode;
  final String? followUpTaskLabel;
  final String? followUpTaskDetail;
  final String? autoCaseKind;
  final String? autoCaseId;
  final String? autoCaseStatus;
  final String? autoCaseLabel;
  final String? snoozedUntilIso;
  final String? snoozeReason;
  final String? workflowUpdatedAtIso;
  final String? workflowUpdatedByAccountId;
  final String? workflowNote;
  final List<String> detailLines;

  const CoachAdminRiskItem({
    required this.riskId,
    required this.category,
    required this.severity,
    required this.title,
    required this.status,
    required this.detectedAtIso,
    required this.operatorId,
    required this.operatorName,
    required this.bookingId,
    required this.statementId,
    required this.payoutRunId,
    required this.tripId,
    required this.referenceLabel,
    required this.currency,
    required this.amountMinorUnits,
    required this.nextAction,
    required this.workflowStatus,
    required this.ownerAccountId,
    required this.ownerTeam,
    required this.suggestedTeam,
    required this.routingSource,
    required this.routingReason,
    this.slaDueAtIso,
    this.slaStatus = 'on_track',
    this.followUpTaskCode,
    this.followUpTaskLabel,
    this.followUpTaskDetail,
    this.autoCaseKind,
    this.autoCaseId,
    this.autoCaseStatus,
    this.autoCaseLabel,
    required this.snoozedUntilIso,
    required this.snoozeReason,
    required this.workflowUpdatedAtIso,
    required this.workflowUpdatedByAccountId,
    required this.workflowNote,
    required this.detailLines,
  });

  static CoachAdminRiskItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final riskId = (raw['risk_id'] ?? '').toString().trim();
    final category = (raw['category'] ?? '').toString().trim();
    final severity = (raw['severity'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim();
    final detectedAtIso = (raw['detected_at'] ?? '').toString().trim();
    final operatorId = (raw['operator_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final statementId = (raw['statement_id'] ?? '').toString().trim();
    final payoutRunId = (raw['payout_run_id'] ?? '').toString().trim();
    final tripId = (raw['trip_id'] ?? '').toString().trim();
    final referenceLabel = (raw['reference_label'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final amountMinorUnits = raw['amount_minor_units'];
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    final workflowStatus =
        (raw['workflow_status'] ?? 'active').toString().trim();
    final ownerAccountId = (raw['owner_account_id'] ?? '').toString().trim();
    final ownerTeam = (raw['owner_team'] ?? '').toString().trim();
    final suggestedTeam = (raw['suggested_team'] ?? '').toString().trim();
    final routingSource = (raw['routing_source'] ?? '').toString().trim();
    final routingReason = (raw['routing_reason'] ?? '').toString().trim();
    final slaDueAtIso = (raw['sla_due_at'] ?? '').toString().trim();
    final slaStatus = (raw['sla_status'] ?? 'on_track').toString().trim();
    final followUpTaskCode =
        (raw['follow_up_task_code'] ?? '').toString().trim();
    final followUpTaskLabel =
        (raw['follow_up_task_label'] ?? '').toString().trim();
    final followUpTaskDetail =
        (raw['follow_up_task_detail'] ?? '').toString().trim();
    final autoCaseKind = (raw['auto_case_kind'] ?? '').toString().trim();
    final autoCaseId = (raw['auto_case_id'] ?? '').toString().trim();
    final autoCaseStatus = (raw['auto_case_status'] ?? '').toString().trim();
    final autoCaseLabel = (raw['auto_case_label'] ?? '').toString().trim();
    final snoozedUntilIso = (raw['snoozed_until'] ?? '').toString().trim();
    final snoozeReason = (raw['snooze_reason'] ?? '').toString().trim();
    final workflowUpdatedAtIso =
        (raw['workflow_updated_at'] ?? '').toString().trim();
    final workflowUpdatedByAccountId =
        (raw['workflow_updated_by_account_id'] ?? '').toString().trim();
    final workflowNote = (raw['workflow_note'] ?? '').toString().trim();
    final detailLines = _coachStringList(raw['detail_lines']);
    if (riskId.isEmpty ||
        category.isEmpty ||
        severity.isEmpty ||
        title.isEmpty ||
        status.isEmpty ||
        detectedAtIso.isEmpty ||
        workflowStatus.isEmpty) {
      return null;
    }
    return CoachAdminRiskItem(
      riskId: riskId,
      category: category,
      severity: severity,
      title: title,
      status: status,
      detectedAtIso: detectedAtIso,
      operatorId: operatorId.isEmpty ? null : operatorId,
      operatorName: operatorName.isEmpty ? null : operatorName,
      bookingId: bookingId.isEmpty ? null : bookingId,
      statementId: statementId.isEmpty ? null : statementId,
      payoutRunId: payoutRunId.isEmpty ? null : payoutRunId,
      tripId: tripId.isEmpty ? null : tripId,
      referenceLabel: referenceLabel.isEmpty ? null : referenceLabel,
      currency: _isCoachCurrency(currency) ? currency : null,
      amountMinorUnits: amountMinorUnits is int ? amountMinorUnits : null,
      nextAction: nextAction.isEmpty ? null : nextAction,
      workflowStatus: workflowStatus,
      ownerAccountId: ownerAccountId.isEmpty ? null : ownerAccountId,
      ownerTeam: ownerTeam.isEmpty ? null : ownerTeam,
      suggestedTeam: suggestedTeam.isEmpty ? null : suggestedTeam,
      routingSource: routingSource.isEmpty ? null : routingSource,
      routingReason: routingReason.isEmpty ? null : routingReason,
      slaDueAtIso: slaDueAtIso.isEmpty ? null : slaDueAtIso,
      slaStatus: slaStatus.isEmpty ? 'on_track' : slaStatus,
      followUpTaskCode: followUpTaskCode.isEmpty ? null : followUpTaskCode,
      followUpTaskLabel: followUpTaskLabel.isEmpty ? null : followUpTaskLabel,
      followUpTaskDetail:
          followUpTaskDetail.isEmpty ? null : followUpTaskDetail,
      autoCaseKind: autoCaseKind.isEmpty ? null : autoCaseKind,
      autoCaseId: autoCaseId.isEmpty ? null : autoCaseId,
      autoCaseStatus: autoCaseStatus.isEmpty ? null : autoCaseStatus,
      autoCaseLabel: autoCaseLabel.isEmpty ? null : autoCaseLabel,
      snoozedUntilIso: snoozedUntilIso.isEmpty ? null : snoozedUntilIso,
      snoozeReason: snoozeReason.isEmpty ? null : snoozeReason,
      workflowUpdatedAtIso:
          workflowUpdatedAtIso.isEmpty ? null : workflowUpdatedAtIso,
      workflowUpdatedByAccountId: workflowUpdatedByAccountId.isEmpty
          ? null
          : workflowUpdatedByAccountId,
      workflowNote: workflowNote.isEmpty ? null : workflowNote,
      detailLines: detailLines,
    );
  }
}

class CoachAdminRiskDashboardResponse {
  final String generatedAtIso;
  final CoachAdminRiskSummary summary;
  final List<CoachAdminRiskItem> risks;

  const CoachAdminRiskDashboardResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.risks,
  });

  static CoachAdminRiskDashboardResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachAdminRiskSummary.fromJson(raw['summary']);
    final risksRaw = raw['risks'];
    if (generatedAtIso.isEmpty || summary == null || risksRaw is! List) {
      return null;
    }
    return CoachAdminRiskDashboardResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      risks: risksRaw
          .map(CoachAdminRiskItem.fromJson)
          .whereType<CoachAdminRiskItem>()
          .toList(growable: false),
    );
  }
}

class CoachAdminRiskMutationResult {
  final String riskId;
  final String action;
  final String updatedAtIso;
  final CoachAdminRiskItem risk;

  const CoachAdminRiskMutationResult({
    required this.riskId,
    required this.action,
    required this.updatedAtIso,
    required this.risk,
  });

  static CoachAdminRiskMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final riskId = (raw['risk_id'] ?? '').toString().trim();
    final action = (raw['action'] ?? '').toString().trim();
    final updatedAtIso = (raw['updated_at'] ?? '').toString().trim();
    final risk = CoachAdminRiskItem.fromJson(raw['risk']);
    if (riskId.isEmpty ||
        action.isEmpty ||
        updatedAtIso.isEmpty ||
        risk == null) {
      return null;
    }
    return CoachAdminRiskMutationResult(
      riskId: riskId,
      action: action,
      updatedAtIso: updatedAtIso,
      risk: risk,
    );
  }
}

class CoachAdminSupportCasesSummary {
  final int totalCases;
  final int urgentCases;
  final int refundCases;
  final int changeCases;
  final int attentionCases;
  final int boardedCases;

  const CoachAdminSupportCasesSummary({
    required this.totalCases,
    required this.urgentCases,
    required this.refundCases,
    required this.changeCases,
    required this.attentionCases,
    required this.boardedCases,
  });

  static CoachAdminSupportCasesSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final totalCases = raw['total_cases'];
    final urgentCases = raw['urgent_cases'];
    final refundCases = raw['refund_cases'];
    final changeCases = raw['change_cases'];
    final attentionCases = raw['attention_cases'];
    final boardedCases = raw['boarded_cases'];
    if (totalCases is! int ||
        urgentCases is! int ||
        refundCases is! int ||
        changeCases is! int ||
        attentionCases is! int ||
        boardedCases is! int) {
      return null;
    }
    return CoachAdminSupportCasesSummary(
      totalCases: totalCases,
      urgentCases: urgentCases,
      refundCases: refundCases,
      changeCases: changeCases,
      attentionCases: attentionCases,
      boardedCases: boardedCases,
    );
  }
}

class CoachAdminSupportCaseSummaryRecord {
  final String caseId;
  final String bookingId;
  final String journeyId;
  final String operatorName;
  final String from;
  final String to;
  final String departureAtIso;
  final String arrivalAtIso;
  final String bookingState;
  final String caseStatus;
  final String priority;
  final String passengerDisplayName;
  final int passengerCount;
  final String? contactEmail;
  final String? operatorBookingReference;
  final String? paymentAuthorizationReference;
  final List<String> ticketIds;
  final List<String> operatorTicketReferences;
  final List<String> openRequestKinds;
  final bool needsAttention;
  final String latestActivityAtIso;

  const CoachAdminSupportCaseSummaryRecord({
    required this.caseId,
    required this.bookingId,
    required this.journeyId,
    required this.operatorName,
    required this.from,
    required this.to,
    required this.departureAtIso,
    required this.arrivalAtIso,
    required this.bookingState,
    required this.caseStatus,
    required this.priority,
    required this.passengerDisplayName,
    required this.passengerCount,
    required this.contactEmail,
    required this.operatorBookingReference,
    required this.paymentAuthorizationReference,
    required this.ticketIds,
    required this.operatorTicketReferences,
    required this.openRequestKinds,
    required this.needsAttention,
    required this.latestActivityAtIso,
  });

  static CoachAdminSupportCaseSummaryRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final caseId = (raw['case_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final from = (raw['from'] ?? '').toString().trim();
    final to = (raw['to'] ?? '').toString().trim();
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final arrivalAtIso = (raw['arrival_at'] ?? '').toString().trim();
    final bookingState = (raw['booking_state'] ?? '').toString().trim();
    final caseStatus = (raw['case_status'] ?? '').toString().trim();
    final priority = (raw['priority'] ?? '').toString().trim();
    final passengerDisplayName =
        (raw['passenger_display_name'] ?? '').toString().trim();
    final passengerCount = raw['passenger_count'];
    final contactEmail = (raw['contact_email'] ?? '').toString().trim();
    final operatorBookingReference =
        (raw['operator_booking_reference'] ?? '').toString().trim();
    final paymentAuthorizationReference =
        (raw['payment_authorization_reference'] ?? '').toString().trim();
    final ticketIds = _coachStringList(raw['ticket_ids']);
    final operatorTicketReferences =
        _coachStringList(raw['operator_ticket_references']);
    final openRequestKinds = _coachStringList(raw['open_request_kinds']);
    final needsAttention = raw['needs_attention'];
    final latestActivityAtIso =
        (raw['latest_activity_at'] ?? '').toString().trim();
    if (caseId.isEmpty ||
        bookingId.isEmpty ||
        journeyId.isEmpty ||
        operatorName.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        departureAtIso.isEmpty ||
        arrivalAtIso.isEmpty ||
        bookingState.isEmpty ||
        caseStatus.isEmpty ||
        priority.isEmpty ||
        passengerDisplayName.isEmpty ||
        passengerCount is! int ||
        passengerCount <= 0 ||
        needsAttention is! bool ||
        latestActivityAtIso.isEmpty) {
      return null;
    }
    return CoachAdminSupportCaseSummaryRecord(
      caseId: caseId,
      bookingId: bookingId,
      journeyId: journeyId,
      operatorName: operatorName,
      from: from,
      to: to,
      departureAtIso: departureAtIso,
      arrivalAtIso: arrivalAtIso,
      bookingState: bookingState,
      caseStatus: caseStatus,
      priority: priority,
      passengerDisplayName: passengerDisplayName,
      passengerCount: passengerCount,
      contactEmail: contactEmail.isEmpty ? null : contactEmail,
      operatorBookingReference:
          operatorBookingReference.isEmpty ? null : operatorBookingReference,
      paymentAuthorizationReference: paymentAuthorizationReference.isEmpty
          ? null
          : paymentAuthorizationReference,
      ticketIds: ticketIds,
      operatorTicketReferences: operatorTicketReferences,
      openRequestKinds: openRequestKinds,
      needsAttention: needsAttention,
      latestActivityAtIso: latestActivityAtIso,
    );
  }
}

class CoachAdminSupportCasesResponse {
  final String generatedAtIso;
  final CoachAdminSupportCasesSummary summary;
  final List<CoachAdminSupportCaseSummaryRecord> cases;

  const CoachAdminSupportCasesResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.cases,
  });

  static CoachAdminSupportCasesResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final summary = CoachAdminSupportCasesSummary.fromJson(raw['summary']);
    final casesRaw = raw['cases'];
    if (generatedAtIso.isEmpty || summary == null || casesRaw is! List) {
      return null;
    }
    return CoachAdminSupportCasesResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      cases: casesRaw
          .map(CoachAdminSupportCaseSummaryRecord.fromJson)
          .whereType<CoachAdminSupportCaseSummaryRecord>()
          .toList(growable: false),
    );
  }
}

class CoachSupportCaseTimelineEvent {
  final String eventId;
  final String eventType;
  final String title;
  final String occurredAtIso;
  final String statusLabel;
  final List<String> detailLines;

  const CoachSupportCaseTimelineEvent({
    required this.eventId,
    required this.eventType,
    required this.title,
    required this.occurredAtIso,
    required this.statusLabel,
    required this.detailLines,
  });

  static CoachSupportCaseTimelineEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final eventId = (raw['event_id'] ?? '').toString().trim();
    final eventType = (raw['event_type'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    final occurredAtIso = (raw['occurred_at'] ?? '').toString().trim();
    final statusLabel = (raw['status_label'] ?? '').toString().trim();
    final detailLines = _coachStringList(raw['detail_lines']);
    if (eventId.isEmpty ||
        eventType.isEmpty ||
        title.isEmpty ||
        occurredAtIso.isEmpty ||
        statusLabel.isEmpty) {
      return null;
    }
    return CoachSupportCaseTimelineEvent(
      eventId: eventId,
      eventType: eventType,
      title: title,
      occurredAtIso: occurredAtIso,
      statusLabel: statusLabel,
      detailLines: detailLines,
    );
  }
}

class CoachAdminSupportCaseDetailResponse {
  final String generatedAtIso;
  final CoachAdminSupportCaseSummaryRecord supportCase;
  final CoachBookedJourneySummary journey;
  final CoachOffer offer;
  final CoachHold? hold;
  final CoachBooking booking;
  final CoachPaymentAuthorization? payment;
  final CoachCompensationState? compensation;
  final List<CoachPassengerManifest> passengerManifests;
  final List<CoachTicketCoupon> tickets;
  final List<CoachTicketArtifact> ticketArtifacts;
  final CoachRefundRequestRecord? refundRequest;
  final CoachChangeRequestRecord? changeRequest;
  final List<CoachBoardingEvent> recentBoardingEvents;
  final List<CoachOperatorFeedHealth> operatorFeedHealth;
  final List<CoachSupportCaseTimelineEvent> timeline;

  const CoachAdminSupportCaseDetailResponse({
    required this.generatedAtIso,
    required this.supportCase,
    required this.journey,
    required this.offer,
    required this.hold,
    required this.booking,
    required this.payment,
    required this.compensation,
    required this.passengerManifests,
    required this.tickets,
    required this.ticketArtifacts,
    required this.refundRequest,
    required this.changeRequest,
    required this.recentBoardingEvents,
    required this.operatorFeedHealth,
    required this.timeline,
  });

  static CoachAdminSupportCaseDetailResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final supportCase =
        CoachAdminSupportCaseSummaryRecord.fromJson(raw['support_case']);
    final journey = CoachBookedJourneySummary.fromJson(raw['journey']);
    final offer = CoachOffer.fromJson(raw['offer']);
    final hold = CoachHold.fromJson(raw['hold']);
    final booking = CoachBooking.fromJson(raw['booking']);
    final payment = CoachPaymentAuthorization.fromJson(raw['payment']);
    final compensation = CoachCompensationState.fromJson(raw['compensation']);
    final passengerManifestsRaw = raw['passengers_manifest'];
    final ticketsRaw = raw['tickets'];
    final ticketArtifactsRaw = raw['ticket_artifacts'];
    final refundRequest =
        CoachRefundRequestRecord.fromJson(raw['refund_request']);
    final changeRequest =
        CoachChangeRequestRecord.fromJson(raw['change_request']);
    final recentBoardingEventsRaw = raw['recent_boarding_events'];
    final operatorFeedHealthRaw = raw['operator_feed_health'];
    final timelineRaw = raw['timeline'];
    if (generatedAtIso.isEmpty ||
        supportCase == null ||
        journey == null ||
        offer == null ||
        booking == null ||
        passengerManifestsRaw is! List ||
        ticketsRaw is! List ||
        ticketArtifactsRaw is! List ||
        recentBoardingEventsRaw is! List ||
        operatorFeedHealthRaw is! List ||
        timelineRaw is! List) {
      return null;
    }
    return CoachAdminSupportCaseDetailResponse(
      generatedAtIso: generatedAtIso,
      supportCase: supportCase,
      journey: journey,
      offer: offer,
      hold: hold,
      booking: booking,
      payment: payment,
      compensation: compensation,
      passengerManifests: passengerManifestsRaw
          .map(CoachPassengerManifest.fromJson)
          .whereType<CoachPassengerManifest>()
          .toList(growable: false),
      tickets: ticketsRaw
          .map(CoachTicketCoupon.fromJson)
          .whereType<CoachTicketCoupon>()
          .toList(growable: false),
      ticketArtifacts: ticketArtifactsRaw
          .map(CoachTicketArtifact.fromJson)
          .whereType<CoachTicketArtifact>()
          .toList(growable: false),
      refundRequest: refundRequest,
      changeRequest: changeRequest,
      recentBoardingEvents: recentBoardingEventsRaw
          .map(CoachBoardingEvent.fromJson)
          .whereType<CoachBoardingEvent>()
          .toList(growable: false),
      operatorFeedHealth: operatorFeedHealthRaw
          .map(CoachOperatorFeedHealth.fromJson)
          .whereType<CoachOperatorFeedHealth>()
          .toList(growable: false),
      timeline: timelineRaw
          .map(CoachSupportCaseTimelineEvent.fromJson)
          .whereType<CoachSupportCaseTimelineEvent>()
          .toList(growable: false),
    );
  }
}

class CoachOperatorPayoutImportPreviewsResponse {
  final String generatedAtIso;
  final CoachOperatorPayoutImportPreviewsSummary summary;
  final List<CoachOperatorPayoutImportPreview> previews;
  final String? nextCursor;

  const CoachOperatorPayoutImportPreviewsResponse({
    required this.generatedAtIso,
    required this.summary,
    required this.previews,
    this.nextCursor,
  });

  static CoachOperatorPayoutImportPreviewsResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final nextCursor = (raw['next_cursor'] ?? '').toString().trim();
    final summary =
        CoachOperatorPayoutImportPreviewsSummary.fromJson(raw['summary']);
    final previewsRaw = raw['previews'];
    if (generatedAtIso.isEmpty || summary == null || previewsRaw is! List) {
      return null;
    }
    return CoachOperatorPayoutImportPreviewsResponse(
      generatedAtIso: generatedAtIso,
      summary: summary,
      previews: previewsRaw
          .map(CoachOperatorPayoutImportPreview.fromJson)
          .whereType<CoachOperatorPayoutImportPreview>()
          .toList(growable: false),
      nextCursor: nextCursor.isEmpty ? null : nextCursor,
    );
  }
}

class CoachOperatorPayoutImportPreviewMutationResult {
  final String command;
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorPayoutImportPreview preview;
  final String nextAction;

  const CoachOperatorPayoutImportPreviewMutationResult({
    required this.command,
    required this.idempotency,
    required this.preview,
    required this.nextAction,
  });

  static CoachOperatorPayoutImportPreviewMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] ?? '').toString().trim();
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final preview = CoachOperatorPayoutImportPreview.fromJson(raw['preview']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (command.isEmpty ||
        idempotency == null ||
        preview == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportPreviewMutationResult(
      command: command,
      idempotency: idempotency,
      preview: preview,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorPayoutRunMutationResult {
  final String command;
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorPayoutRun payoutRun;
  final String nextAction;

  const CoachOperatorPayoutRunMutationResult({
    required this.command,
    required this.idempotency,
    required this.payoutRun,
    required this.nextAction,
  });

  static CoachOperatorPayoutRunMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] ?? '').toString().trim();
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final payoutRun = CoachOperatorPayoutRun.fromJson(raw['payout_run']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (command.isEmpty ||
        idempotency == null ||
        payoutRun == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutRunMutationResult(
      command: command,
      idempotency: idempotency,
      payoutRun: payoutRun,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorPayoutImportMutationResult {
  final String command;
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorPayoutImport payoutImport;
  final CoachOperatorPayoutRun payoutRun;
  final String nextAction;

  const CoachOperatorPayoutImportMutationResult({
    required this.command,
    required this.idempotency,
    required this.payoutImport,
    required this.payoutRun,
    required this.nextAction,
  });

  static CoachOperatorPayoutImportMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] ?? '').toString().trim();
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final payoutImport =
        CoachOperatorPayoutImport.fromJson(raw['payout_import']);
    final payoutRun = CoachOperatorPayoutRun.fromJson(raw['payout_run']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (command.isEmpty ||
        idempotency == null ||
        payoutImport == null ||
        payoutRun == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportMutationResult(
      command: command,
      idempotency: idempotency,
      payoutImport: payoutImport,
      payoutRun: payoutRun,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorPayoutImportBatchFailure {
  final int lineNumber;
  final String? payoutRunId;
  final String detail;

  const CoachOperatorPayoutImportBatchFailure({
    required this.lineNumber,
    required this.payoutRunId,
    required this.detail,
  });

  static CoachOperatorPayoutImportBatchFailure? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lineNumber = raw['line_number'];
    final payoutRunId = (raw['payout_run_id'] ?? '').toString().trim();
    final detail = (raw['detail'] ?? '').toString().trim();
    if (lineNumber is! int || detail.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportBatchFailure(
      lineNumber: lineNumber,
      payoutRunId: payoutRunId.isEmpty ? null : payoutRunId,
      detail: detail,
    );
  }
}

class CoachOperatorPayoutImportPreviewEcho {
  final String importSource;
  final String reportName;
  final String reportFormat;
  final String reportChecksumSha256;
  final String requestFingerprint;
  final String previewToken;
  final String previewStatus;
  final String expiresAtIso;
  final String? reworkOfBatchId;

  const CoachOperatorPayoutImportPreviewEcho({
    required this.importSource,
    required this.reportName,
    required this.reportFormat,
    required this.reportChecksumSha256,
    required this.requestFingerprint,
    required this.previewToken,
    required this.previewStatus,
    required this.expiresAtIso,
    required this.reworkOfBatchId,
  });

  bool isUsableAt(DateTime now) {
    if (previewStatus != 'active') {
      return false;
    }
    final expiresAt = DateTime.tryParse(expiresAtIso)?.toUtc();
    if (expiresAt == null) {
      return false;
    }
    return expiresAt.isAfter(now.toUtc());
  }

  static CoachOperatorPayoutImportPreviewEcho? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final importSource = (raw['import_source'] ?? '').toString().trim();
    final reportName = (raw['report_name'] ?? '').toString().trim();
    final reportFormat = (raw['report_format'] ?? '').toString().trim();
    final reportChecksumSha256 =
        (raw['report_checksum_sha256'] ?? '').toString().trim();
    final requestFingerprint =
        (raw['request_fingerprint'] ?? '').toString().trim();
    final previewToken = (raw['preview_token'] ?? '').toString().trim();
    final previewStatus = (raw['preview_status'] ?? '').toString().trim();
    final expiresAtIso = (raw['expires_at'] ?? '').toString().trim();
    final reworkOfBatchId = (raw['rework_of_batch_id'] ?? '').toString().trim();
    if (importSource.isEmpty ||
        reportName.isEmpty ||
        reportFormat.isEmpty ||
        reportChecksumSha256.isEmpty ||
        requestFingerprint.isEmpty ||
        previewToken.isEmpty ||
        previewStatus.isEmpty ||
        expiresAtIso.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportPreviewEcho(
      importSource: importSource,
      reportName: reportName,
      reportFormat: reportFormat,
      reportChecksumSha256: reportChecksumSha256,
      requestFingerprint: requestFingerprint,
      previewToken: previewToken,
      previewStatus: previewStatus,
      expiresAtIso: expiresAtIso,
      reworkOfBatchId: reworkOfBatchId.isEmpty ? null : reworkOfBatchId,
    );
  }
}

class CoachOperatorPayoutImportBatchMutationResult {
  final String command;
  final bool dryRun;
  final bool mutationApplied;
  final CoachOperatorPayoutImportPreviewEcho? previewEcho;
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorPayoutImportBatch batch;
  final List<CoachOperatorPayoutImport> imports;
  final List<CoachOperatorPayoutImportBatchFailure> failedRows;
  final String nextAction;

  const CoachOperatorPayoutImportBatchMutationResult({
    required this.command,
    required this.dryRun,
    required this.mutationApplied,
    required this.previewEcho,
    required this.idempotency,
    required this.batch,
    required this.imports,
    required this.failedRows,
    required this.nextAction,
  });

  static CoachOperatorPayoutImportBatchMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] ?? '').toString().trim();
    final dryRun = raw['dry_run'];
    final mutationApplied = raw['mutation_applied'];
    final previewEcho =
        CoachOperatorPayoutImportPreviewEcho.fromJson(raw['preview_echo']);
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final batch = CoachOperatorPayoutImportBatch.fromJson(raw['batch']);
    final importsRaw = raw['imports'];
    final failedRowsRaw = raw['failed_rows'];
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (command.isEmpty ||
        (dryRun != null && dryRun is! bool) ||
        (mutationApplied != null && mutationApplied is! bool) ||
        idempotency == null ||
        batch == null ||
        importsRaw is! List ||
        failedRowsRaw is! List ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutImportBatchMutationResult(
      command: command,
      dryRun: dryRun is bool ? dryRun : batch.dryRun,
      mutationApplied:
          mutationApplied is bool ? mutationApplied : !batch.dryRun,
      previewEcho: previewEcho,
      idempotency: idempotency,
      batch: batch,
      imports: importsRaw
          .map(CoachOperatorPayoutImport.fromJson)
          .whereType<CoachOperatorPayoutImport>()
          .toList(growable: false),
      failedRows: failedRowsRaw
          .map(CoachOperatorPayoutImportBatchFailure.fromJson)
          .whereType<CoachOperatorPayoutImportBatchFailure>()
          .toList(growable: false),
      nextAction: nextAction,
    );
  }
}

class CoachOperatorPayoutExportMutationResult {
  final String command;
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorPayoutExport export;
  final String nextAction;

  const CoachOperatorPayoutExportMutationResult({
    required this.command,
    required this.idempotency,
    required this.export,
    required this.nextAction,
  });

  static CoachOperatorPayoutExportMutationResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] ?? '').toString().trim();
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final export = CoachOperatorPayoutExport.fromJson(raw['export']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (command.isEmpty ||
        idempotency == null ||
        export == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorPayoutExportMutationResult(
      command: command,
      idempotency: idempotency,
      export: export,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorRefundReviewResult {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorRefundQueueEntry request;
  final CoachOperatorSettlementEffect? settlementEffect;
  final String nextAction;

  const CoachOperatorRefundReviewResult({
    required this.idempotency,
    required this.request,
    required this.settlementEffect,
    required this.nextAction,
  });

  static CoachOperatorRefundReviewResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final request = CoachOperatorRefundQueueEntry.fromJson(raw['request']);
    final settlementEffect =
        CoachOperatorSettlementEffect.fromJson(raw['settlement_effect']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (idempotency == null || request == null || nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorRefundReviewResult(
      idempotency: idempotency,
      request: request,
      settlementEffect: settlementEffect,
      nextAction: nextAction,
    );
  }
}

class CoachOperatorChangeReviewResult {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOperatorChangeQueueEntry request;
  final CoachOperatorSettlementEffect? settlementEffect;
  final String nextAction;

  const CoachOperatorChangeReviewResult({
    required this.idempotency,
    required this.request,
    required this.settlementEffect,
    required this.nextAction,
  });

  static CoachOperatorChangeReviewResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final request = CoachOperatorChangeQueueEntry.fromJson(raw['request']);
    final settlementEffect =
        CoachOperatorSettlementEffect.fromJson(raw['settlement_effect']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    if (idempotency == null || request == null || nextAction.isEmpty) {
      return null;
    }
    return CoachOperatorChangeReviewResult(
      idempotency: idempotency,
      request: request,
      settlementEffect: settlementEffect,
      nextAction: nextAction,
    );
  }
}

class CoachCrewTripSummary {
  final String tripId;
  final String journeyId;
  final String bookingId;
  final String operatorName;
  final String from;
  final String to;
  final String departureAtIso;
  final String arrivalAtIso;
  final String boardingOpensAtIso;
  final String boardingClosesAtIso;
  final String gateLabel;
  final String vehicleLabel;
  final int manifestCount;
  final int boardedCount;
  final int deniedCount;
  final int noShowCount;
  final int pendingCount;

  const CoachCrewTripSummary({
    required this.tripId,
    required this.journeyId,
    required this.bookingId,
    required this.operatorName,
    required this.from,
    required this.to,
    required this.departureAtIso,
    required this.arrivalAtIso,
    required this.boardingOpensAtIso,
    required this.boardingClosesAtIso,
    required this.gateLabel,
    required this.vehicleLabel,
    required this.manifestCount,
    required this.boardedCount,
    required this.deniedCount,
    required this.noShowCount,
    required this.pendingCount,
  });

  static CoachCrewTripSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tripId = (raw['trip_id'] ?? '').toString().trim();
    final journeyId = (raw['journey_id'] ?? '').toString().trim();
    final bookingId = (raw['booking_id'] ?? '').toString().trim();
    final operatorName = (raw['operator_name'] ?? '').toString().trim();
    final from = (raw['from'] ?? '').toString().trim();
    final to = (raw['to'] ?? '').toString().trim();
    final departureAtIso = (raw['departure_at'] ?? '').toString().trim();
    final arrivalAtIso = (raw['arrival_at'] ?? '').toString().trim();
    final boardingOpensAtIso =
        (raw['boarding_opens_at'] ?? '').toString().trim();
    final boardingClosesAtIso =
        (raw['boarding_closes_at'] ?? '').toString().trim();
    final gateLabel = (raw['gate_label'] ?? '').toString().trim();
    final vehicleLabel = (raw['vehicle_label'] ?? '').toString().trim();
    final manifestCount = raw['manifest_count'];
    final boardedCount = raw['boarded_count'];
    final deniedCount = raw['denied_count'];
    final noShowCount = raw['no_show_count'];
    final pendingCount = raw['pending_count'];
    if (tripId.isEmpty ||
        journeyId.isEmpty ||
        bookingId.isEmpty ||
        operatorName.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        departureAtIso.isEmpty ||
        arrivalAtIso.isEmpty ||
        boardingOpensAtIso.isEmpty ||
        boardingClosesAtIso.isEmpty ||
        gateLabel.isEmpty ||
        vehicleLabel.isEmpty ||
        manifestCount is! int ||
        boardedCount is! int ||
        deniedCount is! int ||
        noShowCount is! int ||
        pendingCount is! int) {
      return null;
    }
    return CoachCrewTripSummary(
      tripId: tripId,
      journeyId: journeyId,
      bookingId: bookingId,
      operatorName: operatorName,
      from: from,
      to: to,
      departureAtIso: departureAtIso,
      arrivalAtIso: arrivalAtIso,
      boardingOpensAtIso: boardingOpensAtIso,
      boardingClosesAtIso: boardingClosesAtIso,
      gateLabel: gateLabel,
      vehicleLabel: vehicleLabel,
      manifestCount: manifestCount,
      boardedCount: boardedCount,
      deniedCount: deniedCount,
      noShowCount: noShowCount,
      pendingCount: pendingCount,
    );
  }
}

class CoachCrewDepartureBoardResponse {
  final String generatedAtIso;
  final List<CoachCrewTripSummary> departures;

  const CoachCrewDepartureBoardResponse({
    required this.generatedAtIso,
    required this.departures,
  });

  static CoachCrewDepartureBoardResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final generatedAtIso = (raw['generated_at'] ?? '').toString().trim();
    final departuresRaw = raw['departures'];
    if (generatedAtIso.isEmpty || departuresRaw is! List) {
      return null;
    }
    return CoachCrewDepartureBoardResponse(
      generatedAtIso: generatedAtIso,
      departures: departuresRaw
          .map(CoachCrewTripSummary.fromJson)
          .whereType<CoachCrewTripSummary>()
          .toList(growable: false),
    );
  }
}

class CoachCrewManifestEntry {
  final CoachPassengerManifest passenger;
  final CoachTicketCoupon ticket;
  final String seatNumber;
  final CoachManifestBoardingState boardingState;
  final CoachBoardingEvent? lastEvent;
  final bool needsAttention;

  const CoachCrewManifestEntry({
    required this.passenger,
    required this.ticket,
    required this.seatNumber,
    required this.boardingState,
    required this.lastEvent,
    required this.needsAttention,
  });

  static CoachCrewManifestEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final passenger = CoachPassengerManifest.fromJson(raw['passenger']);
    final ticket = CoachTicketCoupon.fromJson(raw['ticket']);
    final seatNumber = (raw['seat_number'] ?? '').toString().trim();
    final boardingState = coachManifestBoardingStateFromWire(
      (raw['boarding_state'] ?? '').toString().trim(),
    );
    final lastEvent = CoachBoardingEvent.fromJson(raw['last_event']);
    final needsAttention = raw['needs_attention'];
    if (passenger == null ||
        ticket == null ||
        seatNumber.isEmpty ||
        boardingState == null ||
        needsAttention is! bool) {
      return null;
    }
    return CoachCrewManifestEntry(
      passenger: passenger,
      ticket: ticket,
      seatNumber: seatNumber,
      boardingState: boardingState,
      lastEvent: lastEvent,
      needsAttention: needsAttention,
    );
  }
}

class CoachCrewManifestResponse {
  final CoachCrewTripSummary trip;
  final List<CoachCrewManifestEntry> manifest;
  final List<CoachBoardingEvent> recentEvents;

  const CoachCrewManifestResponse({
    required this.trip,
    required this.manifest,
    required this.recentEvents,
  });

  static CoachCrewManifestResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final trip = CoachCrewTripSummary.fromJson(raw['trip']);
    final manifestRaw = raw['manifest'];
    final recentEventsRaw = raw['recent_events'];
    if (trip == null || manifestRaw is! List || recentEventsRaw is! List) {
      return null;
    }
    return CoachCrewManifestResponse(
      trip: trip,
      manifest: manifestRaw
          .map(CoachCrewManifestEntry.fromJson)
          .whereType<CoachCrewManifestEntry>()
          .toList(growable: false),
      recentEvents: recentEventsRaw
          .map(CoachBoardingEvent.fromJson)
          .whereType<CoachBoardingEvent>()
          .toList(growable: false),
    );
  }
}

class CoachCrewBoardingResult {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachCrewTripSummary trip;
  final CoachCrewManifestEntry manifestEntry;
  final CoachBoardingEvent boardingEvent;
  final List<CoachBoardingEvent> recentEvents;

  const CoachCrewBoardingResult({
    required this.idempotency,
    required this.trip,
    required this.manifestEntry,
    required this.boardingEvent,
    required this.recentEvents,
  });

  static CoachCrewBoardingResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final trip = CoachCrewTripSummary.fromJson(raw['trip']);
    final manifestEntry =
        CoachCrewManifestEntry.fromJson(raw['manifest_entry']);
    final boardingEvent = CoachBoardingEvent.fromJson(raw['boarding_event']);
    final recentEventsRaw = raw['recent_events'];
    if (idempotency == null ||
        trip == null ||
        manifestEntry == null ||
        boardingEvent == null ||
        recentEventsRaw is! List) {
      return null;
    }
    return CoachCrewBoardingResult(
      idempotency: idempotency,
      trip: trip,
      manifestEntry: manifestEntry,
      boardingEvent: boardingEvent,
      recentEvents: recentEventsRaw
          .map(CoachBoardingEvent.fromJson)
          .whereType<CoachBoardingEvent>()
          .toList(growable: false),
    );
  }
}

class CoachCommandIdempotencyMeta {
  final String key;
  final String scope;
  final String requestFingerprint;
  final bool replayed;
  final Map<String, String> derivedKeys;

  const CoachCommandIdempotencyMeta({
    required this.key,
    required this.scope,
    required this.requestFingerprint,
    required this.replayed,
    required this.derivedKeys,
  });

  static CoachCommandIdempotencyMeta? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = (raw['key'] ?? '').toString().trim();
    final scope = (raw['scope'] ?? '').toString().trim();
    final requestFingerprint =
        (raw['request_fingerprint'] ?? '').toString().trim();
    final replayed = raw['replayed'];
    final derivedKeys = _coachStringMap(raw['derived_keys']);
    if (key.isEmpty ||
        scope.isEmpty ||
        requestFingerprint.isEmpty ||
        replayed is! bool) {
      return null;
    }
    return CoachCommandIdempotencyMeta(
      key: key,
      scope: scope,
      requestFingerprint: requestFingerprint,
      replayed: replayed,
      derivedKeys: derivedKeys,
    );
  }
}

class CoachPaymentAuthorization {
  final String status;
  final String method;
  final String authorizationReference;
  final String currency;
  final int chargedMinorUnits;

  const CoachPaymentAuthorization({
    required this.status,
    required this.method,
    required this.authorizationReference,
    required this.currency,
    required this.chargedMinorUnits,
  });

  static CoachPaymentAuthorization? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final status = (raw['status'] ?? '').toString().trim();
    final method = (raw['method'] ?? '').toString().trim();
    final authorizationReference =
        (raw['authorization_reference'] ?? '').toString().trim();
    final currency = (raw['currency'] ?? '').toString().trim().toUpperCase();
    final chargedMinorUnits = raw['charged_minor_units'];
    if (status.isEmpty ||
        method.isEmpty ||
        authorizationReference.isEmpty ||
        !_isCoachCurrency(currency) ||
        chargedMinorUnits is! int ||
        chargedMinorUnits < 0) {
      return null;
    }
    return CoachPaymentAuthorization(
      status: status,
      method: method,
      authorizationReference: authorizationReference,
      currency: currency,
      chargedMinorUnits: chargedMinorUnits,
    );
  }
}

class CoachCompensationState {
  final String state;
  final String action;
  final String supportQueue;
  final bool triggered;
  final String? reason;
  final String? recoveryReference;

  const CoachCompensationState({
    required this.state,
    required this.action,
    required this.supportQueue,
    required this.triggered,
    required this.reason,
    required this.recoveryReference,
  });

  static CoachCompensationState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final state = (raw['state'] ?? '').toString().trim();
    final action = (raw['action'] ?? '').toString().trim();
    final supportQueue = (raw['support_queue'] ?? '').toString().trim();
    final triggered = raw['triggered'];
    final reason = raw['reason'] == null ? '' : raw['reason'].toString().trim();
    final recoveryReference = raw['recovery_reference'] == null
        ? ''
        : raw['recovery_reference'].toString().trim();
    if (state.isEmpty ||
        action.isEmpty ||
        supportQueue.isEmpty ||
        triggered is! bool) {
      return null;
    }
    return CoachCompensationState(
      state: state,
      action: action,
      supportQueue: supportQueue,
      triggered: triggered,
      reason: reason.isEmpty ? null : reason,
      recoveryReference: recoveryReference.isEmpty ? null : recoveryReference,
    );
  }
}

class CoachHoldDraft {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOffer offer;
  final CoachHold hold;
  final String bookingState;
  final int holdTtlSeconds;

  const CoachHoldDraft({
    required this.idempotency,
    required this.offer,
    required this.hold,
    required this.bookingState,
    required this.holdTtlSeconds,
  });

  static CoachHoldDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final offer = CoachOffer.fromJson(raw['offer']);
    final hold = CoachHold.fromJson(raw['hold']);
    final bookingState = (raw['booking_state'] ?? '').toString().trim();
    final holdTtlSeconds = raw['hold_ttl_seconds'];
    if (idempotency == null ||
        offer == null ||
        hold == null ||
        bookingState.isEmpty ||
        holdTtlSeconds is! int ||
        holdTtlSeconds <= 0) {
      return null;
    }
    return CoachHoldDraft(
      idempotency: idempotency,
      offer: offer,
      hold: hold,
      bookingState: bookingState,
      holdTtlSeconds: holdTtlSeconds,
    );
  }
}

class CoachBookingDraft {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachOffer offer;
  final CoachHold? hold;
  final CoachBooking booking;
  final List<CoachPassengerManifest> passengerManifests;
  final CoachPaymentAuthorization payment;
  final CoachCompensationState compensation;
  final String nextAction;

  const CoachBookingDraft({
    required this.idempotency,
    required this.offer,
    required this.hold,
    required this.booking,
    required this.passengerManifests,
    required this.payment,
    required this.compensation,
    required this.nextAction,
  });

  static CoachBookingDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final offer = CoachOffer.fromJson(raw['offer']);
    final hold = CoachHold.fromJson(raw['hold']);
    final booking = CoachBooking.fromJson(raw['booking']);
    final passengerManifestsRaw = raw['passengers_manifest'];
    final payment = CoachPaymentAuthorization.fromJson(raw['payment']);
    final compensation = CoachCompensationState.fromJson(raw['compensation']);
    final nextAction = (raw['next_action'] ?? '').toString().trim();
    final passengerManifests = passengerManifestsRaw is List
        ? passengerManifestsRaw
            .map(CoachPassengerManifest.fromJson)
            .whereType<CoachPassengerManifest>()
            .toList(growable: false)
        : const <CoachPassengerManifest>[];
    if (idempotency == null ||
        offer == null ||
        booking == null ||
        payment == null ||
        compensation == null ||
        nextAction.isEmpty) {
      return null;
    }
    return CoachBookingDraft(
      idempotency: idempotency,
      offer: offer,
      hold: hold,
      booking: booking,
      passengerManifests: passengerManifests,
      payment: payment,
      compensation: compensation,
      nextAction: nextAction,
    );
  }
}

class CoachTicketingResult {
  final CoachCommandIdempotencyMeta idempotency;
  final CoachBooking booking;
  final List<CoachPassengerManifest> passengerManifests;
  final List<CoachTicketCoupon> tickets;
  final List<String> deliveryChannels;
  final CoachCompensationState compensation;

  const CoachTicketingResult({
    required this.idempotency,
    required this.booking,
    required this.passengerManifests,
    required this.tickets,
    required this.deliveryChannels,
    required this.compensation,
  });

  static CoachTicketingResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final idempotency =
        CoachCommandIdempotencyMeta.fromJson(raw['idempotency']);
    final booking = CoachBooking.fromJson(raw['booking']);
    final passengerManifestsRaw = raw['passengers_manifest'];
    final ticketsRaw = raw['tickets'];
    final deliveryChannels = _coachStringList(raw['delivery_channels']);
    final compensation = CoachCompensationState.fromJson(raw['compensation']);
    if (idempotency == null ||
        booking == null ||
        ticketsRaw is! List ||
        deliveryChannels.isEmpty ||
        compensation == null) {
      return null;
    }
    final tickets = ticketsRaw
        .map(CoachTicketCoupon.fromJson)
        .whereType<CoachTicketCoupon>()
        .toList(growable: false);
    final passengerManifests = passengerManifestsRaw is List
        ? passengerManifestsRaw
            .map(CoachPassengerManifest.fromJson)
            .whereType<CoachPassengerManifest>()
            .toList(growable: false)
        : const <CoachPassengerManifest>[];
    if (tickets.isEmpty) return null;
    return CoachTicketingResult(
      idempotency: idempotency,
      booking: booking,
      passengerManifests: passengerManifests,
      tickets: tickets,
      deliveryChannels: deliveryChannels,
      compensation: compensation,
    );
  }
}

class CoachMobilityApi {
  static const Duration _requestTimeout = Duration(seconds: 15);

  final String baseUrl;
  final http.Client? _httpClient;

  const CoachMobilityApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  Future<CoachBookingShelfResponse> listBookings() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'bookings'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachBookingShelfResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach booking shelf payload');
    }
    return response;
  }

  Future<CoachJourneyLiveResponse> getJourneyLive(String journeyId) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'journeys', journeyId, 'live'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachJourneyLiveResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach journey live payload');
    }
    return response;
  }

  Future<CoachRefundEligibilityResponse> getRefundEligibility(
    String bookingId,
  ) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'bookings',
        bookingId,
        'refund_eligibility',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachRefundEligibilityResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach refund eligibility payload');
    }
    return response;
  }

  Future<CoachChangeOptionsResponse> getChangeOptions(String bookingId) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'bookings',
        bookingId,
        'change_options',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachChangeOptionsResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach change options payload');
    }
    return response;
  }

  Future<CoachAdminOverviewResponse> adminOverview({
    int limit = 8,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'admin', 'overview'],
      queryParameters: <String, String>{
        'limit': limit.toString(),
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachAdminOverviewResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach admin overview payload');
    }
    return response;
  }

  Future<CoachAdminPartnerOnboardingResponse> adminPartnerOnboarding({
    String? query,
    String? workflowStatus,
    int limit = 20,
  }) async {
    final normalizedQuery = query?.trim() ?? '';
    final normalizedWorkflowStatus = workflowStatus?.trim() ?? '';
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
      if (normalizedQuery.isNotEmpty) 'q': normalizedQuery,
      if (normalizedWorkflowStatus.isNotEmpty)
        'workflow_status': normalizedWorkflowStatus,
    };
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'admin',
        'partners',
        'onboarding',
      ],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachAdminPartnerOnboardingResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach admin partner onboarding payload',
      );
    }
    return response;
  }

  Future<CoachAdminPartnerOnboardingMutationResult>
      adminPartnerOnboardingAction({
    required String operatorId,
    required String action,
    String? ownerAccountId,
    String? dueAtIso,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'admin',
        'partners',
        operatorId,
        'onboarding_action',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'action': action.trim(),
        if ((ownerAccountId ?? '').trim().isNotEmpty)
          'owner_account_id': ownerAccountId!.trim(),
        if ((dueAtIso ?? '').trim().isNotEmpty) 'due_at': dueAtIso!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-admin-partner-onboarding-action'),
    );
    final response =
        CoachAdminPartnerOnboardingMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach admin partner onboarding action payload',
      );
    }
    return response;
  }

  Future<CoachAdminDisruptionsResponse> adminDisruptions({
    String? query,
    String? workflowStatus,
    String? disruptionKind,
    int limit = 20,
  }) async {
    final normalizedQuery = query?.trim() ?? '';
    final normalizedWorkflowStatus = workflowStatus?.trim() ?? '';
    final normalizedDisruptionKind = disruptionKind?.trim() ?? '';
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
      if (normalizedQuery.isNotEmpty) 'q': normalizedQuery,
      if (normalizedWorkflowStatus.isNotEmpty)
        'workflow_status': normalizedWorkflowStatus,
      if (normalizedDisruptionKind.isNotEmpty)
        'disruption_kind': normalizedDisruptionKind,
    };
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'admin',
        'disruptions',
      ],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachAdminDisruptionsResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach admin disruptions payload');
    }
    return response;
  }

  Future<CoachAdminDisruptionMutationResult> adminDisruptionAction({
    required String tripId,
    required String action,
    int? delayMinutes,
    String? reason,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'admin',
        'disruptions',
        tripId,
        'action',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'action': action.trim(),
        if (delayMinutes != null) 'delay_minutes': delayMinutes,
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-admin-disruption-action'),
    );
    final response = CoachAdminDisruptionMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach admin disruption action payload',
      );
    }
    return response;
  }

  Future<CoachAdminFinanceJournalResponse> adminFinanceJournal({
    String? query,
    int limit = 20,
  }) async {
    final normalizedQuery = query?.trim() ?? '';
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
      if (normalizedQuery.isNotEmpty) 'q': normalizedQuery,
    };
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'admin',
        'finance',
        'journal',
      ],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachAdminFinanceJournalResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach admin finance journal payload');
    }
    return response;
  }

  Future<CoachAdminShamellPayReconciliationResponse>
      adminShamellPayReconciliation({
    String? query,
    int limit = 20,
  }) async {
    final normalizedQuery = query?.trim() ?? '';
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
      if (normalizedQuery.isNotEmpty) 'q': normalizedQuery,
    };
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'admin',
        'finance',
        'shamell_pay_reconciliation',
      ],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response =
        CoachAdminShamellPayReconciliationResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach admin SyrChat Pay reconciliation payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportBatchMutationResult>
      createAdminShamellPayReportImport({
    required String reportName,
    String reportFormat = 'csv',
    required String reportBody,
    String? expectedPreviewToken,
    bool dryRun = false,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'admin',
        'finance',
        'shamell_pay_reports',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'report_name': reportName.trim(),
        'report_format': reportFormat.trim(),
        'report_body': reportBody,
        if ((expectedPreviewToken ?? '').trim().isNotEmpty)
          'expected_preview_token': expectedPreviewToken!.trim(),
        if (dryRun) 'dry_run': true,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-admin-shamell-pay-report-import'),
    );
    final response =
        CoachOperatorPayoutImportBatchMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach admin SyrChat Pay report import payload',
      );
    }
    return response;
  }

  Future<CoachOperatorPayoutImportMutationResult>
      releaseAdminShamellPayOperatorRail({
    required String payoutRunId,
    String? note,
    String? externalReference,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'admin',
        'finance',
        'shamell_pay_reconciliation',
        payoutRunId,
        'release_operator_rail',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
        if ((externalReference ?? '').trim().isNotEmpty)
          'external_reference': externalReference!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-admin-operator-rail-release'),
    );
    final response = CoachOperatorPayoutImportMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach admin operator rail release payload',
      );
    }
    return response;
  }

  Future<CoachOperatorPayoutImportMutationResult>
      confirmAdminShamellPayOperatorRail({
    required String payoutRunId,
    String? paymentReference,
    String? externalReference,
    String? importedAtIso,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'admin',
        'finance',
        'shamell_pay_reconciliation',
        payoutRunId,
        'confirm_operator_rail',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if ((paymentReference ?? '').trim().isNotEmpty)
          'payment_reference': paymentReference!.trim(),
        if ((externalReference ?? '').trim().isNotEmpty)
          'external_reference': externalReference!.trim(),
        if ((importedAtIso ?? '').trim().isNotEmpty)
          'imported_at': importedAtIso!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-admin-operator-rail-confirm'),
    );
    final response = CoachOperatorPayoutImportMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach admin operator rail confirm payload',
      );
    }
    return response;
  }

  Future<CoachOperatorPayoutImportMutationResult>
      failAdminShamellPayOperatorRail({
    required String payoutRunId,
    String? externalReference,
    String? importedAtIso,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'admin',
        'finance',
        'shamell_pay_reconciliation',
        payoutRunId,
        'fail_operator_rail',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if ((externalReference ?? '').trim().isNotEmpty)
          'external_reference': externalReference!.trim(),
        if ((importedAtIso ?? '').trim().isNotEmpty)
          'imported_at': importedAtIso!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-admin-operator-rail-fail'),
    );
    final response = CoachOperatorPayoutImportMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach admin operator rail fail payload',
      );
    }
    return response;
  }

  Future<CoachAdminRiskDashboardResponse> adminRiskDashboard({
    String? query,
    int limit = 20,
  }) async {
    final normalizedQuery = query?.trim() ?? '';
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
      if (normalizedQuery.isNotEmpty) 'q': normalizedQuery,
    };
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'admin',
        'risk',
        'dashboard',
      ],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachAdminRiskDashboardResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach admin risk dashboard payload');
    }
    return response;
  }

  Future<CoachAdminRiskMutationResult> adminRiskAction({
    required String riskId,
    required String action,
    String? ownerAccountId,
    String? ownerTeam,
    String? snoozedUntilIso,
    String? snoozeReason,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'admin',
        'risk',
        riskId,
        'action',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'action': action.trim(),
        if ((ownerAccountId ?? '').trim().isNotEmpty)
          'owner_account_id': ownerAccountId!.trim(),
        if ((ownerTeam ?? '').trim().isNotEmpty)
          'owner_team': ownerTeam!.trim(),
        if ((snoozedUntilIso ?? '').trim().isNotEmpty)
          'snoozed_until': snoozedUntilIso!.trim(),
        if ((snoozeReason ?? '').trim().isNotEmpty)
          'snooze_reason': snoozeReason!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-admin-risk-action'),
    );
    final response = CoachAdminRiskMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach admin risk action payload');
    }
    return response;
  }

  Future<CoachAdminSupportCasesResponse> adminSupportCases({
    String? query,
    int limit = 20,
  }) async {
    final normalizedQuery = query?.trim() ?? '';
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
      if (normalizedQuery.isNotEmpty) 'q': normalizedQuery,
    };
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'admin',
        'support',
        'cases',
      ],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachAdminSupportCasesResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach admin support cases payload');
    }
    return response;
  }

  Future<CoachAdminSupportCaseDetailResponse> adminSupportCaseDetail(
    String caseId,
  ) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'admin',
        'support',
        'cases',
        caseId,
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachAdminSupportCaseDetailResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach admin support case detail payload');
    }
    return response;
  }

  Future<CoachSelfServiceReissueResult> adminResolveSupportCasePaymentFailure({
    required String caseId,
    required String paymentMethod,
    List<String>? deliveryChannels,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'admin',
        'support',
        'cases',
        caseId,
        'resolve_payment_failure',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'payment_method': paymentMethod.trim(),
        if (deliveryChannels != null && deliveryChannels.isNotEmpty)
          'delivery_channels': deliveryChannels,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-admin-support-reissue-recovery'),
    );
    final response = CoachSelfServiceReissueResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach admin support payment recovery payload');
    }
    return response;
  }

  Future<CoachOperatorRefundQueueResponse> operatorRefundQueue({
    int limit = 20,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'operator', 'refund_queue'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorRefundQueueResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator refund queue payload');
    }
    return response;
  }

  Future<CoachOperatorChangeQueueResponse> operatorChangeQueue({
    int limit = 20,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'operator', 'change_queue'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorChangeQueueResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator change queue payload');
    }
    return response;
  }

  Future<CoachOperatorReconciliationResponse> operatorReconciliation({
    int limit = 12,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'reconciliation',
      ],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorReconciliationResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator reconciliation payload');
    }
    return response;
  }

  Future<CoachOperatorSettlementStatementsResponse>
      operatorSettlementStatements({
    int limit = 8,
    String? cursor,
  }) async {
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
    };
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      queryParameters['cursor'] = normalizedCursor;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'settlement_statements',
      ],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response =
        CoachOperatorSettlementStatementsResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator settlement statements payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutRunsResponse> operatorPayoutRuns({
    int limit = 8,
    String? cursor,
  }) async {
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
    };
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      queryParameters['cursor'] = normalizedCursor;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'operator', 'payout_runs'],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorPayoutRunsResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout runs payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutReconciliationResponse>
      operatorPayoutReconciliation({
    int limit = 8,
    String? cursor,
  }) async {
    final queryParameters = <String, String>{
      'limit': limit.clamp(1, 50).toString(),
    };
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      queryParameters['cursor'] = normalizedCursor;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_reconciliation',
      ],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response =
        CoachOperatorPayoutReconciliationResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout reconciliation payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportsResponse> operatorPayoutImports({
    int limit = 8,
    String? cursor,
  }) async {
    final normalizedCursor = cursor?.trim();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'operator', 'payout_imports'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedCursor != null && normalizedCursor.isNotEmpty)
          'cursor': normalizedCursor,
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorPayoutImportsResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout imports payload');
    }
    return response;
  }

  Future<CoachOperatorCatalogImportRunsResponse> operatorCatalogImportRuns({
    int limit = 8,
    String? cursor,
    String? status,
    String? replayScope,
    String? issueSeverity,
    String? issueStage,
  }) async {
    final normalizedCursor = cursor?.trim();
    final normalizedStatus = status?.trim();
    final normalizedReplayScope = replayScope?.trim();
    final normalizedIssueSeverity = issueSeverity?.trim();
    final normalizedIssueStage = issueStage?.trim();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_runs',
      ],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedCursor != null && normalizedCursor.isNotEmpty)
          'cursor': normalizedCursor,
        if (normalizedStatus != null && normalizedStatus.isNotEmpty)
          'status': normalizedStatus,
        if (normalizedReplayScope != null && normalizedReplayScope.isNotEmpty)
          'replay_scope': normalizedReplayScope,
        if (normalizedIssueSeverity != null &&
            normalizedIssueSeverity.isNotEmpty &&
            normalizedIssueSeverity != 'all')
          'severity': normalizedIssueSeverity,
        if (normalizedIssueStage != null &&
            normalizedIssueStage.isNotEmpty &&
            normalizedIssueStage != 'all')
          'stage': normalizedIssueStage,
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorCatalogImportRunsResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator catalog import runs payload');
    }
    return response;
  }

  Future<List<CoachCatalogImportRunSavedView>>
      operatorCatalogImportRunSavedViews({
    String visibilityScope = 'all',
    String? ownerAccountId,
    String? operatorId,
  }) async {
    final normalizedScope = switch (visibilityScope.trim().toLowerCase()) {
      'personal' => 'personal',
      'shared_ops' => 'shared_ops',
      _ => 'all',
    };
    final normalizedOwnerAccountId = switch ((ownerAccountId ?? '').trim()) {
      '' => null,
      'all' => null,
      final value => value,
    };
    final normalizedOperatorId = switch ((operatorId ?? '').trim()) {
      '' => null,
      'all' => null,
      final value => value,
    };
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_saved_views',
      ],
      queryParameters: <String, String>{
        if (normalizedScope != 'all') 'visibility_scope': normalizedScope,
        if (normalizedScope == 'shared_ops' &&
            normalizedOwnerAccountId != null &&
            normalizedOwnerAccountId.isNotEmpty)
          'owner_account_id': normalizedOwnerAccountId,
        if (normalizedScope == 'shared_ops' &&
            normalizedOperatorId != null &&
            normalizedOperatorId.isNotEmpty)
          'operator_id': normalizedOperatorId,
      }.isEmpty
          ? null
          : <String, String>{
              if (normalizedScope != 'all') 'visibility_scope': normalizedScope,
              if (normalizedScope == 'shared_ops' &&
                  normalizedOwnerAccountId != null &&
                  normalizedOwnerAccountId.isNotEmpty)
                'owner_account_id': normalizedOwnerAccountId,
              if (normalizedScope == 'shared_ops' &&
                  normalizedOperatorId != null &&
                  normalizedOperatorId.isNotEmpty)
                'operator_id': normalizedOperatorId,
            },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewsFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      operatorCatalogImportRunSavedViewOwners() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_saved_views',
      ],
      queryParameters: const <String, String>{
        'visibility_scope': 'shared_ops',
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewOwnerSummariesFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      operatorCatalogImportRunSavedViewOperators() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_saved_views',
      ],
      queryParameters: const <String, String>{
        'visibility_scope': 'shared_ops',
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewOperatorSummariesFromPayload(
      decoded,
    );
  }

  Future<List<CoachCatalogImportRunSavedView>>
      upsertOperatorCatalogImportRunSavedView(
    CoachCatalogImportRunSavedView view, {
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_saved_views',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'view_id': view.viewId,
        'name': view.name,
        'visibility_scope': view.visibilityScope,
        'operator_ids': view.operatorIds,
        'status': view.preferences.status,
        'replay_scope': view.preferences.replayScope,
        'severity': view.preferences.issueSeverity,
        'stage': view.preferences.issueStage,
        'is_default': view.isDefault,
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-catalog-import-run-saved-view'),
    );
    return _coachCatalogImportRunSavedViewsFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedView>>
      deleteOperatorCatalogImportRunSavedView(
    String viewId, {
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_saved_views',
        normalizedViewId,
        'delete',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      const <String, Object?>{},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-catalog-import-run-saved-view-delete',
          ),
    );
    return _coachCatalogImportRunSavedViewsFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedView>>
      toggleOperatorCatalogImportRunSavedViewFavorite(
    String viewId, {
    required bool favorite,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_saved_views',
        normalizedViewId,
        'favorite',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{'favorite': favorite},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-catalog-import-run-saved-view-favorite',
          ),
    );
    return _coachCatalogImportRunSavedViewsFromPayload(decoded);
  }

  Future<String?> markOperatorCatalogImportRunSavedViewUsed(
    String viewId, {
    String? usedAtIso,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_saved_views',
        normalizedViewId,
        'use',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if ((usedAtIso ?? '').trim().isNotEmpty) 'used_at': usedAtIso!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-catalog-import-run-saved-view-use',
          ),
    );
    if (decoded is! Map) {
      return null;
    }
    return (decoded['used_at'] ?? '').toString().trim().isEmpty
        ? null
        : (decoded['used_at'] ?? '').toString().trim();
  }

  Future<List<CoachCatalogImportRunIssueSavedView>>
      operatorCatalogImportRunIssueSavedViews({
    String visibilityScope = 'all',
    String? ownerAccountId,
    String? operatorId,
  }) async {
    final normalizedScope = switch (visibilityScope.trim().toLowerCase()) {
      'personal' => 'personal',
      'shared_ops' => 'shared_ops',
      _ => 'all',
    };
    final normalizedOwnerAccountId = switch ((ownerAccountId ?? '').trim()) {
      '' => null,
      'all' => null,
      final value => value,
    };
    final normalizedOperatorId = switch ((operatorId ?? '').trim()) {
      '' => null,
      'all' => null,
      final value => value,
    };
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_issue_saved_views',
      ],
      queryParameters: <String, String>{
        if (normalizedScope != 'all') 'visibility_scope': normalizedScope,
        if (normalizedScope == 'shared_ops' &&
            normalizedOwnerAccountId != null &&
            normalizedOwnerAccountId.isNotEmpty)
          'owner_account_id': normalizedOwnerAccountId,
        if (normalizedScope == 'shared_ops' &&
            normalizedOperatorId != null &&
            normalizedOperatorId.isNotEmpty)
          'operator_id': normalizedOperatorId,
      }.isEmpty
          ? null
          : <String, String>{
              if (normalizedScope != 'all') 'visibility_scope': normalizedScope,
              if (normalizedScope == 'shared_ops' &&
                  normalizedOwnerAccountId != null &&
                  normalizedOwnerAccountId.isNotEmpty)
                'owner_account_id': normalizedOwnerAccountId,
              if (normalizedScope == 'shared_ops' &&
                  normalizedOperatorId != null &&
                  normalizedOperatorId.isNotEmpty)
                'operator_id': normalizedOperatorId,
            },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunIssueSavedViewsFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      operatorCatalogImportRunIssueSavedViewOwners() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_issue_saved_views',
      ],
      queryParameters: const <String, String>{
        'visibility_scope': 'shared_ops',
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewOwnerSummariesFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      operatorCatalogImportRunIssueSavedViewOperators() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_issue_saved_views',
      ],
      queryParameters: const <String, String>{
        'visibility_scope': 'shared_ops',
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewOperatorSummariesFromPayload(
      decoded,
    );
  }

  Future<List<CoachCatalogImportRunIssueSavedView>>
      upsertOperatorCatalogImportRunIssueSavedView(
    CoachCatalogImportRunIssueSavedView view, {
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_issue_saved_views',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'view_id': view.viewId,
        'name': view.name,
        'visibility_scope': view.visibilityScope,
        'operator_ids': view.operatorIds,
        'severity': view.preferences.severity,
        'stage': view.preferences.stage,
        'is_default': view.isDefault,
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-catalog-import-run-issue-saved-view',
          ),
    );
    return _coachCatalogImportRunIssueSavedViewsFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunIssueSavedView>>
      deleteOperatorCatalogImportRunIssueSavedView(
    String viewId, {
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_issue_saved_views',
        normalizedViewId,
        'delete',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      const <String, Object?>{},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-catalog-import-run-issue-saved-view-delete',
          ),
    );
    return _coachCatalogImportRunIssueSavedViewsFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunIssueSavedView>>
      toggleOperatorCatalogImportRunIssueSavedViewFavorite(
    String viewId, {
    required bool favorite,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_issue_saved_views',
        normalizedViewId,
        'favorite',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{'favorite': favorite},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-catalog-import-run-issue-saved-view-favorite',
          ),
    );
    return _coachCatalogImportRunIssueSavedViewsFromPayload(decoded);
  }

  Future<String?> markOperatorCatalogImportRunIssueSavedViewUsed(
    String viewId, {
    String? usedAtIso,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_run_issue_saved_views',
        normalizedViewId,
        'use',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if ((usedAtIso ?? '').trim().isNotEmpty) 'used_at': usedAtIso!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-catalog-import-run-issue-saved-view-use',
          ),
    );
    if (decoded is! Map) {
      return null;
    }
    return (decoded['used_at'] ?? '').toString().trim().isEmpty
        ? null
        : (decoded['used_at'] ?? '').toString().trim();
  }

  Future<CoachOperatorCatalogImportConfigResponse>
      operatorCatalogImportConfig() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_config',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorCatalogImportConfigResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator catalog import config payload');
    }
    return response;
  }

  Future<CoachOperatorCatalogImportRunDetailResponse> operatorCatalogImportRun(
    String importRunId, {
    int limit = 8,
    String? cursor,
    String? issueSeverity,
    String? issueStage,
  }) async {
    final normalizedImportRunId = importRunId.trim();
    if (normalizedImportRunId.isEmpty) {
      throw const CoachApiException('import run id required');
    }
    final normalizedCursor = cursor?.trim();
    final normalizedIssueSeverity = issueSeverity?.trim();
    final normalizedIssueStage = issueStage?.trim();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_runs',
        normalizedImportRunId,
      ],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedCursor != null && normalizedCursor.isNotEmpty)
          'cursor': normalizedCursor,
        if (normalizedIssueSeverity != null &&
            normalizedIssueSeverity.isNotEmpty &&
            normalizedIssueSeverity != 'all')
          'severity': normalizedIssueSeverity,
        if (normalizedIssueStage != null &&
            normalizedIssueStage.isNotEmpty &&
            normalizedIssueStage != 'all')
          'stage': normalizedIssueStage,
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorCatalogImportRunDetailResponse.fromJson(
      decoded,
    );
    if (response == null) {
      throw const CoachApiException(
        'invalid coach operator catalog import run detail payload',
      );
    }
    return response;
  }

  Future<CoachOperatorCatalogImportRunLineageResponse>
      operatorCatalogImportRunLineage(
    String importRunId, {
    int limit = 8,
    String? cursor,
  }) async {
    final normalizedImportRunId = importRunId.trim();
    if (normalizedImportRunId.isEmpty) {
      throw const CoachApiException('import run id required');
    }
    final normalizedCursor = cursor?.trim();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_runs',
        normalizedImportRunId,
        'replays',
      ],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedCursor != null && normalizedCursor.isNotEmpty)
          'cursor': normalizedCursor,
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorCatalogImportRunLineageResponse.fromJson(
      decoded,
    );
    if (response == null) {
      throw const CoachApiException(
        'invalid coach operator catalog import run lineage payload',
      );
    }
    return response;
  }

  Future<CoachOperatorCatalogImportSourcesResponse>
      operatorCatalogImportSources() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_sources',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response =
        CoachOperatorCatalogImportSourcesResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach operator catalog import sources payload',
      );
    }
    return response;
  }

  Future<CoachOperatorCatalogSourceArtifactsResponse>
      operatorCatalogSourceArtifacts({
    int limit = 8,
    String? cursor,
  }) async {
    final normalizedCursor = cursor?.trim();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_source_artifacts',
      ],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedCursor != null && normalizedCursor.isNotEmpty)
          'cursor': normalizedCursor,
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response =
        CoachOperatorCatalogSourceArtifactsResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach operator catalog source artifacts payload',
      );
    }
    return response;
  }

  Future<CoachOperatorCatalogSourceArtifactDetailResponse>
      operatorCatalogSourceArtifact(
    String artifactId, {
    int limit = 8,
    String? cursor,
  }) async {
    final normalizedArtifactId = artifactId.trim();
    if (normalizedArtifactId.isEmpty) {
      throw const CoachApiException('artifact id required');
    }
    final normalizedCursor = cursor?.trim();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'catalog_source_artifacts',
        normalizedArtifactId,
      ],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedCursor != null && normalizedCursor.isNotEmpty)
          'cursor': normalizedCursor,
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorCatalogSourceArtifactDetailResponse.fromJson(
      decoded,
    );
    if (response == null) {
      throw const CoachApiException(
        'invalid coach operator catalog source artifact payload',
      );
    }
    return response;
  }

  Future<CoachOperatorCatalogImportConfigMutationResult>
      updateOperatorCatalogImportConfig({
    required String feedLocator,
    String? idempotencyKey,
  }) async {
    final normalizedFeedLocator = feedLocator.trim();
    if (normalizedFeedLocator.isEmpty) {
      throw const CoachApiException('feed locator required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_config',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'feed_locator': normalizedFeedLocator,
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-catalog-import-config'),
    );
    final response =
        CoachOperatorCatalogImportConfigMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator catalog import config mutation payload');
    }
    return response;
  }

  Future<CoachOperatorCatalogImportSourceUploadResult>
      uploadOperatorCatalogImportSourceFile({
    String sourceKind = 'gtfs',
    required Uint8List fileBytes,
    required String fileName,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_sources',
        'upload',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final trimmedFileName =
        fileName.trim().isEmpty ? 'coach_gtfs_upload.zip' : fileName.trim();
    final decoded = await _postMultipart(
      uri,
      fields: <String, String>{
        'source_kind': sourceKind.trim().isEmpty ? 'gtfs' : sourceKind.trim(),
      },
      fileFieldName: 'file',
      fileName: trimmedFileName,
      fileBytes: fileBytes,
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-catalog-import-source-upload'),
    );
    final response =
        CoachOperatorCatalogImportSourceUploadResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
        'invalid coach operator catalog import source upload payload',
      );
    }
    return response;
  }

  Future<CoachOperatorFeedHealthResponse> operatorFeedHealth() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'operator', 'feed_health'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorFeedHealthResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator feed health payload');
    }
    return response;
  }

  Future<CoachOperatorCatalogImportRunMutationResult>
      triggerOperatorCatalogImportRun({
    String? sourceArtifactId,
    String? replayImportRunId,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'catalog_import_runs',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final normalizedSourceArtifactId = sourceArtifactId?.trim();
    final normalizedReplayImportRunId = replayImportRunId?.trim();
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if (normalizedSourceArtifactId != null &&
            normalizedSourceArtifactId.isNotEmpty)
          'source_artifact_id': normalizedSourceArtifactId,
        if (normalizedReplayImportRunId != null &&
            normalizedReplayImportRunId.isNotEmpty)
          'replay_import_run_id': normalizedReplayImportRunId,
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-catalog-import'),
    );
    final response =
        CoachOperatorCatalogImportRunMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator catalog import mutation payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportPreviewsResponse>
      operatorPayoutImportPreviews({
    int limit = 8,
    String? status,
    String? fromCreatedAtIso,
    String? toCreatedAtIso,
    String? cursor,
  }) async {
    final normalizedStatus = status?.trim();
    final normalizedFromCreatedAtIso = fromCreatedAtIso?.trim();
    final normalizedToCreatedAtIso = toCreatedAtIso?.trim();
    final normalizedCursor = cursor?.trim();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_previews',
      ],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedStatus != null && normalizedStatus.isNotEmpty)
          'status': normalizedStatus,
        if (normalizedFromCreatedAtIso != null &&
            normalizedFromCreatedAtIso.isNotEmpty)
          'from_created_at': normalizedFromCreatedAtIso,
        if (normalizedToCreatedAtIso != null &&
            normalizedToCreatedAtIso.isNotEmpty)
          'to_created_at': normalizedToCreatedAtIso,
        if (normalizedCursor != null && normalizedCursor.isNotEmpty)
          'cursor': normalizedCursor,
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response =
        CoachOperatorPayoutImportPreviewsResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout import previews payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportPreviewMutationResult>
      invalidateOperatorPayoutImportPreview({
    required String previewToken,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_import_previews',
        previewToken.trim(),
        'invalidate',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      const <String, Object?>{},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
              'coach-ops-payout-import-preview-invalidate'),
    );
    final response =
        CoachOperatorPayoutImportPreviewMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout import preview payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportProfilesResponse>
      operatorPayoutImportProfiles() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_profiles',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response =
        CoachOperatorPayoutImportProfilesResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout import profiles payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportBatchesResponse> operatorPayoutImportBatches({
    int limit = 8,
    String? cursor,
  }) async {
    final normalizedCursor = cursor?.trim();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batches',
      ],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedCursor != null && normalizedCursor.isNotEmpty)
          'cursor': normalizedCursor,
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachOperatorPayoutImportBatchesResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout import batches payload');
    }
    return response;
  }

  Future<List<CoachPayoutImportBatchSavedView>>
      operatorPayoutImportBatchSavedViews() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batch_saved_views',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachPayoutImportBatchSavedViewsFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      operatorPayoutImportBatchSavedViewOwners() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batch_saved_views',
      ],
      queryParameters: const <String, String>{
        'visibility_scope': 'shared_ops',
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewOwnerSummariesFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      operatorPayoutImportBatchSavedViewOperators() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batch_saved_views',
      ],
      queryParameters: const <String, String>{
        'visibility_scope': 'shared_ops',
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewOperatorSummariesFromPayload(
      decoded,
    );
  }

  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      operatorPayoutImportPreviewSavedViews() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_preview_saved_views',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachPayoutImportPreviewSavedViewsFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedViewOwnerSummary>>
      operatorPayoutImportPreviewSavedViewOwners() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_preview_saved_views',
      ],
      queryParameters: const <String, String>{
        'visibility_scope': 'shared_ops',
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewOwnerSummariesFromPayload(decoded);
  }

  Future<List<CoachCatalogImportRunSavedViewOperatorSummary>>
      operatorPayoutImportPreviewSavedViewOperators() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_preview_saved_views',
      ],
      queryParameters: const <String, String>{
        'visibility_scope': 'shared_ops',
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    return _coachCatalogImportRunSavedViewOperatorSummariesFromPayload(
      decoded,
    );
  }

  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      upsertOperatorPayoutImportPreviewSavedView(
    CoachPayoutImportPreviewHistorySavedView view, {
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_preview_saved_views',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'view_id': view.viewId,
        'name': view.name,
        'status': view.preferences.status,
        'from_created_at': view.preferences.fromCreatedAtIso,
        'to_created_at': view.preferences.toCreatedAtIso,
        'operator_id': view.preferences.operatorId,
        'visibility_scope': view.visibilityScope,
        'is_default': view.isDefault,
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-payout-import-preview-saved-view',
          ),
    );
    return _coachPayoutImportPreviewSavedViewsFromPayload(decoded);
  }

  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      deleteOperatorPayoutImportPreviewSavedView(
    String viewId, {
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_import_preview_saved_views',
        normalizedViewId,
        'delete',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      const <String, Object?>{},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-payout-import-preview-saved-view-delete',
          ),
    );
    return _coachPayoutImportPreviewSavedViewsFromPayload(decoded);
  }

  Future<List<CoachPayoutImportPreviewHistorySavedView>>
      toggleOperatorPayoutImportPreviewSavedViewFavorite(
    String viewId, {
    required bool favorite,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_import_preview_saved_views',
        normalizedViewId,
        'favorite',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{'favorite': favorite},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-payout-import-preview-saved-view-favorite',
          ),
    );
    return _coachPayoutImportPreviewSavedViewsFromPayload(decoded);
  }

  Future<String?> markOperatorPayoutImportPreviewSavedViewUsed(
    String viewId, {
    String? usedAtIso,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_import_preview_saved_views',
        normalizedViewId,
        'use',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if ((usedAtIso ?? '').trim().isNotEmpty) 'used_at': usedAtIso!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-payout-import-preview-saved-view-use',
          ),
    );
    if (decoded is! Map) {
      return null;
    }
    return (decoded['used_at'] ?? '').toString().trim().isEmpty
        ? null
        : (decoded['used_at'] ?? '').toString().trim();
  }

  Future<List<CoachPayoutImportBatchSavedView>>
      upsertOperatorPayoutImportBatchSavedView(
    CoachPayoutImportBatchSavedView view, {
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batch_saved_views',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'view_id': view.viewId,
        'name': view.name,
        'operator_id': view.preferences.operatorId,
        'visibility_scope': view.visibilityScope,
        'is_default': view.isDefault,
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-payout-import-batch-saved-view'),
    );
    return _coachPayoutImportBatchSavedViewsFromPayload(decoded);
  }

  Future<List<CoachPayoutImportBatchSavedView>>
      deleteOperatorPayoutImportBatchSavedView(
    String viewId, {
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batch_saved_views',
        normalizedViewId,
        'delete',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      const <String, Object?>{},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-payout-import-batch-saved-view-delete',
          ),
    );
    return _coachPayoutImportBatchSavedViewsFromPayload(decoded);
  }

  Future<List<CoachPayoutImportBatchSavedView>>
      toggleOperatorPayoutImportBatchSavedViewFavorite(
    String viewId, {
    required bool favorite,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batch_saved_views',
        normalizedViewId,
        'favorite',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{'favorite': favorite},
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-payout-import-batch-saved-view-favorite',
          ),
    );
    return _coachPayoutImportBatchSavedViewsFromPayload(decoded);
  }

  Future<String?> markOperatorPayoutImportBatchSavedViewUsed(
    String viewId, {
    String? usedAtIso,
    String? idempotencyKey,
  }) async {
    final normalizedViewId = viewId.trim();
    if (normalizedViewId.isEmpty) {
      throw const CoachApiException('viewId required');
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batch_saved_views',
        normalizedViewId,
        'use',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if ((usedAtIso ?? '').trim().isNotEmpty) 'used_at': usedAtIso!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey(
            'coach-ops-payout-import-batch-saved-view-use',
          ),
    );
    if (decoded is! Map) {
      return null;
    }
    return (decoded['used_at'] ?? '').toString().trim().isEmpty
        ? null
        : (decoded['used_at'] ?? '').toString().trim();
  }

  Future<CoachCrewDepartureBoardResponse> crewDepartures({
    int limit = 12,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'crew', 'departures'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachCrewDepartureBoardResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach crew departures payload');
    }
    return response;
  }

  Future<CoachCrewManifestResponse> getCrewManifest(String tripId) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'crew',
        'trips',
        tripId,
        'manifest',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachCrewManifestResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach crew manifest payload');
    }
    return response;
  }

  Future<CoachCrewBoardingResult> recordBoarding({
    required String tripId,
    required String ticketId,
    required CoachBoardingScanStatus scanStatus,
    bool offlineCaptured = false,
    String? deviceId,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'crew',
        'trips',
        tripId,
        'boardings',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'ticket_id': ticketId.trim(),
        'scan_status': coachBoardingScanStatusWireValue(scanStatus),
        'offline_captured': offlineCaptured,
        if ((deviceId ?? '').trim().isNotEmpty) 'device_id': deviceId!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey:
          idempotencyKey ?? newPaymentsIdempotencyKey('coach-crew-boarding'),
    );
    final response = CoachCrewBoardingResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach crew boarding payload');
    }
    return response;
  }

  Future<CoachPlatformBootstrap> bootstrap() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'bootstrap'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final bootstrap = CoachPlatformBootstrap.fromJson(decoded);
    if (bootstrap == null) {
      throw const CoachApiException('invalid coach bootstrap payload');
    }
    return bootstrap;
  }

  Future<CoachJourneySearchResponse> search({
    required String from,
    required String to,
    required String departureDate,
    int passengers = 1,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'search'],
      queryParameters: <String, String>{
        'from': from.trim(),
        'to': to.trim(),
        'departure_date': departureDate.trim(),
        'passengers': passengers.toString(),
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final response = CoachJourneySearchResponse.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach search payload');
    }
    return response;
  }

  Future<CoachOffer> getOffer({
    required String offerId,
    int passengers = 1,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'offers', offerId],
      queryParameters: <String, String>{
        'passengers': passengers.toString(),
      },
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final offer = CoachOffer.fromJson(decoded);
    if (offer == null) {
      throw const CoachApiException('invalid coach offer payload');
    }
    return offer;
  }

  Future<CoachHold> getHold(String holdId) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'holds', holdId],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final hold = CoachHold.fromJson(decoded);
    if (hold == null) {
      throw const CoachApiException('invalid coach hold payload');
    }
    return hold;
  }

  Future<CoachBooking> getBooking(String bookingId) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'bookings', bookingId],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final booking = CoachBooking.fromJson(decoded);
    if (booking == null) {
      throw const CoachApiException('invalid coach booking payload');
    }
    return booking;
  }

  Future<CoachTicketCoupon> getTicket(String ticketId) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'tickets', ticketId],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _getJson(uri);
    final ticket = CoachTicketCoupon.fromJson(decoded);
    if (ticket == null) {
      throw const CoachApiException('invalid coach ticket payload');
    }
    return ticket;
  }

  Future<CoachHoldDraft> createHold({
    required String offerId,
    int passengers = 1,
    List<String>? passengerIds,
    List<String>? preferredSeatNumbers,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'holds'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'offer_id': offerId.trim(),
        'passengers': passengers,
        if (passengerIds != null && passengerIds.isNotEmpty)
          'passenger_ids': passengerIds,
        if (preferredSeatNumbers != null && preferredSeatNumbers.isNotEmpty)
          'preferred_seat_numbers': preferredSeatNumbers,
      },
      idempotencyKey:
          idempotencyKey ?? newPaymentsIdempotencyKey('coach-hold-create'),
    );
    final response = CoachHoldDraft.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach hold create payload');
    }
    return response;
  }

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
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'bookings'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'offer_id': offerId.trim(),
        if ((holdId ?? '').trim().isNotEmpty) 'hold_id': holdId!.trim(),
        'passengers': passengers,
        if (passengerIds != null && passengerIds.isNotEmpty)
          'passenger_ids': passengerIds,
        if (preferredSeatNumbers != null && preferredSeatNumbers.isNotEmpty)
          'preferred_seat_numbers': preferredSeatNumbers,
        if (passengerManifests != null && passengerManifests.isNotEmpty)
          'passengers_manifest': passengerManifests
              .map((manifest) => manifest.toJson())
              .toList(growable: false),
        'payment_method': paymentMethod.trim(),
        if ((contactEmail ?? '').trim().isNotEmpty)
          'contact_email': contactEmail!.trim(),
        'accept_terms': acceptTerms,
      },
      idempotencyKey:
          idempotencyKey ?? newPaymentsIdempotencyKey('coach-booking-create'),
    );
    final response = CoachBookingDraft.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach booking create payload');
    }
    return response;
  }

  Future<CoachTicketingResult> issueTickets({
    required String bookingId,
    required String offerId,
    String? holdId,
    List<String>? passengerIds,
    List<CoachPassengerManifest>? passengerManifests,
    List<String>? deliveryChannels,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'bookings', bookingId, 'tickets'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'offer_id': offerId.trim(),
        if ((holdId ?? '').trim().isNotEmpty) 'hold_id': holdId!.trim(),
        if (passengerIds != null && passengerIds.isNotEmpty)
          'passenger_ids': passengerIds,
        if (passengerManifests != null && passengerManifests.isNotEmpty)
          'passengers_manifest': passengerManifests
              .map((manifest) => manifest.toJson())
              .toList(growable: false),
        if (deliveryChannels != null && deliveryChannels.isNotEmpty)
          'delivery_channels': deliveryChannels,
      },
      idempotencyKey:
          idempotencyKey ?? newPaymentsIdempotencyKey('coach-ticket-issue'),
    );
    final response = CoachTicketingResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach ticket issue payload');
    }
    return response;
  }

  Future<CoachRefundRequestResult> requestRefund({
    required String bookingId,
    required CoachRefundKind refundKind,
    List<String>? ticketIds,
    String? reason,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'coach', 'bookings', bookingId, 'refunds'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'refund_kind': coachRefundKindWireValue(refundKind),
        if (ticketIds != null && ticketIds.isNotEmpty) 'ticket_ids': ticketIds,
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      },
      idempotencyKey:
          idempotencyKey ?? newPaymentsIdempotencyKey('coach-refund-request'),
    );
    final response = CoachRefundRequestResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach refund request payload');
    }
    return response;
  }

  Future<CoachRebookRequestResult> requestRebook({
    required String bookingId,
    required String targetOfferId,
    List<String>? preferredSeatNumbers,
    String? reason,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'bookings',
        bookingId,
        'rebook_requests',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'target_offer_id': targetOfferId.trim(),
        if (preferredSeatNumbers != null && preferredSeatNumbers.isNotEmpty)
          'preferred_seat_numbers': preferredSeatNumbers,
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      },
      idempotencyKey:
          idempotencyKey ?? newPaymentsIdempotencyKey('coach-rebook-request'),
    );
    final response = CoachRebookRequestResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException('invalid coach rebook request payload');
    }
    return response;
  }

  Future<CoachSelfServiceReissueResult> selfServiceReissue({
    required String bookingId,
    required String targetOfferId,
    List<String>? preferredSeatNumbers,
    List<String>? deliveryChannels,
    String? paymentMethod,
    String? reason,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'bookings',
        bookingId,
        'reissue',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'target_offer_id': targetOfferId.trim(),
        if (preferredSeatNumbers != null && preferredSeatNumbers.isNotEmpty)
          'preferred_seat_numbers': preferredSeatNumbers,
        if (deliveryChannels != null && deliveryChannels.isNotEmpty)
          'delivery_channels': deliveryChannels,
        if ((paymentMethod ?? '').trim().isNotEmpty)
          'payment_method': paymentMethod!.trim(),
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      },
      idempotencyKey:
          idempotencyKey ?? newPaymentsIdempotencyKey('coach-ticket-reissue'),
    );
    final response = CoachSelfServiceReissueResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach self-service reissue payload');
    }
    return response;
  }

  Future<CoachSelfServiceReissueResult> resolveReissuePaymentFailure({
    required String bookingId,
    required String paymentMethod,
    List<String>? deliveryChannels,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'bookings',
        bookingId,
        'reissue',
        'resolve_payment_failure',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'payment_method': paymentMethod.trim(),
        if (deliveryChannels != null && deliveryChannels.isNotEmpty)
          'delivery_channels': deliveryChannels,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ticket-reissue-recovery'),
    );
    final response = CoachSelfServiceReissueResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach self-service reissue recovery payload');
    }
    return response;
  }

  Future<CoachOperatorRefundReviewResult> reviewRefundRequest({
    required String refundRequestId,
    required bool approve,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'refund_requests',
        refundRequestId,
        'review',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'decision': approve ? 'approve' : 'reject',
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-refund-review'),
    );
    final response = CoachOperatorRefundReviewResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator refund review payload');
    }
    return response;
  }

  Future<CoachOperatorChangeReviewResult> reviewChangeRequest({
    required String changeRequestId,
    required bool approve,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'change_requests',
        changeRequestId,
        'review',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'decision': approve ? 'approve' : 'reject',
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-change-review'),
    );
    final response = CoachOperatorChangeReviewResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator change review payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutRunMutationResult> createOperatorPayoutRun({
    required List<String> statementIds,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'coach', 'operator', 'payout_runs'],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'statement_ids':
            statementIds.map((value) => value.trim()).toList(growable: false),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey:
          idempotencyKey ?? newPaymentsIdempotencyKey('coach-ops-payout-run'),
    );
    final response = CoachOperatorPayoutRunMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout run payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutRunMutationResult> markOperatorPayoutRunPaid({
    required String payoutRunId,
    String? paymentReference,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_runs',
        payoutRunId,
        'mark_paid',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        if ((paymentReference ?? '').trim().isNotEmpty)
          'payment_reference': paymentReference!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-payout-run-paid'),
    );
    final response = CoachOperatorPayoutRunMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout run paid payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportMutationResult> createOperatorPayoutImport({
    required String payoutRunId,
    required String importSource,
    required String externalStatus,
    String? paymentReference,
    String? externalReference,
    String? importedAtIso,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_runs',
        payoutRunId,
        'imports',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'import_source': importSource.trim(),
        'external_status': externalStatus.trim(),
        if ((paymentReference ?? '').trim().isNotEmpty)
          'payment_reference': paymentReference!.trim(),
        if ((externalReference ?? '').trim().isNotEmpty)
          'external_reference': externalReference!.trim(),
        if ((importedAtIso ?? '').trim().isNotEmpty)
          'imported_at': importedAtIso!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-payout-import'),
    );
    final response = CoachOperatorPayoutImportMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout import payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportBatchMutationResult>
      createOperatorPayoutImportBatch({
    required String importSource,
    required String reportName,
    String reportFormat = 'csv',
    required String reportBody,
    String? reworkOfBatchId,
    String? expectedPreviewToken,
    bool dryRun = false,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batches',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'import_source': importSource.trim(),
        'report_name': reportName.trim(),
        'report_format': reportFormat.trim(),
        'report_body': reportBody,
        if ((reworkOfBatchId ?? '').trim().isNotEmpty)
          'rework_of_batch_id': reworkOfBatchId!.trim(),
        if ((expectedPreviewToken ?? '').trim().isNotEmpty)
          'expected_preview_token': expectedPreviewToken!.trim(),
        if (dryRun) 'dry_run': true,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-payout-import-batch'),
    );
    final response =
        CoachOperatorPayoutImportBatchMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout import batch payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutImportBatchMutationResult>
      uploadOperatorPayoutImportBatchFile({
    required String importSource,
    String? reportName,
    String reportFormat = 'csv',
    required Uint8List fileBytes,
    required String fileName,
    String? reworkOfBatchId,
    String? expectedPreviewToken,
    bool dryRun = false,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'coach',
        'operator',
        'payout_import_batches',
        'upload',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final trimmedFileName =
        fileName.trim().isEmpty ? 'payout_import_report.csv' : fileName.trim();
    final decoded = await _postMultipart(
      uri,
      fields: <String, String>{
        'import_source': importSource.trim(),
        if ((reportName ?? '').trim().isNotEmpty)
          'report_name': reportName!.trim(),
        if (reportFormat.trim().isNotEmpty)
          'report_format': reportFormat.trim(),
        if ((reworkOfBatchId ?? '').trim().isNotEmpty)
          'rework_of_batch_id': reworkOfBatchId!.trim(),
        if ((expectedPreviewToken ?? '').trim().isNotEmpty)
          'expected_preview_token': expectedPreviewToken!.trim(),
        if (dryRun) 'dry_run': 'true',
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      fileFieldName: 'file',
      fileName: trimmedFileName,
      fileBytes: fileBytes,
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-payout-import-batch-upload'),
    );
    final response =
        CoachOperatorPayoutImportBatchMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout import batch payload');
    }
    return response;
  }

  Future<CoachOperatorPayoutExportMutationResult>
      createOperatorPayoutRunExport({
    required String payoutRunId,
    required String exportFormat,
    String? note,
    String? idempotencyKey,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'coach',
        'operator',
        'payout_runs',
        payoutRunId,
        'exports',
      ],
    );
    if (uri == null) {
      throw const CoachApiException('secure base URL required');
    }
    final decoded = await _postJson(
      uri,
      <String, Object?>{
        'export_format': exportFormat.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      idempotencyKey: idempotencyKey ??
          newPaymentsIdempotencyKey('coach-ops-payout-run-export'),
    );
    final response = CoachOperatorPayoutExportMutationResult.fromJson(decoded);
    if (response == null) {
      throw const CoachApiException(
          'invalid coach operator payout export payload');
    }
    return response;
  }

  Uri? resolvePayoutExportUri(String downloadPath) {
    return _resolveCoachDownloadUri(downloadPath);
  }

  Uri? resolvePayoutImportReportUri(String downloadPath) {
    return _resolveCoachDownloadUri(downloadPath);
  }

  Future<String> fetchPayoutImportReportBody(String downloadPath) async {
    final uri = resolvePayoutImportReportUri(downloadPath);
    if (uri == null) {
      throw const CoachApiException('invalid coach payout import report URL');
    }
    return _getText(uri);
  }

  Uri? resolveTicketArtifactUri(String downloadPath) {
    return _resolveCoachDownloadUri(downloadPath);
  }

  /// Downloads the raw bytes of a coach ticket artifact (wallet pass, PDF,
  /// QR SVG) via [/downloads/coach/tickets/:artifact_name]. Verifies that
  /// the response content-type and length match what the issuing API said
  /// the artifact would be — a defensive guard against a TLS-terminator
  /// rewriting the body or a CDN serving a stale wrong-kind cache entry.
  Future<Uint8List> fetchTicketArtifactBytes(CoachTicketArtifact artifact) async {
    final uri = resolveTicketArtifactUri(artifact.downloadPath);
    if (uri == null) {
      throw const CoachApiException('invalid coach ticket artifact URL');
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final response =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CoachApiException(
          _coachApiErrorDetail(response.body) ?? 'coach ticket artifact fetch failed',
          statusCode: response.statusCode,
        );
      }
      final contentType = response.headers['content-type']?.trim() ?? '';
      // mime_type from the API is e.g. "application/vnd.apple.pkpass"; the
      // response header may add "; charset=…" for text bodies. Compare on
      // the base type only.
      final baseContentType = contentType.split(';').first.trim().toLowerCase();
      final expectedType = artifact.mimeType.split(';').first.trim().toLowerCase();
      if (baseContentType.isNotEmpty &&
          expectedType.isNotEmpty &&
          baseContentType != expectedType) {
        throw CoachApiException(
          'coach ticket artifact content-type mismatch: got "$baseContentType", expected "$expectedType"',
        );
      }
      // Length sanity: the API claims a specific content_length_bytes when
      // it issues the artifact metadata. We tolerate +/-0 only — any drift
      // means the bytes weren't the ones we authorized for delivery.
      // Skipped when the API reported -1 (length unknown) to stay forward
      // compatible with streamed artifacts.
      if (artifact.contentLengthBytes >= 0 &&
          response.bodyBytes.length != artifact.contentLengthBytes) {
        throw CoachApiException(
          'coach ticket artifact length mismatch: got ${response.bodyBytes.length}, expected ${artifact.contentLengthBytes}',
        );
      }
      return response.bodyBytes;
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  Uri? _resolveCoachDownloadUri(String downloadPath) {
    final normalizedPath = downloadPath.trim();
    if (normalizedPath.isEmpty) return null;
    final parsed = Uri.tryParse(normalizedPath);
    if (parsed != null && parsed.hasScheme) {
      final scheme = parsed.scheme.toLowerCase();
      if (scheme == 'https' || scheme == 'http') {
        return parsed;
      }
      return null;
    }
    if (!normalizedPath.startsWith('/')) {
      return null;
    }
    final base = Uri.tryParse(baseUrl);
    if (base == null || base.host.isEmpty || !base.hasScheme) {
      return null;
    }
    final scheme = base.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      return null;
    }
    return base.resolveUri(Uri.parse(normalizedPath));
  }

  Future<Object?> _getJson(Uri uri) async {
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final response =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CoachApiException(
          _coachApiErrorDetail(response.body) ?? 'coach request failed',
          statusCode: response.statusCode,
        );
      }
      if (response.bodyBytes.isEmpty) return null;
      return jsonDecode(response.body);
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  Future<String> _getText(Uri uri) async {
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final response =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CoachApiException(
          _coachApiErrorDetail(response.body) ?? 'coach request failed',
          statusCode: response.statusCode,
        );
      }
      return utf8.decode(response.bodyBytes);
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  Future<Object?> _postJson(
    Uri uri,
    Map<String, Object?> payload, {
    required String idempotencyKey,
  }) async {
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] = idempotencyKey.trim();
      final response = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CoachApiException(
          _coachApiErrorDetail(response.body) ?? 'coach request failed',
          statusCode: response.statusCode,
        );
      }
      if (response.bodyBytes.isEmpty) return null;
      return jsonDecode(response.body);
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  Future<Object?> _postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    required String fileFieldName,
    required String fileName,
    required Uint8List fileBytes,
    required String idempotencyKey,
  }) async {
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(
        baseUrl,
        extra: <String, String>{
          'Idempotency-Key': idempotencyKey.trim(),
        },
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(headers);
      request.fields.addAll(fields);
      request.files.add(
        http.MultipartFile.fromBytes(
          fileFieldName,
          fileBytes,
          filename: fileName,
        ),
      );
      final streamed = await client.send(request).timeout(_requestTimeout);
      final response =
          await http.Response.fromStream(streamed).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CoachApiException(
          _coachApiErrorDetail(response.body) ?? 'coach request failed',
          statusCode: response.statusCode,
        );
      }
      if (response.bodyBytes.isEmpty) return null;
      return jsonDecode(response.body);
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }
}
