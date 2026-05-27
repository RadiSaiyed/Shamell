import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'mini_apps_config.dart';
import 'mini_program_shelf_prefs.dart';
import 'mini_program_runtime.dart';
import 'session_cookie_store.dart';
import 'shamell_empty_state.dart';

class MiniProgramsDirectoryPage extends StatefulWidget {
  final String baseUrl;
  // `walletId` and `onOpenMod` are now nullable so the page can be
  // opened from the Discover "Gaming" tile (which has no walletId
  // context and doesn't need the parent's openMod router because the
  // bundled mini-games it lists open directly via their own runtime).
  // Legacy callers that supply both continue to work unchanged.
  final String walletId;
  final String deviceId;
  final void Function(String modId)? onOpenMod;

  /// Optional category to pre-filter on (e.g. `'Gaming'`). Matched
  /// against `MiniAppDescriptor.categoryEn` server-side and the
  /// localised display name in the chips. Pass `null` (or omit) for
  /// the unfiltered all-categories view.
  final String? initialCategoryFilter;

  const MiniProgramsDirectoryPage({
    super.key,
    required this.baseUrl,
    this.walletId = '',
    required this.deviceId,
    this.onOpenMod,
    this.initialCategoryFilter,
  });

  @override
  State<MiniProgramsDirectoryPage> createState() =>
      _MiniProgramsDirectoryPageState();
}

