import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../device_id.dart';
import '../payments/payments_attestation.dart';
import '../payments/payments_idempotency.dart';
import '../privacy_redaction.dart';
import '../session_cookie_store.dart';
import 'ride_hailing_store.dart';
import 'ride_platform_contracts.dart';

const bool _rideDiagnosticLogs =
    bool.fromEnvironment('SHAMELL_DIAGNOSTIC_BOOTSTRAP_LOGS');
const int _ridePlaceLabelMaxChars = 80;

void _rideDiagnosticLog(String message) {
  if (!_rideDiagnosticLogs) return;
  debugPrint('RIDE_DIAG: $message');
}

String compactRidePlaceLabel(String raw,
    {int maxChars = _ridePlaceLabelMaxChars}) {
  final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty || normalized.length <= maxChars) {
    return normalized;
  }

  final parts = normalized
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return _truncateRidePlaceLabel(normalized, maxChars);
  }

  final deduped = <String>[];
  for (final part in parts) {
    final exists = deduped.any(
      (existing) => existing.toLowerCase() == part.toLowerCase(),
    );
    if (!exists) {
      deduped.add(part);
    }
  }

  String joinParts(List<String> values) => values.join(', ');

  final fullJoined = joinParts(deduped);
  if (fullJoined.length <= maxChars) {
    return fullJoined;
  }

  final candidates = <String>[
    if (deduped.length >= 2) joinParts(deduped.take(2).toList(growable: false)),
    if (deduped.length >= 3)
      joinParts(<String>[deduped.first, deduped[deduped.length - 2]]),
    if (deduped.length >= 4)
      joinParts(
          <String>[deduped.first, deduped[1], deduped[deduped.length - 2]]),
    deduped.first,
  ];

  for (final candidate in candidates) {
    final compact = candidate.trim();
    if (compact.isNotEmpty && compact.length <= maxChars) {
      return compact;
    }
  }

  return _truncateRidePlaceLabel(deduped.first, maxChars);
}

String _truncateRidePlaceLabel(String value, int maxChars) {
  final normalized = value.trim();
  if (normalized.length <= maxChars) {
    return normalized;
  }
  if (maxChars <= 3) {
    return normalized.substring(0, maxChars);
  }
  return '${normalized.substring(0, maxChars - 3).trimRight()}...';
}

@visibleForTesting
List<({String? event, String data})> parseRideSsePayload(String payload) {
  final events = <({String? event, String data})>[];
  String? currentEvent;
  final dataLines = <String>[];
  for (final line in const LineSplitter().convert(payload)) {
    if (line.isEmpty) {
      if (dataLines.isNotEmpty) {
        events.add((event: currentEvent, data: dataLines.join('\n')));
      }
      currentEvent = null;
      dataLines.clear();
      continue;
    }
    if (line.startsWith(':')) {
      continue;
    }
    if (line.startsWith('event:')) {
      currentEvent = line.substring(6).trim();
      continue;
    }
    if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    }
  }
  if (dataLines.isNotEmpty) {
    events.add((event: currentEvent, data: dataLines.join('\n')));
  }
  return events;
}

class RideApiException implements Exception {
  final String detail;
  final int? statusCode;

  const RideApiException(this.detail, {this.statusCode});

  @override
  String toString() => detail;
}

