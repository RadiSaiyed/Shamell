import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'session_cookie_store.dart';

class ShamellPlatformFeatureEvents {
  static const Duration _timeout = Duration(seconds: 5);

  const ShamellPlatformFeatureEvents._();

  static Future<void> record({
    required String baseUrl,
    required String moduleId,
    required String action,
    required String featureKey,
    String? miniProgramId,
    String? roleContext,
    Map<String, Object?>? metadata,
    http.Client? client,
  }) async {
    try {
      final uri = secureApiChildUri(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'me',
          'platform',
          'features',
          'events',
        ],
      );
      if (uri == null) return;
      final headers =
          await shamellSessionHeadersForBaseUrl(baseUrl, json: true);
      if ((headers['cookie'] ?? '').trim().isEmpty) return;
      final normalizedModuleId = _normalizeKey(moduleId);
      final normalizedAction = _normalizeKey(action);
      final normalizedFeatureKey = _normalizeKey(featureKey);
      if (normalizedModuleId == null ||
          normalizedAction == null ||
          normalizedFeatureKey == null) {
        return;
      }
      final body = <String, Object?>{
        'module_id': normalizedModuleId,
        'action': normalizedAction,
        'feature_key': normalizedFeatureKey,
      };
      final normalizedMiniProgram = _normalizeKey(miniProgramId);
      if (normalizedMiniProgram != null) {
        body['mini_program_id'] = normalizedMiniProgram;
      }
      final normalizedRole = _normalizeText(roleContext);
      if (normalizedRole != null) {
        body['role_context'] = normalizedRole;
      }
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

  static String? _normalizeKey(String? raw) {
    final trimmed = raw?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return null;
    var value = trimmed.replaceAll(RegExp(r'[^a-z0-9_.:-]+'), '_');
    value = value.replaceAll(RegExp(r'_+'), '_');
    value = value.replaceAll(RegExp(r'^_+|_+$'), '');
    if (value.isEmpty) return null;
    return value;
  }

  static String? _normalizeText(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
