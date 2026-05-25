// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/base_url.dart';

// Stored session state is bound to a single API origin (scheme + host + port)
// so a session cannot silently follow a same-host base URL change to a
// different backend port.
const String _sessionStateKey = 'sa_cookie';

const String _sessionCookieName = '__Host-sa_session';

const FlutterSecureStorage _sessionStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'shamell_secure_store',
  ),
  iOptions:
      IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  mOptions:
      MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device),
);
const Duration _sessionSecureStoreIoTimeout = Duration(seconds: 3);

String? _volatileSessionState;

@visibleForTesting
void debugSetVolatileSessionTokenForBaseUrl(String baseUrl, String token) {
  final origin = _normalizedSessionOriginFromBaseUrl(baseUrl);
  final t = token.trim().toLowerCase();
  if (origin == null || origin.isEmpty || !_isValidToken(t)) return;
  _volatileSessionState = _SessionState(scope: origin, token: t).encode();
}

@visibleForTesting
void debugClearVolatileSessionForTests() {
  _volatileSessionState = null;
}

class _SecureSessionReadResult {
  final String? value;
  final bool failed;
  const _SecureSessionReadResult({
    required this.value,
    required this.failed,
  });
}

class _SessionState {
  final String scope;
  final String token;
  final bool legacyHostOnly;
  const _SessionState({
    required this.scope,
    required this.token,
    this.legacyHostOnly = false,
  });

  String encode() => jsonEncode(<String, Object?>{
        'v': 2,
        'origin': scope,
        'token': token,
      });
}

bool _isLocalhost(String host) {
  final h = host.trim().toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h == '::1';
}

Uri? _parseBaseUrl(String baseUrl) {
  return parseApiBaseUrl(baseUrl);
}

String _normalizedSessionOrigin(Uri u) {
  final scheme = u.scheme.trim().toLowerCase();
  final host = u.host.trim().toLowerCase();
  final defaultPort = scheme == 'https' ? 443 : 80;
  final needsPort = u.hasPort && u.port != defaultPort;
  return needsPort ? '$scheme://$host:${u.port}' : '$scheme://$host';
}

String? _normalizedSessionOriginFromBaseUrl(String baseUrl) {
  final u = _parseBaseUrl(baseUrl);
  if (u == null || !_isSecureSessionBaseUri(u)) return null;
  return _normalizedSessionOrigin(u);
}

bool _canUseLegacyHostScopedSession(Uri u) {
  final scheme = u.scheme.trim().toLowerCase();
  final defaultPort = scheme == 'https' ? 443 : 80;
  return !u.hasPort || u.port == defaultPort;
}

bool _isValidToken(String token) {
  return RegExp(r'^[0-9a-f]{32}$').hasMatch(token.trim().toLowerCase());
}

_SessionState? _parseSessionState(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('{')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        final origin =
            (decoded['origin'] ?? '').toString().trim().toLowerCase();
        final host = (decoded['host'] ?? '').toString().trim().toLowerCase();
        final token = (decoded['token'] ?? '').toString().trim().toLowerCase();
        if (origin.isNotEmpty && _isValidToken(token)) {
          return _SessionState(scope: origin, token: token);
        }
        if (host.isNotEmpty && _isValidToken(token)) {
          return _SessionState(
            scope: host,
            token: token,
            legacyHostOnly: true,
          );
        }
      }
    } catch (_) {}
  }
  return null;
}

Future<_SecureSessionReadResult> _readSecureSessionState() async {
  try {
    final stored = (await _sessionStorage
                .read(key: _sessionStateKey)
                .timeout(_sessionSecureStoreIoTimeout) ??
            '')
        .trim();
    if (stored.isEmpty) {
      return const _SecureSessionReadResult(value: null, failed: false);
    }
    return _SecureSessionReadResult(value: stored, failed: false);
  } catch (_) {
    return const _SecureSessionReadResult(value: null, failed: true);
  }
}

