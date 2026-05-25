import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../base_url.dart';

enum RideTripStatus {
  idle,
  quoteShown,
  rideRequested,
  matching,
  driverAssigned,
  driverArriving,
  driverArrived,
  tripStarted,
  tripInProgress,
  tripCompleted,
  canceled,
  paymentFailed,
}

String rideTripStatusWireValue(RideTripStatus status) {
  switch (status) {
    case RideTripStatus.idle:
      return 'idle';
    case RideTripStatus.quoteShown:
      return 'quote_shown';
    case RideTripStatus.rideRequested:
      return 'ride_requested';
    case RideTripStatus.matching:
      return 'matching';
    case RideTripStatus.driverAssigned:
      return 'driver_assigned';
    case RideTripStatus.driverArriving:
      return 'driver_arriving';
    case RideTripStatus.driverArrived:
      return 'driver_arrived';
    case RideTripStatus.tripStarted:
      return 'trip_started';
    case RideTripStatus.tripInProgress:
      return 'trip_in_progress';
    case RideTripStatus.tripCompleted:
      return 'trip_completed';
    case RideTripStatus.canceled:
      return 'cancelled';
    case RideTripStatus.paymentFailed:
      return 'payment_failed';
  }
}

RideTripStatus? rideTripStatusFromWire(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'idle':
      return RideTripStatus.idle;
    case 'quote_shown':
      return RideTripStatus.quoteShown;
    case 'ride_requested':
      return RideTripStatus.rideRequested;
    case 'matching':
      return RideTripStatus.matching;
    case 'searching':
      return RideTripStatus.matching;
    case 'driver_assigned':
      return RideTripStatus.driverAssigned;
    case 'driver_arriving':
      return RideTripStatus.driverArriving;
    case 'driver_arrived':
      return RideTripStatus.driverArrived;
    case 'trip_started':
      return RideTripStatus.tripStarted;
    case 'trip_in_progress':
      return RideTripStatus.tripInProgress;
    case 'in_progress':
      return RideTripStatus.tripInProgress;
    case 'trip_completed':
      return RideTripStatus.tripCompleted;
    case 'completed':
      return RideTripStatus.tripCompleted;
    case 'cancelled':
    case 'canceled':
      return RideTripStatus.canceled;
    case 'payment_failed':
      return RideTripStatus.paymentFailed;
    default:
      return null;
  }
}

bool rideTripStatusIsTerminal(RideTripStatus status) {
  return status == RideTripStatus.tripCompleted ||
      status == RideTripStatus.canceled;
}

bool rideTripStatusCanTransition({
  required RideTripStatus from,
  required RideTripStatus to,
}) {
  if (from == to) return true;
  switch (from) {
    case RideTripStatus.idle:
      return to == RideTripStatus.quoteShown;
    case RideTripStatus.quoteShown:
      return to == RideTripStatus.idle || to == RideTripStatus.rideRequested;
    case RideTripStatus.rideRequested:
      return to == RideTripStatus.matching || to == RideTripStatus.canceled;
    case RideTripStatus.matching:
      return to == RideTripStatus.driverAssigned ||
          to == RideTripStatus.canceled;
    case RideTripStatus.driverAssigned:
      return to == RideTripStatus.driverArriving ||
          to == RideTripStatus.canceled;
    case RideTripStatus.driverArriving:
      return to == RideTripStatus.driverArrived ||
          to == RideTripStatus.canceled;
    case RideTripStatus.driverArrived:
      return to == RideTripStatus.tripStarted || to == RideTripStatus.canceled;
    case RideTripStatus.tripStarted:
      return to == RideTripStatus.tripInProgress ||
          to == RideTripStatus.canceled;
    case RideTripStatus.tripInProgress:
      return to == RideTripStatus.tripCompleted ||
          to == RideTripStatus.paymentFailed;
    case RideTripStatus.paymentFailed:
      return to == RideTripStatus.tripCompleted ||
          to == RideTripStatus.canceled;
    case RideTripStatus.tripCompleted:
      return false;
    case RideTripStatus.canceled:
      return false;
  }
}

bool rideTripStatusRiderCanCancel(RideTripStatus status) {
  switch (status) {
    case RideTripStatus.rideRequested:
    case RideTripStatus.matching:
    case RideTripStatus.driverAssigned:
    case RideTripStatus.driverArriving:
    case RideTripStatus.driverArrived:
    case RideTripStatus.tripStarted:
      return true;
    case RideTripStatus.idle:
    case RideTripStatus.quoteShown:
    case RideTripStatus.tripInProgress:
    case RideTripStatus.tripCompleted:
    case RideTripStatus.canceled:
    case RideTripStatus.paymentFailed:
      return false;
  }
}

