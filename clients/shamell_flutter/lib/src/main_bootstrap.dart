part of '../main.dart';

enum AppMode { auto, user, operator, admin }

const String _appModeRaw =
    String.fromEnvironment('APP_MODE', defaultValue: 'auto');
const bool _enableDesktopPush =
    bool.fromEnvironment('ENABLE_DESKTOP_PUSH', defaultValue: false);

bool _isPushSupportedPlatform() {
  if (kIsWeb) return true;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return isMobile || _enableDesktopPush;
}

AppMode get currentAppMode {
  switch (_appModeRaw.toLowerCase()) {
    case 'auto':
      return AppMode.auto;
    case 'operator':
      return AppMode.operator;
    case 'admin':
      return AppMode.admin;
    default:
      return AppMode.user;
  }
}

String appModeLabel(AppMode mode) {
  switch (mode) {
    case AppMode.operator:
      return 'Operator';
    case AppMode.admin:
      return 'Admin';
    case AppMode.auto:
      return 'Hybrid';
    case AppMode.user:
      return 'User';
  }
}

IconData appModeIcon(AppMode mode) {
  switch (mode) {
    case AppMode.operator:
      return Icons.support_agent;
    case AppMode.admin:
      return Icons.admin_panel_settings;
    case AppMode.user:
      return Icons.person_outline;
    case AppMode.auto:
      return Icons.all_inclusive;
  }
}

class _MiniOfficialUpdate {
  final String accountId;
  final String accountName;
  final String? avatarUrl;
  final String title;
  final DateTime ts;

  const _MiniOfficialUpdate({
    required this.accountId,
    required this.accountName,
    required this.avatarUrl,
    required this.title,
    required this.ts,
  });
}

class _RoleChip extends StatelessWidget {
  final AppMode mode;
  final AppMode current;
  final VoidCallback onTap;
  final bool enabled;
  const _RoleChip(
      {required this.mode,
      required this.current,
      required this.onTap,
      this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isSelected = mode == current;
    String label;
    if (l.isArabic) {
      switch (mode) {
        case AppMode.user:
          label = 'مستخدم';
          break;
        case AppMode.operator:
          label = 'مشغل';
          break;
        case AppMode.admin:
          label = 'مسؤول';
          break;
        case AppMode.auto:
          label = 'هجين';
          break;
      }
    } else {
      label = appModeLabel(mode);
    }
    final icon = appModeIcon(mode);
    final theme = Theme.of(context);
    final isDisabled = !enabled;
    // Distinct tint per mode when selected
    Color tint;
    switch (mode) {
      case AppMode.user:
        tint = theme.colorScheme.primary;
        break;
      case AppMode.operator:
        tint = theme.colorScheme.primary;
        break;
      case AppMode.admin:
        tint = theme.colorScheme.primary;
        break;
      case AppMode.auto:
        tint = theme.colorScheme.primary;
        break;
    }
    final bg = isSelected
        ? tint.withValues(alpha: .12)
        : theme.colorScheme.surface.withValues(alpha: isDisabled ? .4 : .9);
    Color fg;
    if (isDisabled) {
      fg = theme.colorScheme.onSurface.withValues(alpha: .40);
    } else {
      fg = theme.colorScheme.onSurface;
    }
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? tint
                    : theme.dividerColor.withValues(alpha: .6),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: fg))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuperadminChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  const _SuperadminChip(
      {required this.selected, required this.onTap, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = !enabled;
    final Color tint = theme.colorScheme.primary;
    final bg = selected
        ? tint.withValues(alpha: .12)
        : theme.colorScheme.surface.withValues(alpha: isDisabled ? .4 : .9);
    final fg = isDisabled
        ? theme.colorScheme.onSurface.withValues(alpha: .40)
        : theme.colorScheme.onSurface;
    return IconButton(
      style: IconButton.styleFrom(
        backgroundColor: bg,
      ),
      onPressed: enabled ? onTap : null,
      icon: Icon(
        Icons.security,
        size: 18,
        color: fg,
      ),
      tooltip: 'Superadmin',
    );
  }
}

class _DriverChip extends StatelessWidget {
  final VoidCallback onTap;
  final bool selected;
  const _DriverChip({required this.onTap, this.selected = false});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final label = l.isArabic ? 'سائق' : 'Driver';
    final icon = Icons.badge_outlined;
    final bg = selected
        ? Tokens.colorBus.withValues(alpha: .18)
        : theme.colorScheme.surface.withValues(alpha: .9);
    final fg =
        theme.brightness == Brightness.dark ? Colors.white : Colors.black87;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? Tokens.colorBus : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _isInDndWindow({
  required DateTime now,
  required int startMinutes,
  required int endMinutes,
}) {
  final cur = now.hour * 60 + now.minute;
  final start = startMinutes.clamp(0, 24 * 60 - 1);
  final end = endMinutes.clamp(0, 24 * 60 - 1);
  if (start == end) return true;
  if (start < end) return cur >= start && cur < end;
  return cur >= start || cur < end;
}

String _chatNotificationPayloadUri() =>
    Uri(scheme: 'shamell', host: 'chat').toString();

const String _kPendingNotificationPayload = 'ui.pending_notification_payload';

// Shamell-like "Plugins" visibility toggles (default: enabled).
const String _kShamellPluginShowMoments = 'shamell.plugins.show_moments';
const String _kShamellPluginShowChannels = 'shamell.plugins.show_channels';
const String _kShamellPluginShowScan = 'shamell.plugins.show_scan';
const String _kShamellPluginShowMiniPrograms =
    'shamell.plugins.show_mini_programs';
const String _kShamellPluginShowCardsOffers =
    'shamell.plugins.show_cards_offers';

Future<String> _loadStoredBaseUrl() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final storedBase = (sp.getString('base_url') ?? '').trim();
    if (storedBase.isNotEmpty) return storedBase;
  } catch (_) {}
  return const String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
}