String? _rideApiErrorDetail(String body) {
  final normalized = body.trim();
  if (normalized.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(normalized);
    if (decoded is Map) {
      for (final key in const ['detail', 'message', 'error']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
  } catch (_) {}
  return normalized.isEmpty ? null : normalized;
}

class RideGeoPoint {
  final double lat;
  final double lon;

  const RideGeoPoint({
    required this.lat,
    required this.lon,
  });
}

class RideSearchPlace {
  final String displayName;
  final RideGeoPoint point;

  const RideSearchPlace({
    required this.displayName,
    required this.point,
  });
}

enum RidePlaceSearchStatus { ok, unavailable }

class RidePlaceSearchResponse {
  final List<RideSearchPlace> places;
  final RidePlaceSearchStatus status;

  const RidePlaceSearchResponse({
    required this.places,
    required this.status,
  });
}

class RideRouteQuote {
  final int distanceMeters;
  final int etaSeconds;
  final int trafficDelaySeconds;
  final List<RideGeoPoint> points;

  const RideRouteQuote({
    required this.distanceMeters,
    required this.etaSeconds,
    required this.trafficDelaySeconds,
    required this.points,
  });
}

class RideTrafficSnapshot {
  final int currentSpeedKmh;
  final int freeFlowSpeedKmh;
  final int currentTravelTimeSeconds;
  final int freeFlowTravelTimeSeconds;
  final int radiusMeters;

  const RideTrafficSnapshot({
    required this.currentSpeedKmh,
    required this.freeFlowSpeedKmh,
    required this.currentTravelTimeSeconds,
    required this.freeFlowTravelTimeSeconds,
    required this.radiusMeters,
  });
}

class RideTomTomQuote {
  final RideSearchPlace pickup;
  final RideSearchPlace destination;
  final RideRouteQuote route;
  final RideTrafficSnapshot? trafficAtPickup;

  const RideTomTomQuote({
    required this.pickup,
    required this.destination,
    required this.route,
    this.trafficAtPickup,
  });
}

class RideTrackingEvent {
  final int eventId;
  final String eventKind;
  final RideTripStatus? status;
  final String? actorAccountId;
  final RideGeoPoint? location;
  final int? accuracyMeters;
  final int? speedKmh;
  final int? headingDegrees;
  final String? note;
  final String createdAtIso;

  const RideTrackingEvent({
    required this.eventId,
    required this.eventKind,
    required this.status,
    required this.actorAccountId,
    required this.location,
    required this.accuracyMeters,
    required this.speedKmh,
    required this.headingDegrees,
    required this.note,
    required this.createdAtIso,
  });
}

class RideLiveTrackingSnapshot {
  final RideTrip ride;
  final RideTrackingEvent? latestDriverLocation;
  final List<RideTrackingEvent> timeline;

  const RideLiveTrackingSnapshot({
    required this.ride,
    required this.latestDriverLocation,
    required this.timeline,
  });
}

class RideDriverLocationReceipt {
  final String rideId;
  final RideTripStatus? status;
  final RideGeoPoint location;
  final int? accuracyMeters;
  final int? speedKmh;
  final int? headingDegrees;

  const RideDriverLocationReceipt({
    required this.rideId,
    required this.status,
    required this.location,
    required this.accuracyMeters,
    required this.speedKmh,
    required this.headingDegrees,
  });
}

class RidePlatformBootstrap {
  final String version;
  final List<String> surfaces;
  final List<String> serviceClasses;
  final List<String> riderLifecycleStates;
  final List<String> riderWalletBuckets;
  final List<String> driverLedgerBalances;
  final List<String> operatorRoles;
  final String mapDisplayStack;
  final String mapRoutingStack;

  const RidePlatformBootstrap({
    required this.version,
    required this.surfaces,
    required this.serviceClasses,
    required this.riderLifecycleStates,
    required this.riderWalletBuckets,
    required this.driverLedgerBalances,
    required this.operatorRoles,
    required this.mapDisplayStack,
    required this.mapRoutingStack,
  });
}

class RideMobilityApi {
  static const Duration _requestTimeout = Duration(seconds: 15);

  final String baseUrl;
  final http.Client? _httpClient;

  const RideMobilityApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  Stream<String> activeTripUpdateStream() {
    return _rideEventStream(
      pathSegments: const <String>['me', 'rides', 'trips', 'active', 'stream'],
    );
  }

  Stream<String> driverUpdateStream() {
    return _rideEventStream(
      pathSegments: const <String>['me', 'rides', 'driver', 'stream'],
    );
  }

  Stream<String> operatorUpdateStream() {
    return _rideEventStream(
      pathSegments: const <String>['me', 'rides', 'operator', 'stream'],
    );
  }

  Stream<String> _rideEventStream({
    required List<String> pathSegments,
  }) async* {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: pathSegments,
    );
    if (uri == null) {
      return;
    }

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Accept'] = 'text/event-stream';
      final request = http.Request('GET', uri)..headers.addAll(headers);
      final resp = await client.send(request).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final body = await resp.stream.bytesToString();
        _rideDiagnosticLog(
          'rideEventStream path=${uri.path} status=${resp.statusCode} body=${shamellPrivacySafePayloadSummary(body)}',
        );
        throw StateError('ride stream unavailable');
      }

      String? currentEvent;
      final dataLines = <String>[];
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (dataLines.isNotEmpty) {
            final eventName = (currentEvent ?? 'message').trim();
            final payload = dataLines.join('\n');
            if (payload.isNotEmpty && eventName != 'heartbeat') {
              yield payload;
            }
          }
          currentEvent = null;
          dataLines.clear();
          continue;
        }
        if (line.startsWith(':')) {
          continue;
        }
        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
          continue;
        }
        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        }
      }
      if (dataLines.isNotEmpty) {
        final eventName = (currentEvent ?? 'message').trim();
        final payload = dataLines.join('\n');
        if (payload.isNotEmpty && eventName != 'heartbeat') {
          yield payload;
        }
      }
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  Future<RidePlaceSearchResponse> searchWithStatus({
    required String query,
    RideGeoPoint? near,
    int limit = 5,
  }) async {
    final q = query.trim();
    if (q.length < 2) {
      return const RidePlaceSearchResponse(
        places: <RideSearchPlace>[],
        status: RidePlaceSearchStatus.ok,
      );
    }

    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'search'],
      queryParameters: <String, String>{
        'q': q,
        'limit': limit.clamp(1, 10).toString(),
        if (near != null) ...<String, String>{
          'lat': near.lat.toStringAsFixed(6),
          'lon': near.lon.toStringAsFixed(6),
        },
      },
    );
    if (uri == null) {
      return const RidePlaceSearchResponse(
        places: <RideSearchPlace>[],
        status: RidePlaceSearchStatus.unavailable,
      );
    }

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const RidePlaceSearchResponse(
          places: <RideSearchPlace>[],
          status: RidePlaceSearchStatus.unavailable,
        );
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) {
        return const RidePlaceSearchResponse(
          places: <RideSearchPlace>[],
          status: RidePlaceSearchStatus.unavailable,
        );
      }
      final out = <RideSearchPlace>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final display =
            compactRidePlaceLabel((item['display_name'] ?? '').toString());
        final lat = item['lat'];
        final lon = item['lon'];
        if (display.isEmpty || lat is! num || lon is! num) continue;
        final p = RideGeoPoint(
          lat: lat.toDouble(),
          lon: lon.toDouble(),
        );
        if (!_isValidPoint(p)) continue;
        out.add(RideSearchPlace(displayName: display, point: p));
        if (out.length >= limit.clamp(1, 10)) break;
      }
      return RidePlaceSearchResponse(
        places: out,
        status: RidePlaceSearchStatus.ok,
      );
    } catch (_) {
      return const RidePlaceSearchResponse(
        places: <RideSearchPlace>[],
        status: RidePlaceSearchStatus.unavailable,
      );
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<List<RideSearchPlace>> search({
    required String query,
    RideGeoPoint? near,
    int limit = 5,
  }) async {
    final result = await searchWithStatus(
      query: query,
      near: near,
      limit: limit,
    );
    return result.places;
  }

  Future<String?> reverseGeocode({
    required RideGeoPoint point,
  }) async {
    if (!_isValidPoint(point)) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'geo', 'reverse'],
      queryParameters: <String, String>{
        'lat': point.lat.toStringAsFixed(6),
        'lon': point.lon.toStringAsFixed(6),
      },
    );
    if (uri == null) return null;

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return null;
      final displayName =
          compactRidePlaceLabel((decoded['display_name'] ?? '').toString());
      if (displayName.isNotEmpty) {
        return displayName;
      }
      final name = compactRidePlaceLabel((decoded['name'] ?? '').toString());
      if (name.isNotEmpty) {
        return name;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideRouteQuote?> route({
    required RideGeoPoint from,
    required RideGeoPoint to,
  }) async {
    if (!_isValidPoint(from) || !_isValidPoint(to)) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'route'],
      queryParameters: <String, String>{
        'from_lat': from.lat.toStringAsFixed(6),
        'from_lon': from.lon.toStringAsFixed(6),
        'to_lat': to.lat.toStringAsFixed(6),
        'to_lon': to.lon.toStringAsFixed(6),
      },
    );
    if (uri == null) return null;

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return null;
      final distance = _parseInt(decoded['distance_m']) ?? 0;
      final eta = _parseInt(decoded['eta_s']) ?? 0;
      final trafficDelay = _parseInt(decoded['traffic_delay_s']) ?? 0;
      final pointsRaw = decoded['points'];
      final points = <RideGeoPoint>[];
      if (pointsRaw is List) {
        for (final point in pointsRaw) {
          if (point is! Map) continue;
          final lat = point['lat'];
          final lon = point['lon'];
          if (lat is! num || lon is! num) continue;
          final parsed = RideGeoPoint(lat: lat.toDouble(), lon: lon.toDouble());
          if (_isValidPoint(parsed)) {
            points.add(parsed);
          }
        }
      }
      return RideRouteQuote(
        distanceMeters: distance < 0 ? 0 : distance,
        etaSeconds: eta < 0 ? 0 : eta,
        trafficDelaySeconds: trafficDelay < 0 ? 0 : trafficDelay,
        points: points,
      );
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTrafficSnapshot?> traffic({
    required RideGeoPoint at,
    int radiusMeters = 2000,
  }) async {
    if (!_isValidPoint(at)) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'traffic'],
      queryParameters: <String, String>{
        'lat': at.lat.toStringAsFixed(6),
        'lon': at.lon.toStringAsFixed(6),
        'radius_m': radiusMeters.clamp(250, 10000).toString(),
      },
    );
    if (uri == null) return null;

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return null;
      return RideTrafficSnapshot(
        currentSpeedKmh:
            (_parseInt(decoded['current_speed_kmh']) ?? 0).clamp(0, 260),
        freeFlowSpeedKmh:
            (_parseInt(decoded['free_flow_speed_kmh']) ?? 0).clamp(0, 260),
        currentTravelTimeSeconds:
            (_parseInt(decoded['current_travel_time_s']) ?? 0).clamp(0, 86400),
        freeFlowTravelTimeSeconds:
            (_parseInt(decoded['free_flow_travel_time_s']) ?? 0)
                .clamp(0, 86400),
        radiusMeters:
            (_parseInt(decoded['radius_m']) ?? radiusMeters).clamp(250, 10000),
      );
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTomTomQuote?> quoteByText({
    required String pickupQuery,
    required String destinationQuery,
  }) async {
    final pickupCandidates = await search(query: pickupQuery, limit: 1);
    if (pickupCandidates.isEmpty) return null;
    final pickup = pickupCandidates.first;

    final destinationCandidates = await search(
      query: destinationQuery,
      near: pickup.point,
      limit: 1,
    );
    if (destinationCandidates.isEmpty) return null;
    final destination = destinationCandidates.first;

    final routeQuote = await route(from: pickup.point, to: destination.point);
    if (routeQuote == null) return null;
    final trafficSnapshot = await traffic(at: pickup.point);
    return RideTomTomQuote(
      pickup: pickup,
      destination: destination,
      route: routeQuote,
      trafficAtPickup: trafficSnapshot,
    );
  }

  Future<RidePlatformBootstrap?> bootstrapConfig() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'bootstrap'],
    );
    if (uri == null) return null;

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return null;
      final version = (decoded['version'] ?? '').toString().trim();
      final mapStack = decoded['map_stack'];
      if (version.isEmpty || mapStack is! Map) return null;
      final display = (mapStack['display'] ?? '').toString().trim();
      final routing =
          (mapStack['routing_eta_search_traffic'] ?? '').toString().trim();
      if (display.isEmpty || routing.isEmpty) return null;
      return RidePlatformBootstrap(
        version: version,
        surfaces: _parseStringList(decoded['surfaces']),
        serviceClasses: _parseStringList(decoded['service_classes']),
        riderLifecycleStates:
            _parseStringList(decoded['rider_lifecycle_states']),
        riderWalletBuckets: _parseStringList(decoded['rider_wallet_buckets']),
        driverLedgerBalances:
            _parseStringList(decoded['driver_ledger_balances']),
        operatorRoles: _parseStringList(decoded['operator_roles']),
        mapDisplayStack: display,
        mapRoutingStack: routing,
      );
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RiderWalletSnapshot?> riderWalletSnapshot({
    required String walletId,
    String? riderId,
  }) async {
    final wid = walletId.trim();
    if (wid.isEmpty) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['payments', 'wallets', wid, 'buckets'],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        return null;
      }
      final currency =
          (decoded['currency'] ?? 'SYP').toString().trim().toUpperCase();
      final normalized = <String, Object?>{
        'rider_id': (riderId ?? '').trim().isEmpty ? wid : riderId!.trim(),
        'buckets': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'cash_balance',
            'currency': currency,
            'balance_minor_units':
                _parseInt(decoded['cash_balance_cents']) ?? 0,
          },
          <String, Object?>{
            'type': 'promo_credit',
            'currency': currency,
            'balance_minor_units':
                _parseInt(decoded['promo_credit_cents']) ?? 0,
          },
          <String, Object?>{
            'type': 'refund_credit',
            'currency': currency,
            'balance_minor_units':
                _parseInt(decoded['refund_credit_cents']) ?? 0,
          },
          <String, Object?>{
            'type': 'corporate_credit',
            'currency': currency,
            'balance_minor_units':
                _parseInt(decoded['corporate_credit_cents']) ?? 0,
          },
        ],
      };
      return RiderWalletSnapshot.fromJson(normalized);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RidePricingPreview?> pricingPreview({
    required String rideClass,
    required int distanceMeters,
    required int etaSeconds,
    int trafficDelaySeconds = 0,
  }) async {
    final normalizedRideClass = rideClass.trim();
    if (normalizedRideClass.isEmpty) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'pricing_preview'],
      queryParameters: <String, String>{
        'ride_class': normalizedRideClass,
        'distance_m': distanceMeters.toString(),
        'eta_s': etaSeconds.toString(),
        'traffic_delay_s': trafficDelaySeconds.toString(),
      },
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RidePricingPreview.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideOperatorPricingPolicyDashboard?> operatorPricingPolicy() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'rides',
        'operator',
        'pricing_policy',
      ],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideOperatorPricingPolicyDashboard.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RidePricingPolicy?> upsertOperatorPricingPolicy({
    required String rideClass,
    required int baseFareMinorUnits,
    required int perKmMinorUnits,
    required int perMinuteMinorUnits,
    required int trafficDelayPerMinuteMinorUnits,
    required int bookingFeeMinorUnits,
    required int minimumFareMinorUnits,
    required int driverShareBps,
  }) async {
    final normalizedRideClass = rideClass.trim();
    if (normalizedRideClass.isEmpty) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'rides',
        'operator',
        'pricing_policy',
      ],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final payload = <String, Object?>{
        'ride_class': normalizedRideClass,
        'base_fare_minor_units': baseFareMinorUnits,
        'per_km_minor_units': perKmMinorUnits,
        'per_minute_minor_units': perMinuteMinorUnits,
        'traffic_delay_per_minute_minor_units': trafficDelayPerMinuteMinorUnits,
        'booking_fee_minor_units': bookingFeeMinorUnits,
        'minimum_fare_minor_units': minimumFareMinorUnits,
        'driver_share_bps': driverShareBps,
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RidePricingPolicy.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTrip?> createTrip({
    required String pickup,
    required String destination,
    required String rideClass,
    required int fareEstimateCents,
    required int etaSeconds,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'trips'],
    );
    if (uri == null) return null;
    final body = <String, Object?>{
      'pickup': pickup,
      'destination': destination,
      'ride_class': rideClass,
      'fare_estimate_cents': fareEstimateCents,
      'eta_seconds': etaSeconds,
    };

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] = newPaymentsIdempotencyKey('ride-create');
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return _rideTripFromPayload(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTrip?> commandTrip({
    required String rideId,
    required String command,
    int? etaSeconds,
    String? driverAccountId,
    String? driverName,
    String? carPlate,
    String? reason,
    // Cycle 201 — structured cancellation reason code. Server
    // validates against the canonical-reason-code regex and stores
    // it in auth_ride_trips.cancel_reason_code for operator
    // analytics (Cycle 198).
    String? cancelReasonCode,
  }) async {
    final id = rideId.trim();
    if (id.isEmpty) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', id, 'commands'],
    );
    if (uri == null) return null;

    final body = <String, Object?>{
      'command': command,
      if (etaSeconds != null) 'eta_seconds': etaSeconds,
      if ((driverAccountId ?? '').trim().isNotEmpty)
        'driver_account_id': driverAccountId!.trim(),
      if ((driverName ?? '').trim().isNotEmpty)
        'driver_name': driverName!.trim(),
      if ((carPlate ?? '').trim().isNotEmpty) 'car_plate': carPlate!.trim(),
      if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      if ((cancelReasonCode ?? '').trim().isNotEmpty)
        'cancel_reason_code': cancelReasonCode!.trim(),
    };

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] = newPaymentsIdempotencyKey('ride-$command');
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return _rideTripFromPayload(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideActiveTripSnapshot> activeTripSnapshot() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'trips', 'active'],
    );
    if (uri == null) {
      return const RideActiveTripSnapshot(
        trip: null,
        requestSucceeded: false,
        authoritativeNoActiveFromServer: false,
      );
    }

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _rideDiagnosticLog(
            'activeTrip status=${resp.statusCode} body=${shamellPrivacySafePayloadSummary(resp.body)}');
        return const RideActiveTripSnapshot(
          trip: null,
          requestSucceeded: false,
          authoritativeNoActiveFromServer: false,
        );
      }
      _rideDiagnosticLog(
        'activeTrip body=${shamellPrivacySafePayloadSummary(resp.body)}',
      );
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        if (decoded.containsKey('active')) {
          final active = decoded['active'];
          if (active == null) {
            _rideDiagnosticLog('activeTrip active=null');
            return const RideActiveTripSnapshot(
              trip: null,
              requestSucceeded: true,
              authoritativeNoActiveFromServer: true,
            );
          }
          return RideActiveTripSnapshot(
            trip: _rideTripFromPayload(active),
            requestSucceeded: true,
            authoritativeNoActiveFromServer: false,
          );
        }
      }
      return RideActiveTripSnapshot(
        trip: _rideTripFromPayload(decoded),
        requestSucceeded: true,
        authoritativeNoActiveFromServer: false,
      );
    } catch (_) {
      return const RideActiveTripSnapshot(
        trip: null,
        requestSucceeded: false,
        authoritativeNoActiveFromServer: false,
      );
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTrip?> activeTrip() async {
    return (await activeTripSnapshot()).trip;
  }

  Future<RideSupportTicketList?> supportTickets({int limit = 8}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'support_tickets'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) return null;

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return RideSupportTicketList.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideSupportTicket?> createSupportTicket({
    String? rideId,
    required RideSupportTicketCategory category,
    String? subject,
    required String body,
    RideSupportTicketContactPreference preferredContact =
        RideSupportTicketContactPreference.inApp,
  }) async {
    final normalizedRideId = (rideId ?? '').trim();
    final normalizedSubject = (subject ?? '').trim();
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'support_tickets'],
    );
    if (uri == null) return null;

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final payload = <String, Object?>{
        'category': rideSupportTicketCategoryWireValue(category),
        'body': normalizedBody,
        'preferred_contact':
            rideSupportTicketContactPreferenceWireValue(preferredContact),
        if (normalizedRideId.isNotEmpty) 'ride_id': normalizedRideId,
        if (normalizedSubject.isNotEmpty) 'subject': normalizedSubject,
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return RideSupportTicket.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideLiveTrackingSnapshot?> trackingSnapshot(String rideId) async {
    final id = rideId.trim();
    if (id.isEmpty) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'trips', id, 'tracking'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return _rideTrackingSnapshotFromPayload(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<List<RideTrip>> driverQueueTrips({int limit = 12}) async {
    final nextTrips = await _fetchDriverQueueTrips(
      pathSegments: const <String>[
        'me',
        'rides',
        'driver',
        'dispatch_offers',
      ],
      limit: limit,
    );
    if (nextTrips != null) {
      return nextTrips;
    }
    final legacyTrips = await _fetchDriverQueueTrips(
      pathSegments: const <String>['me', 'rides', 'driver', 'queue'],
      limit: limit,
    );
    return legacyTrips ?? const <RideTrip>[];
  }

  Future<List<RideTrip>?> _fetchDriverQueueTrips({
    required List<String> pathSegments,
    required int limit,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: pathSegments,
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _rideDiagnosticLog(
          'driverQueueTrips path=${uri.path} status=${resp.statusCode} body=${shamellPrivacySafePayloadSummary(resp.body)}',
        );
        return null;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return null;
      return decoded.map(_rideTripFromPayload).whereType<RideTrip>().toList();
    } catch (error) {
      _rideDiagnosticLog(
        'driverQueueTrips path=${uri.path} exception=$error',
      );
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideDriverPresence?> driverPresence() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'driver', 'presence'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return RideDriverPresence.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideDriverPresence?> setDriverPresence({
    required bool online,
    double? lat,
    double? lon,
    String? driverName,
    String? carPlate,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'driver', 'presence'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final payload = <String, Object?>{
        'online': online,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if ((driverName ?? '').trim().isNotEmpty)
          'driver_name': driverName!.trim(),
        if ((carPlate ?? '').trim().isNotEmpty) 'car_plate': carPlate!.trim(),
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return RideDriverPresence.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTrip?> driverActiveTrip() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'driver', 'trips', 'active'],
    );
    if (uri == null) return null;

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _rideDiagnosticLog(
          'driverActiveTrip status=${resp.statusCode} body=${shamellPrivacySafePayloadSummary(resp.body)}',
        );
        return null;
      }
      _rideDiagnosticLog(
        'driverActiveTrip body=${shamellPrivacySafePayloadSummary(resp.body)}',
      );
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        if (decoded.containsKey('active')) {
          final active = decoded['active'];
          if (active == null) {
            _rideDiagnosticLog('driverActiveTrip active=null');
            return null;
          }
          return _rideTripFromPayload(active);
        }
      }
      return _rideTripFromPayload(decoded);
    } catch (error) {
      _rideDiagnosticLog('driverActiveTrip exception=$error');
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTrip?> driverAcceptTrip({
    required String rideId,
    required String driverName,
    required String carPlate,
    int? etaSeconds,
  }) async {
    final id = rideId.trim();
    if (id.isEmpty) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'driver', 'trips', id, 'accept'],
    );
    if (uri == null) return null;

    final body = <String, Object?>{
      'driver_name': driverName.trim(),
      'car_plate': carPlate.trim(),
      if (etaSeconds != null) 'eta_seconds': etaSeconds,
    };

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('ride-driver-accept');
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _rideDiagnosticLog(
          'driverAcceptTrip rideId=${shamellShortRideId(id)} status=${resp.statusCode} body=${shamellPrivacySafePayloadSummary(resp.body)}',
        );
        throw RideApiException(
          _rideApiErrorDetail(resp.body) ?? 'Could not accept ride.',
          statusCode: resp.statusCode,
        );
      }
      return _rideTripFromPayload(jsonDecode(resp.body));
    } catch (error) {
      if (error is RideApiException) rethrow;
      _rideDiagnosticLog(
        'driverAcceptTrip rideId=${shamellShortRideId(id)} exception=$error',
      );
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTrip?> driverCommandTrip({
    required String rideId,
    required String command,
    int? etaSeconds,
    String? reason,
    // Cycle 201 — structured cancellation reason code from the
    // picker (e.g. 'rider_no_show'). Forwarded into the server's
    // cancel_reason_code column for operator analytics.
    String? cancelReasonCode,
  }) async {
    final id = rideId.trim();
    if (id.isEmpty) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['me', 'rides', 'driver', 'trips', id, 'commands'],
    );
    if (uri == null) return null;
    final body = <String, Object?>{
      'command': command,
      if (etaSeconds != null) 'eta_seconds': etaSeconds,
      if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      if ((cancelReasonCode ?? '').trim().isNotEmpty)
        'cancel_reason_code': cancelReasonCode!.trim(),
    };
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('ride-driver-$command');
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return _rideTripFromPayload(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<DriverLedgerSnapshot?> driverLedger({
    required String walletId,
    String? driverId,
  }) async {
    final wid = walletId.trim();
    if (wid.isEmpty) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>['payments', 'wallets', wid, 'driver-ledger'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return DriverLedgerSnapshot.fromJson(
        jsonDecode(resp.body),
        fallbackDriverId: driverId,
      );
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideDriverLocationReceipt?> sendDriverLocationPing({
    required String rideId,
    required RideGeoPoint point,
    int? accuracyMeters,
    int? speedKmh,
    int? headingDegrees,
  }) async {
    final id = rideId.trim();
    if (id.isEmpty || !_isValidPoint(point)) return null;
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'rides',
        'driver',
        'trips',
        id,
        'location_ping',
      ],
    );
    if (uri == null) return null;

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final payload = <String, Object?>{
        'lat': point.lat,
        'lon': point.lon,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        if (speedKmh != null) 'speed_kmh': speedKmh,
        if (headingDegrees != null) 'heading_degrees': headingDegrees,
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return _rideDriverLocationReceiptFromPayload(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideDriverFinanceDashboard?> driverFinanceDashboard() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'rides',
        'driver',
        'finance_dashboard'
      ],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideDriverFinanceDashboard.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideDriverDocumentDashboard?> driverDocuments() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'driver', 'documents'],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideDriverDocumentDashboard.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideDriverDocument?> upsertDriverDocument({
    required RideDriverDocumentType documentType,
    required String documentNumber,
    String? issuingCountry,
    String? expiresAtIso,
  }) async {
    final normalizedDocumentNumber = documentNumber.trim();
    final normalizedCountry = (issuingCountry ?? '').trim().toUpperCase();
    final normalizedExpiresAtIso = (expiresAtIso ?? '').trim();
    if (normalizedDocumentNumber.isEmpty) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'driver', 'documents'],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final payload = <String, Object?>{
        'document_type': rideDriverDocumentTypeWireValue(documentType),
        'document_number': normalizedDocumentNumber,
        if (normalizedCountry.isNotEmpty) 'issuing_country': normalizedCountry,
        if (normalizedExpiresAtIso.isNotEmpty)
          'expires_at': normalizedExpiresAtIso,
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideDriverDocument.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideDriverShiftSummary?> driverShiftSummary() async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'rides',
        'driver',
        'shift_summary',
      ],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideDriverShiftSummary.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RidePayoutRequest?> createDriverPayoutRequest({
    required String driverWalletId,
    required String platformPayoutWalletId,
    required int amountMinorUnits,
    int? expiresInSeconds,
  }) async {
    if (amountMinorUnits <= 0) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>[
        'me',
        'rides',
        'driver',
        'payout_requests',
      ],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final deviceId =
          (await getOrCreateStableDeviceId(baseUrlOverride: baseUrl)).trim();
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('ride-driver-payout-request');
      headers['X-Device-ID'] = deviceId;
      headers.addAll(
        await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: baseUrl,
          deviceId: deviceId,
          operation: 'payments_requests_create',
          resourceId: shamellPaymentRequestCreateAttestationResourceId(
            fromWalletId: driverWalletId,
            toWalletId: platformPayoutWalletId,
            amountCents: amountMinorUnits,
          ),
          client: client,
        ),
      );
      final payload = <String, Object?>{
        'amount_minor_units': amountMinorUnits,
        if (expiresInSeconds != null) 'expires_in_secs': expiresInSeconds,
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RidePayoutRequest.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideOperatorLiveBoard?> operatorLiveBoard({
    int openLimit = 12,
    int activeLimit = 12,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'live_board'],
      queryParameters: <String, String>{
        'open_limit': openLimit.clamp(1, 50).toString(),
        'active_limit': activeLimit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideOperatorLiveBoard.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideOperatorDriverRoster?> operatorDriverRoster({
    int limit = 20,
  }) async {
    final nextRoster = await _fetchOperatorDriverRoster(
      pathSegments: const <String>['me', 'rides', 'operator', 'fleet', 'live'],
      limit: limit,
    );
    if (nextRoster != null) {
      return nextRoster;
    }
    return _fetchOperatorDriverRoster(
      pathSegments: const <String>[
        'me',
        'rides',
        'operator',
        'driver_roster',
      ],
      limit: limit,
    );
  }

  Future<RideOperatorDriverRoster?> _fetchOperatorDriverRoster({
    required List<String> pathSegments,
    required int limit,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: pathSegments,
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _rideDiagnosticLog(
          'operatorDriverRoster path=${uri.path} status=${resp.statusCode} body=${shamellPrivacySafePayloadSummary(resp.body)}',
        );
        return null;
      }
      return RideOperatorDriverRoster.fromJson(jsonDecode(resp.body));
    } catch (error) {
      _rideDiagnosticLog(
        'operatorDriverRoster path=${uri.path} exception=$error',
      );
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideOperatorCaseQueue?> operatorCaseQueue({int limit = 20}) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'case_queue'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideOperatorCaseQueue.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideOperatorSupportQueue?> operatorSupportQueue({
    int limit = 20,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'support_queue'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideOperatorSupportQueue.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideOperatorDocumentQueue?> operatorDocumentQueue({
    String? status,
    int limit = 20,
  }) async {
    final normalizedStatus = (status ?? '').trim().toLowerCase();
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'document_queue'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
        if (normalizedStatus.isNotEmpty) 'status': normalizedStatus,
      },
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideOperatorDocumentQueue.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideOperatorFinanceQueue?> operatorFinanceQueue({
    int limit = 20,
  }) async {
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['me', 'rides', 'operator', 'finance_queue'],
      queryParameters: <String, String>{
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideOperatorFinanceQueue.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RidePayoutRequest?> approveOperatorPayoutRequest({
    required String requestId,
    required String feeWalletId,
  }) async {
    final rid = requestId.trim();
    final payoutWalletId = feeWalletId.trim();
    if (rid.isEmpty || payoutWalletId.isEmpty) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'rides',
        'operator',
        'payout_requests',
        rid,
        'approve',
      ],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final deviceId =
          (await getOrCreateStableDeviceId(baseUrlOverride: baseUrl)).trim();
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('ride-operator-payout-approve');
      headers['X-Device-ID'] = deviceId;
      headers.addAll(
        await shamellBuildPaymentMutationAttestationHeaders(
          baseUrl: baseUrl,
          deviceId: deviceId,
          operation: 'payments_requests_accept',
          resourceId: shamellPaymentRequestAcceptAttestationResourceId(
            requestId: rid,
            toWalletId: payoutWalletId,
          ),
          client: client,
        ),
      );
      final resp = await client
          .post(uri, headers: headers, body: '{}')
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RidePayoutRequest.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideTrip?> operatorCommandTrip({
    required String rideId,
    required String command,
    String? reason,
    String? cancelReasonCode,
  }) async {
    final normalizedRideId = rideId.trim();
    final normalizedCommand = command.trim();
    final normalizedReason = (reason ?? '').trim();
    final normalizedCancelReasonCode = (cancelReasonCode ?? '').trim();
    if (normalizedRideId.isEmpty || normalizedCommand.isEmpty) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'rides',
        'operator',
        'trips',
        normalizedRideId,
        'commands',
      ],
    );
    if (uri == null) {
      return null;
    }

    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('ride-operator-$normalizedCommand');
      final payload = <String, Object?>{
        'command': normalizedCommand,
        if (normalizedReason.isNotEmpty) 'reason': normalizedReason,
        if (normalizedCancelReasonCode.isNotEmpty)
          'cancel_reason_code': normalizedCancelReasonCode,
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _rideDiagnosticLog(
          'operatorCommandTrip rideId=${shamellShortRideId(normalizedRideId)} command=$normalizedCommand status=${resp.statusCode} body=${shamellPrivacySafePayloadSummary(resp.body)}',
        );
        throw RideApiException(
          _rideApiErrorDetail(resp.body) ?? 'Could not update ride.',
          statusCode: resp.statusCode,
        );
      }
      _rideDiagnosticLog(
        'operatorCommandTrip rideId=${shamellShortRideId(normalizedRideId)} command=$normalizedCommand status=200 body=${shamellPrivacySafePayloadSummary(resp.body)}',
      );
      return _rideTripFromPayload(jsonDecode(resp.body));
    } catch (error) {
      if (error is RideApiException) rethrow;
      _rideDiagnosticLog(
        'operatorCommandTrip rideId=${shamellShortRideId(normalizedRideId)} command=$normalizedCommand exception=$error',
      );
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideDriverDocument?> reviewOperatorDocument({
    required String documentId,
    required String decision,
    String? note,
  }) async {
    final normalizedDocumentId = documentId.trim();
    final normalizedDecision = decision.trim().toLowerCase();
    final normalizedNote = (note ?? '').trim();
    if (normalizedDocumentId.isEmpty || normalizedDecision.isEmpty) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'rides',
        'operator',
        'documents',
        normalizedDocumentId,
        'review',
      ],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final payload = <String, Object?>{
        'decision': normalizedDecision,
        if (normalizedNote.isNotEmpty) 'note': normalizedNote,
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideDriverDocument.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<RideSupportTicket?> resolveOperatorSupportTicket({
    required String ticketId,
    required String note,
  }) async {
    final normalizedTicketId = ticketId.trim();
    final normalizedNote = note.trim();
    if (normalizedTicketId.isEmpty || normalizedNote.isEmpty) {
      return null;
    }
    final uri = secureApiChildUri(
      baseUrl: baseUrl,
      pathSegments: <String>[
        'me',
        'rides',
        'operator',
        'support_tickets',
        normalizedTicketId,
        'resolve',
      ],
    );
    if (uri == null) {
      return null;
    }
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(baseUrl);
      headers['Content-Type'] = 'application/json';
      final payload = <String, Object?>{
        'note': normalizedNote,
      };
      final resp = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }
      return RideSupportTicket.fromJson(jsonDecode(resp.body));
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }
}

RideTrip? resolveBestRideActiveTrip({
  RideTrip? serverTrip,
  RideTrip? trackingTrip,
  RideTrip? persistedTrip,
}) {
  RideTrip? nonTerminal(RideTrip? trip) {
    if (trip == null) return null;
    return rideTripStatusIsTerminal(trip.status) ? null : trip;
  }

  final server = nonTerminal(serverTrip);
  final tracking = nonTerminal(trackingTrip);
  final persisted = nonTerminal(persistedTrip);

  if (tracking != null) {
    if (server != null && server.rideId == tracking.rideId) {
      return tracking;
    }
    if (persisted != null && persisted.rideId == tracking.rideId) {
      return tracking;
    }
    if (server == null && persisted == null) {
      return tracking;
    }
  }

  return server ?? persisted ?? tracking;
}

class RideActiveTripSnapshot {
  final RideTrip? trip;
  final bool requestSucceeded;
  final bool authoritativeNoActiveFromServer;

  const RideActiveTripSnapshot({
    required this.trip,
    required this.requestSucceeded,
    required this.authoritativeNoActiveFromServer,
  });
}

RideTrip? _rideTripFromPayload(Object? raw) {
  if (raw is! Map) return null;
  final rideId = (raw['ride_id'] ?? '').toString().trim();
  if (rideId.isEmpty) return null;
  final pickup = (raw['pickup'] ?? '').toString().trim();
  final destination = (raw['destination'] ?? '').toString().trim();
  final rideClass = (raw['ride_class'] ?? '').toString().trim();
  final status = rideTripStatusFromWire((raw['status'] ?? '').toString());
  if (pickup.isEmpty ||
      destination.isEmpty ||
      rideClass.isEmpty ||
      status == null) {
    return null;
  }
  final fareEstimateCents =
      (_parseInt(raw['fare_estimate_cents']) ?? 0).clamp(0, 500000000);
  final etaMinutes = (_parseInt(raw['eta_minutes']) ??
          (((_parseInt(raw['eta_seconds']) ?? 0) + 59) ~/ 60))
      .clamp(1, 24 * 60);
  final createdAtIso = (raw['created_at'] ?? '').toString().trim();
  final lastUpdatedAtIso =
      (raw['last_updated_at'] ?? raw['status_updated_at'] ?? '')
          .toString()
          .trim();
  if (createdAtIso.isEmpty || lastUpdatedAtIso.isEmpty) return null;
  final driverName = (raw['driver_name'] ?? '').toString().trim();
  final carPlate = (raw['car_plate'] ?? '').toString().trim();
  final pickupLabel = (raw['pickup_label'] ?? '').toString().trim();
  final destinationLabel = (raw['destination_label'] ?? '').toString().trim();
  final pickupLocationRaw = raw['pickup_location'];
  final destinationLocationRaw = raw['destination_location'];
  return RideTrip(
    rideId: rideId,
    offerId: (raw['offer_id'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['offer_id'] ?? '').toString().trim(),
    pickup: pickup,
    destination: destination,
    pickupLabel: pickupLabel.isEmpty ? pickup : pickupLabel,
    destinationLabel: destinationLabel.isEmpty ? destination : destinationLabel,
    pickupLat: _parseDouble(raw['pickup_lat']) ??
        (pickupLocationRaw is Map
            ? _parseDouble(pickupLocationRaw['lat'])
            : null),
    pickupLon: _parseDouble(raw['pickup_lon']) ??
        (pickupLocationRaw is Map
            ? _parseDouble(pickupLocationRaw['lon'])
            : null),
    destinationLat: _parseDouble(raw['destination_lat']) ??
        (destinationLocationRaw is Map
            ? _parseDouble(destinationLocationRaw['lat'])
            : null),
    destinationLon: _parseDouble(raw['destination_lon']) ??
        (destinationLocationRaw is Map
            ? _parseDouble(destinationLocationRaw['lon'])
            : null),
    rideClass: rideClass,
    driverName: driverName.isEmpty ? 'Driver pending' : driverName,
    carPlate: carPlate.isEmpty ? '--' : carPlate,
    etaMinutes: etaMinutes,
    fareEstimateCents: fareEstimateCents,
    status: status,
    cancelReasonCode:
        (raw['cancel_reason_code'] ?? '').toString().trim().isEmpty
            ? null
            : (raw['cancel_reason_code'] ?? '').toString().trim(),
    createdAtIso: createdAtIso,
    lastUpdatedAtIso: lastUpdatedAtIso,
    assignedAtIso: (raw['assigned_at'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['assigned_at'] ?? '').toString().trim(),
    arrivingAtIso: (raw['arriving_at'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['arriving_at'] ?? '').toString().trim(),
    arrivedAtIso: (raw['arrived_at'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['arrived_at'] ?? '').toString().trim(),
    startedAtIso: (raw['started_at'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['started_at'] ?? '').toString().trim(),
    completedAtIso: (raw['completed_at'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['completed_at'] ?? '').toString().trim(),
  );
}

RideTrackingEvent? _rideTrackingEventFromPayload(Object? raw) {
  if (raw is! Map) return null;
  final eventId = _parseInt(raw['event_id']) ?? 0;
  final eventKind = (raw['event_kind'] ?? '').toString().trim();
  final createdAtIso =
      (raw['created_at'] ?? raw['updated_at'] ?? '').toString().trim();
  if (eventId < 0 || eventKind.isEmpty || createdAtIso.isEmpty) {
    return null;
  }
  RideGeoPoint? location;
  int? accuracyMeters;
  int? speedKmh;
  int? headingDegrees;
  final locationRaw = raw['location'];
  if (locationRaw is Map) {
    final lat = locationRaw['lat'];
    final lon = locationRaw['lon'];
    if (lat is num && lon is num) {
      final parsed = RideGeoPoint(lat: lat.toDouble(), lon: lon.toDouble());
      if (_isValidPoint(parsed)) {
        location = parsed;
        accuracyMeters = _parseInt(locationRaw['accuracy_meters']) ??
            _parseInt(raw['accuracy_meters']);
        speedKmh =
            _parseInt(locationRaw['speed_kmh']) ?? _parseInt(raw['speed_kmh']);
        headingDegrees = _parseInt(locationRaw['heading_degrees']) ??
            _parseInt(raw['heading_degrees']);
      }
    }
  }
  return RideTrackingEvent(
    eventId: eventId,
    eventKind: eventKind,
    status: rideTripStatusFromWire((raw['status'] ?? '').toString()),
    actorAccountId: (raw['actor_account_id'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['actor_account_id'] ?? '').toString().trim(),
    location: location,
    accuracyMeters: accuracyMeters,
    speedKmh: speedKmh,
    headingDegrees: headingDegrees,
    note: (raw['note'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['note'] ?? '').toString().trim(),
    createdAtIso: createdAtIso,
  );
}

RideLiveTrackingSnapshot? _rideTrackingSnapshotFromPayload(Object? raw) {
  if (raw is! Map) return null;
  final ride = _rideTripFromPayload(raw['ride']);
  if (ride == null) return null;
  final latestDriverLocation =
      _rideTrackingEventFromPayload(raw['latest_driver_location']) ??
          _rideTrackingEventFromLiveStatePayload(raw['live_state']);
  final timelineRaw = raw['timeline'];
  final timeline = <RideTrackingEvent>[];
  if (timelineRaw is List) {
    for (final item in timelineRaw) {
      final parsed = _rideTrackingEventFromPayload(item);
      if (parsed == null) continue;
      timeline.add(parsed);
      if (timeline.length >= 32) break;
    }
  }
  return RideLiveTrackingSnapshot(
    ride: ride,
    latestDriverLocation: latestDriverLocation,
    timeline: timeline,
  );
}

RideTrackingEvent? _rideTrackingEventFromLiveStatePayload(Object? raw) {
  if (raw is! Map) return null;
  final locationRaw = raw['location'];
  if (locationRaw is! Map) return null;
  final lat = locationRaw['lat'];
  final lon = locationRaw['lon'];
  if (lat is! num || lon is! num) return null;
  final location = RideGeoPoint(lat: lat.toDouble(), lon: lon.toDouble());
  if (!_isValidPoint(location)) return null;
  final createdAtIso =
      (raw['last_location_at'] ?? raw['updated_at'] ?? '').toString().trim();
  if (createdAtIso.isEmpty) return null;
  return RideTrackingEvent(
    eventId: 0,
    eventKind: 'driver_location',
    status: rideTripStatusFromWire((raw['stage'] ?? '').toString()),
    actorAccountId: (raw['driver_account_id'] ?? '').toString().trim().isEmpty
        ? null
        : (raw['driver_account_id'] ?? '').toString().trim(),
    location: location,
    accuracyMeters: _parseInt(locationRaw['accuracy_meters']),
    speedKmh: _parseInt(locationRaw['speed_kmh']),
    headingDegrees: _parseInt(locationRaw['heading_degrees']),
    note: null,
    createdAtIso: createdAtIso,
  );
}

RideDriverLocationReceipt? _rideDriverLocationReceiptFromPayload(Object? raw) {
  if (raw is! Map) return null;
  final rideId = (raw['ride_id'] ?? '').toString().trim();
  final locationRaw = raw['location'];
  if (rideId.isEmpty || locationRaw is! Map) return null;
  final lat = locationRaw['lat'];
  final lon = locationRaw['lon'];
  if (lat is! num || lon is! num) return null;
  final point = RideGeoPoint(lat: lat.toDouble(), lon: lon.toDouble());
  if (!_isValidPoint(point)) return null;
  return RideDriverLocationReceipt(
    rideId: rideId,
    status: rideTripStatusFromWire((raw['status'] ?? '').toString()),
    location: point,
    accuracyMeters: _parseInt(locationRaw['accuracy_meters']),
    speedKmh: _parseInt(locationRaw['speed_kmh']),
    headingDegrees: _parseInt(locationRaw['heading_degrees']),
  );
}

bool _isValidPoint(RideGeoPoint point) {
  if (!point.lat.isFinite || !point.lon.isFinite) return false;
  return point.lat >= -90 &&
      point.lat <= 90 &&
      point.lon >= -180 &&
      point.lon <= 180;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

List<String> _parseStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  final out = <String>[];
  for (final item in raw) {
    final value = item.toString().trim();
    if (value.isEmpty) continue;
    out.add(value);
    if (out.length >= 64) break;
  }
  return out;
}
