import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Stored session state is bound to a single API host (best practice: never send
// a session to a different base URL if the user changes it in "Advanced").
const String _sessionStateKey = 'sa_cookie';

const String _sessionCookieName = '__Host-sa_session';

const FlutterSecureStorage _sessionStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    resetOnError: true,
    sharedPreferencesName: 'shamell_secure_store',
  ),
  iOptions:
      IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device),
);

String? _volatileSessionState;

class _SessionState {
  final String host;
  final String token;
  const _SessionState({required this.host, required this.token});

  String encode() => jsonEncode(<String, Object?>{
        'v': 1,
        'host': host,
        'token': token,
      });
}

bool _isLocalhost(String host) {
  final h = host.trim().toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h == '::1';
}

Uri? _parseBaseUrl(String baseUrl) {
  try {
    final u = Uri.parse(baseUrl.trim());
    if (u.host.trim().isEmpty) return null;
    return u;
  } catch (_) {
    return null;
  }
}

String? _normalizedHostFromBaseUrl(String baseUrl) {
  final u = _parseBaseUrl(baseUrl);
  if (u == null) return null;
  final host = u.host.trim().toLowerCase();
  if (host.isEmpty) return null;
  return host;
}

bool _isValidToken(String token) {
  return RegExp(r'^[0-9a-f]{32}$').hasMatch(token.trim().toLowerCase());
}

String? _extractTokenFromCookieish(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final mHost = RegExp(r'__Host-sa_session=([0-9a-f]{32})').firstMatch(s);
  if (mHost != null && (mHost.group(1) ?? '').isNotEmpty) {
    return (mHost.group(1) ?? '').trim().toLowerCase();
  }
  final mLegacy = RegExp(r'(^|;\\s*)sa_session=([0-9a-f]{32})').firstMatch(s);
  if (mLegacy != null && (mLegacy.group(2) ?? '').isNotEmpty) {
    return (mLegacy.group(2) ?? '').trim().toLowerCase();
  }
  // Raw token (allowed for backwards-compat).
  final v = s.toLowerCase();
  if (_isValidToken(v)) return v;
  return null;
}

_SessionState? _parseSessionState(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('{')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        final host = (decoded['host'] ?? '').toString().trim().toLowerCase();
        final token = (decoded['token'] ?? '').toString().trim().toLowerCase();
        if (host.isNotEmpty && _isValidToken(token)) {
          return _SessionState(host: host, token: token);
        }
      }
    } catch (_) {}
  }
  return null;
}

Future<void> _writeSessionState(_SessionState st) async {
  final encoded = st.encode();
  _volatileSessionState = null;
  if (_useSecureSessionStore()) {
    try {
      await _sessionStorage.write(key: _sessionStateKey, value: encoded);
      if (_allowLegacySessionFallback()) {
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString(_sessionStateKey, encoded);
        } catch (_) {}
      } else {
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.remove(_sessionStateKey);
        } catch (_) {}
      }
      return;
    } catch (_) {
      _volatileSessionState = encoded;
      if (_allowLegacySessionFallback()) {
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString(_sessionStateKey, encoded);
        } catch (_) {}
      }
      return;
    }
  } else if (_allowLegacySessionFallback()) {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_sessionStateKey, encoded);
    } catch (_) {}
    return;
  } else {
    _volatileSessionState = encoded;
    return;
  }
}

bool _allowLegacySessionFallback() {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_SESSION_FALLBACK_ON_MOBILE_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_SESSION_FALLBACK_ON_MOBILE',
      defaultValue: true,
    );
  }
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_SESSION_FALLBACK_IN_RELEASE',
      defaultValue: false,
    );
  }
  return const bool.fromEnvironment(
    'ALLOW_LEGACY_SESSION_FALLBACK',
    defaultValue: true,
  );
}

bool _useSecureSessionStore() {
  if (kIsWeb) return true;
  final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (!isDesktop) return true;
  if (kReleaseMode) {
    return const bool.fromEnvironment(
      'ENABLE_DESKTOP_SECURE_STORAGE',
      defaultValue: true,
    );
  }
  return const bool.fromEnvironment(
    'ENABLE_DESKTOP_SECURE_STORAGE',
    defaultValue: false,
  );
}