Future<bool> _writeSecureSessionState(String encoded) async {
  try {
    await _sessionStorage
        .write(key: _sessionStateKey, value: encoded)
        .timeout(_sessionSecureStoreIoTimeout);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _deleteSecureSessionState() async {
  try {
    await _sessionStorage
        .delete(key: _sessionStateKey)
        .timeout(_sessionSecureStoreIoTimeout);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _writeSessionState(_SessionState st) async {
  final encoded = st.encode();
  _volatileSessionState = null;
  if (_useSecureSessionStore()) {
    final wroteSecure = await _writeSecureSessionState(encoded);
    if (wroteSecure) {
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
    }
    _volatileSessionState = encoded;
    if (_allowLegacySessionFallback()) {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_sessionStateKey, encoded);
      } catch (_) {}
    }
    return;
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

@visibleForTesting
bool shamellAllowLegacySessionFallbackForRuntime({
  required bool releaseMode,
  required bool isWeb,
  required TargetPlatform platform,
  bool? allowLegacySessionFallbackOnMobile,
  bool? allowLegacySessionFallback,
}) {
  // Fail closed in release builds: never allow legacy/shared-preferences
  // session fallback in production artifacts, regardless of compile-time flags.
  // This prevents accidental token persistence downgrade in hardened builds.
  if (releaseMode) return false;
  if (isWeb) return false;
  final isMobile =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  if (isMobile) {
    // Non-release mobile builds regularly target localhost/LAN backends and
    // depend on resilient session recovery across emulator/device restarts.
    return allowLegacySessionFallbackOnMobile ?? true;
  }
  return allowLegacySessionFallback ?? true;
}

bool _allowLegacySessionFallback() {
  return shamellAllowLegacySessionFallbackForRuntime(
    releaseMode: kReleaseMode,
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    allowLegacySessionFallbackOnMobile: const bool.fromEnvironment(
      'ALLOW_LEGACY_SESSION_FALLBACK_ON_MOBILE',
      defaultValue: true,
    ),
    allowLegacySessionFallback: const bool.fromEnvironment(
      'ALLOW_LEGACY_SESSION_FALLBACK',
      defaultValue: true,
    ),
  );
}

bool _useSecureSessionStore() {
  if (kIsWeb) return true;
  final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (!isDesktop) {
    if (kReleaseMode) return true;
    return const bool.fromEnvironment(
      'ENABLE_MOBILE_SECURE_STORAGE',
      defaultValue: true,
    );
  }
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
    final secureRead = await _readSecureSessionState();
    secureReadFailed = secureRead.failed;
    final stored = secureRead.value;
    if (stored != null) {
      final parsed = _parseSessionState(stored);
      if (parsed != null) {
        return parsed;
      }
      // Can't safely bind a raw legacy token/cookieish value to a specific
      // origin. Fail closed instead of rebinding it to the current base URL.
      await clearSessionCookie();
      return null;
    }
  }

  // Fail closed on production/mobile defaults: do not trust legacy
  // SharedPreferences session state unless fallback is explicitly enabled or
  // secure storage is currently unavailable.
  if (!_allowLegacySessionFallback() && !secureReadFailed) {
    return null;
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
        final migrated = await _writeSecureSessionState(legacy);
        if (migrated) {
          await sp.remove(_sessionStateKey);
        } else if (secureReadFailed) {
          _volatileSessionState = legacy;
        }
      }
      return parsed;
    }
    // Can't safely bind a raw legacy token/cookieish value to a specific
    // origin. Fail closed instead of rebinding it to the current base URL.
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
  // Never send sessions over plaintext to non-local hosts.
  if (!_isSecureSessionBaseUri(u)) {
    return null;
  }
  final origin = _normalizedSessionOrigin(u);
  final host = u.host.trim().toLowerCase();
  final st = await _readSessionState();
  if (st != null) {
    if (!st.legacyHostOnly && st.scope.trim().toLowerCase() == origin) {
      return st.token;
    }
    if (st.legacyHostOnly &&
        st.scope.trim().toLowerCase() == host &&
        _canUseLegacyHostScopedSession(u)) {
      final migrated = _SessionState(scope: origin, token: st.token);
      await _writeSessionState(migrated);
      return migrated.token;
    }
  }
  // If secure storage has a token bound to another origin (for example from a
  // previous environment), allow explicit legacy fallback values to recover
  // without forcing a full logout.
  if (_allowLegacySessionFallback()) {
    try {
      final sp = await SharedPreferences.getInstance();
      final rawLegacy = (sp.getString(_sessionStateKey) ?? '').trim();
      final legacy = _parseSessionState(rawLegacy);
      if (legacy != null) {
        if (!legacy.legacyHostOnly &&
            legacy.scope.trim().toLowerCase() == origin) {
          return legacy.token;
        }
        if (legacy.legacyHostOnly &&
            legacy.scope.trim().toLowerCase() == host &&
            _canUseLegacyHostScopedSession(u)) {
          final migrated = _SessionState(scope: origin, token: legacy.token);
          await _writeSessionState(migrated);
          return migrated.token;
        }
      }
    } catch (_) {}
  }
  return null;
}

Future<String?> getSessionCookieHeader(String baseUrl) async {
  final token = await getSessionTokenForBaseUrl(baseUrl);
  if (token == null || token.isEmpty) return null;
  return '$_sessionCookieName=$token';
}

Future<Map<String, String>> shamellSessionHeadersForBaseUrl(
  String baseUrl, {
  bool json = false,
  bool includeSessionCookie = true,
  Map<String, String>? extra,
}) async {
  final headers = <String, String>{};
  if (json) headers['content-type'] = 'application/json';
  final normalizedBase = normalizeSecureApiBaseUrl(baseUrl.trim());
  final host = Uri.tryParse(normalizedBase ?? '')?.host.toLowerCase() ?? '';
  if (isLocalhostHost(host)) {
    headers['x-shamell-client-ip'] = '127.0.0.1';
  }
  if (includeSessionCookie && normalizedBase != null) {
    try {
      final cookie = await getSessionCookieHeader(normalizedBase);
      if (cookie != null && cookie.isNotEmpty) {
        headers['cookie'] = cookie;
      }
    } catch (_) {}
  }
  if (extra != null && extra.isNotEmpty) {
    headers.addAll(extra);
  }
  return headers;
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
  final origin = _normalizedSessionOriginFromBaseUrl(baseUrl);
  final t = token.trim().toLowerCase();
  if (origin == null || origin.isEmpty) return;
  if (!_isValidToken(t)) return;
  await _writeSessionState(_SessionState(scope: origin, token: t));
}

bool _isSecureSessionBaseUri(Uri u) {
  final scheme = u.scheme.toLowerCase();
  final host = u.host.trim().toLowerCase();
  if (scheme == 'https') return true;
  if (scheme != 'http') return false;
  if (_isLocalhost(host)) return true;
  // In non-release builds, also allow HTTP on the developer's local network
  // so the same code path drives device-on-LAN testing without HTTPS.
  return !kReleaseMode && isLocalNetworkHost(host);
}

Future<void> clearSessionCookie() async {
  _volatileSessionState = null;
  if (_useSecureSessionStore()) {
    await _deleteSecureSessionState();
  }
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_sessionStateKey);
  } catch (_) {}
}
