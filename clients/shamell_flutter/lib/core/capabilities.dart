import 'package:shared_preferences/shared_preferences.dart';

/// Server-driven feature capabilities.
///
/// Best practice: fail-closed (capability defaults to off unless explicitly
/// enabled by the server). This prevents half-implemented modules from being
/// reachable and avoids confusing auth/404 UI errors.
class ShamellCapabilities {
  final bool chat;
  final bool payments;
  final bool bus;
  final bool friends;
  final bool moments;
  final bool officialAccounts;
  final bool channels;
  final bool miniPrograms;
  final bool serviceNotifications;
  final bool subscriptions;
  final bool paymentsPhoneTargets;

  const ShamellCapabilities({
    required this.chat,
    required this.payments,
    required this.bus,
    required this.friends,
    required this.moments,
    required this.officialAccounts,
    required this.channels,
    required this.miniPrograms,
    required this.serviceNotifications,
    required this.subscriptions,
    required this.paymentsPhoneTargets,
  });

  static const ShamellCapabilities conservativeDefaults = ShamellCapabilities(
    chat: true,
    payments: true,
    bus: true,
    friends: false,
    moments: false,
    officialAccounts: false,
    channels: false,
    miniPrograms: false,
    serviceNotifications: false,
    subscriptions: false,
    paymentsPhoneTargets: false,
  );

  // SharedPreferences keys (persisted per install).
  static const String kChat = 'cap.chat';
  static const String kPayments = 'cap.payments';
  static const String kBus = 'cap.bus';
  static const String kFriends = 'cap.friends';
  static const String kMoments = 'cap.moments';
  static const String kOfficialAccounts = 'cap.official_accounts';
  static const String kChannels = 'cap.channels';
  static const String kMiniPrograms = 'cap.mini_programs';
  static const String kServiceNotifications = 'cap.service_notifications';
  static const String kSubscriptions = 'cap.subscriptions';
  static const String kPaymentsPhoneTargets = 'cap.payments_phone_targets';

  static String _originForBaseUrl(String baseUrl) {
    final raw = baseUrl.trim();
    final u = Uri.tryParse(raw);
    if (u == null) return 'unknown';
    final scheme = (u.scheme.isNotEmpty ? u.scheme : 'http').toLowerCase();
    final host = (u.host.isNotEmpty ? u.host : u.path).trim().toLowerCase();
    if (host.isEmpty) return 'unknown';
    final defaultPort = scheme == 'https' ? 443 : scheme == 'http' ? 80 : null;
    final hasPort = u.hasPort;
    final port = hasPort ? u.port : null;
    final includePort = port != null && (defaultPort == null || port != defaultPort);
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
  static ShamellCapabilities fromPrefsForBaseUrl(
    SharedPreferences sp,
    String baseUrl,
  ) {
    final d = conservativeDefaults;
    bool read(String key, bool fallback) {
      final v = sp.getBool(_scopedKey(baseUrl, key));
      return v ?? fallback;
    }

    return ShamellCapabilities(
      chat: read(kChat, d.chat),
      payments: read(kPayments, d.payments),
      bus: read(kBus, d.bus),
      friends: read(kFriends, d.friends),
      moments: read(kMoments, d.moments),
      officialAccounts: read(kOfficialAccounts, d.officialAccounts),
      channels: read(kChannels, d.channels),
      miniPrograms: read(kMiniPrograms, d.miniPrograms),
      serviceNotifications: read(kServiceNotifications, d.serviceNotifications),
      subscriptions: read(kSubscriptions, d.subscriptions),
      // Permanently disabled: never route payments by phone number.
      paymentsPhoneTargets: false,
    );
  }

  static ShamellCapabilities fromPrefs(SharedPreferences sp) {
    final d = conservativeDefaults;
    return ShamellCapabilities(
      chat: sp.getBool(kChat) ?? d.chat,
      payments: sp.getBool(kPayments) ?? d.payments,
      bus: sp.getBool(kBus) ?? d.bus,
      friends: sp.getBool(kFriends) ?? d.friends,
      moments: sp.getBool(kMoments) ?? d.moments,
      officialAccounts: sp.getBool(kOfficialAccounts) ?? d.officialAccounts,
      channels: sp.getBool(kChannels) ?? d.channels,
      miniPrograms: sp.getBool(kMiniPrograms) ?? d.miniPrograms,
      serviceNotifications:
          sp.getBool(kServiceNotifications) ?? d.serviceNotifications,
      subscriptions: sp.getBool(kSubscriptions) ?? d.subscriptions,
      // Permanently disabled: never route payments by phone number, even if a
      // stale preference or server response tries to enable it.
      paymentsPhoneTargets: false,
    );
  }

  Future<void> persistForBaseUrl(SharedPreferences sp, String baseUrl) async {
    await sp.setBool(_scopedKey(baseUrl, kChat), chat);
    await sp.setBool(_scopedKey(baseUrl, kPayments), payments);
    await sp.setBool(_scopedKey(baseUrl, kBus), bus);
    await sp.setBool(_scopedKey(baseUrl, kFriends), friends);
    await sp.setBool(_scopedKey(baseUrl, kMoments), moments);
    await sp.setBool(_scopedKey(baseUrl, kOfficialAccounts), officialAccounts);
    await sp.setBool(_scopedKey(baseUrl, kChannels), channels);
    await sp.setBool(_scopedKey(baseUrl, kMiniPrograms), miniPrograms);
    await sp.setBool(
        _scopedKey(baseUrl, kServiceNotifications), serviceNotifications);
    await sp.setBool(_scopedKey(baseUrl, kSubscriptions), subscriptions);
    // Keep the key for backwards compatibility, but always store "false".
    await sp.setBool(_scopedKey(baseUrl, kPaymentsPhoneTargets), false);
  }

  Future<void> persist(SharedPreferences sp) async {
    await sp.setBool(kChat, chat);
    await sp.setBool(kPayments, payments);
    await sp.setBool(kBus, bus);
    await sp.setBool(kFriends, friends);
    await sp.setBool(kMoments, moments);
    await sp.setBool(kOfficialAccounts, officialAccounts);
    await sp.setBool(kChannels, channels);
    await sp.setBool(kMiniPrograms, miniPrograms);
    await sp.setBool(kServiceNotifications, serviceNotifications);
    await sp.setBool(kSubscriptions, subscriptions);
    // Keep the key for backwards compatibility, but always store "false".
    await sp.setBool(kPaymentsPhoneTargets, false);
  }

  /// Merges a capabilities JSON object into a baseline, falling back to baseline
  /// values for any missing keys.
  static ShamellCapabilities mergeJson(
      dynamic capsJson, ShamellCapabilities base) {
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

    return ShamellCapabilities(
      chat: read('chat', base.chat),
      payments: read('payments', base.payments),
      bus: read('bus', base.bus),
      friends: read('friends', base.friends),
      moments: read('moments', base.moments),
      officialAccounts: read('official_accounts', base.officialAccounts),
      channels: read('channels', base.channels),
      miniPrograms: read('mini_programs', base.miniPrograms),
      serviceNotifications:
          read('service_notifications', base.serviceNotifications),
      subscriptions: read('subscriptions', base.subscriptions),
      // Permanently disabled: never route payments by phone number.
      paymentsPhoneTargets: false,
    );
  }
}
