import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/rides/ride_mobility_api.dart';
import 'package:shamell_flutter/core/rides/ride_hailing_store.dart';
import 'package:shamell_flutter/core/rides/ride_platform_contracts.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

const _apiBaseUrl = 'https://api.shamell.online';

class _StreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  _StreamingClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
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

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
  });

  setUp(() async {
    await setSessionTokenForBaseUrl(
      _apiBaseUrl,
      '0123456789abcdef0123456789abcdef',
    );
  });

  test('parseRideSsePayload collects events and ignores comments', () {
    final events = parseRideSsePayload(
      [
        ': keep alive',
        'event: rides_update',
        'data: {"emitted_at":"2026-04-04T00:00:00Z"}',
        '',
        'event: heartbeat',
        'data: {"emitted_at":"2026-04-04T00:00:20Z"}',
        '',
      ].join('\n'),
    );

    expect(events, hasLength(2));
    expect(events.first.event, 'rides_update');
    expect(events.first.data, '{"emitted_at":"2026-04-04T00:00:00Z"}');
    expect(events.last.event, 'heartbeat');
  });

  test('activeTripUpdateStream emits non-heartbeat sse events', () async {
    final client = _StreamingClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/trips/active/stream');
      expect(request.headers['accept'], 'text/event-stream');
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[
          utf8.encode('event: rides_update\n'),
          utf8.encode('data: {"emitted_at":"2026-04-04T00:00:00Z"}\n\n'),
          utf8.encode('event: heartbeat\n'),
          utf8.encode('data: {"emitted_at":"2026-04-04T00:00:20Z"}\n\n'),
          utf8.encode('event: rides_update\n'),
          utf8.encode('data: {"emitted_at":"2026-04-04T00:00:40Z"}\n\n'),
        ]),
        200,
        headers: const <String, String>{'content-type': 'text/event-stream'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final events = await api.activeTripUpdateStream().take(2).toList();

    expect(
      events,
      <String>[
        '{"emitted_at":"2026-04-04T00:00:00Z"}',
        '{"emitted_at":"2026-04-04T00:00:40Z"}',
      ],
    );
  });

  test('driverAcceptTrip surfaces backend detail for insufficient reserve',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/rides/driver/trips/ride_123/accept');
      return http.Response(
        jsonEncode(<String, Object?>{
          'detail':
              'driver balance must cover the 10% platform fee (120) before accepting this ride',
        }),
        409,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    expect(
      () => api.driverAcceptTrip(
        rideId: 'ride_123',
        driverName: 'Prod Driver',
        carPlate: 'SH001',
      ),
      throwsA(
        isA<RideApiException>().having(
          (error) => error.detail,
          'detail',
          contains('10% platform fee'),
        ),
      ),
    );
  });

  test('search parses sanitized places from BFF response', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/search');
      expect(request.url.queryParameters['q'], 'Old Town');
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'display_name': 'Old Town Gate',
            'lat': 33.5123,
            'lon': 36.3012,
          },
          <String, dynamic>{
            'display_name': 'Al Midan',
            'lat': 33.4888,
            'lon': 36.2921,
          },
        ]),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final places = await api.search(query: 'Old Town', limit: 3);
    expect(places.length, 2);
    expect(places.first.displayName, 'Old Town Gate');
    expect(places.first.point.lat, closeTo(33.5123, 0.00001));
    expect(places.first.point.lon, closeTo(36.3012, 0.00001));
  });

  test('route parses eta distance traffic and route points', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/route');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'distance_m': 5400,
          'eta_s': 780,
          'traffic_delay_s': 120,
          'points': <Map<String, dynamic>>[
            <String, dynamic>{'lat': 33.5138, 'lon': 36.2765},
            <String, dynamic>{'lat': 33.5201, 'lon': 36.3010},
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );
    final quote = await api.route(
      from: const RideGeoPoint(lat: 33.5138, lon: 36.2765),
      to: const RideGeoPoint(lat: 33.5201, lon: 36.3010),
    );

    expect(quote, isNotNull);
    expect(quote!.distanceMeters, 5400);
    expect(quote.etaSeconds, 780);
    expect(quote.trafficDelaySeconds, 120);
    expect(quote.points.length, 2);
  });

  test('reverseGeocode prefers display_name from BFF response', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/geo/reverse');
      expect(request.url.queryParameters['lat'], '33.513800');
      expect(request.url.queryParameters['lon'], '36.276500');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'name': 'Bab Sharqi',
          'display_name': 'Bab Sharqi, Damascus, Syria',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final label = await api.reverseGeocode(
      point: const RideGeoPoint(lat: 33.5138, lon: 36.2765),
    );

    expect(label, 'Bab Sharqi, Damascus, Syria');
  });

  test('search compacts overlong display names into concise labels', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/search');
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'display_name':
                'Building 12, Very Long Residential Compound Name, Al Qusour District, Damascus, Syria',
            'lat': 33.5138,
            'lon': 36.2765,
          },
        ]),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final places = await api.search(query: 'Compound', limit: 1);

    expect(places, hasLength(1));
    expect(places.first.displayName,
        'Building 12, Very Long Residential Compound Name');
    expect(places.first.displayName.length, lessThanOrEqualTo(80));
  });

  test('searchWithStatus marks backend failures as unavailable', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/search');
      return http.Response('temporary failure', 503);
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final result = await api.searchWithStatus(query: 'Malki', limit: 5);

    expect(result.places, isEmpty);
    expect(result.status, RidePlaceSearchStatus.unavailable);
  });

  test('quoteByText chains search route traffic endpoints', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add(request.url.path);
      if (request.url.path == '/me/rides/search' &&
          request.url.queryParameters['q'] == 'Damascus Gate') {
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'display_name': 'Damascus Gate',
              'lat': 33.5161,
              'lon': 36.3068,
            }
          ]),
          200,
        );
      }
      if (request.url.path == '/me/rides/search' &&
          request.url.queryParameters['q'] == 'Bab Touma') {
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'display_name': 'Bab Touma',
              'lat': 33.5132,
              'lon': 36.3130,
            }
          ]),
          200,
        );
      }
      if (request.url.path == '/me/rides/route') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'distance_m': 1800,
            'eta_s': 300,
            'traffic_delay_s': 40,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'lat': 33.5161, 'lon': 36.3068},
              <String, dynamic>{'lat': 33.5132, 'lon': 36.3130},
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/me/rides/traffic') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'current_speed_kmh': 24,
            'free_flow_speed_kmh': 41,
            'current_travel_time_s': 330,
            'free_flow_travel_time_s': 240,
            'radius_m': 2000,
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );
    final quote = await api.quoteByText(
      pickupQuery: 'Damascus Gate',
      destinationQuery: 'Bab Touma',
    );

    expect(quote, isNotNull);
    expect(quote!.route.etaSeconds, 300);
    expect(quote.trafficAtPickup, isNotNull);
    expect(
        calls,
        containsAll(<String>[
          '/me/rides/search',
          '/me/rides/route',
          '/me/rides/traffic',
        ]));
  });

  test('bootstrapConfig parses ride platform contract from BFF', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/bootstrap');
      return http.Response(
        jsonEncode(<String, Object?>{
          'version': '2026-03-31',
          'surfaces': <String>['rider', 'driver', 'admin'],
          'service_classes': <String>[
            'economy',
            'xl',
            'premium',
            'delivery',
            'corporate',
          ],
          'rider_lifecycle_states': <String>[
            'idle',
            'quote_shown',
            'ride_requested',
            'matching',
          ],
          'rider_wallet_buckets': <String>[
            'cash_balance',
            'promo_credit',
            'refund_credit',
            'corporate_credit',
          ],
          'driver_ledger_balances': <String>[
            'earnings_available',
            'held_reserve',
            'debt',
            'payout_pending',
            'bonuses',
            'cash_collected',
          ],
          'operator_roles': <String>[
            'super_admin',
            'city_manager',
            'support_l1',
          ],
          'map_stack': <String, String>{
            'display': 'tomtom_maplibre_raster_primary_osm_fallback',
            'routing_eta_search_traffic': 'tomtom',
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );
    final bootstrap = await api.bootstrapConfig();
    expect(bootstrap, isNotNull);
    expect(bootstrap!.version, '2026-03-31');
    expect(bootstrap.serviceClasses, contains('corporate'));
    expect(bootstrap.riderWalletBuckets, contains('promo_credit'));
    expect(
      bootstrap.mapDisplayStack,
      'tomtom_maplibre_raster_primary_osm_fallback',
    );
    expect(bootstrap.mapRoutingStack, 'tomtom');
  });

  test('createTrip and commandTrip use idempotency and parse trip payload',
      () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'POST' && request.url.path == '/me/rides/trips') {
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['pickup'], 'Old Town');
        expect(payload['destination'], 'Bab Touma');
        expect(payload.containsKey('driver_name'), isFalse);
        expect(payload.containsKey('car_plate'), isFalse);
        return http.Response(
          jsonEncode(<String, Object?>{
            'ride_id': 'RIDE1234567890ABCD123456',
            'pickup': 'Old Town',
            'destination': 'Bab Touma',
            'ride_class': 'economy',
            'driver_name': 'Ayman',
            'car_plate': 'AB-1234',
            'fare_estimate_cents': 1250,
            'eta_seconds': 420,
            'status': 'ride_requested',
            'created_at': '2026-03-31T09:10:00Z',
            'last_updated_at': '2026-03-31T09:10:00Z',
          }),
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path ==
              '/me/rides/trips/RIDE1234567890ABCD123456/commands') {
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['command'], 'enter_matching');
        return http.Response(
          jsonEncode(<String, Object?>{
            'ride_id': 'RIDE1234567890ABCD123456',
            'pickup': 'Old Town',
            'destination': 'Bab Touma',
            'ride_class': 'economy',
            'driver_name': 'Ayman',
            'car_plate': 'AB-1234',
            'fare_estimate_cents': 1250,
            'eta_minutes': 6,
            'status': 'matching',
            'created_at': '2026-03-31T09:10:00Z',
            'last_updated_at': '2026-03-31T09:11:00Z',
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final created = await api.createTrip(
      pickup: 'Old Town',
      destination: 'Bab Touma',
      rideClass: 'economy',
      fareEstimateCents: 1250,
      etaSeconds: 420,
    );
    expect(created, isNotNull);
    expect(created!.status, RideTripStatus.rideRequested);
    expect(created.etaMinutes, 7);

    final updated = await api.commandTrip(
      rideId: created.rideId,
      command: 'enter_matching',
    );
    expect(updated, isNotNull);
    expect(updated!.status, RideTripStatus.matching);
    expect(
      calls,
      containsAll(<String>[
        'POST /me/rides/trips',
        'POST /me/rides/trips/RIDE1234567890ABCD123456/commands',
      ]),
    );
  });

  test('resolveBestRideActiveTrip prefers fresher tracking trip', () {
    const serverTrip = RideTrip(
      rideId: 'RIDE1234567890ABCD123456',
      pickup: 'Old Town',
      destination: 'Bab Touma',
      rideClass: 'economy',
      driverName: 'Driver pending',
      carPlate: '--',
      etaMinutes: 7,
      fareEstimateCents: 1250,
      status: RideTripStatus.rideRequested,
      createdAtIso: '2026-04-02T14:00:00Z',
      lastUpdatedAtIso: '2026-04-02T14:00:00Z',
    );
    const trackingTrip = RideTrip(
      rideId: 'RIDE1234567890ABCD123456',
      pickup: 'Old Town',
      destination: 'Bab Touma',
      rideClass: 'economy',
      driverName: 'Maya',
      carPlate: 'BA-1586',
      etaMinutes: 4,
      fareEstimateCents: 1250,
      status: RideTripStatus.driverAssigned,
      createdAtIso: '2026-04-02T14:00:00Z',
      lastUpdatedAtIso: '2026-04-02T14:04:00Z',
    );

    final resolved = resolveBestRideActiveTrip(
      serverTrip: serverTrip,
      trackingTrip: trackingTrip,
      persistedTrip: null,
    );

    expect(resolved, isNotNull);
    expect(resolved!.status, RideTripStatus.driverAssigned);
    expect(resolved.driverName, 'Maya');
    expect(resolved.carPlate, 'BA-1586');
  });

  test('resolveBestRideActiveTrip falls back to persisted trip', () {
    const persistedTrip = RideTrip(
      rideId: 'RIDE1234567890ABCD123456',
      pickup: 'Old Town',
      destination: 'Bab Touma',
      rideClass: 'economy',
      driverName: 'Driver pending',
      carPlate: '--',
      etaMinutes: 7,
      fareEstimateCents: 1250,
      status: RideTripStatus.matching,
      createdAtIso: '2026-04-02T14:00:00Z',
      lastUpdatedAtIso: '2026-04-02T14:01:00Z',
    );

    final resolved = resolveBestRideActiveTrip(
      serverTrip: null,
      trackingTrip: null,
      persistedTrip: persistedTrip,
    );

    expect(resolved, isNotNull);
    expect(resolved!.status, RideTripStatus.matching);
    expect(resolved.rideId, persistedTrip.rideId);
  });

  test('resolveBestRideActiveTrip ignores terminal persisted trip', () {
    const persistedTrip = RideTrip(
      rideId: 'RIDE1234567890ABCD123456',
      pickup: 'Old Town',
      destination: 'Bab Touma',
      rideClass: 'economy',
      driverName: 'Maya',
      carPlate: 'BA-1586',
      etaMinutes: 7,
      fareEstimateCents: 1250,
      status: RideTripStatus.tripCompleted,
      createdAtIso: '2026-04-02T14:00:00Z',
      lastUpdatedAtIso: '2026-04-02T14:10:00Z',
    );

    final resolved = resolveBestRideActiveTrip(
      serverTrip: null,
      trackingTrip: null,
      persistedTrip: persistedTrip,
    );

    expect(resolved, isNull);
  });

  test('activeTrip parses direct trip payload from live bff shape', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/trips/active');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ride_id': 'RIDERDIRECT1234567890AB',
          'pickup': 'Umayyad Square',
          'destination': 'Bab Touma',
          'ride_class': 'economy',
          'driver_name': 'Maya',
          'car_plate': 'BA-1586',
          'eta_minutes': 7,
          'fare_estimate_cents': 1880,
          'status': 'driver_arriving',
          'created_at': '2026-04-02T14:00:00Z',
          'last_updated_at': '2026-04-02T14:06:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final trip = await api.activeTrip();
    expect(trip, isNotNull);
    expect(trip!.rideId, 'RIDERDIRECT1234567890AB');
    expect(trip.status, RideTripStatus.driverArriving);
  });

  test('activeTrip parses wrapped active ride payload', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/trips/active');
      return http.Response(
        jsonEncode(<String, Object?>{
          'active': <String, Object?>{
            'ride_id': 'RIDERWRAPPED123456789A',
            'pickup': 'Midan',
            'destination': 'Mazzeh',
            'ride_class': 'economy',
            'driver_name': 'Maya',
            'car_plate': 'BA-1586',
            'eta_minutes': 5,
            'fare_estimate_cents': 1540,
            'status': 'driver_assigned',
            'created_at': '2026-04-02T14:00:00Z',
            'last_updated_at': '2026-04-02T14:06:00Z',
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final trip = await api.activeTrip();
    expect(trip, isNotNull);
    expect(trip!.rideId, 'RIDERWRAPPED123456789A');
    expect(trip.status, RideTripStatus.driverAssigned);
  });

  test('activeTrip parses extended trip metadata fields', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/trips/active');
      return http.Response(
        jsonEncode(<String, Object?>{
          'active': <String, Object?>{
            'ride_id': 'RIDEEXT1234567890ABCD12',
            'offer_id': 'OFFER1234567890ABCD12',
            'pickup': 'Old Town',
            'destination': 'Bab Touma',
            'pickup_label': 'Old Town, Damascus',
            'destination_label': 'Bab Touma, Damascus',
            'pickup_location': <String, Object?>{
              'lat': 33.5138,
              'lon': 36.2765
            },
            'destination_lat': 33.5149,
            'destination_lon': 36.3015,
            'ride_class': 'economy',
            'driver_name': 'Maya',
            'car_plate': 'BA-1586',
            'eta_seconds': 360,
            'fare_estimate_cents': 1880,
            'status': 'driver_arriving',
            'cancel_reason_code': 'rider_cancelled',
            'created_at': '2026-04-04T08:00:00Z',
            'last_updated_at': '2026-04-04T08:06:00Z',
            'assigned_at': '2026-04-04T08:03:00Z',
            'arriving_at': '2026-04-04T08:04:00Z',
            'arrived_at': '2026-04-04T08:05:00Z',
            'started_at': '2026-04-04T08:07:00Z',
            'completed_at': '2026-04-04T08:12:00Z',
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final trip = await api.activeTrip();
    expect(trip, isNotNull);
    expect(trip!.offerId, 'OFFER1234567890ABCD12');
    expect(trip.pickupLabel, 'Old Town, Damascus');
    expect(trip.destinationLabel, 'Bab Touma, Damascus');
    expect(trip.pickupLat, 33.5138);
    expect(trip.pickupLon, 36.2765);
    expect(trip.destinationLat, 33.5149);
    expect(trip.destinationLon, 36.3015);
    expect(trip.cancelReasonCode, 'rider_cancelled');
    expect(trip.assignedAtIso, '2026-04-04T08:03:00Z');
    expect(trip.completedAtIso, '2026-04-04T08:12:00Z');
  });

  test('pricingPreview parses backend fare breakdown', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/pricing_preview');
      expect(request.url.queryParameters['ride_class'], 'economy');
      expect(request.url.queryParameters['distance_m'], '5400');
      expect(request.url.queryParameters['eta_s'], '780');
      expect(request.url.queryParameters['traffic_delay_s'], '120');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ride_class': 'economy',
          'currency': 'SYP',
          'distance_m': 5400,
          'eta_s': 780,
          'traffic_delay_s': 120,
          'breakdown': <String, Object?>{
            'base_fare_minor_units': 700,
            'distance_component_minor_units': 702,
            'time_component_minor_units': 455,
            'traffic_surcharge_minor_units': 36,
            'booking_fee_minor_units': 150,
            'minimum_fare_lift_minor_units': 0,
          },
          'total_fare_minor_units': 2043,
          'suggested_driver_payout_minor_units': 1552,
          'platform_margin_minor_units': 491,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final preview = await api.pricingPreview(
      rideClass: 'economy',
      distanceMeters: 5400,
      etaSeconds: 780,
      trafficDelaySeconds: 120,
    );

    expect(preview, isNotNull);
    expect(preview!.totalFareMinorUnits, 2043);
    expect(preview.trafficSurchargeMinorUnits, 36);
    expect(preview.platformMarginMinorUnits, 491);
  });

  test('operatorPricingPolicy parses persisted pricing policies', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/operator/pricing_policy');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T13:30:00Z',
          'policies': <Map<String, Object?>>[
            <String, Object?>{
              'ride_class': 'economy',
              'base_fare_minor_units': 700,
              'per_km_minor_units': 130,
              'per_minute_minor_units': 35,
              'traffic_delay_per_minute_minor_units': 18,
              'booking_fee_minor_units': 150,
              'minimum_fare_minor_units': 1100,
              'driver_share_bps': 8200,
              'updated_at': '2026-04-02T13:20:00Z',
              'updated_by_account_id': 'ops-1',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final dashboard = await api.operatorPricingPolicy();
    expect(dashboard, isNotNull);
    expect(dashboard!.policies.single.rideClass, 'economy');
    expect(dashboard.policies.single.driverShareBps, 8200);
  });

  test('upsertOperatorPricingPolicy posts pricing payload and parses response',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/rides/operator/pricing_policy');
      expect(request.headers['content-type'], 'application/json');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['ride_class'], 'economy');
      expect(payload['base_fare_minor_units'], 720);
      expect(payload['driver_share_bps'], 8250);
      return http.Response(
        jsonEncode(<String, Object?>{
          'ride_class': 'economy',
          'base_fare_minor_units': 720,
          'per_km_minor_units': 132,
          'per_minute_minor_units': 36,
          'traffic_delay_per_minute_minor_units': 19,
          'booking_fee_minor_units': 155,
          'minimum_fare_minor_units': 1120,
          'driver_share_bps': 8250,
          'updated_at': '2026-04-02T13:35:00Z',
          'updated_by_account_id': 'city-manager-1',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final policy = await api.upsertOperatorPricingPolicy(
      rideClass: 'economy',
      baseFareMinorUnits: 720,
      perKmMinorUnits: 132,
      perMinuteMinorUnits: 36,
      trafficDelayPerMinuteMinorUnits: 19,
      bookingFeeMinorUnits: 155,
      minimumFareMinorUnits: 1120,
      driverShareBps: 8250,
    );
    expect(policy, isNotNull);
    expect(policy!.baseFareMinorUnits, 720);
    expect(policy.updatedByAccountId, 'city-manager-1');
  });

  test('trackingSnapshot parses timeline and latest driver location', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path,
          '/me/rides/trips/RIDE1234567890ABCD123456/tracking');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ride': <String, Object?>{
            'ride_id': 'RIDE1234567890ABCD123456',
            'pickup': 'Umayyad Square',
            'destination': 'Bab Touma',
            'ride_class': 'economy',
            'driver_name': 'Maya',
            'car_plate': 'BA-1586',
            'eta_minutes': 7,
            'fare_estimate_cents': 1880,
            'status': 'driver_arriving',
            'created_at': '2026-04-02T14:00:00Z',
            'last_updated_at': '2026-04-02T14:06:00Z',
          },
          'latest_driver_location': <String, Object?>{
            'event_id': 11,
            'event_kind': 'driver_location',
            'status': 'driver_arriving',
            'actor_account_id': 'driver-1',
            'location': <String, Object?>{
              'lat': 33.5138,
              'lon': 36.2765,
              'accuracy_meters': 14,
              'speed_kmh': 31,
              'heading_degrees': 82,
            },
            'created_at': '2026-04-02T14:06:10Z',
          },
          'timeline': <Map<String, Object?>>[
            <String, Object?>{
              'event_id': 1,
              'event_kind': 'ride_created',
              'status': 'ride_requested',
              'created_at': '2026-04-02T14:00:00Z',
            },
            <String, Object?>{
              'event_id': 6,
              'event_kind': 'status_changed',
              'status': 'driver_arriving',
              'created_at': '2026-04-02T14:05:00Z',
            },
            <String, Object?>{
              'event_id': 11,
              'event_kind': 'driver_location',
              'status': 'driver_arriving',
              'location': <String, Object?>{
                'lat': 33.5138,
                'lon': 36.2765,
              },
              'created_at': '2026-04-02T14:06:10Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final snapshot = await api.trackingSnapshot('RIDE1234567890ABCD123456');

    expect(snapshot, isNotNull);
    expect(snapshot!.ride.driverName, 'Maya');
    expect(snapshot.latestDriverLocation, isNotNull);
    expect(snapshot.latestDriverLocation!.location!.lat,
        closeTo(33.5138, 0.00001));
    expect(snapshot.timeline, hasLength(3));
  });

  test(
      'trackingSnapshot falls back to live_state for synthetic driver location',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path,
          '/me/rides/trips/RIDE1234567890ABCD123456/tracking');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ride': <String, Object?>{
            'ride_id': 'RIDE1234567890ABCD123456',
            'pickup': 'Umayyad Square',
            'destination': 'Bab Touma',
            'ride_class': 'economy',
            'driver_name': 'Maya',
            'car_plate': 'BA-1586',
            'eta_minutes': 7,
            'fare_estimate_cents': 1880,
            'status': 'driver_arriving',
            'created_at': '2026-04-02T14:00:00Z',
            'last_updated_at': '2026-04-02T14:06:00Z',
          },
          'live_state': <String, Object?>{
            'ride_id': 'RIDE1234567890ABCD123456',
            'rider_account_id': 'rider-1',
            'driver_account_id': 'driver-1',
            'driver_name': 'Maya',
            'car_plate': 'BA-1586',
            'stage': 'driver_arriving',
            'location': <String, Object?>{
              'lat': 33.5138,
              'lon': 36.2765,
              'accuracy_meters': 14,
              'speed_kmh': 31,
              'heading_degrees': 82,
            },
            'last_location_at': '2026-04-02T14:06:10Z',
            'updated_at': '2026-04-02T14:06:10Z',
          },
          'timeline': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final snapshot = await api.trackingSnapshot('RIDE1234567890ABCD123456');

    expect(snapshot, isNotNull);
    expect(snapshot!.latestDriverLocation, isNotNull);
    expect(snapshot.latestDriverLocation!.eventId, 0);
    expect(snapshot.latestDriverLocation!.location!.lat,
        closeTo(33.5138, 0.00001));
    expect(snapshot.latestDriverLocation!.accuracyMeters, 14);
    expect(snapshot.latestDriverLocation!.speedKmh, 31);
    expect(snapshot.latestDriverLocation!.headingDegrees, 82);
    expect(snapshot.timeline, isEmpty);
  });

  test('driverQueueTrips prefers dispatch_offers and falls back to queue',
      () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/me/rides/driver/dispatch_offers') {
        return http.Response('{}', 404);
      }
      if (request.url.path == '/me/rides/driver/queue') {
        return http.Response(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'ride_id': 'RIDEQUEUE1234567890ABCD12',
              'pickup': 'Bab Touma',
              'destination': 'Malki',
              'ride_class': 'economy',
              'driver_name': 'Maya',
              'car_plate': 'BA-1586',
              'eta_minutes': 6,
              'fare_estimate_cents': 2100,
              'status': 'ride_requested',
              'created_at': '2026-04-02T14:00:00Z',
              'last_updated_at': '2026-04-02T14:00:00Z',
            },
          ]),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final queue = await api.driverQueueTrips(limit: 12);

    expect(
      paths,
      equals(const <String>[
        '/me/rides/driver/dispatch_offers',
        '/me/rides/driver/queue',
      ]),
    );
    expect(queue, hasLength(1));
    expect(queue.single.rideId, 'RIDEQUEUE1234567890ABCD12');
  });

  test('sendDriverLocationPing posts coordinates and parses receipt', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path,
          '/me/rides/driver/trips/RIDE1234567890ABCD123456/location_ping');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['lat'], 33.5138);
      expect(payload['lon'], 36.2765);
      expect(payload['accuracy_meters'], 18);
      return http.Response(
        jsonEncode(<String, Object?>{
          'ride_id': 'RIDE1234567890ABCD123456',
          'status': 'driver_arriving',
          'location': <String, Object?>{
            'lat': 33.5138,
            'lon': 36.2765,
            'accuracy_meters': 18,
            'speed_kmh': 24,
            'heading_degrees': 91,
          },
          'ok': true,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final receipt = await api.sendDriverLocationPing(
      rideId: 'RIDE1234567890ABCD123456',
      point: const RideGeoPoint(lat: 33.5138, lon: 36.2765),
      accuracyMeters: 18,
      speedKmh: 24,
      headingDegrees: 91,
    );

    expect(receipt, isNotNull);
    expect(receipt!.rideId, 'RIDE1234567890ABCD123456');
    expect(receipt.status, RideTripStatus.driverArriving);
    expect(receipt.location.lon, closeTo(36.2765, 0.00001));
  });

  test(
      'riderWalletSnapshot normalizes payment buckets into ride wallet snapshot',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/payments/wallets/WALLET123/buckets');
      return http.Response(
        jsonEncode(<String, Object?>{
          'wallet_id': 'WALLET123',
          'currency': 'SYP',
          'cash_balance_cents': 100000,
          'promo_credit_cents': 4000,
          'refund_credit_cents': 2500,
          'corporate_credit_cents': 9000,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final snapshot = await api.riderWalletSnapshot(
      walletId: 'WALLET123',
      riderId: 'rider-1',
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.riderId, 'rider-1');
    expect(snapshot.bucketBalance(RideWalletBucketType.cashBalance), 100000);
    expect(snapshot.bucketBalance(RideWalletBucketType.corporateCredit), 9000);
  });

  test('operatorLiveBoard parses counts and trip lists from BFF', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/operator/live_board');
      expect(request.url.queryParameters['open_limit'], '12');
      expect(request.url.queryParameters['active_limit'], '12');
      return http.Response(
        jsonEncode(<String, Object?>{
          'counts': <String, Object?>{
            'open_dispatches': 4,
            'active_trips': 7,
            'en_route_trips': 3,
            'in_progress_trips': 2,
            'payment_failures': 1,
            'online_drivers': 5,
          },
          'summary': <String, Object?>{
            'generated_at': '2026-04-02T10:00:00Z',
            'open_dispatch_value_minor_units': 8400,
            'active_trip_value_minor_units': 27100,
            'completed_today_count': 11,
            'completed_today_value_minor_units': 55200,
            'avg_open_eta_seconds': 540,
            'avg_active_eta_seconds': 910,
            'active_driver_count': 4,
            'idle_online_drivers': 1,
            'driver_utilization_bps': 8000,
            'capacity_gap_dispatches': 3,
            'stalled_dispatches': 2,
            'overdue_arrivals': 1,
            'long_running_trips': 1,
            'silent_tracking_trips': 2,
            'metadata_gaps': 0,
            'class_breakdown': <Map<String, Object?>>[
              <String, Object?>{
                'ride_class': 'economy',
                'open_dispatches': 3,
                'active_trips': 4,
                'completed_today_count': 8,
                'open_dispatch_value_minor_units': 5600,
                'active_trip_value_minor_units': 14800,
                'completed_today_value_minor_units': 30100,
              },
            ],
            'alerts': <Map<String, Object?>>[
              <String, Object?>{
                'code': 'payment_failures',
                'severity': 'critical',
                'title': 'Payment failures require intervention',
                'detail': '1 rides are currently blocked in payment_failed.',
              },
            ],
          },
          'open_dispatches': <Map<String, Object?>>[
            <String, Object?>{
              'ride_id': 'RIDEOPEN1234567890ABCD1234',
              'pickup': 'Umayyad Square',
              'destination': 'Bab Touma',
              'ride_class': 'economy',
              'driver_name': 'Driver pending',
              'car_plate': '--',
              'fare_estimate_cents': 1400,
              'eta_minutes': 8,
              'status': 'ride_requested',
              'created_at': '2026-03-31T09:10:00Z',
              'last_updated_at': '2026-03-31T09:10:00Z',
            },
          ],
          'active_trips': <Map<String, Object?>>[
            <String, Object?>{
              'ride_id': 'RIDEACTIVE1234567890ABCD1',
              'pickup': 'Mazzeh',
              'destination': 'Damascus Airport',
              'ride_class': 'premium',
              'driver_name': 'Maya',
              'car_plate': 'BA-1586',
              'fare_estimate_cents': 4200,
              'eta_minutes': 13,
              'status': 'driver_arriving',
              'created_at': '2026-03-31T09:11:00Z',
              'last_updated_at': '2026-03-31T09:12:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final board = await api.operatorLiveBoard();
    expect(board, isNotNull);
    expect(board!.counts.openDispatches, 4);
    expect(board.counts.activeTrips, 7);
    expect(board.counts.onlineDrivers, 5);
    expect(board.openDispatches, hasLength(1));
    expect(board.activeTrips, hasLength(1));
    expect(board.summary, isNotNull);
    expect(board.summary!.completedTodayValueMinorUnits, 55200);
    expect(board.summary!.activeDriverCount, 4);
    expect(board.summary!.idleOnlineDrivers, 1);
    expect(board.summary!.driverUtilizationBps, 8000);
    expect(board.summary!.capacityGapDispatches, 3);
    expect(board.summary!.silentTrackingTrips, 2);
    expect(board.summary!.classBreakdown.single.rideClass, 'economy');
    expect(
      board.summary!.alerts.single.severity,
      RideOperatorAlertSeverity.critical,
    );
    expect(board.activeTrips.first.driverName, 'Maya');
    expect(board.activeTrips.first.status, RideTripStatus.driverArriving);
  });

  test('operatorDriverRoster parses online and active drivers', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/operator/fleet/live');
      expect(request.url.queryParameters['limit'], '18');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T10:05:00Z',
          'online_drivers': 2,
          'tracking_online_drivers': 1,
          'active_trip_drivers': 1,
          'drivers': <Map<String, Object?>>[
            <String, Object?>{
              'driver_account_id': 'driver-1',
              'availability_status': 'online',
              'last_seen_at': '2026-04-02T10:04:30Z',
              'last_online_at': '2026-04-02T09:10:00Z',
              'updated_at': '2026-04-02T10:04:30Z',
              'location': <String, Object?>{
                'lat': 33.5138,
                'lon': 36.2765,
              },
              'driver_name': 'Maya',
              'car_plate': 'BA-1586',
              'active_ride_id': 'RIDEACTIVE1234567890ABCD1',
              'active_trip_status': 'driver_arriving',
              'active_pickup': 'Mazzeh',
              'active_destination': 'Damascus Airport',
            },
            <String, Object?>{
              'driver_account_id': 'driver-2',
              'availability_status': 'online',
              'last_seen_at': '2026-04-02T10:04:10Z',
              'last_online_at': '2026-04-02T09:50:00Z',
              'updated_at': '2026-04-02T10:04:10Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final roster = await api.operatorDriverRoster(limit: 18);
    expect(roster, isNotNull);
    expect(roster!.drivers, hasLength(2));
    expect(roster.drivers.first.driverName, 'Maya');
    expect(roster.drivers.first.isOnline, isTrue);
    expect(roster.drivers.first.isIdleOnline, isFalse);
    expect(
      roster.drivers.first.activeTripStatus,
      RideTripStatus.driverArriving,
    );
    expect(roster.drivers.first.location, isNotNull);
    expect(roster.drivers.last.isIdleOnline, isTrue);
  });

  test('operatorDriverRoster falls back to legacy driver_roster endpoint',
      () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(request.method, 'GET');
      expect(request.url.queryParameters['limit'], '18');
      if (request.url.path == '/me/rides/operator/fleet/live') {
        return http.Response('{}', 404);
      }
      if (request.url.path == '/me/rides/operator/driver_roster') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'generated_at': '2026-04-02T10:05:00Z',
            'drivers': <Map<String, Object?>>[
              <String, Object?>{
                'driver_account_id': 'driver-1',
                'availability_status': 'online',
                'last_seen_at': '2026-04-02T10:04:30Z',
                'updated_at': '2026-04-02T10:04:30Z',
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final roster = await api.operatorDriverRoster(limit: 18);

    expect(
      paths,
      equals(const <String>[
        '/me/rides/operator/fleet/live',
        '/me/rides/operator/driver_roster',
      ]),
    );
    expect(roster, isNotNull);
    expect(roster!.drivers, hasLength(1));
  });

  test('driverPresence parses server-backed presence state', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/driver/presence');
      return http.Response(
        jsonEncode(<String, Object?>{
          'driver_account_id': 'driver-1',
          'online': true,
          'last_seen_at': '2026-04-02T15:00:00Z',
          'last_online_at': '2026-04-02T14:55:00Z',
          'location': <String, Object?>{
            'lat': 33.5138,
            'lon': 36.2765,
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final presence = await api.driverPresence();
    expect(presence, isNotNull);
    expect(presence!.online, isTrue);
    expect(presence.location, isNotNull);
    expect(presence.location!.lat, closeTo(33.5138, 0.0001));
  });

  test('driverActiveTrip parses direct trip payload from live bff shape',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/driver/trips/active');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ride_id': 'RIDEDIRECT1234567890ABCDE',
          'pickup': 'Umayyad Square',
          'destination': 'Bab Touma',
          'ride_class': 'economy',
          'driver_name': 'Maya',
          'car_plate': 'BA-1586',
          'eta_minutes': 6,
          'fare_estimate_cents': 710,
          'status': 'driver_assigned',
          'created_at': '2026-04-03T04:25:53Z',
          'last_updated_at': '2026-04-03T04:27:48Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final trip = await api.driverActiveTrip();
    expect(trip, isNotNull);
    expect(trip!.rideId, 'RIDEDIRECT1234567890ABCDE');
    expect(trip.driverName, 'Maya');
    expect(trip.status, RideTripStatus.driverAssigned);
  });

  test('driverActiveTrip parses wrapped active trip payload', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/driver/trips/active');
      return http.Response(
        jsonEncode(<String, Object?>{
          'active': <String, Object?>{
            'ride_id': 'RIDEWRAPPED123456789ABCD',
            'pickup': 'Midan',
            'destination': 'Mazzeh',
            'ride_class': 'economy',
            'driver_name': 'Maya',
            'car_plate': 'BA-1586',
            'eta_minutes': 4,
            'fare_estimate_cents': 990,
            'status': 'driver_arriving',
            'created_at': '2026-04-03T04:25:53Z',
            'last_updated_at': '2026-04-03T04:27:48Z',
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final trip = await api.driverActiveTrip();
    expect(trip, isNotNull);
    expect(trip!.rideId, 'RIDEWRAPPED123456789ABCD');
    expect(trip.status, RideTripStatus.driverArriving);
  });

  test('setDriverPresence posts online heartbeat and parses response',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/rides/driver/presence');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['online'], isTrue);
      expect(payload['lat'], 33.51);
      expect(payload['lon'], 36.27);
      expect(payload['driver_name'], 'Prod Driver');
      expect(payload['car_plate'], 'SH001');
      return http.Response(
        jsonEncode(<String, Object?>{
          'driver_account_id': 'driver-1',
          'online': true,
          'last_seen_at': '2026-04-02T15:02:00Z',
          'last_online_at': '2026-04-02T15:02:00Z',
          'driver_name': 'Prod Driver',
          'car_plate': 'SH001',
          'location': <String, Object?>{
            'lat': 33.51,
            'lon': 36.27,
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final presence = await api.setDriverPresence(
      online: true,
      lat: 33.51,
      lon: 36.27,
      driverName: 'Prod Driver',
      carPlate: 'SH001',
    );
    expect(presence, isNotNull);
    expect(presence!.online, isTrue);
    expect(presence.driverName, 'Prod Driver');
    expect(presence.carPlate, 'SH001');
    expect(presence.location!.lon, closeTo(36.27, 0.0001));
  });

  test('driverFinanceDashboard parses payout and reserve summary', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/driver/finance_dashboard');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T12:20:00Z',
          'wallet_id': 'WALLET123',
          'platform_payout_wallet_id': 'FEE-WALLET-1',
          'ledger': <String, Object?>{
            'driver_id': 'driver-1',
            'earnings_available_cents': 25000,
            'held_reserve_cents': 4000,
            'debt_cents': 1500,
            'payout_pending_cents': 2000,
            'bonuses_cents': 1200,
            'cash_collected_cents': 500,
          },
          'completed_today_count': 9,
          'completed_today_value_minor_units': 48200,
          'active_trip_value_minor_units': 6200,
          'net_available_minor_units': 22200,
          'recommended_reserve_minor_units': 4820,
          'recommended_payout_minor_units': 17880,
          'pending_settlement_minor_units': 4000,
          'reserve_coverage_bps': 8298,
          'payout_blocked': false,
          'alerts': <Map<String, Object?>>[
            <String, Object?>{
              'code': 'driver_pending_settlement',
              'severity': 'high',
              'title': 'Cash or debt settlement required',
              'detail': '4,000 SYP must settle before the next payout window.',
            },
          ],
          'recent_completed_trips': <Map<String, Object?>>[
            <String, Object?>{
              'ride_id': 'RIDECOMPLETE1234567890ABCD',
              'pickup': 'Abu Rummaneh',
              'destination': 'Old Damascus',
              'ride_class': 'economy',
              'driver_name': 'Maya',
              'car_plate': 'BA-1586',
              'fare_estimate_cents': 3200,
              'eta_minutes': 9,
              'status': 'trip_completed',
              'created_at': '2026-04-02T11:50:00Z',
              'last_updated_at': '2026-04-02T12:00:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final dashboard = await api.driverFinanceDashboard();
    expect(dashboard, isNotNull);
    expect(dashboard!.walletId, 'WALLET123');
    expect(dashboard.platformPayoutWalletId, 'FEE-WALLET-1');
    expect(dashboard.ledger.driverId, 'driver-1');
    expect(dashboard.recommendedPayoutMinorUnits, 17880);
    expect(dashboard.alerts.single.severity, RideOperatorAlertSeverity.high);
    expect(dashboard.recentCompletedTrips.single.status,
        RideTripStatus.tripCompleted);
  });

  test('driverShiftSummary parses online session workload', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/driver/shift_summary');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T12:40:00Z',
          'online': true,
          'last_seen_at': '2026-04-02T12:39:30Z',
          'last_online_at': '2026-04-02T10:10:00Z',
          'current_online_duration_seconds': 9000,
          'open_dispatches_visible': 4,
          'active_trip_count': 1,
          'completed_today_count': 6,
          'completed_today_value_minor_units': 28100,
          'payment_failed_count': 1,
          'avg_completed_eta_seconds': 780,
          'last_completed_at': '2026-04-02T12:15:00Z',
          'alerts': <Map<String, Object?>>[
            <String, Object?>{
              'code': 'driver_shift_payment_failures',
              'severity': 'high',
              'title': 'A completed fare still needs payment recovery',
              'detail':
                  '1 rides are still blocked in payment_failed and may delay payout settlement.',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final summary = await api.driverShiftSummary();
    expect(summary, isNotNull);
    expect(summary!.online, isTrue);
    expect(summary.currentOnlineDurationSeconds, 9000);
    expect(summary.openDispatchesVisible, 4);
    expect(summary.paymentFailedCount, 1);
    expect(summary.alerts.single.code, 'driver_shift_payment_failures');
  });

  test('driverDocuments parses readiness and masked documents', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/driver/documents');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T12:45:00Z',
          'driver_account_id': 'driver-1',
          'summary': <String, Object?>{
            'missing_documents': 1,
            'pending_documents': 1,
            'approved_documents': 2,
            'rejected_documents': 0,
            'expired_documents': 0,
            'blocking_issues': 2,
            'ready_to_drive': false,
          },
          'documents': <Map<String, Object?>>[
            <String, Object?>{
              'document_id': 'ride_doc_1',
              'driver_account_id': 'driver-1',
              'document_type': 'driver_license',
              'document_number_masked': '••••1234',
              'issuing_country': 'SY',
              'status': 'approved',
              'submitted_at': '2026-04-01T10:00:00Z',
              'reviewed_at': '2026-04-01T11:00:00Z',
              'expires_at': '2027-04-01T00:00:00Z',
              'review_note': null,
            },
            <String, Object?>{
              'document_id': null,
              'driver_account_id': 'driver-1',
              'document_type': 'insurance',
              'document_number_masked': null,
              'issuing_country': null,
              'status': 'missing',
              'submitted_at': null,
              'reviewed_at': null,
              'expires_at': null,
              'review_note': null,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final dashboard = await api.driverDocuments();
    expect(dashboard, isNotNull);
    expect(dashboard!.driverAccountId, 'driver-1');
    expect(dashboard.summary.blockingIssues, 2);
    expect(dashboard.documents.first.documentType,
        RideDriverDocumentType.driverLicense);
    expect(dashboard.documents.last.status, RideDriverDocumentStatus.missing);
  });

  test('upsertDriverDocument posts payload and parses response', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/rides/driver/documents');
      expect(request.headers['content-type'], 'application/json');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['document_type'], 'insurance');
      expect(payload['document_number'], 'INS-8899');
      expect(payload['issuing_country'], 'SY');
      expect(payload['expires_at'], '2027-04-02T00:00:00Z');
      return http.Response(
        jsonEncode(<String, Object?>{
          'document_id': 'ride_doc_insurance_1',
          'driver_account_id': 'driver-1',
          'document_type': 'insurance',
          'document_number_masked': '••••8899',
          'issuing_country': 'SY',
          'status': 'pending',
          'submitted_at': '2026-04-02T12:55:00Z',
          'reviewed_at': null,
          'expires_at': '2027-04-02T00:00:00Z',
          'review_note': null,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final document = await api.upsertDriverDocument(
      documentType: RideDriverDocumentType.insurance,
      documentNumber: 'INS-8899',
      issuingCountry: 'sy',
      expiresAtIso: '2027-04-02T00:00:00Z',
    );
    expect(document, isNotNull);
    expect(document!.documentId, 'ride_doc_insurance_1');
    expect(document.status, RideDriverDocumentStatus.pending);
  });

  test('createDriverPayoutRequest uses challenge headers and parses response',
      () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.url.path == '/auth/payment_attestation/challenge') {
        expect(request.method, 'POST');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['device_id'], isNotEmpty);
        expect(payload['operation'], 'payments_requests_create');
        expect(
          payload['resource_id'],
          'from_wallet_id=driver-wallet-1&to_wallet_id=fee-wallet-1&amount_cents=17880',
        );
        return http.Response(
          jsonEncode(<String, Object?>{'enabled': false}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/me/rides/driver/payout_requests') {
        expect(request.method, 'POST');
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        expect(request.headers['X-Device-ID'], isNotEmpty);
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['amount_minor_units'], 17880);
        expect(payload['expires_in_secs'], 3600);
        return http.Response(
          jsonEncode(<String, Object?>{
            'request_id': 'req_driver_payout_1',
            'from_wallet_id': 'driver-wallet-1',
            'to_wallet_id': 'fee-wallet-1',
            'amount_minor_units': 17880,
            'currency': 'SYP',
            'message': 'ride_driver_payout',
            'status': 'pending',
            'created_at': '2026-04-02T12:26:00Z',
            'age_seconds': 0,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final request = await api.createDriverPayoutRequest(
      driverWalletId: 'driver-wallet-1',
      platformPayoutWalletId: 'fee-wallet-1',
      amountMinorUnits: 17880,
      expiresInSeconds: 3600,
    );

    expect(request, isNotNull);
    expect(request!.requestId, 'req_driver_payout_1');
    expect(request.status, RidePayoutRequestStatus.pending);
    expect(
      calls,
      containsAll(<String>[
        'POST /auth/payment_attestation/challenge',
        'POST /me/rides/driver/payout_requests',
      ]),
    );
  });

  test('operatorCaseQueue parses derived case workload', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/operator/case_queue');
      expect(request.url.queryParameters['limit'], '20');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T12:25:00Z',
          'totals': <String, Object?>{
            'open_cases': 5,
            'critical_cases': 1,
            'high_cases': 3,
            'finance_cases': 1,
            'support_cases': 2,
            'compliance_cases': 2,
          },
          'cases': <Map<String, Object?>>[
            <String, Object?>{
              'case_id': 'RIDEFAIL123:payment_failed',
              'category': 'finance',
              'severity': 'critical',
              'title': 'Payment failed after trip completion',
              'detail':
                  'The ride is blocked in payment_failed and needs finance intervention.',
              'suggested_action':
                  'Retry collection or move the trip into manual settlement.',
              'ride_id': 'RIDEFAIL123',
              'ride_class': 'premium',
              'status': 'payment_failed',
              'pickup': 'Malki',
              'destination': 'Qasaa',
              'driver_name': 'Maya',
              'car_plate': 'BA-1586',
              'fare_estimate_minor_units': 5400,
              'age_seconds': 3100,
              'created_at': '2026-04-02T11:20:00Z',
              'last_updated_at': '2026-04-02T11:35:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final queue = await api.operatorCaseQueue();
    expect(queue, isNotNull);
    expect(queue!.totals.openCases, 5);
    expect(queue.cases.single.category, RideOperatorCaseCategory.finance);
    expect(queue.cases.single.severity, RideOperatorAlertSeverity.critical);
    expect(queue.cases.single.status, RideTripStatus.paymentFailed);
  });

  test('supportTickets parses rider support tickets', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/support_tickets');
      expect(request.url.queryParameters['limit'], '6');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T14:30:00Z',
          'tickets': <Map<String, Object?>>[
            <String, Object?>{
              'ticket_id': 'rst_1',
              'ride_id': 'RIDE-1',
              'rider_account_id': 'rider-1',
              'category': 'lost_item',
              'subject': 'Lost item · RIDE-1',
              'body': 'Left a bag in the car.',
              'preferred_contact': 'phone',
              'status': 'open',
              'resolution_note': null,
              'resolved_by_account_id': null,
              'resolved_at': null,
              'ride_class': 'economy',
              'trip_status': 'trip_completed',
              'pickup': 'Mazzeh',
              'destination': 'Damascus Airport',
              'driver_name': 'Maya',
              'car_plate': 'BA-1586',
              'created_at': '2026-04-02T14:00:00Z',
              'updated_at': '2026-04-02T14:10:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final list = await api.supportTickets(limit: 6);
    expect(list, isNotNull);
    expect(list!.tickets.single.category, RideSupportTicketCategory.lostItem);
    expect(list.tickets.single.preferredContact,
        RideSupportTicketContactPreference.phone);
  });

  test('createSupportTicket posts rider support payload and parses response',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/rides/support_tickets');
      expect(request.headers['content-type'], 'application/json');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['ride_id'], 'RIDE-1');
      expect(payload['category'], 'payment_issue');
      expect(payload['preferred_contact'], 'in_app');
      expect(payload['body'], 'Wallet debit mismatch.');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ticket_id': 'rst_2',
          'ride_id': 'RIDE-1',
          'rider_account_id': 'rider-1',
          'category': 'payment_issue',
          'subject': 'Payment issue · RIDE-1',
          'body': 'Wallet debit mismatch.',
          'preferred_contact': 'in_app',
          'status': 'open',
          'resolution_note': null,
          'resolved_by_account_id': null,
          'resolved_at': null,
          'ride_class': 'economy',
          'trip_status': 'payment_failed',
          'pickup': 'Umayyad Square',
          'destination': 'Bab Touma',
          'driver_name': 'Maya',
          'car_plate': 'BA-1586',
          'created_at': '2026-04-02T14:20:00Z',
          'updated_at': '2026-04-02T14:20:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final ticket = await api.createSupportTicket(
      rideId: 'RIDE-1',
      category: RideSupportTicketCategory.paymentIssue,
      body: 'Wallet debit mismatch.',
    );
    expect(ticket, isNotNull);
    expect(ticket!.ticketId, 'rst_2');
    expect(ticket.category, RideSupportTicketCategory.paymentIssue);
  });

  test('operatorSupportQueue parses support workload', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/operator/support_queue');
      expect(request.url.queryParameters['limit'], '16');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T14:40:00Z',
          'totals': <String, Object?>{
            'open_tickets': 4,
            'urgent_tickets': 2,
          },
          'tickets': <Map<String, Object?>>[
            <String, Object?>{
              'ticket_id': 'rst_3',
              'ride_id': 'RIDE-2',
              'rider_account_id': 'rider-2',
              'category': 'safety',
              'subject': 'Safety incident · RIDE-2',
              'body': 'Driver was speeding.',
              'preferred_contact': 'phone',
              'status': 'open',
              'resolution_note': null,
              'resolved_by_account_id': null,
              'resolved_at': null,
              'ride_class': 'premium',
              'trip_status': 'trip_completed',
              'pickup': 'Mazzeh',
              'destination': 'Old Damascus',
              'driver_name': 'Omar',
              'car_plate': 'DA-1001',
              'created_at': '2026-04-02T14:15:00Z',
              'updated_at': '2026-04-02T14:35:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final queue = await api.operatorSupportQueue(limit: 16);
    expect(queue, isNotNull);
    expect(queue!.totals.urgentTickets, 2);
    expect(queue.tickets.single.category, RideSupportTicketCategory.safety);
  });

  test('operatorDocumentQueue parses compliance document backlog', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/operator/document_queue');
      expect(request.url.queryParameters['limit'], '16');
      expect(request.url.queryParameters['status'], 'pending');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T12:55:00Z',
          'totals': <String, Object?>{
            'pending_documents': 4,
            'rejected_documents': 2,
            'expired_documents': 1,
            'blocked_drivers': 5,
          },
          'documents': <Map<String, Object?>>[
            <String, Object?>{
              'document_id': 'ride_doc_2',
              'driver_account_id': 'driver-2',
              'document_type': 'vehicle_registration',
              'document_number_masked': '••••4567',
              'issuing_country': 'SY',
              'status': 'pending',
              'submitted_at': '2026-04-02T08:00:00Z',
              'reviewed_at': null,
              'expires_at': '2027-03-01T00:00:00Z',
              'review_note': null,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final queue = await api.operatorDocumentQueue(status: 'pending', limit: 16);
    expect(queue, isNotNull);
    expect(queue!.totals.pendingDocuments, 4);
    expect(queue.documents.single.documentType,
        RideDriverDocumentType.vehicleRegistration);
  });

  test('operatorFinanceQueue parses payout totals and requests', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/rides/operator/finance_queue');
      expect(request.url.queryParameters['limit'], '16');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-02T12:35:00Z',
          'fee_wallet_id': 'FEE-WALLET-1',
          'totals': <String, Object?>{
            'pending_requests': 2,
            'pending_amount_minor_units': 54000,
            'approved_requests': 3,
            'blocked_requests': 1,
            'oldest_pending_age_seconds': 1800,
          },
          'requests': <Map<String, Object?>>[
            <String, Object?>{
              'request_id': 'req_driver_payout_1',
              'from_wallet_id': 'driver-wallet-1',
              'to_wallet_id': 'FEE-WALLET-1',
              'amount_minor_units': 17880,
              'currency': 'SYP',
              'message': 'ride_driver_payout',
              'status': 'pending',
              'created_at': '2026-04-02T12:26:00Z',
              'age_seconds': 600,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final queue = await api.operatorFinanceQueue(limit: 16);
    expect(queue, isNotNull);
    expect(queue!.feeWalletId, 'FEE-WALLET-1');
    expect(queue.totals.pendingAmountMinorUnits, 54000);
    expect(queue.requests.single.requestId, 'req_driver_payout_1');
  });

  test('resolveOperatorSupportTicket posts resolution note and parses response',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/rides/operator/support_tickets/rst_3/resolve',
      );
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['note'], 'Customer contacted and refund queued.');
      return http.Response(
        jsonEncode(<String, Object?>{
          'ticket_id': 'rst_3',
          'ride_id': 'RIDE-2',
          'rider_account_id': 'rider-2',
          'category': 'safety',
          'subject': 'Safety incident · RIDE-2',
          'body': 'Driver was speeding.',
          'preferred_contact': 'phone',
          'status': 'resolved',
          'resolution_note': 'Customer contacted and refund queued.',
          'resolved_by_account_id': 'ops-1',
          'resolved_at': '2026-04-02T14:45:00Z',
          'ride_class': 'premium',
          'trip_status': 'trip_completed',
          'pickup': 'Mazzeh',
          'destination': 'Old Damascus',
          'driver_name': 'Omar',
          'car_plate': 'DA-1001',
          'created_at': '2026-04-02T14:15:00Z',
          'updated_at': '2026-04-02T14:45:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final ticket = await api.resolveOperatorSupportTicket(
      ticketId: 'rst_3',
      note: 'Customer contacted and refund queued.',
    );
    expect(ticket, isNotNull);
    expect(ticket!.status, RideSupportTicketStatus.resolved);
    expect(ticket.resolutionNote, 'Customer contacted and refund queued.');
  });

  test(
      'approveOperatorPayoutRequest uses accept attestation and parses response',
      () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.url.path == '/auth/payment_attestation/challenge') {
        expect(request.method, 'POST');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['device_id'], isNotEmpty);
        expect(payload['operation'], 'payments_requests_accept');
        expect(
          payload['resource_id'],
          'rid=req_driver_payout_1&to_wallet_id=FEE-WALLET-1',
        );
        return http.Response(
          jsonEncode(<String, Object?>{'enabled': false}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.path ==
          '/me/rides/operator/payout_requests/req_driver_payout_1/approve') {
        expect(request.method, 'POST');
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        expect(request.headers['X-Device-ID'], isNotEmpty);
        expect(request.body, '{}');
        return http.Response(
          jsonEncode(<String, Object?>{
            'request_id': 'req_driver_payout_1',
            'from_wallet_id': 'driver-wallet-1',
            'to_wallet_id': 'FEE-WALLET-1',
            'amount_minor_units': 17880,
            'currency': 'SYP',
            'message': 'ride_driver_payout',
            'status': 'accepted',
            'created_at': '2026-04-02T12:26:00Z',
            'age_seconds': 60,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final request = await api.approveOperatorPayoutRequest(
      requestId: 'req_driver_payout_1',
      feeWalletId: 'FEE-WALLET-1',
    );

    expect(request, isNotNull);
    expect(request!.status, RidePayoutRequestStatus.accepted);
    expect(
      calls,
      containsAll(<String>[
        'POST /auth/payment_attestation/challenge',
        'POST /me/rides/operator/payout_requests/req_driver_payout_1/approve',
      ]),
    );
  });

  test('reviewOperatorDocument posts decision and parses response', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/rides/operator/documents/ride_doc_2/review',
      );
      expect(request.headers['content-type'], 'application/json');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['decision'], 'approve');
      expect(payload['note'], 'Documents verified.');
      return http.Response(
        jsonEncode(<String, Object?>{
          'document_id': 'ride_doc_2',
          'driver_account_id': 'driver-2',
          'document_type': 'vehicle_registration',
          'document_number_masked': '••••4567',
          'issuing_country': 'SY',
          'status': 'approved',
          'submitted_at': '2026-04-02T08:00:00Z',
          'reviewed_at': '2026-04-02T13:05:00Z',
          'expires_at': '2027-03-01T00:00:00Z',
          'review_note': 'Documents verified.',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = RideMobilityApi(
      baseUrl: _apiBaseUrl,
      httpClient: client,
    );

    final document = await api.reviewOperatorDocument(
      documentId: 'ride_doc_2',
      decision: 'approve',
      note: 'Documents verified.',
    );
    expect(document, isNotNull);
    expect(document!.status, RideDriverDocumentStatus.approved);
    expect(document.reviewNote, 'Documents verified.');
  });
}
