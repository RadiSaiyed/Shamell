import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted hotel-operator login session.
///
/// Kept deliberately small — just the bearer token (HMAC-signed by
/// the backend, stateless from the client's perspective), its expiry,
/// the operator's display info, and the hotels they may administer.
///
/// Stored under one SharedPreferences key so a sign-out is a single
/// `remove`. We deliberately do not encrypt the token in storage:
/// it has a 7-day lifetime, is bound to a specific operator, and
/// the device-local storage is already the security boundary
/// the rest of the SyrChat app trusts.
class HotelsOperatorSession {
  final String token;
  final DateTime tokenExpiresAt;
  final String operatorId;
  final String loginId;
  final String displayName;
  final String? contactEmail;
  final List<HotelsOperatorGrant> hotels;

  const HotelsOperatorSession({
    required this.token,
    required this.tokenExpiresAt,
    required this.operatorId,
    required this.loginId,
    required this.displayName,
    required this.hotels,
    this.contactEmail,
  });

  /// Marker for sessions that ride the Shamell platform cookie
  /// instead of the legacy hotel-operator bearer token. Set by
  /// `HotelsOperatorSession.platformAuth(...)` after a successful
  /// `/v1/hotels/me/grants` call; the rest of the console uses it to
  /// skip the Authorization header (the BFF injects
  /// X-Shamell-Account-Id upstream so the hotels-service dual-auth
  /// path picks up).
  bool get isPlatformAuth => token.isEmpty;

  bool get isExpired {
    if (isPlatformAuth) return false; // Shamell session owns its lifecycle.
    return DateTime.now().toUtc().isAfter(tokenExpiresAt);
  }

  bool canAdminister(String hotelId) =>
      hotels.any((g) => g.hotelId == hotelId.trim());

  String authorizationHeader() => isPlatformAuth ? '' : 'Bearer $token';

  /// Construct a session that piggybacks on the Shamell platform cookie
  /// — no bearer token. The single grant carries the hotel + role
  /// returned by `/v1/hotels/me/grants`. `tokenExpiresAt` is set to a
  /// far-future date so legacy code paths reading it never trip the
  /// expiry guard; `isExpired` short-circuits to false anyway via
  /// `isPlatformAuth`.
  factory HotelsOperatorSession.platformAuth({
    required String hotelId,
    required String role,
    String displayName = 'Platform operator',
  }) {
    return HotelsOperatorSession(
      token: '',
      tokenExpiresAt: DateTime.utc(9999, 12, 31),
      operatorId: '',
      loginId: '',
      displayName: displayName,
      hotels: [HotelsOperatorGrant(hotelId: hotelId, role: role)],
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'token_expires_at': tokenExpiresAt.toIso8601String(),
        'operator_id': operatorId,
        'login_id': loginId,
        'display_name': displayName,
        'contact_email': contactEmail,
        'hotels': hotels.map((g) => g.toJson()).toList(),
      };

  static HotelsOperatorSession? fromJson(Map<String, dynamic> json) {
    final token = (json['token'] ?? '').toString();
    if (token.isEmpty) return null;
    final exp = DateTime.tryParse((json['token_expires_at'] ?? '').toString());
    if (exp == null) return null;
    final hotelsRaw = json['hotels'];
    final hotels = hotelsRaw is List
        ? hotelsRaw
            .whereType<Map>()
            .map((m) => HotelsOperatorGrant.fromJson(m.cast<String, dynamic>()))
            .whereType<HotelsOperatorGrant>()
            .toList(growable: false)
        : const <HotelsOperatorGrant>[];
    return HotelsOperatorSession(
      token: token,
      tokenExpiresAt: exp,
      operatorId: (json['operator_id'] ?? '').toString(),
      loginId: (json['login_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      contactEmail: json['contact_email']?.toString(),
      hotels: hotels,
    );
  }

  static HotelsOperatorSession? fromLoginResponse(Map<String, dynamic> body) {
    final token = (body['token'] ?? '').toString();
    if (token.isEmpty) return null;
    final exp = DateTime.tryParse((body['token_expires_at'] ?? '').toString());
    if (exp == null) return null;
    final op = body['operator'];
    if (op is! Map) return null;
    final hotelsRaw = op['hotels'];
    final hotels = hotelsRaw is List
        ? hotelsRaw
            .whereType<Map>()
            .map((m) => HotelsOperatorGrant.fromJson(m.cast<String, dynamic>()))
            .whereType<HotelsOperatorGrant>()
            .toList(growable: false)
        : const <HotelsOperatorGrant>[];
    return HotelsOperatorSession(
      token: token,
      tokenExpiresAt: exp,
      operatorId: (op['id'] ?? '').toString(),
      loginId: (op['login_id'] ?? '').toString(),
      displayName: (op['display_name'] ?? '').toString(),
      contactEmail: op['contact_email']?.toString(),
      hotels: hotels,
    );
  }
}

class HotelsOperatorGrant {
  final String hotelId;
  final String role;
  const HotelsOperatorGrant({required this.hotelId, required this.role});

  Map<String, dynamic> toJson() => {'hotel_id': hotelId, 'role': role};

  static HotelsOperatorGrant? fromJson(Map<String, dynamic> json) {
    final id = (json['hotel_id'] ?? '').toString();
    if (id.isEmpty) return null;
    return HotelsOperatorGrant(
      hotelId: id,
      role: (json['role'] ?? 'staff').toString(),
    );
  }
}

/// Storage facade for the operator session. Versioned key so a
/// breaking change (e.g. token format) can ignore the old payload.
class HotelsOperatorSessionStore {
  static const _kKey = 'hotels_operator_session_v1';

  Future<HotelsOperatorSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final s = HotelsOperatorSession.fromJson(decoded.cast<String, dynamic>());
      if (s == null || s.isExpired) {
        // Don't return expired sessions — caller would just send a
        // doomed request. Clean them up while we're here.
        await prefs.remove(_kKey);
        return null;
      }
      return s;
    } catch (_) {
      // Corrupt payload — wipe it so we get a fresh slate next time.
      await prefs.remove(_kKey);
      return null;
    }
  }

  Future<void> save(HotelsOperatorSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