class _MiniProgramsDirectoryPageState extends State<MiniProgramsDirectoryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _programs = const <Map<String, dynamic>>[];
  String _query = '';
  String _statusFilter = 'all'; // all, active, draft
  Set<String> _pinned = <String>{};
  String? _myOwnerContact;
  bool _myOnly = false;
  String? _categoryFilter;
  bool _trendingOnly = false;
  Map<String, Map<String, dynamic>> _shelfMeta =
      const <String, Map<String, dynamic>>{};
  bool _shelfSyncing = false;

  static const Duration _networkTimeout = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    // Seed the category filter when launched from a category-specific
    // entry point (e.g. the Discover "Gaming" tile pre-filters to the
    // Gaming category so the user lands directly in the games list).
    final preset = widget.initialCategoryFilter?.trim();
    if (preset != null && preset.isNotEmpty) {
      _categoryFilter = preset;
    }
    _load();
    _loadPinned();
    _syncShelfFromServer();
    _loadMyOwnerContact();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPinned() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ids = loadMiniProgramPinnedIdsSync(sp);
      if (!mounted) return;
      setState(() {
        _pinned = ids.toSet();
      });
    } catch (_) {}
  }

  List<String> _cleanIds(Iterable<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final id = item.trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  String _shelfItemId(Map<String, dynamic> item) {
    return (item['app_id'] ?? item['id'] ?? '').toString().trim();
  }

  Map<String, dynamic>? _shelfMetaFor(String appId) {
    final id = appId.trim();
    if (id.isEmpty) return null;
    return _shelfMeta[id] ?? _shelfMeta[id.toLowerCase()];
  }

  int _shelfOpenCount(String appId) {
    final raw = _shelfMetaFor(appId)?['open_count'];
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString()) ?? 0;
  }

  String _shelfSeenVersion(String appId) {
    return (_shelfMetaFor(appId)?['seen_version'] ?? '').toString().trim();
  }

  Future<Map<String, String>> _authHeaders({bool json = false}) {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: json);
  }

  Future<void> _syncShelfFromServer() async {
    if (_shelfSyncing) return;
    _shelfSyncing = true;
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/me/mini_programs/shelf?limit=100');
      final resp = await http
          .get(uri, headers: await _authHeaders())
          .timeout(_networkTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final decoded = jsonDecode(resp.body);
      final raw = decoded is Map
          ? (decoded['items'] is List
              ? decoded['items'] as List
              : decoded['programs'] is List
                  ? decoded['programs'] as List
                  : const <dynamic>[])
          : decoded is List
              ? decoded
              : const <dynamic>[];
      final serverPinned = <String>[];
      final serverRecent = <String>[];
      final shelfMeta = <String, Map<String, dynamic>>{};
      for (final item in raw) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();
        final id = _shelfItemId(m);
        if (id.isEmpty) continue;
        shelfMeta[id] = m;
        if (m['pinned'] == true) serverPinned.add(id);
        final lastOpened = (m['last_opened_at'] ?? '').toString().trim();
        final openCount = m['open_count'];
        if (lastOpened.isNotEmpty || (openCount is num && openCount > 0)) {
          serverRecent.add(id);
        }
      }

      final sp = await SharedPreferences.getInstance();
      final localPinned = loadMiniProgramPinnedIdsSync(sp);
      final localRecent = loadMiniProgramRecentIdsSync(sp);
      final nextPinned = _cleanIds(<String>[...serverPinned, ...localPinned]);
      final nextRecent = _cleanIds(<String>[...serverRecent, ...localRecent])
          .take(10)
          .toList();
      await saveMiniProgramShelfPrefs(
        sp,
        pinnedIds: nextPinned,
        pinnedOrder: nextPinned,
        recentIds: nextRecent,
      );

      final serverPinnedSet = serverPinned.toSet();
      for (final id in localPinned) {
        if (!serverPinnedSet.contains(id)) {
          // ignore: discarded_futures
          _syncPinnedStateToServer(id, true);
        }
      }
      // ignore: discarded_futures
      _syncPinnedOrderToServer(nextPinned);

      if (!mounted) return;
      setState(() {
        _pinned = nextPinned.toSet();
        _shelfMeta = shelfMeta;
      });
    } catch (_) {
    } finally {
      _shelfSyncing = false;
    }
  }

  Future<void> _loadMyOwnerContact() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final phone = sp.getString('phone') ?? '';
      if (!mounted) return;
      setState(() {
        _myOwnerContact = phone.trim().isEmpty ? null : phone.trim();
      });
    } catch (_) {}
  }

  Future<void> _togglePinned(String appId) async {
    if (appId.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final pinnedList = loadMiniProgramPinnedIdsSync(sp);
      final pinnedSet = pinnedList.toSet();
      final isPinned = pinnedSet.contains(appId);
      pinnedList.removeWhere((e) => e == appId);
      if (!isPinned) {
        pinnedList.insert(0, appId);
      }
      await saveMiniProgramPinnedIds(sp, pinnedList);

      final orderList = loadMiniProgramPinnedOrderSync(sp);
      orderList.removeWhere((e) => e == appId);
      if (!isPinned) {
        orderList.insert(0, appId);
      }
      final nextOrder = miniProgramPinnedOrderFromLists(
        pinnedIds: pinnedList,
        orderedIds: orderList,
      );
      await saveMiniProgramPinnedOrder(
        sp,
        nextOrder,
        pinnedIds: pinnedList,
      );
      if (!mounted) return;
      setState(() {
        _pinned = pinnedList.toSet();
      });
      // ignore: discarded_futures
      _syncPinnedStateToServer(appId, !isPinned);
      // ignore: discarded_futures
      _syncPinnedOrderToServer(pinnedList);
    } catch (_) {}
  }

  Future<void> _syncPinnedStateToServer(String appId, bool pinned) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/me/mini_programs/shelf/${Uri.encodeComponent(id)}',
      );
      await http
          .patch(
            uri,
            headers: await _authHeaders(json: true),
            body: jsonEncode({'pinned': pinned}),
          )
          .timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<void> _syncPinnedOrderToServer(List<String> orderedIds) async {
    final ids = _cleanIds(orderedIds);
    if (ids.isEmpty) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/mini_programs/shelf/order');
      await http
          .post(
            uri,
            headers: await _authHeaders(json: true),
            body: jsonEncode({'app_ids': ids}),
          )
          .timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<void> _trackOpen(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final current = loadMiniProgramRecentIdsSync(sp);
      final next = _cleanIds(<String>[id, ...current]).take(10).toList();
      await saveMiniProgramRecentIds(sp, next);
    } catch (_) {}
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(id)}/track_open',
      );
      await http
          .post(uri, headers: await _authHeaders())
          .timeout(_networkTimeout);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _localMiniPrograms() {
    final out = <Map<String, dynamic>>[];
    // When the directory is opened with the Gaming filter (via the
    // Discover "Gaming" tile or a deep link), surface the games. In all
    // other views games stay hidden — they have their own discovery
    // surface and shouldn't appear in the generic services list.
    final includeGaming = _categoryFilter == 'Gaming';
    for (final m in visibleMiniApps(includeGaming: includeGaming)) {
      final id = m.id.trim();
      if (id.isEmpty) continue;
      final scopes = <String>[];
      final idLower = id.toLowerCase();
      if (idLower.contains('pay') ||
          idLower.contains('wallet') ||
          idLower.contains('payment')) {
        scopes.add('payments');
      }
      out.add(<String, dynamic>{
        'app_id': id,
        'title_en': m.titleEn,
        'title_ar': m.titleAr,
        'description_en': m.categoryEn,
        'description_ar': m.categoryAr,
        'status': 'active',
        'review_status': 'approved',
        'enabled': m.enabled,
        'manifest_authority': 'local_fallback',
        '__registry_source': 'local',
        'usage_score': m.usageScore,
        'rating': m.rating,
        'rating_count': m.ratingCount,
        'moments_shares_30d': m.momentsShares,
        'moments_shares_total': m.momentsShares,
        'owner_name': '',
        'owner_contact': '',
        'released_version': '',
        'scopes': scopes,
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _mergeWithLocal(
    List<Map<String, dynamic>> remote,
  ) {
    final merged = <Map<String, dynamic>>[
      for (final p in remote) Map<String, dynamic>.from(p),
    ];
    final existing = <String>{};
    for (final p in merged) {
      final id = (p['app_id'] ?? '').toString().trim().toLowerCase();
      if (id.isNotEmpty) existing.add(id);
    }
    for (final p in _localMiniPrograms()) {
      final id = (p['app_id'] ?? '').toString().trim().toLowerCase();
      if (id.isEmpty || existing.contains(id)) continue;
      merged.add(p);
    }
    return merged;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _programs = _localMiniPrograms();
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs');
      final resp = await http
          .get(uri, headers: await _authHeaders())
          .timeout(_networkTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        setState(() {
          _error = resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}';
          _loading = false;
          _programs = _mergeWithLocal(_programs);
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
      final list = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['programs'] is List) {
        for (final e in decoded['programs'] as List) {
          if (e is Map) {
            list.add(e.cast<String, dynamic>());
          }
        }
      } else if (decoded is List) {
        for (final e in decoded) {
          if (e is Map) {
            list.add(e.cast<String, dynamic>());
          }
        }
      }
      setState(() {
        _programs = _mergeWithLocal(list);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _programs = _mergeWithLocal(_programs);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.apps_outlined,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: l.isArabic
                    ? 'بحث في البرامج المصغّرة'
                    : 'Search mini‑programs',
              ),
              onChanged: (v) {
                setState(() {
                  _query = v;
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.isArabic ? 'الكل' : 'All'),
                    selected: _statusFilter == 'all',
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _statusFilter = 'all';
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Text(l.isArabic ? 'نشطة' : 'Active'),
                    selected: _statusFilter == 'active',
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _statusFilter = 'active';
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Text(l.isArabic ? 'مسودات' : 'Drafts'),
                    selected: _statusFilter == 'draft',
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _statusFilter = 'draft';
                      });
                    },
                  ),
                  if (_myOwnerContact != null && _myOwnerContact!.isNotEmpty)
                    ChoiceChip(
                      label: Text(
                        l.isArabic ? 'برامجي فقط' : 'My mini‑programs only',
                      ),
                      selected: _myOnly,
                      onSelected: (sel) {
                        setState(() {
                          _myOnly = sel;
                        });
                      },
                    ),
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_fire_department_outlined,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(l.isArabic ? 'شائعة' : 'Trending'),
                      ],
                    ),
                    selected: _trendingOnly,
                    onSelected: (sel) {
                      setState(() {
                        _trendingOnly = sel;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_programs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildCategoryChips(l),
              ),
            ),
          Expanded(
            child: _buildList(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(L10n l) {
    final isArabic = l.isArabic;
    final cats = <String>{};
    for (final p in _programs) {
      final appId = (p['app_id'] ?? '').toString();
      final titleEn = (p['title_en'] ?? '').toString();
      final titleAr = (p['title_ar'] ?? '').toString();
      final descEn = (p['description_en'] ?? '').toString();
      final descAr = (p['description_ar'] ?? '').toString();
      final haystack = '${titleEn.toLowerCase()} '
              '${titleAr.toLowerCase()} '
              '${descEn.toLowerCase()} '
              '${descAr.toLowerCase()} '
              '${appId.toLowerCase()}'
          .trim();
      if (haystack.isEmpty) continue;
      if (haystack.contains('bus') ||
          haystack.contains('ride') ||
          haystack.contains('transport') ||
          haystack.contains('mobility')) {
        cats.add('transport');
      } else if (haystack.contains('wallet') ||
          haystack.contains('pay') ||
          haystack.contains('payment') ||
          haystack.contains('payments')) {
        cats.add('wallet');
      } else if (haystack.contains('moments') ||
          haystack.contains('social') ||
          haystack.contains('people_nearby') ||
          haystack.contains('nearby') ||
          haystack.contains('sticker')) {
        cats.add('social');
      } else if (haystack.contains('channels') ||
          haystack.contains('media') ||
          haystack.contains('video')) {
        cats.add('media');
      } else if (haystack.contains('official') ||
          haystack.contains('service') ||
          haystack.contains('account') ||
          haystack.contains('verified')) {
        cats.add('services');
      } else if (haystack.contains('favorite') ||
          haystack.contains('bookmark') ||
          haystack.contains('personal') ||
          haystack.contains('saved')) {
        cats.add('tools');
      } else if (haystack.contains('gaming') ||
          haystack.contains('game') ||
          haystack.contains('arcade') ||
          haystack.contains('puzzle')) {
        cats.add('gaming');
      }
    }
    if (cats.isEmpty) {
      return const SizedBox.shrink();
    }
    String labelFor(String key) {
      switch (key) {
        case 'transport':
          return isArabic ? 'التنقل والنقل' : 'Transport';
        case 'wallet':
          return isArabic ? 'المحفظة والمدفوعات' : 'Wallet & payments';
        case 'social':
          return isArabic ? 'اجتماعي' : 'Social';
        case 'media':
          return isArabic ? 'الإعلام' : 'Media';
        case 'services':
          return isArabic ? 'الخدمات' : 'Services';
        case 'tools':
          return isArabic ? 'أدوات شخصية' : 'Personal tools';
        case 'gaming':
          return isArabic ? 'الألعاب' : 'Gaming';
        default:
          return key;
      }
    }

    final keys = cats.toList()..sort();
    return Wrap(
      spacing: 8,
      children: keys.map((key) {
        final selected = _categoryFilter == key;
        return ChoiceChip(
          label: Text(labelFor(key)),
          selected: selected,
          onSelected: (sel) {
            setState(() {
              _categoryFilter = sel ? key : null;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildList(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final term = _query.trim().toLowerCase();
    final filtered = _programs.where((p) {
      final status = (p['status'] ?? '').toString().toLowerCase();
      if (_statusFilter == 'active' && status != 'active') return false;
      if (_statusFilter == 'draft' && status != 'draft') return false;
      final id = (p['app_id'] ?? '').toString().toLowerCase();
      final titleEn = (p['title_en'] ?? '').toString().toLowerCase();
      final titleAr = (p['title_ar'] ?? '').toString().toLowerCase();
      final ownerName = (p['owner_name'] ?? '').toString().toLowerCase();
      final ownerContact = (p['owner_contact'] ?? '').toString().trim();
      if (_myOnly &&
          !((_myOwnerContact ?? '').isNotEmpty &&
              ownerContact.isNotEmpty &&
              _myOwnerContact == ownerContact)) {
        return false;
      }
      final usageScore =
          (p['usage_score'] is num) ? (p['usage_score'] as num).toInt() : 0;
      final ratingVal =
          (p['rating'] is num) ? (p['rating'] as num).toDouble() : 0.0;
      final moments30 = (p['moments_shares_30d'] is num)
          ? (p['moments_shares_30d'] as num).toInt()
          : 0;
      if (_trendingOnly) {
        final isTrending =
            usageScore >= 50 || ratingVal >= 4.5 || moments30 >= 5;
        if (!isTrending) return false;
      }
      if (_categoryFilter != null) {
        final appIdRaw = (p['app_id'] ?? '').toString();
        final descEn = (p['description_en'] ?? '').toString();
        final descAr = (p['description_ar'] ?? '').toString();
        final hay = '${titleEn.toLowerCase()} '
                '${titleAr.toLowerCase()} '
                '${descEn.toLowerCase()} '
                '${descAr.toLowerCase()} '
                '${appIdRaw.toLowerCase()}'
            .trim();
        bool matches = false;
        switch (_categoryFilter) {
          case 'transport':
            matches = hay.contains('bus') ||
                hay.contains('ride') ||
                hay.contains('transport') ||
                hay.contains('mobility');
            break;
          case 'wallet':
            matches = hay.contains('wallet') ||
                hay.contains('pay') ||
                hay.contains('payment') ||
                hay.contains('payments');
            break;
          case 'social':
            matches = hay.contains('moments') ||
                hay.contains('social') ||
                hay.contains('people_nearby') ||
                hay.contains('nearby') ||
                hay.contains('sticker') ||
                hay.contains('ملصق');
            break;
          case 'media':
            matches = hay.contains('channels') ||
                hay.contains('media') ||
                hay.contains('video') ||
                hay.contains('قناة');
            break;
          case 'services':
            matches = hay.contains('official') ||
                hay.contains('service') ||
                hay.contains('account') ||
                hay.contains('verified') ||
                hay.contains('رسمي');
            break;
          case 'tools':
            matches = hay.contains('favorite') ||
                hay.contains('bookmark') ||
                hay.contains('personal') ||
                hay.contains('saved') ||
                hay.contains('مفض');
            break;
          case 'Gaming':
            // Match against the descriptor's category — entries from
            // _localMiniPrograms() copy categoryEn into description_en,
            // so a category-name compare is unambiguous and doesn't
            // depend on the game's title containing the word "game".
            matches = descEn == 'Gaming' || descAr == 'الألعاب';
            break;
          default:
            matches = false;
        }
        if (!matches) return false;
      }
      if (term.isEmpty) return true;
      return id.contains(term) ||
          titleEn.contains(term) ||
          titleAr.contains(term) ||
          ownerName.contains(term);
    }).toList()
      ..sort((a, b) {
        final appA = (a['app_id'] ?? '').toString().trim();
        final appB = (b['app_id'] ?? '').toString().trim();
        final pinnedA = _pinned.contains(appA);
        final pinnedB = _pinned.contains(appB);
        if (pinnedA != pinnedB) return pinnedB ? 1 : -1;
        final opensA = _shelfOpenCount(appA);
        final opensB = _shelfOpenCount(appB);
        if (opensA != opensB) return opensB.compareTo(opensA);
        final ua =
            (a['usage_score'] is num) ? (a['usage_score'] as num).toInt() : 0;
        final ub =
            (b['usage_score'] is num) ? (b['usage_score'] as num).toInt() : 0;
        final ra = (a['rating'] is num) ? (a['rating'] as num).toDouble() : 0.0;
        final rb = (b['rating'] is num) ? (b['rating'] as num).toDouble() : 0.0;
        final scoreA = ua + (ra * 10.0);
        final scoreB = ub + (rb * 10.0);
        return scoreB.compareTo(scoreA);
      });

    if (filtered.isEmpty && !_loading) {
      return Center(
        child: ShamellEmptyState.empty(
          icon: Icons.widgets_outlined,
          title: l.isArabic
              ? 'لا توجد برامج مصغّرة مسجّلة بعد.'
              : 'No mini‑programs registered yet.',
        ),
      );
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = filtered[i];
        final appId = (p['app_id'] ?? '').toString();
        final titleEn = (p['title_en'] ?? '').toString();
        final titleAr = (p['title_ar'] ?? '').toString();
        final status = (p['status'] ?? '').toString().toLowerCase();
        final ownerName = (p['owner_name'] ?? '').toString();
        final ownerContact = (p['owner_contact'] ?? '').toString().trim();
        final releasedVersion =
            (p['released_version'] ?? p['last_version'] ?? '').toString();
        final personalOpenCount = _shelfOpenCount(appId);
        final seenVersion = _shelfSeenVersion(appId);
        final usageScore =
            (p['usage_score'] is num) ? (p['usage_score'] as num).toInt() : 0;
        final rating =
            (p['rating'] is num) ? (p['rating'] as num).toDouble() : 0.0;
        final moments30 = (p['moments_shares_30d'] is num)
            ? (p['moments_shares_30d'] as num).toInt()
            : 0;
        final ratingCount =
            (p['rating_count'] is num) ? (p['rating_count'] as num).toInt() : 0;
        final isArabic = l.isArabic;
        final title = isArabic && titleAr.isNotEmpty
            ? titleAr
            : (titleEn.isNotEmpty ? titleEn : appId);
        final subtitleLines = <String>[];
        final isMine = _myOwnerContact != null &&
            _myOwnerContact!.isNotEmpty &&
            ownerContact.isNotEmpty &&
            _myOwnerContact == ownerContact;
        if (ownerName.isNotEmpty) {
          if (isMine) {
            subtitleLines.add(
              isArabic ? 'أنت (المالك)' : 'You (owner)',
            );
          } else {
            subtitleLines.add(
              isArabic ? 'المالك: $ownerName' : 'Owner: $ownerName',
            );
          }
        } else if (isMine) {
          subtitleLines.add(
            isArabic ? 'أنت (المالك)' : 'You (owner)',
          );
        }
        if (releasedVersion.isNotEmpty) {
          subtitleLines.add(
            isArabic
                ? 'الإصدار المنشور: $releasedVersion'
                : 'Released version: $releasedVersion',
          );
        }
        if (personalOpenCount > 0) {
          subtitleLines.add(
            isArabic
                ? 'استخدامك: $personalOpenCount فتح'
                : 'Your use: $personalOpenCount opens',
          );
        }
        if (seenVersion.isNotEmpty && seenVersion == releasedVersion) {
          subtitleLines.add(
            isArabic ? 'شوهد الإصدار الحالي' : 'Current release seen',
          );
        }
        if (rating > 0) {
          final label = isArabic ? 'التقييم' : 'Rating';
          final ratingText = rating.toStringAsFixed(1);
          final countText = ratingCount > 0 ? ' ($ratingCount)' : '';
          subtitleLines.add('$label: $ratingText$countText');
        }
        if (moments30 > 0) {
          subtitleLines.add(
            isArabic
                ? 'مشاركات في اللحظات (٣٠ يوماً): $moments30'
                : 'Moments shares (30d): $moments30',
          );
        }
        String? categoryLabel;
        final haystack = '${titleEn.toLowerCase()} '
                '${titleAr.toLowerCase()} '
                '${(p['description_en'] ?? '').toString().toLowerCase()} '
                '${(p['description_ar'] ?? '').toString().toLowerCase()} '
                '${appId.toLowerCase()}'
            .trim();
        if (haystack.contains('bus') ||
            haystack.contains('ride') ||
            haystack.contains('transport') ||
            haystack.contains('mobility')) {
          categoryLabel = isArabic ? 'التنقل والنقل' : 'Transport';
        } else if (haystack.contains('wallet') ||
            haystack.contains('pay') ||
            haystack.contains('payment') ||
            haystack.contains('payments')) {
          categoryLabel = isArabic ? 'المحفظة والمدفوعات' : 'Wallet & payments';
        } else if (haystack.contains('moments') ||
            haystack.contains('social') ||
            haystack.contains('people_nearby') ||
            haystack.contains('nearby') ||
            haystack.contains('sticker')) {
          categoryLabel = isArabic ? 'اجتماعي' : 'Social';
        } else if (haystack.contains('channels') ||
            haystack.contains('media') ||
            haystack.contains('video')) {
          categoryLabel = isArabic ? 'الإعلام' : 'Media';
        } else if (haystack.contains('official') ||
            haystack.contains('service') ||
            haystack.contains('account') ||
            haystack.contains('verified')) {
          categoryLabel = isArabic ? 'الخدمات' : 'Services';
        } else if (haystack.contains('favorite') ||
            haystack.contains('bookmark') ||
            haystack.contains('personal') ||
            haystack.contains('saved')) {
          categoryLabel = isArabic ? 'أدوات شخصية' : 'Personal tools';
        } else if (haystack.contains('gaming') ||
            haystack.contains('game') ||
            haystack.contains('arcade') ||
            haystack.contains('puzzle')) {
          categoryLabel = isArabic ? 'الألعاب' : 'Gaming';
        }
        if (categoryLabel != null && categoryLabel.isNotEmpty) {
          subtitleLines.add(
            isArabic ? 'الفئة: $categoryLabel' : 'Category: $categoryLabel',
          );
        }
        final bool isTrending =
            usageScore >= 50 || rating >= 4.5 || moments30 >= 5;
        final bool isPinned = _pinned.contains(appId);
        final statusLabel = () {
          switch (status) {
            case 'active':
              return isArabic ? 'نشط' : 'Active';
            case 'draft':
              return isArabic ? 'مسودة' : 'Draft';
            default:
              return status.isNotEmpty ? status : null;
          }
        }();
        Color? statusColor;
        if (status == 'active') {
          statusColor = Tokens.colorPayments;
        } else if (status == 'draft') {
          statusColor = theme.colorScheme.onSurface.withValues(alpha: .6);
        }
        return ListTile(
          leading: const Icon(Icons.widgets_outlined),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isArabic ? 'برنامجي' : 'My mini‑program',
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.primary.withValues(alpha: .85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (isTrending) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_outlined,
                        size: 12,
                        color: theme.colorScheme.primary.withValues(alpha: .85),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isArabic ? 'شائع' : 'Trending',
                        style: TextStyle(
                          fontSize: 9,
                          color:
                              theme.colorScheme.primary.withValues(alpha: .85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          subtitle: subtitleLines.isEmpty
              ? null
              : Text(
                  subtitleLines.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (statusLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (statusColor ?? theme.colorScheme.primary)
                        .withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: statusColor ?? theme.colorScheme.primary,
                    ),
                  ),
                ),
              IconButton(
                iconSize: 18,
                tooltip: isArabic
                    ? (isPinned ? 'إزالة من المفضلة' : 'تثبيت كخدمة مفضلة')
                    : (isPinned ? 'Remove from pinned' : 'Pin mini‑program'),
                onPressed: () => _togglePinned(appId),
                icon: Icon(
                  isPinned ? Icons.star : Icons.star_border_outlined,
                  color: isPinned
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: .55),
                ),
              ),
            ],
          ),
          onTap: () {
            if (appId.isEmpty) return;
            // ignore: discarded_futures
            _trackOpen(appId);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MiniProgramPage(
                  id: appId,
                  baseUrl: widget.baseUrl,
                  walletId: widget.walletId,
                  deviceId: widget.deviceId,
                  onOpenMod: widget.onOpenMod,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