class RideTrip {
  final String rideId;
  final String? offerId;
  final String pickup;
  final String destination;
  final String? pickupLabel;
  final String? destinationLabel;
  final double? pickupLat;
  final double? pickupLon;
  final double? destinationLat;
  final double? destinationLon;
  final String rideClass;
  final String driverName;
  final String carPlate;
  final int etaMinutes;
  final int fareEstimateCents;
  final RideTripStatus status;
  final String? cancelReasonCode;
  final String createdAtIso;
  final String lastUpdatedAtIso;
  final String? assignedAtIso;
  final String? arrivingAtIso;
  final String? arrivedAtIso;
  final String? startedAtIso;
  final String? completedAtIso;

  const RideTrip({
    required this.rideId,
    this.offerId,
    required this.pickup,
    required this.destination,
    this.pickupLabel,
    this.destinationLabel,
    this.pickupLat,
    this.pickupLon,
    this.destinationLat,
    this.destinationLon,
    required this.rideClass,
    required this.driverName,
    required this.carPlate,
    required this.etaMinutes,
    required this.fareEstimateCents,
    required this.status,
    this.cancelReasonCode,
    required this.createdAtIso,
    required this.lastUpdatedAtIso,
    this.assignedAtIso,
    this.arrivingAtIso,
    this.arrivedAtIso,
    this.startedAtIso,
    this.completedAtIso,
  });

  RideTrip copyWith({
    RideTripStatus? status,
    String? lastUpdatedAtIso,
    int? etaMinutes,
  }) {
    return RideTrip(
      rideId: rideId,
      offerId: offerId,
      pickup: pickup,
      destination: destination,
      pickupLabel: pickupLabel,
      destinationLabel: destinationLabel,
      pickupLat: pickupLat,
      pickupLon: pickupLon,
      destinationLat: destinationLat,
      destinationLon: destinationLon,
      rideClass: rideClass,
      driverName: driverName,
      carPlate: carPlate,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      fareEstimateCents: fareEstimateCents,
      status: status ?? this.status,
      cancelReasonCode: cancelReasonCode,
      createdAtIso: createdAtIso,
      lastUpdatedAtIso: lastUpdatedAtIso ?? this.lastUpdatedAtIso,
      assignedAtIso: assignedAtIso,
      arrivingAtIso: arrivingAtIso,
      arrivedAtIso: arrivedAtIso,
      startedAtIso: startedAtIso,
      completedAtIso: completedAtIso,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ride_id': rideId,
      'offer_id': offerId,
      'pickup': pickup,
      'destination': destination,
      'pickup_label': pickupLabel ?? pickup,
      'destination_label': destinationLabel ?? destination,
      'pickup_lat': pickupLat,
      'pickup_lon': pickupLon,
      'destination_lat': destinationLat,
      'destination_lon': destinationLon,
      'ride_class': rideClass,
      'driver_name': driverName,
      'car_plate': carPlate,
      'eta_minutes': etaMinutes,
      'fare_estimate_cents': fareEstimateCents,
      'status': rideTripStatusWireValue(status),
      'cancel_reason_code': cancelReasonCode,
      'created_at': createdAtIso,
      'last_updated_at': lastUpdatedAtIso,
      'assigned_at': assignedAtIso,
      'arriving_at': arrivingAtIso,
      'arrived_at': arrivedAtIso,
      'started_at': startedAtIso,
      'completed_at': completedAtIso,
    };
  }

  static RideTrip? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rideId = (raw['ride_id'] ?? '').toString().trim();
    final offerId = (raw['offer_id'] ?? '').toString().trim();
    final pickup = (raw['pickup'] ?? '').toString().trim();
    final destination = (raw['destination'] ?? '').toString().trim();
    final pickupLabel = (raw['pickup_label'] ?? '').toString().trim();
    final destinationLabel = (raw['destination_label'] ?? '').toString().trim();
    final rideClass = (raw['ride_class'] ?? '').toString().trim();
    final driverName = (raw['driver_name'] ?? '').toString().trim();
    final carPlate = (raw['car_plate'] ?? '').toString().trim();
    final status = rideTripStatusFromWire((raw['status'] ?? '').toString());
    final cancelReasonCode =
        (raw['cancel_reason_code'] ?? '').toString().trim();
    final createdAtIso = (raw['created_at'] ?? '').toString().trim();
    final lastUpdatedAtIso = (raw['last_updated_at'] ?? '').toString().trim();
    final assignedAtIso = (raw['assigned_at'] ?? '').toString().trim();
    final arrivingAtIso = (raw['arriving_at'] ?? '').toString().trim();
    final arrivedAtIso = (raw['arrived_at'] ?? '').toString().trim();
    final startedAtIso = (raw['started_at'] ?? '').toString().trim();
    final completedAtIso = (raw['completed_at'] ?? '').toString().trim();
    final etaMinutes = raw['eta_minutes'];
    final fareEstimateCents = raw['fare_estimate_cents'];
    final pickupLat = _jsonDouble(raw['pickup_lat']) ??
        _jsonDouble((raw['pickup_location'] as Map?)?['lat']);
    final pickupLon = _jsonDouble(raw['pickup_lon']) ??
        _jsonDouble((raw['pickup_location'] as Map?)?['lon']);
    final destinationLat = _jsonDouble(raw['destination_lat']) ??
        _jsonDouble((raw['destination_location'] as Map?)?['lat']);
    final destinationLon = _jsonDouble(raw['destination_lon']) ??
        _jsonDouble((raw['destination_location'] as Map?)?['lon']);