Future<void> _handleNotificationPayload(String payload) async {
  final raw = payload.trim();
  if (raw.isEmpty) return;
  // If the user isn't logged in yet, store and let HomePage consume it after login.
  try {
    final cookie = await _getCookie();
    if (cookie == null || cookie.isEmpty) {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPendingNotificationPayload, raw);
      return;
    }
  } catch (_) {}

  Uri? uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    uri = null;
  }
  if (uri == null || uri.scheme.isEmpty) return;

  final baseUrl = await _loadStoredBaseUrl();
  final nav = _rootNavKey.currentState;
  if (nav == null) return;

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    await launchWithSession(uri);
    return;
  }

  if (scheme != 'shamell') return;

  final host = uri.host.toLowerCase();
  if (host == 'moments') {
    final postId = (uri.queryParameters['post_id'] ?? '').trim();
    final commentId = (uri.queryParameters['comment_id'] ?? '').trim();
    final focus = (uri.queryParameters['focus'] ?? '').trim().toLowerCase();
    final focusComments =
        focus == 'comments' || focus == 'thread' || focus == 'true';
    nav.push(
      MaterialPageRoute(
        builder: (_) => MomentsPage(
          baseUrl: baseUrl,
          initialPostId: postId.isNotEmpty ? postId : null,
          focusComments: focusComments || commentId.isNotEmpty,
          initialCommentId: commentId.isNotEmpty ? commentId : null,
        ),
      ),
    );
    return;
  }

  if (host == 'chat') {
    // Hardening: push/notifications must be wakeup-only. Never deep-link into
    // specific chats/messages/groups from notification payloads (even local).
    nav.push(
      MaterialPageRoute(
        builder: (_) => ShamellChatPage(
          baseUrl: baseUrl,
        ),
      ),
    );
    return;
  }

  if (host == 'official') {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return;
    final accountId = segs.first.trim();
    if (accountId.isEmpty) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => OfficialAccountDeepLinkPage(
          baseUrl: baseUrl,
          accountId: accountId,
          onOpenChat: (peerId) {
            if (peerId.isEmpty) return;
            _rootNavKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => ShamellChatPage(
                  baseUrl: baseUrl,
                  initialPeerId: peerId,
                ),
              ),
            );
          },
        ),
      ),
    );
    return;
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  // Ensure Firebase is initialised in background isolates
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  try {
    await NotificationService.initialize();
  } catch (_) {}

  try {
    final data = message.data;
    final rawType = (data['type'] ?? '').toString().trim().toLowerCase();
    if (rawType != 'chat_wakeup') return;

    final store = ChatLocalStore();
    final prefs = await store.loadNotifyConfig();
    if (!prefs.enabled) return;
    if (prefs.dnd &&
        _isInDndWindow(
          now: DateTime.now(),
          startMinutes: prefs.dndStart,
          endMinutes: prefs.dndEnd,
        )) {
      return;
    }

    final localeCode = PlatformDispatcher.instance.locale.languageCode;
    final isArabic = localeCode.toLowerCase().startsWith('ar');

    await NotificationService.showChatMessage(
      title: 'Shamell',
      body: isArabic ? 'لديك رسائل جديدة.' : 'You have new messages.',
      playSound: prefs.sound,
      vibrate: prefs.vibrate,
      deepLink: _chatNotificationPayloadUri(),
    );
  } catch (_) {}
}

final GlobalKey<NavigatorState> _rootNavKey = GlobalKey<NavigatorState>();

