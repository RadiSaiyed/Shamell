// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url.dart';

class _SecureBoolReadResult {
  final bool? value;
  final bool failed;
  const _SecureBoolReadResult({required this.value, required this.failed});
}

/// Server-driven feature capabilities.
///
/// Best practice: fail-closed (capability defaults to off unless explicitly
/// enabled by the server). This prevents half-implemented modules from being
/// reachable and avoids confusing auth/404 UI errors.
class ShamellCapabilities {
  final bool coach;
  final bool chat;
  final bool payments;
  final bool friends;
  final bool moments;
  final bool officialAccounts;
  final bool channels;
  final bool serviceNotifications;
  final bool paymentsPhoneTargets;
  final bool paymentsSonic;
  final bool paymentsCashVouchers;
  final bool paymentsBills;
  final bool paymentsSavings;

  const ShamellCapabilities({
    this.coach = false,
    required this.chat,
    required this.payments,
    required this.friends,
    required this.moments,
    required this.officialAccounts,
    required this.channels,
    required this.serviceNotifications,
    required this.paymentsPhoneTargets,
    this.paymentsSonic = _kPaymentsSonicForcedOff,
    this.paymentsCashVouchers = _kPaymentsCashVouchersForcedOff,
    this.paymentsBills = _kPaymentsBillsForcedOff,
    this.paymentsSavings = _kPaymentsSavingsForcedOff,
  });

  static const ShamellCapabilities conservativeDefaults = ShamellCapabilities(
    coach: false,
    chat: true,
    payments: true,
    friends: false,
    moments: true,
    officialAccounts: false,
    channels: _kChannelsForcedOff,
    serviceNotifications: false,
    paymentsPhoneTargets: _kPaymentsPhoneTargetsForcedOff,
    paymentsSonic: _kPaymentsSonicForcedOff,
    paymentsCashVouchers: _kPaymentsCashVouchersForcedOff,
    paymentsBills: _kPaymentsBillsForcedOff,
    paymentsSavings: _kPaymentsSavingsForcedOff,
  );

  // SharedPreferences keys (persisted per install).
  static const String kCoach = 'cap.coach';
  static const String kChat = 'cap.chat';
  static const String kPayments = 'cap.payments';
  static const String kFriends = 'cap.friends';
  static const String kMoments = 'cap.moments';
  static const String kOfficialAccounts = 'cap.official_accounts';
  static const String kChannels = 'cap.channels';
  static const String kServiceNotifications = 'cap.service_notifications';
  static const String kPaymentsPhoneTargets = 'cap.payments_phone_targets';
  static const String kPaymentsSonic = 'cap.payments_sonic';
  static const String kPaymentsCashVouchers = 'cap.payments_cash_vouchers';
  static const String kPaymentsBills = 'cap.payments_bills';
  static const String kPaymentsSavings = 'cap.payments_savings';