Future<_SessionState?> _readSessionState() async {
  final volatile = (_volatileSessionState ?? '').trim();
  if (volatile.isNotEmpty) {
    return _parseSessionState(volatile);
  }

  var secureReadFailed = false;
  if (_useSecureSessionStore()) {
    try {
      final stored =
          (await _sessionStorage.read(key: _sessionStateKey) ?? '').trim();
      if (stored.isNotEmpty) {
        final parsed = _parseSessionState(stored);
        if (parsed != null) {
          return parsed;
        }
        // Legacy raw value: try to migrate if we can infer the host.
        final token = _extractTokenFromCookieish(stored);
        if (token != null && token.isNotEmpty) {
          try {
            final sp = await SharedPreferences.getInstance();
            final base = (sp.getString('base_url') ?? '').trim();
            final host = _normalizedHostFromBaseUrl(base);
            if (host != null && host.isNotEmpty) {
              final st = _SessionState(host: host, token: token);
              await _writeSessionState(st);
              return st;
            }
          } catch (_) {}
        }
        // Can't safely bind legacy value to a host.
        await clearSessionCookie();
        return null;
      }
    } catch (_) {
      secureReadFailed = true;
    }
  }

  try {
    final sp = await SharedPreferences.getInstance();
    final legacy = (sp.getString(_sessionStateKey) ?? '').trim();
    if (legacy.isEmpty) {
      return null;
    }
    final parsed = _parseSessionState(legacy);
    if (parsed != null) {
      if (_useSecureSessionStore()) {
        try {
          await _sessionStorage.write(key: _sessionStateKey, value: legacy);
          await sp.remove(_sessionStateKey);
        } catch (_) {
          if (secureReadFailed) {
            _volatileSessionState = legacy;
          }
        }
      }
      return parsed;
    }
    // Legacy raw value: try to migrate if we can infer the host.
    final token = _extractTokenFromCookieish(legacy);
    if (token != null && token.isNotEmpty) {
      final base = (sp.getString('base_url') ?? '').trim();
      final host = _normalizedHostFromBaseUrl(base);
      if (host != null && host.isNotEmpty) {
        final st = _SessionState(host: host, token: token);
        await _writeSessionState(st);
        return st;
      }
    }
    // Can't safely bind legacy value to a host.
    await clearSessionCookie();
    return null;
  } catch (_) {
    return null;
  }
}

Future<String?> getSessionTokenForBaseUrl(String baseUrl) async {
  // On web, rely on HttpOnly cookies managed by the browser, not client-side
  // storage. (Storing session tokens in web storage is a footgun.)
  if (kIsWeb) return null;
  final u = _parseBaseUrl(baseUrl);
  if (u == null) return null;
  final host = u.host.trim().toLowerCase();
  // Never send sessions over plaintext to non-local hosts.
  if (!_isSecureSessionBaseUri(u)) {
    return null;
  }
  final st = await _readSessionState();
  if (st == null) return null;
  if (st.host.trim().toLowerCase() != host) {
    return null;
  }
  return st.token;
}

Future<String?> getSessionCookieHeader(String baseUrl) async {
  final token = await getSessionTokenForBaseUrl(baseUrl);
  if (token == null || token.isEmpty) return null;
  return '$_sessionCookieName=$token';
}

String? extractSessionTokenFromSetCookieHeader(String? setCookie) {
  final sc = (setCookie ?? '').trim();
  if (sc.isEmpty) return null;
  final m = RegExp(r'__host-sa_session=([0-9a-f]{32})', caseSensitive: false)
      .firstMatch(sc);
  final tok = (m?.group(1) ?? '').trim().toLowerCase();
  if (tok.isEmpty) return null;
  if (!_isValidToken(tok)) return null;
  return tok;
}

Future<void> setSessionTokenForBaseUrl(String baseUrl, String token) async {
  if (kIsWeb) return;
  final u = _parseBaseUrl(baseUrl);
  if (u == null || !_isSecureSessionBaseUri(u)) return;
  final host = u.host.trim().toLowerCase();
  final t = token.trim().toLowerCase();
  if (host.isEmpty) return;
  if (!_isValidToken(t)) return;
  await _writeSessionState(_SessionState(host: host, token: t));
}

bool _isSecureSessionBaseUri(Uri u) {
  final scheme = u.scheme.toLowerCase();
  final host = u.host.trim().toLowerCase();
  return scheme == 'https' || (scheme == 'http' && _isLocalhost(host));
}

Future<void> clearSessionCookie() async {
  _volatileSessionState = null;
  if (_useSecureSessionStore()) {
    try {
      await _sessionStorage.delete(key: _sessionStateKey);
    } catch (_) {}
  }
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_sessionStateKey);
  } catch (_) {}
}
