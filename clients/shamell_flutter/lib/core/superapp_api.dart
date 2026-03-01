import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'shamell_webview_page.dart';

const Duration _superappApiRequestTimeout = Duration(seconds: 20);

class GeoPosition {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });
}

typedef EnsureOfficialFollowFn = Future<void> Function({
  required String officialId,
  required String chatPeerId,
});

typedef RecordModuleUseFn = Future<void> Function(String moduleId);

/// Host‑API surface that Mini‑Apps are allowed to depend on.
///
/// This will grow to include Payments, Chat, Location, Storage,
/// Analytics, FeatureFlags, etc. For now it exposes the minimal
/// primitives required to open built‑in Mini‑Apps without reaching
/// into `main.dart`.
class SuperappAPI {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final void Function(String modId) openMod;
  final void Function(Widget page) pushPage;
  final EnsureOfficialFollowFn ensureServiceOfficialFollow;
  final RecordModuleUseFn recordModuleUse;

  const SuperappAPI({
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.openMod,
    required this.pushPage,
    required this.ensureServiceOfficialFollow,
    required this.recordModuleUse,
  });

  static Future<void> _noopEnsureOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) async {}

  static Future<void> _noopRecordModuleUse(String moduleId) async {}

  static void _noopOpenMod(String modId) {}

  static void _noopPushPage(Widget page) {}

  bool get _canPushPage => pushPage != _noopPushPage;

  factory SuperappAPI.light({
    required String baseUrl,
    String walletId = '',
    String deviceId = '',
    void Function(String modId)? openMod,
    void Function(Widget page)? pushPage,
    EnsureOfficialFollowFn? ensureServiceOfficialFollow,
    RecordModuleUseFn? recordModuleUse,
  }) {
    return SuperappAPI(
      baseUrl: baseUrl,
      walletId: walletId,
      deviceId: deviceId,
      openMod: openMod ?? _noopOpenMod,
      pushPage: pushPage ?? _noopPushPage,
      ensureServiceOfficialFollow:
          ensureServiceOfficialFollow ?? _noopEnsureOfficialFollow,
      recordModuleUse: recordModuleUse ?? _noopRecordModuleUse,
    );
  }

  String get _cleanBase => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Uri uri(String path, {Map<String, String>? query}) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$_cleanBase/$p')
        .replace(queryParameters: query?.isEmpty == true ? null : query);
  }

  Future<Map<String, String>> sessionHeaders({
    bool json = false,
    Map<String, String>? extra,
  }) async {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    try {
      final cookie = await getSessionCookieHeader(baseUrl);
      if (cookie != null && cookie.isNotEmpty) h['cookie'] = cookie;
    } catch (_) {}
    if (extra != null && extra.isNotEmpty) {
      h.addAll(extra);
    }
    return h;
  }

  Future<http.Response> getUri(Uri uri, {Map<String, String>? headers}) {
    return http.get(uri, headers: headers).timeout(_superappApiRequestTimeout);
  }

  Future<http.Response> postUri(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return http
        .post(uri, headers: headers, body: body, encoding: encoding)
        .timeout(_superappApiRequestTimeout);
  }

  Future<http.Response> patchUri(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return http
        .patch(uri, headers: headers, body: body, encoding: encoding)
        .timeout(_superappApiRequestTimeout);
  }

  Future<http.Response> deleteUri(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return http
        .delete(uri, headers: headers, body: body, encoding: encoding)
        .timeout(_superappApiRequestTimeout);
  }

  Future<String?> kvGetString(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<int?> kvGetInt(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getInt(key);
    } catch (_) {
      return null;
    }
  }

  Future<bool?> kvGetBool(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(key);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>?> kvGetStringList(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getStringList(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> kvSetString(String key, String value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, value);
    } catch (_) {}
  }

  Future<void> kvSetInt(String key, int value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(key, value);
    } catch (_) {}
  }

  Future<void> kvSetBool(String key, bool value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, value);
    } catch (_) {}
  }

  Future<void> kvSetStringList(String key, List<String> value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(key, value);
    } catch (_) {}
  }

  Future<void> kvRemove(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(key);
    } catch (_) {}
  }

  Future<void> shareText(
    String text, {
    String? subject,
  }) async {
    try {
      await Share.share(text, subject: subject);
    } catch (_) {}
  }

  Future<bool> openUrl(
    Uri uri, {
    bool external = false,
  }) async {
    try {
      final baseUri = Uri.tryParse(_cleanBase);
      if (baseUri != null && uri.scheme.isEmpty) {
        try {
          uri = baseUri.resolveUri(uri);
        } catch (_) {}
      }
      if (!external) {
        final scheme = uri.scheme.toLowerCase();
        if ((scheme == 'http' || scheme == 'https') && _canPushPage) {
          // Best practice: keep embedded WebViews first-party and same-origin.
          if (baseUri != null) {
            final sameScheme = baseUri.scheme.toLowerCase() == scheme;
            final sameHost =
                baseUri.host.toLowerCase() == uri.host.toLowerCase();
            final basePort =
                baseUri.hasPort ? baseUri.port : (scheme == 'https' ? 443 : 80);
            final uriPort =
                uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
            final sameOrigin = sameScheme && sameHost && basePort == uriPort;
            if (sameOrigin) {
              pushPage(
                ShamellWebViewPage(
                  initialUri: uri,
                  baseUri: baseUri,
                ),
              );
              return true;
            }
          }
          // Non-same-origin: open externally to reduce phishing surface.
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return await launchUrl(
        uri,
        mode: external
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> openUrlString(
    String url, {
    bool external = false,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return openUrl(uri, external: external);
  }

  Future<GeoPosition?> getCurrentLocation({bool best = true}) async {
    try {
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: best ? LocationAccuracy.best : LocationAccuracy.high,
      );
      return GeoPosition(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
      );
    } catch (_) {
      return null;
    }
  }
}
