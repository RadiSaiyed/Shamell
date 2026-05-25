import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/coach_bus/coach_catalog_import_run_filter_store.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_batch_filter_store.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_preview_history_filter_store.dart';
import 'package:shamell_flutter/core/coach_bus/coach_platform_contracts.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
    await setSessionTokenForBaseUrl(
      _apiBaseUrl,
      '0123456789abcdef0123456789abcdef',
    );
  });

  test('journey option rejects non-SYP currency', () {
    final option = CoachJourneyOption.fromJson(<String, Object?>{
      'journey_id': 'journey_demo_express_direct',
      'operator_id': 'op_demo_express',
      'operator_name': 'Demo Express',
      'operator_integration_mode': 'hybrid',
      'departure_at': '2026-04-08T08:00:00Z',
      'arrival_at': '2026-04-08T12:30:00Z',
      'duration_minutes': 270,
      'transfer_count': 0,
      'seats_available': 8,
      'low_availability': false,
      'currency': 'EUR',
      'price_from_minor_units': 9180,
      'amenities': <String>['wifi', 'power_outlet'],
      'changeable': true,
      'refundable': true,
      'best_offer': <String, Object?>{
        'offer_id': 'offer_demo_express_direct',
        'operator_id': 'op_demo_express',
        'itinerary_id': 'iti_demo_direct',
        'currency': 'SYP',
        'total_minor_units': 9180,
        'seats_requested': 2,
        'hold_supported': true,
        'changeable': true,
        'refundable': true,
        'expires_at': '2026-04-07T12:05:00Z',
      },
      'realtime': <String, Object?>{
        'delay_minutes': 5,
        'trip_updates_fresh': true,
        'vehicle_positions_fresh': true,
        'service_alerts_fresh': true,
      },
    });

    expect(option, isNull);
  });

  test('bootstrap parses coach platform metadata', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/bootstrap');
      return http.Response(
        jsonEncode(<String, Object?>{
          'version': '2026-04-07',
          'surfaces': <String>['passenger', 'operator', 'crew', 'admin'],
          'commercial_boundaries': <String>[
            'offer',
            'booking',
            'ticket',
            'boarding',
            'settlement',
          ],
          'integration_modes': <String>['feed', 'api', 'hybrid'],
          'static_catalog_feeds': <String>['gtfs', 'netex'],
          'realtime_feeds': <String>[
            'gtfs_rt_trip_updates',
            'gtfs_rt_vehicle_positions',
            'gtfs_rt_service_alerts',
            'siri',
          ],
          'booking_states': <String>['offer_created', 'ticketed'],
          'wallet_buckets': <String>[
            'cash_balance',
            'promo_credit',
            'refund_credit',
            'gift_card_credit',
            'corporate_credit',
          ],
          'settlement_bases': <String>['ticketed', 'boarded'],
          'realtime_freshness_targets': <String, Object?>{
            'trip_updates_seconds': 90,
            'vehicle_positions_seconds': 90,
            'service_alerts_seconds': 600,
          },
          'operator_feed_health': <Object?>[
            <String, Object?>{
              'operator_id': 'op_demo_express',
              'operator_name': 'Demo Express',
              'operator_integration_mode': 'hybrid',
              'feed_kind': 'gtfs_rt_trip_updates',
              'source_kind': 'gtfs_rt',
              'sync_status': 'ok',
              'freshness_status': 'fresh',
              'last_attempted_at': '2026-04-09T07:55:00Z',
              'last_succeeded_at': '2026-04-09T07:55:00Z',
              'freshness_expires_at': '2026-04-09T07:56:30Z',
              'records_ingested': 4,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final bootstrap = await api.bootstrap();

    expect(bootstrap.version, '2026-04-07');
    expect(bootstrap.commercialBoundaries, contains('settlement'));
    expect(bootstrap.integrationModes, contains('hybrid'));
    expect(bootstrap.tripUpdatesFreshnessSeconds, 90);
    expect(bootstrap.serviceAlertsFreshnessSeconds, 600);
    expect(bootstrap.operatorFeedHealth, hasLength(1));
    expect(bootstrap.operatorFeedHealth.first.operatorName, 'Demo Express');
    expect(bootstrap.operatorFeedHealth.first.isHealthy, isTrue);
  });

  test('search parses journeys and embedded best offers', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/search');
      expect(request.url.queryParameters['from'], 'Damascus');
      expect(request.url.queryParameters['to'], 'Aleppo');
      expect(request.url.queryParameters['departure_date'], '2026-04-08');
      expect(request.url.queryParameters['passengers'], '2');
      return http.Response(
        jsonEncode(<String, Object?>{
          'query': <String, Object?>{
            'from': 'Damascus',
            'to': 'Aleppo',
            'departure_date': '2026-04-08',
            'passengers': 2,
          },
          'journeys': <Map<String, Object?>>[
            <String, Object?>{
              'journey_id': 'journey_demo_express_direct',
              'operator_id': 'op_demo_express',
              'operator_name': 'Demo Express',
              'operator_integration_mode': 'hybrid',
              'departure_at': '2026-04-08T08:00:00Z',
              'arrival_at': '2026-04-08T12:30:00Z',
              'duration_minutes': 270,
              'transfer_count': 0,
              'seats_available': 8,
              'low_availability': false,
              'currency': 'SYP',
              'price_from_minor_units': 9180,
              'amenities': <String>['wifi', 'power_outlet'],
              'changeable': true,
              'refundable': true,
              'best_offer': <String, Object?>{
                'offer_id': 'offer_demo_express_direct',
                'operator_id': 'op_demo_express',
                'itinerary_id': 'iti_demo_direct',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'seats_requested': 2,
                'hold_supported': true,
                'changeable': true,
                'refundable': true,
                'expires_at': '2026-04-07T12:05:00Z',
              },
              'realtime': <String, Object?>{
                'delay_minutes': 5,
                'trip_updates_fresh': true,
                'vehicle_positions_fresh': true,
                'service_alerts_fresh': true,
              },
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.search(
      from: 'Damascus',
      to: 'Aleppo',
      departureDate: '2026-04-08',
      passengers: 2,
    );

    expect(response.passengers, 2);
    expect(response.journeys.single.integrationMode,
        CoachOperatorIntegrationMode.hybrid);
    expect(response.journeys.single.bestOffer.seatsRequested, 2);
    expect(response.journeys.single.live.delayMinutes, 5);
  });

  test('operatorCatalogImportRuns parses catalog import audit history',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/operator/catalog_import_runs');
      expect(request.url.queryParameters['limit'], '8');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-09T10:00:00Z',
          'summary': <String, Object?>{
            'total_runs': 2,
            'succeeded_runs': 1,
            'failed_runs': 1,
            'running_runs': 0,
            'imported_records_total': 15,
            'latest_succeeded_at': '2026-04-09T09:55:00Z',
          },
          'import_runs': <Object?>[
            <String, Object?>{
              'import_run_id': 'catalogimportrun_demo_failed',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'trigger_kind': 'startup',
              'feed_locator': '/srv/feeds/operator_a',
              'replay_lineage_summary': <String, Object?>{
                'replay_run_count': 3,
                'latest_replay_run_id': 'catalogimportrun_demo_failed_replay_2',
                'latest_replay_started_at': '2026-04-15T10:10:00Z',
              },
              'source_artifact_id': 'catalogsourceartifact_demo_failed',
              'source_artifact': <String, Object?>{
                'artifact_id': 'catalogsourceartifact_demo_failed',
                'feed_kind': 'static_catalog',
                'source_kind': 'gtfs',
                'source_label': 'operator_a_feed.zip',
                'file_name': 'operator_a_feed.zip',
                'file_checksum_sha256': '${'a' * 64}',
                'content_length_bytes': 512,
                'extracted_file_count': 7,
                'feed_locator': '/srv/feeds/operator_a',
                'created_by_account_id': 'acct_ops_demo',
                'created_at': '2026-04-09T09:57:00Z',
              },
              'status': 'failed',
              'started_at': '2026-04-09T09:58:00Z',
              'finished_at': '2026-04-09T09:58:10Z',
              'counts': <String, Object?>{
                'operators': 0,
                'cities': 0,
                'stop_clusters': 0,
                'stops': 0,
                'lines': 0,
                'service_calendars': 0,
                'trips': 0,
                'fare_products': 0,
                'total_records': 0,
                'ready': false,
              },
              'error_message': 'required GTFS file missing: stops.txt',
              'issue_count': 1,
              'issues': <Object?>[
                <String, Object?>{
                  'issue_id': 'catalogimportissue_demo_failed_1',
                  'severity': 'error',
                  'stage': 'load_feed',
                  'code': 'required_file_missing',
                  'message': 'required GTFS file missing: stops.txt',
                  'file_name': 'stops.txt',
                },
              ],
            },
            <String, Object?>{
              'import_run_id': 'catalogimportrun_demo_ok',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'trigger_kind': 'scheduled',
              'feed_locator': '/srv/feeds/operator_a',
              'status': 'succeeded',
              'started_at': '2026-04-09T09:54:00Z',
              'finished_at': '2026-04-09T09:55:00Z',
              'counts': <String, Object?>{
                'operators': 1,
                'cities': 2,
                'stop_clusters': 2,
                'stops': 4,
                'lines': 1,
                'service_calendars': 1,
                'trips': 2,
                'fare_products': 2,
                'total_records': 15,
                'ready': true,
              },
            },
          ],
          'next_cursor': '2026-04-09T09:54:00Z|catalogimportrun_demo_ok',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogImportRuns();

    expect(response.summary.totalRuns, 2);
    expect(response.summary.importedRecordsTotal, 15);
    expect(response.importRuns.first.isFailed, isTrue);
    expect(
        response.importRuns.first.issues.single.code, 'required_file_missing');
    expect(response.importRuns.first.issues.single.fileName, 'stops.txt');
    expect(
      response.importRuns.first.sourceArtifact?.artifactId,
      'catalogsourceartifact_demo_failed',
    );
    expect(
      response.importRuns.first.sourceArtifactId,
      'catalogsourceartifact_demo_failed',
    );
    expect(
      response.importRuns.first.sourceArtifact?.sourceLabel,
      'operator_a_feed.zip',
    );
    expect(response.importRuns.first.replayLineageSummary?.replayRunCount, 3);
    expect(
      response.importRuns.first.replayLineageSummary?.latestReplayRunId,
      'catalogimportrun_demo_failed_replay_2',
    );
    expect(
      response.importRuns.first.replayLineageSummary?.latestReplayStartedAtIso,
      '2026-04-15T10:10:00Z',
    );
    expect(response.importRuns.last.counts.ready, isTrue);
    expect(
      response.nextCursor,
      '2026-04-09T09:54:00Z|catalogimportrun_demo_ok',
    );
  });

  test('operatorCatalogImportRunSavedViews parses server-backed saved views',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:00:00Z',
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'savedview_failed_attention',
              'account_id': 'acct_ops_shared',
              'name': 'Failed attention',
              'visibility_scope': 'shared_ops',
              'operator_ids': <String>['op_demo_express'],
              'status': 'failed',
              'replay_scope': 'attention',
              'severity': 'error',
              'stage': 'load_feed',
              'is_favorite': true,
              'last_used_at': '2026-04-16T08:01:00Z',
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-16T07:58:00Z',
              'updated_at': '2026-04-16T07:59:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorCatalogImportRunSavedViews();

    expect(savedViews, hasLength(1));
    expect(savedViews.single.viewId, 'savedview_failed_attention');
    expect(savedViews.single.accountId, 'acct_ops_shared');
    expect(savedViews.single.name, 'Failed attention');
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.operatorIds, const <String>['op_demo_express']);
    expect(savedViews.single.preferences.status, 'failed');
    expect(savedViews.single.preferences.replayScope, 'attention');
    expect(savedViews.single.preferences.issueSeverity, 'error');
    expect(savedViews.single.preferences.issueStage, 'load_feed');
    expect(savedViews.single.isFavorite, isTrue);
    expect(savedViews.single.lastUsedAtIso, '2026-04-16T08:01:00Z');
    expect(savedViews.single.isDefault, isFalse);
    expect(savedViews.single.canManage, isFalse);
    expect(savedViews.single.updatedAtIso, '2026-04-16T07:59:00Z');
  });

  test('operatorCatalogImportRunSavedViews forwards visibility scope filter',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:00:00Z',
          'saved_views': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorCatalogImportRunSavedViews(
      visibilityScope: 'shared_ops',
    );

    expect(savedViews, isEmpty);
  });

  test(
      'operatorCatalogImportRunSavedViews forwards shared owner account filter',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      expect(
        request.url.queryParameters['owner_account_id'],
        'acct_ops_shared',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:00:00Z',
          'saved_views': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorCatalogImportRunSavedViews(
      visibilityScope: 'shared_ops',
      ownerAccountId: 'acct_ops_shared',
    );

    expect(savedViews, isEmpty);
  });

  test('operatorCatalogImportRunSavedViews forwards shared operator filter',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      expect(request.url.queryParameters['operator_id'], 'op_demo_express');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:00:00Z',
          'saved_views': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorCatalogImportRunSavedViews(
      visibilityScope: 'shared_ops',
      operatorId: 'op_demo_express',
    );

    expect(savedViews, isEmpty);
  });

  test('operatorCatalogImportRunSavedViewOwners parses shared owner summaries',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:00:00Z',
          'saved_views': const <Object?>[],
          'shared_owner_summaries': <Object?>[
            <String, Object?>{
              'account_id': 'acct_ops_shared',
              'shared_view_count': 3,
            },
            <String, Object?>{
              'account_id': 'acct_ops_other',
              'shared_view_count': 1,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final owners = await api.operatorCatalogImportRunSavedViewOwners();

    expect(owners, hasLength(2));
    expect(owners.first.accountId, 'acct_ops_shared');
    expect(owners.first.sharedViewCount, 3);
    expect(owners.last.accountId, 'acct_ops_other');
  });

  test(
      'operatorCatalogImportRunSavedViewOperators parses shared operator summaries',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:00:00Z',
          'saved_views': const <Object?>[],
          'shared_operator_summaries': <Object?>[
            <String, Object?>{
              'operator_id': 'op_demo_express',
              'operator_name': 'Demo Express',
              'shared_view_count': 3,
            },
            <String, Object?>{
              'operator_id': 'op_border_runner',
              'operator_name': 'Border Runner',
              'shared_view_count': 1,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final operators = await api.operatorCatalogImportRunSavedViewOperators();

    expect(operators, hasLength(2));
    expect(operators.first.operatorId, 'op_demo_express');
    expect(operators.first.operatorName, 'Demo Express');
    expect(operators.first.sharedViewCount, 3);
    expect(operators.last.operatorId, 'op_border_runner');
  });

  test('upsertOperatorCatalogImportRunSavedView posts saved view mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-saved-view-upsert-1',
      );
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        <String, Object?>{
          'view_id': 'savedview_failed_attention',
          'name': 'Failed attention',
          'visibility_scope': 'shared_ops',
          'operator_ids': <String>['op_demo_express'],
          'status': 'failed',
          'replay_scope': 'attention',
          'severity': 'error',
          'stage': 'load_feed',
          'is_default': false,
        },
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'catalog_import_run_saved_view_upsert',
          'idempotency': <String, Object?>{
            'key': 'idem-coach-catalog-saved-view-upsert-1',
            'scope': 'coach_operator_catalog_import_run_saved_view_upsert',
            'request_fingerprint': 'fp_catalog_saved_view_upsert_1',
            'replayed': false,
            'derived_keys': <String, Object?>{},
          },
          'saved_view': <String, Object?>{
            'view_id': 'savedview_failed_attention',
            'account_id': 'acct_ops_shared',
            'name': 'Failed attention',
            'visibility_scope': 'shared_ops',
            'operator_ids': <String>['op_demo_express'],
            'status': 'failed',
            'replay_scope': 'attention',
            'severity': 'error',
            'stage': 'load_feed',
            'is_default': false,
            'can_manage': true,
            'created_at': '2026-04-16T07:58:00Z',
            'updated_at': '2026-04-16T07:59:30Z',
          },
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'savedview_failed_attention',
              'account_id': 'acct_ops_shared',
              'name': 'Failed attention',
              'visibility_scope': 'shared_ops',
              'operator_ids': <String>['op_demo_express'],
              'status': 'failed',
              'replay_scope': 'attention',
              'severity': 'error',
              'stage': 'load_feed',
              'is_default': false,
              'can_manage': true,
              'created_at': '2026-04-16T07:58:00Z',
              'updated_at': '2026-04-16T07:59:30Z',
            },
          ],
          'next_action': 'catalog_import_run_filters_ready',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.upsertOperatorCatalogImportRunSavedView(
      const CoachCatalogImportRunSavedView(
        viewId: 'savedview_failed_attention',
        name: 'Failed attention',
        visibilityScope: 'shared_ops',
        operatorIds: <String>['op_demo_express'],
        preferences: CoachCatalogImportRunFilterPreferences(
          status: 'failed',
          replayScope: 'attention',
          issueSeverity: 'error',
          issueStage: 'load_feed',
        ),
        createdAtIso: '2026-04-16T07:58:00Z',
        updatedAtIso: '2026-04-16T07:59:30Z',
      ),
      idempotencyKey: 'idem-coach-catalog-saved-view-upsert-1',
    );

    expect(savedViews, hasLength(1));
    expect(savedViews.single.viewId, 'savedview_failed_attention');
    expect(savedViews.single.accountId, 'acct_ops_shared');
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.operatorIds, const <String>['op_demo_express']);
    expect(savedViews.single.preferences.status, 'failed');
    expect(savedViews.single.preferences.issueSeverity, 'error');
    expect(savedViews.single.isDefault, isFalse);
    expect(savedViews.single.canManage, isTrue);
  });

  test('deleteOperatorCatalogImportRunSavedView posts delete mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views/savedview_failed_attention/delete',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-saved-view-delete-1',
      );
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        const <String, Object?>{},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'catalog_import_run_saved_view_delete',
          'idempotency': <String, Object?>{
            'key': 'idem-coach-catalog-saved-view-delete-1',
            'scope': 'coach_operator_catalog_import_run_saved_view_delete',
            'request_fingerprint': 'fp_catalog_saved_view_delete_1',
            'replayed': false,
            'derived_keys': <String, Object?>{},
          },
          'deleted_view_id': 'savedview_failed_attention',
          'saved_views': const <Object?>[],
          'next_action': 'catalog_import_run_filters_ready',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.deleteOperatorCatalogImportRunSavedView(
      'savedview_failed_attention',
      idempotencyKey: 'idem-coach-catalog-saved-view-delete-1',
    );

    expect(savedViews, isEmpty);
  });

  test('toggleOperatorCatalogImportRunSavedViewFavorite posts mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views/savedview_failed_attention/favorite',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-saved-view-favorite-1',
      );
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        <String, Object?>{'favorite': true},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'savedview_failed_attention',
              'account_id': 'acct_ops_shared',
              'name': 'Failed attention',
              'visibility_scope': 'shared_ops',
              'operator_ids': <String>['op_demo_express'],
              'status': 'failed',
              'replay_scope': 'attention',
              'severity': 'error',
              'stage': 'load_feed',
              'is_favorite': true,
              'is_default': false,
              'can_manage': true,
              'created_at': '2026-04-16T07:58:00Z',
              'updated_at': '2026-04-16T07:59:30Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews =
        await api.toggleOperatorCatalogImportRunSavedViewFavorite(
      'savedview_failed_attention',
      favorite: true,
      idempotencyKey: 'idem-coach-catalog-saved-view-favorite-1',
    );

    expect(savedViews, hasLength(1));
    expect(savedViews.single.isFavorite, isTrue);
  });

  test('markOperatorCatalogImportRunSavedViewUsed posts mutation', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_saved_views/savedview_failed_attention/use',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-saved-view-use-1',
      );
      expect(
        jsonDecode(request.body),
        <String, Object?>{'used_at': '2026-04-16T10:00:00Z'},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'view_id': 'savedview_failed_attention',
          'used_at': '2026-04-16T10:00:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final usedAtIso = await api.markOperatorCatalogImportRunSavedViewUsed(
      'savedview_failed_attention',
      usedAtIso: '2026-04-16T10:00:00Z',
      idempotencyKey: 'idem-coach-catalog-saved-view-use-1',
    );

    expect(usedAtIso, '2026-04-16T10:00:00Z');
  });

  test('operatorCatalogImportRunIssueSavedViews parses server-backed views',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:10:00Z',
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'catalogimportrunissuesavedview_errors',
              'account_id': 'acct_ops_shared',
              'name': 'Errors only',
              'visibility_scope': 'shared_ops',
              'operator_ids': <String>['op_demo_express'],
              'severity': 'error',
              'stage': 'all',
              'is_favorite': true,
              'last_used_at': '2026-04-16T08:06:00Z',
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-16T08:00:00Z',
              'updated_at': '2026-04-16T08:05:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorCatalogImportRunIssueSavedViews();

    expect(savedViews, hasLength(1));
    expect(
      savedViews.single.viewId,
      'catalogimportrunissuesavedview_errors',
    );
    expect(savedViews.single.accountId, 'acct_ops_shared');
    expect(savedViews.single.name, 'Errors only');
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.operatorIds, const <String>['op_demo_express']);
    expect(savedViews.single.preferences.severity, 'error');
    expect(savedViews.single.preferences.stage, 'all');
    expect(savedViews.single.isFavorite, isTrue);
    expect(savedViews.single.lastUsedAtIso, '2026-04-16T08:06:00Z');
    expect(savedViews.single.isDefault, isFalse);
    expect(savedViews.single.canManage, isFalse);
    expect(savedViews.single.updatedAtIso, '2026-04-16T08:05:00Z');
  });

  test(
      'operatorCatalogImportRunIssueSavedViews forwards visibility scope filter',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'personal');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:10:00Z',
          'saved_views': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorCatalogImportRunIssueSavedViews(
      visibilityScope: 'personal',
    );

    expect(savedViews, isEmpty);
  });

  test(
      'operatorCatalogImportRunIssueSavedViews forwards shared owner account filter',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      expect(
        request.url.queryParameters['owner_account_id'],
        'acct_ops_shared',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:10:00Z',
          'saved_views': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorCatalogImportRunIssueSavedViews(
      visibilityScope: 'shared_ops',
      ownerAccountId: 'acct_ops_shared',
    );

    expect(savedViews, isEmpty);
  });

  test(
      'operatorCatalogImportRunIssueSavedViews forwards shared operator filter',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      expect(request.url.queryParameters['operator_id'], 'op_demo_express');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:10:00Z',
          'saved_views': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorCatalogImportRunIssueSavedViews(
      visibilityScope: 'shared_ops',
      operatorId: 'op_demo_express',
    );

    expect(savedViews, isEmpty);
  });

  test(
      'operatorCatalogImportRunIssueSavedViewOwners parses shared owner summaries',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:10:00Z',
          'saved_views': const <Object?>[],
          'shared_owner_summaries': <Object?>[
            <String, Object?>{
              'account_id': 'acct_ops_shared',
              'shared_view_count': 2,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final owners = await api.operatorCatalogImportRunIssueSavedViewOwners();

    expect(owners, hasLength(1));
    expect(owners.single.accountId, 'acct_ops_shared');
    expect(owners.single.sharedViewCount, 2);
  });

  test(
      'operatorCatalogImportRunIssueSavedViewOperators parses shared operator summaries',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-16T08:10:00Z',
          'saved_views': const <Object?>[],
          'shared_operator_summaries': <Object?>[
            <String, Object?>{
              'operator_id': 'op_demo_express',
              'operator_name': 'Demo Express',
              'shared_view_count': 2,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final operators =
        await api.operatorCatalogImportRunIssueSavedViewOperators();

    expect(operators, hasLength(1));
    expect(operators.single.operatorId, 'op_demo_express');
    expect(operators.single.operatorName, 'Demo Express');
    expect(operators.single.sharedViewCount, 2);
  });

  test('upsertOperatorCatalogImportRunIssueSavedView posts mutation', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-issue-saved-view-upsert-1',
      );
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        <String, Object?>{
          'view_id': 'catalogimportrunissuesavedview_errors',
          'name': 'Errors only',
          'visibility_scope': 'shared_ops',
          'operator_ids': <String>['op_demo_express'],
          'severity': 'error',
          'stage': 'all',
          'is_default': false,
        },
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'catalog_import_run_issue_saved_view_upsert',
          'idempotency': <String, Object?>{
            'key': 'idem-coach-catalog-issue-saved-view-upsert-1',
            'scope':
                'coach_operator_catalog_import_run_issue_saved_view_upsert',
            'request_fingerprint': 'fp_catalog_issue_saved_view_upsert_1',
            'replayed': false,
            'derived_keys': <String, Object?>{},
          },
          'saved_view': <String, Object?>{
            'view_id': 'catalogimportrunissuesavedview_errors',
            'account_id': 'acct_ops_shared',
            'name': 'Errors only',
            'visibility_scope': 'shared_ops',
            'operator_ids': <String>['op_demo_express'],
            'severity': 'error',
            'stage': 'all',
            'is_default': false,
            'can_manage': true,
            'created_at': '2026-04-16T08:00:00Z',
            'updated_at': '2026-04-16T08:06:30Z',
          },
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'catalogimportrunissuesavedview_errors',
              'account_id': 'acct_ops_shared',
              'name': 'Errors only',
              'visibility_scope': 'shared_ops',
              'operator_ids': <String>['op_demo_express'],
              'severity': 'error',
              'stage': 'all',
              'is_default': false,
              'can_manage': true,
              'created_at': '2026-04-16T08:00:00Z',
              'updated_at': '2026-04-16T08:06:30Z',
            },
          ],
          'next_action': 'catalog_import_run_issue_filters_ready',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.upsertOperatorCatalogImportRunIssueSavedView(
      const CoachCatalogImportRunIssueSavedView(
        viewId: 'catalogimportrunissuesavedview_errors',
        name: 'Errors only',
        visibilityScope: 'shared_ops',
        operatorIds: <String>['op_demo_express'],
        preferences: CoachCatalogImportRunIssueFilterPreferences(
          severity: 'error',
          stage: 'all',
        ),
        createdAtIso: '2026-04-16T08:00:00Z',
        updatedAtIso: '2026-04-16T08:06:30Z',
      ),
      idempotencyKey: 'idem-coach-catalog-issue-saved-view-upsert-1',
    );

    expect(savedViews, hasLength(1));
    expect(
      savedViews.single.viewId,
      'catalogimportrunissuesavedview_errors',
    );
    expect(savedViews.single.accountId, 'acct_ops_shared');
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.operatorIds, const <String>['op_demo_express']);
    expect(savedViews.single.preferences.severity, 'error');
    expect(savedViews.single.preferences.stage, 'all');
    expect(savedViews.single.isDefault, isFalse);
    expect(savedViews.single.canManage, isTrue);
  });

  test('deleteOperatorCatalogImportRunIssueSavedView posts delete mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views/catalogimportrunissuesavedview_errors/delete',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-issue-saved-view-delete-1',
      );
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        const <String, Object?>{},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'catalog_import_run_issue_saved_view_delete',
          'idempotency': <String, Object?>{
            'key': 'idem-coach-catalog-issue-saved-view-delete-1',
            'scope':
                'coach_operator_catalog_import_run_issue_saved_view_delete',
            'request_fingerprint': 'fp_catalog_issue_saved_view_delete_1',
            'replayed': false,
            'derived_keys': <String, Object?>{},
          },
          'deleted_view_id': 'catalogimportrunissuesavedview_errors',
          'saved_views': const <Object?>[],
          'next_action': 'catalog_import_run_issue_filters_ready',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.deleteOperatorCatalogImportRunIssueSavedView(
      'catalogimportrunissuesavedview_errors',
      idempotencyKey: 'idem-coach-catalog-issue-saved-view-delete-1',
    );

    expect(savedViews, isEmpty);
  });

  test('toggleOperatorCatalogImportRunIssueSavedViewFavorite posts mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views/catalogimportrunissuesavedview_errors/favorite',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-issue-saved-view-favorite-1',
      );
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        <String, Object?>{'favorite': true},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'catalogimportrunissuesavedview_errors',
              'account_id': 'acct_ops_shared',
              'name': 'Errors only',
              'visibility_scope': 'shared_ops',
              'operator_ids': <String>['op_demo_express'],
              'severity': 'error',
              'stage': 'all',
              'is_favorite': true,
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-16T08:00:00Z',
              'updated_at': '2026-04-16T08:05:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews =
        await api.toggleOperatorCatalogImportRunIssueSavedViewFavorite(
      'catalogimportrunissuesavedview_errors',
      favorite: true,
      idempotencyKey: 'idem-coach-catalog-issue-saved-view-favorite-1',
    );

    expect(savedViews, hasLength(1));
    expect(savedViews.single.isFavorite, isTrue);
  });

  test('markOperatorCatalogImportRunIssueSavedViewUsed posts mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_run_issue_saved_views/catalogimportrunissuesavedview_errors/use',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-issue-saved-view-use-1',
      );
      expect(
        jsonDecode(request.body),
        <String, Object?>{'used_at': '2026-04-16T10:05:00Z'},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'view_id': 'catalogimportrunissuesavedview_errors',
          'used_at': '2026-04-16T10:05:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final usedAtIso = await api.markOperatorCatalogImportRunIssueSavedViewUsed(
      'catalogimportrunissuesavedview_errors',
      usedAtIso: '2026-04-16T10:05:00Z',
      idempotencyKey: 'idem-coach-catalog-issue-saved-view-use-1',
    );

    expect(usedAtIso, '2026-04-16T10:05:00Z');
  });

  test('operatorCatalogImportRun parses single import run detail', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_runs/catalogimportrun_demo_failed',
      );
      expect(request.url.queryParameters['limit'], '8');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-10T08:00:00Z',
          'issues_summary': <String, Object?>{
            'total_issues': 3,
            'filtered_issues': 3,
            'error_issues': 2,
            'warning_issues': 1,
          },
          'issues_filters': <String, Object?>{
            'severity': null,
            'stage': null,
            'available_severities': <String>['error', 'warning'],
            'available_stages': <String>[
              'hydrate_trip',
              'load_feed',
              'parse_stop_times',
            ],
          },
          'issues_next_cursor': 'catalogimportissue_demo_failed_2',
          'import_run': <String, Object?>{
            'import_run_id': 'catalogimportrun_demo_failed',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'trigger_kind': 'startup',
            'feed_locator': '/srv/feeds/operator_a',
            'replayed_from_import_run_id': 'catalogimportrun_demo_failed_old_2',
            'source_artifact_id': 'catalogsourceartifact_demo_failed',
            'source_artifact': <String, Object?>{
              'artifact_id': 'catalogsourceartifact_demo_failed',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'source_label': 'operator_a_feed.zip',
              'file_name': 'operator_a_feed.zip',
              'file_checksum_sha256': '${'a' * 64}',
              'content_length_bytes': 512,
              'extracted_file_count': 7,
              'feed_locator': '/srv/feeds/operator_a',
              'created_by_account_id': 'acct_ops_demo',
              'created_at': '2026-04-09T09:57:00Z',
            },
            'status': 'failed',
            'started_at': '2026-04-09T09:58:00Z',
            'finished_at': '2026-04-09T09:58:10Z',
            'counts': <String, Object?>{
              'operators': 0,
              'cities': 0,
              'stop_clusters': 0,
              'stops': 0,
              'lines': 0,
              'service_calendars': 0,
              'trips': 0,
              'fare_products': 0,
              'total_records': 0,
              'ready': false,
            },
            'error_message': 'required GTFS file missing: stops.txt',
            'issue_count': 2,
            'issues': <Object?>[
              <String, Object?>{
                'issue_id': 'catalogimportissue_demo_failed_1',
                'severity': 'error',
                'stage': 'load_feed',
                'code': 'required_file_missing',
                'message': 'required GTFS file missing: stops.txt',
                'file_name': 'stops.txt',
              },
              <String, Object?>{
                'issue_id': 'catalogimportissue_demo_failed_2',
                'severity': 'error',
                'stage': 'parse_stop_times',
                'code': 'invalid_time_value',
                'message': 'stop_times.txt contains invalid departure_time',
                'file_name': 'stop_times.txt',
                'row_reference': 'row:42',
              },
            ],
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogImportRun(
      'catalogimportrun_demo_failed',
    );

    expect(response.importRun.importRunId, 'catalogimportrun_demo_failed');
    expect(
      response.importRun.replayedFromImportRunId,
      'catalogimportrun_demo_failed_old_2',
    );
    expect(
      response.importRun.sourceArtifactId,
      'catalogsourceartifact_demo_failed',
    );
    expect(response.issuesSummary.totalIssues, 3);
    expect(response.issuesSummary.filteredIssues, 3);
    expect(response.issuesSummary.errorIssues, 2);
    expect(response.issuesSummary.warningIssues, 1);
    expect(response.issuesFilters.severity, isNull);
    expect(response.issuesFilters.stage, isNull);
    expect(response.issuesFilters.availableSeverities, ['error', 'warning']);
    expect(
      response.issuesFilters.availableStages,
      ['hydrate_trip', 'load_feed', 'parse_stop_times'],
    );
    expect(response.issuesNextCursor, 'catalogimportissue_demo_failed_2');
    expect(response.importRun.issues, hasLength(2));
    expect(response.importRun.issues.last.rowReference, 'row:42');
  });

  test('operatorCatalogImportRun forwards issue severity and stage filters',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_runs/catalogimportrun_demo_failed',
      );
      expect(request.url.queryParameters['limit'], '8');
      expect(request.url.queryParameters['severity'], 'warning');
      expect(request.url.queryParameters['stage'], 'hydrate_trip');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-10T08:00:00Z',
          'issues_summary': <String, Object?>{
            'total_issues': 3,
            'filtered_issues': 1,
            'error_issues': 0,
            'warning_issues': 1,
          },
          'issues_filters': <String, Object?>{
            'severity': 'warning',
            'stage': 'hydrate_trip',
            'available_severities': <String>['error', 'warning'],
            'available_stages': <String>[
              'hydrate_trip',
              'load_feed',
              'parse_stop_times',
            ],
          },
          'import_run': <String, Object?>{
            'import_run_id': 'catalogimportrun_demo_failed',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'trigger_kind': 'startup',
            'status': 'failed',
            'started_at': '2026-04-09T09:58:00Z',
            'counts': <String, Object?>{
              'operators': 0,
              'cities': 0,
              'stop_clusters': 0,
              'stops': 0,
              'lines': 0,
              'service_calendars': 0,
              'trips': 0,
              'fare_products': 0,
              'total_records': 0,
              'ready': false,
            },
            'issue_count': 1,
            'issues': <Object?>[
              <String, Object?>{
                'issue_id': 'catalogimportissue_demo_failed_3',
                'severity': 'warning',
                'stage': 'hydrate_trip',
                'code': 'partial_trip_skip',
                'message': 'trip skipped because terminal stop was missing',
                'file_name': 'trips.txt',
                'row_reference': 'trip:42',
              },
            ],
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogImportRun(
      'catalogimportrun_demo_failed',
      issueSeverity: 'warning',
      issueStage: 'hydrate_trip',
    );

    expect(response.issuesSummary.filteredIssues, 1);
    expect(response.issuesFilters.severity, 'warning');
    expect(response.issuesFilters.stage, 'hydrate_trip');
    expect(response.importRun.issues, hasLength(1));
    expect(response.importRun.issues.single.stage, 'hydrate_trip');
  });

  test('operatorCatalogImportRuns forwards run and issue filters', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/operator/catalog_import_runs');
      expect(request.url.queryParameters['limit'], '8');
      expect(request.url.queryParameters['status'], 'failed');
      expect(request.url.queryParameters['replay_scope'], 'attention');
      expect(request.url.queryParameters['severity'], 'error');
      expect(request.url.queryParameters['stage'], 'load_feed');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-10T10:00:00Z',
          'summary': <String, Object?>{
            'total_runs': 1,
            'succeeded_runs': 0,
            'failed_runs': 1,
            'running_runs': 0,
            'imported_records_total': 0,
            'latest_succeeded_at': null,
          },
          'import_runs': <Object?>[
            <String, Object?>{
              'import_run_id': 'catalogimportrun_demo_failed',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'trigger_kind': 'manual',
              'status': 'failed',
              'started_at': '2026-04-10T09:58:00Z',
              'counts': <String, Object?>{
                'operators': 0,
                'cities': 0,
                'stop_clusters': 0,
                'stops': 0,
                'lines': 0,
                'service_calendars': 0,
                'trips': 0,
                'fare_products': 0,
                'total_records': 0,
                'ready': false,
              },
              'issues': <Object?>[],
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogImportRuns(
      status: 'failed',
      replayScope: 'attention',
      issueSeverity: 'error',
      issueStage: 'load_feed',
    );

    expect(response.summary.totalRuns, 1);
    expect(response.importRuns.single.isFailed, isTrue);
  });

  test(
      'operatorCatalogImportRunLineage parses replay lineage for an import run',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_runs/catalogimportrun_demo_failed/replays',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:18:00Z',
          'import_run': <String, Object?>{
            'import_run_id': 'catalogimportrun_demo_failed',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'trigger_kind': 'startup',
            'feed_locator': '/srv/feeds/operator_a_failed',
            'status': 'failed',
            'started_at': '2026-04-15T10:14:00Z',
            'finished_at': '2026-04-15T10:14:10Z',
            'counts': <String, Object?>{
              'operators': 0,
              'cities': 0,
              'stop_clusters': 0,
              'stops': 0,
              'lines': 0,
              'service_calendars': 0,
              'trips': 0,
              'fare_products': 0,
              'total_records': 0,
              'ready': false,
            },
            'issue_count': 0,
            'issues': <Object?>[],
          },
          'replay_runs_summary': <String, Object?>{
            'total_runs': 3,
            'failed_runs': 1,
            'succeeded_runs': 1,
            'running_runs': 1,
            'latest_started_at': '2026-04-15T10:16:00Z',
          },
          'replay_runs_next_cursor':
              '2026-04-14T10:16:00Z|catalogimportrun_demo_failed_replay_1',
          'replay_runs': <Object?>[
            <String, Object?>{
              'import_run_id': 'catalogimportrun_demo_failed_replay_2',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'trigger_kind': 'manual',
              'feed_locator': '/srv/feeds/operator_a_replay_2',
              'replayed_from_import_run_id': 'catalogimportrun_demo_failed',
              'status': 'succeeded',
              'started_at': '2026-04-15T10:16:00Z',
              'finished_at': '2026-04-15T10:16:20Z',
              'counts': <String, Object?>{
                'operators': 1,
                'cities': 2,
                'stop_clusters': 2,
                'stops': 4,
                'lines': 1,
                'service_calendars': 1,
                'trips': 2,
                'fare_products': 2,
                'total_records': 15,
                'ready': true,
              },
              'issue_count': 0,
              'issues': <Object?>[],
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogImportRunLineage(
      'catalogimportrun_demo_failed',
    );

    expect(response.importRun.importRunId, 'catalogimportrun_demo_failed');
    expect(response.replayRunsSummary.totalRuns, 3);
    expect(
      response.replayRunsNextCursor,
      '2026-04-14T10:16:00Z|catalogimportrun_demo_failed_replay_1',
    );
    expect(response.replayRuns, hasLength(1));
    expect(
      response.replayRuns.single.replayedFromImportRunId,
      'catalogimportrun_demo_failed',
    );
  });

  test(
      'operatorCatalogSourceArtifact parses single source artifact detail with referencing runs',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_source_artifacts/catalogsourceartifact_demo_failed',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:18:00Z',
          'source_artifact': <String, Object?>{
            'artifact_id': 'catalogsourceartifact_demo_failed',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'source_label': 'broken_feed.zip',
            'file_name': 'broken_feed.zip',
            'file_checksum_sha256': '${'c' * 64}',
            'content_length_bytes': 2048,
            'extracted_file_count': 6,
            'feed_locator': '/srv/feeds/operator_a_failed',
            'created_by_account_id': 'acct_ops_demo',
            'created_at': '2026-04-15T10:12:00Z',
          },
          'referencing_import_runs_summary': <String, Object?>{
            'total_runs': 3,
            'failed_runs': 1,
            'succeeded_runs': 2,
            'running_runs': 0,
            'latest_started_at': '2026-04-15T10:14:00Z',
          },
          'referencing_import_runs_next_cursor':
              '2026-04-14T10:14:00Z|catalogimportrun_demo_failed_old',
          'referencing_import_runs': <Object?>[
            <String, Object?>{
              'import_run_id': 'catalogimportrun_demo_failed',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'trigger_kind': 'startup',
              'feed_locator': '/srv/feeds/operator_a_failed',
              'source_artifact_id': 'catalogsourceartifact_demo_failed',
              'status': 'failed',
              'started_at': '2026-04-15T10:14:00Z',
              'finished_at': '2026-04-15T10:14:10Z',
              'counts': <String, Object?>{
                'operators': 1,
                'cities': 1,
                'stop_clusters': 1,
                'stops': 2,
                'lines': 1,
                'service_calendars': 1,
                'trips': 1,
                'fare_products': 1,
                'total_records': 9,
                'ready': true,
              },
              'issue_count': 0,
              'issues': <Object?>[],
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogSourceArtifact(
      'catalogsourceartifact_demo_failed',
    );

    expect(response.sourceArtifact.artifactId,
        'catalogsourceartifact_demo_failed');
    expect(response.referencingImportRunsSummary.totalRuns, 3);
    expect(
      response.referencingImportRunsNextCursor,
      '2026-04-14T10:14:00Z|catalogimportrun_demo_failed_old',
    );
    expect(response.referencingImportRuns, hasLength(1));
    expect(
      response.referencingImportRuns.single.importRunId,
      'catalogimportrun_demo_failed',
    );
  });

  test('triggerOperatorCatalogImportRun posts manual import command', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/coach/operator/catalog_import_runs');
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-import-manual-1',
      );
      expect(
        jsonDecode(
            request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes)),
        <String, Object?>{},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'catalog_import_run_trigger',
          'idempotency': <String, Object?>{
            'key': 'idem-coach-catalog-import-manual-1',
            'scope': 'coach_operator_catalog_import_run_trigger',
            'request_fingerprint': 'fp_catalog_import_manual_1',
            'replayed': false,
            'derived_keys': <String, Object?>{},
          },
          'import_run': <String, Object?>{
            'import_run_id': 'catalogimportrun_demo_manual',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'trigger_kind': 'manual',
            'feed_locator': '/srv/feeds/operator_a',
            'source_artifact_id': 'catalogsourceartifact_demo_uploaded',
            'status': 'succeeded',
            'started_at': '2026-04-09T10:05:00Z',
            'finished_at': '2026-04-09T10:05:20Z',
            'counts': <String, Object?>{
              'operators': 1,
              'cities': 2,
              'stop_clusters': 2,
              'stops': 4,
              'lines': 1,
              'service_calendars': 1,
              'trips': 2,
              'fare_products': 2,
              'total_records': 15,
              'ready': true,
            },
          },
          'next_action': 'catalog_search_ready',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.triggerOperatorCatalogImportRun(
      idempotencyKey: 'idem-coach-catalog-import-manual-1',
    );

    expect(response.command, 'catalog_import_run_trigger');
    expect(response.importRun.triggerKind, 'manual');
    expect(
      response.importRun.sourceArtifactId,
      'catalogsourceartifact_demo_uploaded',
    );
    expect(response.importRun.counts.totalRecords, 15);
    expect(response.nextAction, 'catalog_search_ready');
  });

  test('triggerOperatorCatalogImportRun posts replay import command', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/coach/operator/catalog_import_runs');
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        <String, Object?>{
          'replay_import_run_id': 'catalogimportrun_demo_failed',
        },
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'catalog_import_run_trigger',
          'idempotency': <String, Object?>{
            'key': 'idem-coach-catalog-import-replay-1',
            'scope': 'coach_operator_catalog_import_run_trigger',
            'request_fingerprint': 'fp_catalog_import_replay_1',
            'replayed': false,
            'derived_keys': <String, Object?>{},
          },
          'import_run': <String, Object?>{
            'import_run_id': 'catalogimportrun_demo_replay_1',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'trigger_kind': 'manual',
            'feed_locator': '/srv/feeds/operator_a',
            'replayed_from_import_run_id': 'catalogimportrun_demo_failed',
            'source_artifact_id': 'catalogsourceartifact_demo_failed',
            'status': 'succeeded',
            'started_at': '2026-04-09T10:15:00Z',
            'finished_at': '2026-04-09T10:15:20Z',
            'counts': <String, Object?>{
              'operators': 1,
              'cities': 2,
              'stop_clusters': 2,
              'stops': 4,
              'lines': 1,
              'service_calendars': 1,
              'trips': 2,
              'fare_products': 2,
              'total_records': 15,
              'ready': true,
            },
            'issues': <Object?>[],
          },
          'next_action': 'catalog_search_ready',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.triggerOperatorCatalogImportRun(
      replayImportRunId: 'catalogimportrun_demo_failed',
      idempotencyKey: 'idem-coach-catalog-import-replay-1',
    );

    expect(response.command, 'catalog_import_run_trigger');
    expect(response.importRun.importRunId, 'catalogimportrun_demo_replay_1');
    expect(
      response.importRun.replayedFromImportRunId,
      'catalogimportrun_demo_failed',
    );
    expect(
      response.importRun.sourceArtifactId,
      'catalogsourceartifact_demo_failed',
    );
  });

  test('operatorCatalogImportConfig parses GTFS import configuration',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/operator/catalog_import_config');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:10:00Z',
          'source_kind': 'gtfs',
          'configured': true,
          'feed_locator': '/srv/feeds/operator_a',
          'status': 'ready',
          'detail': 'GTFS feed directory is configured.',
          'config_origin': 'database',
          'source_artifact': <String, Object?>{
            'artifact_id': 'catalogsourceartifact_demo_current',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'source_label': 'operator_a_feed.zip',
            'file_name': 'operator_a_feed.zip',
            'file_checksum_sha256': '${'b' * 64}',
            'content_length_bytes': 1024,
            'extracted_file_count': 7,
            'feed_locator': '/srv/feeds/operator_a',
            'created_by_account_id': 'acct_ops_demo',
            'created_at': '2026-04-15T10:08:00Z',
          },
          'updated_at': '2026-04-15T10:09:30Z',
          'updated_by_account_id': 'acct_ops_demo',
          'latest_import_run': <String, Object?>{
            'import_run_id': 'catalogimportrun_demo_manual',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'trigger_kind': 'manual',
            'feed_locator': '/srv/feeds/operator_a',
            'status': 'succeeded',
            'started_at': '2026-04-15T10:09:00Z',
            'finished_at': '2026-04-15T10:09:20Z',
            'counts': <String, Object?>{
              'operators': 1,
              'cities': 2,
              'stop_clusters': 2,
              'stops': 4,
              'lines': 1,
              'service_calendars': 1,
              'trips': 2,
              'fare_products': 2,
              'total_records': 15,
              'ready': true,
            },
            'error_message': null,
            'issue_count': 0,
            'issues': const <Object?>[],
          },
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogImportConfig();

    expect(response.isReady, isTrue);
    expect(response.feedLocator, '/srv/feeds/operator_a');
    expect(response.configOrigin, 'database');
    expect(response.sourceArtifact?.artifactId,
        'catalogsourceartifact_demo_current');
    expect(response.sourceArtifact?.sourceLabel, 'operator_a_feed.zip');
    expect(response.updatedByAccountId, 'acct_ops_demo');
    expect(
        response.latestImportRun?.importRunId, 'catalogimportrun_demo_manual');
  });

  test('operatorCatalogImportSources parses available GTFS sources', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/operator/catalog_import_sources');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:11:00Z',
          'sources': <Object?>[
            <String, Object?>{
              'source_kind': 'gtfs',
              'feed_locator': '/srv/feeds/operator_a',
              'source_origin': 'database_saved',
              'source_label': 'Saved feed locator',
              'status': 'ready',
              'detail': 'GTFS feed directory is configured.',
              'selected': true,
            },
            <String, Object?>{
              'source_kind': 'gtfs',
              'feed_locator': '/srv/feeds/operator_env_default',
              'source_origin': 'environment_default',
              'source_label': 'Environment default',
              'status': 'ready',
              'detail': 'GTFS feed directory is configured.',
              'selected': false,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogImportSources();

    expect(response.sources, hasLength(2));
    expect(response.sources.first.selected, isTrue);
    expect(response.sources.last.sourceOrigin, 'environment_default');
    expect(
        response.sources.last.feedLocator, '/srv/feeds/operator_env_default');
  });

  test('operatorCatalogSourceArtifacts parses uploaded GTFS artifacts',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/operator/catalog_source_artifacts');
      expect(request.url.queryParameters['limit'], '8');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:12:00Z',
          'summary': <String, Object?>{
            'total_artifacts': 2,
            'uploaded_bytes_total': 1536,
            'latest_created_at': '2026-04-15T10:11:00Z',
          },
          'artifacts': <Object?>[
            <String, Object?>{
              'artifact_id': 'catalogsourceartifact_demo_current',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'source_label': 'operator_a_feed.zip',
              'file_name': 'operator_a_feed.zip',
              'file_checksum_sha256': '${'d' * 64}',
              'content_length_bytes': 1024,
              'extracted_file_count': 7,
              'feed_locator': '/srv/feeds/operator_a',
              'created_by_account_id': 'acct_ops_demo',
              'created_at': '2026-04-15T10:11:00Z',
            },
            <String, Object?>{
              'artifact_id': 'catalogsourceartifact_demo_previous',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'source_label': 'operator_a_feed_v1.zip',
              'file_name': 'operator_a_feed_v1.zip',
              'file_checksum_sha256': '${'e' * 64}',
              'content_length_bytes': 512,
              'extracted_file_count': 7,
              'feed_locator': '/srv/feeds/operator_a_v1',
              'created_by_account_id': 'acct_ops_demo',
              'created_at': '2026-04-14T10:11:00Z',
            },
          ],
          'next_cursor':
              '2026-04-14T10:11:00Z|catalogsourceartifact_demo_previous',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorCatalogSourceArtifacts();

    expect(response.summary.totalArtifacts, 2);
    expect(response.summary.uploadedBytesTotal, 1536);
    expect(response.artifacts.first.sourceLabel, 'operator_a_feed.zip');
    expect(response.artifacts.last.feedLocator, '/srv/feeds/operator_a_v1');
    expect(
      response.nextCursor,
      '2026-04-14T10:11:00Z|catalogsourceartifact_demo_previous',
    );
  });

  test('uploadOperatorCatalogImportSourceFile sends multipart GTFS archive',
      () async {
    late http.BaseRequest capturedRequest;
    final client = _StreamingClient((request) async {
      capturedRequest = request;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/catalog_import_sources/upload',
      );
      expect(
        request.headers['Idempotency-Key'],
        'coach-ops-catalog-import-source-upload-test-1',
      );
      expect(
        request.headers['cookie']?.toLowerCase(),
        '__host-sa_session=0123456789abcdef0123456789abcdef',
      );
      expect(request, isA<http.MultipartRequest>());
      final multipart = request as http.MultipartRequest;
      expect(multipart.fields['source_kind'], 'gtfs');
      expect(multipart.files, hasLength(1));
      expect(multipart.files.single.field, 'file');
      expect(multipart.files.single.filename, 'operator_b_feed.zip');
      expect(multipart.files.single.length, 5);
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'command': 'catalog_import_source_upload',
              'idempotency': <String, Object?>{
                'key': 'coach-ops-catalog-import-source-upload-test-1',
                'scope': 'coach_operator_catalog_import_source_upload',
                'request_fingerprint':
                    'fp_coach_catalog_import_source_upload_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'uploaded_source': <String, Object?>{
                'source_artifact_id':
                    'catalogsourceartifact_operator_b_feed_uploaded',
                'source_kind': 'gtfs',
                'source_label': 'operator_b_feed.zip',
                'file_name': 'operator_b_feed.zip',
                'file_checksum_sha256': '${'c' * 64}',
                'content_length_bytes': 5,
                'feed_locator':
                    '/tmp/shamell_coach_gtfs_uploads/operator_b_feed_uploaded',
                'extracted_file_count': 7,
              },
              'config': <String, Object?>{
                'generated_at': '2026-04-15T10:14:00Z',
                'source_kind': 'gtfs',
                'configured': true,
                'feed_locator':
                    '/tmp/shamell_coach_gtfs_uploads/operator_b_feed_uploaded',
                'status': 'ready',
                'detail': 'GTFS feed directory is configured.',
                'config_origin': 'database',
                'source_artifact': <String, Object?>{
                  'artifact_id':
                      'catalogsourceartifact_operator_b_feed_uploaded',
                  'feed_kind': 'static_catalog',
                  'source_kind': 'gtfs',
                  'source_label': 'operator_b_feed.zip',
                  'file_name': 'operator_b_feed.zip',
                  'file_checksum_sha256': '${'c' * 64}',
                  'content_length_bytes': 5,
                  'extracted_file_count': 7,
                  'feed_locator':
                      '/tmp/shamell_coach_gtfs_uploads/operator_b_feed_uploaded',
                  'created_by_account_id': 'acct_ops_demo',
                  'created_at': '2026-04-15T10:14:00Z',
                },
                'updated_at': '2026-04-15T10:14:00Z',
                'updated_by_account_id': 'acct_ops_demo',
                'latest_import_run': null,
              },
              'next_action': 'catalog_import_ready',
            }),
          ),
        ),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
        request: request,
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final result = await api.uploadOperatorCatalogImportSourceFile(
      fileName: 'operator_b_feed.zip',
      fileBytes: Uint8List.fromList(const <int>[1, 2, 3, 4, 5]),
      idempotencyKey: 'coach-ops-catalog-import-source-upload-test-1',
    );

    expect(capturedRequest, isA<http.MultipartRequest>());
    expect(result.command, 'catalog_import_source_upload');
    expect(
      result.uploadedSource.sourceArtifactId,
      'catalogsourceartifact_operator_b_feed_uploaded',
    );
    expect(result.uploadedSource.sourceKind, 'gtfs');
    expect(result.uploadedSource.sourceLabel, 'operator_b_feed.zip');
    expect(result.uploadedSource.fileName, 'operator_b_feed.zip');
    expect(result.uploadedSource.contentLengthBytes, 5);
    expect(result.uploadedSource.extractedFileCount, 7);
    expect(
      result.config.feedLocator,
      '/tmp/shamell_coach_gtfs_uploads/operator_b_feed_uploaded',
    );
    expect(result.config.isReady, isTrue);
    expect(
      result.config.sourceArtifact?.artifactId,
      'catalogsourceartifact_operator_b_feed_uploaded',
    );
    expect(result.nextAction, 'catalog_import_ready');
  });

  test('updateOperatorCatalogImportConfig posts config mutation', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/coach/operator/catalog_import_config');
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-import-config-1',
      );
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        <String, Object?>{
          'feed_locator': '/srv/feeds/operator_b',
        },
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'catalog_import_config_update',
          'idempotency': <String, Object?>{
            'key': 'idem-coach-catalog-import-config-1',
            'scope': 'coach_operator_catalog_import_config_update',
            'request_fingerprint': 'fp_catalog_import_config_1',
            'replayed': false,
            'derived_keys': <String, Object?>{},
          },
          'config': <String, Object?>{
            'generated_at': '2026-04-15T10:12:00Z',
            'source_kind': 'gtfs',
            'configured': true,
            'feed_locator': '/srv/feeds/operator_b',
            'status': 'ready',
            'detail': 'GTFS feed directory is configured.',
            'config_origin': 'database',
            'updated_at': '2026-04-15T10:12:00Z',
            'updated_by_account_id': 'acct_ops_demo',
            'latest_import_run': null,
          },
          'next_action': 'catalog_import_ready',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.updateOperatorCatalogImportConfig(
      feedLocator: '/srv/feeds/operator_b',
      idempotencyKey: 'idem-coach-catalog-import-config-1',
    );

    expect(response.command, 'catalog_import_config_update');
    expect(response.config.feedLocator, '/srv/feeds/operator_b');
    expect(response.config.configOrigin, 'database');
    expect(response.nextAction, 'catalog_import_ready');
  });

  test('triggerOperatorCatalogImportRun posts selected artifact override',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/coach/operator/catalog_import_runs');
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-catalog-import-artifact-1',
      );
      expect(
        jsonDecode(
          request.bodyBytes.isEmpty ? '{}' : utf8.decode(request.bodyBytes),
        ),
        <String, Object?>{
          'source_artifact_id': 'catalogsourceartifact_demo_current',
        },
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'catalog_import_run_trigger',
          'idempotency': <String, Object?>{
            'key': 'idem-coach-catalog-import-artifact-1',
            'scope': 'coach_operator_catalog_import_run_trigger',
            'request_fingerprint': 'fp_catalog_import_manual_artifact_1',
            'replayed': false,
            'derived_keys': <String, Object?>{},
          },
          'import_run': <String, Object?>{
            'import_run_id': 'catalogimportrun_demo_manual_artifact',
            'feed_kind': 'static_catalog',
            'source_kind': 'gtfs',
            'trigger_kind': 'manual',
            'feed_locator': '/srv/feeds/operator_a',
            'source_artifact_id': 'catalogsourceartifact_demo_current',
            'source_artifact': <String, Object?>{
              'artifact_id': 'catalogsourceartifact_demo_current',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'source_label': 'operator_a_feed.zip',
              'file_name': 'operator_a_feed.zip',
              'file_checksum_sha256': '${'f' * 64}',
              'content_length_bytes': 1024,
              'extracted_file_count': 7,
              'feed_locator': '/srv/feeds/operator_a',
              'created_by_account_id': 'acct_ops_demo',
              'created_at': '2026-04-15T10:11:00Z',
            },
            'status': 'succeeded',
            'started_at': '2026-04-15T10:20:00Z',
            'finished_at': '2026-04-15T10:20:15Z',
            'counts': <String, Object?>{
              'operators': 1,
              'cities': 2,
              'stop_clusters': 2,
              'stops': 4,
              'lines': 1,
              'service_calendars': 1,
              'trips': 2,
              'fare_products': 2,
              'total_records': 15,
              'ready': true,
            },
          },
          'next_action': 'catalog_search_ready',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.triggerOperatorCatalogImportRun(
      sourceArtifactId: 'catalogsourceartifact_demo_current',
      idempotencyKey: 'idem-coach-catalog-import-artifact-1',
    );

    expect(
      response.importRun.sourceArtifactId,
      'catalogsourceartifact_demo_current',
    );
    expect(response.importRun.sourceArtifact?.artifactId,
        'catalogsourceartifact_demo_current');
    expect(response.importRun.feedLocator, '/srv/feeds/operator_a');
    expect(response.nextAction, 'catalog_search_ready');
  });

  test('operatorFeedHealth parses operator feed health summary', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/operator/feed_health');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-09T10:06:00Z',
          'summary': <String, Object?>{
            'operators_total': 2,
            'healthy_operators': 1,
            'degraded_feeds': 1,
            'stale_feeds': 1,
          },
          'feeds': <Object?>[
            <String, Object?>{
              'operator_id': 'op_demo_b',
              'operator_name': 'Demo B',
              'operator_integration_mode': 'hybrid',
              'feed_kind': 'gtfs_rt_trip_updates',
              'source_kind': 'gtfs_rt',
              'sync_status': 'error',
              'freshness_status': 'stale',
              'last_attempted_at': '2026-04-09T10:05:00Z',
              'records_ingested': 0,
              'error_message': 'upstream timeout',
            },
            <String, Object?>{
              'operator_id': 'op_demo_a',
              'operator_name': 'Demo A',
              'operator_integration_mode': 'feed',
              'feed_kind': 'static_catalog',
              'source_kind': 'gtfs',
              'sync_status': 'ok',
              'freshness_status': 'fresh',
              'last_attempted_at': '2026-04-09T10:04:00Z',
              'last_succeeded_at': '2026-04-09T10:04:00Z',
              'freshness_expires_at': '2026-04-10T10:04:00Z',
              'records_ingested': 12,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.operatorFeedHealth();

    expect(response.summary.operatorsTotal, 2);
    expect(response.summary.healthyOperators, 1);
    expect(response.summary.degradedFeeds, 1);
    expect(response.feeds.first.operatorName, 'Demo B');
    expect(response.feeds.last.isHealthy, isTrue);
  });

  test('getOffer uses path and passengers query parameter', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/offers/offer_demo_express_direct');
      expect(request.url.queryParameters['passengers'], '3');
      return http.Response(
        jsonEncode(<String, Object?>{
          'offer_id': 'offer_demo_express_direct',
          'operator_id': 'op_demo_express',
          'itinerary_id': 'iti_demo_direct',
          'currency': 'SYP',
          'total_minor_units': 13770,
          'seats_requested': 3,
          'hold_supported': true,
          'changeable': true,
          'refundable': true,
          'expires_at': '2026-04-07T12:05:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final offer = await api.getOffer(
      offerId: 'offer_demo_express_direct',
      passengers: 3,
    );

    expect(offer.seatsRequested, 3);
    expect(offer.totalMinorUnits, 13770);
  });

  test('getHold, getBooking, and getTicket parse core lifecycle records',
      () async {
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/me/coach/holds/hold_demo':
          return http.Response(
            jsonEncode(<String, Object?>{
              'hold_id': 'hold_demo',
              'offer_id': 'offer_demo_express_direct',
              'operator_reference': 'operator-hold_demo',
              'expires_at': '2026-04-07T12:04:30Z',
              'status': 'active',
              'seat_assignments': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'pax_1',
                  'seat_number': '4A',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case '/me/coach/bookings/booking_demo':
          return http.Response(
            jsonEncode(<String, Object?>{
              'booking_id': 'booking_demo',
              'offer_id': 'offer_demo_express_direct',
              'hold_id': 'hold_demo',
              'operator_booking_reference': 'operator-booking-booking_demo',
              'state': 'ticketed',
              'currency': 'SYP',
              'total_minor_units': 4590,
              'passenger_count': 1,
              'created_at': '2026-04-07T12:06:00Z',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case '/me/coach/tickets/ticket_demo':
          return http.Response(
            jsonEncode(<String, Object?>{
              'ticket_id': 'ticket_demo',
              'booking_id': 'booking_demo',
              'coupon_id': 'coupon-ticket_demo',
              'passenger_id': 'pax_1',
              'segment_ids': <String>['seg_demo_direct_1'],
              'status': 'active',
              'operator_ticket_reference': 'operator-ticket-ticket_demo',
              'qr_payload_ref': 'object://coach/tickets/ticket_demo/qr',
              'artifacts': <Map<String, Object?>>[
                <String, Object?>{
                  'artifact_id': 'ticketartifact_ticket_demo_qr',
                  'ticket_id': 'ticket_demo',
                  'booking_id': 'booking_demo',
                  'artifact_kind': 'qr',
                  'delivery_channel': 'qr',
                  'file_name': 'ticket_demo-qr.svg',
                  'mime_type': 'image/svg+xml',
                  'content_length_bytes': 2048,
                  'download_path':
                      '/downloads/coach/tickets/ticketartifact_ticket_demo_qr.svg',
                },
                <String, Object?>{
                  'artifact_id': 'ticketartifact_ticket_demo_pdf',
                  'ticket_id': 'ticket_demo',
                  'booking_id': 'booking_demo',
                  'artifact_kind': 'pdf',
                  'delivery_channel': 'pdf',
                  'file_name': 'ticket_demo.pdf',
                  'mime_type': 'application/pdf',
                  'content_length_bytes': 32768,
                  'download_path':
                      '/downloads/coach/tickets/ticketartifact_ticket_demo_pdf.pdf',
                },
              ],
              'issued_at': '2026-04-07T12:06:30Z',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final hold = await api.getHold('hold_demo');
    final booking = await api.getBooking('booking_demo');
    final ticket = await api.getTicket('ticket_demo');

    expect(hold.status, CoachHoldStatus.active);
    expect(booking.state, CoachBookingLifecycleState.ticketed);
    expect(ticket.status, CoachTicketStatus.active);
    expect(ticket.artifacts.length, 2);
    expect(ticket.artifactByKind('pdf')!.mimeType, 'application/pdf');
  });

  test('listBookings parses saved coach trips with passengers and tickets',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/coach/bookings');
      return http.Response(
        jsonEncode(<String, Object?>{
          'summary': <String, Object?>{
            'upcoming_count': 2,
            'ticketed_count': 1,
            'needs_action_count': 1,
          },
          'bookings': <Map<String, Object?>>[
            <String, Object?>{
              'journey': <String, Object?>{
                'journey_id': 'journey_demo_express_direct',
                'operator_name': 'Demo Express',
                'from': 'Damascus',
                'to': 'Aleppo',
                'departure_at': '2026-04-08T08:00:00Z',
                'arrival_at': '2026-04-08T12:30:00Z',
                'status_label': 'Boarding pass ready',
              },
              'offer': <String, Object?>{
                'offer_id': 'offer_demo_express_direct',
                'operator_id': 'op_demo_express',
                'itinerary_id': 'iti_demo_direct',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'seats_requested': 2,
                'hold_supported': true,
                'changeable': true,
                'refundable': true,
                'expires_at': '2026-04-07T12:05:00Z',
              },
              'hold': <String, Object?>{
                'hold_id': 'hold_demo_express_direct',
                'offer_id': 'offer_demo_express_direct',
                'operator_reference': 'operator-hold_demo_express_direct',
                'expires_at': '2026-04-07T12:04:30Z',
                'status': 'converted',
                'seat_assignments': <Map<String, Object?>>[
                  <String, Object?>{
                    'passenger_id': 'adult_1',
                    'seat_number': '4A',
                  },
                  <String, Object?>{
                    'passenger_id': 'adult_2',
                    'seat_number': '4B',
                  },
                ],
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_direct',
                'hold_id': 'hold_demo_express_direct',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
                <String, Object?>{
                  'passenger_id': 'adult_2',
                  'given_name': 'Omar',
                  'family_name': 'Darwish',
                  'rider_category': 'student',
                  'nationality_code': 'DE',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_demo_express_direct_1',
                  'booking_id': 'booking_demo_express_direct',
                  'coupon_id': 'coupon-ticket_demo_express_direct_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_booking_demo_express_direct_1'],
                  'status': 'active',
                  'operator_ticket_reference':
                      'operator-ticket-ticket_demo_express_direct_1',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_demo_express_direct_1/qr',
                  'issued_at': '2026-04-07T12:06:30Z',
                },
              ],
            },
            <String, Object?>{
              'journey': <String, Object?>{
                'journey_id': 'journey_northern_connector_night',
                'operator_name': 'Northern Connector',
                'from': 'Aleppo',
                'to': 'Latakia',
                'departure_at': '2026-04-09T22:15:00Z',
                'arrival_at': '2026-04-10T03:45:00Z',
                'status_label': 'Issue tickets',
              },
              'offer': <String, Object?>{
                'offer_id': 'offer_night_connector',
                'operator_id': 'op_northern_connector',
                'itinerary_id': 'iti_night_connector',
                'currency': 'SYP',
                'total_minor_units': 3990,
                'seats_requested': 1,
                'hold_supported': true,
                'changeable': true,
                'refundable': false,
                'expires_at': '2026-04-07T12:05:00Z',
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_night_connector',
                'offer_id': 'offer_night_connector',
                'hold_id': 'hold_night_connector',
                'operator_booking_reference':
                    'operator-booking-booking_night_connector',
                'state': 'booking_pending',
                'currency': 'SYP',
                'total_minor_units': 3990,
                'passenger_count': 1,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'senior_1',
                  'given_name': 'Maha',
                  'family_name': 'Khalil',
                  'rider_category': 'senior',
                  'nationality_code': 'SY',
                },
              ],
              'tickets': <Map<String, Object?>>[],
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.listBookings();

    expect(response.summary.upcomingCount, 2);
    expect(response.bookings.length, 2);
    expect(response.bookings.first.journey.operatorName, 'Demo Express');
    expect(
        response.bookings.first.hold?.seatAssignments.first.seatNumber, '4A');
    expect(response.bookings.first.passengerManifests.last.displayName,
        'Omar Darwish');
    expect(response.bookings.first.tickets.single.qrPayloadRef,
        'object://coach/tickets/ticket_demo_express_direct_1/qr');
    expect(response.bookings.last.tickets, isEmpty);
  });

  test('refund eligibility and refund request parse customer self-service flow',
      () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /me/coach/bookings/booking_demo_express_direct/refund_eligibility':
          return http.Response(
            jsonEncode(<String, Object?>{
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_direct',
                'hold_id': 'hold_demo_express_direct',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_booking_demo_express_direct_1',
                  'booking_id': 'booking_demo_express_direct',
                  'coupon_id': 'coupon-ticket_booking_demo_express_direct_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_booking_demo_express_direct_1'],
                  'status': 'active',
                  'operator_ticket_reference':
                      'operator-ticket-ticket_booking_demo_express_direct_1',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
                  'issued_at': '2026-04-07T12:06:30Z',
                },
              ],
              'eligibility': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'booking_state': 'ticketed',
                'refundable': true,
                'currency': 'SYP',
                'refund_cutoff_at': '2026-04-08T06:00:00Z',
                'recommended_kind': 'refund_credit',
                'tickets_void_required': true,
                'options': <Map<String, Object?>>[
                  <String, Object?>{
                    'kind': 'refund_credit',
                    'label': 'Travel credit',
                    'currency': 'SYP',
                    'refund_minor_units': 9180,
                    'fee_minor_units': 0,
                    'expires_at': '2027-04-08T00:00:00Z',
                  },
                  <String, Object?>{
                    'kind': 'original_payment',
                    'label': 'Original payment',
                    'currency': 'SYP',
                    'refund_minor_units': 8190,
                    'fee_minor_units': 990,
                  },
                ],
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/bookings/booking_demo_express_direct/refunds':
          expect(
            request.headers.entries.any(
              (entry) =>
                  entry.key.toLowerCase() == 'idempotency-key' &&
                  entry.value == 'coach-refund-test-1',
            ),
            isTrue,
          );
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['refund_kind'], 'refund_credit');
          expect(body['ticket_ids'],
              <String>['ticket_booking_demo_express_direct_1']);
          expect(body['reason'], 'customer changed plans');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'refund_request',
              'idempotency': <String, Object?>{
                'key': 'coach-refund-test-1',
                'scope': 'coach_refund_request',
                'request_fingerprint': 'fp_refund_request_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'refund_authorize': 'coach_refund_authorize.1234',
                  'ledger_posting': 'coach_refund_ledger_posting.1234',
                },
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_direct',
                'hold_id': 'hold_demo_express_direct',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'refund_requested',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'refund_request': <String, Object?>{
                'refund_request_id': 'refundreq_demo_1',
                'booking_id': 'booking_demo_express_direct',
                'status': 'requested',
                'selected_kind': 'refund_credit',
                'currency': 'SYP',
                'requested_minor_units': 9180,
                'fee_minor_units': 0,
                'ticket_ids': <String>['ticket_booking_demo_express_direct_1'],
                'reason': 'customer changed plans',
                'created_at': '2026-04-07T13:00:00Z',
              },
              'compensation': <String, Object?>{
                'state': 'armed',
                'action': 'issue_refund_credit_or_raise_finance_case',
                'support_queue': 'coach_refund_queue',
                'triggered': false,
              },
              'next_action': 'await_refund_review',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final eligibility =
        await api.getRefundEligibility('booking_demo_express_direct');
    final result = await api.requestRefund(
      bookingId: 'booking_demo_express_direct',
      refundKind: CoachRefundKind.refundCredit,
      ticketIds: const <String>['ticket_booking_demo_express_direct_1'],
      reason: 'customer changed plans',
      idempotencyKey: 'coach-refund-test-1',
    );

    expect(eligibility.eligibility.refundable, isTrue);
    expect(
        eligibility.eligibility.recommendedKind, CoachRefundKind.refundCredit);
    expect(
      eligibility.eligibility
          .optionForKind(CoachRefundKind.originalPayment)
          ?.feeMinorUnits,
      990,
    );
    expect(result.booking.state, CoachBookingLifecycleState.refundRequested);
    expect(result.refundRequest.selectedKind, CoachRefundKind.refundCredit);
    expect(result.compensation.supportQueue, 'coach_refund_queue');
    expect(result.nextAction, 'await_refund_review');
  });

  test('change options and rebook request parse customer self-service flow',
      () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /me/coach/bookings/booking_demo_express_direct/change_options':
          return http.Response(
            jsonEncode(<String, Object?>{
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_direct',
                'hold_id': 'hold_demo_express_direct',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_booking_demo_express_direct_1',
                  'booking_id': 'booking_demo_express_direct',
                  'coupon_id': 'coupon-ticket_booking_demo_express_direct_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_booking_demo_express_direct_1'],
                  'status': 'active',
                  'operator_ticket_reference':
                      'operator-ticket-ticket_booking_demo_express_direct_1',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
                  'issued_at': '2026-04-07T12:06:30Z',
                },
              ],
              'eligibility': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'booking_state': 'ticketed',
                'changeable': true,
                'change_cutoff_at': '2026-04-08T06:30:00Z',
                'options': <Map<String, Object?>>[
                  <String, Object?>{
                    'target_offer_id': 'offer_demo_express_midday',
                    'journey_id': 'journey_demo_express_midday',
                    'departure_at': '2026-04-08T12:00:00Z',
                    'arrival_at': '2026-04-08T16:30:00Z',
                    'currency': 'SYP',
                    'fare_difference_minor_units': 800,
                    'change_fee_minor_units': 500,
                    'total_due_minor_units': 1300,
                    'seat_map_available': true,
                    'expires_at': '2026-04-07T14:00:00Z',
                  },
                ],
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/bookings/booking_demo_express_direct/rebook_requests':
          expect(
            request.headers.entries.any(
              (entry) =>
                  entry.key.toLowerCase() == 'idempotency-key' &&
                  entry.value == 'coach-rebook-test-1',
            ),
            isTrue,
          );
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['target_offer_id'], 'offer_demo_express_midday');
          expect(body['preferred_seat_numbers'], <String>['5A', '5B']);
          expect(body['reason'], 'move to midday departure');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'rebook_request',
              'idempotency': <String, Object?>{
                'key': 'coach-rebook-test-1',
                'scope': 'coach_rebook_request',
                'request_fingerprint': 'fp_rebook_request_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'change_authorize': 'coach_change_authorize.1234',
                  'reissue_tickets': 'coach_reissue_tickets.1234',
                },
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_direct',
                'hold_id': 'hold_demo_express_direct',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'change_request': <String, Object?>{
                'change_request_id': 'changereq_demo_1',
                'booking_id': 'booking_demo_express_direct',
                'status': 'requested',
                'target_offer_id': 'offer_demo_express_midday',
                'currency': 'SYP',
                'fare_difference_minor_units': 800,
                'change_fee_minor_units': 500,
                'total_due_minor_units': 1300,
                'reason': 'move to midday departure',
                'created_at': '2026-04-07T13:05:00Z',
              },
              'compensation': <String, Object?>{
                'state': 'armed',
                'action': 'reissue_tickets_or_raise_support_case',
                'support_queue': 'coach_rebook_queue',
                'triggered': false,
              },
              'next_action': 'await_reissue',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final options = await api.getChangeOptions('booking_demo_express_direct');
    final result = await api.requestRebook(
      bookingId: 'booking_demo_express_direct',
      targetOfferId: 'offer_demo_express_midday',
      preferredSeatNumbers: const <String>['5A', '5B'],
      reason: 'move to midday departure',
      idempotencyKey: 'coach-rebook-test-1',
    );

    expect(options.eligibility.changeable, isTrue);
    expect(options.eligibility.options.single.totalDueMinorUnits, 1300);
    expect(result.changeRequest.targetOfferId, 'offer_demo_express_midday');
    expect(result.changeRequest.totalDueMinorUnits, 1300);
    expect(result.compensation.supportQueue, 'coach_rebook_queue');
    expect(result.nextAction, 'await_reissue');
  });

  test('self-service reissue posts direct zero-due ticket reissue', () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'POST /me/coach/bookings/booking_demo_express_direct/reissue':
          expect(
            request.headers.entries.any(
              (entry) =>
                  entry.key.toLowerCase() == 'idempotency-key' &&
                  entry.value == 'coach-reissue-test-1',
            ),
            isTrue,
          );
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['target_offer_id'], 'offer_demo_express_evening');
          expect(body['preferred_seat_numbers'], <String>['5A', '5B']);
          expect(body['delivery_channels'], <String>['wallet_pass', 'pdf']);
          expect(body['reason'], 'switch to evening departure');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'ticket_reissue',
              'idempotency': <String, Object?>{
                'key': 'coach-reissue-test-1',
                'scope': 'coach_ticket_reissue',
                'request_fingerprint': 'fp_ticket_reissue_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'ticket_reissue': 'coach_ticket_reissue_upstream.1234',
                  'wallet_artifact': 'coach_wallet_artifact.1234',
                },
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_evening',
                'hold_id': 'hold_booking_demo_express_direct_reissue',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 8880,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'change_request': <String, Object?>{
                'change_request_id': 'changereq_demo_reissue_1',
                'booking_id': 'booking_demo_express_direct',
                'status': 'reissued',
                'target_offer_id': 'offer_demo_express_evening',
                'currency': 'SYP',
                'fare_difference_minor_units': -300,
                'change_fee_minor_units': 300,
                'total_due_minor_units': 0,
                'reason': 'switch to evening departure',
                'created_at': '2026-04-07T13:20:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_booking_demo_express_direct_reissue_1',
                  'booking_id': 'booking_demo_express_direct',
                  'coupon_id':
                      'coupon-ticket_booking_demo_express_direct_reissue_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_booking_demo_express_evening_1'],
                  'status': 'active',
                  'operator_ticket_reference':
                      'operator-ticket-ticket_booking_demo_express_direct_reissue_1',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_booking_demo_express_direct_reissue_1/qr',
                  'issued_at': '2026-04-07T13:20:00Z',
                  'artifacts': <Map<String, Object?>>[
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_qr',
                      'ticket_id':
                          'ticket_booking_demo_express_direct_reissue_1',
                      'booking_id': 'booking_demo_express_direct',
                      'artifact_kind': 'qr',
                      'delivery_channel': 'qr',
                      'status': 'ready',
                      'file_name':
                          'ticket_booking_demo_express_direct_reissue_1-qr.svg',
                      'mime_type': 'image/svg+xml',
                      'content_length_bytes': 2048,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_qr.svg',
                    },
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_wallet',
                      'ticket_id':
                          'ticket_booking_demo_express_direct_reissue_1',
                      'booking_id': 'booking_demo_express_direct',
                      'artifact_kind': 'wallet_pass',
                      'delivery_channel': 'wallet_pass',
                      'status': 'ready',
                      'file_name':
                          'ticket_booking_demo_express_direct_reissue_1.pkpass',
                      'mime_type': 'application/vnd.apple.pkpass',
                      'content_length_bytes': 8192,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_wallet.pkpass',
                    },
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_pdf',
                      'ticket_id':
                          'ticket_booking_demo_express_direct_reissue_1',
                      'booking_id': 'booking_demo_express_direct',
                      'artifact_kind': 'pdf',
                      'delivery_channel': 'pdf',
                      'status': 'ready',
                      'file_name':
                          'ticket_booking_demo_express_direct_reissue_1.pdf',
                      'mime_type': 'application/pdf',
                      'content_length_bytes': 32768,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_pdf.pdf',
                    },
                  ],
                },
              ],
              'delivery_channels': <String>['wallet_pass', 'pdf'],
              'compensation': <String, Object?>{
                'state': 'resolved',
                'action': 'reissue_completed',
                'support_queue': 'coach_rebook_queue',
                'triggered': false,
              },
              'next_action': 'completed',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final result = await api.selfServiceReissue(
      bookingId: 'booking_demo_express_direct',
      targetOfferId: 'offer_demo_express_evening',
      preferredSeatNumbers: const <String>['5A', '5B'],
      deliveryChannels: const <String>['wallet_pass', 'pdf'],
      reason: 'switch to evening departure',
      idempotencyKey: 'coach-reissue-test-1',
    );

    expect(result.changeRequest.status, 'reissued');
    expect(result.booking.offerId, 'offer_demo_express_evening');
    expect(result.tickets.single.ticketId,
        'ticket_booking_demo_express_direct_reissue_1');
    expect(result.deliveryChannels, const <String>['wallet_pass', 'pdf']);
    expect(result.payment, isNull);
    expect(result.compensation.action, 'reissue_completed');
    expect(result.nextAction, 'completed');
  });

  test('self-service reissue can authorize payable change collection',
      () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'POST /me/coach/bookings/booking_demo_express_direct/reissue':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['target_offer_id'], 'offer_demo_express_midday');
          expect(body['payment_method'], 'card');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'ticket_reissue',
              'idempotency': <String, Object?>{
                'key': 'coach-reissue-paid-test-1',
                'scope': 'coach_ticket_reissue',
                'request_fingerprint': 'fp_ticket_reissue_paid_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'ticket_reissue': 'coach_ticket_reissue_upstream.2222',
                  'wallet_artifact': 'coach_wallet_artifact.2222',
                },
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_midday',
                'hold_id': 'hold_booking_demo_express_direct_reissue',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9980,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'change_request': <String, Object?>{
                'change_request_id': 'changereq_demo_reissue_2',
                'booking_id': 'booking_demo_express_direct',
                'status': 'reissued',
                'target_offer_id': 'offer_demo_express_midday',
                'currency': 'SYP',
                'fare_difference_minor_units': 800,
                'change_fee_minor_units': 500,
                'total_due_minor_units': 1300,
                'reason': 'move to midday departure',
                'created_at': '2026-04-07T13:20:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_booking_demo_express_direct_reissue_1',
                  'booking_id': 'booking_demo_express_direct',
                  'coupon_id':
                      'coupon-ticket_booking_demo_express_direct_reissue_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_booking_demo_express_midday_1'],
                  'status': 'active',
                  'operator_ticket_reference':
                      'operator-ticket-ticket_booking_demo_express_direct_reissue_1',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_booking_demo_express_direct_reissue_1/qr',
                  'issued_at': '2026-04-07T13:20:00Z',
                  'artifacts': <Map<String, Object?>>[
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_qr',
                      'ticket_id':
                          'ticket_booking_demo_express_direct_reissue_1',
                      'booking_id': 'booking_demo_express_direct',
                      'artifact_kind': 'qr',
                      'delivery_channel': 'qr',
                      'status': 'ready',
                      'file_name':
                          'ticket_booking_demo_express_direct_reissue_1-qr.svg',
                      'mime_type': 'image/svg+xml',
                      'content_length_bytes': 2048,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_qr.svg',
                    },
                  ],
                },
              ],
              'delivery_channels': <String>['wallet_pass', 'pdf'],
              'payment': <String, Object?>{
                'status': 'authorized',
                'method': 'card',
                'authorization_reference': 'payauth_demo_reissue_change',
                'currency': 'SYP',
                'charged_minor_units': 1300,
              },
              'compensation': <String, Object?>{
                'state': 'resolved',
                'action': 'reissue_completed',
                'support_queue': 'coach_rebook_queue',
                'triggered': false,
              },
              'next_action': 'completed',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final result = await api.selfServiceReissue(
      bookingId: 'booking_demo_express_direct',
      targetOfferId: 'offer_demo_express_midday',
      preferredSeatNumbers: const <String>['5A', '5B'],
      deliveryChannels: const <String>['wallet_pass', 'pdf'],
      paymentMethod: 'card',
      reason: 'move to midday departure',
      idempotencyKey: 'coach-reissue-paid-test-1',
    );

    expect(result.changeRequest.totalDueMinorUnits, 1300);
    expect(result.booking.offerId, 'offer_demo_express_midday');
    expect(result.payment, isNotNull);
    expect(result.payment!.method, 'card');
    expect(result.payment!.chargedMinorUnits, 1300);
  });

  test('self-service reissue can surface payable collection failure', () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'POST /me/coach/bookings/booking_demo_express_direct/reissue':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['target_offer_id'], 'offer_demo_express_midday');
          expect(body['payment_method'], 'wallet_credit');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'ticket_reissue',
              'idempotency': <String, Object?>{
                'key': 'coach-reissue-wallet-failed-test-1',
                'scope': 'coach_ticket_reissue',
                'request_fingerprint': 'fp_ticket_reissue_wallet_failed_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'payment_authorize': 'coach_payment_authorize.4444',
                  'support_recovery': 'coach_reissue_recovery.4444',
                },
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_direct',
                'hold_id': 'hold_demo_express_direct',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'change_request': <String, Object?>{
                'change_request_id': 'changereq_demo_reissue_failed_1',
                'booking_id': 'booking_demo_express_direct',
                'status': 'payment_failed',
                'target_offer_id': 'offer_demo_express_midday',
                'currency': 'SYP',
                'fare_difference_minor_units': 800,
                'change_fee_minor_units': 500,
                'total_due_minor_units': 1300,
                'reason': 'move to midday departure',
                'created_at': '2026-04-07T13:20:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_booking_demo_express_direct_1',
                  'booking_id': 'booking_demo_express_direct',
                  'coupon_id': 'coupon-ticket_booking_demo_express_direct_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_booking_demo_express_direct_1'],
                  'status': 'active',
                  'operator_ticket_reference':
                      'operator-ticket-ticket_booking_demo_express_direct_1',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
                  'issued_at': '2026-04-07T12:06:30Z',
                },
              ],
              'delivery_channels': <String>['wallet_pass', 'pdf'],
              'payment': <String, Object?>{
                'status': 'failed',
                'method': 'wallet_credit',
                'authorization_reference':
                    'payauth_booking_demo_express_direct_wallet_credit_failed',
                'currency': 'SYP',
                'charged_minor_units': 0,
              },
              'compensation': <String, Object?>{
                'state': 'triggered',
                'action': 'retry_collection_or_raise_support_case',
                'support_queue': 'coach_rebook_queue',
                'triggered': true,
                'reason': 'wallet_credit_insufficient',
                'recovery_reference': 'recovery_demo_change_payment',
              },
              'next_action': 'resolve_payment_failure',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final result = await api.selfServiceReissue(
      bookingId: 'booking_demo_express_direct',
      targetOfferId: 'offer_demo_express_midday',
      preferredSeatNumbers: const <String>['5A', '5B'],
      deliveryChannels: const <String>['wallet_pass', 'pdf'],
      paymentMethod: 'wallet_credit',
      reason: 'move to midday departure',
      idempotencyKey: 'coach-reissue-wallet-failed-test-1',
    );

    expect(result.changeRequest.status, 'payment_failed');
    expect(result.booking.offerId, 'offer_demo_express_direct');
    expect(result.payment, isNotNull);
    expect(result.payment!.status, 'failed');
    expect(result.payment!.chargedMinorUnits, 0);
    expect(result.compensation.triggered, isTrue);
    expect(result.compensation.reason, 'wallet_credit_insufficient');
    expect(result.nextAction, 'resolve_payment_failure');
  });

  test('self-service reissue recovery can resolve payable collection failure',
      () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'POST /me/coach/bookings/booking_demo_express_direct/reissue/resolve_payment_failure':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['payment_method'], 'card');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'resolve_payment_failure',
              'idempotency': <String, Object?>{
                'key': 'coach-reissue-recovery-test-1',
                'scope': 'coach_ticket_reissue_recovery',
                'request_fingerprint': 'fp_ticket_reissue_recovery_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'ticket_reissue': 'coach_ticket_reissue_upstream.5555',
                  'wallet_artifact': 'coach_wallet_artifact.5555',
                },
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_express_direct',
                'offer_id': 'offer_demo_express_midday',
                'hold_id': 'hold_booking_demo_express_direct_reissue',
                'operator_booking_reference':
                    'operator-booking-booking_demo_express_direct',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9980,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'change_request': <String, Object?>{
                'change_request_id': 'changereq_demo_reissue_failed_1',
                'booking_id': 'booking_demo_express_direct',
                'status': 'reissued',
                'target_offer_id': 'offer_demo_express_midday',
                'currency': 'SYP',
                'fare_difference_minor_units': 800,
                'change_fee_minor_units': 500,
                'total_due_minor_units': 1300,
                'reason': 'move to midday departure',
                'created_at': '2026-04-07T13:30:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_booking_demo_express_direct_reissue_1',
                  'booking_id': 'booking_demo_express_direct',
                  'coupon_id':
                      'coupon-ticket_booking_demo_express_direct_reissue_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_booking_demo_express_midday_1'],
                  'status': 'active',
                  'operator_ticket_reference':
                      'operator-ticket-ticket_booking_demo_express_direct_reissue_1',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_booking_demo_express_direct_reissue_1/qr',
                  'issued_at': '2026-04-07T13:30:30Z',
                },
              ],
              'delivery_channels': <String>['wallet_pass', 'pdf'],
              'payment': <String, Object?>{
                'status': 'authorized',
                'method': 'card',
                'authorization_reference':
                    'payauth_booking_demo_express_direct_card_1300',
                'currency': 'SYP',
                'charged_minor_units': 1300,
              },
              'compensation': <String, Object?>{
                'state': 'resolved',
                'action': 'reissue_completed',
                'support_queue': 'coach_rebook_queue',
                'triggered': false,
              },
              'next_action': 'completed',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final result = await api.resolveReissuePaymentFailure(
      bookingId: 'booking_demo_express_direct',
      paymentMethod: 'card',
      deliveryChannels: const <String>['wallet_pass', 'pdf'],
      idempotencyKey: 'coach-reissue-recovery-test-1',
    );

    expect(result.changeRequest.status, 'reissued');
    expect(result.nextAction, 'completed');
    expect(result.payment, isNotNull);
    expect(result.payment!.status, 'authorized');
    expect(result.payment!.method, 'card');
  });

  test('admin support recovery can resolve failed change payment', () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'POST /me/coach/admin/support/cases/booking_demo_change_payment_failed/resolve_payment_failure':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['payment_method'], 'card');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'resolve_payment_failure',
              'idempotency': <String, Object?>{
                'key': 'coach-admin-support-recovery-test-1',
                'scope': 'coach_ticket_reissue_recovery',
                'request_fingerprint': 'fp_ticket_reissue_recovery_admin_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'ticket_reissue': 'coach_ticket_reissue_upstream.7777',
                  'wallet_artifact': 'coach_wallet_artifact.7777',
                },
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo_change_payment_failed',
                'offer_id': 'offer_demo_express_midday',
                'hold_id': 'hold_booking_demo_change_payment_failed_reissue',
                'operator_booking_reference':
                    'operator-booking-booking_demo_change_payment_failed',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9980,
                'passenger_count': 1,
                'created_at': '2026-04-13T06:30:00Z',
              },
              'change_request': <String, Object?>{
                'change_request_id': 'changereq_demo_failed_1',
                'booking_id': 'booking_demo_change_payment_failed',
                'status': 'reissued',
                'target_offer_id': 'offer_demo_express_midday',
                'currency': 'SYP',
                'fare_difference_minor_units': 800,
                'change_fee_minor_units': 500,
                'total_due_minor_units': 1300,
                'reason': 'move to midday departure',
                'created_at': '2026-04-13T08:10:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_2',
                  'given_name': 'Omar',
                  'family_name': 'Darwish',
                  'rider_category': 'student',
                  'nationality_code': 'DE',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_change_demo_1_reissued',
                  'booking_id': 'booking_demo_change_payment_failed',
                  'coupon_id': 'coupon-ticket_change_demo_1_reissued',
                  'passenger_id': 'adult_2',
                  'segment_ids': <String>['seg_change_demo_midday_1'],
                  'status': 'active',
                  'operator_ticket_reference':
                      'operator-ticket-change-demo-1-reissued',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_change_demo_1_reissued/qr',
                  'issued_at': '2026-04-13T08:10:30Z',
                },
              ],
              'delivery_channels': <String>['wallet_pass', 'pdf'],
              'payment': <String, Object?>{
                'status': 'authorized',
                'method': 'card',
                'authorization_reference':
                    'payauth_booking_demo_change_payment_failed_card_1300',
                'currency': 'SYP',
                'charged_minor_units': 1300,
              },
              'compensation': <String, Object?>{
                'state': 'resolved',
                'action': 'reissue_completed',
                'support_queue': 'coach_rebook_queue',
                'triggered': false,
              },
              'next_action': 'completed',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final result = await api.adminResolveSupportCasePaymentFailure(
      caseId: 'booking_demo_change_payment_failed',
      paymentMethod: 'card',
      idempotencyKey: 'coach-admin-support-recovery-test-1',
    );

    expect(result.changeRequest.status, 'reissued');
    expect(result.payment?.status, 'authorized');
    expect(result.nextAction, 'completed');
  });

  test('createHold posts idempotent hold command and parses envelope',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/coach/holds');
      expect(
        request.headers.entries.any(
          (entry) =>
              entry.key.toLowerCase() == 'idempotency-key' &&
              entry.value == 'coach-hold-test-1',
        ),
        isTrue,
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['offer_id'], 'offer_demo_express_direct');
      expect(body['passengers'], 2);
      expect(body['passenger_ids'], <String>['pax_1', 'pax_2']);
      expect(body['preferred_seat_numbers'], <String>['4A', '4B']);
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'hold_create',
          'idempotency': <String, Object?>{
            'key': 'coach-hold-test-1',
            'scope': 'coach_hold_create',
            'request_fingerprint': 'fp_hold_create_1',
            'replayed': false,
            'derived_keys': <String, String>{
              'inventory_hold': 'coach_hold_inventory.1234',
            },
          },
          'offer': <String, Object?>{
            'offer_id': 'offer_demo_express_direct',
            'operator_id': 'op_demo_express',
            'itinerary_id': 'iti_demo_direct',
            'currency': 'SYP',
            'total_minor_units': 9180,
            'seats_requested': 2,
            'hold_supported': true,
            'changeable': true,
            'refundable': true,
            'expires_at': '2026-04-07T12:05:00Z',
          },
          'hold': <String, Object?>{
            'hold_id': 'hold_offer_demo_express_direct_abcd1234',
            'offer_id': 'offer_demo_express_direct',
            'operator_reference':
                'operator-hold_offer_demo_express_direct_abcd1234',
            'expires_at': '2026-04-07T12:04:30Z',
            'status': 'active',
            'seat_assignments': <Map<String, Object?>>[
              <String, Object?>{
                'passenger_id': 'pax_1',
                'seat_number': '4A',
              },
              <String, Object?>{
                'passenger_id': 'pax_2',
                'seat_number': '4B',
              },
            ],
          },
          'booking_state': 'hold_created',
          'hold_ttl_seconds': 300,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final response = await api.createHold(
      offerId: 'offer_demo_express_direct',
      passengers: 2,
      passengerIds: const <String>['pax_1', 'pax_2'],
      preferredSeatNumbers: const <String>['4A', '4B'],
      idempotencyKey: 'coach-hold-test-1',
    );

    expect(response.idempotency.key, 'coach-hold-test-1');
    expect(response.offer.seatsRequested, 2);
    expect(response.hold.seatAssignments.length, 2);
    expect(response.bookingState, 'hold_created');
  });

  test(
      'createBooking and issueTickets parse payment and compensation envelopes',
      () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'POST /me/coach/bookings':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['offer_id'], 'offer_demo_express_direct');
          expect(body['hold_id'], 'hold_demo');
          expect(body['passengers'], 2);
          expect(body['passenger_ids'], <String>['adult_1', 'adult_2']);
          expect(body['preferred_seat_numbers'], <String>['4A', '4B']);
          expect(body['passengers_manifest'], <Map<String, Object?>>[
            <String, Object?>{
              'passenger_id': 'adult_1',
              'given_name': 'Lina',
              'family_name': 'Haddad',
              'rider_category': 'adult',
              'nationality_code': 'SY',
            },
            <String, Object?>{
              'passenger_id': 'adult_2',
              'given_name': 'Omar',
              'family_name': 'Darwish',
              'rider_category': 'student',
              'nationality_code': 'DE',
            },
          ]);
          expect(body['payment_method'], 'wallet_credit');
          expect(body['contact_email'], 'pax@shamell.test');
          expect(body['accept_terms'], true);
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'booking_create',
              'idempotency': <String, Object?>{
                'key': 'coach-booking-test-1',
                'scope': 'coach_booking_create',
                'request_fingerprint': 'fp_booking_create_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'payment_authorize': 'coach_payment_authorize.1234',
                  'booking_finalize': 'coach_booking_finalize.1234',
                },
              },
              'offer': <String, Object?>{
                'offer_id': 'offer_demo_express_direct',
                'operator_id': 'op_demo_express',
                'itinerary_id': 'iti_demo_direct',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'seats_requested': 2,
                'hold_supported': true,
                'changeable': true,
                'refundable': true,
                'expires_at': '2026-04-07T12:05:00Z',
              },
              'hold': <String, Object?>{
                'hold_id': 'hold_demo',
                'offer_id': 'offer_demo_express_direct',
                'operator_reference': 'operator-hold_demo',
                'expires_at': '2026-04-07T12:04:30Z',
                'status': 'converted',
                'seat_assignments': <Map<String, Object?>>[
                  <String, Object?>{
                    'passenger_id': 'adult_1',
                    'seat_number': '4A',
                  },
                  <String, Object?>{
                    'passenger_id': 'adult_2',
                    'seat_number': '4B',
                  },
                ],
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
                <String, Object?>{
                  'passenger_id': 'adult_2',
                  'given_name': 'Omar',
                  'family_name': 'Darwish',
                  'rider_category': 'student',
                  'nationality_code': 'DE',
                },
              ],
              'booking': <String, Object?>{
                'booking_id': 'booking_demo',
                'offer_id': 'offer_demo_express_direct',
                'hold_id': 'hold_demo',
                'operator_booking_reference': 'operator-booking-booking_demo',
                'state': 'booking_pending',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'payment': <String, Object?>{
                'status': 'authorized',
                'method': 'wallet_credit',
                'authorization_reference': 'payauth_demo',
                'currency': 'SYP',
                'charged_minor_units': 9180,
              },
              'compensation': <String, Object?>{
                'state': 'armed',
                'action': 'void_payment_or_issue_refund_credit',
                'support_queue': 'coach_ticketing_failures',
                'triggered': false,
              },
              'next_action': 'issue_tickets',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/bookings/booking_demo/tickets':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['offer_id'], 'offer_demo_express_direct');
          expect(body['hold_id'], 'hold_demo');
          expect(body['passenger_ids'], <String>['adult_1', 'adult_2']);
          expect(body['passengers_manifest'], <Map<String, Object?>>[
            <String, Object?>{
              'passenger_id': 'adult_1',
              'given_name': 'Lina',
              'family_name': 'Haddad',
              'rider_category': 'adult',
              'nationality_code': 'SY',
            },
            <String, Object?>{
              'passenger_id': 'adult_2',
              'given_name': 'Omar',
              'family_name': 'Darwish',
              'rider_category': 'student',
              'nationality_code': 'DE',
            },
          ]);
          expect(body['delivery_channels'], <String>['wallet_pass', 'pdf']);
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'ticket_issue',
              'idempotency': <String, Object?>{
                'key': 'coach-ticket-test-1',
                'scope': 'coach_ticket_issue',
                'request_fingerprint': 'fp_ticket_issue_1',
                'replayed': false,
                'derived_keys': <String, String>{
                  'ticket_issue': 'coach_ticket_issue_upstream.1234',
                  'wallet_artifact': 'coach_wallet_artifact.1234',
                },
              },
              'booking': <String, Object?>{
                'booking_id': 'booking_demo',
                'offer_id': 'offer_demo_express_direct',
                'hold_id': 'hold_demo',
                'operator_booking_reference': 'operator-booking-booking_demo',
                'state': 'ticketed',
                'currency': 'SYP',
                'total_minor_units': 9180,
                'passenger_count': 2,
                'created_at': '2026-04-07T12:06:00Z',
              },
              'passengers_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
                <String, Object?>{
                  'passenger_id': 'adult_2',
                  'given_name': 'Omar',
                  'family_name': 'Darwish',
                  'rider_category': 'student',
                  'nationality_code': 'DE',
                },
              ],
              'tickets': <Map<String, Object?>>[
                <String, Object?>{
                  'ticket_id': 'ticket_demo_1',
                  'booking_id': 'booking_demo',
                  'coupon_id': 'coupon-ticket_demo_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_booking_demo_1'],
                  'status': 'active',
                  'operator_ticket_reference': 'operator-ticket-ticket_demo_1',
                  'qr_payload_ref': 'object://coach/tickets/ticket_demo_1/qr',
                  'artifacts': <Map<String, Object?>>[
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_1_qr',
                      'ticket_id': 'ticket_demo_1',
                      'booking_id': 'booking_demo',
                      'artifact_kind': 'qr',
                      'delivery_channel': 'qr',
                      'file_name': 'ticket_demo_1-qr.svg',
                      'mime_type': 'image/svg+xml',
                      'content_length_bytes': 2048,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_1_qr.svg',
                    },
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_1_wallet',
                      'ticket_id': 'ticket_demo_1',
                      'booking_id': 'booking_demo',
                      'artifact_kind': 'wallet_pass',
                      'delivery_channel': 'wallet_pass',
                      'file_name': 'ticket_demo_1.pkpass',
                      'mime_type': 'application/vnd.apple.pkpass',
                      'content_length_bytes': 8192,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_1_wallet.pkpass',
                    },
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_1_pdf',
                      'ticket_id': 'ticket_demo_1',
                      'booking_id': 'booking_demo',
                      'artifact_kind': 'pdf',
                      'delivery_channel': 'pdf',
                      'file_name': 'ticket_demo_1.pdf',
                      'mime_type': 'application/pdf',
                      'content_length_bytes': 32768,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_1_pdf.pdf',
                    },
                  ],
                  'issued_at': '2026-04-07T12:06:30Z',
                },
                <String, Object?>{
                  'ticket_id': 'ticket_demo_2',
                  'booking_id': 'booking_demo',
                  'coupon_id': 'coupon-ticket_demo_2',
                  'passenger_id': 'adult_2',
                  'segment_ids': <String>['seg_booking_demo_2'],
                  'status': 'active',
                  'operator_ticket_reference': 'operator-ticket-ticket_demo_2',
                  'qr_payload_ref': 'object://coach/tickets/ticket_demo_2/qr',
                  'artifacts': <Map<String, Object?>>[
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_2_qr',
                      'ticket_id': 'ticket_demo_2',
                      'booking_id': 'booking_demo',
                      'artifact_kind': 'qr',
                      'delivery_channel': 'qr',
                      'file_name': 'ticket_demo_2-qr.svg',
                      'mime_type': 'image/svg+xml',
                      'content_length_bytes': 2048,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_2_qr.svg',
                    },
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_2_wallet',
                      'ticket_id': 'ticket_demo_2',
                      'booking_id': 'booking_demo',
                      'artifact_kind': 'wallet_pass',
                      'delivery_channel': 'wallet_pass',
                      'file_name': 'ticket_demo_2.pkpass',
                      'mime_type': 'application/vnd.apple.pkpass',
                      'content_length_bytes': 8192,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_2_wallet.pkpass',
                    },
                    <String, Object?>{
                      'artifact_id': 'ticketartifact_demo_2_pdf',
                      'ticket_id': 'ticket_demo_2',
                      'booking_id': 'booking_demo',
                      'artifact_kind': 'pdf',
                      'delivery_channel': 'pdf',
                      'file_name': 'ticket_demo_2.pdf',
                      'mime_type': 'application/pdf',
                      'content_length_bytes': 32768,
                      'download_path':
                          '/downloads/coach/tickets/ticketartifact_demo_2_pdf.pdf',
                    },
                  ],
                  'issued_at': '2026-04-07T12:06:30Z',
                },
              ],
              'delivery_channels': <String>['wallet_pass', 'pdf'],
              'compensation': <String, Object?>{
                'state': 'not_triggered',
                'action': 'void_payment_or_issue_refund_credit',
                'support_queue': 'coach_ticketing_failures',
                'triggered': false,
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final booking = await api.createBooking(
      offerId: 'offer_demo_express_direct',
      holdId: 'hold_demo',
      passengers: 2,
      passengerIds: const <String>['adult_1', 'adult_2'],
      preferredSeatNumbers: const <String>['4A', '4B'],
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
      paymentMethod: 'wallet_credit',
      contactEmail: 'pax@shamell.test',
      acceptTerms: true,
      idempotencyKey: 'coach-booking-test-1',
    );
    final ticketing = await api.issueTickets(
      bookingId: booking.booking.bookingId,
      offerId: 'offer_demo_express_direct',
      holdId: 'hold_demo',
      passengerIds: const <String>['adult_1', 'adult_2'],
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
      deliveryChannels: const <String>['wallet_pass', 'pdf'],
      idempotencyKey: 'coach-ticket-test-1',
    );

    expect(booking.payment.status, 'authorized');
    expect(booking.payment.method, 'wallet_credit');
    expect(
        booking.passengerManifests
            .singleWhere((p) => p.passengerId == 'adult_2')
            .displayName,
        'Omar Darwish');
    expect(booking.compensation.state, 'armed');
    expect(ticketing.booking.state, CoachBookingLifecycleState.ticketed);
    expect(ticketing.passengerManifests.first.nationalityCode, 'SY');
    expect(ticketing.tickets.length, 2);
    expect(ticketing.tickets.first.artifacts.length, 3);
    expect(
      ticketing.tickets.first.artifactByKind('wallet_pass')!.downloadPath,
      contains('.pkpass'),
    );
    expect(ticketing.deliveryChannels, contains('wallet_pass'));
    expect(ticketing.compensation.triggered, isFalse);
  });

  test('operator queues and review commands parse coach ops worklists',
      () async {
    final client = MockClient((request) async {
      final key = '${request.method} ${request.url.path}';
      switch (key) {
        case 'GET /me/coach/operator/refund_queue':
          expect(request.url.queryParameters['limit'], '8');
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T14:10:00Z',
              'totals': <String, Object?>{
                'open_requests': 2,
                'pending_review': 2,
                'approved': 0,
                'rejected': 0,
                'credit_requests': 1,
                'cash_requests': 1,
              },
              'requests': <Map<String, Object?>>[
                <String, Object?>{
                  'refund_request_id': 'refundreq_demo_credit',
                  'booking_id': 'booking_demo_express_direct',
                  'journey_id': 'journey_demo_express_direct',
                  'operator_name': 'Demo Express',
                  'from': 'Damascus',
                  'to': 'Aleppo',
                  'departure_at': '2026-04-08T08:00:00Z',
                  'arrival_at': '2026-04-08T12:30:00Z',
                  'booking_state': 'refund_requested',
                  'request_status': 'requested',
                  'selected_kind': 'refund_credit',
                  'currency': 'SYP',
                  'requested_minor_units': 9180,
                  'fee_minor_units': 0,
                  'ticket_ids': <String>['ticket_demo_1', 'ticket_demo_2'],
                  'reason': 'customer changed plans',
                  'requested_at': '2026-04-07T13:00:00Z',
                  'queue_status': 'pending_review',
                  'urgency': 'medium',
                  'suggested_action':
                      'Travel credit can be approved immediately.',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/change_queue':
          expect(request.url.queryParameters['limit'], '8');
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T14:10:00Z',
              'totals': <String, Object?>{
                'open_requests': 2,
                'pending_review': 2,
                'approved': 0,
                'rejected': 0,
                'collection_required_requests': 1,
                'zero_due_requests': 1,
              },
              'requests': <Map<String, Object?>>[
                <String, Object?>{
                  'change_request_id': 'changereq_demo_midday',
                  'booking_id': 'booking_demo_express_direct',
                  'journey_id': 'journey_demo_express_direct',
                  'operator_name': 'Demo Express',
                  'from': 'Damascus',
                  'to': 'Aleppo',
                  'departure_at': '2026-04-08T08:00:00Z',
                  'arrival_at': '2026-04-08T12:30:00Z',
                  'booking_state': 'ticketed',
                  'request_status': 'requested',
                  'target_offer_id': 'offer_demo_express_midday',
                  'target_journey_id': 'journey_demo_express_midday',
                  'currency': 'SYP',
                  'fare_difference_minor_units': 800,
                  'change_fee_minor_units': 500,
                  'total_due_minor_units': 1300,
                  'reason': 'move to midday departure',
                  'requested_at': '2026-04-07T13:05:00Z',
                  'queue_status': 'pending_review',
                  'urgency': 'high',
                  'suggested_action':
                      'Collect the fare difference before reissuing tickets.',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/reconciliation':
          expect(request.url.queryParameters['limit'], '6');
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T15:20:00Z',
              'summary': <String, Object?>{
                'currency': 'SYP',
                'trip_count': 2,
                'manifest_passengers': 3,
                'boarded_passengers': 1,
                'pending_boarding_passengers': 2,
                'needs_attention_passengers': 1,
                'pending_review_requests': 2,
                'reviewed_requests': 2,
                'approved_credit_refund_minor_units': 9180,
                'approved_cash_refund_minor_units': 0,
                'approved_collection_due_minor_units': 0,
              },
              'trip_snapshots': <Map<String, Object?>>[
                <String, Object?>{
                  'trip': <String, Object?>{
                    'trip_id': 'trip_demo_express_direct',
                    'journey_id': 'journey_demo_express_direct',
                    'booking_id': 'booking_demo_express_direct',
                    'operator_name': 'Demo Express',
                    'from': 'Damascus',
                    'to': 'Aleppo',
                    'departure_at': '2026-04-08T08:00:00Z',
                    'arrival_at': '2026-04-08T12:30:00Z',
                    'boarding_opens_at': '2026-04-08T07:20:00Z',
                    'boarding_closes_at': '2026-04-08T07:55:00Z',
                    'gate_label': 'Bay A4',
                    'vehicle_label': 'Bus DX-402',
                    'manifest_count': 2,
                    'boarded_count': 1,
                    'denied_count': 0,
                    'no_show_count': 0,
                    'pending_count': 1,
                  },
                  'recent_events': <Map<String, Object?>>[
                    <String, Object?>{
                      'boarding_event_id': 'boardevt_demo_scan',
                      'ticket_id': 'ticket_demo_1',
                      'trip_id': 'trip_demo_express_direct',
                      'scan_status': 'duplicate',
                      'captured_at': '2026-04-08T07:42:30Z',
                      'offline_captured': false,
                      'device_id': 'crew_device_demo',
                      'note': 'duplicate scan at gate',
                    },
                  ],
                  'pending_ticket_ids': <String>['ticket_demo_2'],
                  'needs_attention_count': 1,
                },
              ],
              'review_history': <Map<String, Object?>>[
                <String, Object?>{
                  'request_kind': 'refund_request',
                  'request_id': 'refundreq_demo_credit',
                  'booking_id': 'booking_demo_express_direct',
                  'journey_id': 'journey_demo_express_direct',
                  'operator_name': 'Demo Express',
                  'from': 'Damascus',
                  'to': 'Aleppo',
                  'departure_at': '2026-04-08T08:00:00Z',
                  'queue_status': 'approved',
                  'urgency': 'medium',
                  'subject_label': 'Travel credit',
                  'currency': 'SYP',
                  'amount_minor_units': 9180,
                  'suggested_action': 'Customer notification is queued.',
                  'reviewed_at': '2026-04-07T14:15:00Z',
                  'reviewed_by_account_id': 'acct_ops_demo',
                  'review_note': 'approved by finance ops',
                  'settlement_effect': <String, Object?>{
                    'kind': 'travel_credit_liability',
                    'currency': 'SYP',
                    'amount_minor_units': 9180,
                  },
                  'next_action': 'customer_notification_queued',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/settlement_statements':
          expect(request.url.queryParameters['limit'], '4');
          if (request.url.queryParameters['cursor'] ==
              '2026-04-13T23:59:59Z|settlement_op_demo_express_2026w15') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'generated_at': '2026-04-07T15:35:00Z',
                'next_cursor': null,
                'statements': <Map<String, Object?>>[
                  <String, Object?>{
                    'statement_id': 'settlement_op_border_runner_2026w14',
                    'operator_id': 'op_border_runner',
                    'operator_name': 'Border Runner',
                    'currency': 'SYP',
                    'period_start': '2026-03-31T00:00:00Z',
                    'period_end': '2026-04-06T23:59:59Z',
                    'next_payout_at': '2026-04-07T10:00:00Z',
                    'status': 'paid_out',
                    'download_formats': <String>['csv', 'datev_json'],
                    'totals': <String, Object?>{
                      'line_count': 1,
                      'gross_minor_units': 5690,
                      'commission_minor_units': 730,
                      'refund_minor_units': 0,
                      'chargeback_reserve_minor_units': 160,
                      'manual_adjustment_minor_units': 0,
                      'net_payable_minor_units': 4800,
                    },
                    'lines': <Map<String, Object?>>[
                      <String, Object?>{
                        'settlement_id': 'settlement_op_border_runner_2026w14',
                        'operator_id': 'op_border_runner',
                        'booking_id': 'booking_demo_border_runner',
                        'basis': 'ticketed',
                        'currency': 'SYP',
                        'gross_minor_units': 5690,
                        'commission_minor_units': 730,
                        'refund_minor_units': 0,
                        'chargeback_reserve_minor_units': 160,
                        'manual_adjustment_minor_units': 0,
                        'net_payable_minor_units': 4800,
                      },
                    ],
                  },
                ],
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json'
              },
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T15:35:00Z',
              'next_cursor':
                  '2026-04-13T23:59:59Z|settlement_op_demo_express_2026w15',
              'statements': <Map<String, Object?>>[
                <String, Object?>{
                  'statement_id': 'settlement_op_demo_express_2026w15',
                  'operator_id': 'op_demo_express',
                  'operator_name': 'Demo Express',
                  'currency': 'SYP',
                  'period_start': '2026-04-07T00:00:00Z',
                  'period_end': '2026-04-13T23:59:59Z',
                  'next_payout_at': '2026-04-14T10:00:00Z',
                  'status': 'ready_for_payout',
                  'download_formats': <String>['csv', 'datev_json'],
                  'totals': <String, Object?>{
                    'line_count': 1,
                    'gross_minor_units': 9180,
                    'commission_minor_units': 1180,
                    'refund_minor_units': 0,
                    'chargeback_reserve_minor_units': 200,
                    'manual_adjustment_minor_units': 0,
                    'net_payable_minor_units': 7800,
                  },
                  'lines': <Map<String, Object?>>[
                    <String, Object?>{
                      'settlement_id': 'settlement_op_demo_express_2026w15',
                      'operator_id': 'op_demo_express',
                      'booking_id': 'booking_demo_express_direct',
                      'basis': 'boarded',
                      'currency': 'SYP',
                      'gross_minor_units': 9180,
                      'commission_minor_units': 1180,
                      'refund_minor_units': 0,
                      'chargeback_reserve_minor_units': 200,
                      'manual_adjustment_minor_units': 0,
                      'net_payable_minor_units': 7800,
                    },
                  ],
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/payout_runs':
          expect(request.url.queryParameters['limit'], '5');
          if (request.url.queryParameters['cursor'] ==
              '2026-04-07T15:50:00Z|payoutrun_demo_express') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'generated_at': '2026-04-07T15:45:00Z',
                'summary': <String, Object?>{
                  'currency': 'SYP',
                  'queued_runs': 1,
                  'paid_runs': 1,
                  'failed_runs': 0,
                  'queued_statement_count': 1,
                  'queued_net_payable_minor_units': 7800,
                  'paid_net_payable_minor_units': 4800,
                },
                'next_cursor': null,
                'runs': <Map<String, Object?>>[
                  <String, Object?>{
                    'payout_run_id': 'payoutrun_demo_older',
                    'status': 'paid',
                    'currency': 'SYP',
                    'statement_ids': <String>[
                      'settlement_op_border_runner_2026w15',
                    ],
                    'operator_ids': <String>['op_border_runner'],
                    'operator_names': <String>['Border Runner'],
                    'statement_count': 1,
                    'gross_minor_units': 5690,
                    'reserve_minor_units': 150,
                    'net_payable_minor_units': 4800,
                    'created_at': '2026-04-07T15:40:00Z',
                    'paid_at': '2026-04-14T10:05:00Z',
                    'created_by_account_id': 'acct_finance_demo',
                    'paid_by_account_id': 'acct_finance_demo',
                    'payment_reference': 'payout_batch_2026w15',
                    'note': 'settled in payout rail',
                    'available_export_formats': <String>['csv', 'datev_json'],
                    'exports': <Map<String, Object?>>[
                      <String, Object?>{
                        'export_id': 'export_payoutrun_demo_older_csv',
                        'payout_run_id': 'payoutrun_demo_older',
                        'export_format': 'csv',
                        'status': 'ready',
                        'file_name':
                            'coach-settlement-payoutrun_demo_older.csv',
                        'mime_type': 'text/csv; charset=utf-8',
                        'download_path':
                            '/downloads/coach/settlement_exports/export_payoutrun_demo_older_csv.csv',
                        'checksum_sha256': 'sha256_demo_older_csv',
                        'content_length_bytes': 182,
                        'created_at': '2026-04-14T10:15:00Z',
                        'created_by_account_id': 'acct_finance_demo',
                        'statement_ids': <String>[
                          'settlement_op_border_runner_2026w15',
                        ],
                        'operator_ids': <String>['op_border_runner'],
                        'note': 'prepared after payout',
                      },
                    ],
                  },
                ],
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T15:45:00Z',
              'summary': <String, Object?>{
                'currency': 'SYP',
                'queued_runs': 1,
                'paid_runs': 1,
                'failed_runs': 0,
                'queued_statement_count': 1,
                'queued_net_payable_minor_units': 7800,
                'paid_net_payable_minor_units': 4800,
              },
              'next_cursor': '2026-04-07T15:50:00Z|payoutrun_demo_express',
              'runs': <Map<String, Object?>>[
                <String, Object?>{
                  'payout_run_id': 'payoutrun_demo_express',
                  'status': 'queued',
                  'currency': 'SYP',
                  'statement_ids': <String>[
                    'settlement_op_demo_express_2026w15',
                  ],
                  'operator_ids': <String>['op_demo_express'],
                  'operator_names': <String>['Demo Express'],
                  'statement_count': 1,
                  'gross_minor_units': 9180,
                  'reserve_minor_units': 200,
                  'net_payable_minor_units': 7800,
                  'created_at': '2026-04-07T15:50:00Z',
                  'created_by_account_id': 'acct_finance_demo',
                  'note': 'queued from coach ops console',
                  'available_export_formats': <String>['csv', 'datev_json'],
                  'exports': const <Map<String, Object?>>[],
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/payout_reconciliation':
          expect(request.url.queryParameters['limit'], '5');
          final cursor = request.url.queryParameters['cursor'];
          if (cursor == '2026-04-14T10:04:00Z|payoutrun_demo_partial') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'generated_at': '2026-04-07T16:05:00Z',
                'summary': <String, Object?>{
                  'currency': 'SYP',
                  'run_count': 3,
                  'balanced_runs': 1,
                  'attention_runs': 1,
                  'queued_runs': 1,
                  'failed_runs': 0,
                  'missing_payment_reference_runs': 0,
                  'missing_exports_runs': 0,
                  'partial_export_runs': 1,
                  'paid_net_payable_minor_units': 7900,
                  'attention_net_payable_minor_units': 100,
                },
                'runs': <Map<String, Object?>>[
                  <String, Object?>{
                    'payout_run_id': 'payoutrun_demo_queued',
                    'run_status': 'queued',
                    'reconciliation_status': 'awaiting_bank_execution',
                    'currency': 'SYP',
                    'operator_names': <String>['Queued Runner'],
                    'statement_ids': <String>[
                      'settlement_op_queued_runner_2026w15',
                    ],
                    'payment_reference': null,
                    'net_payable_minor_units': 2400,
                    'available_export_formats': <String>[
                      'csv',
                      'datev_json',
                    ],
                    'ready_export_formats': const <String>[],
                    'missing_export_formats': const <String>[],
                    'created_at': '2026-04-13T10:04:00Z',
                    'paid_at': null,
                    'needs_attention': false,
                    'attention_reasons': const <String>[],
                    'next_action':
                        'Wait for the external payout rail to confirm execution.',
                  },
                ],
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T16:05:00Z',
              'summary': <String, Object?>{
                'currency': 'SYP',
                'run_count': 3,
                'balanced_runs': 1,
                'attention_runs': 1,
                'queued_runs': 1,
                'failed_runs': 0,
                'missing_payment_reference_runs': 0,
                'missing_exports_runs': 0,
                'partial_export_runs': 1,
                'paid_net_payable_minor_units': 7900,
                'attention_net_payable_minor_units': 100,
              },
              'next_cursor': '2026-04-14T10:04:00Z|payoutrun_demo_partial',
              'runs': <Map<String, Object?>>[
                <String, Object?>{
                  'payout_run_id': 'payoutrun_demo_balanced',
                  'run_status': 'paid',
                  'reconciliation_status': 'balanced',
                  'currency': 'SYP',
                  'operator_names': <String>['Demo Express'],
                  'statement_ids': <String>[
                    'settlement_op_demo_express_2026w15',
                  ],
                  'payment_reference': 'payout_batch_2026w15',
                  'net_payable_minor_units': 7800,
                  'available_export_formats': <String>['csv', 'datev_json'],
                  'ready_export_formats': <String>['csv', 'datev_json'],
                  'missing_export_formats': const <String>[],
                  'created_at': '2026-04-14T10:05:00Z',
                  'paid_at': '2026-04-14T10:05:00Z',
                  'needs_attention': false,
                  'attention_reasons': const <String>[],
                  'next_action': 'No further reconciliation action required.',
                },
                <String, Object?>{
                  'payout_run_id': 'payoutrun_demo_partial',
                  'run_status': 'paid',
                  'reconciliation_status': 'partial_exports',
                  'currency': 'SYP',
                  'operator_names': <String>['Border Runner'],
                  'statement_ids': <String>[
                    'settlement_op_border_runner_2026w15',
                  ],
                  'payment_reference': 'payout_batch_2026w15',
                  'net_payable_minor_units': 100,
                  'available_export_formats': <String>['csv', 'datev_json'],
                  'ready_export_formats': <String>['csv'],
                  'missing_export_formats': <String>['datev_json'],
                  'created_at': '2026-04-14T10:04:00Z',
                  'paid_at': '2026-04-14T10:04:00Z',
                  'needs_attention': true,
                  'attention_reasons': <String>[
                    'Missing export artifacts: datev_json.',
                  ],
                  'next_action':
                      'Generate the missing export formats before publishing the statement pack.',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/payout_imports':
          expect(request.url.queryParameters['limit'], '4');
          final cursor = request.url.queryParameters['cursor'];
          if (cursor == '2026-04-14T10:06:00Z|payoutimport_demo_executed') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'generated_at': '2026-04-07T16:10:00Z',
                'summary': <String, Object?>{
                  'total_imports': 3,
                  'executed_imports': 2,
                  'failed_imports': 1,
                  'pending_imports': 0,
                },
                'next_cursor': null,
                'imports': <Map<String, Object?>>[
                  <String, Object?>{
                    'import_id': 'payoutimport_demo_older',
                    'import_batch_id': 'payoutbatch_demo_older',
                    'payout_run_id': 'payoutrun_demo_older',
                    'import_source': 'psp_report',
                    'external_status': 'executed',
                    'payment_reference': 'psp_transfer_demo_older',
                    'external_reference': 'psp_batch_2026w14',
                    'imported_at': '2026-04-01T10:06:00Z',
                    'imported_by_account_id': 'acct_finance_demo',
                    'previous_run_status': 'queued',
                    'applied_run_status': 'paid',
                    'note': 'older import applied from coach ops console',
                  },
                ],
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json'
              },
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T16:10:00Z',
              'summary': <String, Object?>{
                'total_imports': 3,
                'executed_imports': 2,
                'failed_imports': 1,
                'pending_imports': 0,
              },
              'next_cursor': '2026-04-14T10:06:00Z|payoutimport_demo_executed',
              'imports': <Map<String, Object?>>[
                <String, Object?>{
                  'import_id': 'payoutimport_demo_executed',
                  'import_batch_id': 'payoutbatch_demo_1',
                  'payout_run_id': 'payoutrun_demo_express',
                  'import_source': 'bank_report',
                  'external_status': 'executed',
                  'payment_reference': 'bank_import_payoutrun_demo_express',
                  'external_reference': 'bank_file_2026w15',
                  'imported_at': '2026-04-14T10:06:00Z',
                  'imported_by_account_id': 'acct_finance_demo',
                  'previous_run_status': 'queued',
                  'applied_run_status': 'paid',
                  'note': 'executed import applied from coach ops console',
                },
                <String, Object?>{
                  'import_id': 'payoutimport_demo_failed',
                  'import_batch_id': 'payoutbatch_demo_1',
                  'payout_run_id': 'payoutrun_demo_failed',
                  'import_source': 'bank_report',
                  'external_status': 'failed',
                  'external_reference': 'bank_file_2026w15',
                  'imported_at': '2026-04-14T10:07:00Z',
                  'imported_by_account_id': 'acct_finance_demo',
                  'previous_run_status': 'queued',
                  'applied_run_status': 'failed',
                  'note': 'failed import applied from coach ops console',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/payout_import_profiles':
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T16:11:00Z',
              'profiles': <Map<String, Object?>>[
                <String, Object?>{
                  'import_source': 'bank_report',
                  'title': 'Bank payout report',
                  'summary':
                      'Use this for bank execution files where SyrChat payout runs are carried as merchant references.',
                  'report_format': 'csv',
                  'supported_delimiters': <String>['comma', 'semicolon'],
                  'status_mappings': <Map<String, Object?>>[
                    <String, Object?>{
                      'normalized_status': 'pending',
                      'accepted_values': <String>[
                        'pending',
                        'processing',
                        'queued',
                      ],
                      'required_fields': const <String>[],
                      'description':
                          'Keeps the payout run queued until the bank execution is final.',
                    },
                    <String, Object?>{
                      'normalized_status': 'executed',
                      'accepted_values': <String>[
                        'executed',
                        'completed',
                        'paid',
                      ],
                      'required_fields': <String>['payment_reference'],
                      'description':
                          'Marks the payout run as paid after bank execution is confirmed.',
                    },
                  ],
                  'sample_body':
                      'merchant_reference;bank_status;transfer_reference;bank_file_reference;executed_at;comment\npayoutrun_demo_express;executed;bank_import_payoutrun_demo_express;bank_file_2026w15;2026-04-14T10:06:00Z;executed import applied from coach ops console',
                  'fields': <Map<String, Object?>>[
                    <String, Object?>{
                      'key': 'payout_run_id',
                      'required': true,
                      'accepted_headers': <String>[
                        'payout_run_id',
                        'merchant_reference',
                        'metadata_payout_run_id',
                      ],
                      'description':
                          'Internal SyrChat payout run reference attached to the bank transfer.',
                    },
                  ],
                },
                <String, Object?>{
                  'import_source': 'psp_report',
                  'title': 'PSP payout report',
                  'summary':
                      'Use this for Stripe Connect, Adyen or other marketplace payout exports.',
                  'report_format': 'csv',
                  'supported_delimiters': <String>[
                    'comma',
                    'semicolon',
                    'tab',
                  ],
                  'status_mappings': <Map<String, Object?>>[
                    <String, Object?>{
                      'normalized_status': 'pending',
                      'accepted_values': <String>[
                        'pending',
                        'processing',
                        'in_transit',
                      ],
                      'required_fields': const <String>[],
                      'description':
                          'Keeps the payout run queued while the PSP transfer is still in flight.',
                    },
                    <String, Object?>{
                      'normalized_status': 'executed',
                      'accepted_values': <String>[
                        'booked',
                        'settled',
                        'succeeded',
                      ],
                      'required_fields': <String>[
                        'payment_reference',
                        'external_reference',
                      ],
                      'description':
                          'Marks the payout run as paid once the PSP rail reports a successful transfer.',
                    },
                  ],
                  'sample_body':
                      'merchant_reference,psp_status,psp_reference,settlement_reference,booked_at,description\npayoutrun_demo_express,booked,psp_transfer_payoutrun_demo_express,psp_batch_2026w15,2026-04-14T10:06:00Z,booked by PSP payout rail',
                  'fields': <Map<String, Object?>>[
                    <String, Object?>{
                      'key': 'external_status',
                      'required': true,
                      'accepted_headers': <String>[
                        'external_status',
                        'psp_status',
                        'transfer_status',
                        'status',
                      ],
                      'description':
                          'Payout status from the PSP or marketplace rail.',
                    },
                  ],
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/payout_import_previews':
          expect(request.url.queryParameters['limit'], '4');
          final status = request.url.queryParameters['status'];
          final fromCreatedAt = request.url.queryParameters['from_created_at'];
          final toCreatedAt = request.url.queryParameters['to_created_at'];
          final cursor = request.url.queryParameters['cursor'];
          if (status == 'invalidated') {
            expect(fromCreatedAt, '2026-04-14T00:00:00Z');
            expect(toCreatedAt, '2026-04-14T23:59:59Z');
            expect(cursor, isNull);
            return http.Response(
              jsonEncode(<String, Object?>{
                'generated_at': '2026-04-14T16:11:00Z',
                'summary': <String, Object?>{
                  'total_previews': 1,
                  'active_previews': 0,
                  'consumed_previews': 0,
                  'expired_previews': 0,
                  'invalidated_previews': 1,
                },
                'previews': <Map<String, Object?>>[
                  <String, Object?>{
                    'preview_token': 'previewtoken_demo_invalidated',
                    'account_id': 'acct_finance_demo',
                    'import_source': 'bank_report',
                    'report_name': 'bank_report_2026w15.csv',
                    'report_format': 'csv',
                    'rework_of_batch_id': 'payoutbatch_demo_1',
                    'report_checksum_sha256': 'sha256_demo_invalidated',
                    'request_fingerprint': 'fp_preview_invalidated_demo',
                    'preview_status': 'invalidated',
                    'created_at': '2026-04-14T10:08:00Z',
                    'expires_at': '2026-04-14T10:18:00Z',
                    'consumed_at': null,
                    'invalidated_at': '2026-04-14T10:09:00Z',
                    'usable_now': false,
                  },
                ],
                'next_cursor': null,
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }
          if (cursor == '2026-04-14T09:08:00Z|previewtoken_demo_consumed') {
            expect(status, isNull);
            expect(fromCreatedAt, isNull);
            expect(toCreatedAt, isNull);
            return http.Response(
              jsonEncode(<String, Object?>{
                'generated_at': '2026-04-07T16:11:00Z',
                'summary': <String, Object?>{
                  'total_previews': 3,
                  'active_previews': 1,
                  'consumed_previews': 1,
                  'expired_previews': 1,
                  'invalidated_previews': 0,
                },
                'next_cursor': null,
                'previews': <Map<String, Object?>>[
                  <String, Object?>{
                    'preview_token': 'previewtoken_demo_expired',
                    'account_id': 'acct_finance_demo',
                    'import_source': 'psp_report',
                    'report_name': 'psp_report_2026w13.csv',
                    'report_format': 'csv',
                    'operator_ids': <String>['op_border_runner'],
                    'rework_of_batch_id': null,
                    'report_checksum_sha256': 'sha256_demo_expired',
                    'request_fingerprint': 'fp_preview_expired_demo',
                    'preview_status': 'expired',
                    'created_at': '2026-04-01T09:08:00Z',
                    'expires_at': '2026-04-01T09:18:00Z',
                    'consumed_at': null,
                    'invalidated_at': null,
                    'usable_now': false,
                  },
                ],
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json'
              },
            );
          }
          expect(status, isNull);
          expect(fromCreatedAt, isNull);
          expect(toCreatedAt, isNull);
          expect(cursor, isNull);
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T16:11:00Z',
              'summary': <String, Object?>{
                'total_previews': 3,
                'active_previews': 1,
                'consumed_previews': 1,
                'expired_previews': 1,
                'invalidated_previews': 0,
              },
              'next_cursor': '2026-04-14T09:08:00Z|previewtoken_demo_consumed',
              'previews': <Map<String, Object?>>[
                <String, Object?>{
                  'preview_token': 'previewtoken_demo_active',
                  'account_id': 'acct_finance_demo',
                  'import_source': 'bank_report',
                  'report_name': 'bank_report_2026w15.csv',
                  'report_format': 'csv',
                  'operator_ids': <String>['op_demo_express'],
                  'rework_of_batch_id': 'payoutbatch_demo_1',
                  'report_checksum_sha256': 'sha256_demo_active',
                  'request_fingerprint': 'fp_preview_active_demo',
                  'preview_status': 'active',
                  'created_at': '2026-04-14T10:08:00Z',
                  'expires_at': '2026-04-14T10:18:00Z',
                  'consumed_at': null,
                  'invalidated_at': null,
                  'usable_now': true,
                },
                <String, Object?>{
                  'preview_token': 'previewtoken_demo_consumed',
                  'account_id': 'acct_finance_demo',
                  'import_source': 'bank_report',
                  'report_name': 'bank_report_2026w14.csv',
                  'report_format': 'csv',
                  'operator_ids': <String>['op_demo_express'],
                  'rework_of_batch_id': null,
                  'report_checksum_sha256': 'sha256_demo_consumed',
                  'request_fingerprint': 'fp_preview_consumed_demo',
                  'preview_status': 'consumed',
                  'created_at': '2026-04-14T09:08:00Z',
                  'expires_at': '2026-04-14T09:18:00Z',
                  'consumed_at': '2026-04-14T09:09:00Z',
                  'invalidated_at': null,
                  'usable_now': false,
                },
                <String, Object?>{
                  'preview_token': 'previewtoken_demo_expired',
                  'account_id': 'acct_finance_demo',
                  'import_source': 'psp_report',
                  'report_name': 'psp_report_2026w13.csv',
                  'report_format': 'csv',
                  'operator_ids': <String>['op_border_runner'],
                  'rework_of_batch_id': null,
                  'report_checksum_sha256': 'sha256_demo_expired',
                  'request_fingerprint': 'fp_preview_expired_demo',
                  'preview_status': 'expired',
                  'created_at': '2026-04-01T09:08:00Z',
                  'expires_at': '2026-04-01T09:18:00Z',
                  'consumed_at': null,
                  'invalidated_at': null,
                  'usable_now': false,
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/operator/payout_import_previews/previewtoken_demo_active/invalidate':
          expect(
            request.headers['Idempotency-Key'],
            isNotNull,
          );
          expect(request.body, '{}');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'payout_import_preview_invalidate',
              'idempotency': <String, Object?>{
                'key': 'coach-ops-payout-preview-invalidate-test-1',
                'scope': 'coach_operator_payout_import_preview_invalidate',
                'request_fingerprint': 'fp_ops_payout_preview_invalidate_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'preview': <String, Object?>{
                'preview_token': 'previewtoken_demo_active',
                'account_id': 'acct_finance_demo',
                'import_source': 'bank_report',
                'report_name': 'bank_report_2026w15.csv',
                'report_format': 'csv',
                'operator_ids': <String>['op_demo_express'],
                'rework_of_batch_id': 'payoutbatch_demo_1',
                'report_checksum_sha256': 'sha256_demo_active',
                'request_fingerprint': 'fp_preview_active_demo',
                'preview_status': 'invalidated',
                'created_at': '2026-04-14T10:08:00Z',
                'expires_at': '2026-04-14T10:18:00Z',
                'consumed_at': null,
                'invalidated_at': '2026-04-14T10:09:00Z',
                'usable_now': false,
              },
              'next_action': 'preview_invalidated',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/operator/payout_import_batches':
          expect(request.url.queryParameters['limit'], '4');
          final cursor = request.url.queryParameters['cursor'];
          if (cursor == '2026-04-14T10:08:00Z|payoutbatch_demo_1') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'generated_at': '2026-04-07T16:12:00Z',
                'summary': <String, Object?>{
                  'total_batches': 3,
                  'total_rows': 4,
                  'applied_rows': 3,
                  'failed_rows': 1,
                },
                'next_cursor': null,
                'batches': <Map<String, Object?>>[
                  <String, Object?>{
                    'batch_id': 'payoutbatch_demo_older',
                    'dry_run': false,
                    'import_source': 'psp_report',
                    'report_name': 'psp_report_2026w14.csv',
                    'report_format': 'csv',
                    'operator_ids': <String>['op_border_runner'],
                    'follow_up_batch_ids': const <String>[],
                    'report_checksum_sha256': 'sha256_demo_older',
                    'total_rows': 1,
                    'applied_rows': 1,
                    'failed_rows': 0,
                    'payout_run_ids': <String>['payoutrun_demo_older'],
                    'failure_messages': const <String>[],
                    'created_at': '2026-04-01T10:08:00Z',
                    'created_by_account_id': 'acct_finance_demo',
                    'report_artifact': null,
                    'rework_artifact': null,
                    'note': 'older batch',
                  },
                ],
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T16:12:00Z',
              'summary': <String, Object?>{
                'total_batches': 3,
                'total_rows': 4,
                'applied_rows': 3,
                'failed_rows': 1,
              },
              'next_cursor': '2026-04-14T10:08:00Z|payoutbatch_demo_1',
              'batches': <Map<String, Object?>>[
                <String, Object?>{
                  'batch_id': 'payoutbatch_demo_1',
                  'dry_run': false,
                  'import_source': 'bank_report',
                  'report_name': 'bank_report_2026w15.csv',
                  'report_format': 'csv',
                  'operator_ids': <String>['op_demo_express'],
                  'follow_up_batch_ids': <String>['payoutbatch_demo_2'],
                  'report_checksum_sha256': 'sha256_demo_report',
                  'total_rows': 2,
                  'applied_rows': 1,
                  'failed_rows': 1,
                  'payout_run_ids': <String>['payoutrun_demo_express'],
                  'failure_messages': <String>[
                    'line 3 (payoutrun_demo_failed): not found',
                  ],
                  'created_at': '2026-04-14T10:08:00Z',
                  'created_by_account_id': 'acct_finance_demo',
                  'report_artifact': <String, Object?>{
                    'artifact_id': 'payoutreport_demo_1',
                    'batch_id': 'payoutbatch_demo_1',
                    'artifact_kind': 'source_report',
                    'import_source': 'bank_report',
                    'report_name': 'bank_report_2026w15.csv',
                    'report_format': 'csv',
                    'operator_ids': <String>['op_demo_express'],
                    'file_name': 'coach-payout-import-payoutbatch_demo_1.csv',
                    'mime_type': 'text/csv; charset=utf-8',
                    'download_path':
                        '/downloads/coach/payout_import_reports/payoutreport_demo_1.csv',
                    'checksum_sha256': 'sha256_demo_report',
                    'content_length_bytes': 182,
                    'created_at': '2026-04-14T10:08:00Z',
                    'created_by_account_id': 'acct_finance_demo',
                    'note': 'uploaded from coach ops console',
                  },
                  'rework_artifact': <String, Object?>{
                    'artifact_id': 'payoutrework_demo_1',
                    'batch_id': 'payoutbatch_demo_1',
                    'artifact_kind': 'failed_row_rework',
                    'import_source': 'bank_report',
                    'report_name':
                        'bank_report_2026w15.csv (failed row rework)',
                    'report_format': 'csv',
                    'operator_ids': <String>['op_demo_express'],
                    'file_name':
                        'coach-payout-import-rework-payoutbatch_demo_1.csv',
                    'mime_type': 'text/csv; charset=utf-8',
                    'download_path':
                        '/downloads/coach/payout_import_reports/payoutrework_demo_1.csv',
                    'checksum_sha256': 'sha256_demo_rework',
                    'content_length_bytes': 224,
                    'created_at': '2026-04-14T10:08:00Z',
                    'created_by_account_id': 'acct_finance_demo',
                    'note': 'failed row rework export',
                  },
                  'note': 'uploaded from coach ops console',
                },
                <String, Object?>{
                  'batch_id': 'payoutbatch_demo_2',
                  'dry_run': false,
                  'import_source': 'bank_report',
                  'report_name':
                      'coach-payout-import-rework-payoutbatch_demo_1.csv',
                  'report_format': 'csv',
                  'operator_ids': <String>['op_demo_express'],
                  'rework_of_batch_id': 'payoutbatch_demo_1',
                  'rework_origin_batch_id': 'payoutbatch_demo_1',
                  'follow_up_batch_ids': const <String>[],
                  'report_checksum_sha256': 'sha256_demo_rework',
                  'total_rows': 1,
                  'applied_rows': 1,
                  'failed_rows': 0,
                  'payout_run_ids': <String>['payoutrun_demo_failed'],
                  'failure_messages': const <String>[],
                  'created_at': '2026-04-14T11:08:00Z',
                  'created_by_account_id': 'acct_finance_demo',
                  'report_artifact': <String, Object?>{
                    'artifact_id': 'payoutreport_demo_2',
                    'batch_id': 'payoutbatch_demo_2',
                    'artifact_kind': 'source_report',
                    'import_source': 'bank_report',
                    'report_name':
                        'coach-payout-import-rework-payoutbatch_demo_1.csv',
                    'report_format': 'csv',
                    'operator_ids': <String>['op_demo_express'],
                    'file_name': 'coach-payout-import-payoutbatch_demo_2.csv',
                    'mime_type': 'text/csv; charset=utf-8',
                    'download_path':
                        '/downloads/coach/payout_import_reports/payoutreport_demo_2.csv',
                    'checksum_sha256': 'sha256_demo_rework',
                    'content_length_bytes': 144,
                    'created_at': '2026-04-14T11:08:00Z',
                    'created_by_account_id': 'acct_finance_demo',
                    'note': 'rework upload',
                  },
                  'rework_artifact': null,
                  'note': 'rework upload',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/operator/payout_runs':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(
            body['statement_ids'],
            <String>['settlement_op_demo_express_2026w15'],
          );
          expect(body['note'], 'queued by finance ops');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'payout_run_create',
              'idempotency': <String, Object?>{
                'key': 'coach-ops-payout-run-test-1',
                'scope': 'coach_operator_payout_run_create',
                'request_fingerprint': 'fp_ops_payout_run_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'payout_run': <String, Object?>{
                'payout_run_id': 'payoutrun_demo_express',
                'status': 'queued',
                'currency': 'SYP',
                'statement_ids': <String>[
                  'settlement_op_demo_express_2026w15',
                ],
                'operator_ids': <String>['op_demo_express'],
                'operator_names': <String>['Demo Express'],
                'statement_count': 1,
                'gross_minor_units': 9180,
                'reserve_minor_units': 200,
                'net_payable_minor_units': 7800,
                'created_at': '2026-04-07T15:50:00Z',
                'created_by_account_id': 'acct_finance_demo',
                'note': 'queued by finance ops',
                'available_export_formats': <String>['csv', 'datev_json'],
                'exports': const <Map<String, Object?>>[],
              },
              'next_action': 'await_external_payout_execution',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/operator/payout_runs/payoutrun_demo_express/imports':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['import_source'], 'bank_report');
          expect(body['external_status'], 'executed');
          expect(
              body['payment_reference'], 'bank_import_payoutrun_demo_express');
          expect(body['external_reference'], 'bank_file_2026w15');
          expect(
            body['note'],
            'executed import applied from coach ops console',
          );
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'payout_import_create',
              'idempotency': <String, Object?>{
                'key': 'coach-ops-payout-import-test-1',
                'scope': 'coach_operator_payout_import_create',
                'request_fingerprint': 'fp_ops_payout_import_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'payout_import': <String, Object?>{
                'import_id': 'payoutimport_demo_executed',
                'import_batch_id': null,
                'payout_run_id': 'payoutrun_demo_express',
                'import_source': 'bank_report',
                'external_status': 'executed',
                'payment_reference': 'bank_import_payoutrun_demo_express',
                'external_reference': 'bank_file_2026w15',
                'imported_at': '2026-04-14T10:06:00Z',
                'imported_by_account_id': 'acct_finance_demo',
                'previous_run_status': 'queued',
                'applied_run_status': 'paid',
                'note': 'executed import applied from coach ops console',
              },
              'payout_run': <String, Object?>{
                'payout_run_id': 'payoutrun_demo_express',
                'status': 'paid',
                'currency': 'SYP',
                'statement_ids': <String>[
                  'settlement_op_demo_express_2026w15',
                ],
                'operator_ids': <String>['op_demo_express'],
                'operator_names': <String>['Demo Express'],
                'statement_count': 1,
                'gross_minor_units': 9180,
                'reserve_minor_units': 200,
                'net_payable_minor_units': 7800,
                'created_at': '2026-04-07T15:50:00Z',
                'paid_at': '2026-04-14T10:06:00Z',
                'created_by_account_id': 'acct_finance_demo',
                'paid_by_account_id': 'acct_finance_demo',
                'payment_reference': 'bank_import_payoutrun_demo_express',
                'note': 'executed import applied from coach ops console',
                'available_export_formats': <String>['csv', 'datev_json'],
                'exports': const <Map<String, Object?>>[],
              },
              'next_action': 'reconciliation_updated',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/operator/payout_import_batches':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['import_source'], 'bank_report');
          expect(body['report_name'], 'bank_report_2026w15.csv');
          expect(body['report_format'], 'csv');
          expect(
            body['report_body'],
            'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
            'payoutrun_demo_express,executed,bank_import_payoutrun_demo_express,bank_file_2026w15,2026-04-14T10:06:00Z,executed import applied from coach ops console\n'
            'payoutrun_demo_failed,failed,,bank_file_2026w15,2026-04-14T10:07:00Z,failed import applied from coach ops console',
          );
          expect(body['note'], 'uploaded from coach ops console');
          final dryRun = body['dry_run'] == true;
          if (dryRun) {
            expect(body['rework_of_batch_id'], 'payoutbatch_demo_1');
            expect(
              body.containsKey('expected_preview_token'),
              isFalse,
            );
          } else {
            expect(body.containsKey('rework_of_batch_id'), isFalse);
            expect(
              body['expected_preview_token'],
              'previewtoken_ops_payout_import_batch_preview_1',
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'payout_import_batch_create',
              'dry_run': dryRun,
              'mutation_applied': !dryRun,
              'preview_echo': dryRun
                  ? <String, Object?>{
                      'import_source': 'bank_report',
                      'report_name': 'bank_report_2026w15.csv',
                      'report_format': 'csv',
                      'report_checksum_sha256': 'sha256_demo_report',
                      'request_fingerprint': 'fp_ops_payout_import_batch_1',
                      'preview_token':
                          'previewtoken_ops_payout_import_batch_preview_1',
                      'preview_status': 'active',
                      'expires_at': '2027-04-14T10:18:00Z',
                      'rework_of_batch_id': 'payoutbatch_demo_1',
                    }
                  : null,
              'idempotency': <String, Object?>{
                'key': 'coach-ops-payout-import-batch-test-1',
                'scope': 'coach_operator_payout_import_batch_create',
                'request_fingerprint': 'fp_ops_payout_import_batch_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'batch': <String, Object?>{
                'batch_id':
                    dryRun ? 'payoutbatchpreview_demo_1' : 'payoutbatch_demo_1',
                'dry_run': dryRun,
                'import_source': 'bank_report',
                'report_name': 'bank_report_2026w15.csv',
                'report_format': 'csv',
                'operator_ids': <String>['op_demo_express'],
                'rework_of_batch_id': dryRun ? 'payoutbatch_demo_1' : null,
                'rework_origin_batch_id': dryRun ? 'payoutbatch_demo_1' : null,
                'follow_up_batch_ids': const <String>[],
                'report_checksum_sha256': 'sha256_demo_report',
                'total_rows': 2,
                'applied_rows': 1,
                'failed_rows': 1,
                'payout_run_ids': <String>['payoutrun_demo_express'],
                'failure_messages': <String>[
                  'line 3 (payoutrun_demo_failed): not found',
                ],
                'created_at': '2026-04-14T10:08:00Z',
                'created_by_account_id': 'acct_finance_demo',
                'report_artifact': dryRun
                    ? null
                    : <String, Object?>{
                        'artifact_id': 'payoutreport_demo_1',
                        'batch_id': 'payoutbatch_demo_1',
                        'artifact_kind': 'source_report',
                        'import_source': 'bank_report',
                        'report_name': 'bank_report_2026w15.csv',
                        'report_format': 'csv',
                        'operator_ids': <String>['op_demo_express'],
                        'file_name':
                            'coach-payout-import-payoutbatch_demo_1.csv',
                        'mime_type': 'text/csv; charset=utf-8',
                        'download_path':
                            '/downloads/coach/payout_import_reports/payoutreport_demo_1.csv',
                        'checksum_sha256': 'sha256_demo_report',
                        'content_length_bytes': 182,
                        'created_at': '2026-04-14T10:08:00Z',
                        'created_by_account_id': 'acct_finance_demo',
                        'note': 'uploaded from coach ops console',
                      },
                'rework_artifact': dryRun
                    ? null
                    : <String, Object?>{
                        'artifact_id': 'payoutrework_demo_1',
                        'batch_id': 'payoutbatch_demo_1',
                        'artifact_kind': 'failed_row_rework',
                        'import_source': 'bank_report',
                        'report_name':
                            'bank_report_2026w15.csv (failed row rework)',
                        'report_format': 'csv',
                        'operator_ids': <String>['op_demo_express'],
                        'file_name':
                            'coach-payout-import-rework-payoutbatch_demo_1.csv',
                        'mime_type': 'text/csv; charset=utf-8',
                        'download_path':
                            '/downloads/coach/payout_import_reports/payoutrework_demo_1.csv',
                        'checksum_sha256': 'sha256_demo_rework',
                        'content_length_bytes': 224,
                        'created_at': '2026-04-14T10:08:00Z',
                        'created_by_account_id': 'acct_finance_demo',
                        'note': 'failed row rework export',
                      },
                'note': 'uploaded from coach ops console',
              },
              'imports': <Map<String, Object?>>[
                <String, Object?>{
                  'import_id': dryRun
                      ? 'payoutimport_preview_executed'
                      : 'payoutimport_demo_executed',
                  'import_batch_id': dryRun
                      ? 'payoutbatchpreview_demo_1'
                      : 'payoutbatch_demo_1',
                  'payout_run_id': 'payoutrun_demo_express',
                  'import_source': 'bank_report',
                  'external_status': 'executed',
                  'payment_reference': 'bank_import_payoutrun_demo_express',
                  'external_reference': 'bank_file_2026w15',
                  'imported_at': '2026-04-14T10:06:00Z',
                  'imported_by_account_id': 'acct_finance_demo',
                  'previous_run_status': 'queued',
                  'applied_run_status': 'paid',
                  'note': 'executed import applied from coach ops console',
                },
              ],
              'failed_rows': <Map<String, Object?>>[
                <String, Object?>{
                  'line_number': 3,
                  'payout_run_id': 'payoutrun_demo_failed',
                  'detail': 'not found',
                },
              ],
              'next_action':
                  dryRun ? 'review_failed_rows' : 'review_failed_rows',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/operator/payout_runs/payoutrun_demo_express/mark_paid':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['payment_reference'], 'payout_batch_2026w15');
          expect(body['note'], 'settled in weekly payout');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'payout_run_mark_paid',
              'idempotency': <String, Object?>{
                'key': 'coach-ops-payout-run-paid-test-1',
                'scope': 'coach_operator_payout_run_mark_paid',
                'request_fingerprint': 'fp_ops_payout_run_paid_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'payout_run': <String, Object?>{
                'payout_run_id': 'payoutrun_demo_express',
                'status': 'paid',
                'currency': 'SYP',
                'statement_ids': <String>[
                  'settlement_op_demo_express_2026w15',
                ],
                'operator_ids': <String>['op_demo_express'],
                'operator_names': <String>['Demo Express'],
                'statement_count': 1,
                'gross_minor_units': 9180,
                'reserve_minor_units': 200,
                'net_payable_minor_units': 7800,
                'created_at': '2026-04-07T15:50:00Z',
                'paid_at': '2026-04-14T10:05:00Z',
                'created_by_account_id': 'acct_finance_demo',
                'paid_by_account_id': 'acct_finance_demo',
                'payment_reference': 'payout_batch_2026w15',
                'note': 'settled in weekly payout',
                'available_export_formats': <String>['csv', 'datev_json'],
                'exports': const <Map<String, Object?>>[],
              },
              'next_action': 'statement_exports_ready',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/operator/payout_runs/payoutrun_demo_express/exports':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['export_format'], 'csv');
          expect(body['note'], 'prepare weekly CSV');
          return http.Response(
            jsonEncode(<String, Object?>{
              'command': 'payout_run_export_create',
              'idempotency': <String, Object?>{
                'key': 'coach-ops-payout-run-export-test-1',
                'scope': 'coach_operator_payout_run_export_create',
                'request_fingerprint': 'fp_ops_payout_run_export_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'export': <String, Object?>{
                'export_id': 'export_payoutrun_demo_express_csv',
                'payout_run_id': 'payoutrun_demo_express',
                'export_format': 'csv',
                'status': 'ready',
                'file_name': 'coach-settlement-payoutrun_demo_express.csv',
                'mime_type': 'text/csv; charset=utf-8',
                'download_path':
                    '/downloads/coach/settlement_exports/export_payoutrun_demo_express_csv.csv',
                'checksum_sha256': 'sha256_demo_csv',
                'content_length_bytes': 182,
                'created_at': '2026-04-14T10:15:00Z',
                'created_by_account_id': 'acct_finance_demo',
                'statement_ids': <String>[
                  'settlement_op_demo_express_2026w15',
                ],
                'operator_ids': <String>['op_demo_express'],
                'note': 'prepare weekly CSV',
              },
              'next_action': 'download_ready',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/operator/refund_requests/refundreq_demo_credit/review':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['decision'], 'approve');
          expect(body['note'], 'approved by finance ops');
          return http.Response(
            jsonEncode(<String, Object?>{
              'idempotency': <String, Object?>{
                'key': 'coach-ops-refund-review-test-1',
                'scope': 'coach_operator_refund_review',
                'request_fingerprint': 'fp_ops_refund_review_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'request': <String, Object?>{
                'refund_request_id': 'refundreq_demo_credit',
                'booking_id': 'booking_demo_express_direct',
                'journey_id': 'journey_demo_express_direct',
                'operator_name': 'Demo Express',
                'from': 'Damascus',
                'to': 'Aleppo',
                'departure_at': '2026-04-08T08:00:00Z',
                'arrival_at': '2026-04-08T12:30:00Z',
                'booking_state': 'refund_requested',
                'request_status': 'requested',
                'selected_kind': 'refund_credit',
                'currency': 'SYP',
                'requested_minor_units': 9180,
                'fee_minor_units': 0,
                'ticket_ids': <String>['ticket_demo_1', 'ticket_demo_2'],
                'reason': 'customer changed plans',
                'requested_at': '2026-04-07T13:00:00Z',
                'queue_status': 'approved',
                'urgency': 'medium',
                'suggested_action': 'Customer notification is queued.',
                'reviewed_at': '2026-04-07T14:15:00Z',
                'reviewed_by_account_id': 'acct_ops_demo',
                'review_note': 'approved by finance ops',
              },
              'settlement_effect': <String, Object?>{
                'kind': 'travel_credit_liability',
                'currency': 'SYP',
                'amount_minor_units': 9180,
              },
              'next_action': 'customer_notification_queued',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/operator/change_requests/changereq_demo_midday/review':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['decision'], 'reject');
          expect(body['note'], 'seat map conflict');
          return http.Response(
            jsonEncode(<String, Object?>{
              'idempotency': <String, Object?>{
                'key': 'coach-ops-change-review-test-1',
                'scope': 'coach_operator_change_review',
                'request_fingerprint': 'fp_ops_change_review_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'request': <String, Object?>{
                'change_request_id': 'changereq_demo_midday',
                'booking_id': 'booking_demo_express_direct',
                'journey_id': 'journey_demo_express_direct',
                'operator_name': 'Demo Express',
                'from': 'Damascus',
                'to': 'Aleppo',
                'departure_at': '2026-04-08T08:00:00Z',
                'arrival_at': '2026-04-08T12:30:00Z',
                'booking_state': 'ticketed',
                'request_status': 'requested',
                'target_offer_id': 'offer_demo_express_midday',
                'target_journey_id': 'journey_demo_express_midday',
                'currency': 'SYP',
                'fare_difference_minor_units': 800,
                'change_fee_minor_units': 500,
                'total_due_minor_units': 1300,
                'reason': 'move to midday departure',
                'requested_at': '2026-04-07T13:05:00Z',
                'queue_status': 'rejected',
                'urgency': 'high',
                'suggested_action':
                    'Keep the original ticket active and notify support.',
                'reviewed_at': '2026-04-07T14:20:00Z',
                'reviewed_by_account_id': 'acct_ops_demo',
                'review_note': 'seat map conflict',
              },
              'next_action': 'keep_original_booking',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final refundQueue = await api.operatorRefundQueue(limit: 8);
    final changeQueue = await api.operatorChangeQueue(limit: 8);
    final reconciliation = await api.operatorReconciliation(limit: 6);
    final settlementStatements =
        await api.operatorSettlementStatements(limit: 4);
    final olderSettlementStatements = await api.operatorSettlementStatements(
      limit: 4,
      cursor: '2026-04-13T23:59:59Z|settlement_op_demo_express_2026w15',
    );
    final payoutRuns = await api.operatorPayoutRuns(limit: 5);
    final olderPayoutRuns = await api.operatorPayoutRuns(
      limit: 5,
      cursor: '2026-04-07T15:50:00Z|payoutrun_demo_express',
    );
    final payoutReconciliation =
        await api.operatorPayoutReconciliation(limit: 5);
    final olderPayoutReconciliation = await api.operatorPayoutReconciliation(
      limit: 5,
      cursor: '2026-04-14T10:04:00Z|payoutrun_demo_partial',
    );
    final payoutImports = await api.operatorPayoutImports(limit: 4);
    final olderPayoutImports = await api.operatorPayoutImports(
      limit: 4,
      cursor: '2026-04-14T10:06:00Z|payoutimport_demo_executed',
    );
    final payoutImportPreviews =
        await api.operatorPayoutImportPreviews(limit: 4);
    final filteredPayoutImportPreviews = await api.operatorPayoutImportPreviews(
      limit: 4,
      status: 'invalidated',
      fromCreatedAtIso: '2026-04-14T00:00:00Z',
      toCreatedAtIso: '2026-04-14T23:59:59Z',
    );
    final olderPayoutImportPreviews = await api.operatorPayoutImportPreviews(
      limit: 4,
      cursor: '2026-04-14T09:08:00Z|previewtoken_demo_consumed',
    );
    final invalidatedPreview = await api.invalidateOperatorPayoutImportPreview(
      previewToken: 'previewtoken_demo_active',
      idempotencyKey: 'coach-ops-payout-preview-invalidate-test-1',
    );
    final payoutImportProfiles = await api.operatorPayoutImportProfiles();
    final payoutImportBatches = await api.operatorPayoutImportBatches(limit: 4);
    final olderPayoutImportBatches = await api.operatorPayoutImportBatches(
      limit: 4,
      cursor: '2026-04-14T10:08:00Z|payoutbatch_demo_1',
    );
    final payoutRun = await api.createOperatorPayoutRun(
      statementIds: const <String>['settlement_op_demo_express_2026w15'],
      note: 'queued by finance ops',
      idempotencyKey: 'coach-ops-payout-run-test-1',
    );
    final payoutImport = await api.createOperatorPayoutImport(
      payoutRunId: 'payoutrun_demo_express',
      importSource: 'bank_report',
      externalStatus: 'executed',
      paymentReference: 'bank_import_payoutrun_demo_express',
      externalReference: 'bank_file_2026w15',
      note: 'executed import applied from coach ops console',
      idempotencyKey: 'coach-ops-payout-import-test-1',
    );
    final payoutImportBatch = await api.createOperatorPayoutImportBatch(
      importSource: 'bank_report',
      reportName: 'bank_report_2026w15.csv',
      reportBody:
          'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
          'payoutrun_demo_express,executed,bank_import_payoutrun_demo_express,bank_file_2026w15,2026-04-14T10:06:00Z,executed import applied from coach ops console\n'
          'payoutrun_demo_failed,failed,,bank_file_2026w15,2026-04-14T10:07:00Z,failed import applied from coach ops console',
      expectedPreviewToken: 'previewtoken_ops_payout_import_batch_preview_1',
      note: 'uploaded from coach ops console',
      idempotencyKey: 'coach-ops-payout-import-batch-test-1',
    );
    final payoutImportBatchPreview = await api.createOperatorPayoutImportBatch(
      importSource: 'bank_report',
      reportName: 'bank_report_2026w15.csv',
      reportBody:
          'payout_run_id,external_status,payment_reference,external_reference,imported_at,note\n'
          'payoutrun_demo_express,executed,bank_import_payoutrun_demo_express,bank_file_2026w15,2026-04-14T10:06:00Z,executed import applied from coach ops console\n'
          'payoutrun_demo_failed,failed,,bank_file_2026w15,2026-04-14T10:07:00Z,failed import applied from coach ops console',
      dryRun: true,
      reworkOfBatchId: 'payoutbatch_demo_1',
      note: 'uploaded from coach ops console',
      idempotencyKey: 'coach-ops-payout-import-batch-preview-test-1',
    );
    final paidPayoutRun = await api.markOperatorPayoutRunPaid(
      payoutRunId: 'payoutrun_demo_express',
      paymentReference: 'payout_batch_2026w15',
      note: 'settled in weekly payout',
      idempotencyKey: 'coach-ops-payout-run-paid-test-1',
    );
    final payoutExport = await api.createOperatorPayoutRunExport(
      payoutRunId: 'payoutrun_demo_express',
      exportFormat: 'csv',
      note: 'prepare weekly CSV',
      idempotencyKey: 'coach-ops-payout-run-export-test-1',
    );
    final refundReview = await api.reviewRefundRequest(
      refundRequestId: 'refundreq_demo_credit',
      approve: true,
      note: 'approved by finance ops',
      idempotencyKey: 'coach-ops-refund-review-test-1',
    );
    final changeReview = await api.reviewChangeRequest(
      changeRequestId: 'changereq_demo_midday',
      approve: false,
      note: 'seat map conflict',
      idempotencyKey: 'coach-ops-change-review-test-1',
    );

    expect(refundQueue.totals.cashRequests, 1);
    expect(
      refundQueue.requests.single.queueStatus,
      CoachOpsQueueStatus.pendingReview,
    );
    expect(changeQueue.requests.single.urgency, CoachOpsRequestUrgency.high);
    expect(reconciliation.summary.reviewedRequests, 2);
    expect(
      reconciliation.tripSnapshots.single.recentEvents.single.scanStatus,
      CoachBoardingScanStatus.duplicate,
    );
    expect(
      reconciliation.reviewHistory.single.requestKind,
      CoachOpsRequestKind.refundRequest,
    );
    expect(settlementStatements.generatedAtIso, '2026-04-07T15:35:00Z');
    expect(
      settlementStatements.statements.single.lines.single.basis,
      CoachSettlementBasis.boarded,
    );
    expect(
      settlementStatements.statements.single.totals.netPayableMinorUnits,
      7800,
    );
    expect(
      settlementStatements.nextCursor,
      '2026-04-13T23:59:59Z|settlement_op_demo_express_2026w15',
    );
    expect(olderSettlementStatements.statements, hasLength(1));
    expect(
      olderSettlementStatements.statements.single.statementId,
      'settlement_op_border_runner_2026w14',
    );
    expect(olderSettlementStatements.nextCursor, isNull);
    expect(payoutRuns.summary.queuedRuns, 1);
    expect(payoutRuns.runs.single.isQueued, isTrue);
    expect(payoutRuns.runs.single.availableExportFormats, <String>[
      'csv',
      'datev_json',
    ]);
    expect(
      payoutRuns.nextCursor,
      '2026-04-07T15:50:00Z|payoutrun_demo_express',
    );
    expect(olderPayoutRuns.runs, hasLength(1));
    expect(olderPayoutRuns.runs.single.payoutRunId, 'payoutrun_demo_older');
    expect(olderPayoutRuns.nextCursor, isNull);
    expect(payoutReconciliation.summary.balancedRuns, 1);
    expect(payoutReconciliation.summary.partialExportRuns, 1);
    expect(payoutReconciliation.summary.queuedRuns, 1);
    expect(
      payoutReconciliation.runs.last.missingExportFormats,
      <String>['datev_json'],
    );
    expect(payoutReconciliation.runs.last.needsAttention, isTrue);
    expect(
      payoutReconciliation.nextCursor,
      '2026-04-14T10:04:00Z|payoutrun_demo_partial',
    );
    expect(olderPayoutReconciliation.runs, hasLength(1));
    expect(
      olderPayoutReconciliation.runs.single.payoutRunId,
      'payoutrun_demo_queued',
    );
    expect(
      olderPayoutReconciliation.runs.single.reconciliationStatus,
      'awaiting_bank_execution',
    );
    expect(olderPayoutReconciliation.nextCursor, isNull);
    expect(payoutImports.summary.totalImports, 3);
    expect(payoutImports.summary.failedImports, 1);
    expect(payoutImports.imports.first.externalStatus, 'executed');
    expect(payoutImports.imports.first.importBatchId, 'payoutbatch_demo_1');
    expect(
      payoutImports.nextCursor,
      '2026-04-14T10:06:00Z|payoutimport_demo_executed',
    );
    expect(olderPayoutImports.imports, hasLength(1));
    expect(
      olderPayoutImports.imports.single.importId,
      'payoutimport_demo_older',
    );
    expect(olderPayoutImports.nextCursor, isNull);
    expect(payoutImportPreviews.summary.totalPreviews, 3);
    expect(payoutImportPreviews.summary.activePreviews, 1);
    expect(payoutImportPreviews.summary.invalidatedPreviews, 0);
    expect(payoutImportPreviews.previews.first.previewStatus, 'active');
    expect(
      payoutImportPreviews.previews.first.operatorIds,
      <String>['op_demo_express'],
    );
    expect(payoutImportPreviews.previews.first.usableNow, isTrue);
    expect(
      payoutImportPreviews.nextCursor,
      '2026-04-14T09:08:00Z|previewtoken_demo_consumed',
    );
    expect(
      payoutImportPreviews.previews.first.reworkOfBatchId,
      'payoutbatch_demo_1',
    );
    expect(filteredPayoutImportPreviews.summary.totalPreviews, 1);
    expect(filteredPayoutImportPreviews.summary.invalidatedPreviews, 1);
    expect(filteredPayoutImportPreviews.nextCursor, isNull);
    expect(
      filteredPayoutImportPreviews.previews.single.previewStatus,
      'invalidated',
    );
    expect(
      filteredPayoutImportPreviews.previews.single.invalidatedAtIso,
      '2026-04-14T10:09:00Z',
    );
    expect(olderPayoutImportPreviews.summary.totalPreviews, 3);
    expect(olderPayoutImportPreviews.previews.single.previewStatus, 'expired');
    expect(
      olderPayoutImportPreviews.previews.single.operatorIds,
      <String>['op_border_runner'],
    );
    expect(olderPayoutImportPreviews.nextCursor, isNull);
    expect(invalidatedPreview.preview.previewStatus, 'invalidated');
    expect(
      invalidatedPreview.preview.operatorIds,
      <String>['op_demo_express'],
    );
    expect(invalidatedPreview.preview.invalidatedAtIso, '2026-04-14T10:09:00Z');
    expect(invalidatedPreview.preview.usableNow, isFalse);
    expect(invalidatedPreview.nextAction, 'preview_invalidated');
    expect(payoutImportProfiles.profiles.first.importSource, 'bank_report');
    expect(
      payoutImportProfiles.profiles.first.supportedDelimiters,
      <String>['comma', 'semicolon'],
    );
    expect(
      payoutImportProfiles.profiles.first.statusMappings[1].normalizedStatus,
      'executed',
    );
    expect(
      payoutImportProfiles.profiles.first.statusMappings[1].acceptedValues,
      <String>['executed', 'completed', 'paid'],
    );
    expect(
      payoutImportProfiles.profiles.first.statusMappings[1].requiredFields,
      <String>['payment_reference'],
    );
    expect(
      payoutImportProfiles.profiles[1].statusMappings[1].requiredFields,
      <String>['payment_reference', 'external_reference'],
    );
    expect(
      payoutImportProfiles.profiles.last.fields.first.acceptedHeaders,
      <String>['external_status', 'psp_status', 'transfer_status', 'status'],
    );
    expect(payoutImportBatches.summary.totalBatches, 3);
    expect(payoutImportBatches.summary.totalRows, 4);
    expect(payoutImportBatches.batches.first.failedRows, 1);
    expect(payoutImportBatches.batches.first.dryRun, isFalse);
    expect(
      payoutImportBatches.batches.first.operatorIds,
      <String>['op_demo_express'],
    );
    expect(
      payoutImportBatches.nextCursor,
      '2026-04-14T10:08:00Z|payoutbatch_demo_1',
    );
    expect(
      payoutImportBatches.batches.first.reportArtifact?.downloadPath,
      '/downloads/coach/payout_import_reports/payoutreport_demo_1.csv',
    );
    expect(
      payoutImportBatches.batches.first.reportArtifact?.artifactKind,
      'source_report',
    );
    expect(
      payoutImportBatches.batches.first.reportArtifact?.operatorIds,
      <String>['op_demo_express'],
    );
    expect(
      payoutImportBatches.batches.first.reworkArtifact?.downloadPath,
      '/downloads/coach/payout_import_reports/payoutrework_demo_1.csv',
    );
    expect(
      payoutImportBatches.batches.first.reworkArtifact?.operatorIds,
      <String>['op_demo_express'],
    );
    expect(
      payoutImportBatches.batches.first.followUpBatchIds,
      <String>['payoutbatch_demo_2'],
    );
    expect(
      payoutImportBatches.batches.last.reworkOfBatchId,
      'payoutbatch_demo_1',
    );
    expect(olderPayoutImportBatches.batches, hasLength(1));
    expect(
      olderPayoutImportBatches.batches.single.batchId,
      'payoutbatch_demo_older',
    );
    expect(
      olderPayoutImportBatches.batches.single.operatorIds,
      <String>['op_border_runner'],
    );
    expect(olderPayoutImportBatches.nextCursor, isNull);
    expect(payoutImport.payoutImport.appliedRunStatus, 'paid');
    expect(
      payoutImport.payoutRun.paymentReference,
      'bank_import_payoutrun_demo_express',
    );
    expect(payoutImportBatch.batch.reportName, 'bank_report_2026w15.csv');
    expect(payoutImportBatch.dryRun, isFalse);
    expect(
      payoutImportBatch.batch.operatorIds,
      <String>['op_demo_express'],
    );
    expect(
      payoutImportBatch.batch.reportArtifact?.fileName,
      'coach-payout-import-payoutbatch_demo_1.csv',
    );
    expect(
      payoutImportBatch.batch.reportArtifact?.operatorIds,
      <String>['op_demo_express'],
    );
    expect(
      payoutImportBatch.batch.reworkArtifact?.fileName,
      'coach-payout-import-rework-payoutbatch_demo_1.csv',
    );
    expect(
      payoutImportBatch.batch.reworkArtifact?.operatorIds,
      <String>['op_demo_express'],
    );
    expect(
        payoutImportBatch.imports.single.importBatchId, 'payoutbatch_demo_1');
    expect(payoutImportBatch.failedRows.single.lineNumber, 3);
    expect(payoutImportBatchPreview.dryRun, isTrue);
    expect(payoutImportBatchPreview.mutationApplied, isFalse);
    expect(
      payoutImportBatchPreview.batch.operatorIds,
      <String>['op_demo_express'],
    );
    expect(payoutImportBatchPreview.batch.reportArtifact, isNull);
    expect(payoutImportBatchPreview.batch.reworkArtifact, isNull);
    expect(
      payoutImportBatchPreview.batch.reworkOfBatchId,
      'payoutbatch_demo_1',
    );
    expect(payoutImportBatchPreview.previewEcho, isNotNull);
    expect(
      payoutImportBatchPreview.previewEcho?.reportChecksumSha256,
      'sha256_demo_report',
    );
    expect(
      payoutImportBatchPreview.previewEcho?.requestFingerprint,
      'fp_ops_payout_import_batch_1',
    );
    expect(
      payoutImportBatchPreview.previewEcho?.previewToken,
      'previewtoken_ops_payout_import_batch_preview_1',
    );
    expect(payoutImportBatchPreview.previewEcho?.previewStatus, 'active');
    expect(
      payoutImportBatchPreview.previewEcho?.expiresAtIso,
      '2027-04-14T10:18:00Z',
    );
    expect(
      payoutImportBatchPreview.previewEcho?.reworkOfBatchId,
      'payoutbatch_demo_1',
    );
    expect(
      payoutImportBatchPreview.batch.reworkOriginBatchId,
      'payoutbatch_demo_1',
    );
    expect(payoutImportBatchPreview.batch.followUpBatchIds, isEmpty);
    expect(
      payoutImportBatchPreview.batch.batchId,
      'payoutbatchpreview_demo_1',
    );
    expect(payoutRun.payoutRun.statementIds.single,
        'settlement_op_demo_express_2026w15');
    expect(paidPayoutRun.payoutRun.isPaid, isTrue);
    expect(paidPayoutRun.payoutRun.paymentReference, 'payout_batch_2026w15');
    expect(payoutExport.export.exportFormat, 'csv');
    expect(payoutExport.export.downloadPath,
        '/downloads/coach/settlement_exports/export_payoutrun_demo_express_csv.csv');
    expect(
      api.resolvePayoutExportUri(payoutExport.export.downloadPath)?.toString(),
      'https://api.shamell.online/downloads/coach/settlement_exports/export_payoutrun_demo_express_csv.csv',
    );
    expect(
      api
          .resolvePayoutImportReportUri(
            '/downloads/coach/payout_import_reports/payoutreport_demo_1.csv',
          )
          ?.toString(),
      'https://api.shamell.online/downloads/coach/payout_import_reports/payoutreport_demo_1.csv',
    );
    expect(refundReview.request.queueStatus, CoachOpsQueueStatus.approved);
    expect(refundReview.settlementEffect?.amountMinorUnits, 9180);
    expect(changeReview.request.queueStatus, CoachOpsQueueStatus.rejected);
    expect(changeReview.nextAction, 'keep_original_booking');
  });

  test('operator payout import batch upload sends multipart file payload',
      () async {
    late http.BaseRequest capturedRequest;
    final client = _StreamingClient((request) async {
      capturedRequest = request;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_batches/upload',
      );
      expect(
        request.headers['Idempotency-Key'],
        'coach-ops-payout-import-batch-upload-test-1',
      );
      expect(
        request.headers['cookie']?.toLowerCase(),
        '__host-sa_session=0123456789abcdef0123456789abcdef',
      );
      expect(request, isA<http.MultipartRequest>());
      final multipart = request as http.MultipartRequest;
      expect(multipart.fields['import_source'], 'bank_report');
      expect(multipart.fields['report_name'], 'bank_report_uploaded.csv');
      expect(multipart.fields['report_format'], 'csv');
      expect(multipart.fields['rework_of_batch_id'], 'payoutbatch_demo_1');
      expect(multipart.fields['dry_run'], 'true');
      expect(multipart.fields['note'], 'uploaded from file');
      expect(multipart.files, hasLength(1));
      expect(multipart.files.single.field, 'file');
      expect(multipart.files.single.filename, 'bank_report_uploaded.csv');
      expect(
        multipart.files.single.length,
        utf8
            .encode(
              'payout_run_id,external_status\n'
              'payoutrun_demo_express,executed\n',
            )
            .length,
      );
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'command': 'payout_import_batch_create',
              'dry_run': true,
              'mutation_applied': false,
              'preview_echo': <String, Object?>{
                'import_source': 'bank_report',
                'report_name': 'bank_report_uploaded.csv',
                'report_format': 'csv',
                'report_checksum_sha256': 'sha256_demo_report',
                'request_fingerprint': 'fp_ops_payout_import_batch_upload_1',
                'preview_token':
                    'previewtoken_ops_payout_import_batch_upload_1',
                'preview_status': 'active',
                'expires_at': '2027-04-14T10:18:00Z',
                'rework_of_batch_id': 'payoutbatch_demo_1',
              },
              'idempotency': <String, Object?>{
                'key': 'coach-ops-payout-import-batch-upload-test-1',
                'scope': 'coach_operator_payout_import_batch_create',
                'request_fingerprint': 'fp_ops_payout_import_batch_upload_1',
                'replayed': false,
                'derived_keys': const <String, String>{},
              },
              'batch': <String, Object?>{
                'batch_id': 'payoutbatchpreview_demo_upload',
                'dry_run': true,
                'import_source': 'bank_report',
                'report_name': 'bank_report_uploaded.csv',
                'report_format': 'csv',
                'operator_ids': <String>['op_demo_express'],
                'rework_of_batch_id': 'payoutbatch_demo_1',
                'rework_origin_batch_id': 'payoutbatch_demo_1',
                'follow_up_batch_ids': const <String>[],
                'report_checksum_sha256': 'sha256_demo_report',
                'total_rows': 1,
                'applied_rows': 1,
                'failed_rows': 0,
                'payout_run_ids': <String>['payoutrun_demo_express'],
                'failure_messages': const <String>[],
                'created_at': '2026-04-14T10:08:00Z',
                'created_by_account_id': 'acct_finance_demo',
                'report_artifact': null,
                'rework_artifact': null,
                'note': 'uploaded from file',
              },
              'imports': <Map<String, Object?>>[
                <String, Object?>{
                  'import_id': 'payoutimport_preview_executed',
                  'import_batch_id': 'payoutbatchpreview_demo_upload',
                  'payout_run_id': 'payoutrun_demo_express',
                  'import_source': 'bank_report',
                  'external_status': 'executed',
                  'payment_reference': null,
                  'external_reference': null,
                  'imported_at': '2026-04-14T10:06:00Z',
                  'imported_by_account_id': 'acct_finance_demo',
                  'previous_run_status': 'queued',
                  'applied_run_status': 'paid',
                  'note': 'uploaded from file',
                },
              ],
              'failed_rows': const <Map<String, Object?>>[],
              'next_action': 'apply_ready',
            }),
          ),
        ),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
        request: request,
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final result = await api.uploadOperatorPayoutImportBatchFile(
      importSource: 'bank_report',
      reportName: 'bank_report_uploaded.csv',
      fileName: 'bank_report_uploaded.csv',
      fileBytes: Uint8List.fromList(
        utf8.encode(
          'payout_run_id,external_status\n'
          'payoutrun_demo_express,executed\n',
        ),
      ),
      reworkOfBatchId: 'payoutbatch_demo_1',
      dryRun: true,
      note: 'uploaded from file',
      idempotencyKey: 'coach-ops-payout-import-batch-upload-test-1',
    );

    expect(capturedRequest, isA<http.MultipartRequest>());
    expect(result.dryRun, isTrue);
    expect(result.batch.reportName, 'bank_report_uploaded.csv');
    expect(result.batch.operatorIds, <String>['op_demo_express']);
    expect(result.batch.reworkOfBatchId, 'payoutbatch_demo_1');
    expect(result.batch.followUpBatchIds, isEmpty);
    expect(result.batch.totalRows, 1);
    expect(result.previewEcho, isNotNull);
    expect(result.previewEcho?.reportName, 'bank_report_uploaded.csv');
    expect(
      result.previewEcho?.requestFingerprint,
      'fp_ops_payout_import_batch_upload_1',
    );
    expect(
      result.previewEcho?.previewToken,
      'previewtoken_ops_payout_import_batch_upload_1',
    );
    expect(result.previewEcho?.previewStatus, 'active');
    expect(result.previewEcho?.expiresAtIso, '2027-04-14T10:18:00Z');
  });

  test('operatorPayoutImportBatchSavedViews parses saved views', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_batch_saved_views',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:00:00Z',
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'payoutimportbatchview_demo_express',
              'account_id': 'acct_finance_demo',
              'name': 'Demo Express batches',
              'visibility_scope': 'shared_ops',
              'operator_id': 'op_demo_express',
              'is_favorite': true,
              'last_used_at': '2026-04-15T09:58:00Z',
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-15T09:55:00Z',
              'updated_at': '2026-04-15T09:56:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorPayoutImportBatchSavedViews();

    expect(savedViews, hasLength(1));
    expect(savedViews.single.viewId, 'payoutimportbatchview_demo_express');
    expect(savedViews.single.accountId, 'acct_finance_demo');
    expect(savedViews.single.name, 'Demo Express batches');
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.preferences.operatorId, 'op_demo_express');
    expect(savedViews.single.isFavorite, isTrue);
    expect(savedViews.single.lastUsedAtIso, '2026-04-15T09:58:00Z');
    expect(savedViews.single.isDefault, isFalse);
    expect(savedViews.single.canManage, isFalse);
  });

  test('operatorPayoutImportBatchSavedViewOwners parses shared owner summaries',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_batch_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:00:00Z',
          'saved_views': const <Object?>[],
          'shared_owner_summaries': <Object?>[
            <String, Object?>{
              'account_id': 'acct_finance_shared',
              'shared_view_count': 2,
            },
            <String, Object?>{
              'account_id': 'acct_finance_other',
              'shared_view_count': 1,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final owners = await api.operatorPayoutImportBatchSavedViewOwners();

    expect(owners, hasLength(2));
    expect(owners.first.accountId, 'acct_finance_shared');
    expect(owners.first.sharedViewCount, 2);
    expect(owners.last.accountId, 'acct_finance_other');
  });

  test(
      'operatorPayoutImportBatchSavedViewOperators parses shared operator summaries',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_batch_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:00:00Z',
          'saved_views': const <Object?>[],
          'shared_operator_summaries': <Object?>[
            <String, Object?>{
              'operator_id': 'op_demo_express',
              'operator_name': 'Demo Express',
              'shared_view_count': 2,
            },
            <String, Object?>{
              'operator_id': 'op_border_runner',
              'operator_name': 'Border Runner',
              'shared_view_count': 1,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final operators = await api.operatorPayoutImportBatchSavedViewOperators();

    expect(operators, hasLength(2));
    expect(operators.first.operatorId, 'op_demo_express');
    expect(operators.first.operatorName, 'Demo Express');
    expect(operators.first.sharedViewCount, 2);
    expect(operators.last.operatorId, 'op_border_runner');
    expect(operators.last.operatorName, 'Border Runner');
  });

  test('operatorPayoutImportPreviewSavedViews parses saved views', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_preview_saved_views',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:00:00Z',
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'previewhistoryview_demo_invalidated',
              'account_id': 'acct_finance_demo',
              'name': 'Invalidated day',
              'visibility_scope': 'shared_ops',
              'status': 'invalidated',
              'from_created_at': '2026-04-14T00:00:00Z',
              'to_created_at': '2026-04-14T23:59:59Z',
              'operator_id': 'op_demo_express',
              'is_favorite': true,
              'last_used_at': '2026-04-15T09:57:00Z',
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-15T09:55:00Z',
              'updated_at': '2026-04-15T09:56:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.operatorPayoutImportPreviewSavedViews();

    expect(savedViews, hasLength(1));
    expect(savedViews.single.viewId, 'previewhistoryview_demo_invalidated');
    expect(savedViews.single.accountId, 'acct_finance_demo');
    expect(savedViews.single.name, 'Invalidated day');
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.preferences.status, 'invalidated');
    expect(
        savedViews.single.preferences.fromCreatedAtIso, '2026-04-14T00:00:00Z');
    expect(
        savedViews.single.preferences.toCreatedAtIso, '2026-04-14T23:59:59Z');
    expect(savedViews.single.preferences.operatorId, 'op_demo_express');
    expect(savedViews.single.isFavorite, isTrue);
    expect(savedViews.single.lastUsedAtIso, '2026-04-15T09:57:00Z');
    expect(savedViews.single.isDefault, isFalse);
    expect(savedViews.single.canManage, isFalse);
  });

  test(
      'operatorPayoutImportPreviewSavedViewOwners parses shared owner summaries',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_preview_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:00:00Z',
          'saved_views': const <Object?>[],
          'shared_owner_summaries': <Object?>[
            <String, Object?>{
              'account_id': 'acct_finance_shared',
              'shared_view_count': 3,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final owners = await api.operatorPayoutImportPreviewSavedViewOwners();

    expect(owners, hasLength(1));
    expect(owners.single.accountId, 'acct_finance_shared');
    expect(owners.single.sharedViewCount, 3);
  });

  test(
      'operatorPayoutImportPreviewSavedViewOperators parses shared operator summaries',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_preview_saved_views',
      );
      expect(request.url.queryParameters['visibility_scope'], 'shared_ops');
      return http.Response(
        jsonEncode(<String, Object?>{
          'generated_at': '2026-04-15T10:00:00Z',
          'saved_views': const <Object?>[],
          'shared_operator_summaries': <Object?>[
            <String, Object?>{
              'operator_id': 'op_demo_express',
              'operator_name': 'Demo Express',
              'shared_view_count': 3,
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final operators = await api.operatorPayoutImportPreviewSavedViewOperators();

    expect(operators, hasLength(1));
    expect(operators.single.operatorId, 'op_demo_express');
    expect(operators.single.operatorName, 'Demo Express');
    expect(operators.single.sharedViewCount, 3);
  });

  test('upsertOperatorPayoutImportPreviewSavedView posts mutation payload',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_preview_saved_views',
      );
      expect(
        request.headers['Idempotency-Key'],
        'coach-ops-payout-import-preview-saved-view-test-1',
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['view_id'], 'previewhistoryview_demo_invalidated');
      expect(body['name'], 'Invalidated day');
      expect(body['status'], 'invalidated');
      expect(body['from_created_at'], '2026-04-14T00:00:00Z');
      expect(body['to_created_at'], '2026-04-14T23:59:59Z');
      expect(body['operator_id'], 'op_demo_express');
      expect(body['visibility_scope'], 'shared_ops');
      expect(body['is_default'], isTrue);
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'payout_import_preview_saved_view_upsert',
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'previewhistoryview_demo_invalidated',
              'account_id': 'acct_finance_demo',
              'name': 'Invalidated day',
              'visibility_scope': 'shared_ops',
              'status': 'invalidated',
              'from_created_at': '2026-04-14T00:00:00Z',
              'to_created_at': '2026-04-14T23:59:59Z',
              'operator_id': 'op_demo_express',
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-15T09:55:00Z',
              'updated_at': '2026-04-15T10:01:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.upsertOperatorPayoutImportPreviewSavedView(
      const CoachPayoutImportPreviewHistorySavedView(
        viewId: 'previewhistoryview_demo_invalidated',
        accountId: 'acct_finance_demo',
        name: 'Invalidated day',
        visibilityScope: 'shared_ops',
        preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
          status: 'invalidated',
          fromCreatedAtIso: '2026-04-14T00:00:00Z',
          toCreatedAtIso: '2026-04-14T23:59:59Z',
          operatorId: 'op_demo_express',
        ),
        isDefault: true,
        canManage: false,
        createdAtIso: '2026-04-15T09:55:00Z',
        updatedAtIso: '2026-04-15T10:01:00Z',
      ),
      idempotencyKey: 'coach-ops-payout-import-preview-saved-view-test-1',
    );

    expect(savedViews, hasLength(1));
    expect(savedViews.single.preferences.status, 'invalidated');
    expect(savedViews.single.preferences.operatorId, 'op_demo_express');
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.isDefault, isFalse);
    expect(savedViews.single.canManage, isFalse);
  });

  test('deleteOperatorPayoutImportPreviewSavedView posts delete mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_preview_saved_views/previewhistoryview_demo_invalidated/delete',
      );
      expect(
        request.headers['Idempotency-Key'],
        'coach-ops-payout-import-preview-saved-view-delete-test-1',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'payout_import_preview_saved_view_delete',
          'deleted_view_id': 'previewhistoryview_demo_invalidated',
          'saved_views': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.deleteOperatorPayoutImportPreviewSavedView(
      'previewhistoryview_demo_invalidated',
      idempotencyKey:
          'coach-ops-payout-import-preview-saved-view-delete-test-1',
    );

    expect(savedViews, isEmpty);
  });

  test('toggleOperatorPayoutImportPreviewSavedViewFavorite posts mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_preview_saved_views/previewhistoryview_demo_invalidated/favorite',
      );
      expect(
        request.headers['Idempotency-Key'],
        'coach-ops-payout-import-preview-saved-view-favorite-test-1',
      );
      expect(
        jsonDecode(request.body),
        <String, Object?>{'favorite': true},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'previewhistoryview_demo_invalidated',
              'account_id': 'acct_finance_demo',
              'name': 'Invalidated day',
              'visibility_scope': 'shared_ops',
              'status': 'invalidated',
              'from_created_at': '2026-04-14T00:00:00Z',
              'to_created_at': '2026-04-14T23:59:59Z',
              'operator_id': 'op_demo_express',
              'is_favorite': true,
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-15T09:55:00Z',
              'updated_at': '2026-04-15T10:01:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews =
        await api.toggleOperatorPayoutImportPreviewSavedViewFavorite(
      'previewhistoryview_demo_invalidated',
      favorite: true,
      idempotencyKey:
          'coach-ops-payout-import-preview-saved-view-favorite-test-1',
    );

    expect(savedViews, hasLength(1));
    expect(savedViews.single.isFavorite, isTrue);
  });

  test('markOperatorPayoutImportPreviewSavedViewUsed posts mutation', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_preview_saved_views/previewhistoryview_demo_invalidated/use',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-preview-saved-view-use-1',
      );
      expect(
        jsonDecode(request.body),
        <String, Object?>{'used_at': '2026-04-16T10:10:00Z'},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'view_id': 'previewhistoryview_demo_invalidated',
          'used_at': '2026-04-16T10:10:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final usedAtIso = await api.markOperatorPayoutImportPreviewSavedViewUsed(
      'previewhistoryview_demo_invalidated',
      usedAtIso: '2026-04-16T10:10:00Z',
      idempotencyKey: 'idem-coach-preview-saved-view-use-1',
    );

    expect(usedAtIso, '2026-04-16T10:10:00Z');
  });

  test('upsertOperatorPayoutImportBatchSavedView posts mutation payload',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_batch_saved_views',
      );
      expect(
        request.headers['Idempotency-Key'],
        'coach-ops-payout-import-batch-saved-view-test-1',
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['view_id'], 'payoutimportbatchview_demo_express');
      expect(body['name'], 'Demo Express batches');
      expect(body['operator_id'], 'op_demo_express');
      expect(body['visibility_scope'], 'shared_ops');
      expect(body['is_default'], isTrue);
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'payout_import_batch_saved_view_upsert',
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'payoutimportbatchview_demo_express',
              'account_id': 'acct_finance_demo',
              'name': 'Demo Express batches',
              'visibility_scope': 'shared_ops',
              'operator_id': 'op_demo_express',
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-15T09:55:00Z',
              'updated_at': '2026-04-15T10:01:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.upsertOperatorPayoutImportBatchSavedView(
      const CoachPayoutImportBatchSavedView(
        viewId: 'payoutimportbatchview_demo_express',
        accountId: 'acct_finance_demo',
        name: 'Demo Express batches',
        visibilityScope: 'shared_ops',
        preferences: CoachPayoutImportBatchFilterPreferences(
          operatorId: 'op_demo_express',
        ),
        isDefault: true,
        canManage: false,
        createdAtIso: '2026-04-15T09:55:00Z',
        updatedAtIso: '2026-04-15T10:01:00Z',
      ),
      idempotencyKey: 'coach-ops-payout-import-batch-saved-view-test-1',
    );

    expect(savedViews, hasLength(1));
    expect(savedViews.single.preferences.operatorId, 'op_demo_express');
    expect(savedViews.single.visibilityScope, 'shared_ops');
    expect(savedViews.single.isDefault, isFalse);
    expect(savedViews.single.canManage, isFalse);
  });

  test('toggleOperatorPayoutImportBatchSavedViewFavorite posts mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_batch_saved_views/payoutimportbatchview_demo_express/favorite',
      );
      expect(
        request.headers['Idempotency-Key'],
        'coach-ops-payout-import-batch-saved-view-favorite-test-1',
      );
      expect(
        jsonDecode(request.body),
        <String, Object?>{'favorite': true},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'saved_views': <Object?>[
            <String, Object?>{
              'view_id': 'payoutimportbatchview_demo_express',
              'account_id': 'acct_finance_demo',
              'name': 'Demo Express batches',
              'visibility_scope': 'shared_ops',
              'operator_id': 'op_demo_express',
              'is_favorite': true,
              'is_default': false,
              'can_manage': false,
              'created_at': '2026-04-15T09:55:00Z',
              'updated_at': '2026-04-15T10:01:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews =
        await api.toggleOperatorPayoutImportBatchSavedViewFavorite(
      'payoutimportbatchview_demo_express',
      favorite: true,
      idempotencyKey:
          'coach-ops-payout-import-batch-saved-view-favorite-test-1',
    );

    expect(savedViews, hasLength(1));
    expect(savedViews.single.isFavorite, isTrue);
  });

  test('markOperatorPayoutImportBatchSavedViewUsed posts mutation', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_batch_saved_views/payoutimportbatchview_demo_express/use',
      );
      expect(
        request.headers['Idempotency-Key'],
        'idem-coach-batch-saved-view-use-1',
      );
      expect(
        jsonDecode(request.body),
        <String, Object?>{'used_at': '2026-04-16T10:15:00Z'},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'view_id': 'payoutimportbatchview_demo_express',
          'used_at': '2026-04-16T10:15:00Z',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final usedAtIso = await api.markOperatorPayoutImportBatchSavedViewUsed(
      'payoutimportbatchview_demo_express',
      usedAtIso: '2026-04-16T10:15:00Z',
      idempotencyKey: 'idem-coach-batch-saved-view-use-1',
    );

    expect(usedAtIso, '2026-04-16T10:15:00Z');
  });

  test('deleteOperatorPayoutImportBatchSavedView posts delete mutation',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/me/coach/operator/payout_import_batch_saved_views/payoutimportbatchview_demo_express/delete',
      );
      expect(
        request.headers['Idempotency-Key'],
        'coach-ops-payout-import-batch-saved-view-delete-test-1',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'command': 'payout_import_batch_saved_view_delete',
          'deleted_view_id': 'payoutimportbatchview_demo_express',
          'saved_views': const <Object?>[],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final savedViews = await api.deleteOperatorPayoutImportBatchSavedView(
      'payoutimportbatchview_demo_express',
      idempotencyKey: 'coach-ops-payout-import-batch-saved-view-delete-test-1',
    );

    expect(savedViews, isEmpty);
  });

  test('fetchPayoutImportReportBody downloads CSV artifact text', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/downloads/coach/payout_import_reports/payoutrework_demo_1.csv',
      );
      expect(
        request.headers['cookie']?.toLowerCase(),
        '__host-sa_session=0123456789abcdef0123456789abcdef',
      );
      return http.Response(
        'payout_run_id,external_status,payment_reference\n'
        'payoutrun_demo_failed,executed,bank_import_payoutrun_demo_failed\n',
        200,
        headers: const <String, String>{'content-type': 'text/csv'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final reportBody = await api.fetchPayoutImportReportBody(
      '/downloads/coach/payout_import_reports/payoutrework_demo_1.csv',
    );

    expect(reportBody, contains('payoutrun_demo_failed,executed'));
  });

  test('crew departure board, manifest and boarding command parse correctly',
      () async {
    final client = MockClient((request) async {
      final key = '${request.method} ${request.url.path}';
      switch (key) {
        case 'GET /me/coach/crew/departures':
          expect(request.url.queryParameters['limit'], '6');
          return http.Response(
            jsonEncode(<String, Object?>{
              'generated_at': '2026-04-07T15:00:00Z',
              'departures': <Map<String, Object?>>[
                <String, Object?>{
                  'trip_id': 'trip_demo_express_direct',
                  'journey_id': 'journey_demo_express_direct',
                  'booking_id': 'booking_demo_express_direct',
                  'operator_name': 'Demo Express',
                  'from': 'Damascus',
                  'to': 'Aleppo',
                  'departure_at': '2026-04-08T08:00:00Z',
                  'arrival_at': '2026-04-08T12:30:00Z',
                  'boarding_opens_at': '2026-04-08T07:20:00Z',
                  'boarding_closes_at': '2026-04-08T07:55:00Z',
                  'gate_label': 'Bay A4',
                  'vehicle_label': 'Bus DX-402',
                  'manifest_count': 2,
                  'boarded_count': 0,
                  'denied_count': 0,
                  'no_show_count': 0,
                  'pending_count': 2,
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'GET /me/coach/crew/trips/trip_demo_express_direct/manifest':
          return http.Response(
            jsonEncode(<String, Object?>{
              'trip': <String, Object?>{
                'trip_id': 'trip_demo_express_direct',
                'journey_id': 'journey_demo_express_direct',
                'booking_id': 'booking_demo_express_direct',
                'operator_name': 'Demo Express',
                'from': 'Damascus',
                'to': 'Aleppo',
                'departure_at': '2026-04-08T08:00:00Z',
                'arrival_at': '2026-04-08T12:30:00Z',
                'boarding_opens_at': '2026-04-08T07:20:00Z',
                'boarding_closes_at': '2026-04-08T07:55:00Z',
                'gate_label': 'Bay A4',
                'vehicle_label': 'Bus DX-402',
                'manifest_count': 2,
                'boarded_count': 0,
                'denied_count': 0,
                'no_show_count': 0,
                'pending_count': 2,
              },
              'manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'passenger': <String, Object?>{
                    'passenger_id': 'adult_1',
                    'given_name': 'Lina',
                    'family_name': 'Haddad',
                    'rider_category': 'adult',
                    'nationality_code': 'SY',
                  },
                  'ticket': <String, Object?>{
                    'ticket_id': 'ticket_booking_demo_express_direct_1',
                    'booking_id': 'booking_demo_express_direct',
                    'coupon_id': 'coupon-ticket_booking_demo_express_direct_1',
                    'passenger_id': 'adult_1',
                    'segment_ids': <String>['seg_1'],
                    'status': 'active',
                    'operator_ticket_reference': 'operator-ticket-1',
                    'qr_payload_ref':
                        'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
                    'issued_at': '2026-04-07T12:06:30Z',
                  },
                  'seat_number': '4A',
                  'boarding_state': 'not_boarded',
                  'needs_attention': false,
                },
              ],
              'recent_events': <Object?>[],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        case 'POST /me/coach/crew/trips/trip_demo_express_direct/boardings':
          expect(
              request.headers['idempotency-key'], 'coach-crew-boarding-test-1');
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['ticket_id'], 'ticket_booking_demo_express_direct_1');
          expect(body['scan_status'], 'scanned');
          expect(body['device_id'], 'crew_device_demo');
          expect(body['note'], 'boarded at bay a4');
          return http.Response(
            jsonEncode(<String, Object?>{
              'idempotency': <String, Object?>{
                'key': 'coach-crew-boarding-test-1',
                'scope': 'coach_crew_boarding_record',
                'request_fingerprint': 'fp_boarding_1',
                'replayed': false,
                'derived_keys': <String, String>{},
              },
              'trip': <String, Object?>{
                'trip_id': 'trip_demo_express_direct',
                'journey_id': 'journey_demo_express_direct',
                'booking_id': 'booking_demo_express_direct',
                'operator_name': 'Demo Express',
                'from': 'Damascus',
                'to': 'Aleppo',
                'departure_at': '2026-04-08T08:00:00Z',
                'arrival_at': '2026-04-08T12:30:00Z',
                'boarding_opens_at': '2026-04-08T07:20:00Z',
                'boarding_closes_at': '2026-04-08T07:55:00Z',
                'gate_label': 'Bay A4',
                'vehicle_label': 'Bus DX-402',
                'manifest_count': 2,
                'boarded_count': 1,
                'denied_count': 0,
                'no_show_count': 0,
                'pending_count': 1,
              },
              'manifest_entry': <String, Object?>{
                'passenger': <String, Object?>{
                  'passenger_id': 'adult_1',
                  'given_name': 'Lina',
                  'family_name': 'Haddad',
                  'rider_category': 'adult',
                  'nationality_code': 'SY',
                },
                'ticket': <String, Object?>{
                  'ticket_id': 'ticket_booking_demo_express_direct_1',
                  'booking_id': 'booking_demo_express_direct',
                  'coupon_id': 'coupon-ticket_booking_demo_express_direct_1',
                  'passenger_id': 'adult_1',
                  'segment_ids': <String>['seg_1'],
                  'status': 'active',
                  'operator_ticket_reference': 'operator-ticket-1',
                  'qr_payload_ref':
                      'object://coach/tickets/ticket_booking_demo_express_direct_1/qr',
                  'issued_at': '2026-04-07T12:06:30Z',
                },
                'seat_number': '4A',
                'boarding_state': 'boarded',
                'last_event': <String, Object?>{
                  'boarding_event_id': 'boardevt_demo',
                  'ticket_id': 'ticket_booking_demo_express_direct_1',
                  'trip_id': 'trip_demo_express_direct',
                  'scan_status': 'scanned',
                  'captured_at': '2026-04-08T07:41:00Z',
                  'offline_captured': false,
                  'device_id': 'crew_device_demo',
                  'note': 'boarded at bay a4',
                },
                'needs_attention': false,
              },
              'boarding_event': <String, Object?>{
                'boarding_event_id': 'boardevt_demo',
                'ticket_id': 'ticket_booking_demo_express_direct_1',
                'trip_id': 'trip_demo_express_direct',
                'scan_status': 'scanned',
                'captured_at': '2026-04-08T07:41:00Z',
                'offline_captured': false,
                'device_id': 'crew_device_demo',
                'note': 'boarded at bay a4',
              },
              'recent_events': <Map<String, Object?>>[
                <String, Object?>{
                  'boarding_event_id': 'boardevt_demo',
                  'ticket_id': 'ticket_booking_demo_express_direct_1',
                  'trip_id': 'trip_demo_express_direct',
                  'scan_status': 'scanned',
                  'captured_at': '2026-04-08T07:41:00Z',
                  'offline_captured': false,
                  'device_id': 'crew_device_demo',
                  'note': 'boarded at bay a4',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    final departures = await api.crewDepartures(limit: 6);
    final manifest = await api.getCrewManifest('trip_demo_express_direct');
    final result = await api.recordBoarding(
      tripId: 'trip_demo_express_direct',
      ticketId: 'ticket_booking_demo_express_direct_1',
      scanStatus: CoachBoardingScanStatus.scanned,
      deviceId: 'crew_device_demo',
      note: 'boarded at bay a4',
      idempotencyKey: 'coach-crew-boarding-test-1',
    );

    expect(departures.departures.single.gateLabel, 'Bay A4');
    expect(
      manifest.manifest.single.boardingState,
      CoachManifestBoardingState.notBoarded,
    );
    expect(result.trip.boardedCount, 1);
    expect(
        result.manifestEntry.boardingState, CoachManifestBoardingState.boarded);
    expect(result.boardingEvent.note, 'boarded at bay a4');
  });

  test('backend detail is surfaced on coach API errors', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'detail': 'operator inventory unavailable',
        }),
        409,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);

    expect(
      () => api.getBooking('booking_demo'),
      throwsA(
        isA<CoachApiException>().having(
          (error) => error.detail,
          'detail',
          'operator inventory unavailable',
        ),
      ),
    );
  });

  CoachTicketArtifact _makeArtifact({
    String mimeType = 'application/vnd.apple.pkpass',
    int contentLengthBytes = 4,
    String downloadPath = '/downloads/coach/tickets/ticketartifact_demo.pkpass',
  }) {
    return CoachTicketArtifact(
      artifactId: 'ticketartifact_demo',
      ticketId: 'ticket_demo_dl_42',
      bookingId: 'booking_demo_dl_42',
      artifactKind: 'wallet_pass',
      deliveryChannel: 'wallet_pass',
      fileName: 'ticket_demo_dl_42.pkpass',
      mimeType: mimeType,
      contentLengthBytes: contentLengthBytes,
      downloadPath: downloadPath,
    );
  }

  test('fetchTicketArtifactBytes returns body on a content-type/length match', () async {
    final payload = Uint8List.fromList(<int>[0x50, 0x4b, 0x03, 0x04]);
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        '$_apiBaseUrl/downloads/coach/tickets/ticketartifact_demo.pkpass',
      );
      return http.Response.bytes(
        payload,
        200,
        headers: const <String, String>{
          'content-type': 'application/vnd.apple.pkpass',
        },
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);
    final bytes = await api.fetchTicketArtifactBytes(_makeArtifact());
    expect(bytes, equals(payload));
  });

  test('fetchTicketArtifactBytes rejects a wrong content-type', () async {
    final client = MockClient((_) async {
      return http.Response.bytes(
        <int>[1, 2, 3, 4],
        200,
        headers: const <String, String>{'content-type': 'text/html'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);
    expect(
      () => api.fetchTicketArtifactBytes(_makeArtifact()),
      throwsA(
        isA<CoachApiException>().having(
          (error) => error.detail,
          'detail',
          contains('content-type mismatch'),
        ),
      ),
    );
  });

  test('fetchTicketArtifactBytes rejects a length mismatch', () async {
    final client = MockClient((_) async {
      return http.Response.bytes(
        <int>[1, 2, 3, 4, 5, 6, 7, 8],
        200,
        headers: const <String, String>{
          'content-type': 'application/vnd.apple.pkpass',
        },
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);
    expect(
      () => api.fetchTicketArtifactBytes(_makeArtifact()),
      throwsA(
        isA<CoachApiException>().having(
          (error) => error.detail,
          'detail',
          contains('length mismatch'),
        ),
      ),
    );
  });

  test('fetchTicketArtifactBytes tolerates a charset suffix on the content-type', () async {
    final payload = Uint8List.fromList(<int>[0x3c, 0x73, 0x76, 0x67]);
    final client = MockClient((_) async {
      return http.Response.bytes(
        payload,
        200,
        headers: const <String, String>{
          'content-type': 'image/svg+xml; charset=utf-8',
        },
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);
    final artifact = _makeArtifact(
      mimeType: 'image/svg+xml',
      contentLengthBytes: payload.length,
      downloadPath: '/downloads/coach/tickets/ticketartifact_demo.svg',
    );
    final bytes = await api.fetchTicketArtifactBytes(artifact);
    expect(bytes, equals(payload));
  });

  test('fetchTicketArtifactBytes propagates server 403 detail', () async {
    final client = MockClient((_) async {
      return http.Response(
        jsonEncode(<String, Object?>{'detail': 'not allowed'}),
        403,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl, httpClient: client);
    expect(
      () => api.fetchTicketArtifactBytes(_makeArtifact()),
      throwsA(
        isA<CoachApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.detail, 'detail', 'not allowed'),
      ),
    );
  });

  test('resolveTicketArtifactUri rejects a non-https absolute URL', () {
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl);
    expect(
      api.resolveTicketArtifactUri('file:///etc/passwd'),
      isNull,
    );
  });

  test('resolveTicketArtifactUri resolves a relative path against baseUrl', () {
    final api = CoachMobilityApi(baseUrl: _apiBaseUrl);
    expect(
      api.resolveTicketArtifactUri('/downloads/coach/tickets/foo.pkpass'),
      Uri.parse('$_apiBaseUrl/downloads/coach/tickets/foo.pkpass'),
    );
  });
}
