part of '../main.dart';

enum AppMode { auto, user, operator, admin }

const String _appModeRaw =
    String.fromEnvironment('APP_MODE', defaultValue: 'auto');
const bool _envSkipLogin =
    bool.fromEnvironment('SKIP_LOGIN', defaultValue: false);
const String kSuperadminPhone = '+963996428955';

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
  final bool enabled;
  final bool selected;
  const _DriverChip(
      {required this.onTap, this.enabled = true, this.selected = false});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final label = l.isArabic ? 'سائق' : 'Driver';
    final icon = Icons.local_taxi;
    final isDisabled = !enabled;
    final bg = selected
        ? Tokens.colorTaxi.withValues(alpha: .18)
        : (isDisabled
            ? theme.colorScheme.surface.withValues(alpha: .4)
            : theme.colorScheme.surface.withValues(alpha: .9));
    final fg = isDisabled
        ? theme.colorScheme.onSurface.withValues(alpha: .40)
        : (theme.brightness == Brightness.dark ? Colors.white : Colors.black87);
    return Expanded(
      child: Semantics(
        button: true,
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
                color: selected ? Tokens.colorTaxi : Colors.white24,
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

String _chatNotificationPayloadUri({
  String? peerId,
  String? senderHint,
  String? groupId,
  String? messageId,
}) {
  final qp = <String, String>{};
  final pid = (peerId ?? '').trim();
  final hint = (senderHint ?? '').trim();
  final gid = (groupId ?? '').trim();
  final mid = (messageId ?? '').trim();
  if (pid.isNotEmpty) qp['peer_id'] = pid;
  if (hint.isNotEmpty) qp['sender_hint'] = hint;
  if (gid.isNotEmpty) qp['group_id'] = gid;
  if (mid.isNotEmpty) qp['mid'] = mid;
  return Uri(scheme: 'shamell', host: 'chat', queryParameters: qp).toString();
}

const String _kPendingNotificationPayload = 'ui.pending_notification_payload';

// WeChat-like "Plugins" visibility toggles (default: enabled).
const String _kWeChatPluginShowMoments = 'wechat.plugins.show_moments';
const String _kWeChatPluginShowChannels = 'wechat.plugins.show_channels';
const String _kWeChatPluginShowScan = 'wechat.plugins.show_scan';
const String _kWeChatPluginShowPeopleNearby =
    'wechat.plugins.show_people_nearby';
const String _kWeChatPluginShowMiniPrograms =
    'wechat.plugins.show_mini_programs';
const String _kWeChatPluginShowCardsOffers = 'wechat.plugins.show_cards_offers';
const String _kWeChatPluginShowStickers = 'wechat.plugins.show_stickers';

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
    final groupId = (uri.queryParameters['group_id'] ?? '').trim();
    final mid = (uri.queryParameters['mid'] ?? '').trim();
    if (groupId.isNotEmpty) {
      String groupName = groupId;
      try {
        final cached = await ChatLocalStore().loadGroupName(groupId);
        if (cached != null && cached.trim().isNotEmpty) {
          groupName = cached.trim();
        }
      } catch (_) {}
      nav.push(
        MaterialPageRoute(
          builder: (_) => GroupChatPage(
            baseUrl: baseUrl,
            groupId: groupId,
            groupName: groupName,
            initialMessageId: mid.isNotEmpty ? mid : null,
          ),
        ),
      );
      return;
    }

    String peerId = (uri.queryParameters['peer_id'] ?? '').trim();
    final senderHint = (uri.queryParameters['sender_hint'] ?? '').trim();
    if (peerId.isEmpty && senderHint.isNotEmpty) {
      try {
        final contacts = await ChatLocalStore().loadContacts();
        final match = contacts
            .where((c) => c.fingerprint == senderHint)
            .cast<ChatContact?>()
            .firstWhere((c) => c != null, orElse: () => null);
        if (match != null && match.id.trim().isNotEmpty) {
          peerId = match.id.trim();
        }
      } catch (_) {}
    }

    nav.push(
      MaterialPageRoute(
        builder: (_) => ThreemaChatPage(
          baseUrl: baseUrl,
          initialPeerId: peerId.isNotEmpty ? peerId : null,
          initialMessageId: mid.isNotEmpty ? mid : null,
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
                builder: (_) => ThreemaChatPage(
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
    final type = (data['type'] ?? '').toString();
    if (type != 'chat') return;

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

    final groupId = (data['group_id'] ?? data['groupId'] ?? '').toString();
    final groupName =
        (data['group_name'] ?? data['groupName'] ?? '').toString();
    final senderHint =
        (data['sender_hint'] ?? data['senderHint'] ?? '').toString();
    final senderId = (data['sender_id'] ?? data['senderId'] ?? '').toString();
    final mid = (data['mid'] ?? data['message_id'] ?? '').toString();

    String? resolvedGroupName;
    if (groupName.trim().isNotEmpty) {
      resolvedGroupName = groupName.trim();
    } else if (groupId.trim().isNotEmpty) {
      try {
        resolvedGroupName = await store.loadGroupName(groupId.trim());
      } catch (_) {}
    }

    String? groupSenderLabel;
    if (senderId.trim().isNotEmpty) {
      try {
        final contacts = await store.loadContacts();
        final match = contacts
            .where((c) => c.id.trim() == senderId.trim())
            .cast<ChatContact?>()
            .firstWhere((c) => c != null, orElse: () => null);
        final name = (match?.name ?? '').trim();
        groupSenderLabel = name.isNotEmpty ? name : senderId.trim();
      } catch (_) {
        groupSenderLabel = senderId.trim();
      }
    }

    String? resolvedPeerId;
    String? resolvedPeerName;
    if (senderHint.trim().isNotEmpty) {
      try {
        final contacts = await store.loadContacts();
        final match = contacts
            .where((c) => c.fingerprint == senderHint.trim())
            .cast<ChatContact?>()
            .firstWhere((c) => c != null, orElse: () => null);
        if (match != null && match.id.trim().isNotEmpty) {
          resolvedPeerId = match.id.trim();
          final name = (match.name ?? '').trim();
          if (name.isNotEmpty) {
            resolvedPeerName = name;
          }
        }
      } catch (_) {}
    }

    final title = () {
      if (groupId.trim().isNotEmpty) {
        if (resolvedGroupName != null && resolvedGroupName!.trim().isNotEmpty) {
          return resolvedGroupName!.trim();
        }
        return groupId.trim().isNotEmpty
            ? groupId.trim()
            : (isArabic ? 'رسالة مجموعة جديدة' : 'New group message');
      }
      if (resolvedPeerName != null && resolvedPeerName!.trim().isNotEmpty) {
        return resolvedPeerName!.trim();
      }
      if (resolvedPeerId != null && resolvedPeerId!.trim().isNotEmpty) {
        return resolvedPeerId!.trim();
      }
      return isArabic ? 'رسالة جديدة' : 'New message';
    }();

    final body = () {
      final noPreview = isArabic ? 'رسالة جديدة' : 'New message';
      if (!prefs.preview) return noPreview;
      if (groupId.trim().isNotEmpty) {
        if (groupSenderLabel != null && groupSenderLabel!.trim().isNotEmpty) {
          return isArabic
              ? '${groupSenderLabel!.trim()}: رسالة جديدة'
              : '${groupSenderLabel!.trim()}: New message';
        }
        return noPreview;
      }
      return isArabic ? 'لديك رسالة جديدة.' : 'You have a new message.';
    }();

    final payload = _chatNotificationPayloadUri(
      peerId: resolvedPeerId,
      senderHint: senderHint,
      groupId: groupId,
      messageId: mid,
    );

    await NotificationService.showChatMessage(
      title: title,
      body: body,
      playSound: prefs.sound,
      vibrate: prefs.vibrate,
      deepLink: payload,
    );
  } catch (_) {}
}

final GlobalKey<NavigatorState> _rootNavKey = GlobalKey<NavigatorState>();

Future<void> _initPush() async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {}
  try {
    final sp = await SharedPreferences.getInstance();
    final storedBase = sp.getString('base_url') ?? '';
    final baseUrl =
        storedBase.isNotEmpty ? storedBase : 'http://localhost:8081';
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
            final type = (data['type'] ?? '').toString();
            if (type == 'moments_comment' ||
                type == 'moments_post_like' ||
                type == 'moments_comment_like') {
              final postId = (data['post_id'] ?? '').toString();
              final commentId = (data['comment_id'] ?? '').toString();
              final focusComments =
                  type == 'moments_comment' || commentId.isNotEmpty;
              _rootNavKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => MomentsPage(
                    baseUrl: baseUrl,
                    initialPostId: postId.isNotEmpty ? postId : null,
                    focusComments: focusComments,
                    initialCommentId: commentId.isNotEmpty ? commentId : null,
                  ),
                ),
              );
            }
          } catch (_) {}
        });
      } catch (_) {}
    }
  } catch (_) {}
}

