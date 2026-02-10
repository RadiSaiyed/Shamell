part of '../main.dart';

class HomePage extends StatefulWidget {
  final AppMode lockedMode;
  const HomePage({super.key, this.lockedMode = AppMode.auto});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _baseUrl = const String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  // WeChat-like bottom navigation tabs:
  // 0 = Chats, 1 = Contacts, 2 = Discover/Services, 3 = Me.
  int _tabIndex = 0;
  bool _wechatStrictUi = true;
  bool _pluginShowMoments = true;
  bool _pluginShowChannels = true;
  bool _pluginShowScan = true;
  bool _pluginShowPeopleNearby = true;
  bool _pluginShowMiniPrograms = true;
  bool _pluginShowCardsOffers = true;
  bool _pluginShowStickers = true;
  String _walletId = '';
  int? _walletBalanceCents;
  String _walletCurrency = 'SYP';
  bool _walletHidden = false;
  bool _walletLoading = false;
  final deviceId = _randId();
  Timer? _flushTimer;
  bool _showOps = false;
  bool _showSuperadmin = false;
  List<String> _roles = const [];
  List<String> _operatorDomains = const [];
  AppMode _appMode = currentAppMode;
  List<String> _recentModules = const [];
  List<String> _pinnedMiniApps = const [];
  List<String> _pinnedMiniProgramsOrder = const [];
  List<String> _recentMiniPrograms = const [];
  Set<String> _miniProgramsUpdateBadgeIds = <String>{};
  final ChatLocalStore _chatStore = ChatLocalStore();
  int _totalUnreadChats = 0;
  bool _officialStripLoading = false;
  List<OfficialAccountHandle> _officialStripAccounts =
      const <OfficialAccountHandle>[];
  String? _officialStripCityLabel;
  final Map<String, String> _officialStripLatestTs = <String, String>{};
  bool _hasUnreadOfficialFeeds = false;
  int _unreadOfficialAccounts = 0;
  List<OfficialAccountHandle> _followedOfficialsPreview =
      const <OfficialAccountHandle>[];
  List<_MiniOfficialUpdate> _latestOfficialUpdates =
      const <_MiniOfficialUpdate>[];
  int _followedServiceCount = 0;
  int _followedSubscriptionCount = 0;
  // Bus admin summary for quick dashboard
  int? _busTripsToday;
  int? _busBookingsToday;
  int? _busRevenueTodayCents;
  CallSignalingClient? _callClient;
  StreamSubscription<Map<String, dynamic>>? _callSub;
  bool _hasUnreadMoments = false;
  int _redpacketMoments30d = 0;
  int _officialServiceMoments = 0;
  int _officialSubscriptionMoments = 0;
  int _officialHotAccounts = 0;
  List<String> _trendingTopicsShort = const <String>[];
  List<Map<String, dynamic>> _trendingMiniPrograms =
      const <Map<String, dynamic>>[];
  String _trendingMiniProgramsSig = '';
  bool _hasNewTrendingMiniPrograms = false;
  int _miniProgramsCount = 0;
  int _miniProgramsTotalUsage = 0;
  int _miniProgramsMoments30d = 0;
  bool _hasDefaultOfficialAccount = false;
  bool _hasUnreadServiceNotifications = false;
  int _friendsCount = 0;
  int _closeFriendsCount = 0;
  int _friendRequestsPending = 0;
  bool _contactsRosterLoading = false;
  String? _contactsRosterError;
  List<Map<String, dynamic>> _contactsRoster = const <Map<String, dynamic>>[];
  Map<String, String> _contactsAliases = const <String, String>{};
  Map<String, String> _contactsTags = const <String, String>{};
  final ScrollController _contactsScrollCtrl = ScrollController();
  final GlobalKey _contactsViewportKey = GlobalKey();
  final Map<String, GlobalKey> _contactsLetterKeys = <String, GlobalKey>{};
  Timer? _contactsIndexHintTimer;
  String? _contactsIndexHint;
  bool _contactsIndexDragging = false;
  String? _contactsStickyHeader;
  double _contactsStickyHeaderOffset = 0.0;
  String _profileName = '';
  String _profilePhone = '';
  String _profileShamellId = '';

  static String _randId() {
    const chars = 'abcdef0123456789';
    final r = Random();
    return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _registerDeviceBestEffort() async {
    try {
      final uri = Uri.parse('$_baseUrl/auth/devices/register');
      final headers = await _hdr(json: true);
      // Stable per-install device id: supports server-side session revocation
      // and keeps device lists consistent across restarts/logouts.
      final did = await getOrCreateStableDeviceId();
      final body = jsonEncode(<String, dynamic>{
        'device_id': did,
        'device_type': kIsWeb ? 'web' : 'mobile',
        'platform': Theme.of(context).platform.name,
      });
      unawaited(http.post(uri, headers: headers, body: body));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // offline sync timer disabled
    _setupLinks();
    unawaited(_consumePendingNotificationPayload());
    _flushTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      await OfflineQueue.flush();
    });
    _registerDeviceBestEffort();
    _loadUnreadBadge();
    _initCallSignaling();
    _loadOfficialStrip();
    _loadMomentsNotifications();
    _loadOfficialMomentsStats();
    _loadTrendingTopicsShort();
    _loadTrendingMiniPrograms();
    _loadMiniProgramDeveloperStats();
    _loadDefaultOfficialAccountFlag();
    _loadFriendsSummary();
    unawaited(_loadContactsRosterMeta());
    unawaited(_loadContactsRoster());
    _loadServiceNotificationsBadge();
    _contactsScrollCtrl.addListener(_updateContactsStickyHeader);
  }