Future<void> _initPush() async {
  if (!_isPushSupportedPlatform()) {
    debugPrint('PUSH_INIT_SKIP: unsupported platform');
    return;
  }
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {}
  try {
    final perm = await FirebaseMessaging.instance.requestPermission();
    if (perm.authorizationStatus == AuthorizationStatus.authorized ||
        perm.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('fcm_token', token);
      }
      try {
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          try {
            final data = message.data;
            final rawType = (data['type'] ?? '').toString().trim().toLowerCase();
            if (rawType != 'chat_wakeup') return;
            // Push is wakeup-only: never deep-link to specific content from remote payloads.
            unawaited(_handleNotificationPayload(_chatNotificationPayloadUri()));
          } catch (_) {}
        });
      } catch (_) {}
    }
  } catch (_) {}
}

/// Launches a web URL and, for trusted same-origin HTTP(S) endpoints,
/// reuses the current Shamell session via embedded WebView cookies.
///
/// Session material is never appended to URL query parameters.
Future<void> launchWithSession(Uri uri) async {
  final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
  Uri? trustedBaseUri;
  bool injectSessionForSameOrigin = false;
  if (isHttp) {
    try {
      final storedBase = (await _loadStoredBaseUrl()).trim();
      final parsed = Uri.tryParse(storedBase);
      if (parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https')) {
        final sameHost = parsed.host.toLowerCase() == uri.host.toLowerCase();
        final sameScheme =
            parsed.scheme.toLowerCase() == uri.scheme.toLowerCase();
        final parsedPort = parsed.hasPort
            ? parsed.port
            : (parsed.scheme == 'https' ? 443 : 80);
        final uriPort =
            uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
        if (sameHost && sameScheme && parsedPort == uriPort) {
          trustedBaseUri = parsed;
          // webview_flutter can't set HttpOnly/Secure cookies; only allow
          // session bridging for localhost dev to avoid leaking bearer tokens
          // to JS in production WebViews.
          final host = parsed.host.toLowerCase();
          final isLocal = host == 'localhost' || host == '127.0.0.1' || host == '::1';
          injectSessionForSameOrigin = !kReleaseMode && isLocal;
        }
      }
    } catch (_) {
      trustedBaseUri = null;
      injectSessionForSameOrigin = false;
    }
  }
  try {
    if (!kIsWeb && isHttp && _rootNavKey.currentState != null) {
      // Best practice: only embed first-party web content. For other origins,
      // defer to the platform browser instead of an in-app WebView.
      if (trustedBaseUri == null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      _rootNavKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => ShamellWebViewPage(
            initialUri: uri,
            baseUri: trustedBaseUri,
            injectSessionForSameOrigin: injectSessionForSameOrigin,
          ),
        ),
      );
      return;
    }
  } catch (_) {}
  await launchUrl(uri);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initPush();
  // Offline background sync disabled
  try {
    await NotificationService.initialize();
    await NotificationService.requestAndroidPermission();
    NotificationService.setOnTapHandler(_handleNotificationPayload);
    final payload = await NotificationService.getLaunchPayload();
    if (payload != null && payload.trim().isNotEmpty) {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPendingNotificationPayload, payload.trim());
    }
  } catch (_) {}
  try {
    await OfflineQueue.init();
  } catch (_) {}
  Perf.init();
  await loadUiPrefs();
  runApp(
    MaterialApp(
      navigatorKey: _rootNavKey,
      home: const SuperApp(),
    ),
  );
}

void showBackoff(BuildContext context, http.Response resp) {
  try {
    final j = jsonDecode(resp.body);
    final ms = (j['retry_after_ms'] ?? 0) as int;
    final reasons = (j['reasons'] ?? []).toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Backoff: ${(ms / 1000).toStringAsFixed(0)}s  reasons: $reasons')));
  } catch (_) {
    final ra = resp.headers['retry-after'] ?? '?';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Backoff: Retry-After=$ra')));
  }
}

bool _hasOpsRole(List<String> roles) {
  // Treat any operator_* role as ops-capable plus classic admin/seller/ops.
  if (roles.any((r) => r == 'admin' || r == 'seller' || r == 'ops')) {
    return true;
  }
  return roles.any((r) => r.startsWith('operator_'));
}

bool _hasSuperadminRole(List<String> roles) {
  // Treat high‑risk / platform‑level roles as superadmin
  const superRoles = ['seller', 'ops'];
  return roles.any((r) => superRoles.contains(r));
}

bool _hasAdminRole(List<String> roles) {
  // Admins plus all superadmins
  if (_hasSuperadminRole(roles)) return true;
  return roles.contains('admin');
}

bool _computeShowOps(List<String> roles, AppMode mode) {
  final hasOps = _hasOpsRole(roles);
  switch (mode) {
    case AppMode.auto:
      return hasOps;
    case AppMode.user:
      return false;
    case AppMode.operator:
    case AppMode.admin:
      return hasOps;
  }
}