/// Launches a web URL and, for HTTP(S) endpoints, appends the current
/// Shamell session (`sa_session`) as query parameter when available.
///
/// This allows admin / superadmin web consoles to reuse the OTP login
/// from the Flutter app without relying on browser cookies.
Future<void> launchWithSession(Uri uri) async {
  try {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final cookie = await _getCookie();
      if (cookie != null && cookie.isNotEmpty) {
        String token = cookie;
        final m = RegExp(r'sa_session=([^;]+)').firstMatch(token);
        if (m != null && m.group(1) != null) {
          token = m.group(1)!;
        }
        if (token.isNotEmpty) {
          final qp = Map<String, String>.from(uri.queryParameters);
          qp.putIfAbsent('sa_session', () => token);
          uri = uri.replace(queryParameters: qp);
        }
      }
    }
  } catch (_) {
    // Fallback: ignore session wiring failures and just open the URL.
  }
  try {
    if (!kIsWeb &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        _rootNavKey.currentState != null) {
      _rootNavKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => WeChatWebViewPage(
            initialUri: uri,
            baseUri: Uri.tryParse(uri.origin),
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
  if (kPushProvider.toLowerCase() == 'gotify' ||
      kPushProvider.toLowerCase() == 'both') {
    try {
      await GotifyClient.start();
    } catch (_) {}
  }
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

bool _computeTaxiOnly(AppMode mode, List<String> operatorDomains) {
  if (mode != AppMode.operator) return false;
  if (operatorDomains.isEmpty) return false;
  // Taxi-only homescreen is only enabled when Taxi is the sole operator domain.
  return operatorDomains.contains('taxi') && operatorDomains.length == 1;
}