  Future<void> _consumePendingNotificationPayload() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final payload = (sp.getString(_kPendingNotificationPayload) ?? '').trim();
      if (payload.isEmpty) return;
      await sp.remove(_kPendingNotificationPayload);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_handleNotificationPayload(payload));
      });
    } catch (_) {}
  }

  Future<void> _loadFriendsSummary() async {
    try {
      int friends = 0;
      int closeFriends = 0;
      int pendingRequests = 0;
      // Friends
      try {
        final uri = Uri.parse('$_baseUrl/me/friends');
        final r = await http.get(uri, headers: await _hdr());
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          List<dynamic>? arr;
          if (decoded is Map && decoded['friends'] is List) {
            arr = decoded['friends'] as List;
          } else if (decoded is List) {
            arr = decoded;
          }
          if (arr != null) {
            friends = arr.length;
          }
        }
      } catch (_) {}
      // Close friends
      try {
        final uri = Uri.parse('$_baseUrl/me/close_friends');
        final r = await http.get(uri, headers: await _hdr());
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          List<dynamic>? arr;
          if (decoded is Map && decoded['friends'] is List) {
            arr = decoded['friends'] as List;
          } else if (decoded is List) {
            arr = decoded;
          }
          if (arr != null) {
            closeFriends = arr.length;
          }
        }
      } catch (_) {}
      // Pending friend requests (incoming only)
      try {
        final uri = Uri.parse('$_baseUrl/me/friend_requests');
        final r = await http.get(uri, headers: await _hdr());
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          List<dynamic>? arr;
          if (decoded is Map && decoded['incoming'] is List) {
            arr = decoded['incoming'] as List;
          } else if (decoded is List) {
            arr = decoded;
          }
          if (arr != null) {
            pendingRequests = arr.length;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _friendsCount = friends;
        _closeFriendsCount = closeFriends;
        _friendRequestsPending = pendingRequests;
      });
    } catch (_) {}
  }

  Future<void> _loadContactsRosterMeta() async {
    try {
      final sp = await SharedPreferences.getInstance();

      Map<String, String> decodeMap(String raw) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final map = <String, String>{};
            decoded.forEach((k, v) {
              final key = (k ?? '').toString().trim();
              final val = (v ?? '').toString().trim();
              if (key.isNotEmpty && val.isNotEmpty) {
                map[key] = val;
              }
            });
            return map;
          }
        } catch (_) {}
        return const <String, String>{};
      }

      final aliases = decodeMap(sp.getString('friends.aliases') ?? '{}');
      final tags = decodeMap(sp.getString('friends.tags') ?? '{}');
      if (!mounted) return;
      setState(() {
        _contactsAliases = aliases;
        _contactsTags = tags;
      });
    } catch (_) {}
  }

  Future<void> _loadContactsRoster({bool force = false}) async {
    if (_contactsRosterLoading) return;
    if (!force && _contactsRoster.isNotEmpty) return;
    setState(() {
      _contactsRosterLoading = true;
      _contactsRosterError = null;
    });
    try {
      final uri = Uri.parse('$_baseUrl/me/friends');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        List<dynamic>? arr;
        if (decoded is Map && decoded['friends'] is List) {
          arr = decoded['friends'] as List;
        } else if (decoded is List) {
          arr = decoded;
        }
        final list = (arr ?? const <dynamic>[])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        if (!mounted) return;
        setState(() {
          _contactsRoster = list;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _contactsRosterError = 'HTTP ${r.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contactsRosterError = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _contactsRosterLoading = false;
        });
      }
    }
  }

  Future<void> _loadDefaultOfficialAccountFlag() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final accId = sp.getString('official.default_account_id') ?? '';
      if (!mounted) return;
      setState(() {
        _hasDefaultOfficialAccount = accId.isNotEmpty;
      });
    } catch (_) {}
  }

  Future<void> _initCallSignaling() async {
    try {
      final devId = await CallSignalingClient.loadDeviceId();
      if (!mounted) return;
      if (devId == null || devId.isEmpty) {
        return;
      }
      final client = CallSignalingClient(_baseUrl);
      final stream = client.connect(deviceId: devId);
      _callClient = client;
      _callSub = stream.listen(_handleCallSignal);
    } catch (_) {
      // Call signaling is best-effort; ignore failures here.
    }
  }

  void _handleCallSignal(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = (msg['type'] ?? '').toString();
    if (type != 'invite') return;
    final callId = (msg['call_id'] ?? '').toString();
    final from = (msg['from'] ?? '').toString();
    if (callId.isEmpty || from.isEmpty) return;
    final modeRaw = (msg['mode'] ?? '').toString().trim().toLowerCase();
    final mode = (modeRaw == 'audio' || modeRaw == 'video') ? modeRaw : 'video';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IncomingCallPage(
          baseUrl: _baseUrl,
          callId: callId,
          fromDeviceId: from,
          mode: mode,
        ),
      ),
    );
  }

  Future<void> _ensureServiceOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) async {
    if (officialId.isEmpty || chatPeerId.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final followKey = 'official.autofollow.$officialId';
      final alreadyFollowed = sp.getBool(followKey) ?? false;
      var justFollowed = false;
      if (!alreadyFollowed) {
        final uri = Uri.parse('$_baseUrl/official_accounts/$officialId/follow');
        final r = await http.post(uri, headers: await _hdr(json: true));
        if (r.statusCode >= 200 && r.statusCode < 300) {
          await sp.setBool(followKey, true);
          justFollowed = true;
        } else {
          // Do not mark as done; try again on next use.
          return;
        }
      }
      // Optionally ensure a chat contact exists for this service account.
      final chatKey = 'official.autochat.$chatPeerId';
      final alreadyLinked = sp.getBool(chatKey) ?? false;
      if (alreadyLinked) return;
      final me = await _chatStore.loadIdentity();
      if (me == null) return;
      final svc = ChatService(_baseUrl);
      ChatContact peer;
      try {
        peer = await svc.resolveDevice(chatPeerId);
      } catch (_) {
        return;
      }
      final contacts = await _chatStore.loadContacts();
      final exists = contacts.any((c) => c.id == peer.id);
      if (!exists) {
        final updated = <ChatContact>[...contacts, peer];
        await _chatStore.saveContacts(updated);
      }
      await sp.setBool(chatKey, true);
      if (justFollowed && mounted) {
        final l = L10n.of(context);
        final msg = l.isArabic
            ? 'تمت متابعة الحساب الرسمي للخدمة تلقائياً.'
            : 'You now follow the service official account.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
          ),
        );
      }
    } catch (_) {}
  }

  void _openOfficialFromStrip(OfficialAccountHandle acc) {
    _navPush(
      OfficialAccountFeedPage(
        baseUrl: _baseUrl,
        account: acc,
        onOpenChat: (peerId) {
          if (peerId.isEmpty) return;
          _navPush(
            ThreemaChatPage(
              baseUrl: _baseUrl,
              initialPeerId: peerId,
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadOfficialStrip() async {
    if (_officialStripLoading || _officialStripAccounts.isNotEmpty) {
      return;
    }
    setState(() {
      _officialStripLoading = true;
    });
    try {
      final miniUpdates = <_MiniOfficialUpdate>[];
      final uri = Uri.parse('$_baseUrl/official_accounts')
          .replace(queryParameters: const {'followed_only': 'false'});
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        final list = <OfficialAccountHandle>[];
        final latestTs = <String, String>{};
        Map<String, dynamic> seenMap = const {};
        try {
          final sp = await SharedPreferences.getInstance();
          final rawSeen = sp.getString('official.feed_seen') ?? '{}';
          final decSeen = jsonDecode(rawSeen);
          if (decSeen is Map<String, dynamic>) {
            seenMap = decSeen;
          }
        } catch (_) {}
        bool hasUnread = false;
        if (decoded is Map && decoded['accounts'] is List) {
          for (final e in decoded['accounts'] as List) {
            if (e is Map) {
              final m = e.cast<String, dynamic>();
              list.add(OfficialAccountHandle.fromJson(m));
              final accId = (m['id'] ?? '').toString();
              final name = (m['name'] ?? '').toString();
              final avatar = (m['avatar_url'] ?? '').toString().isEmpty
                  ? null
                  : (m['avatar_url'] ?? '').toString();
              final isFollowed = (m['followed'] as bool?) ?? false;
              String? lastTs;
              String? lastTitle;
              if (m['last_item'] is Map) {
                final lm = m['last_item'] as Map;
                final rawTs = (lm['ts'] ?? '').toString();
                if (rawTs.isNotEmpty) {
                  lastTs = rawTs;
                }
                final rawTitle = (lm['title'] ?? '').toString();
                if (rawTitle.isNotEmpty) {
                  lastTitle = rawTitle;
                }
              }
              if (accId.isNotEmpty && lastTs != null && lastTs.isNotEmpty) {
                latestTs[accId] = lastTs;
                if (!hasUnread) {
                  final seenRaw = (seenMap[accId] ?? '').toString();
                  if (seenRaw.isEmpty) {
                    hasUnread = true;
                  } else {
                    try {
                      final last = DateTime.parse(lastTs);
                      final seen = DateTime.parse(seenRaw);
                      if (last.isAfter(seen)) {
                        hasUnread = true;
                      }
                    } catch (_) {}
                  }
                }
                if (isFollowed) {
                  try {
                    final dt = DateTime.parse(lastTs);
                    final title =
                        (lastTitle ?? '').isNotEmpty ? lastTitle! : name;
                    miniUpdates.add(
                      _MiniOfficialUpdate(
                        accountId: accId,
                        accountName: name,
                        avatarUrl: avatar,
                        title: title,
                        ts: dt,
                      ),
                    );
                  } catch (_) {}
                }
              }
            }
          }
        } else if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              final m = e.cast<String, dynamic>();
              list.add(OfficialAccountHandle.fromJson(m));
              final accId = (m['id'] ?? '').toString();
              final name = (m['name'] ?? '').toString();
              final avatar = (m['avatar_url'] ?? '').toString().isEmpty
                  ? null
                  : (m['avatar_url'] ?? '').toString();
              final isFollowed = (m['followed'] as bool?) ?? false;
              String? lastTs;
              String? lastTitle;
              if (m['last_item'] is Map) {
                final lm = m['last_item'] as Map;
                final rawTs = (lm['ts'] ?? '').toString();
                if (rawTs.isNotEmpty) {
                  lastTs = rawTs;
                }
                final rawTitle = (lm['title'] ?? '').toString();
                if (rawTitle.isNotEmpty) {
                  lastTitle = rawTitle;
                }
              }
              if (accId.isNotEmpty && lastTs != null && lastTs.isNotEmpty) {
                latestTs[accId] = lastTs;
                if (!hasUnread) {
                  final seenRaw = (seenMap[accId] ?? '').toString();
                  if (seenRaw.isEmpty) {
                    hasUnread = true;
                  } else {
                    try {
                      final last = DateTime.parse(lastTs);
                      final seen = DateTime.parse(seenRaw);
                      if (last.isAfter(seen)) {
                        hasUnread = true;
                      }
                    } catch (_) {}
                  }
                }
                if (isFollowed) {
                  try {
                    final dt = DateTime.parse(lastTs);
                    final title =
                        (lastTitle ?? '').isNotEmpty ? lastTitle! : name;
                    miniUpdates.add(
                      _MiniOfficialUpdate(
                        accountId: accId,
                        accountName: name,
                        avatarUrl: avatar,
                        title: title,
                        ts: dt,
                      ),
                    );
                  } catch (_) {}
                }
              }
            }
          }
        }
        // Pick a simple "recommended city" based on most common city among accounts.
        String? cityKey;
        String? cityLabel;
        final counts = <String, int>{};
        final labels = <String, String>{};
        for (final a in list) {
          final c = (a.city ?? '').trim();
          if (c.isEmpty) continue;
          final key = c.toLowerCase();
          counts[key] = (counts[key] ?? 0) + 1;
          labels.putIfAbsent(key, () => c);
        }
        if (counts.isNotEmpty) {
          String bestKey = counts.keys.first;
          var bestCount = counts[bestKey] ?? 0;
          counts.forEach((k, v) {
            if (v > bestCount) {
              bestKey = k;
              bestCount = v;
            }
          });
          cityKey = bestKey;
          cityLabel = labels[bestKey] ?? '';
        }
        List<OfficialAccountHandle> recommended = list;
        final followed = list.where((a) => a.followed).toList();
        final followedService =
            followed.where((a) => (a.kind).toLowerCase() == 'service').toList();
        final followedSubscription =
            followed.where((a) => (a.kind).toLowerCase() != 'service').toList();
        if (cityKey != null && cityKey.isNotEmpty) {
          final byCity = list
              .where((a) => (a.city ?? '').trim().toLowerCase() == cityKey)
              .toList();
          if (byCity.isNotEmpty) {
            recommended = byCity;
          }
        }
        if (recommended.length > 8) {
          recommended = recommended.sublist(0, 8);
        }
        miniUpdates.sort((a, b) => b.ts.compareTo(a.ts));
        List<_MiniOfficialUpdate> latest = miniUpdates;
        if (latest.length > 3) {
          latest = latest.sublist(0, 3);
        }
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString(
            'official.strip_city_label',
            cityLabel ?? '',
          );
        } catch (_) {}
        setState(() {
          _officialStripAccounts = recommended;
          _officialStripCityLabel =
              (cityLabel != null && cityLabel.isNotEmpty) ? cityLabel : null;
          _officialStripLatestTs
            ..clear()
            ..addAll(latestTs);
          _hasUnreadOfficialFeeds = hasUnread;
          _followedServiceCount = followedService.length;
          _followedSubscriptionCount = followedSubscription.length;
          _latestOfficialUpdates = latest;
          if (followed.isNotEmpty) {
            final starred = followed.where((a) => a.featured).toList();
            final others = followed.where((a) => !a.featured).toList();
            starred.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            others.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            final merged = <OfficialAccountHandle>[...starred, ...others];
            if (merged.length > 8) {
              _followedOfficialsPreview = merged.sublist(0, 8);
            } else {
              _followedOfficialsPreview = merged;
            }
          } else {
            _followedOfficialsPreview = const <OfficialAccountHandle>[];
          }
        });
      } else {
        // Soft-fail; Discover tab works without official strip.
      }
    } catch (e) {
      // Ignore errors; strip is optional.
    } finally {
      if (mounted) {
        setState(() {
          _officialStripLoading = false;
        });
      }
    }
  }

  Future<void> _openOfficialNotifications() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    Perf.action('official_open_notifications_sheet');
    // Preload official accounts once so we can apply modes per group without refetching.
    final accounts = <Map<String, dynamic>>[];
    try {
      final uri = Uri.parse('$_baseUrl/official_accounts')
          .replace(queryParameters: const {'followed_only': 'false'});
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        List<dynamic> raw = const [];
        if (decoded is Map && decoded['accounts'] is List) {
          raw = decoded['accounts'] as List;
        } else if (decoded is List) {
          raw = decoded;
        }
        for (final e in raw) {
          if (e is Map) {
            accounts.add(e.cast<String, dynamic>());
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;

    Future<void> applyGroupMode(
      String group,
      OfficialNotificationMode mode,
    ) async {
      if (accounts.isEmpty) return;
      try {
        final contacts = await _chatStore.loadContacts();
        final byId = {for (final c in contacts) c.id: c};
        final updatedContacts = List<ChatContact>.from(contacts);
        var changedContacts = false;
        final modeStr = switch (mode) {
          OfficialNotificationMode.full => 'full',
          OfficialNotificationMode.summary => 'summary',
          OfficialNotificationMode.muted => 'muted',
        };
        for (final m in accounts) {
          final kindStr = (m['kind'] ?? 'service').toString().toLowerCase();
          final peerId = (m['chat_peer_id'] ?? '').toString().trim();
          if (peerId.isEmpty) continue;
          final isService = kindStr == 'service';
          if (group == 'service' && !isService) continue;
          if (group == 'subscription' && isService) continue;
          await _chatStore.setOfficialNotifMode(peerId, mode);
          final existing = byId[peerId];
          if (existing != null) {
            final shouldMute = mode == OfficialNotificationMode.muted;
            if (existing.muted != shouldMute) {
              final idx = updatedContacts.indexWhere((c) => c.id == peerId);
              if (idx != -1) {
                updatedContacts[idx] = existing.copyWith(muted: shouldMute);
                changedContacts = true;
              }
            }
          }
          // Best-effort sync to server per account.
          final accId = (m['id'] ?? '').toString();
          if (accId.isNotEmpty) {
            try {
              final uri = Uri.parse(
                  '$_baseUrl/official_accounts/$accId/notification_mode');
              final body = jsonEncode({'mode': modeStr});
              await http.post(uri, headers: await _hdr(json: true), body: body);
            } catch (_) {}
          }
        }
        if (changedContacts) {
          await _chatStore.saveContacts(updatedContacts);
        }
      } catch (_) {}
    }

    OfficialNotificationMode serviceMode = OfficialNotificationMode.full;
    OfficialNotificationMode subscriptionMode = OfficialNotificationMode.full;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: StatefulBuilder(
              builder: (ctx, setModalState) {
                return SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.notifications_none_outlined,
                        ),
                        title: Text(
                          l.isArabic
                              ? 'إشعارات الحسابات الرسمية'
                              : 'Official account notifications',
                        ),
                        subtitle: Text(
                          l.isArabic
                              ? 'تغيير وضع الإشعارات لكل حسابات الخدمات والاشتراك'
                              : 'Change notification mode for all service and subscription accounts',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(
                          l.isArabic ? 'حسابات الخدمات' : 'Service accounts',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      RadioGroup<OfficialNotificationMode>(
                        groupValue: serviceMode,
                        onChanged: (mode) async {
                          if (mode == null) return;
                          setModalState(() => serviceMode = mode);
                          await applyGroupMode('service', mode);
                          Perf.action(
                            switch (mode) {
                              OfficialNotificationMode.full =>
                                'official_notifications_service_full',
                              OfficialNotificationMode.summary =>
                                'official_notifications_service_summary',
                              OfficialNotificationMode.muted =>
                                'official_notifications_service_muted',
                            },
                          );
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.full,
                              title: Text(
                                l.isArabic
                                    ? 'إظهار معاينة الرسائل'
                                    : 'Show message preview',
                              ),
                            ),
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.summary,
                              title: Text(
                                l.isArabic
                                    ? 'إخفاء محتوى الرسائل'
                                    : 'Hide message content',
                              ),
                            ),
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.muted,
                              title: Text(
                                l.isArabic
                                    ? 'كتم الإشعارات'
                                    : 'Mute notifications',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(
                          l.isArabic
                              ? 'حسابات الاشتراك'
                              : 'Subscription accounts',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      RadioGroup<OfficialNotificationMode>(
                        groupValue: subscriptionMode,
                        onChanged: (mode) async {
                          if (mode == null) return;
                          setModalState(() => subscriptionMode = mode);
                          await applyGroupMode('subscription', mode);
                          Perf.action(
                            switch (mode) {
                              OfficialNotificationMode.full =>
                                'official_notifications_subscription_full',
                              OfficialNotificationMode.summary =>
                                'official_notifications_subscription_summary',
                              OfficialNotificationMode.muted =>
                                'official_notifications_subscription_muted',
                            },
                          );
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.full,
                              title: Text(
                                l.isArabic
                                    ? 'إظهار معاينة الرسائل'
                                    : 'Show message preview',
                              ),
                            ),
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.summary,
                              title: Text(
                                l.isArabic
                                    ? 'إخفاء محتوى الرسائل'
                                    : 'Hide message content',
                              ),
                            ),
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.muted,
                              title: Text(
                                l.isArabic
                                    ? 'كتم الإشعارات'
                                    : 'Mute notifications',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    String _homeTitle() {
      switch (_tabIndex) {
        case 0:
          return l.mirsaalTabChats;
        case 1:
          return l.mirsaalTabContacts;
        case 2:
          return l.isArabic ? 'استكشاف' : 'Discover';
        case 3:
          return l.isArabic ? 'أنا' : 'Me';
        default:
          return l.appTitle;
      }
    }

    return Scaffold(
      // Chats tab is a full-page chat shell (it has its own AppBar with
      // WeChat-style actions), so avoid rendering a second AppBar here.
      appBar: _tabIndex == 0
          ? null
          : AppBar(
              title: Text(_homeTitle()),
              actions: [
                if (_tabIndex == 1)
                  PopupMenuButton<String>(
                    tooltip: l.isArabic ? 'إضافة' : 'Add',
                    icon: const Icon(Icons.add_circle_outline),
                    onSelected: (value) {
                      switch (value) {
                        case 'add_friend':
                          _navPush(
                            FriendsPage(
                              _baseUrl,
                              mode: FriendsPageMode.newFriends,
                            ),
                          );
                          return;
                        case 'scan':
                          unawaited(_openWeChatScanAndHandle());
                          return;
                        case 'help':
                          _openOnboarding();
                          return;
                      }
                    },
                    itemBuilder: (ctx) {
                      Widget item(IconData icon, String label) {
                        return Row(
                          children: [
                            Icon(icon, size: 18),
                            const SizedBox(width: 10),
                            Text(label),
                          ],
                        );
                      }

                      return [
                        PopupMenuItem<String>(
                          value: 'add_friend',
                          child: item(
                            Icons.person_add_alt_1_outlined,
                            l.isArabic ? 'إضافة صديق' : 'Add friend',
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'scan',
                          child: item(
                            Icons.qr_code_scanner,
                            l.isArabic ? 'مسح' : 'Scan',
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        PopupMenuItem<String>(
                          value: 'help',
                          child: item(
                            Icons.help_outline,
                            l.isArabic ? 'مساعدة' : 'Help',
                          ),
                        ),
                      ];
                    },
                  ),
                if (_tabIndex == 2)
                  IconButton(
                    onPressed: _openGlobalSearch,
                    tooltip: l.isArabic ? 'بحث' : 'Search',
                    icon: const Icon(Icons.search),
                  ),
                if (_tabIndex == 3)
                  IconButton(
                    onPressed: () {
                      _openWeChatSettings();
                    },
                    tooltip: l.settingsTitle,
                    icon: const Icon(Icons.settings_outlined),
                  ),
              ],
            ),
      body: AppBG(
        // SafeArea is already handled by the AppBar (and by the embedded
        // chat shell on the Chats tab). Wrapping here would double-apply
        // padding on notched devices.
        child: _buildTabBody(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor:
            Theme.of(context).bottomNavigationBarTheme.selectedItemColor ??
                Theme.of(context).colorScheme.primary,
        unselectedItemColor:
            Theme.of(context).bottomNavigationBarTheme.unselectedItemColor ??
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
        backgroundColor:
            Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
        onTap: (index) {
          setState(() {
            _tabIndex = index;
          });
          if (index == 2) {
            unawaited(_refreshMiniProgramUpdateBadges());
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline),
                if (_totalUnreadChats > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            activeIcon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble),
                if (_totalUnreadChats > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: l.mirsaalTabChats,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.people_outline),
            activeIcon: const Icon(Icons.people),
            label: l.mirsaalTabContacts,
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.travel_explore_outlined),
                if (_hasUnreadOfficialFeeds ||
                    _hasUnreadMoments ||
                    _hasUnreadServiceNotifications ||
                    _hasNewTrendingMiniPrograms ||
                    _miniProgramsUpdateBadgeIds.isNotEmpty)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            activeIcon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.travel_explore),
                if (_hasUnreadOfficialFeeds ||
                    _hasUnreadMoments ||
                    _hasUnreadServiceNotifications ||
                    _hasNewTrendingMiniPrograms ||
                    _miniProgramsUpdateBadgeIds.isNotEmpty)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: l.isArabic ? 'استكشاف' : 'Discover',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: l.isArabic ? 'أنا' : 'Me',
          ),
        ],
      ),
    );
  }

  /// Top-level body switch for WeChat-like tab layout.
  Widget _buildTabBody() {
    switch (_tabIndex) {
      case 0:
        return _buildChatsTab();
      case 1:
        return _buildContactsTab();
      case 2:
        return _buildServicesTab();
      case 3:
        return _buildMeTab();
      default:
        return _buildChatsTab();
    }
  }

  /// Tab 0 – Chats: entry point for end-user and service chats.
  Widget _buildChatsTab() {
    return ThreemaChatPage(
      baseUrl: _baseUrl,
      showBottomNav: false,
    );
  }

  /// Tab 1 – Contacts: people, P2P and service assistants.
  Widget _buildContactsTab() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    Widget friendReqBadge() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _friendRequestsPending > 99 ? '99+' : '$_friendRequestsPending',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

    void showIndexHint(String letter, {bool persist = false}) {
      _contactsIndexHintTimer?.cancel();
      if (_contactsIndexHint != letter) {
        setState(() {
          _contactsIndexHint = letter;
        });
      }
      if (persist) return;
      _contactsIndexHintTimer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() {
          _contactsIndexHint = null;
        });
      });
    }

    String chatIdForFriend(Map<String, dynamic> f) {
      final deviceId = (f['device_id'] ?? '').toString().trim();
      if (deviceId.isNotEmpty) return deviceId;
      final shamellId = (f['shamell_id'] ?? '').toString().trim();
      if (shamellId.isNotEmpty) return shamellId;
      final id = (f['id'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
      final phone = (f['phone'] ?? '').toString().trim();
      if (phone.isNotEmpty) return phone;
      return '';
    }

    String displayForFriend(Map<String, dynamic> f) {
      final chatId = chatIdForFriend(f);
      final alias = (_contactsAliases[chatId] ?? '').trim();
      final name = (f['name'] ?? f['id'] ?? '').toString().trim();
      final id = (f['id'] ?? '').toString().trim();
      if (alias.isNotEmpty) return alias;
      if (name.isNotEmpty) return name;
      return id.isNotEmpty ? id : chatId;
    }

    String letterForDisplay(String display) {
      final raw = display.trim();
      if (raw.isEmpty) return '#';
      final first = raw[0].toUpperCase();
      final code = first.codeUnitAt(0);
      if (code < 65 || code > 90) return '#';
      return first;
    }

    final topKey = GlobalKey();
    final closeKey = GlobalKey();
    _contactsLetterKeys.clear();
    _contactsLetterKeys['↑'] = topKey;

    Widget contactRow(Map<String, dynamic> f) {
      final chatId = chatIdForFriend(f);
      final alias = (_contactsAliases[chatId] ?? '').trim();
      final tags = (_contactsTags[chatId] ?? '').trim();
      final display = displayForFriend(f);
      final original = (f['name'] ?? f['id'] ?? '').toString().trim();
      final isClose = ((f['close'] as bool?) ?? false) == true;
      final isDark = theme.brightness == Brightness.dark;
      final bg = isDark ? theme.colorScheme.surface : Colors.white;
      return Material(
        color: bg,
        child: InkWell(
          onTap: () {
            if (chatId.isEmpty) return;
            _navPush(
              WeChatContactInfoPage(
                baseUrl: _baseUrl,
                friend: f,
                peerId: chatId,
                displayName: original.isNotEmpty ? original : display,
                alias: alias,
                tags: tags,
                isCloseFriend: isClose,
                pushPage: _navPush,
              ),
              onReturn: () {
                unawaited(_loadFriendsSummary());
                unawaited(_loadContactsRosterMeta());
                unawaited(_loadContactsRoster(force: true));
              },
            );
          },
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 40,
                      height: 40,
                      color: theme.colorScheme.primary.withValues(alpha: .14),
                      alignment: Alignment.center,
                      child: Text(
                        display.isNotEmpty
                            ? display.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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

    Widget contactLetterHeader(String letter, GlobalKey key) {
      return Container(
        key: key,
        color: WeChatPalette.background,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Text(
          letter,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: .60),
          ),
        ),
      );
    }

    Widget contactSectionHeader(String label, {Key? headerKey}) {
      return Container(
        key: headerKey,
        color: WeChatPalette.background,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: .60),
          ),
        ),
      );
    }

    Widget roster() {
      if (_contactsRosterLoading && _contactsRoster.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (_contactsRoster.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Text(
            _contactsRosterError != null
                ? (l.isArabic
                    ? 'تعذر تحميل جهات الاتصال. اسحب للتحديث.'
                    : 'Could not load contacts. Pull to refresh.')
                : l.mirsaalNoContactsHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
        );
      }

      final all = List<Map<String, dynamic>>.from(_contactsRoster);
      all.sort((a, b) => displayForFriend(a)
          .toLowerCase()
          .compareTo(displayForFriend(b).toLowerCase()));
      final close =
          all.where((f) => ((f['close'] as bool?) ?? false) == true).toList();
      final normal =
          all.where((f) => ((f['close'] as bool?) ?? false) != true).toList();

      final widgets = <Widget>[];
      const dividerIndent = 72.0;

      void addContactRow(Map<String, dynamic> f, {bool addDivider = true}) {
        widgets.add(contactRow(f));
        if (addDivider) {
          widgets.add(
            Divider(
              height: 1,
              thickness: 0.5,
              indent: dividerIndent,
              color: theme.dividerColor,
            ),
          );
        }
      }

      if (close.isNotEmpty) {
        _contactsLetterKeys['☆'] = closeKey;
        widgets.add(
          contactSectionHeader(
            l.mirsaalFriendsCloseLabel,
            headerKey: closeKey,
          ),
        );
        for (var i = 0; i < close.length; i++) {
          addContactRow(close[i], addDivider: i != close.length - 1);
        }
      }

      if (normal.isNotEmpty) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 8));
        }
        String currentLetter = '';
        for (var i = 0; i < normal.length; i++) {
          final f = normal[i];
          final letter = letterForDisplay(displayForFriend(f));
          if (letter != currentLetter) {
            currentLetter = letter;
            final key = GlobalKey();
            _contactsLetterKeys[letter] = key;
            widgets.add(contactLetterHeader(letter, key));
          }
          addContactRow(f, addDivider: i != normal.length - 1);
        }
      }

      return Container(
        margin: const EdgeInsets.only(top: 8),
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widgets,
        ),
      );
    }

    final content = RefreshIndicator(
      onRefresh: () async {
        await _loadFriendsSummary();
        await _loadContactsRosterMeta();
        await _loadContactsRoster(force: true);
      },
      child: ListView(
        key: _contactsViewportKey,
        controller: _contactsScrollCtrl,
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          Container(
            key: topKey,
            child: WeChatSearchBar(
              hintText: l.isArabic ? 'بحث' : 'Search',
              readOnly: true,
              onTap: _openGlobalSearch,
            ),
          ),
          WeChatSection(
            children: [
              ListTile(
                dense: true,
                leading: const WeChatLeadingIcon(
                  icon: Icons.person_add_outlined,
                  background: Color(0xFFF59E0B),
                ),
                title: Text(l.isArabic ? 'أصدقاء جدد' : 'New friends'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_friendRequestsPending > 0) ...[
                      friendReqBadge(),
                      const SizedBox(width: 8),
                    ],
                    chevron(),
                  ],
                ),
                onTap: () {
                  _navPush(
                    FriendsPage(_baseUrl, mode: FriendsPageMode.newFriends),
                    onReturn: () {
                      unawaited(_loadFriendsSummary());
                      unawaited(_loadContactsRosterMeta());
                      unawaited(_loadContactsRoster(force: true));
                    },
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const WeChatLeadingIcon(
                  icon: Icons.group_outlined,
                  background: WeChatPalette.green,
                ),
                title: Text(l.isArabic ? 'الدردشات الجماعية' : 'Group chats'),
                trailing: chevron(),
                onTap: () => _navPush(GroupChatsPage(baseUrl: _baseUrl)),
              ),
              ListTile(
                dense: true,
                leading: const WeChatLeadingIcon(
                  icon: Icons.sell_outlined,
                  background: Color(0xFF3B82F6),
                ),
                title: Text(l.isArabic ? 'الوسوم' : 'Tags'),
                trailing: chevron(),
                onTap: () => _navPush(FriendTagsPage(baseUrl: _baseUrl)),
              ),
              ListTile(
                dense: true,
                leading: const WeChatLeadingIcon(
                  icon: Icons.verified_outlined,
                  background: Color(0xFF10B981),
                ),
                title:
                    Text(l.isArabic ? 'الحسابات الرسمية' : 'Official accounts'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasUnreadOfficialFeeds) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    chevron(),
                  ],
                ),
                onTap: () {
                  _navPush(
                    OfficialAccountsPage(
                      baseUrl: _baseUrl,
                      initialCityFilter: _officialStripCityLabel,
                      onOpenChat: (peerId) {
                        if (peerId.isEmpty) return;
                        _navPush(
                          ThreemaChatPage(
                            baseUrl: _baseUrl,
                            initialPeerId: peerId,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
          roster(),
        ],
      ),
    );

    final letters = <String>[
      '↑',
      '☆',
      ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('')
    ];
    final showIndex = _contactsRoster.isNotEmpty;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateContactsStickyHeader();
    });

    return Stack(
      children: [
        content,
        if (_contactsStickyHeader != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(0, _contactsStickyHeaderOffset),
                child: Container(
                  height: 28,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: WeChatPalette.background,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(
                          alpha: isDark ? .18 : .45,
                        ),
                        width: 0.6,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _contactsStickyHeader == '☆'
                        ? l.mirsaalFriendsCloseLabel
                        : _contactsStickyHeader!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: .60),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (showIndex)
          Positioned(
            right: l.isArabic ? null : 2,
            left: l.isArabic ? 2 : null,
            top: 88,
            bottom: 80,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final height = constraints.maxHeight;
                const indexPaddingV = 8.0;
                final effectiveHeight = max(1.0, height - indexPaddingV * 2);
                final cellHeight = effectiveHeight / letters.length;

                void jumpTo(String letter, {required bool persistHint}) {
                  final isSame = _contactsIndexHint == letter;
                  showIndexHint(letter, persist: persistHint);
                  if (isSame) return;
                  if (letter == '↑') {
                    if (!_contactsScrollCtrl.hasClients) return;
                    _contactsScrollCtrl.animateTo(
                      0,
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                    );
                    return;
                  }
                  final key = _contactsLetterKeys[letter];
                  if (key == null) return;
                  final target = key.currentContext;
                  if (target == null) return;
                  Scrollable.ensureVisible(
                    target,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                  );
                }

                void handle(Offset localPos, {required bool persistHint}) {
                  final dy =
                      (localPos.dy - indexPaddingV).clamp(0.0, effectiveHeight);
                  final idx = (dy / cellHeight)
                      .floor()
                      .clamp(0, letters.length - 1)
                      .toInt();
                  jumpTo(letters[idx], persistHint: persistHint);
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    if (_contactsIndexDragging) {
                      setState(() {
                        _contactsIndexDragging = false;
                      });
                    }
                    handle(d.localPosition, persistHint: false);
                  },
                  onVerticalDragStart: (d) {
                    if (!_contactsIndexDragging) {
                      setState(() {
                        _contactsIndexDragging = true;
                      });
                    }
                    handle(d.localPosition, persistHint: true);
                  },
                  onVerticalDragUpdate: (d) =>
                      handle(d.localPosition, persistHint: true),
                  onVerticalDragEnd: (_) {
                    if (_contactsIndexDragging) {
                      setState(() {
                        _contactsIndexDragging = false;
                      });
                    }
                    final hint = _contactsIndexHint;
                    if (hint != null) showIndexHint(hint);
                  },
                  onVerticalDragCancel: () {
                    if (_contactsIndexDragging) {
                      setState(() {
                        _contactsIndexDragging = false;
                      });
                    }
                    final hint = _contactsIndexHint;
                    if (hint != null) showIndexHint(hint);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: _contactsIndexDragging
                          ? theme.colorScheme.onSurface.withValues(
                              alpha: isDark ? .14 : .06,
                            )
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: letters.map((letter) {
                        final selected = _contactsIndexHint == letter;
                        const size = 16.0;
                        return SizedBox(
                          width: size,
                          height: size,
                          child: DecoratedBox(
                            decoration: selected
                                ? const BoxDecoration(
                                    color: WeChatPalette.green,
                                    shape: BoxShape.circle,
                                  )
                                : const BoxDecoration(),
                            child: Center(
                              child: Text(
                                letter,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                  color: selected
                                      ? Colors.white
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: .62),
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        if (_contactsIndexHint != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      _contactsIndexHint!,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _updateContactsStickyHeader() {
    if (!mounted) return;
    if (_tabIndex != 1) return;
    final viewportCtx = _contactsViewportKey.currentContext;
    if (viewportCtx == null) return;
    final viewportObj = viewportCtx.findRenderObject();
    if (viewportObj is! RenderBox) return;

    const headerH = 28.0;
    final entries = <MapEntry<String, double>>[];

    for (final e in _contactsLetterKeys.entries) {
      if (e.key == '↑') continue;
      final ctx = e.value.currentContext;
      if (ctx == null) continue;
      final obj = ctx.findRenderObject();
      if (obj is! RenderBox) continue;
      final pos = obj.localToGlobal(Offset.zero, ancestor: viewportObj);
      entries.add(MapEntry(e.key, pos.dy));
    }
    if (entries.isEmpty) {
      if (_contactsStickyHeader != null || _contactsStickyHeaderOffset != 0.0) {
        setState(() {
          _contactsStickyHeader = null;
          _contactsStickyHeaderOffset = 0.0;
        });
      }
      return;
    }
    entries.sort((a, b) => a.value.compareTo(b.value));

    MapEntry<String, double>? current;
    for (final e in entries) {
      if (e.value <= 0) {
        current = e;
      } else {
        break;
      }
    }

    final nextHeader = current == null
        ? null
        : (() {
            final idx = entries.indexOf(current!);
            if (idx < 0 || idx >= entries.length - 1) return null;
            return entries[idx + 1];
          })();

    final nextKey = current?.key;
    final nextOffset = (current == null || nextHeader == null)
        ? 0.0
        : min(0.0, nextHeader.value - headerH);

    if (nextKey == _contactsStickyHeader &&
        (nextOffset - _contactsStickyHeaderOffset).abs() < 0.5) {
      return;
    }

    setState(() {
      _contactsStickyHeader = nextKey;
      _contactsStickyHeaderOffset = nextOffset;
    });
  }

  void _openGlobalSearch() {
    _navPush(
      GlobalSearchPage(
        baseUrl: _baseUrl,
        walletId: _walletId,
        deviceId: deviceId,
        onOpenMod: _openMod,
      ),
    );
  }

  void _openWeChatSettings() {
    _navPush(
      WeChatSettingsPage(
        baseUrl: _baseUrl,
        walletId: _walletId,
        deviceId: deviceId,
        profileName: _profileName,
        profilePhone: _profilePhone,
        profileShamellId: _profileShamellId,
        showOps: _showOps,
        showSuperadmin: _showSuperadmin,
        hasDefaultOfficialAccount: _hasDefaultOfficialAccount,
        miniProgramsCount: _miniProgramsCount,
        miniProgramsTotalUsage: _miniProgramsTotalUsage,
        miniProgramsMoments30d: _miniProgramsMoments30d,
        onOpenOfficialNotifications: _openOfficialNotifications,
        onLogout: _logout,
        pushPage: (page) => _navPush(page),
        onOpenMod: _openMod,
      ),
    );
  }

  String? _friendQrPayload() {
    final p = _profilePhone.trim();
    final id = _profileShamellId.trim();
    if (p.isEmpty && id.isEmpty) return null;
    if (id.isNotEmpty && p.isNotEmpty) {
      final uri = Uri(
        scheme: 'shamell',
        host: 'friend',
        path: '/$id',
        queryParameters: {'phone': p},
      );
      return uri.toString();
    }
    final core = p.isNotEmpty ? p : id;
    final uri = Uri(
      scheme: 'shamell',
      host: 'friend',
      path: '/$core',
    );
    return uri.toString();
  }

  void _showFriendQr() {
    final l = L10n.of(context);
    final payload = _friendQrPayload();
    if (payload == null || payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'لا يوجد معرّف أو رقم هاتف صالح بعد.'
                : 'No valid Shamell ID or phone yet.',
          ),
        ),
      );
      return;
    }
    _navPush(
      WeChatMyQrCodePage(
        payload: payload,
        profileName: _profileName,
        profilePhone: _profilePhone,
        profileShamellId: _profileShamellId,
      ),
    );
  }

  /// Tab 1 – Services: main super app hub (existing HomeRoute* layouts).
  Widget _buildServicesTab() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    if (_wechatStrictUi) {
      Icon chevron() => Icon(
            l.isArabic ? Icons.chevron_left : Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: .40),
          );

      Widget badgeDot() => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.surface,
                width: 1.5,
              ),
            ),
          );

      IconData miniPreviewIconFor(String id) {
        final meta = miniAppById(id);
        if (meta != null) return meta.icon;
        final lower = id.toLowerCase();
        if (lower.contains('pay') ||
            lower.contains('wallet') ||
            lower.contains('payment')) {
          return Icons.account_balance_wallet_outlined;
        }
        if (lower.contains('bus') ||
            lower.contains('ride') ||
            lower.contains('mobility')) {
          return Icons.directions_bus_filled_outlined;
        }
        return Icons.widgets_outlined;
      }

      Color miniPreviewBgFor(String id) {
        final lower = id.toLowerCase();
        if (lower.contains('pay') ||
            lower.contains('wallet') ||
            lower.contains('payment')) {
          return Tokens.colorPayments;
        }
        if (lower.contains('bus') ||
            lower.contains('ride') ||
            lower.contains('mobility')) {
          return Tokens.colorBus;
        }
        return const Color(0xFF64748B);
      }

      Color miniPreviewFgFor(String id) {
        return Colors.white;
      }

      List<String> miniProgramsPreviewIds() {
        final ids = <String>[];
        final updateBadges = _miniProgramsUpdateBadgeIds;
        void add(String id) {
          final clean = id.trim();
          if (clean.isEmpty) return;
          if (ids.contains(clean)) return;
          ids.add(clean);
        }

        // Prefer items with update badges (WeChat-style: show updated mini
        // programs first in the Discover preview stack).
        if (updateBadges.isNotEmpty) {
          for (final id in _recentMiniPrograms) {
            if (updateBadges.contains(id.trim())) add(id);
          }
          for (final id in _pinnedMiniProgramsOrder) {
            if (updateBadges.contains(id.trim())) add(id);
          }
          for (final id in _pinnedMiniApps) {
            if (updateBadges.contains(id.trim())) add(id);
          }
        }
        for (final id in _recentMiniPrograms) {
          add(id);
        }
        for (final id in _pinnedMiniProgramsOrder) {
          add(id);
        }
        for (final id in _pinnedMiniApps) {
          add(id);
        }
        for (final p in _trendingMiniPrograms) {
          add((p['app_id'] ?? '').toString());
        }
        if (ids.length > 3) {
          ids.removeRange(3, ids.length);
        }
        return ids;
      }

      Widget miniPreviewIcon(String id) {
        const size = 22.0;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: miniPreviewBgFor(id),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: theme.colorScheme.surface,
              width: 2,
            ),
          ),
          child: Icon(
            miniPreviewIconFor(id),
            size: 12,
            color: miniPreviewFgFor(id),
          ),
        );
      }

      Widget miniProgramsTrailing() {
        final ids = miniProgramsPreviewIds();
        final showBadge = _hasNewTrendingMiniPrograms ||
            _miniProgramsUpdateBadgeIds.isNotEmpty;
        Widget previewStack() {
          const size = 22.0;
          const overlap = 8.0;
          final width = size + (ids.length - 1) * (size - overlap);
          return SizedBox(
            width: width,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < ids.length; i++)
                  Positioned(
                    left: i * (size - overlap),
                    child: miniPreviewIcon(ids[i]),
                  ),
              ],
            ),
          );
        }

        if (ids.isEmpty) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBadge) ...[
                badgeDot(),
                const SizedBox(width: 8),
              ],
              chevron(),
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            previewStack(),
            const SizedBox(width: 8),
            if (showBadge) ...[
              badgeDot(),
              const SizedBox(width: 8),
            ],
            chevron(),
          ],
        );
      }

      final discoverTopTiles = <Widget>[
        if (_pluginShowMoments)
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.photo_library_outlined,
              background: Color(0xFF10B981),
            ),
            title: Text(l.mirsaalChannelMomentsTitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasUnreadMoments) ...[
                  badgeDot(),
                  const SizedBox(width: 8),
                ],
                chevron(),
              ],
            ),
            onTap: () {
              _navPush(
                MomentsPage(
                  baseUrl: _baseUrl,
                  onOpenOfficialDirectory: (ctx) {
                    _navPush(
                      OfficialAccountsPage(
                        baseUrl: _baseUrl,
                        initialCityFilter: _officialStripCityLabel,
                        onOpenChat: (peerId) {
                          if (peerId.isEmpty) return;
                          _navPush(
                            ThreemaChatPage(
                              baseUrl: _baseUrl,
                              initialPeerId: peerId,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        if (_pluginShowChannels)
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.live_tv_outlined,
              background: Color(0xFFF59E0B),
            ),
            title: Text(l.isArabic ? 'القنوات' : 'Channels'),
            trailing: chevron(),
            onTap: () {
              _navPush(
                ChannelsPage(
                  baseUrl: _baseUrl,
                ),
              );
            },
          ),
        if (_pluginShowChannels)
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.radio_button_checked,
              background: Color(0xFFF43F5E),
            ),
            title: Text(l.isArabic ? 'مباشر' : 'Live'),
            trailing: chevron(),
            onTap: () {
              _navPush(
                ChannelsPage(
                  baseUrl: _baseUrl,
                  initialLiveOnly: true,
                ),
              );
            },
          ),
        if (_pluginShowMoments)
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.local_fire_department_outlined,
              background: Color(0xFFF59E0B),
            ),
            title: Text(l.isArabic ? 'الأخبار' : 'Top Stories'),
            trailing: chevron(),
            onTap: () {
              _navPush(
                MomentsPage(
                  baseUrl: _baseUrl,
                  initialHotOfficialsOnly: true,
                  showComposer: false,
                ),
              );
            },
          ),
      ];

      final discoverToolsTiles = <Widget>[
        if (_pluginShowScan)
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.qr_code_scanner,
              background: Color(0xFF3B82F6),
            ),
            title: Text(l.mirsaalChannelScanTitle),
            trailing: chevron(),
            onTap: () {
              unawaited(_openWeChatScanAndHandle());
            },
          ),
        if (_pluginShowPeopleNearby)
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.vibration_outlined,
              background: Color(0xFF8B5CF6),
            ),
            title: Text(l.isArabic ? 'هزّ' : 'Shake'),
            trailing: chevron(),
            onTap: () {
              _navPush(
                WeChatShakePage(
                  baseUrl: _baseUrl,
                ),
              );
            },
          ),
      ];

      final discoverSearchTiles = <Widget>[
        ListTile(
          dense: true,
          leading: const WeChatLeadingIcon(
            icon: Icons.search,
            background: Color(0xFF64748B),
          ),
          title: Text(l.isArabic ? 'بحث' : 'Search'),
          trailing: chevron(),
          onTap: _openGlobalSearch,
        ),
      ];

      final discoverNearbyTiles = <Widget>[
        if (_pluginShowPeopleNearby)
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.people_alt_outlined,
              background: Color(0xFF7C3AED),
            ),
            title: Text(l.mirsaalFriendsPeopleNearbyTitle),
            trailing: chevron(),
            onTap: () {
              _navPush(PeopleNearbyPage(baseUrl: _baseUrl));
            },
          ),
        if (_pluginShowMiniPrograms)
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.grid_view_outlined,
              background: WeChatPalette.green,
            ),
            title: Text(l.miniAppsTitle),
            trailing: miniProgramsTrailing(),
            onTap: _openMiniProgramsDiscover,
          ),
      ];

      return ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          if (!kEnduserOnly && _showSuperadmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Builder(builder: (context) {
                final hasOps = _hasOpsRole(_roles);
                final hasAdmin = _hasAdminRole(_roles);
                final isSuper = _showSuperadmin;
                final allowSwitch = isSuper;
                return Row(
                  children: [
	                  _RoleChip(
	                    mode: AppMode.user,
	                    current: _appMode,
	                    onTap: () => _changeAppMode(AppMode.user),
	                    enabled: allowSwitch || _appMode == AppMode.user,
	                  ),
	                  const SizedBox(width: 8),
	                  _RoleChip(
	                    mode: AppMode.operator,
	                    current: _appMode,
	                    onTap: () => _changeAppMode(AppMode.operator),
	                    enabled: allowSwitch && hasOps,
                    ),
                    const SizedBox(width: 8),
                    _RoleChip(
                      mode: AppMode.admin,
                      current: _appMode,
                      onTap: () => _changeAppMode(AppMode.admin),
                      enabled: allowSwitch && hasAdmin,
                    ),
                    const SizedBox(width: 8),
                    _SuperadminChip(
                      selected: isSuper && _appMode == AppMode.admin,
                      enabled: allowSwitch && isSuper,
                      onTap: () {
                        if (!isSuper || !allowSwitch) return;
                        _changeAppMode(AppMode.admin);
                      },
                    ),
                  ],
                );
	              }),
	            ),
	          if (discoverTopTiles.isNotEmpty)
	            WeChatSection(
	              margin: const EdgeInsets.only(top: 8),
	              children: discoverTopTiles,
            ),
          if (discoverToolsTiles.isNotEmpty)
            WeChatSection(
              children: discoverToolsTiles,
            ),
          if (discoverSearchTiles.isNotEmpty)
            WeChatSection(
              children: discoverSearchTiles,
            ),
          if (discoverNearbyTiles.isNotEmpty)
            WeChatSection(
              children: discoverNearbyTiles,
            ),
          if (!kEnduserOnly &&
              (_appMode == AppMode.operator || _appMode == AppMode.admin) &&
              _busTripsToday != null &&
              _busRevenueTodayCents != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: GlassPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.directions_bus_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.of(context).busTodayTitle,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_busTripsToday ?? 0} ${L10n.of(context).tripsLabel} · ${_busBookingsToday ?? 0} ${L10n.of(context).bookingsLabel} · ${fmtCents(_busRevenueTodayCents!)} SYP',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open Bus Control',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () {
                        final baseUri = Uri.tryParse(_baseUrl);
                        final uri = baseUri?.resolve('/bus/admin') ??
                            Uri.parse(
                                '${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/bus/admin');
                        _navPush(
                          WeChatWebViewPage(
                            initialUri: uri,
                            baseUri: baseUri,
                            initialTitle: L10n.of(context).isArabic
                                ? 'إدارة الباص'
                                : 'Bus admin',
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return Column(
      children: [
        if (!kEnduserOnly && _showSuperadmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Builder(builder: (context) {
              final hasOps = _hasOpsRole(_roles);
              final hasAdmin = _hasAdminRole(_roles);
              final isSuper = _showSuperadmin;
              final allowSwitch = isSuper;
              return Row(
                children: [
	                  _RoleChip(
	                    mode: AppMode.user,
	                    current: _appMode,
	                    onTap: () => _changeAppMode(AppMode.user),
	                    enabled: allowSwitch || _appMode == AppMode.user,
	                  ),
	                  const SizedBox(width: 8),
	                  _RoleChip(
	                    mode: AppMode.operator,
	                    current: _appMode,
	                    onTap: () => _changeAppMode(AppMode.operator),
	                    enabled: allowSwitch && hasOps,
                  ),
                  const SizedBox(width: 8),
                  _RoleChip(
                    mode: AppMode.admin,
                    current: _appMode,
                    onTap: () => _changeAppMode(AppMode.admin),
                    enabled: allowSwitch && hasAdmin,
                  ),
                  const SizedBox(width: 8),
                  _SuperadminChip(
                    selected: isSuper && _appMode == AppMode.admin,
                    enabled: allowSwitch && isSuper,
                    onTap: () {
                      if (!isSuper || !allowSwitch) return;
                      _changeAppMode(AppMode.admin);
                    },
                  ),
                ],
              );
	            }),
	          ),
	        // WeChat-like primary Discover list: Moments, Scan, People Nearby,
	        // Mini-programs, Official accounts.
	        WeChatSection(
	          margin: const EdgeInsets.only(top: 8),
          children: [
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.photo_library_outlined,
                background: Color(0xFF10B981),
              ),
              title: Text(l.mirsaalChannelMomentsTitle),
              subtitle: Text(l.mirsaalChannelMomentsSubtitle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasUnreadMoments) ...[
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
                ],
              ),
              onTap: () {
                _navPush(
                  MomentsPage(
                    baseUrl: _baseUrl,
                    onOpenOfficialDirectory: (ctx) {
                      _navPush(
                        OfficialAccountsPage(
                          baseUrl: _baseUrl,
                          initialCityFilter: _officialStripCityLabel,
                          onOpenChat: (peerId) {
                            if (peerId.isEmpty) return;
                            _navPush(
                              ThreemaChatPage(
                                baseUrl: _baseUrl,
                                initialPeerId: peerId,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.live_tv_outlined,
                background: Color(0xFFF59E0B),
              ),
              title: Text(l.isArabic ? 'القنوات' : 'Channels'),
              subtitle: Text(
                l.isArabic
                    ? 'مقاطع قصيرة وبث مباشر من الحسابات الرسمية'
                    : 'Short videos and live from official accounts',
              ),
              trailing:
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
              onTap: () {
                _navPush(
                  ChannelsPage(
                    baseUrl: _baseUrl,
                  ),
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.radio_button_checked,
                background: Color(0xFFF43F5E),
              ),
              title: Text(l.isArabic ? 'مباشر' : 'Live'),
              subtitle: Text(
                l.isArabic ? 'البث المباشر من القنوات' : 'Live now in Channels',
              ),
              trailing:
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
              onTap: () {
                _navPush(
                  ChannelsPage(
                    baseUrl: _baseUrl,
                    initialLiveOnly: true,
                  ),
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.qr_code_scanner,
                background: Color(0xFF3B82F6),
              ),
              title: Text(l.mirsaalChannelScanTitle),
              subtitle: Text(l.mirsaalChannelScanSubtitle),
              trailing:
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
              onTap: () {
                unawaited(_openWeChatScanAndHandle());
              },
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.vibration_outlined,
                background: Color(0xFF8B5CF6),
              ),
              title: Text(l.isArabic ? 'هزّ' : 'Shake'),
              subtitle: Text(
                l.isArabic
                    ? 'اكتشف أشخاصاً وخدمات عبر الهزّ'
                    : 'Discover by shaking',
              ),
              trailing:
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
              onTap: () {
                _navPush(
                  WeChatShakePage(
                    baseUrl: _baseUrl,
                  ),
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.local_fire_department_outlined,
                background: Color(0xFFF59E0B),
              ),
              title: Text(l.isArabic ? 'الأخبار' : 'Top Stories'),
              subtitle: Text(
                l.isArabic
                    ? 'أفضل المشاركات من الحسابات الرسمية'
                    : 'Hot shares from official accounts',
              ),
              trailing:
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
              onTap: () {
                _navPush(
                  MomentsPage(
                    baseUrl: _baseUrl,
                    initialHotOfficialsOnly: true,
                    showComposer: false,
                  ),
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.search,
                background: Color(0xFF64748B),
              ),
              title: Text(l.isArabic ? 'بحث' : 'Search'),
              subtitle: Text(
                l.isArabic
                    ? 'ابحث في الدردشات واللحظات والمزيد'
                    : 'Search chats, Moments and more',
              ),
              trailing:
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
              onTap: _openGlobalSearch,
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.people_alt_outlined,
                background: Color(0xFF7C3AED),
              ),
              title: Text(l.mirsaalFriendsPeopleNearbyTitle),
              subtitle: Text(l.mirsaalFriendsPeopleNearbySubtitle),
              trailing:
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
              onTap: () {
                _navPush(PeopleNearbyPage(baseUrl: _baseUrl));
              },
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.grid_view_outlined,
                background: WeChatPalette.green,
              ),
              title: Text(l.miniAppsTitle),
              subtitle: Text(
                l.isArabic
                    ? 'فتح تطبيقات مرسال المصغّرة'
                    : 'Open Shamell mini‑programs',
              ),
              trailing:
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
              onTap: _openMiniProgramsDiscover,
            ),
            ListTile(
              dense: true,
              leading: const WeChatLeadingIcon(
                icon: Icons.verified_outlined,
                background: Color(0xFF10B981),
              ),
              title: Text(l.mirsaalChannelOfficialAccountsTitle),
              subtitle: Text(l.mirsaalChannelOfficialAccountsSubtitle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasUnreadOfficialFeeds) ...[
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  Icon(l.isArabic ? Icons.chevron_left : Icons.chevron_right),
                ],
              ),
              onTap: () {
                _navPush(
                  OfficialAccountsPage(
                    baseUrl: _baseUrl,
                    initialCityFilter: _officialStripCityLabel,
                    onOpenChat: (peerId) {
                      if (peerId.isEmpty) return;
                      _navPush(
                        ThreemaChatPage(
                          baseUrl: _baseUrl,
                          initialPeerId: peerId,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
        if (!kEnduserOnly &&
            (_appMode == AppMode.operator || _appMode == AppMode.admin) &&
            _busTripsToday != null &&
            _busRevenueTodayCents != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.directions_bus_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.of(context).busTodayTitle,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          '${_busTripsToday ?? 0} ${L10n.of(context).tripsLabel} · ${_busBookingsToday ?? 0} ${L10n.of(context).bookingsLabel} · ${fmtCents(_busRevenueTodayCents!)} SYP',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open Bus Control',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () {
                      final baseUri = Uri.tryParse(_baseUrl);
                      final uri = baseUri?.resolve('/bus/admin') ??
                          Uri.parse(
                              '${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/bus/admin');
                      _navPush(
                        WeChatWebViewPage(
                          initialUri: uri,
                          baseUri: baseUri,
                          initialTitle: L10n.of(context).isArabic
                              ? 'إدارة الباص'
                              : 'Bus admin',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        if (_walletId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _appMode == AppMode.operator
                              ? (L10n.of(context).isArabic
                                  ? 'محفظة المشغل'
                                  : 'Operator wallet')
                              : L10n.of(context).homeWallet,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _walletHidden
                              ? '••••••'
                              : (_walletBalanceCents == null
                                  ? (_walletLoading
                                      ? (L10n.of(context).isArabic
                                          ? 'جارٍ التحميل…'
                                          : 'Loading…')
                                      : (L10n.of(context).isArabic
                                          ? 'الرصيد غير متاح'
                                          : 'Balance unavailable'))
                                  : '${fmtCents(_walletBalanceCents!)} $_walletCurrency'),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _walletHidden ? 'Show balance' : 'Hide balance',
                    icon: Icon(_walletHidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () {
                      setState(() => _walletHidden = !_walletHidden);
                    },
                  ),
                ],
              ),
            ),
          ),
        if (_walletId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: PayActionButton(
                    icon: Icons.qr_code_scanner,
                    label: l.qaScanPay,
                    onTap: _quickScanPay,
                    tint: Tokens.colorPayments,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PayActionButton(
                    icon: Icons.swap_horiz,
                    label: l.qaP2P,
                    onTap: _quickP2P,
                    tint: Tokens.colorPayments,
                  ),
                ),
              ],
            ),
          ),
        if (_walletId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: PayActionButton(
                    icon: Icons.account_balance_wallet_outlined,
                    label: l.qaTopup,
                    onTap: _quickTopup,
                    tint: Tokens.colorPayments,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PayActionButton(
                    icon: Icons.bolt,
                    label: 'Sonic',
                    onTap: () => _navPush(SonicPayPage(_baseUrl)),
                    tint: Tokens.colorPayments,
                  ),
                ),
              ],
            ),
          ),
        if (_officialStripAccounts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Perf.action('official_open_directory_from_home_strip');
                    _navPush(
                      OfficialAccountsPage(
                        baseUrl: _baseUrl,
                        initialCityFilter: _officialStripCityLabel,
                        onOpenChat: (peerId) {
                          if (peerId.isEmpty) return;
                          _navPush(
                            ThreemaChatPage(
                              baseUrl: _baseUrl,
                              initialPeerId: peerId,
                            ),
                          );
                        },
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _officialStripCityLabel != null &&
                                _officialStripCityLabel!.isNotEmpty
                            ? (l.isArabic
                                ? 'الحسابات الرسمية في ${_officialStripCityLabel}'
                                : 'Official accounts in ${_officialStripCityLabel}')
                            : (l.isArabic
                                ? 'الحسابات الرسمية المقترحة'
                                : 'Recommended official accounts'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right,
                          size: 16, color: Colors.grey),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _officialStripAccounts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final acc = _officialStripAccounts[i];
                      final theme = Theme.of(ctx);
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openOfficialFromStrip(acc),
                        child: Container(
                          width: 190,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.dividerColor.withValues(alpha: .40),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundImage: acc.avatarUrl != null &&
                                        acc.avatarUrl!.isNotEmpty
                                    ? NetworkImage(acc.avatarUrl!)
                                    : null,
                                child: acc.avatarUrl == null
                                    ? Text(
                                        acc.name.isNotEmpty
                                            ? acc.name.characters.first
                                                .toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      acc.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      acc.category?.isNotEmpty == true
                                          ? acc.category!
                                          : (acc.city?.isNotEmpty == true
                                              ? acc.city!
                                              : (l.isArabic
                                                  ? 'حساب رسمي'
                                                  : 'Official account')),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'اكتشف' : 'Discover',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              // WeChat-like “Discover” strip: lightweight promos to key mini-apps.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildDiscoverPromoChip(
                      icon: Icons.search,
                      label: l.isArabic ? 'بحث عالمي' : 'Global search',
                      onTap: () {
                        _navPush(
                          GlobalSearchPage(
                            baseUrl: _baseUrl,
                            walletId: _walletId,
                            deviceId: deviceId,
                            onOpenMod: _openMod,
                          ),
                        );
                      },
	                    ),
	                    _buildDiscoverPromoChip(
	                      icon: Icons.directions_bus_filled_outlined,
	                      label: l.isArabic ? 'الباص بضغطة زر' : 'Bus in one tap',
	                      onTap: () => _openMod('bus'),
	                    ),
                    if (_walletId.isNotEmpty)
                      _buildDiscoverPromoChip(
                        icon: Icons
                            .qr_code_scanner, // mirrors Wallet “Scan & pay”
                        label: l.isArabic ? 'امسح للدفع' : 'Scan & pay',
                        onTap: _quickScanPay,
                      ),
                    _buildDiscoverPromoChip(
                      icon: Icons.verified_outlined,
                      label: _officialStripCityLabel != null &&
                              _officialStripCityLabel!.isNotEmpty
                          ? (l.isArabic
                              ? 'خدمات في ${_officialStripCityLabel}'
                              : 'Services in ${_officialStripCityLabel}')
                          : (l.isArabic
                              ? 'الحسابات الرسمية'
                              : 'Official accounts'),
                      showUnreadDot: _hasUnreadOfficialFeeds,
                      badgeIcon: _officialHotAccounts > 0
                          ? Icons.local_fire_department_outlined
                          : null,
                      onTap: () {
                        Perf.action(
                            'official_open_directory_from_discover_chip');
                        _navPush(
                          OfficialAccountsPage(
                            baseUrl: _baseUrl,
                            initialCityFilter: _officialStripCityLabel,
                            onOpenChat: (peerId) {
                              if (peerId.isEmpty) return;
                              _navPush(
                                ThreemaChatPage(
                                  baseUrl: _baseUrl,
                                  initialPeerId: peerId,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.subscriptions_outlined,
                      label: l.isArabic
                          ? 'خلاصة الاشتراكات'
                          : 'Subscriptions feed',
                      showUnreadDot: _hasUnreadOfficialFeeds,
                      onTap: () {
                        Perf.action(
                            'official_open_subscriptions_from_discover_chip');
                        _navPush(
                          ThreemaChatPage(
                            baseUrl: _baseUrl,
                            initialPeerId: '__official_subscriptions__',
                          ),
                        );
                      },
                    ),
                    if (_officialStripCityLabel != null &&
                        _officialStripCityLabel!.isNotEmpty)
                      _buildDiscoverPromoChip(
                        icon: Icons.photo_library_outlined,
                        label: l.isArabic
                            ? 'لحظات: خدمات في ${_officialStripCityLabel!}'
                            : 'Moments: services in ${_officialStripCityLabel!}',
                        showUnreadDot: _hasUnreadMoments,
                        onTap: () => _navPush(
                          MomentsPage(
                            baseUrl: _baseUrl,
                            officialCity: _officialStripCityLabel,
                            officialCategory: null,
                            onOpenOfficialDirectory: (ctx) {
                              _navPush(
                                OfficialAccountsPage(
                                  baseUrl: _baseUrl,
                                  initialCityFilter: _officialStripCityLabel,
                                  onOpenChat: (peerId) {
                                    if (peerId.isEmpty) return;
                                    _navPush(
                                      ThreemaChatPage(
                                        baseUrl: _baseUrl,
                                        initialPeerId: peerId,
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    _buildDiscoverPromoChip(
                      icon: Icons.photo_library_outlined,
                      label: l.isArabic ? 'اللحظات' : 'Moments',
                      showUnreadDot: _hasUnreadMoments,
                      badgeIcon:
                          _redpacketMoments30d > 0 ? Icons.card_giftcard : null,
                      onTap: () => _navPush(
                        MomentsPage(
                          baseUrl: _baseUrl,
                          onOpenOfficialDirectory: (ctx) {
                            _navPush(
                              OfficialAccountsPage(
                                baseUrl: _baseUrl,
                                initialCityFilter: _officialStripCityLabel,
                                onOpenChat: (peerId) {
                                  if (peerId.isEmpty) return;
                                  _navPush(
                                    ThreemaChatPage(
                                      baseUrl: _baseUrl,
                                      initialPeerId: peerId,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.grid_view_outlined,
                      label: l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs',
                      badgeLabel: _miniProgramsCount > 0
                          ? (l.isArabic ? 'جديد' : 'My apps')
                          : null,
                      onTap: _openMiniProgramsDiscover,
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.local_fire_department_outlined,
                      label: l.isArabic
                          ? 'لحظات: حسابات رائجة'
                          : 'Moments: hot official shares',
                      onTap: () {
                        _navPush(
                          MomentsPage(
                            baseUrl: _baseUrl,
                            initialHotOfficialsOnly: true,
                          ),
                        );
                      },
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.live_tv_outlined,
                      label: l.isArabic ? 'القنوات' : 'Channels',
                      badgeLabel: _hasDefaultOfficialAccount
                          ? (l.isArabic ? 'منشئ' : 'Creator')
                          : null,
                      onTap: () {
                        _navPush(
                          ChannelsPage(
                            baseUrl: _baseUrl,
                          ),
                        );
                      },
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.radio_button_checked,
                      label: l.isArabic
                          ? 'القنوات: البث المباشر'
                          : 'Channels: live now',
                      onTap: () {
                        _navPush(
                          ChannelsPage(
                            baseUrl: _baseUrl,
                            initialLiveOnly: true,
                          ),
                        );
                      },
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.local_fire_department_outlined,
                      label: l.isArabic
                          ? 'القنوات: المقاطع الرائجة'
                          : 'Channels: hot clips',
                      onTap: () {
                        _navPush(
                          ChannelsPage(
                            baseUrl: _baseUrl,
                            initialHotOnly: true,
                          ),
                        );
                      },
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.tag_outlined,
                      label: l.isArabic
                          ? 'مواضيع اللحظات الشائعة'
                          : 'Trending Moments topics',
                      onTap: () {
                        _navPush(
                          MomentsPage(
                            baseUrl: _baseUrl,
                          ),
                        );
                      },
                    ),
                    if (_walletId.isNotEmpty)
                      _buildDiscoverPromoChip(
                        icon: Icons.card_giftcard_outlined,
                        label: l.isArabic
                            ? 'مهرجان الحزم الحمراء'
                            : 'Red‑packet festival',
                        showUnreadDot: _redpacketMoments30d > 0,
                        badgeIcon: _redpacketMoments30d > 0
                            ? Icons.photo_library_outlined
                            : null,
                        onTap: () {
                          showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) {
                              final t = Theme.of(ctx);
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Material(
                                  color: t.cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(
                                          Icons.photo_library_outlined,
                                        ),
                                        title: Text(
                                          l.isArabic
                                              ? 'حزم حمراء في اللحظات'
                                              : 'Red packets in Moments',
                                        ),
                                        subtitle: Text(
                                          l.isArabic
                                              ? (_redpacketMoments30d > 0
                                                  ? 'منشورات تحتوي على حزم حمراء (آخر ٣٠ يوماً: $_redpacketMoments30d)'
                                                  : 'عرض المشاركات التي تحتوي على حزم حمراء في اللحظات')
                                              : (_redpacketMoments30d > 0
                                                  ? 'Moments with red packets (last 30 days: $_redpacketMoments30d)'
                                                  : 'See Moments posts that include red packets'),
                                          style:
                                              t.textTheme.bodySmall?.copyWith(
                                            color: t.colorScheme.onSurface
                                                .withValues(alpha: .70),
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.of(ctx).pop();
                                          _navPush(
                                            MomentsPage(
                                              baseUrl: _baseUrl,
                                              initialRedpacketOnly: true,
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.tag_outlined,
                                        ),
                                        title: Text(
                                          l.isArabic
                                              ? 'هاشتاق حزم حمراء'
                                              : 'Red‑packet Moments topic',
                                        ),
                                        subtitle: Text(
                                          l.isArabic
                                              ? 'استعرض المشاركات مع الوسم #ShamellRedPacket'
                                              : 'Browse Moments with #ShamellRedPacket',
                                          style:
                                              t.textTheme.bodySmall?.copyWith(
                                            color: t.colorScheme.onSurface
                                                .withValues(alpha: .70),
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.of(ctx).pop();
                                          _navPush(
                                            MomentsPage(
                                              baseUrl: _baseUrl,
                                              topicTag: '#ShamellRedPacket',
                                            ),
                                          );
                                        },
                                      ),
                                      if (_walletId.isNotEmpty)
                                        ListTile(
                                          leading: const Icon(
                                            Icons.card_giftcard_outlined,
                                          ),
                                          title: Text(
                                            l.isArabic
                                                ? 'سجل الحزم الحمراء'
                                                : 'Red‑packet history',
                                          ),
                                          subtitle: Text(
                                            l.isArabic
                                                ? 'عرض سجل الحزم الحمراء في المحفظة'
                                                : 'View your red‑packet history in the wallet',
                                            style:
                                                t.textTheme.bodySmall?.copyWith(
                                              color: t.colorScheme.onSurface
                                                  .withValues(alpha: .70),
                                            ),
                                          ),
                                          onTap: () {
                                            Navigator.of(ctx).pop();
                                            _navPush(
                                              PaymentsPage(
                                                _baseUrl,
                                                _walletId,
                                                deviceId,
                                                initialSection:
                                                    'redpacket_history',
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    _buildDiscoverPromoChip(
                      icon: Icons.location_on_outlined,
                      label: l.isArabic ? 'الأشخاص القريبون' : 'People nearby',
                      onTap: () => _navPush(
                        PeopleNearbyPage(
                          baseUrl: _baseUrl,
                          recommendedOfficials: _officialStripAccounts,
                          recommendedCityLabel: _officialStripCityLabel,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_trendingMiniPrograms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l.isArabic
                          ? 'أفضل البرامج المصغّرة هذا الأسبوع'
                          : 'Top mini‑programs this week',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .80),
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _trendingMiniPrograms.map((p) {
                      final id = (p['app_id'] ?? '').toString();
                      final titleEn = (p['title_en'] ?? '').toString();
                      final titleAr = (p['title_ar'] ?? '').toString();
                      final isArabic = l.isArabic;
                      final label = isArabic && titleAr.isNotEmpty
                          ? titleAr
                          : (titleEn.isNotEmpty ? titleEn : id);
                      final usageRaw = p['usage_score'];
                      final ratingRaw = p['rating'];
                      final moments30Raw = p['moments_shares_30d'];
                      final usage = usageRaw is num ? usageRaw.toInt() : 0;
                      final rating =
                          ratingRaw is num ? ratingRaw.toDouble() : 0.0;
                      final moments30 =
                          moments30Raw is num ? moments30Raw.toInt() : 0;
                      final isHot =
                          usage >= 50 || rating >= 4.5 || moments30 >= 5;
                      if (id.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final subtitle = () {
                        if (moments30 > 0) {
                          return isArabic
                              ? 'مشاركات في اللحظات (٣٠ يوماً): $moments30'
                              : 'Moments (30d): $moments30';
                        }
                        if (usage > 0) {
                          return isArabic ? 'استخدام: $usage' : 'Usage: $usage';
                        }
                        return null;
                      }();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Icon(
                            isHot
                                ? Icons.local_fire_department_outlined
                                : Icons.widgets_outlined,
                            size: 18,
                          ),
                          label: Text(label),
                          tooltip: subtitle,
                          onPressed: () {
                            _navPush(
                              MiniProgramPage(
                                id: id,
                                baseUrl: _baseUrl,
                                walletId: _walletId,
                                deviceId: deviceId,
                                onOpenMod: _openMod,
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              if (_pinnedMiniApps.isNotEmpty ||
                  _pinnedMiniProgramsOrder.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l.isArabic
                          ? 'التطبيقات/البرامج المصغّرة المثبتة'
                          : 'Pinned mini‑apps/programs',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .80),
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <String>{
                      for (final id in _pinnedMiniProgramsOrder) id.trim(),
                      for (final id in _pinnedMiniApps) id.trim(),
                    }
                        .where((id) => id.isNotEmpty)
                        .map((id) => _buildDiscoverChip(id, l))
                        .where((w) => w != null)
                        .cast<Widget>()
                        .toList(),
                  ),
                ),
              ],
              if (_recentModules.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l.isArabic ? 'مستخدمة مؤخراً' : 'Recently used',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .80),
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _recentModules
                        .map((id) => _buildDiscoverChip(id, l))
                        .where((w) => w != null)
                        .cast<Widget>()
                        .toList(),
                  ),
                ),
              ],
              Row(
                children: [
                  TextButton(
                    onPressed: _openMiniProgramsDiscover,
                    child: Text(
                        l.isArabic ? 'كل التطبيقات المصغرة' : 'All mini‑apps'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _scanMiniAppQr,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: Text(
                      l.isArabic ? 'مسح رمز تطبيق' : 'Scan mini‑app QR',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _buildHomeRoute()),
      ],
    );
  }

  /// Tab 2 – Wallet: focused money & payments hub.

  /// Tab 3 – Me: profile, journey, settings and ops/admin tools.
  Widget _buildMeTab() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : WeChatPalette.background;
    String avatarInitial() {
      final n = _profileName.trim();
      if (n.isNotEmpty) {
        return n.characters.first.toUpperCase();
      }
      final p = _profilePhone.trim();
      if (p.isNotEmpty) {
        return p.characters.last;
      }
      return '?';
    }

    final displayName =
        _profileName.trim().isNotEmpty ? _profileName.trim() : l.menuProfile;
    final shamellId = _profileShamellId.trim();
    final shamellLabel = l.isArabic ? 'معرّف Shamell' : 'Shamell ID';

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    if (_wechatStrictUi) {
      return Container(
        color: bgColor,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            WeChatSection(
              margin: const EdgeInsets.only(top: 0),
              dividerIndent: 16,
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 56,
                      height: 56,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: isDark ? .35 : .90),
                      alignment: Alignment.center,
                      child: Text(
                        avatarInitial(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    shamellId.isNotEmpty
                        ? '$shamellLabel: $shamellId'
                        : (_profilePhone.trim().isNotEmpty
                            ? _profilePhone.trim()
                            : (l.isArabic
                                ? 'عرض بيانات الحساب والمحفظة'
                                : 'View your account and wallet details')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkResponse(
                        onTap: _showFriendQr,
                        radius: 22,
                        child: Icon(
                          Icons.qr_code_2_outlined,
                          size: 20,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
                        ),
                      ),
                      const SizedBox(width: 8),
                      chevron(),
                    ],
                  ),
                  onTap: () => _navPush(ProfilePage(_baseUrl)),
                ),
              ],
            ),
            WeChatSection(
              children: [
                ListTile(
                  dense: true,
                  leading: const WeChatLeadingIcon(
                    icon: Icons.account_balance_wallet_outlined,
                    background: WeChatPalette.green,
                  ),
                  title: Text(
                    l.mePayEntryTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: chevron(),
                  onTap: () =>
                      _navPush(PaymentsPage(_baseUrl, _walletId, deviceId)),
                ),
              ],
            ),
            WeChatSection(
              children: [
                ListTile(
                  dense: true,
                  leading: const WeChatLeadingIcon(
                    icon: Icons.star_outline,
                    background: Color(0xFFF59E0B),
                  ),
                  title: Text(l.isArabic ? 'المفضلة' : 'Favorites'),
                  trailing: chevron(),
                  onTap: () => _navPush(FavoritesPage(baseUrl: _baseUrl)),
                ),
                if (_pluginShowMoments)
                  ListTile(
                    dense: true,
                    leading: const WeChatLeadingIcon(
                      icon: Icons.photo_library_outlined,
                      background: Color(0xFF10B981),
                    ),
                    title: Text(l.mirsaalChannelMomentsTitle),
                    trailing: chevron(),
                    onTap: () {
                      _navPush(
                        MomentsPage(
                          baseUrl: _baseUrl,
                          showOnlyMine: true,
                          showComposer: true,
                        ),
                      );
                    },
                  ),
                if (_pluginShowCardsOffers)
                  ListTile(
                    dense: true,
                    leading: const WeChatLeadingIcon(
                      icon: Icons.card_giftcard_outlined,
                      background: Color(0xFF3B82F6),
                    ),
                    title: Text(
                        l.isArabic ? 'البطاقات والعروض' : 'Cards & Offers'),
                    trailing: chevron(),
                    onTap: () {
                      _navPush(
                        CardsOffersPage(
                          baseUrl: _baseUrl,
                          walletId: _walletId,
                          deviceId: deviceId,
                        ),
                      );
                    },
                  ),
                if (_pluginShowStickers)
                  ListTile(
                    dense: true,
                    leading: const WeChatLeadingIcon(
                      icon: Icons.emoji_emotions_outlined,
                      background: Color(0xFF7C3AED),
                    ),
                    title: Text(l.isArabic ? 'الملصقات' : 'Sticker Gallery'),
                    trailing: chevron(),
                    onTap: () => _navPush(StickerStorePage(baseUrl: _baseUrl)),
                  ),
              ],
            ),
            WeChatSection(
              children: [
                ListTile(
                  dense: true,
                  leading: const WeChatLeadingIcon(
                    icon: Icons.settings_outlined,
                    background: Color(0xFF64748B),
                  ),
                  title: Text(l.settingsTitle),
                  trailing: chevron(),
                  onTap: _openWeChatSettings,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      color: bgColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(
                    avatarInitial(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shamellId.isNotEmpty
                            ? '$shamellLabel: $shamellId'
                            : (_profilePhone.trim().isNotEmpty
                                ? _profilePhone.trim()
                                : (l.isArabic
                                    ? 'عرض بيانات الحساب والمحفظة'
                                    : 'View your account and wallet details')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.qr_code_2_outlined),
                  onPressed: () {
                    _navPush(ProfilePage(_baseUrl));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Tokens.colorPayments.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Tokens.colorPayments,
                    ),
                  ),
                  title: Text(
                    l.mePayEntryTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _walletId.isEmpty
                        ? l.mePayEntrySubtitleSetup
                        : l.mePayEntrySubtitleManage,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _navPush(PaymentsPage(_baseUrl, _walletId, deviceId));
                  },
                ),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 16,
                  endIndent: 16,
                  color: theme.dividerColor.withValues(alpha: .40),
                ),
                ListTile(
                  leading: const Icon(Icons.search),
                  title: Text(l.isArabic ? 'بحث' : 'Search'),
                  subtitle: Text(
                    l.isArabic
                        ? 'ابحث عن الخدمات، التطبيقات المصغّرة واللحظات'
                        : 'Search services, mini‑apps and Moments',
                  ),
                  onTap: () {
                    _navPush(
                      GlobalSearchPage(
                        baseUrl: _baseUrl,
                        walletId: _walletId,
                        deviceId: deviceId,
                        onOpenMod: _openMod,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.isArabic ? 'الحساب والخدمات' : 'Account & services',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          if (_hasDefaultOfficialAccount)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(
                l.isArabic ? 'مركز الحساب الرسمي' : 'Official account console',
              ),
              subtitle: Text(
                l.isArabic
                    ? 'لوحة مُبسّطة لإدارة الحساب الرسمي، الحملات، القنوات والأثر في اللحظات.'
                    : 'Lightweight console for managing your official account, campaigns, Channels and Moments impact.',
              ),
              onTap: () async {
                try {
                  final sp = await SharedPreferences.getInstance();
                  final accId =
                      sp.getString('official.default_account_id') ?? '';
                  final accName =
                      sp.getString('official.default_account_name') ?? '';
                  if (accId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          l.isArabic
                              ? 'لا يوجد حساب رسمي مرتبط لهذا المستخدم.'
                              : 'No default official account linked to this user.',
                        ),
                      ),
                    );
                    return;
                  }
                  _navPush(
                    OfficialOwnerConsolePage(
                      baseUrl: _baseUrl,
                      accountId: accId,
                      accountName: accName.isNotEmpty ? accName : accId,
                    ),
                  );
                } catch (_) {}
              },
            ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: Text(l.isArabic ? 'الأصدقاء' : 'Friends'),
            subtitle: Text(() {
              if (_friendsCount > 0 || _closeFriendsCount > 0) {
                if (l.isArabic) {
                  return 'عدد الأصدقاء: $_friendsCount · الأصدقاء المقرّبون: $_closeFriendsCount';
                }
                return 'Friends: $_friendsCount · Close friends: $_closeFriendsCount';
              }
              return l.isArabic
                  ? 'إدارة شبكة الأصدقاء واختيار الأصدقاء المقرّبين للحظات'
                  : 'Manage your friends and choose close friends for Moments';
            }()),
            onTap: () {
              _navPush(FriendsPage(_baseUrl, mode: FriendsPageMode.manage));
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.verified_outlined),
                if (_hasUnreadOfficialFeeds)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(l.isArabic ? 'الحسابات الرسمية' : 'Official accounts'),
            subtitle: Text(
              () {
                final base = _unreadOfficialAccounts > 0
                    ? (l.isArabic
                        ? 'متابَعة: $_followedServiceCount خدمة · $_followedSubscriptionCount اشتراك · $_unreadOfficialAccounts حساب غير مقروء'
                        : 'Following: $_followedServiceCount Service · $_followedSubscriptionCount Subscriptions · $_unreadOfficialAccounts with unread updates')
                    : (l.isArabic
                        ? 'متابَعة: $_followedServiceCount خدمة · $_followedSubscriptionCount اشتراك'
                        : 'Following: $_followedServiceCount Service · $_followedSubscriptionCount Subscriptions');
                final svc = _officialServiceMoments;
                final sub = _officialSubscriptionMoments;
                final hot = _officialHotAccounts;
                var out = base;
                if (svc > 0 || sub > 0) {
                  final extra = l.isArabic
                      ? ' · منشورات في اللحظات: $svc خدمة · $sub اشتراك'
                      : ' · Moments shares: $svc from services · $sub from subscriptions';
                  out = '$out$extra';
                }
                if (hot > 0) {
                  final extraHot = l.isArabic
                      ? ' · حسابات رائجة في اللحظات: $hot'
                      : ' · Hot in Moments: $hot accounts';
                  out = '$out$extraHot';
                }
                return out;
              }(),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Perf.action('official_open_directory_from_me_tile');
              _navPush(
                OfficialAccountsPage(
                  baseUrl: _baseUrl,
                  initialCityFilter: _officialStripCityLabel,
                  initialKindFilter: null,
                  onOpenChat: (peerId) {
                    if (peerId.isEmpty) return;
                    _navPush(
                      ThreemaChatPage(
                        baseUrl: _baseUrl,
                        initialPeerId: peerId,
                      ),
                    );
                  },
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_business_outlined),
            title: Text(
              l.isArabic
                  ? 'تسجيل حساب رسمي جديد'
                  : 'Register new official account',
            ),
            subtitle: Text(
              l.isArabic
                  ? 'إنشاء حساب رسمي لخدمتك على نمط WeChat (يبدأ كطلب قيد المراجعة).'
                  : 'Create a WeChat‑style Official account for your service (starts as a request under review).',
            ),
            onTap: () {
              _navPush(
                OfficialAccountRegisterPage(
                  baseUrl: _baseUrl,
                ),
              );
            },
          ),
          if (_followedOfficialsPreview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l.isArabic ? 'الخدمات المميزة' : 'Starred services',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              () {
                final serviceStarred = _followedOfficialsPreview
                    .where((a) => (a.kind.toLowerCase() == 'service'))
                    .length;
                final subStarred = _followedOfficialsPreview
                    .where((a) => (a.kind.toLowerCase() == 'subscription'))
                    .length;
                if (l.isArabic) {
                  return 'مميزة: $serviceStarred خدمة · $subStarred اشتراك';
                }
                return 'Starred: $serviceStarred services · $subStarred subscriptions';
              }(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 4),
            GridView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 3.5,
              ),
              itemCount: _followedOfficialsPreview.length,
              itemBuilder: (ctx, i) {
                final acc = _followedOfficialsPreview[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Perf.action('official_open_from_me_starred');
                    _navPush(
                      OfficialAccountFeedPage(
                        baseUrl: _baseUrl,
                        account: acc,
                        onOpenChat: (peerId) {
                          if (peerId.isEmpty) return;
                          _navPush(
                            ThreemaChatPage(
                              baseUrl: _baseUrl,
                              initialPeerId: peerId,
                            ),
                          );
                        },
                      ),
                    );
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: .40),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundImage:
                              acc.avatarUrl != null && acc.avatarUrl!.isNotEmpty
                                  ? NetworkImage(acc.avatarUrl!)
                                  : null,
                          child: (acc.avatarUrl == null ||
                                  acc.avatarUrl!.isEmpty)
                              ? Text(
                                  acc.name.isNotEmpty
                                      ? acc.name.characters.first.toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      acc.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (acc.featured) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4.0),
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: theme.colorScheme.secondary,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4.0),
                                      child: Icon(
                                        Icons.local_fire_department_outlined,
                                        size: 14,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: .85),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if ((acc.category ?? '').isNotEmpty)
                                Text(
                                  acc.category!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .70),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            leading: const Icon(Icons.notifications_none_outlined),
            title: Text(
              l.isArabic
                  ? 'إشعارات الحسابات الرسمية'
                  : 'Official notifications',
            ),
            subtitle: Text(
              l.isArabic
                  ? 'تعيين وضع الإشعارات لخدماتك واشتراكاتك'
                  : 'Set notification mode for your service and subscription accounts',
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openOfficialNotifications,
            onLongPress: () {
              _navPush(
                OfficialNotificationsDebugPage(baseUrl: _baseUrl),
              );
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.mark_email_unread_outlined),
            title: Text(
              l.isArabic ? 'إشعارات الخدمات' : 'Service notifications',
            ),
            subtitle: Text(
              l.isArabic
                  ? 'مركز رسائل الحسابات الرسمية بأسلوب WeChat Service Notifications'
                  : 'Notification center for official accounts, similar to WeChat Service Notifications',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasUnreadServiceNotifications)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            onTap: () {
              _navPush(
                OfficialTemplateMessagesPage(
                  baseUrl: _baseUrl,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'المحتوى واللحظات' : 'Content & Moments',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          if (_hasUnreadOfficialFeeds) ...[
            const SizedBox(height: 4),
            ListTile(
              dense: true,
              leading: const Icon(Icons.subscriptions_outlined),
              title: Text(
                l.isArabic
                    ? 'عرض تحديثات الاشتراك'
                    : 'View subscription updates',
              ),
              subtitle: Text(
                l.isArabic
                    ? 'فتح خلاصة الاشتراكات في Mirsaal'
                    : 'Open the subscriptions feed in Mirsaal',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .70),
                    ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Perf.action('official_open_subscriptions_from_me_tile');
                _navPush(
                  ThreemaChatPage(
                    baseUrl: _baseUrl,
                    initialPeerId: '__official_subscriptions__',
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Perf.action('official_open_directory_from_me_service');
                    _navPush(
                      OfficialAccountsPage(
                        baseUrl: _baseUrl,
                        initialCityFilter: _officialStripCityLabel,
                        initialKindFilter: 'service',
                        onOpenChat: (peerId) {
                          if (peerId.isEmpty) return;
                          _navPush(
                            ThreemaChatPage(
                              baseUrl: _baseUrl,
                              initialPeerId: peerId,
                            ),
                          );
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.miscellaneous_services_outlined,
                      size: 18),
                  label: Text(
                    l.isArabic ? 'حسابات الخدمات' : 'Service accounts',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Perf.action('official_open_directory_from_me_subscription');
                    _navPush(
                      OfficialAccountsPage(
                        baseUrl: _baseUrl,
                        initialCityFilter: _officialStripCityLabel,
                        initialKindFilter: 'subscription',
                        onOpenChat: (peerId) {
                          if (peerId.isEmpty) return;
                          _navPush(
                            ThreemaChatPage(
                              baseUrl: _baseUrl,
                              initialPeerId: peerId,
                            ),
                          );
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.subscriptions_outlined, size: 18),
                  label: Text(
                    l.isArabic ? 'حسابات الاشتراك' : 'Subscription accounts',
                  ),
                ),
              ),
            ],
          ),
          if (_latestOfficialUpdates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l.isArabic
                  ? 'آخر التحديثات من الحسابات الرسمية'
                  : 'Latest from officials',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            const SizedBox(height: 4),
            ..._latestOfficialUpdates.map((u) {
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundImage:
                      (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
                          ? NetworkImage(u.avatarUrl!)
                          : null,
                  child: (u.avatarUrl == null || u.avatarUrl!.isEmpty)
                      ? Text(
                          u.accountName.isNotEmpty
                              ? u.accountName.characters.first.toUpperCase()
                              : '?',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )
                      : null,
                ),
                title: Text(
                  u.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  u.accountName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                onTap: () {
                  Perf.action('official_open_from_me_latest');
                  _navPush(
                    OfficialAccountDeepLinkPage(
                      baseUrl: _baseUrl,
                      accountId: u.accountId,
                      onOpenChat: (peerId) {
                        if (peerId.isEmpty) return;
                        _navPush(
                          ThreemaChatPage(
                            baseUrl: _baseUrl,
                            initialPeerId: peerId,
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            }),
          ],
          ListTile(
            dense: true,
            leading: const Icon(Icons.bookmark_outline),
            title: Text(l.isArabic ? 'المفضلة' : 'Favorites'),
            subtitle: Text(
              l.isArabic
                  ? 'احفظ الروابط أو الملاحظات المهمة'
                  : 'Save important links or notes',
            ),
            onTap: () {
              _navPush(FavoritesPage(baseUrl: _baseUrl));
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l.isArabic ? 'اللحظات' : 'Moments'),
            subtitle: Text(() {
              final base = l.isArabic
                  ? 'مشاركات مع الأصدقاء وخدمة الحسابات الرسمية'
                  : 'Share moments with friends and official accounts';
              final rp = _redpacketMoments30d;
              String out = base;
              if (rp > 0) {
                final extra = l.isArabic
                    ? ' · حزم حمراء في آخر ٣٠ يوماً: $rp'
                    : ' · Red packets in last 30 days: $rp';
                out = '$out$extra';
              }
              if (_trendingTopicsShort.isNotEmpty) {
                final tags =
                    _trendingTopicsShort.take(3).map((t) => '#$t').join(', ');
                final extraTopics = l.isArabic
                    ? ' · مواضيع شائعة: $tags'
                    : ' · Trending topics: $tags';
                out = '$out$extraTopics';
              }
              return out;
            }()),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasUnreadMoments)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            onTap: () {
              _navPush(
                MomentsPage(
                  baseUrl: _baseUrl,
                  onOpenOfficialDirectory: (ctx) {
                    _navPush(
                      OfficialAccountsPage(
                        baseUrl: _baseUrl,
                        initialCityFilter: _officialStripCityLabel,
                        onOpenChat: (peerId) {
                          if (peerId.isEmpty) return;
                          _navPush(
                            ThreemaChatPage(
                              baseUrl: _baseUrl,
                              initialPeerId: peerId,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.emoji_emotions_outlined),
            title: Text(l.isArabic ? 'الملصقات' : 'Stickers'),
            subtitle: Text(
              l.isArabic
                  ? 'استعرض وحمّل حزم الملصقات للدردشة'
                  : 'Browse and install chat sticker packs',
            ),
            onTap: () {
              _navPush(StickerStorePage(baseUrl: _baseUrl));
            },
          ),
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: Text(
              l.isArabic ? 'التطبيقات المصغرة' : 'Mini‑programs',
            ),
            subtitle: Text(() {
              final pinned = _pinnedMiniApps.length;
              final recent = _recentModules.length;
              if (pinned > 0 || recent > 0) {
                if (l.isArabic) {
                  return 'خدمات/برامج مصغّرة مثبتة: $pinned · مستخدمة مؤخراً: $recent';
                }
                return 'Pinned mini‑apps/programs: $pinned · Recently used: $recent';
              }
		              return l.isArabic
		                  ? 'استعرض تطبيقات وخدمات مثل الباص والمحفظة'
		                  : 'Browse mini‑apps and mini‑programs like Bus and Wallet';
		            }()),
	            onTap: _openMiniProgramsDiscover,
	          ),
          if (_miniProgramsCount > 0 || _showOps) ...[
            const SizedBox(height: 12),
            Text(
              l.isArabic
                  ? 'مركز مطوري البرامج المصغّرة'
                  : 'Mini‑program Dev Center',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            const SizedBox(height: 4),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.widgets_outlined),
                    title: Text(
                      l.isArabic ? 'برامجي المصغّرة' : 'My mini‑programs',
                    ),
                    subtitle: Text(() {
                      if (_miniProgramsCount > 0) {
                        if (l.isArabic) {
                          return 'عدد البرامج: $_miniProgramsCount · الفتحات: $_miniProgramsTotalUsage · اللحظات (٣٠ يوماً): $_miniProgramsMoments30d';
                        }
                        return 'Mini‑programs: $_miniProgramsCount · Opens: $_miniProgramsTotalUsage · Moments (30d): $_miniProgramsMoments30d';
                      }
                      return l.isArabic
                          ? 'لوحة مطور صغيرة لبرامجك المصغّرة'
                          : 'Developer dashboard for your mini‑programs';
                    }()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _navPush(
                        MyMiniProgramsPage(
                          baseUrl: _baseUrl,
                          walletId: _walletId,
                          deviceId: deviceId,
                          onOpenMod: _openMod,
                        ),
                      );
                    },
                  ),
                  if (_showOps) const Divider(height: 1),
                  if (_showOps)
                    ListTile(
                      leading: const Icon(Icons.add_box_outlined),
                      title: Text(
                        l.isArabic
                            ? 'تسجيل برنامج مصغر جديد'
                            : 'Register new mini‑program',
                      ),
                      subtitle: Text(
                        l.isArabic
                            ? 'إنشاء برنامج مصغر على نمط WeChat لحسابك (يبدأ كمسودة قيد المراجعة).'
                            : 'Create a WeChat‑style mini‑program (starts as a draft under review).',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _navPush(
                          MiniProgramRegisterPage(
                            baseUrl: _baseUrl,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.photo_album_outlined),
            title: Text(
              l.isArabic ? 'لحظاتي فقط' : 'My Moments',
            ),
            subtitle: Text(
              l.isArabic
                  ? 'عرض اللحظات التي قمت بنشرها'
                  : 'View only the moments you posted',
            ),
            onTap: () {
              _navPush(
                MomentsPage(
                  baseUrl: _baseUrl,
                  showOnlyMine: true,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          if (_walletId.isNotEmpty)
            Text(
              l.isArabic ? 'المحفظة والحملات' : 'Wallet & campaigns',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
          if (_walletId.isNotEmpty) const SizedBox(height: 4),
          if (_walletId.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.qr_code_2_outlined),
              title: Text(
                l.isArabic ? 'رمز الدفع الخاص بي' : 'My pay code',
              ),
              subtitle: Text(
                l.isArabic
                    ? 'عرض رمز QR لاستلام المدفوعات عبر Shamell Pay، مشابه لرمز WeChat Pay.'
                    : 'Show a QR code to receive payments via Shamell Pay, similar to a WeChat Pay money code.',
              ),
              onTap: () {
                _navPush(
                  PaymentsPage(
                    _baseUrl,
                    _walletId,
                    deviceId,
                    initialSection: 'receive',
                  ),
                );
              },
            ),
          if (_walletId.isNotEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.qr_code_2_outlined),
                    title: Text(
                      l.isArabic ? 'رمز الدفع الخاص بي' : 'My pay code',
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عرض رمز QR لاستلام المدفوعات عبر Shamell Pay، مشابه لرمز WeChat Pay.'
                          : 'Show a QR code to receive payments via Shamell Pay, similar to a WeChat Pay money code.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _navPush(
                        PaymentsPage(
                          _baseUrl,
                          _walletId,
                          deviceId,
                          initialSection: 'receive',
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.card_giftcard_outlined),
                    title: Text(
                      l.isArabic ? 'حزم حمراء' : 'Red packets',
                    ),
                    subtitle: Text(() {
                      final base = l.isArabic
                          ? 'سجل الحزم الحمراء في Mirsaal'
                          : 'View your Mirsaal red‑packet history';
                      final rp = _redpacketMoments30d;
                      if (rp > 0) {
                        final extra = l.isArabic
                            ? ' · حزم حمراء في اللحظات (آخر ٣٠ يوماً): $rp'
                            : ' · Red packets in Moments (last 30 days): $rp';
                        return '$base$extra';
                      }
                      return base;
                    }()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _navPush(
                        PaymentsPage(
                          _baseUrl,
                          _walletId,
                          deviceId,
                          initialSection: 'redpacket_history',
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: Text(
                      l.isArabic
                          ? 'حملات الحزم الحمراء'
                          : 'Red‑packet campaigns',
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'إدارة حملات الحزم الحمراء ومشاركتها في اللحظات'
                          : 'Manage your red‑packet campaigns and share them in Moments',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      try {
                        final sp = await SharedPreferences.getInstance();
                        final accId =
                            sp.getString('official.default_account_id') ?? '';
                        final accName =
                            sp.getString('official.default_account_name') ?? '';
                        if (accId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                l.isArabic
                                    ? 'لا يوجد حساب رسمي مرتبط لإدارة الحملات.'
                                    : 'No linked official account to manage campaigns.',
                              ),
                            ),
                          );
                          return;
                        }
                        _navPush(
                          RedpacketCampaignsPage(
                            baseUrl: _baseUrl,
                            accountId: accId,
                            accountName: accName.isNotEmpty ? accName : accId,
                          ),
                        );
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.live_tv_outlined),
            title: Text(
              l.isArabic ? 'قنواتي' : 'My Channels',
            ),
            subtitle: Text(
              l.isArabic
                  ? 'لوحة منشئ القنوات: عرض المقاطع والمشاهدات والإعجابات والتعليقات وتأثيرها في اللحظات لحسابك الرسمي'
                  : 'Channels creator dashboard: view clips, views, likes, comments and Moments impact for your official account',
            ),
            onTap: () async {
              try {
                final sp = await SharedPreferences.getInstance();
                final accId = sp.getString('official.default_account_id') ?? '';
                final accName =
                    sp.getString('official.default_account_name') ?? '';
                if (accId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l.isArabic
                            ? 'لا يوجد حساب رسمي مرتبط لعرض تحليلات القنوات.'
                            : 'No linked official account to show Channels insights.',
                      ),
                    ),
                  );
                  return;
                }
                _navPush(
                  ChannelsPage(
                    baseUrl: _baseUrl,
                    officialAccountId: accId,
                    officialName: accName.isNotEmpty ? accName : accId,
                    initialHotOnly: false,
                  ),
                );
              } catch (_) {}
            },
          ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.timeline),
                  title: Text(l.journeyTitle),
                  subtitle: Text(
                    l.isArabic
                        ? 'نظرة عامة على الأدوار والتنقل'
                        : 'Overview of your roles and mobility',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _navPush(JourneyPage(_baseUrl));
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.devices_other_outlined),
                  title: Text(
                    l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices',
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'إدارة مرسال ويب ومرسال على أجهزة أخرى وتسجيل الخروج عن بُعد'
                        : 'Manage Mirsaal Web / Desktop logins and sign out from other devices',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _navPush(DevicesPage(baseUrl: _baseUrl));
                  },
                ),
              ],
            ),
          ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(
                    l.isArabic
                        ? 'الوسائط والملفات في الدردشات'
                        : 'Media & files in chats',
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'استعرض الصور والملفات والروابط من كل الدردشات في مكان واحد.'
                        : 'Browse photos, files and links from all chats in one place.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _navPush(GlobalMediaPage(baseUrl: _baseUrl));
                  },
                ),
                const Divider(height: 1),
	                ListTile(
	                  leading: const Icon(Icons.receipt_long_outlined),
	                  title: Text(l.isArabic ? 'رحلاتي' : 'My trips'),
		                  subtitle: Text(
		                    l.isArabic
		                        ? 'كل رحلات وحجوزات الباص في مكان واحد'
		                        : 'All bus trips and bookings in one place',
		                  ),
	                  trailing: const Icon(Icons.chevron_right),
	                  onTap: () {
	                    _navPush(OrderCenterPage(_baseUrl));
	                  },
                ),
                if (_walletId.isNotEmpty) const Divider(height: 1),
                if (_walletId.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(l.historyTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _navPush(
                          HistoryPage(baseUrl: _baseUrl, walletId: _walletId));
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'الإعدادات والمساعدة' : 'Settings & help',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: Text(l.isArabic ? 'دليل سريع' : 'Quick guide'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openOnboarding,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text(l.settingsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _navPush(
                        SettingsPage(baseUrl: _baseUrl, walletId: _walletId));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.isArabic ? 'الدعم والسلامة' : 'Support & safety',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(l.menuEmergency),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showEmergency,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.report_problem_outlined),
                  title: Text(l.menuComplaints),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showComplaints,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: Text(l.menuCallUs),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _callUs,
                ),
              ],
            ),
          ),
          if (!kEnduserOnly && _hasOpsRole(_roles)) ...[
            const SizedBox(height: 12),
            Text(
              l.isArabic ? 'لوحة المشغل والمسؤول' : 'Ops & admin workbench',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            const SizedBox(height: 4),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: Text(l.menuSwitchMode),
                    subtitle: Text(
                      l.isArabic
                          ? 'التبديل بين مستخدم / مشغل / مسؤول'
                          : 'Switch between user / operator / admin modes',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showModeSheet,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.dashboard_customize_outlined),
                    title: Text(l.menuOperatorConsole),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _navPush(OperatorDashboardPage(_baseUrl));
                    },
                  ),
                  if (!kEnduserOnly && _hasAdminRole(_roles))
                    const Divider(height: 1),
                  if (!kEnduserOnly && _hasAdminRole(_roles))
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: Text(l.menuAdminConsole),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _navPush(AdminDashboardPage(_baseUrl));
                      },
                    ),
                  if (!kEnduserOnly && _showSuperadmin)
                    const Divider(height: 1),
                  if (!kEnduserOnly && _showSuperadmin)
                    ListTile(
                      leading: const Icon(Icons.security),
                      title: Text(l.menuSuperadminConsole),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _navPush(SuperadminDashboardPage(_baseUrl));
                      },
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.opsTitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .80),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildOpsWorkbenchShortcuts(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l.menuLogout),
            subtitle: Text(
              l.menuLogoutSubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  /// Compact WeChat‑style grid of operator / admin shortcuts inside Me tab.
  Widget _buildOpsWorkbenchShortcuts(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    Widget tile({
      required IconData icon,
      required String label,
      required Color tint,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 88,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: tint.withValues(alpha: .95),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

	    final shortcuts = <Widget>[];

	    if (_operatorDomains.contains('bus')) {
	      shortcuts.add(
	        tile(
	          icon: Icons.directions_bus_filled_outlined,
          label: l.isArabic ? 'مشغل الباص' : 'Bus operator',
          tint: Tokens.colorBus,
          onTap: () {
            final baseUri = Uri.tryParse(_baseUrl);
            final uri = baseUri?.resolve('/bus/admin') ??
                Uri.parse(
                    '${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/bus/admin');
            _navPush(
              WeChatWebViewPage(
                initialUri: uri,
                baseUri: baseUri,
                initialTitle: l.isArabic ? 'إدارة الباص' : 'Bus admin',
              ),
            );
          },
        ),
      );
    }
    // Risk / exports / parametrics – admin web consoles.
    if (_hasAdminRole(_roles) || _hasSuperadminRole(_roles)) {
      shortcuts.add(
        tile(
          icon: Icons.shield_moon_outlined,
          label: l.isArabic ? 'مخاطر' : 'Risk admin',
          tint: Tokens.colorPayments,
          onTap: () {
            launchWithSession(Uri.parse('$_baseUrl/admin/risk'));
          },
        ),
      );
      shortcuts.add(
        tile(
          icon: Icons.file_download_outlined,
          label: l.isArabic ? 'التقارير' : 'Exports',
          tint: Tokens.colorPayments,
          onTap: () {
            launchWithSession(Uri.parse('$_baseUrl/admin/exports'));
          },
        ),
      );
      shortcuts.add(
        tile(
          icon: Icons.analytics_outlined,
          label: l.isArabic ? 'المقاييس' : 'Parametrics',
          tint: Tokens.colorPayments,
          onTap: () {
            launchWithSession(Uri.parse('$_baseUrl/admin/overview'));
          },
        ),
      );
      shortcuts.add(
        tile(
          icon: Icons.rule_folder_outlined,
          label: l.isArabic ? 'مراجعة البرامج' : 'Mini‑program review',
          tint: Tokens.colorPayments,
          onTap: () {
            _navPush(MiniProgramsReviewPage(baseUrl: _baseUrl));
          },
        ),
      );
    }

    if (shortcuts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: shortcuts,
    );
  }

  void _openOnboarding() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingPage()),
    );
  }

  Future<void> _loadUnreadBadge() async {
    try {
      final unreadMap = await _chatStore.loadUnread();
      final total =
          unreadMap.values.fold<int>(0, (sum, v) => sum + (v < 0 ? 1 : v));
      if (!mounted) return;
      setState(() {
        _totalUnreadChats = total;
      });
      await _recomputeOfficialUnreadFromPrefs();
    } catch (_) {}
  }

  Future<void> _loadMomentsNotifications() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final seenRaw = (sp.getString('moments.comments_seen_ts') ?? '').trim();
      final uri = Uri.parse('$_baseUrl/moments/notifications');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return;
      final lastTs = (decoded['last_comment_ts'] ?? '').toString().trim();
      final rpRaw = decoded['redpacket_posts_30d'];
      final rp = rpRaw is num ? rpRaw.toInt() : 0;
      bool hasUnread = false;
      if (lastTs.isNotEmpty) {
        if (seenRaw.isEmpty) {
          hasUnread = true;
        } else {
          try {
            final last = DateTime.parse(lastTs);
            final seen = DateTime.parse(seenRaw);
            if (last.isAfter(seen)) {
              hasUnread = true;
            }
          } catch (_) {
            hasUnread = true;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _hasUnreadMoments = hasUnread;
        _redpacketMoments30d = rp;
      });
    } catch (_) {}
  }

  Future<void> _loadOfficialMomentsStats() async {
    try {
      final uri = Uri.parse('$_baseUrl/me/official_moments_stats');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return;
      final svcRaw = decoded['service_shares'];
      final subRaw = decoded['subscription_shares'];
      final hotRaw = decoded['hot_accounts'];
      final svc = svcRaw is num ? svcRaw.toInt() : 0;
      final sub = subRaw is num ? subRaw.toInt() : 0;
      final hot = hotRaw is num ? hotRaw.toInt() : 0;
      if (!mounted) return;
      setState(() {
        _officialServiceMoments = svc;
        _officialSubscriptionMoments = sub;
        _officialHotAccounts = hot;
      });
    } catch (_) {}
  }

  Future<void> _loadTrendingTopicsShort() async {
    try {
      final uri = Uri.parse('$_baseUrl/moments/topics/trending')
          .replace(queryParameters: const {'limit': '3'});
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['items'] is List) {
        raw = decoded['items'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final tags = <String>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final tag = (m['tag'] ?? '').toString().trim();
        if (tag.isEmpty) continue;
        tags.add(tag);
      }
      if (!mounted || tags.isEmpty) return;
      setState(() {
        _trendingTopicsShort = tags;
      });
    } catch (_) {}
  }

  Future<void> _loadTrendingMiniPrograms() async {
    try {
      final uri = Uri.parse('$_baseUrl/mini_programs')
          .replace(queryParameters: const {'limit': '20'});
      final r = await http.get(uri);
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['programs'] is List) {
        raw = decoded['programs'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final list = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        list.add(e.cast<String, dynamic>());
      }
      if (list.isEmpty || !mounted) return;
      list.sort((a, b) {
        int _usage(Map<String, dynamic> m) =>
            (m['usage_score'] is num) ? (m['usage_score'] as num).toInt() : 0;
        double _rating(Map<String, dynamic> m) =>
            (m['rating'] is num) ? (m['rating'] as num).toDouble() : 0.0;
        int _moments30(Map<String, dynamic> m) =>
            (m['moments_shares_30d'] is num)
                ? (m['moments_shares_30d'] as num).toInt()
                : 0;

        double score(Map<String, dynamic> m) {
          final ua = _usage(m);
          final ra = _rating(m);
          final ma = _moments30(m);
          // WeChat‑artige Heuristik für „Top diese Woche“:
          // Nutzung + Rating + Moments‑Shares der letzten 30 Tage.
          return ua + (ra * 8.0) + (ma * 5.0);
        }

        final scoreA = score(a);
        final scoreB = score(b);
        return scoreB.compareTo(scoreA);
      });
      final top = list.length > 6 ? list.sublist(0, 6) : list;
      final sig = top
          .map((p) => (p['app_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .join('|');
      String seenSig = '';
      try {
        final sp = await SharedPreferences.getInstance();
        seenSig = sp.getString('mini_programs.trending_seen_sig') ?? '';
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _trendingMiniPrograms = top;
        _trendingMiniProgramsSig = sig;
        _hasNewTrendingMiniPrograms = sig.isNotEmpty && sig != seenSig;
      });
    } catch (_) {}
  }

  Future<void> _loadServiceNotificationsBadge() async {
    try {
      // Lightweight probe: ask backend for unread-only template messages
      // and treat a non-empty list as "has unread service notifications".
      final uri = Uri.parse('$_baseUrl/me/official_template_messages')
          .replace(queryParameters: const {
        'unread_only': 'true',
        'limit': '1',
      });
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['messages'] is List) {
        raw = decoded['messages'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final hasUnread = raw.isNotEmpty;
      if (!mounted) return;
      setState(() {
        _hasUnreadServiceNotifications = hasUnread;
      });
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setBool(
          'official_template_messages.has_unread',
          hasUnread,
        );
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _loadMiniProgramDeveloperStats() async {
    try {
      final uri = Uri.parse('$_baseUrl/mini_programs/developer_json');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['programs'] is List) {
        raw = decoded['programs'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      int count = 0;
      int totalUsage = 0;
      int totalMoments30 = 0;
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        count += 1;
        final u = m['usage_score'];
        if (u is num) {
          totalUsage += u.toInt();
        }
        final ms30 = m['moments_shares_30d'];
        if (ms30 is num) {
          totalMoments30 += ms30.toInt();
        }
      }
      if (!mounted) return;
      setState(() {
        _miniProgramsCount = count;
        _miniProgramsTotalUsage = totalUsage;
        _miniProgramsMoments30d = totalMoments30;
      });
    } catch (_) {}
  }

  Future<void> _recomputeOfficialUnreadFromPrefs() async {
    if (_officialStripLatestTs.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('official.feed_seen') ?? '{}';
      Map<String, dynamic> seenMap;
      try {
        seenMap = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        seenMap = <String, dynamic>{};
      }
      bool hasUnread = false;
      int unreadAccounts = 0;
      _officialStripLatestTs.forEach((accId, lastTs) {
        final lastRaw = lastTs.trim();
        if (lastRaw.isEmpty) {
          return;
        }
        final seenRaw = (seenMap[accId] ?? '').toString().trim();
        if (seenRaw.isEmpty) {
          hasUnread = true;
          return;
        }
        try {
          final last = DateTime.parse(lastRaw);
          final seen = DateTime.parse(seenRaw);
          if (last.isAfter(seen)) {
            hasUnread = true;
            unreadAccounts += 1;
          }
        } catch (_) {
          hasUnread = true;
          unreadAccounts += 1;
        }
      });
      if (!mounted) return;
      setState(() {
        _hasUnreadOfficialFeeds = hasUnread;
        _unreadOfficialAccounts = unreadAccounts;
      });
    } catch (_) {}
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final storedRoles = sp.getStringList('roles') ?? const [];
    final storedOpDomains = sp.getStringList('operator_domains') ?? const [];
    final storedMode = sp.getString('app_mode');
    final storedPhone = sp.getString('phone') ?? '';
    final storedProfileName = sp.getString('last_login_name') ?? '';
    final storedProfilePhone = sp.getString('last_login_phone') ?? '';
    String derivedShamellId = '';
    final corePhone = storedProfilePhone.trim().replaceAll('+', '');
    if (corePhone.isNotEmpty) {
      derivedShamellId = 'm$corePhone';
    }
    final storedIsSuper = sp.getBool('is_superadmin') ?? false;
    final pluginShowMoments = sp.getBool(_kWeChatPluginShowMoments) ?? true;
    final pluginShowChannels = sp.getBool(_kWeChatPluginShowChannels) ?? true;
    final pluginShowScan = sp.getBool(_kWeChatPluginShowScan) ?? true;
    final pluginShowPeopleNearby =
        sp.getBool(_kWeChatPluginShowPeopleNearby) ?? true;
    final pluginShowMiniPrograms =
        sp.getBool(_kWeChatPluginShowMiniPrograms) ?? true;
    final pluginShowCardsOffers =
        sp.getBool(_kWeChatPluginShowCardsOffers) ?? true;
    final pluginShowStickers = sp.getBool(_kWeChatPluginShowStickers) ?? true;
    // Start from lockedMode when provided; otherwise from currentAppMode and prefs.
    AppMode appMode =
        widget.lockedMode == AppMode.auto ? currentAppMode : widget.lockedMode;
    if (widget.lockedMode == AppMode.auto &&
        storedMode != null &&
        storedMode.isNotEmpty) {
      switch (storedMode.toLowerCase()) {
        case 'user':
          appMode = AppMode.user;
          break;
        case 'operator':
          appMode = AppMode.operator;
          break;
        case 'admin':
          appMode = AppMode.admin;
          break;
        case 'auto':
        default:
          appMode = AppMode.auto;
      }
    }
    final baseShowOps = _computeShowOps(storedRoles, appMode);
    final showSuper = storedIsSuper || storedPhone == kSuperadminPhone;
    final showOps = baseShowOps || showSuper;
    final effectiveMode = kEnduserOnly ? AppMode.user : appMode;
    setState(() {
      _baseUrl = sp.getString('base_url') ?? _baseUrl;
      _walletId = sp.getString('wallet_id') ?? _walletId;
      _pluginShowMoments = pluginShowMoments;
      _pluginShowChannels = pluginShowChannels;
      _pluginShowScan = pluginShowScan;
      _pluginShowPeopleNearby = pluginShowPeopleNearby;
      _pluginShowMiniPrograms = pluginShowMiniPrograms;
      _pluginShowCardsOffers = pluginShowCardsOffers;
      _pluginShowStickers = pluginShowStickers;
      _roles = storedRoles;
      _operatorDomains = storedOpDomains;
      _appMode = effectiveMode;
      _showOps = kEnduserOnly ? false : showOps;
      _showSuperadmin = kEnduserOnly ? false : showSuper;
      _recentModules = sp.getStringList('recent_modules') ?? const [];
      _pinnedMiniApps = sp.getStringList('pinned_miniapps') ?? const [];
      _pinnedMiniProgramsOrder =
          sp.getStringList('mini_programs.pinned_order') ?? const [];
      _recentMiniPrograms =
          sp.getStringList('recent_mini_programs') ?? const [];
      _profileName = storedProfileName;
      _profilePhone = storedProfilePhone;
      _profileShamellId = derivedShamellId;
    });
    unawaited(_refreshMiniProgramUpdateBadges());
    // Configure remote metrics after loading prefs
    final metricsRemote = sp.getBool('metrics_remote') ?? false;
    Perf.configure(
        baseUrl: _baseUrl, deviceId: deviceId, remote: metricsRemote);
    // 1) Optional: Cached Snapshot aus vorheriger Session anwenden, damit Home
    //    sofort etwas sinnvolles anzeigt, auch bevor das Netz greift.
    try {
      final cachedRaw = sp.getString('home_snapshot');
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        final cached = jsonDecode(cachedRaw) as Map<String, dynamic>;
        await _applyHomeSnapshot(cached, sp, appMode, persist: false);
      }
    } catch (_) {}
    // ensure Wallet/Rollen + erste KPIs via Aggregat-Endpunkt (idempotent)
    try {
      final r = await http.get(Uri.parse('$_baseUrl/me/home_snapshot'),
          headers: await _hdr());
      if (r.statusCode == 200) {
        Perf.action('home_snapshot_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        await sp.setString('home_snapshot', r.body);
        await _applyHomeSnapshot(j, sp, appMode, persist: true);
      } else {
        Perf.action('home_snapshot_fail');
      }
    } catch (_) {
      Perf.action('home_snapshot_error');
    }
    // Fallback: explizit Rollen laden, falls Aggregat leer war
    if (_roles.isEmpty) {
      await _loadRoles();
    }
    if (_walletId.isNotEmpty) {
      await _loadWalletSummary();
    }
    // Load KPIs for dashboard when in operator/admin mode
    if (!kEnduserOnly &&
        (_appMode == AppMode.operator || _appMode == AppMode.admin)) {
      unawaited(_loadBusSummary());
    }
  }

  Future<void> _applyHomeSnapshot(
    Map<String, dynamic> j,
    SharedPreferences sp,
    AppMode appMode, {
    required bool persist,
  }) async {
    final phone = (j['phone'] ?? '').toString();
    final isSuperFlag = (j['is_superadmin'] ?? false) == true;
    if (persist) {
      if (phone.isNotEmpty) {
        await sp.setString('phone', phone);
      }
      await sp.setBool('is_superadmin', isSuperFlag);
    }
    final w = (j['wallet_id'] ?? '').toString();
    final rolesFromOverview =
        (j['roles'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final opDomainsFromOverview =
        (j['operator_domains'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    if (w.isNotEmpty) {
      if (persist) {
        await sp.setString('wallet_id', w);
      }
      if (mounted) {
        setState(() {
          _walletId = w;
        });
      }
    }
    if (rolesFromOverview.isNotEmpty) {
      if (persist) {
        await sp.setStringList('roles', rolesFromOverview);
        await sp.setStringList('operator_domains', opDomainsFromOverview);
      }
      final baseShowOps = _computeShowOps(rolesFromOverview, appMode);
      final showSuper = isSuperFlag || phone == kSuperadminPhone;
      final showOps = baseShowOps || showSuper;
	      if (mounted) {
	        setState(() {
	          _roles = rolesFromOverview;
	          _operatorDomains = opDomainsFromOverview;
	          _showOps = showOps;
	          _showSuperadmin = showSuper;
	        });
	      }
	    } else {
      // Even without explicit roles, a flagged Superadmin should see Ops/Superadmin UI.
      final showSuper = isSuperFlag || phone == kSuperadminPhone;
      final showOps = showSuper;
      if (mounted) {
        setState(() {
          _showOps = showOps;
          _showSuperadmin = showSuper;
        });
      }
	    }
	    // Optional: hydrate initial KPIs from the snapshot
	    try {
	      final bs = j['bus_admin_summary'];
	      if (bs is Map<String, dynamic>) {
	        final trips = bs['trips_today'] ?? 0;
        final bookings = bs['bookings_today'] ?? 0;
        final revenueC = bs['revenue_cents_today'] ?? 0;
        final revInt =
            revenueC is int ? revenueC : int.tryParse(revenueC.toString()) ?? 0;
        if (mounted) {
          setState(() {
            _busTripsToday =
                trips is int ? trips : int.tryParse(trips.toString()) ?? 0;
            _busBookingsToday = bookings is int
                ? bookings
                : int.tryParse(bookings.toString()) ?? 0;
            _busRevenueTodayCents = revInt;
          });
        }
	      }
	    } catch (_) {}
	  }

  @override
  void dispose() {
    _linksSub?.cancel();
    _flushTimer?.cancel();
    _contactsIndexHintTimer?.cancel();
    _contactsScrollCtrl.removeListener(_updateContactsStickyHeader);
    _contactsScrollCtrl.dispose();
    try {
      _callSub?.cancel();
    } catch (_) {}
    try {
      _callClient?.close();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadWalletSummary() async {
    if (_walletId.isEmpty) return;
    setState(() => _walletLoading = true);
    try {
      // Konsistente Nutzung des Wallet-Snapshots wie in den
      // Payments-Ansichten, um Serverlogik zentral zu halten.
      final uri = Uri.parse('$_baseUrl/wallets/' +
              Uri.encodeComponent(_walletId) +
              '/snapshot')
          .replace(queryParameters: const {'limit': '1'});
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        Perf.action('wallet_snapshot_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final w = j['wallet'];
        if (w is Map<String, dynamic>) {
          final cents = (w['balance_cents'] ?? 0) as int;
          final cur = (w['currency'] ?? 'SYP').toString();
          if (mounted) {
            setState(() {
              _walletBalanceCents = cents;
              _walletCurrency = cur;
            });
          }
        }
      } else {
        Perf.action('wallet_snapshot_fail');
      }
    } catch (_) {
      Perf.action('wallet_snapshot_error');
    }
    if (mounted) {
      setState(() => _walletLoading = false);
    }
  }

  Future<void> _loadBusSummary() async {
    try {
      final uri = Uri.parse('$_baseUrl/bus/admin/summary');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final trips = j['trips_today'] ?? 0;
        final bookings = j['bookings_today'] ?? 0;
        final revenueC = j['revenue_cents_today'] ?? 0;
        final revInt =
            revenueC is int ? revenueC : int.tryParse(revenueC.toString()) ?? 0;
        if (mounted) {
          setState(() {
            _busTripsToday =
                trips is int ? trips : int.tryParse(trips.toString()) ?? 0;
            _busBookingsToday = bookings is int
                ? bookings
                : int.tryParse(bookings.toString()) ?? 0;
            _busRevenueTodayCents = revInt;
          });
        }
      }
    } catch (_) {}
  }

  Widget _buildHomeRoute() {
	    final actions = HomeActions(
	      onScanPay: _quickScanPay,
	      onTopup: _quickTopup,
	      onSonic: () => _navPush(SonicPayPage(_baseUrl)),
	      onP2P: _quickP2P,
	      onMobility: () => _navPush(JourneyPage(_baseUrl)),
	      onOps: () => _navPush(OpsPage(_baseUrl)),
      onBills: () => _navPush(BillsPage(_baseUrl, _walletId, deviceId)),
      onWallet: () =>
          _navPush(HistoryPage(baseUrl: _baseUrl, walletId: _walletId)),
      onHistory: () =>
          _navPush(HistoryPage(baseUrl: _baseUrl, walletId: _walletId)),
      onBus: () => _openMod('bus'),
      onChat: () => _openMod('chat'),
      // Inventory view
      onVouchers: () => _navPush(CashMandatePage(_baseUrl)),
      onRequests: () =>
          _navPush(RequestsPage(baseUrl: _baseUrl, walletId: _walletId)),
    );
	    final child = HomeRouteGrid(
	      actions: actions,
	      showOps: _showOps,
	      showSuperadmin: _showSuperadmin,
	    );
	    return AnimatedSwitcher(duration: Tokens.motionBase, child: child);
	  }

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linksSub;
  Future<void> _setupLinks() async {
    try {
      _appLinks = AppLinks();
      final uri = await _appLinks!.getInitialLink();
      if (uri != null) {
        unawaited(_handleUri(uri));
      }
      _linksSub = _appLinks!.uriLinkStream.listen((uri) {
        if (uri != null) {
          unawaited(_handleUri(uri));
        }
      });
    } catch (_) {}
  }

  Future<void> _handleUri(Uri uri) async {
    try {
      final scheme = uri.scheme.toLowerCase();
      final host = uri.host.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        await launchWithSession(uri);
        return;
      }
      if (scheme == 'shamell') {
        if (host == 'friend') {
          final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          final core = segs.isNotEmpty ? Uri.decodeComponent(segs.last) : '';
          final phone = (uri.queryParameters['phone'] ?? '').trim();
          final target = (phone.isNotEmpty ? phone : core).trim();
          if (target.isEmpty) return;
          final meId = _profileShamellId.trim();
          final mePhone = _profilePhone.trim();
          if (target == meId || target == mePhone) {
            final l = L10n.of(context);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    l.isArabic ? 'هذا هو رمزك.' : 'That is your own QR code.'),
              ));
            }
            return;
          }

          Map<String, dynamic>? found;
          String foundChatId = '';
          String norm(String s) => s.trim().toLowerCase();
          final needle = norm(target);
          String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
          final needleDigits = digitsOnly(target);
          for (final f in _contactsRoster) {
            final candidates = <String>[
              (f['device_id'] ?? '').toString(),
              (f['shamell_id'] ?? '').toString(),
              (f['id'] ?? '').toString(),
              (f['phone'] ?? '').toString(),
            ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            bool match = candidates.any((c) => norm(c) == needle);
            if (!match && needleDigits.isNotEmpty) {
              match = candidates.any((c) => digitsOnly(c) == needleDigits);
            }
            if (!match) continue;
            found = f;
            foundChatId = () {
              final deviceId = (f['device_id'] ?? '').toString().trim();
              if (deviceId.isNotEmpty) return deviceId;
              final shamellId = (f['shamell_id'] ?? '').toString().trim();
              if (shamellId.isNotEmpty) return shamellId;
              final id = (f['id'] ?? '').toString().trim();
              if (id.isNotEmpty) return id;
              final phone = (f['phone'] ?? '').toString().trim();
              if (phone.isNotEmpty) return phone;
              return '';
            }();
            break;
          }

          if (found != null && foundChatId.isNotEmpty) {
            final alias = (_contactsAliases[foundChatId] ?? '').trim();
            final tags = (_contactsTags[foundChatId] ?? '').trim();
            final display =
                (found['name'] ?? found['id'] ?? '').toString().trim();
            final isClose = ((found['close'] as bool?) ?? false) == true;
            _navPush(
              WeChatContactInfoPage(
                baseUrl: _baseUrl,
                friend: found,
                peerId: foundChatId,
                displayName: display.isNotEmpty ? display : foundChatId,
                alias: alias,
                tags: tags,
                isCloseFriend: isClose,
                pushPage: _navPush,
              ),
              onReturn: () {
                unawaited(_loadFriendsSummary());
                unawaited(_loadContactsRosterMeta());
                unawaited(_loadContactsRoster(force: true));
              },
            );
            return;
          }

          _navPush(
            FriendsPage(
              _baseUrl,
              mode: FriendsPageMode.newFriends,
              initialAddText: target,
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
            _navPush(
              GroupChatPage(
                baseUrl: _baseUrl,
                groupId: groupId,
                groupName: groupName,
                initialMessageId: mid.isNotEmpty ? mid : null,
              ),
            );
            return;
          }

          String peerId = (uri.queryParameters['peer_id'] ?? '').trim();
          final senderHint = (uri.queryParameters['sender_hint'] ?? '').trim();
          if (peerId.isEmpty) {
            final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
            if (segs.isNotEmpty) peerId = segs.last.trim();
          }
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
          if (peerId.isEmpty) return;
          _navPush(
            ThreemaChatPage(
              baseUrl: _baseUrl,
              initialPeerId: peerId,
              initialMessageId: mid.isNotEmpty ? mid : null,
            ),
          );
          return;
        }
        if (host == 'miniapp' ||
            host == 'miniapps' ||
            host == 'mini_program' ||
            host == 'mini_programs') {
          final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          final id = (uri.queryParameters['id'] ??
                  (segs.isNotEmpty ? segs.last : null) ??
                  uri.queryParameters['miniapp'] ??
                  uri.queryParameters['app_id'])
              ?.trim()
              .toLowerCase();
          if (id != null && id.isNotEmpty) {
            _openMod(id);
            return;
          }
        }
        if (host == 'stickers') {
          final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          String? packId;
          if (segs.isNotEmpty) {
            if (segs.length >= 2 && segs.first.toLowerCase() == 'pack') {
              packId = segs[1];
            } else {
              packId = segs.last;
            }
          } else {
            packId = uri.queryParameters['pack_id'];
          }
          if (packId != null && packId.isNotEmpty) {
            _openStickerPackDeepLink(packId);
            return;
          }
          // Fallback: open generic sticker store.
          _navPush(StickerStorePage(baseUrl: _baseUrl));
          return;
        }
        if (host == 'official') {
          final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segs.isEmpty) return;
          final accountId = segs.first;
          if (accountId.isEmpty) return;
          if (segs.length > 1) {
            final itemId = segs[1];
            if (itemId.isNotEmpty) {
              _openOfficialItemDeepLink(accountId, itemId);
              return;
            }
          }
          _openOfficialDeepLink(accountId);
          return;
        }
        if (host == 'moments') {
          final postId = uri.queryParameters['post_id'];
          final focus = (uri.queryParameters['focus'] ?? '').toLowerCase();
          final focusComments =
              focus == 'comments' || focus == 'thread' || focus == 'true';
          final commentId = uri.queryParameters['comment_id'];
          _openMomentsDeepLink(
            postId,
            focusComments: focusComments,
            commentId: commentId,
          );
          return;
        }
      }
      String? mod = uri.queryParameters['mod'];
      if (mod == null) {
        final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) mod = segs.last;
      }
      // offline sync removed; ignore syncnow
      if (mod == null) return;
      _openMod(mod.toLowerCase());
    } catch (_) {}
  }

  void _openOfficialDeepLink(String accountId) {
    if (accountId.isEmpty) return;
    _navPush(
      OfficialAccountDeepLinkPage(
        baseUrl: _baseUrl,
        accountId: accountId,
        onOpenChat: (peerId) {
          if (peerId.isEmpty) return;
          _navPush(
            ThreemaChatPage(
              baseUrl: _baseUrl,
              initialPeerId: peerId,
            ),
          );
        },
      ),
    );
  }

  void _openMomentsDeepLink(
    String? postId, {
    bool focusComments = false,
    String? commentId,
  }) {
    _navPush(
      MomentsPage(
        baseUrl: _baseUrl,
        initialPostId: postId,
        focusComments: focusComments,
        initialCommentId: commentId,
        onOpenOfficialDirectory: (ctx) {
          _navPush(
            OfficialAccountsPage(
              baseUrl: _baseUrl,
              initialCityFilter: _officialStripCityLabel,
              onOpenChat: (peerId) {
                if (peerId.isEmpty) return;
                _navPush(
                  ThreemaChatPage(
                    baseUrl: _baseUrl,
                    initialPeerId: peerId,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openStickerPackDeepLink(String packId) {
    if (packId.isEmpty) {
      _navPush(StickerStorePage(baseUrl: _baseUrl));
      return;
    }
    _navPush(
      StickerStorePage(
        baseUrl: _baseUrl,
        initialPackId: packId,
      ),
    );
  }

  void _openOfficialItemDeepLink(String accountId, String itemId) {
    if (accountId.isEmpty || itemId.isEmpty) return;
    _navPush(
      OfficialFeedItemDeepLinkPage(
        baseUrl: _baseUrl,
        accountId: accountId,
        itemId: itemId,
        onOpenChat: (peerId) {
          if (peerId.isEmpty) return;
          _navPush(
            ThreemaChatPage(
              baseUrl: _baseUrl,
              initialPeerId: peerId,
            ),
          );
        },
      ),
    );
  }

  void _showEmergency() {
    showDialog(
        context: context,
        builder: (_) {
          final l = L10n.of(context);
          return AlertDialog(
            title: Text(l.emergencyTitle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.local_police_outlined),
                  title: Text(l.emergencyPolice),
                  subtitle: const Text('112'),
                  onTap: () {
                    launchUrl(Uri.parse('tel:112'));
                    Navigator.pop(context);
                  }),
              ListTile(
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: Text(l.emergencyAmbulance),
                  subtitle: const Text('110'),
                  onTap: () {
                    launchUrl(Uri.parse('tel:110'));
                    Navigator.pop(context);
                  }),
              ListTile(
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: Text(l.emergencyFire),
                  subtitle: const Text('113'),
                  onTap: () {
                    launchUrl(Uri.parse('tel:113'));
                    Navigator.pop(context);
                  }),
            ]),
          );
        });
  }

  void _showComplaints() {
    showDialog(
        context: context,
        builder: (_) {
          final l = L10n.of(context);
          return AlertDialog(
            title: Text(l.complaintsTitle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Email: radisaiyed@icloud.com'),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () {
                    launchUrl(Uri.parse(
                        'mailto:radisaiyed@icloud.com?subject=Complaint'));
                    Navigator.pop(context);
                  },
                  child: Text(l.complaintsEmailUs)),
            ]),
          );
        });
  }

  void _callUs() {
    try {
      launchUrl(Uri.parse('tel:+963996428955'));
    } catch (_) {}
  }
  // NOTE: support call number aligned with current superadmin phone.

  Future<void> _loadRoles() async {
    try {
      final r = await http.get(Uri.parse('$_baseUrl/me/roles'),
          headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final phone = (j['phone'] ?? '').toString();
        final roles =
            (j['roles'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        final sp = await SharedPreferences.getInstance();
        await sp.setStringList('roles', roles);
        if (phone.isNotEmpty) {
          await sp.setString('phone', phone);
        }
        final storedIsSuper = sp.getBool('is_superadmin') ?? false;
        if (mounted) {
          final baseShowOps = _computeShowOps(roles, _appMode);
          final showSuper = storedIsSuper || phone == kSuperadminPhone;
          final showOps = baseShowOps || showSuper;
          setState(() {
            _roles = roles;
            _showOps = showOps;
            _showSuperadmin = showSuper;
          });
        }
      }
    } catch (_) {}
  }

  void _openMod(String mod) {
    final id = mod.trim().toLowerCase();
    if (id.isEmpty) return;

    // Native modules: keep Payments + Chat fully integrated.
    if (id == 'chat') {
      if (mounted) {
        setState(() {
          _tabIndex = 0;
        });
      }
      return;
    }
    if (id == 'payments' || id == 'pay' || id == 'wallet') {
      _quickP2P();
      return;
    }
    final api = SuperappAPI(
      baseUrl: _baseUrl,
      walletId: _walletId,
      deviceId: deviceId,
      openMod: _openMod,
      pushPage: _navPush,
      ensureServiceOfficialFollow: _ensureServiceOfficialFollow,
      recordModuleUse: _recordModuleUse,
    );

    final miniApp = MiniAppRegistry.byId(id);
    if (miniApp != null) {
      _navPush(miniApp.entry(context, api));
      return;
    }

    unawaited(_recordModuleUse(id));
    _navPush(
      MiniProgramPage(
        id: id,
        baseUrl: _baseUrl,
        walletId: _walletId,
        deviceId: deviceId,
        onOpenMod: _openMod,
      ),
    );
  }

  void _quickScanPay() {
    unawaited(_recordModuleUse('payments'));
    unawaited(_ensureServiceOfficialFollow(
        officialId: 'shamell_pay', chatPeerId: 'shamell_pay'));
    _navPush(
        PaymentsPage(_baseUrl, _walletId, deviceId, triggerScanOnOpen: true));
  }

  void _quickTopup() {
    unawaited(_recordModuleUse('topup'));
    _navPush(TopupPage(_baseUrl, triggerScanOnOpen: true));
  }

  void _quickP2P() {
    unawaited(_recordModuleUse('payments'));
    unawaited(_ensureServiceOfficialFollow(
        officialId: 'shamell_pay', chatPeerId: 'shamell_pay'));
    _navPush(PaymentsPage(_baseUrl, _walletId, deviceId));
  }

  Map<String, String> _parsePipePairs(String raw) {
    final parts = raw.split('|');
    final map = <String, String>{};
    for (final p in parts.skip(1)) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      final k = p.substring(0, idx).trim().toLowerCase();
      final v = Uri.decodeComponent(p.substring(idx + 1).trim());
      if (k.isEmpty || v.isEmpty) continue;
      map[k] = v;
    }
    return map;
  }

  Future<void> _openWeChatScanAndHandle() async {
    try {
      final res = await Navigator.of(context).push<String?>(
        MaterialPageRoute(builder: (_) => const ScanPage()),
      );
      if (!mounted) return;
      _loadUnreadBadge();
      _loadMomentsNotifications();
      unawaited(_loadWeChatPluginsPrefs());
      final raw = (res ?? '').trim();
      if (raw.isEmpty) return;
      await _handleScanResult(raw);
    } catch (_) {}
  }

  Future<void> _showScanResultSheet(String raw) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.isArabic ? 'نتيجة المسح' : 'Scan result',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: .35,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: SelectableText(
                    raw,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    try {
                      await Clipboard.setData(ClipboardData(text: raw));
                    } catch (_) {}
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(l.isArabic ? 'تم النسخ' : 'Copied'),
                    ));
                  },
                  child: Text(l.isArabic ? 'نسخ' : 'Copy'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l.isArabic ? 'إغلاق' : 'Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleScanResult(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    final upper = text.toUpperCase();
    if (upper.startsWith('PAY|') || upper.startsWith('CASH|')) {
      final kv = _parsePipePairs(text);
      final alias = (kv['to_alias'] ?? kv['alias'] ?? '').trim();
      final phone = (kv['to_phone'] ?? kv['phone'] ?? '').trim();
      final wallet =
          (kv['to_wallet_id'] ?? kv['wallet'] ?? kv['to'] ?? '').trim();
      final recipient =
          (alias.isNotEmpty ? alias : (phone.isNotEmpty ? phone : wallet))
              .trim();
      final amountRaw = (kv['amount'] ?? '').trim();
      final amountCents = parseCents(amountRaw);
      final label = (kv['label'] ?? kv['merchant'] ?? kv['name'] ?? '').trim();

      String fromWallet = _walletId.trim();
      if (fromWallet.isEmpty) {
        try {
          final sp = await SharedPreferences.getInstance();
          fromWallet = (sp.getString('wallet_id') ?? '').trim();
        } catch (_) {}
      }

      unawaited(_recordModuleUse('payments'));
      unawaited(_ensureServiceOfficialFollow(
          officialId: 'shamell_pay', chatPeerId: 'shamell_pay'));
      _navPush(
        PaymentsPage(
          _baseUrl,
          fromWallet,
          deviceId,
          initialRecipient: recipient.isNotEmpty ? recipient : null,
          initialAmountCents: amountCents > 0 ? amountCents : null,
          initialSection: 'send',
          contextLabel: label.isNotEmpty ? label : null,
        ),
      );
      return;
    }

    if (upper.startsWith('APP|') ||
        upper.startsWith('MINIAPP|') ||
        upper.startsWith('MINIPROGRAM|') ||
        upper.startsWith('MINI_PROGRAM|')) {
      final kv = _parsePipePairs(text);
      final id = (kv['id'] ??
              kv['miniapp'] ??
              kv['mini_app'] ??
              kv['app'] ??
              kv['app_id'])
          ?.trim()
          .toLowerCase();
      if (id != null && id.isNotEmpty) {
        _openMod(id);
        return;
      }
    }

    final uri = Uri.tryParse(text);
    if (uri != null && uri.scheme.isNotEmpty) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        await launchWithSession(uri);
        return;
      }
      if (scheme == 'shamell') {
        await _handleUri(uri);
        return;
      }
    }

    await _showScanResultSheet(text);
  }

  Future<void> _scanMiniAppQr() => _openWeChatScanAndHandle();

  Future<void> _recordModuleUse(String moduleId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final existing = sp.getStringList('recent_modules') ?? const <String>[];
      final updated = <String>[
        moduleId,
        ...existing.where((m) => m != moduleId)
      ];
      if (updated.length > 8) {
        updated.removeRange(8, updated.length);
      }
      await sp.setStringList('recent_modules', updated);
      if (mounted) {
        setState(() {
          _recentModules = updated;
        });
      }
    } catch (_) {}
    // Best-effort server-side analytics for Mini-Apps (Mini-Programs).
    try {
      final uri = Uri.parse(
          '$_baseUrl/mini_apps/${Uri.encodeComponent(moduleId)}/track_open');
      unawaited(http.post(uri));
    } catch (_) {}
  }

  Future<void> _refreshMiniProgramsLocalPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final pinned = sp.getStringList('pinned_miniapps') ?? const <String>[];
      final pinnedOrder =
          sp.getStringList('mini_programs.pinned_order') ?? const <String>[];
      final recents =
          sp.getStringList('recent_mini_programs') ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _pinnedMiniApps = pinned;
        _pinnedMiniProgramsOrder = pinnedOrder;
        _recentMiniPrograms = recents;
      });
    } catch (_) {}
    unawaited(_refreshMiniProgramUpdateBadges());
  }

  Map<String, String> _decodeStringMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = <String, String>{};
        decoded.forEach((k, v) {
          final key = (k ?? '').toString().trim();
          final val = (v ?? '').toString().trim();
          if (key.isNotEmpty && val.isNotEmpty) map[key] = val;
        });
        return map;
      }
    } catch (_) {}
    return const <String, String>{};
  }

  Future<void> _refreshMiniProgramUpdateBadges() async {
    try {
      final interested = <String>{};
      for (final raw in [
        ..._pinnedMiniApps,
        ..._pinnedMiniProgramsOrder,
        ..._recentMiniPrograms,
      ]) {
        final id = raw.trim();
        if (id.isNotEmpty) interested.add(id);
      }
      if (interested.isEmpty) {
        if (!mounted) return;
        if (_miniProgramsUpdateBadgeIds.isNotEmpty) {
          setState(() => _miniProgramsUpdateBadgeIds = <String>{});
        }
        return;
      }

      final sp = await SharedPreferences.getInstance();
      final latest = _decodeStringMap(
        sp.getString('mini_programs.latest_released_versions.v1') ?? '{}',
      );
      final seen = _decodeStringMap(
        sp.getString('mini_programs.seen_release_versions.v1') ?? '{}',
      );

      final nextSeen = Map<String, String>.from(seen);
      var seenChanged = false;
      final badges = <String>{};

      for (final id in interested) {
        final rel = (latest[id] ?? '').trim();
        if (rel.isEmpty) continue;
        final prev = (nextSeen[id] ?? '').trim();
        if (prev.isEmpty) {
          // Treat the current release as "seen" so we only badge when a newer
          // release appears later (WeChat-style red dot behaviour).
          nextSeen[id] = rel;
          seenChanged = true;
          continue;
        }
        if (prev != rel) badges.add(id);
      }

      if (seenChanged) {
        try {
          await sp.setString(
            'mini_programs.seen_release_versions.v1',
            jsonEncode(nextSeen),
          );
        } catch (_) {}
      }

      if (!mounted) return;
      if (_miniProgramsUpdateBadgeIds.length == badges.length &&
          _miniProgramsUpdateBadgeIds.every(badges.contains)) {
        return;
      }
      setState(() => _miniProgramsUpdateBadgeIds = badges);
    } catch (_) {}
  }

  void _markTrendingMiniProgramsSeen() {
    if (mounted && _hasNewTrendingMiniPrograms) {
      setState(() {
        _hasNewTrendingMiniPrograms = false;
      });
    }
    final sig = _trendingMiniProgramsSig;
    if (sig.isEmpty) return;
    unawaited(() async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('mini_programs.trending_seen_sig', sig);
      } catch (_) {}
    }());
  }

  void _openMiniProgramsDiscover() {
    _markTrendingMiniProgramsSeen();
    _navPush(
      MiniProgramsDiscoverPage(
        baseUrl: _baseUrl,
        walletId: _walletId,
        deviceId: deviceId,
        onOpenMod: _openMod,
      ),
      onReturn: () {
        unawaited(_refreshMiniProgramsLocalPrefs());
        unawaited(_loadTrendingMiniPrograms());
      },
    );
  }

  Widget _buildDiscoverPromoChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool showUnreadDot = false,
    IconData? badgeIcon,
    String? badgeLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 18),
            if (showUnreadDot)
              Positioned(
                right: -4,
                top: -4,
                child: Icon(
                  Icons.brightness_1,
                  size: 8,
                  color: Colors.redAccent,
                ),
              ),
            if (!showUnreadDot && badgeIcon != null)
              Positioned(
                right: -4,
                top: -4,
                child: Icon(
                  badgeIcon,
                  size: 10,
                  color: Colors.redAccent,
                ),
              ),
          ],
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (badgeLabel != null && badgeLabel.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ],
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget? _buildDiscoverChip(String id, L10n l) {
    final meta = miniAppById(id);
    // Primary path: built‑in Shamell mini‑app.
    if (meta != null) {
      final label = meta.title(isArabic: l.isArabic);
      final icon = meta.icon;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          onPressed: () => _openMod(id),
        ),
      );
    }
    // Fallback: treat as pinned Mini‑Program runtime app_id so it still
    // appears in the Discover row WeChat‑style.
    final isArabic = l.isArabic;
    final label = isArabic ? 'برنامج مصغّر $id' : 'Mini‑program $id';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: const Icon(Icons.widgets_outlined, size: 18),
        label: Text(label),
        onPressed: () {
          if (id.isEmpty) return;
          _navPush(
            MiniProgramPage(
              id: id,
              baseUrl: _baseUrl,
              walletId: _walletId,
              deviceId: deviceId,
              onOpenMod: _openMod,
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadWeChatPluginsPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final showMoments = sp.getBool(_kWeChatPluginShowMoments) ?? true;
      final showChannels = sp.getBool(_kWeChatPluginShowChannels) ?? true;
      final showScan = sp.getBool(_kWeChatPluginShowScan) ?? true;
      final showPeopleNearby =
          sp.getBool(_kWeChatPluginShowPeopleNearby) ?? true;
      final showMiniPrograms =
          sp.getBool(_kWeChatPluginShowMiniPrograms) ?? true;
      final showCardsOffers = sp.getBool(_kWeChatPluginShowCardsOffers) ?? true;
      final showStickers = sp.getBool(_kWeChatPluginShowStickers) ?? true;
      if (!mounted) return;
      setState(() {
        _pluginShowMoments = showMoments;
        _pluginShowChannels = showChannels;
        _pluginShowScan = showScan;
        _pluginShowPeopleNearby = showPeopleNearby;
        _pluginShowMiniPrograms = showMiniPrograms;
        _pluginShowCardsOffers = showCardsOffers;
        _pluginShowStickers = showStickers;
      });
    } catch (_) {}
  }

  void _navPush(Widget page, {VoidCallback? onReturn}) {
    Navigator.of(context)
        .push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
            child: page),
      ),
    ))
        .then((_) {
      _loadUnreadBadge();
      _loadMomentsNotifications();
      unawaited(_loadWeChatPluginsPrefs());
      onReturn?.call();
    });
  }

  Future<void> _logout() async {
    try {
      final cookie = await _getCookie();
      await _clearCookie();
      final uri = Uri.parse('$_baseUrl/auth/logout');
      await http.post(uri, headers: {'Cookie': cookie ?? ''});
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // removed duplicate dispose; handled earlier for timers

  Future<void> _changeAppMode(AppMode mode) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        'app_mode',
        switch (mode) {
          AppMode.user => 'user',
          AppMode.operator => 'operator',
          AppMode.admin => 'admin',
          AppMode.auto => 'auto',
        });
    if (!mounted) return;
    setState(() {
      _appMode = mode;
      _showOps = _computeShowOps(_roles, _appMode);
    });
  }

  void _showModeSheet() {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final modes = <AppMode>[
            AppMode.user,
            AppMode.operator,
            AppMode.admin
          ];
          return GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                  color: Colors.black54,
                  child: GestureDetector(
                      onTap: () {},
                      child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                              decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surface
                                      .withValues(alpha: .98),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(16))),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 16),
                              child: SafeArea(
                                  top: false,
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                            height: 4,
                                            width: 44,
                                            margin: const EdgeInsets.only(
                                                bottom: 8),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                                color: Colors.white24,
                                                borderRadius:
                                                    BorderRadius.circular(4))),
                                        const Text('App mode',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        ...modes.map((m) {
                                          final selectedMode =
                                              _appMode == AppMode.auto
                                                  ? AppMode.user
                                                  : _appMode;
                                          final isSelected = selectedMode == m;
                                          return ListTile(
                                            leading: Icon(
                                              appModeIcon(m),
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                            title: Text(appModeLabel(m)),
                                            trailing: isSelected
                                                ? const Icon(Icons.check_circle)
                                                : const SizedBox.shrink(),
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              _changeAppMode(m);
                                            },
                                          );
                                        }),
                                      ])))))));
        });
  }
}