    if (rideId.isEmpty ||
        pickup.isEmpty ||
        destination.isEmpty ||
        rideClass.isEmpty ||
        driverName.isEmpty ||
        carPlate.isEmpty ||
        createdAtIso.isEmpty ||
        lastUpdatedAtIso.isEmpty ||
        status == null ||
        etaMinutes is! int ||
        fareEstimateCents is! int) {
      return null;
    }

    if (etaMinutes < 0 || fareEstimateCents < 0) {
      return null;
    }

    return RideTrip(
      rideId: rideId,
      offerId: offerId.isEmpty ? null : offerId,
      pickup: pickup,
      destination: destination,
      pickupLabel: pickupLabel.isEmpty ? pickup : pickupLabel,
      destinationLabel:
          destinationLabel.isEmpty ? destination : destinationLabel,
      pickupLat: pickupLat,
      pickupLon: pickupLon,
      destinationLat: destinationLat,
      destinationLon: destinationLon,
      rideClass: rideClass,
      driverName: driverName,
      carPlate: carPlate,
      etaMinutes: etaMinutes,
      fareEstimateCents: fareEstimateCents,
      status: status,
      cancelReasonCode: cancelReasonCode.isEmpty ? null : cancelReasonCode,
      createdAtIso: createdAtIso,
      lastUpdatedAtIso: lastUpdatedAtIso,
      assignedAtIso: assignedAtIso.isEmpty ? null : assignedAtIso,
      arrivingAtIso: arrivingAtIso.isEmpty ? null : arrivingAtIso,
      arrivedAtIso: arrivedAtIso.isEmpty ? null : arrivedAtIso,
      startedAtIso: startedAtIso.isEmpty ? null : startedAtIso,
      completedAtIso: completedAtIso.isEmpty ? null : completedAtIso,
    );
  }
}

double? _jsonDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

const String _rideHistoryScopedKeyPrefix = 'ride_hailing.history.v1.';
const String _rideActiveScopedKeyPrefix = 'ride_hailing.active.v1.';
const String _rideUnknownScope = 'unknown';
const int _rideHistoryMaxEntries = 50;

String _rideScope(String rawBaseUrl) {
  final normalized = normalizeSecureApiBaseUrl(rawBaseUrl.trim()) ?? '';
  if (normalized.isEmpty) return _rideUnknownScope;
  return Uri.parse(normalized).origin;
}

String _rideHistoryScopedKey(String scope) =>
    '$_rideHistoryScopedKeyPrefix$scope';
String _rideActiveScopedKey(String scope) =>
    '$_rideActiveScopedKeyPrefix$scope';

Future<List<RideTrip>> loadRideHailingHistory({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope =
      _rideScope(baseUrlOverride ?? (prefs.getString('base_url') ?? ''));
  final raw = (prefs.getString(_rideHistoryScopedKey(scope)) ?? '').trim();
  if (raw.isEmpty) {
    return const <RideTrip>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <RideTrip>[];
    final parsed = decoded
        .map(RideTrip.fromJson)
        .whereType<RideTrip>()
        .toList(growable: false);
    return parsed;
  } catch (_) {
    return const <RideTrip>[];
  }
}

Future<void> saveRideHailingHistory(
  List<RideTrip> trips, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope =
      _rideScope(baseUrlOverride ?? (prefs.getString('base_url') ?? ''));
  final normalized = trips.take(_rideHistoryMaxEntries).toList(growable: false);
  await prefs.setString(
    _rideHistoryScopedKey(scope),
    jsonEncode(normalized.map((trip) => trip.toJson()).toList(growable: false)),
  );
}

Future<RideTrip?> loadActiveRideHailingTrip({
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope =
      _rideScope(baseUrlOverride ?? (prefs.getString('base_url') ?? ''));
  final raw = (prefs.getString(_rideActiveScopedKey(scope)) ?? '').trim();
  if (raw.isEmpty) return null;
  try {
    return RideTrip.fromJson(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

Future<void> saveActiveRideHailingTrip(
  RideTrip? trip, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final scope =
      _rideScope(baseUrlOverride ?? (prefs.getString('base_url') ?? ''));
  final key = _rideActiveScopedKey(scope);
  if (trip == null) {
    await prefs.remove(key);
    return;
  }
  await prefs.setString(key, jsonEncode(trip.toJson()));
}

Future<void> upsertRideHailingHistoryTrip(
  RideTrip trip, {
  SharedPreferences? sp,
  String? baseUrlOverride,
}) async {
  final history = await loadRideHailingHistory(
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
  final next = <RideTrip>[trip];
  for (final existing in history) {
    if (existing.rideId == trip.rideId) continue;
    next.add(existing);
  }
  await saveRideHailingHistory(
    next,
    sp: sp,
    baseUrlOverride: baseUrlOverride,
  );
}
