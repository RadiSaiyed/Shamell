import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_url.dart';
import 'device_binding_guard.dart';
import 'http_error.dart';
import 'session_cookie_store.dart';

const Duration kForgetDeviceRequestTimeout = Duration(seconds: 15);

class ForgetDeviceException implements Exception {
  final String message;
  final int? statusCode;
  final String? rawBody;

  const ForgetDeviceException(
    this.message, {
    this.statusCode,
    this.rawBody,
  });

  bool get isCriticalAccountSessionFailure {
    final status = statusCode;
    if (status != null) {
      return shamellIsCriticalAccountSessionHttpFailure(
        statusCode: status,
        rawBody: rawBody ?? message,
      );
    }
    return shamellContainsCriticalAccountSessionDetail(rawBody ?? message);
  }

  @override
  String toString() => message;
}

Future<void> forgetDeviceOnServer({
  required String baseUrl,
  required String deviceId,
  required String sessionCookie,
  required bool isArabic,
  http.Client? client,
}) async {
  final normalizedDeviceId = deviceId.trim();
  if (normalizedDeviceId.isEmpty) {
    throw ForgetDeviceException(
      isArabic
          ? 'تعذّر تأكيد هوية هذا الجهاز.'
          : 'Could not confirm this device identity.',
    );
  }
  final cookie = sessionCookie.trim();
  if (cookie.isEmpty) {
    throw ForgetDeviceException(
      isArabic ? 'تسجيل الدخول مطلوب.' : 'Sign-in required.',
    );
  }

  final uri = secureApiChildUri(
    baseUrl: baseUrl,
    pathSegments: <String>['auth', 'devices', normalizedDeviceId],
  );
  if (uri == null) {
    throw ForgetDeviceException(
      isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.',
    );
  }
  final httpClient = client ?? shamellHttpClient();
  final closeClient = client == null;
  try {
    final resp = await httpClient
        .delete(
          uri,
          headers: await shamellSessionHeadersForBaseUrl(
            baseUrl,
            includeSessionCookie: false,
            extra: <String, String>{'cookie': cookie},
          ),
        )
        .timeout(kForgetDeviceRequestTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ForgetDeviceException(
        sanitizeHttpError(
          statusCode: resp.statusCode,
          rawBody: resp.body,
          isArabic: isArabic,
        ),
        statusCode: resp.statusCode,
        rawBody: resp.body,
      );
    }

    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map &&
          (decoded['status'] ?? '').toString().trim().toLowerCase() ==
              'ignored') {
        throw ForgetDeviceException(
          isArabic
              ? 'تعذّر تأكيد إزالة هذا الجهاز من الخادم.'
              : 'Could not confirm device removal on the server.',
        );
      }
    } on ForgetDeviceException {
      rethrow;
    } catch (_) {}
  } on ForgetDeviceException {
    rethrow;
  } catch (e) {
    throw ForgetDeviceException(
      sanitizeExceptionForUi(
        error: e,
        isArabic: isArabic,
        fallbackEn: 'Could not forget this device.',
        fallbackAr: 'تعذّر نسيان هذا الجهاز.',
      ),
    );
  } finally {
    if (closeClient) httpClient.close();
  }
}
