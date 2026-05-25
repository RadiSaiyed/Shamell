import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class ShamellAppActivity {
  static const Duration _timeout = Duration(seconds: 5);

  const ShamellAppActivity._();

  static Future<void> record({
    required String baseUrl,
    String eventType = 'app_action',
    String? moduleId,
    String? action,
    String? route,
    Map<String, Object?>? metadata,
    http.Client? client,
  }) async {
    try {
      final uri = secureApiChildUri(
        baseUrl: baseUrl,
        pathSegments: const <String>['me', 'activity'],
      );
      if (uri == null) return;
      final headers =
          await shamellSessionHeadersForBaseUrl(baseUrl, json: true);
      if ((headers['cookie'] ?? '').trim().isEmpty) return;
      final body = <String, Object?>{
        'event_type': _normalizeEventType(eventType),
      };
      final normalizedModuleId = _normalizeText(moduleId);
      if (normalizedModuleId != null) body['module_id'] = normalizedModuleId;
      final normalizedAction = _normalizeText(action);
      if (normalizedAction != null) body['action'] = normalizedAction;
      final normalizedRoute = _normalizeText(route);
      if (normalizedRoute != null) body['route'] = normalizedRoute;
      if (metadata != null && metadata.isNotEmpty) {
        body['metadata'] = metadata;
      }
      final httpClient = client ?? shamellHttpClient();
      final closeClient = client == null;
      try {
        await httpClient
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout);
      } finally {
        if (closeClient) {
          httpClient.close();
        }
      }
    } catch (_) {}
  }

  static String _normalizeEventType(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return 'app_action';
    return value;
  }

  static String? _normalizeText(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}

void shamellRecordAppActivity({
  required String baseUrl,
  String eventType = 'app_action',
  String? moduleId,
  String? action,
  String? route,
  Map<String, Object?>? metadata,
  http.Client? client,
}) {
  unawaited(
    ShamellAppActivity.record(
      baseUrl: baseUrl,
      eventType: eventType,
      moduleId: moduleId,
      action: action,
      route: route,
      metadata: metadata,
      client: client,
    ),
  );
}