  // Hard-disabled capabilities (product decision during v2 migration).
  static const bool _kChannelsForcedOff = false;
  static const bool _kPaymentsPhoneTargetsForcedOff = false;
  static const bool _kPaymentsSonicForcedOff = false;
  static const bool _kPaymentsCashVouchersForcedOff = false;
  static const bool _kPaymentsBillsForcedOff = false;
  static const bool _kPaymentsSavingsForcedOff = false;
  static const FlutterSecureStorage _secureStore = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
      sharedPreferencesName: 'shamell_secure_store',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );

  static String _originForBaseUrl(String baseUrl) {
    final normalized = normalizeSecureApiBaseUrl(baseUrl.trim());
    if (normalized == null) return 'unknown';
    final u = Uri.tryParse(normalized);
    if (u == null) return 'unknown';
    final scheme = u.scheme.toLowerCase();
    final host = u.host.trim().toLowerCase();
    if (host.isEmpty) return 'unknown';
    final defaultPort = scheme == 'https'
        ? 443
        : scheme == 'http'
            ? 80
            : null;
    final hasPort = u.hasPort;
    final port = hasPort ? u.port : null;
    final includePort =
        port != null && (defaultPort == null || port != defaultPort);
    final portPart = includePort ? ':$port' : '';
    return '$scheme://$host$portPart';
  }

  static String _scopedKey(String baseUrl, String key) {
    // Scope persisted capabilities to the server origin to avoid stale caps
    // leaking across environments (localhost/staging/prod).
    return '$key@${_originForBaseUrl(baseUrl)}';
  }

  /// Reads server capabilities scoped to a specific base URL origin.
  ///
  /// Important: this intentionally does NOT fall back to legacy global keys,
  /// because doing so would re-enable stale capabilities when switching between
  /// servers/environments.
  static Future<ShamellCapabilities> loadForBaseUrl(
    String baseUrl, {
    SharedPreferences? sp,
  }) async {
    final d = conservativeDefaults;
    Future<bool> read(String key, bool fallback) async {
      return _loadCapabilityValue(
        key: _scopedKey(baseUrl, key),
        fallback: fallback,
        sp: sp,
      );
    }

    return _composeServerDriven(
      coach: await read(kCoach, d.coach),
      chat: await read(kChat, d.chat),
      payments: await read(kPayments, d.payments),
      friends: await read(kFriends, d.friends),
      moments: await read(kMoments, d.moments),
      officialAccounts: await read(kOfficialAccounts, d.officialAccounts),
      serviceNotifications: await read(
        kServiceNotifications,
        d.serviceNotifications,
      ),
      paymentsSonic: await read(kPaymentsSonic, d.paymentsSonic),
      paymentsCashVouchers: await read(
        kPaymentsCashVouchers,
        d.paymentsCashVouchers,
      ),
      paymentsBills: await read(kPaymentsBills, d.paymentsBills),
      paymentsSavings: await read(kPaymentsSavings, d.paymentsSavings),
    );
  }

  static Future<ShamellCapabilities> loadGlobal({SharedPreferences? sp}) async {
    final d = conservativeDefaults;
    return _composeServerDriven(
      coach: await _loadCapabilityValue(key: kCoach, fallback: d.coach, sp: sp),
      chat: await _loadCapabilityValue(key: kChat, fallback: d.chat, sp: sp),
      payments: await _loadCapabilityValue(
        key: kPayments,
        fallback: d.payments,
        sp: sp,
      ),
      friends: await _loadCapabilityValue(
        key: kFriends,
        fallback: d.friends,
        sp: sp,
      ),
      moments: await _loadCapabilityValue(
        key: kMoments,
        fallback: d.moments,
        sp: sp,
      ),
      officialAccounts: await _loadCapabilityValue(
        key: kOfficialAccounts,
        fallback: d.officialAccounts,
        sp: sp,
      ),
      serviceNotifications: await _loadCapabilityValue(
        key: kServiceNotifications,
        fallback: d.serviceNotifications,
        sp: sp,
      ),
      paymentsSonic: await _loadCapabilityValue(
        key: kPaymentsSonic,
        fallback: d.paymentsSonic,
        sp: sp,
      ),
      paymentsCashVouchers: await _loadCapabilityValue(
        key: kPaymentsCashVouchers,
        fallback: d.paymentsCashVouchers,
        sp: sp,
      ),
      paymentsBills: await _loadCapabilityValue(
        key: kPaymentsBills,
        fallback: d.paymentsBills,
        sp: sp,
      ),
      paymentsSavings: await _loadCapabilityValue(
        key: kPaymentsSavings,
        fallback: d.paymentsSavings,
        sp: sp,
      ),
    );
  }

  Future<void> persistForBaseUrl(SharedPreferences sp, String baseUrl) async {
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kCoach),
      value: coach,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kChat),
      value: chat,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kPayments),
      value: payments,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kFriends),
      value: friends,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kMoments),
      value: moments,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kOfficialAccounts),
      value: officialAccounts,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kChannels),
      value: _kChannelsForcedOff,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kServiceNotifications),
      value: serviceNotifications,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kPaymentsSonic),
      value: _kPaymentsSonicForcedOff,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kPaymentsCashVouchers),
      value: _kPaymentsCashVouchersForcedOff,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kPaymentsBills),
      value: _kPaymentsBillsForcedOff,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kPaymentsSavings),
      value: _kPaymentsSavingsForcedOff,
      sp: sp,
    );
    // Keep the key for backwards compatibility, but always store "false".
    await _saveCapabilityValue(
      key: _scopedKey(baseUrl, kPaymentsPhoneTargets),
      value: _kPaymentsPhoneTargetsForcedOff,
      sp: sp,
    );
  }

  Future<void> persist(SharedPreferences sp) async {
    await _saveCapabilityValue(key: kCoach, value: coach, sp: sp);
    await _saveCapabilityValue(key: kChat, value: chat, sp: sp);
    await _saveCapabilityValue(key: kPayments, value: payments, sp: sp);
    await _saveCapabilityValue(key: kFriends, value: friends, sp: sp);
    await _saveCapabilityValue(key: kMoments, value: moments, sp: sp);
    await _saveCapabilityValue(
      key: kOfficialAccounts,
      value: officialAccounts,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: kChannels,
      value: _kChannelsForcedOff,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: kServiceNotifications,
      value: serviceNotifications,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: kPaymentsSonic,
      value: _kPaymentsSonicForcedOff,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: kPaymentsCashVouchers,
      value: _kPaymentsCashVouchersForcedOff,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: kPaymentsBills,
      value: _kPaymentsBillsForcedOff,
      sp: sp,
    );
    await _saveCapabilityValue(
      key: kPaymentsSavings,
      value: _kPaymentsSavingsForcedOff,
      sp: sp,
    );
    // Keep the key for backwards compatibility, but always store "false".
    await _saveCapabilityValue(
      key: kPaymentsPhoneTargets,
      value: _kPaymentsPhoneTargetsForcedOff,
      sp: sp,
    );
  }

  /// Merges a capabilities JSON object into a baseline, falling back to baseline
  /// values for any missing keys.
  static ShamellCapabilities mergeJson(
    dynamic capsJson,
    ShamellCapabilities base,
  ) {
    if (capsJson is! Map) return base;
    bool read(String key, bool fallback) {
      try {
        final v = capsJson[key];
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) {
          final t = v.trim().toLowerCase();
          if (t == 'true' || t == '1' || t == 'yes') return true;
          if (t == 'false' || t == '0' || t == 'no') return false;
        }
      } catch (_) {}
      return fallback;
    }

    return _composeServerDriven(
      coach: read('coach', base.coach),
      chat: read('chat', base.chat),
      payments: read('payments', base.payments),
      friends: read('friends', base.friends),
      moments: read('moments', base.moments),
      officialAccounts: read('official_accounts', base.officialAccounts),
      serviceNotifications: read(
        'service_notifications',
        base.serviceNotifications,
      ),
      paymentsSonic: read('payments_sonic', base.paymentsSonic),
      paymentsCashVouchers: read(
        'payments_cash_vouchers',
        base.paymentsCashVouchers,
      ),
      paymentsBills: read('payments_bills', base.paymentsBills),
      paymentsSavings: read('payments_savings', base.paymentsSavings),
    );
  }

  static ShamellCapabilities _composeServerDriven({
    required bool coach,
    required bool chat,
    required bool payments,
    required bool friends,
    required bool moments,
    required bool officialAccounts,
    required bool serviceNotifications,
    bool paymentsSonic = _kPaymentsSonicForcedOff,
    bool paymentsCashVouchers = _kPaymentsCashVouchersForcedOff,
    bool paymentsBills = _kPaymentsBillsForcedOff,
    bool paymentsSavings = _kPaymentsSavingsForcedOff,
  }) {
    return ShamellCapabilities(
      coach: coach,
      chat: chat,
      payments: payments,
      friends: friends,
      moments: moments,
      officialAccounts: officialAccounts,
      channels: _kChannelsForcedOff,
      serviceNotifications: serviceNotifications,
      paymentsPhoneTargets: _kPaymentsPhoneTargetsForcedOff,
      paymentsSonic: _kPaymentsSonicForcedOff,
      paymentsCashVouchers: _kPaymentsCashVouchersForcedOff,
      paymentsBills: _kPaymentsBillsForcedOff,
      paymentsSavings: _kPaymentsSavingsForcedOff,
    );
  }

  static Future<bool> _loadCapabilityValue({
    required String key,
    required bool fallback,
    SharedPreferences? sp,
  }) async {
    if (!kIsWeb) {
      var secureReadFailed = false;
      final secureRead = await _readSecureBoolResult(key);
      secureReadFailed = secureRead.failed;
      final secure = secureRead.value;
      if (secure != null) {
        await _removeLegacyBool(key, sp: sp);
        return secure;
      }

      // Fail closed by default: do not trust mutable SharedPreferences
      // capability values unless fallback is explicitly enabled or secure
      // storage is unavailable.
      if (!_allowLegacyCapabilitiesFallback() && !secureReadFailed) {
        await _removeLegacyBool(key, sp: sp);
        return fallback;
      }

      try {
        final prefs = sp ?? await SharedPreferences.getInstance();
        final legacy = prefs.getBool(key);
        if (legacy == null) return fallback;
        final wrote = await _writeSecureBool(key, legacy);
        await _removeLegacyBool(key, sp: prefs);
        if (!wrote) {
          try {
            await _secureStore.delete(key: key);
          } catch (_) {}
          if (secureReadFailed) {
            return legacy;
          }
          return fallback;
        }
        return legacy;
      } catch (_) {
        return fallback;
      }
    }

    try {
      final prefs = sp ?? await SharedPreferences.getInstance();
      final legacy = prefs.getBool(key);
      return legacy ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> _saveCapabilityValue({
    required String key,
    required bool value,
    required SharedPreferences sp,
  }) async {
    if (!kIsWeb) {
      final wrote = await _writeSecureBool(key, value);
      await _removeLegacyBool(key, sp: sp);
      if (!wrote) {
        try {
          await _secureStore.delete(key: key);
        } catch (_) {}
      }
      return;
    }

    await sp.setBool(key, value);
  }

  static bool _allowLegacyCapabilitiesFallback() {
    if (kIsWeb) return false;
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      if (kReleaseMode) {
        return const bool.fromEnvironment(
          'ALLOW_LEGACY_CAPABILITIES_FALLBACK_ON_MOBILE_IN_RELEASE',
          defaultValue: false,
        );
      }
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_CAPABILITIES_FALLBACK_ON_MOBILE',
        defaultValue: false,
      );
    }
    if (kReleaseMode) {
      return const bool.fromEnvironment(
        'ALLOW_LEGACY_CAPABILITIES_FALLBACK_IN_RELEASE',
        defaultValue: false,
      );
    }
    return const bool.fromEnvironment(
      'ALLOW_LEGACY_CAPABILITIES_FALLBACK',
      defaultValue: true,
    );
  }

  static Future<_SecureBoolReadResult> _readSecureBoolResult(String key) async {
    try {
      final raw =
          (await _secureStore.read(key: key) ?? '').trim().toLowerCase();
      if (raw.isEmpty) {
        return const _SecureBoolReadResult(value: null, failed: false);
      }
      if (raw == '1' || raw == 'true') {
        return const _SecureBoolReadResult(value: true, failed: false);
      }
      if (raw == '0' || raw == 'false') {
        return const _SecureBoolReadResult(value: false, failed: false);
      }
      return const _SecureBoolReadResult(value: null, failed: false);
    } catch (_) {
      return const _SecureBoolReadResult(value: null, failed: true);
    }
  }

  static Future<bool> _writeSecureBool(String key, bool value) async {
    try {
      final encoded = value ? '1' : '0';
      await _secureStore.write(key: key, value: encoded);
      final roundTrip = (await _secureStore.read(key: key) ?? '').trim();
      return roundTrip == encoded;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _removeLegacyBool(
    String key, {
    SharedPreferences? sp,
  }) async {
    try {
      final prefs = sp ?? await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  static Future<void> clearPersistedState({SharedPreferences? sp}) async {
    final prefs = sp ?? await SharedPreferences.getInstance();
    final capabilityKeys = <String>{
      kCoach,
      kChat,
      kPayments,
      kFriends,
      kMoments,
      kOfficialAccounts,
      kChannels,
      kServiceNotifications,
      kPaymentsPhoneTargets,
      kPaymentsSonic,
      kPaymentsCashVouchers,
      kPaymentsBills,
      kPaymentsSavings,
    };

    for (final key in prefs.getKeys()) {
      if (_isCapabilityStorageKey(key, capabilityKeys)) {
        try {
          await prefs.remove(key);
        } catch (_) {}
      }
    }

    if (kIsWeb) return;
    try {
      final all = await _secureStore.readAll();
      for (final key in all.keys) {
        if (_isCapabilityStorageKey(key, capabilityKeys)) {
          try {
            await _secureStore.delete(key: key);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static bool _isCapabilityStorageKey(String key, Set<String> capabilityKeys) {
    final normalized = key.trim();
    if (normalized.isEmpty) return false;
    for (final capabilityKey in capabilityKeys) {
      if (normalized == capabilityKey ||
          normalized.startsWith('$capabilityKey@')) {
        return true;
      }
    }
    return false;
  }
}
