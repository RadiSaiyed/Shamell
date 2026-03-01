import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'chat/chat_service.dart' show ChatLocalStore, OfficialNotificationMode;
import 'chat/chat_models.dart' show ChatContact;

import 'design_tokens.dart';
import 'l10n.dart';
import 'favorites_page.dart' show addFavoriteItemQuick;
import 'mini_apps_config.dart';
import '../mini_apps/payments/payments_shell.dart';
import 'ui_kit.dart';
import 'call_signaling.dart';
import 'moments_page.dart' show MomentsPage;
import 'channels_page.dart' show ChannelsPage;
import 'app_shell_widgets.dart' show AppBG;
import 'mini_program_runtime.dart';
import 'shamell_ui.dart';
import 'perf.dart';
import 'http_error.dart';
import 'safe_set_state.dart';

const Duration _officialRequestTimeout = Duration(seconds: 15);

class OfficialAccountsPage extends StatefulWidget {
  final String baseUrl;
  final void Function(String peerId)? onOpenChat;
  final String? initialCityFilter;
  final String? initialKindFilter;

  const OfficialAccountsPage({
    super.key,
    required this.baseUrl,
    this.onOpenChat,
    this.initialCityFilter,
    this.initialKindFilter,
  });

  @override
  State<OfficialAccountsPage> createState() => _OfficialAccountsPageState();
}

class _OfficialAccountsPageState extends State<OfficialAccountsPage>
    with SafeSetStateMixin<OfficialAccountsPage> {
  bool _loading = true;
  String _error = '';
  List<_OfficialAccount> _accounts = const [];
  bool _loadingDiscover = false;
  String _discoverError = '';
  List<_OfficialAccount> _allAccounts = const [];
  List<_OfficialAccount> _searchResults = const [];
  int _tabIndex = 0; // 0 = Following, 1 = Discover
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _selectedCategory = '';
  String _selectedCity = '';
  String _selectedKind = ''; // '', 'service', 'subscription'
  final Map<String, OfficialNotificationMode?> _notifModes = {};
  final Map<String, String> _seenFeedTs = {};
  bool _featuredOnly = false;
  bool _hotOnly = false;
  final Map<String, Map<String, dynamic>> _momentsStatsByAccountId =
      <String, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    _selectedCity = widget.initialCityFilter?.trim() ?? '';
    _selectedKind = widget.initialKindFilter?.trim().toLowerCase() ?? '';
    _load();
    _loadSeenFeed();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    final h = <String, String>{};
    if (jsonBody) h['content-type'] = 'application/json';
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) h['cookie'] = cookie;
    } catch (_) {}
    return h;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: const {'followed_only': 'true'});
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        final list = <_OfficialAccount>[];
        if (decoded is Map && decoded['accounts'] is List) {
          for (final e in decoded['accounts'] as List) {
            if (e is Map) {
              final m = e.cast<String, dynamic>();
              list.add(_OfficialAccount.fromJson(m));
            }
          }
        } else if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              final m = e.cast<String, dynamic>();
              list.add(_OfficialAccount.fromJson(m));
            }
          }
        }
        var result = list;
        try {
          final store = ChatLocalStore();
          final unreadMap = await store.loadUnread();
          result = list
              .map((a) => a.withUnreadFrom(unreadMap[a.chatPeerId] ?? 0))
              .toList();
        } catch (_) {}
        setState(() {
          _accounts = result;
        });
        await _preloadNotificationModes(result);
      } else {
        setState(() {
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } catch (e) {
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadDiscover() async {
    setState(() {
      _loadingDiscover = true;
      _discoverError = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: const {'followed_only': 'false'});
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        final list = <_OfficialAccount>[];
        if (decoded is Map && decoded['accounts'] is List) {
          for (final e in decoded['accounts'] as List) {
            if (e is Map) {
              final m = e.cast<String, dynamic>();
              list.add(_OfficialAccount.fromJson(m));
            }
          }
        } else if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              final m = e.cast<String, dynamic>();
              list.add(_OfficialAccount.fromJson(m));
            }
          }
        }
        var result = list;
        try {
          final store = ChatLocalStore();
          final unreadMap = await store.loadUnread();
          result = list
              .map((a) => a.withUnreadFrom(unreadMap[a.chatPeerId] ?? 0))
              .toList();
        } catch (_) {}
        setState(() {
          _allAccounts = result;
          // Reset search results when reloading full directory.
          _searchResults = const [];
        });
        // Best-effort preload of Moments social-impact stats for directory tiles.
        // ignore: discarded_futures
        _preloadMomentsStats(result);
        await _preloadNotificationModes(result);
      } else {
        setState(() {
          _discoverError = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } catch (e) {
      setState(() {
        _discoverError = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDiscover = false;
        });
      }
    }
  }

  Future<void> _loadSeenFeed() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('official.feed_seen');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final local = <String, String>{};
      decoded.forEach((k, v) {
        final key = k.toString();
        final val = v?.toString() ?? '';
        if (key.isNotEmpty && val.isNotEmpty) {
          local[key] = val;
        }
      });
      if (!mounted || local.isEmpty) return;
      setState(() {
        _seenFeedTs.addAll(local);
      });
    } catch (_) {}
  }

  Future<void> _runSearch(String q) async {
    final needle = q.trim();
    if (needle.length < 2) {
      if (!mounted) return;
      setState(() {
        _searchResults = const [];
      });
      return;
    }
    try {
      final uri = Uri.parse('${widget.baseUrl}/search').replace(
        queryParameters: <String, String>{
          'kind': 'official',
          'query': needle,
          'limit': '20',
        },
      );
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(r.body);
      final list = <_OfficialAccount>[];
      if (decoded is Map && decoded['results'] is List) {
        for (final e in decoded['results'] as List) {
          if (e is! Map) continue;
          if ((e['kind'] ?? '').toString() != 'official') continue;
          final extra = (e['extra'] as Map?)?.cast<String, dynamic>() ?? {};
          final rawBadges = extra['badges'];
          final badges = <String>[];
          if (rawBadges is List) {
            for (final b in rawBadges) {
              final s = (b ?? '').toString().trim();
              if (s.isNotEmpty) {
                badges.add(s);
              }
            }
          }
          final acc = _OfficialAccount(
            id: (e['id'] ?? '').toString(),
            kind: (extra['kind'] ?? 'service').toString(),
            name: (e['title'] ?? '').toString(),
            description: (e['snippet'] ?? '').toString().isEmpty
                ? null
                : (e['snippet'] ?? '').toString(),
            avatarUrl: null,
            verified: (extra['badges'] is List &&
                (extra['badges'] as List).contains('verified')),
            featured: (extra['badges'] is List &&
                (extra['badges'] as List).contains('featured')),
            badges: badges,
            unreadCount: 0,
            lastItemTitle: null,
            lastItemTs: null,
            chatPeerId: null,
            miniAppId: null,
            category: (extra['category'] ?? '').toString().isEmpty
                ? null
                : (extra['category'] ?? '').toString(),
            city: (extra['city'] ?? '').toString().isEmpty
                ? null
                : (extra['city'] ?? '').toString(),
            address: null,
            openingHours: null,
            websiteUrl: null,
            qrPayload: null,
            followed: false,
            menuItems: const <_OfficialMenuItem>[],
            notifMode: null,
          );
          list.add(acc);
        }
      }
      if (!mounted) return;
      setState(() {
        _searchResults = list;
      });
    } catch (_) {}
  }

  Future<void> _preloadNotificationModes(
      List<_OfficialAccount> accounts) async {
    try {
      final store = ChatLocalStore();
      final local = <String, OfficialNotificationMode?>{};
      for (final a in accounts) {
        final peerId = (a.chatPeerId ?? '').trim();
        if (peerId.isEmpty) continue;
        OfficialNotificationMode? mode = a.notifMode;
        if (mode != null) {
          await store.setOfficialNotifMode(peerId, mode);
        } else {
          mode = await store.loadOfficialNotifMode(peerId);
        }
        local[peerId] = mode;
      }
      if (!mounted || local.isEmpty) return;
      setState(() {
        _notifModes.addAll(local);
      });
    } catch (_) {}
  }

  Future<void> _preloadMomentsStats(List<_OfficialAccount> accounts) async {
    try {
      // Only preload a small subset to avoid too many requests.
      final subset = accounts.take(10).toList();
      for (final a in subset) {
        final id = a.id.trim();
        if (id.isEmpty) continue;
        if (_momentsStatsByAccountId.containsKey(id)) continue;
        try {
          final uri = Uri.parse(
                  '${widget.baseUrl}/official_accounts/${Uri.encodeComponent(id)}/moments_stats')
              .replace(queryParameters: const {});
          final r = await http
              .get(uri, headers: await _hdr())
              .timeout(_officialRequestTimeout);
          if (r.statusCode < 200 || r.statusCode >= 300) continue;
          final decoded = jsonDecode(r.body);
          if (decoded is! Map) continue;
          final total = decoded['total_shares'];
          final shares30 = decoded['shares_30d'];
          final followers = decoded['followers'];
          final per1k = decoded['shares_per_1k_followers'];
          final totalInt = total is num ? total.toInt() : 0;
          final shares30Int = shares30 is num ? shares30.toInt() : 0;
          final followersInt = followers is num ? followers.toInt() : 0;
          final per1kVal = per1k is num ? per1k.toDouble() : 0.0;
          if (!mounted) continue;
          _momentsStatsByAccountId[id] = <String, dynamic>{
            'total_shares': totalInt,
            'shares_30d': shares30Int,
            'followers': followersInt,
            'shares_per_1k_followers': per1kVal,
          };
        } catch (_) {
          continue;
        }
      }
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  List<_OfficialAccount> _filtered(List<_OfficialAccount> src) {
    var list = src;
    final catFilter = _selectedCategory.trim().toLowerCase();
    if (catFilter.isNotEmpty) {
      list = list
          .where((a) => (a.category ?? '').toLowerCase() == catFilter)
          .toList();
    }
    final cityFilter = _selectedCity.trim().toLowerCase();
    if (cityFilter.isNotEmpty) {
      list = list
          .where((a) => (a.city ?? '').toLowerCase() == cityFilter)
          .toList();
    }
    final kindFilter = _selectedKind.trim().toLowerCase();
    if (kindFilter.isNotEmpty) {
      if (kindFilter == 'service') {
        list = list.where((a) => (a.kind).toLowerCase() == 'service').toList();
      } else if (kindFilter == 'subscription') {
        list = list.where((a) => (a.kind).toLowerCase() != 'service').toList();
      }
    }
    if (_featuredOnly) {
      list = list.where((a) => a.featured).toList();
    }
    if (_hotOnly) {
      list = list.where((a) {
        final stats = _momentsStatsByAccountId[a.id];
        if (stats == null) return false;
        final totalRaw = stats['total_shares'];
        final s30Raw = stats['shares_30d'];
        final per1kRaw = stats['shares_per_1k_followers'];
        final total = totalRaw is num ? totalRaw.toInt() : 0;
        final s30 = s30Raw is num ? s30Raw.toInt() : 0;
        final per1k = per1kRaw is num ? per1kRaw.toDouble() : 0.0;
        // Hot if either strong all-time, strong last 30d or high per-1k.
        return total >= 10 || s30 >= 3 || per1k >= 5.0;
      }).toList();
    }
    return list;
  }

  bool _hasUnreadFeed(_OfficialAccount a) {
    final lastRaw = (a.lastItemTs ?? '').trim();
    if (lastRaw.isEmpty) return false;
    final seenRaw = (_seenFeedTs[a.id] ?? '').trim();
    if (seenRaw.isEmpty) return true;
    try {
      final last = DateTime.parse(lastRaw);
      final seen = DateTime.parse(seenRaw);
      return last.isAfter(seen);
    } catch (_) {
      return false;
    }
  }

  Future<void> _markAllFeedsSeen() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('official.feed_seen') ?? '{}';
      Map<String, dynamic> map;
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        map = <String, dynamic>{};
      }
      void apply(List<_OfficialAccount> list) {
        for (final a in list) {
          final id = a.id.trim();
          final ts = (a.lastItemTs ?? '').trim();
          if (id.isNotEmpty && ts.isNotEmpty) {
            map[id] = ts;
          }
        }
      }

      apply(_accounts);
      apply(_allAccounts);
      await sp.setString('official.feed_seen', jsonEncode(map));
      if (!mounted) return;
      setState(() {
        _seenFeedTs
          ..clear()
          ..addAll(map.map((k, v) => MapEntry(k.toString(), v.toString())));
      });
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تم اعتبار كل تحديثات الحسابات الرسمية مقروءة.'
                : 'All official feeds marked as read.',
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final isDiscover = _tabIndex == 1;
    final baseList = isDiscover ? _allAccounts : _accounts;
    final filtered = _filtered(baseList);

    final isLoading = isDiscover
        ? (_loadingDiscover && baseList.isEmpty)
        : (_loading && baseList.isEmpty);
    final err = isDiscover ? _discoverError : _error;

    // Collect categories for filter chips.
    final categorySet = <String>{};
    for (final a in baseList) {
      final c = (a.category ?? '').trim();
      if (c.isNotEmpty) categorySet.add(c);
    }
    final categories = categorySet.toList()..sort();
    final hasAnyUnreadFeed = baseList.any(_hasUnreadFeed);

    // Simple heuristic for "recommended in your city" based on most common city.
    List<_OfficialAccount> recommended = const [];
    String? recommendedCityLabel;
    if (isDiscover &&
        _search.trim().isEmpty &&
        _selectedCategory.trim().isEmpty &&
        _allAccounts.isNotEmpty) {
      final counts = <String, int>{};
      final labels = <String, String>{};
      for (final a in _allAccounts) {
        final city = (a.city ?? '').trim();
        if (city.isEmpty) continue;
        final key = city.toLowerCase();
        counts[key] = (counts[key] ?? 0) + 1;
        labels.putIfAbsent(key, () => city);
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
        if (bestCount > 0) {
          recommended = _allAccounts
              .where((a) => (a.city ?? '').trim().toLowerCase() == bestKey)
              .toList();
          if (recommended.length > 3) {
            recommended = recommended.sublist(0, 3);
          }
          recommendedCityLabel = labels[bestKey] ?? '';
          if (recommendedCityLabel.isEmpty && recommended.isNotEmpty) {
            recommendedCityLabel = recommended.first.city;
          }
        }
      }
    }

    // When a search query is active and we have results from /search,
    // use them as the primary Discover list to get Shamell-like ranking.
    final bool useSearch =
        _search.trim().isNotEmpty && _searchResults.isNotEmpty;
    final listForUi = useSearch ? _searchResults : filtered;

    final serviceFiltered =
        listForUi.where((a) => a.kind.toLowerCase() == 'service').toList();
    final subscriptionFiltered =
        listForUi.where((a) => a.kind.toLowerCase() != 'service').toList();

    final body = isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.surfaceContainerHighest
                        : ShamellPalette.searchFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() {
                              _tabIndex = 0;
                            });
                          },
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _tabIndex == 0
                                  ? theme.colorScheme.surface
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              l.isArabic ? 'المتابَعة' : 'Following',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() {
                              _tabIndex = 1;
                            });
                            if (_allAccounts.isEmpty && !_loadingDiscover) {
                              _loadDiscover();
                            }
                          },
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _tabIndex == 1
                                  ? theme.colorScheme.surface
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              l.isArabic ? 'اكتشاف' : 'Discover',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ShamellSearchBar(
                hintText: l.isArabic
                    ? 'ابحث في الحسابات الرسمية'
                    : 'Search official accounts',
                controller: _searchCtrl,
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                onChanged: (v) {
                  setState(() {
                    _search = v;
                  });
                  // Use rich /search ranking for non-empty queries.
                  // ignore: discarded_futures
                  _runSearch(v);
                },
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(
                          l.isArabic ? 'الكل' : 'All',
                        ),
                        selected: _selectedCategory.trim().isEmpty &&
                            _selectedKind.isEmpty &&
                            _selectedCity.isEmpty &&
                            !_featuredOnly &&
                            !_hotOnly,
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() {
                            _selectedCategory = '';
                            _selectedKind = '';
                            _selectedCity = '';
                            _featuredOnly = false;
                            _hotOnly = false;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(
                          l.isArabic ? 'الخدمات' : 'Service',
                        ),
                        selected: _selectedKind == 'service',
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() {
                            _selectedKind = 'service';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 14),
                            const SizedBox(width: 4),
                            Text(l.isArabic ? 'مميزة' : 'Featured'),
                          ],
                        ),
                        selected: _featuredOnly,
                        onSelected: (sel) {
                          setState(() {
                            _featuredOnly = sel;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department_outlined,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l.isArabic
                                  ? 'رائج خلال ٣٠ يوماً'
                                  : 'Hot (last 30 days)',
                            ),
                          ],
                        ),
                        selected: _hotOnly,
                        onSelected: (sel) {
                          setState(() {
                            _hotOnly = sel;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(
                          l.isArabic ? 'الاشتراك' : 'Subscription',
                        ),
                        selected: _selectedKind == 'subscription',
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() {
                            _selectedKind = 'subscription';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      // Common service categories as quick filters when available.
                      if (categories
                          .map((c) => c.toLowerCase())
                          .contains('transport'))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(
                              l.isArabic ? 'التنقل والنقل' : 'Transport',
                            ),
                            selected: _selectedCategory.trim().toLowerCase() ==
                                'transport',
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _selectedCategory = 'transport';
                              });
                            },
                          ),
                        ),
                      if (categories
                          .map((c) => c.toLowerCase())
                          .contains('wallet'))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(
                              l.isArabic ? 'المحفظة' : 'Wallet & payments',
                            ),
                            selected: _selectedCategory.trim().toLowerCase() ==
                                'wallet',
                            onSelected: (sel) {
                              if (!sel) return;
                              setState(() {
                                _selectedCategory = 'wallet';
                              });
                            },
                          ),
                        ),
                      const SizedBox(width: 8),
                      if (categories.isNotEmpty) ...[
                        ...categories.map((c) {
                          final sel = _selectedCategory.trim().toLowerCase() ==
                              c.toLowerCase();
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(_labelForCategory(c, l)),
                              selected: sel,
                              onSelected: (s) {
                                setState(() {
                                  _selectedCategory = s ? c : '';
                                });
                              },
                            ),
                          );
                        }),
                        const SizedBox(width: 4),
                      ],
                      if (_selectedCity.isNotEmpty) ...[
                        ChoiceChip(
                          label: Text(
                            l.isArabic
                                ? 'الخدمات في $_selectedCity'
                                : 'Services in $_selectedCity',
                          ),
                          selected: true,
                          onSelected: (sel) {
                            if (!sel) return;
                            setState(() {
                              _selectedCity = '';
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              if (err.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    err,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              if (filtered.isEmpty && err.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    isDiscover
                        ? (l.isArabic
                            ? 'لا توجد حسابات رسمية لعرضها.'
                            : 'No official accounts to show yet.')
                        : (l.isArabic
                            ? 'لا توجد حسابات رسمية متابَعة بعد.'
                            : 'You are not following any official accounts yet.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      if (isDiscover &&
                          _momentsStatsByAccountId.isNotEmpty &&
                          err.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                          child: Text(
                            l.isArabic
                                ? 'خدمات رائجة في اللحظات'
                                : 'Hot in Moments · services',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .80),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: () {
                                final hot = <_OfficialAccount>[];
                                for (final a in _allAccounts) {
                                  final stats = _momentsStatsByAccountId[a.id];
                                  if (stats == null) continue;
                                  final totalRaw = stats['total_shares'];
                                  final s30Raw = stats['shares_30d'];
                                  final per1kRaw =
                                      stats['shares_per_1k_followers'];
                                  final total =
                                      totalRaw is num ? totalRaw.toInt() : 0;
                                  final s30 =
                                      s30Raw is num ? s30Raw.toInt() : 0;
                                  final per1k = per1kRaw is num
                                      ? per1kRaw.toDouble()
                                      : 0.0;
                                  if (total >= 10 || s30 >= 3 || per1k >= 5.0) {
                                    hot.add(a);
                                  }
                                }
                                hot.sort((a, b) {
                                  final sa = _momentsStatsByAccountId[a.id];
                                  final sb = _momentsStatsByAccountId[b.id];
                                  double scoreA = 0;
                                  double scoreB = 0;
                                  if (sa != null) {
                                    final totalA =
                                        (sa['total_shares'] as num? ?? 0)
                                            .toDouble();
                                    final s30A = (sa['shares_30d'] as num? ?? 0)
                                        .toDouble();
                                    final per1kA =
                                        (sa['shares_per_1k_followers']
                                                    as num? ??
                                                0)
                                            .toDouble();
                                    scoreA = s30A * 2.0 + per1kA + totalA * 0.1;
                                  }
                                  if (sb != null) {
                                    final totalB =
                                        (sb['total_shares'] as num? ?? 0)
                                            .toDouble();
                                    final s30B = (sb['shares_30d'] as num? ?? 0)
                                        .toDouble();
                                    final per1kB =
                                        (sb['shares_per_1k_followers']
                                                    as num? ??
                                                0)
                                            .toDouble();
                                    scoreB = s30B * 2.0 + per1kB + totalB * 0.1;
                                  }
                                  return scoreB.compareTo(scoreA);
                                });
                                final top =
                                    hot.length > 3 ? hot.sublist(0, 3) : hot;
                                if (top.isEmpty) return <Widget>[];
                                return top
                                    .map(
                                      (a) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: ActionChip(
                                          avatar: CircleAvatar(
                                            radius: 12,
                                            backgroundImage:
                                                (a.avatarUrl ?? '').isNotEmpty
                                                    ? NetworkImage(a.avatarUrl!)
                                                    : null,
                                            child: (a.avatarUrl ?? '').isEmpty
                                                ? Text(
                                                    a.name.isNotEmpty
                                                        ? a.name.characters
                                                            .first
                                                            .toUpperCase()
                                                        : '?',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          label: Text(
                                            a.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    OfficialAccountFeedPage(
                                                  baseUrl: widget.baseUrl,
                                                  account: a.toHandle(),
                                                  onOpenChat: widget.onOpenChat,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    )
                                    .toList();
                              }(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      if (isDiscover &&
                          recommended.isNotEmpty &&
                          err.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: Text(
                            (recommendedCityLabel ?? '').isNotEmpty
                                ? (l.isArabic
                                    ? 'موصى به في ${recommendedCityLabel!}'
                                    : 'Recommended in ${recommendedCityLabel!}')
                                : (l.isArabic ? 'موصى به' : 'Recommended'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .80),
                            ),
                          ),
                        ),
                        if (recommendedCityLabel != null &&
                            recommendedCityLabel!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                FilterChip(
                                  label: Text(
                                    l.isArabic
                                        ? 'لحظات: خدمات في ${recommendedCityLabel!}'
                                        : 'Moments: services in ${recommendedCityLabel!}',
                                  ),
                                  onSelected: (sel) {
                                    if (!sel) return;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => MomentsPage(
                                          baseUrl: widget.baseUrl,
                                          officialCity: recommendedCityLabel,
                                          officialCategory: null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                FilterChip(
                                  label: Text(
                                    l.isArabic
                                        ? 'لحظات: النقل في ${recommendedCityLabel!}'
                                        : 'Moments: transport in ${recommendedCityLabel!}',
                                  ),
                                  onSelected: (sel) {
                                    if (!sel) return;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => MomentsPage(
                                          baseUrl: widget.baseUrl,
                                          officialCategory: 'transport',
                                          officialCity: recommendedCityLabel,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ...recommended
                            .map(
                              (a) => _buildAccountTile(context, theme, l, a),
                            )
                            .toList(),
                        const Divider(height: 1),
                      ],
                      if (serviceFiltered.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text(
                            l.isArabic ? 'حسابات الخدمات' : 'Service accounts',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .80),
                            ),
                          ),
                        ),
                        ...serviceFiltered
                            .map(
                              (a) => _buildAccountTile(context, theme, l, a),
                            )
                            .toList(),
                        const Divider(height: 1),
                      ],
                      if (subscriptionFiltered.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text(
                            l.isArabic
                                ? 'حسابات الاشتراك'
                                : 'Subscription accounts',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .80),
                            ),
                          ),
                        ),
                        ...subscriptionFiltered
                            .map(
                              (a) => _buildAccountTile(context, theme, l, a),
                            )
                            .toList(),
                      ],
                    ],
                  ),
                ),
            ],
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الحسابات الرسمية' : 'Official accounts'),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          if (hasAnyUnreadFeed)
            IconButton(
              tooltip:
                  l.isArabic ? 'اعتبار الكل مقروءاً' : 'Mark all feeds read',
              icon: const Icon(Icons.mark_email_read_outlined),
              onPressed: _markAllFeedsSeen,
            ),
        ],
      ),
      body: body,
    );
  }

  String _labelForCategory(String raw, L10n l) {
    final key = raw.toLowerCase();
    if (key.isEmpty) return raw;
    if (l.isArabic) {
      switch (key) {
        case 'transport':
          return 'التنقل والنقل';
        case 'wallet':
        case 'payments':
          return 'المحفظة والمدفوعات';
        default:
          return raw;
      }
    } else {
      switch (key) {
        case 'transport':
          return 'Transport';
        case 'wallet':
        case 'payments':
          return 'Wallet & payments';
        default:
          return raw;
      }
    }
  }

  Widget _buildAccountTile(
      BuildContext context, ThemeData theme, L10n l, _OfficialAccount a) {
    final chatId = (a.chatPeerId ?? '').trim();
    final hasChat = chatId.isNotEmpty;
    final mode = hasChat ? _notifModes[chatId] : null;

    IconData? notifIcon;
    Color? notifColor;
    if (hasChat) {
      switch (mode) {
        case OfficialNotificationMode.muted:
          notifIcon = Icons.notifications_off_outlined;
          notifColor = theme.colorScheme.onSurface.withValues(alpha: .60);
          break;
        case OfficialNotificationMode.summary:
          notifIcon = Icons.notifications_none_outlined;
          notifColor = theme.colorScheme.primary;
          break;
        case OfficialNotificationMode.full:
        case null:
          notifIcon = Icons.notifications_active_outlined;
          notifColor = theme.colorScheme.primary;
          break;
      }
    }

    final hasUnreadFeed = _hasUnreadFeed(a);
    final stats = _momentsStatsByAccountId[a.id];
    final totalShares =
        stats != null ? (stats['total_shares'] as int? ?? 0) : 0;
    final shares30 = stats != null ? (stats['shares_30d'] as int? ?? 0) : 0;
    final per1k = stats != null
        ? (stats['shares_per_1k_followers'] as num? ?? 0).toDouble()
        : 0.0;
    final bool isHotRecent =
        shares30 >= 3 || per1k >= 5.0 || a.badges.contains('hot_in_moments');
    final rawCategory = (a.category ?? '').trim();
    final rawCity = (a.city ?? '').trim();
    final hasCategory = rawCategory.isNotEmpty;
    final hasCity = rawCity.isNotEmpty;
    final categoryLabel =
        hasCategory ? _labelForCategory(rawCategory, l) : null;

    return ListTile(
      onTap: () {
        final isService = a.kind.toLowerCase() == 'service';
        Perf.action('official_open_feed');
        Perf.action('official_open_from_list');
        Perf.action(isService
            ? 'official_open_feed_service'
            : 'official_open_feed_subscription');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OfficialAccountFeedPage(
              baseUrl: widget.baseUrl,
              account: a.toHandle(),
              onOpenChat: widget.onOpenChat,
            ),
          ),
        );
      },
      leading: CircleAvatar(
        backgroundImage:
            a.avatarUrl != null ? NetworkImage(a.avatarUrl!) : null,
        child: a.avatarUrl == null
            ? Text(
                a.name.isNotEmpty ? a.name.characters.first.toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          if (a.verified)
            Padding(
              padding: EdgeInsets.only(left: 4.0),
              child: Icon(
                Icons.verified,
                size: 16,
                color: Tokens.colorPayments,
              ),
            ),
          if (a.featured)
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      l.isArabic ? 'مميز' : 'Featured',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (hasUnreadFeed)
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Icon(
                Icons.brightness_1,
                size: 8,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.lastItemTitle ??
                (a.description ??
                    (l.isArabic
                        ? 'حساب رسمي في Shamell'
                        : 'Official account in Shamell')),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasCategory || hasCity)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasCategory && categoryLabel != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        categoryLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              theme.colorScheme.primary.withValues(alpha: .85),
                        ),
                      ),
                    ),
                    if (hasCity) const SizedBox(width: 6),
                  ],
                  if (hasCity) ...[
                    const Icon(
                      Icons.location_on_outlined,
                      size: 12,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      rawCity,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .65),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (totalShares > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                () {
                  if (l.isArabic) {
                    final parts = <String>[];
                    parts.add('تمت المشاركة $totalShares مرة');
                    if (shares30 > 0) {
                      parts.add('$shares30 مشاركات في آخر ٣٠ يوماً');
                    }
                    if (per1k > 0) {
                      parts.add(
                          '${per1k.toStringAsFixed(1)} مشاركة لكل ١٬٠٠٠ متابع');
                    }
                    return 'الأثر في اللحظات: ${parts.join(' · ')}';
                  } else {
                    final parts = <String>[];
                    parts.add('shared $totalShares times');
                    if (shares30 > 0) {
                      parts.add('$shares30 shares in last 30 days');
                    }
                    if (per1k > 0) {
                      parts.add(
                          '${per1k.toStringAsFixed(1)} shares per 1k followers');
                    }
                    return 'Moments impact: ${parts.join(' · ')}';
                  }
                }(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
                ),
              ),
            ),
          if (isHotRecent)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_outlined,
                      size: 14,
                      color: theme.colorScheme.primary.withValues(alpha: .85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.isArabic
                          ? 'رائج في آخر ٣٠ يوماً'
                          : 'Hot in last 30 days',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      trailing: (!hasChat && a.unreadCount <= 0 && (a.miniAppId == null))
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (a.unreadCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      a.unreadCount > 99 ? '99+' : '${a.unreadCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                if ((a.miniAppId ?? '').isNotEmpty) ...[
                  if (a.unreadCount > 0) const SizedBox(width: 8),
                  IconButton(
                    tooltip: () {
                      final id = (a.miniAppId ?? '').trim();
                      if (id == 'bus')
                        return l.isArabic ? 'فتح الباص' : 'Open bus';
                      if (id == 'payments') {
                        return l.isArabic ? 'فتح المحفظة' : 'Open wallet';
                      }
                      return l.isArabic ? 'فتح الخدمة' : 'Open service';
                    }(),
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () {
                      _openMiniAppForAccount(context, a);
                    },
                  ),
                ],
                if (hasChat && notifIcon != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: l.isArabic
                        ? 'إعدادات الإشعارات'
                        : 'Notification settings',
                    icon: Icon(
                      notifIcon,
                      size: 20,
                      color: notifColor,
                    ),
                    onPressed: () => _showAccountNotificationSheet(a),
                  ),
                ],
              ],
            ),
    );
  }

  void _openMiniAppForAccount(BuildContext context, _OfficialAccount a) {
    final raw = (a.miniAppId ?? '').trim().toLowerCase();
    if (raw.isEmpty) return;

    void openMod(String next) {
      final id = next.trim().toLowerCase();
      if (id.isEmpty) return;
      if (id == 'payments' || id == 'alias' || id == 'merchant') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentsPage(
              widget.baseUrl,
              '',
              'official',
              contextLabel: a.name,
            ),
          ),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MiniProgramPage(
            id: id,
            baseUrl: widget.baseUrl,
            walletId: '',
            deviceId: 'official',
            onOpenMod: openMod,
          ),
        ),
      );
    }

    openMod(raw);
  }

  Future<void> _showAccountNotificationSheet(_OfficialAccount a) async {
    final chatId = (a.chatPeerId ?? '').trim();
    if (chatId.isEmpty) return;
    final l = L10n.of(context);
    OfficialNotificationMode? current;
    try {
      final store = ChatLocalStore();
      current = await store.loadOfficialNotifMode(chatId);
    } catch (_) {
      current = null;
    }
    current ??= OfficialNotificationMode.full;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: RadioGroup<OfficialNotificationMode>(
              groupValue: current,
              onChanged: (mode) async {
                if (mode == null) return;
                Navigator.of(ctx).pop();
                await _setAccountNotificationMode(chatId, mode);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.full,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic
                          ? 'إظهار معاينة الرسائل'
                          : 'Show message preview',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عرض محتوى الرسائل في الإشعارات لهذا الحساب'
                          : 'Show message content in notifications for this account',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.summary,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic
                          ? 'إخفاء محتوى الرسائل'
                          : 'Hide message content',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'إظهار إشعار مختصر فقط عند وصول رسالة جديدة'
                          : 'Show a brief alert without message text',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.muted,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic ? 'كتم الإشعارات' : 'Mute notifications',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عدم إظهار إشعارات لهذه الدردشة'
                          : 'Turn off local notifications for this chat',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _accountIdForChat(String chatId) {
    for (final a in _accounts) {
      final pid = (a.chatPeerId ?? a.id).trim();
      if (pid == chatId) return a.id;
    }
    for (final a in _allAccounts) {
      final pid = (a.chatPeerId ?? a.id).trim();
      if (pid == chatId) return a.id;
    }
    return null;
  }

  Future<void> _setAccountNotificationMode(
      String chatId, OfficialNotificationMode mode) async {
    if (chatId.isEmpty) return;
    try {
      final store = ChatLocalStore();
      final contacts = await store.loadContacts();
      ChatContact? updatedContact;
      final updated = <ChatContact>[];
      for (final c in contacts) {
        if (c.id == chatId) {
          final u = c.copyWith(muted: mode == OfficialNotificationMode.muted);
          updatedContact = u;
          updated.add(u);
        } else {
          updated.add(c);
        }
      }
      if (updatedContact != null) {
        await store.saveContacts(updated);
      }
      await store.setOfficialNotifMode(chatId, mode);
      // Sync per-account mode to server using account_id when known.
      final accId = _accountIdForChat(chatId);
      if (accId != null) {
        try {
          final uri = Uri.parse(
              '${widget.baseUrl}/official_accounts/$accId/notification_mode');
          final body = jsonEncode({
            'mode': switch (mode) {
              OfficialNotificationMode.full => 'full',
              OfficialNotificationMode.summary => 'summary',
              OfficialNotificationMode.muted => 'muted',
            }
          });
          await http
              .post(uri, headers: await _hdr(jsonBody: true), body: body)
              .timeout(_officialRequestTimeout);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _notifModes[chatId] = mode;
      });
    } catch (_) {}
  }
}

class OfficialAccountDeepLinkPage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final void Function(String peerId)? onOpenChat;

  const OfficialAccountDeepLinkPage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    this.onOpenChat,
  });

  @override
  State<OfficialAccountDeepLinkPage> createState() =>
      _OfficialAccountDeepLinkPageState();
}

class _OfficialAccountDeepLinkPageState
    extends State<OfficialAccountDeepLinkPage>
    with SafeSetStateMixin<OfficialAccountDeepLinkPage> {
  bool _loading = true;
  String _error = '';
  OfficialAccountHandle? _account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    final h = <String, String>{};
    if (jsonBody) h['content-type'] = 'application/json';
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) h['cookie'] = cookie;
    } catch (_) {}
    return h;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: const {'followed_only': 'false'});
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        final list = <OfficialAccountHandle>[];
        if (decoded is Map && decoded['accounts'] is List) {
          for (final e in decoded['accounts'] as List) {
            if (e is Map) {
              list.add(
                  OfficialAccountHandle.fromJson(e.cast<String, dynamic>()));
            }
          }
        } else if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              list.add(
                  OfficialAccountHandle.fromJson(e.cast<String, dynamic>()));
            }
          }
        }
        final acc = list
            .where((a) => a.id == widget.accountId)
            .cast<OfficialAccountHandle?>()
            .firstWhere((a) => a != null, orElse: () => null);
        if (!mounted) return;
        if (acc == null) {
          setState(() {
            _error = 'Unknown official account';
            _loading = false;
          });
        } else {
          setState(() {
            _account = acc;
            _loading = false;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (_loading) {
      return DomainPageScaffold(
        background: const AppBG(),
        title: l.isArabic ? 'الحسابات الرسمية' : 'Official accounts',
        child: const Center(child: CircularProgressIndicator()),
        scrollable: false,
      );
    }
    if (_account == null) {
      return DomainPageScaffold(
        background: const AppBG(),
        title: l.isArabic ? 'الحسابات الرسمية' : 'Official accounts',
        child: Center(
          child: Text(
            _error.isNotEmpty ? _error : 'Unknown official account',
          ),
        ),
        scrollable: false,
      );
    }
    return OfficialAccountFeedPage(
      baseUrl: widget.baseUrl,
      account: _account!,
      onOpenChat: widget.onOpenChat,
    );
  }
}

class OfficialFeedItemDeepLinkPage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final String itemId;
  final void Function(String peerId)? onOpenChat;

  const OfficialFeedItemDeepLinkPage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    required this.itemId,
    this.onOpenChat,
  });

  @override
  State<OfficialFeedItemDeepLinkPage> createState() =>
      _OfficialFeedItemDeepLinkPageState();
}

class _OfficialFeedItemDeepLinkPageState
    extends State<OfficialFeedItemDeepLinkPage>
    with SafeSetStateMixin<OfficialFeedItemDeepLinkPage> {
  bool _loading = true;
  String _error = '';
  OfficialAccountHandle? _account;
  _OfficialFeedItem? _item;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    final h = <String, String>{};
    if (jsonBody) h['content-type'] = 'application/json';
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) h['cookie'] = cookie;
    } catch (_) {}
    return h;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts');
      final r = await http
          .get(
            uri.replace(queryParameters: const {'followed_only': 'false'}),
            headers: await _hdr(),
          )
          .timeout(_officialRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        final list = <OfficialAccountHandle>[];
        if (decoded is Map && decoded['accounts'] is List) {
          for (final e in decoded['accounts'] as List) {
            if (e is Map) {
              list.add(
                  OfficialAccountHandle.fromJson(e.cast<String, dynamic>()));
            }
          }
        } else if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              list.add(
                  OfficialAccountHandle.fromJson(e.cast<String, dynamic>()));
            }
          }
        }
        final acc = list
            .where((a) => a.id == widget.accountId)
            .cast<OfficialAccountHandle?>()
            .firstWhere((a) => a != null, orElse: () => null);
        if (acc == null) {
          if (!mounted) return;
          setState(() {
            _error = 'Unknown official account';
            _loading = false;
          });
          return;
        }
        final feedUri =
            Uri.parse('${widget.baseUrl}/official_accounts/${acc.id}/feed')
                .replace(queryParameters: const {'limit': '50'});
        final fr = await http
            .get(feedUri, headers: await _hdr())
            .timeout(_officialRequestTimeout);
        if (fr.statusCode >= 200 && fr.statusCode < 300) {
          final fd = jsonDecode(fr.body);
          _OfficialFeedItem? found;
          if (fd is Map && fd['items'] is List) {
            for (final e in fd['items'] as List) {
              if (e is Map) {
                final it =
                    _OfficialFeedItem.fromJson(e.cast<String, dynamic>());
                if (it.id == widget.itemId) {
                  found = it;
                  break;
                }
              }
            }
          }
          if (!mounted) return;
          setState(() {
            _account = acc;
            _item = found;
            _loading = false;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _error = sanitizeHttpError(
              statusCode: fr.statusCode,
              rawBody: fr.body,
              isArabic: L10n.of(context).isArabic,
            );
            _loading = false;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final acc = _account;
    final item = _item;
    if (_loading) {
      return DomainPageScaffold(
        background: const AppBG(),
        title: l.isArabic ? 'الحسابات الرسمية' : 'Official accounts',
        child: const Center(child: CircularProgressIndicator()),
        scrollable: false,
      );
    }
    if (acc == null || item == null) {
      return DomainPageScaffold(
        background: const AppBG(),
        title: l.isArabic ? 'الحسابات الرسمية' : 'Official accounts',
        child: Center(
          child: Text(
            _error.isNotEmpty ? _error : 'Unknown feed item',
          ),
        ),
        scrollable: false,
      );
    }
    final isLive = item.type.toLowerCase() == 'live';
    final chatId = (acc.chatPeerId ?? acc.id).trim();
    final onOpenChat = widget.onOpenChat;
    return DomainPageScaffold(
      background: const AppBG(),
      title: (item.title ?? '').isNotEmpty ? item.title! : acc.name,
      scrollable: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.live_tv_outlined,
                      size: 16,
                      color: theme.colorScheme.error.withValues(alpha: .90),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.isArabic ? 'بث مباشر الآن' : 'Live now',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            if (isLive) const SizedBox(height: 12),
            if (isLive && (item.liveUrl ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final url = item.liveUrl!;
                    final uri = Uri.tryParse(url);
                    if (uri == null) return;
                    if (!await canLaunchUrl(uri)) return;
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(
                    l.isArabic ? 'مشاهدة البث الآن' : 'Watch live now',
                  ),
                ),
              ),
            if ((item.thumbUrl ?? '').isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    item.thumbUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (item.tsLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  item.tsLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .60),
                  ),
                ),
              ),
            if ((item.snippet ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  item.snippet!,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 24),
            Text(
              l.isArabic ? 'من' : 'From',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if ((acc.avatarUrl ?? '').isNotEmpty)
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(acc.avatarUrl!),
                  ),
                if ((acc.avatarUrl ?? '').isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    acc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      Perf.action('official_share_to_moments');
                      final buf = StringBuffer();
                      if ((item.title ?? '').isNotEmpty) {
                        buf.writeln(item.title);
                      }
                      if ((item.snippet ?? '').isNotEmpty) {
                        buf.writeln(item.snippet);
                      }
                      buf.writeln();
                      buf.writeln(
                        l.isArabic ? 'من ${acc.name}' : 'From ${acc.name}',
                      );
                      buf.writeln(
                        'shamell://official/${acc.id}/${item.id}',
                      );
                      var text = buf.toString().trim();
                      if (text.isEmpty) return;
                      if (!text.contains('#')) {
                        text += l.isArabic
                            ? ' #شامل_حساب_رسمي'
                            : ' #ShamellOfficial';
                      }
                      try {
                        final sp = await SharedPreferences.getInstance();
                        await sp.setString('moments_preset_text', text);
                        final thumb = (item.thumbUrl ?? '').trim();
                        if (thumb.isNotEmpty) {
                          try {
                            final uri = Uri.tryParse(thumb);
                            if (uri != null) {
                              final resp = await http
                                  .get(uri, headers: await _hdr())
                                  .timeout(_officialRequestTimeout);
                              if (resp.statusCode >= 200 &&
                                  resp.statusCode < 300 &&
                                  resp.bodyBytes.isNotEmpty) {
                                final b64 = base64Encode(resp.bodyBytes);
                                await sp.setString('moments_preset_image', b64);
                              }
                            }
                          } catch (_) {}
                        }
                      } catch (_) {}
                      if (!mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MomentsPage(baseUrl: widget.baseUrl),
                        ),
                      );
                    },
                    icon: const Icon(Icons.camera_roll_outlined, size: 18),
                    label: Text(
                      l.isArabic ? 'مشاركة في اللحظات' : 'Share to Moments',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      Perf.action('official_share_to_moments');
                      final buf = StringBuffer();
                      if ((item.title ?? '').isNotEmpty) {
                        buf.writeln(item.title);
                      }
                      if ((item.snippet ?? '').isNotEmpty) {
                        buf.writeln(item.snippet);
                      }
                      buf.writeln();
                      buf.writeln(
                        l.isArabic ? 'من ${acc.name}' : 'From ${acc.name}',
                      );
                      buf.writeln(
                        'shamell://official/${acc.id}/${item.id}',
                      );
                      var text = buf.toString().trim();
                      if (text.isEmpty) return;
                      if (!text.contains('#')) {
                        text += l.isArabic
                            ? ' #شامل_حساب_رسمي'
                            : ' #ShamellOfficial';
                      }
                      try {
                        final sp = await SharedPreferences.getInstance();
                        await sp.setString('moments_preset_text', text);
                        final thumb = (item.thumbUrl ?? '').trim();
                        if (thumb.isNotEmpty) {
                          try {
                            final uri = Uri.tryParse(thumb);
                            if (uri != null) {
                              final resp = await http
                                  .get(uri, headers: await _hdr())
                                  .timeout(_officialRequestTimeout);
                              if (resp.statusCode >= 200 &&
                                  resp.statusCode < 300 &&
                                  resp.bodyBytes.isNotEmpty) {
                                final b64 = base64Encode(resp.bodyBytes);
                                await sp.setString('moments_preset_image', b64);
                              }
                            }
                          } catch (_) {}
                        }
                      } catch (_) {}
                      if (!mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MomentsPage(baseUrl: widget.baseUrl),
                        ),
                      );
                    },
                    icon: const Icon(Icons.camera_roll_outlined, size: 18),
                    label: Text(
                      l.isArabic ? 'مشاركة في اللحظات' : 'Share to Moments',
                    ),
                  ),
                  if (onOpenChat != null && chatId.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        Perf.action('official_open_chat_from_feed_item');
                        onOpenChat(chatId);
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(
                        l.isArabic ? 'دردشة' : 'Chat',
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () async {
                      Perf.action('official_save_item_favorite');
                      final buf = StringBuffer();
                      if ((item.title ?? '').isNotEmpty) {
                        buf.writeln(item.title);
                      }
                      if ((item.snippet ?? '').isNotEmpty) {
                        buf.writeln(item.snippet);
                      }
                      buf.writeln();
                      buf.writeln(
                        l.isArabic ? 'من ${acc.name}' : 'From ${acc.name}',
                      );
                      buf.writeln(
                        'shamell://official/${acc.id}/${item.id}',
                      );
                      final text = buf.toString().trim();
                      if (text.isEmpty) return;
                      await addFavoriteItemQuick(text);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l.isArabic
                                ? 'تم حفظ هذا العنصر في المفضلة.'
                                : 'Saved to favorites.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: Text(
                      l.isArabic ? 'حفظ في المفضلة' : 'Save to favorites',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Perf.action('official_share_item');
                      final buf = StringBuffer();
                      if ((item.title ?? '').isNotEmpty) {
                        buf.writeln(item.title);
                      }
                      if ((item.snippet ?? '').isNotEmpty) {
                        buf.writeln(item.snippet);
                      }
                      buf.writeln();
                      buf.writeln(
                        l.isArabic ? 'من ${acc.name}' : 'From ${acc.name}',
                      );
                      buf.writeln(
                        'shamell://official/${acc.id}/${item.id}',
                      );
                      final text = buf.toString().trim();
                      if (text.isEmpty) return;
                      await Share.share(text);
                    },
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(
                      l.isArabic ? 'مشاركة' : 'Share',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfficialAccountFeedPage extends StatefulWidget {
  final String baseUrl;
  final OfficialAccountHandle account;
  final void Function(String peerId)? onOpenChat;

  const OfficialAccountFeedPage({
    super.key,
    required this.baseUrl,
    required this.account,
    this.onOpenChat,
  });

  @override
  State<OfficialAccountFeedPage> createState() =>
      _OfficialAccountFeedPageState();
}

class _OfficialAccountFeedPageState extends State<OfficialAccountFeedPage>
    with SafeSetStateMixin<OfficialAccountFeedPage> {
  bool _loading = true;
  String _error = '';
  List<_OfficialFeedItem> _items = const [];
  bool _followed = true;
  List<_OfficialLocation> _locations = const [];
  bool _muted = false;
  bool _hasChatPeer = false;
  OfficialNotificationMode? _notifMode;
  bool _loadingRelated = false;
  List<OfficialAccountHandle> _relatedAccounts =
      const <OfficialAccountHandle>[];
  int _momentsSharesTotal = 0;
  int _momentsUniqueSharers30d = 0;
  double _momentsSharesPer1k = 0;
  int _momentsComments30d = 0;
  List<Map<String, dynamic>> _channelClips = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _latestMoments = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _followed = true;
    _load();
    _loadMuteState();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    final h = <String, String>{};
    if (jsonBody) h['content-type'] = 'application/json';
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) h['cookie'] = cookie;
    } catch (_) {}
    return h;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse(
              '${widget.baseUrl}/official_accounts/${widget.account.id}/feed')
          .replace(queryParameters: const {'limit': '20'});
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        final list = <_OfficialFeedItem>[];
        if (decoded is Map && decoded['items'] is List) {
          for (final e in decoded['items'] as List) {
            if (e is Map) {
              list.add(_OfficialFeedItem.fromJson(e.cast<String, dynamic>()));
            }
          }
        }
        List<_OfficialLocation> locs = const [];
        try {
          final locUri = Uri.parse(
                  '${widget.baseUrl}/official_accounts/${widget.account.id}/locations')
              .replace(queryParameters: const {'limit': '50'});
          final lr = await http
              .get(locUri, headers: await _hdr())
              .timeout(_officialRequestTimeout);
          if (lr.statusCode >= 200 && lr.statusCode < 300) {
            final ld = jsonDecode(lr.body);
            if (ld is Map && ld['locations'] is List) {
              final arr = ld['locations'] as List;
              locs = arr
                  .whereType<Map>()
                  .map((m) =>
                      _OfficialLocation.fromJson(m.cast<String, dynamic>()))
                  .toList();
            }
          }
        } catch (_) {}
        int sharesTotal = 0;
        int uniqSharers30 = 0;
        double sharesPer1k = 0;
        int comments30 = 0;
        try {
          final statsUri = Uri.parse(
              '${widget.baseUrl}/official_accounts/${widget.account.id}/moments_stats');
          final sr = await http
              .get(statsUri, headers: await _hdr())
              .timeout(_officialRequestTimeout);
          if (sr.statusCode >= 200 && sr.statusCode < 300) {
            final sd = jsonDecode(sr.body);
            if (sd is Map) {
              final t = sd['total_shares'];
              final u30 = sd['unique_sharers_30d'];
              final spk = sd['shares_per_1k_followers'];
              final c30 = sd['comments_30d'];
              if (t is num) sharesTotal = t.toInt();
              if (u30 is num) uniqSharers30 = u30.toInt();
              if (spk is num) sharesPer1k = spk.toDouble();
              if (c30 is num) comments30 = c30.toInt();
            }
          }
        } catch (_) {}
        setState(() {
          _items = list;
          _locations = locs;
          _momentsSharesTotal = sharesTotal;
          _momentsUniqueSharers30d = uniqSharers30;
          _momentsSharesPer1k = sharesPer1k;
          _momentsComments30d = comments30;
        });
        // Load Channels clips for this Official (Shamell‑style cross‑view).
        // ignore: discarded_futures
        _loadChannelClips();
        // Load latest Moments posts for this Official so we can show a
        // small "Moments from this account" strip.
        // ignore: discarded_futures
        _loadLatestMoments();
        // Mark latest feed item as seen for this account.
        if (list.isNotEmpty) {
          try {
            final latest = list.first;
            if (latest.ts != null) {
              final sp = await SharedPreferences.getInstance();
              final raw = sp.getString('official.feed_seen') ?? '{}';
              Map<String, dynamic> map;
              try {
                map = jsonDecode(raw) as Map<String, dynamic>;
              } catch (_) {
                map = <String, dynamic>{};
              }
              map[widget.account.id] = latest.ts!.toUtc().toIso8601String();
              await sp.setString('official.feed_seen', jsonEncode(map));
            }
          } catch (_) {}
        }
      } else {
        setState(() {
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } catch (e) {
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMuteState() async {
    final chatId = widget.account.chatPeerId ?? widget.account.id;
    if (chatId.isEmpty) return;
    try {
      final store = ChatLocalStore();
      final contacts = await store.loadContacts();
      ChatContact? found;
      for (final c in contacts) {
        if (c.id == chatId) {
          found = c;
          break;
        }
      }
      final mode = await store.loadOfficialNotifMode(chatId);
      if (!mounted) return;
      setState(() {
        _hasChatPeer = found != null;
        _notifMode = mode;
        _muted =
            (found?.muted ?? false) || mode == OfficialNotificationMode.muted;
      });
    } catch (_) {}
  }

  Future<void> _loadChannelClips() async {
    final accId = widget.account.id.trim();
    if (accId.isEmpty) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/channels/feed').replace(
        queryParameters: <String, String>{
          'limit': '10',
          'official_account_id': accId,
        },
      );
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['items'] is List) {
        raw = decoded['items'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final clips = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final acc = (m['official_account_id'] ?? '').toString().trim();
        if (acc.isNotEmpty && acc != accId) continue;
        clips.add(m);
      }
      if (!mounted || clips.isEmpty) return;
      setState(() {
        _channelClips = clips;
      });
    } catch (_) {
      // best-effort only
    }
  }

  Future<void> _loadLatestMoments() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/feed').replace(
        queryParameters: <String, String>{
          'limit': '10',
          'official_account_id': widget.account.id,
        },
      );
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['items'] is List) {
        raw = decoded['items'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final items = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) {
          items.add(e.cast<String, dynamic>());
        }
      }
      if (!mounted) return;
      setState(() {
        _latestMoments = items;
      });
    } catch (_) {
      // best-effort only
    }
  }

  Future<void> _setNotificationMode(OfficialNotificationMode mode) async {
    final chatId = widget.account.chatPeerId ?? widget.account.id;
    if (chatId.isEmpty) return;
    try {
      final store = ChatLocalStore();
      final contacts = await store.loadContacts();
      ChatContact? updatedContact;
      final updated = <ChatContact>[];
      for (final c in contacts) {
        if (c.id == chatId) {
          final u = c.copyWith(muted: mode == OfficialNotificationMode.muted);
          updatedContact = u;
          updated.add(u);
        } else {
          updated.add(c);
        }
      }
      if (updatedContact != null) {
        await store.saveContacts(updated);
      }
      await store.setOfficialNotifMode(chatId, mode);
      // Sync per-account mode to server (best-effort).
      try {
        final uri = Uri.parse(
            '${widget.baseUrl}/official_accounts/${widget.account.id}/notification_mode');
        final body = jsonEncode({
          'mode': switch (mode) {
            OfficialNotificationMode.full => 'full',
            OfficialNotificationMode.summary => 'summary',
            OfficialNotificationMode.muted => 'muted',
          }
        });
        await http
            .post(uri, headers: await _hdr(jsonBody: true), body: body)
            .timeout(_officialRequestTimeout);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _hasChatPeer = updatedContact != null;
        _notifMode = mode;
        _muted = mode == OfficialNotificationMode.muted;
      });
    } catch (_) {}
  }

  Future<void> _showNotificationSheet() async {
    if (!_hasChatPeer) return;
    final l = L10n.of(context);
    final current = _notifMode ??
        (_muted
            ? OfficialNotificationMode.muted
            : OfficialNotificationMode.full);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: RadioGroup<OfficialNotificationMode>(
              groupValue: current,
              onChanged: (mode) async {
                if (mode == null) return;
                Navigator.of(ctx).pop();
                await _setNotificationMode(mode);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.full,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic
                          ? 'إظهار معاينة الرسائل'
                          : 'Show message preview',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عرض محتوى الرسائل في الإشعارات لهذا الحساب'
                          : 'Show message content in notifications for this account',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.summary,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic
                          ? 'إخفاء محتوى الرسائل'
                          : 'Hide message content',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'إظهار إشعار مختصر فقط عند وصول رسالة جديدة'
                          : 'Show a brief alert without message text',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                  RadioListTile<OfficialNotificationMode>(
                    value: OfficialNotificationMode.muted,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      l.isArabic ? 'كتم الإشعارات' : 'Mute notifications',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عدم إظهار إشعارات لهذه الدردشة'
                          : 'Turn off local notifications for this chat',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDeeplink(_OfficialFeedItem item) async {
    final dl = item.deeplinkMiniAppId;
    if (dl != null && dl.isNotEmpty) {
      await _openMiniAppById(dl, payload: item.deeplinkPayload);
      return;
    }
    if (!mounted) return;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final acc = widget.account;
    final chatPeerId = (acc.chatPeerId ?? acc.id).trim();
    final onOpenChat = widget.onOpenChat;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DomainPageScaffold(
          background: const AppBG(),
          title: (item.title ?? '').isNotEmpty ? item.title! : acc.name,
          scrollable: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((item.thumbUrl ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        item.thumbUrl!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                if (_momentsSharesTotal >= 10)
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department_outlined,
                            size: 12,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            l.isArabic ? 'رائج في اللحظات' : 'Hot in Moments',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (item.tsLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      item.tsLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .60),
                      ),
                    ),
                  ),
                if ((item.snippet ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      item.snippet!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  l.isArabic ? 'من' : 'From',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if ((acc.avatarUrl ?? '').isNotEmpty)
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: NetworkImage(acc.avatarUrl!),
                      ),
                    if ((acc.avatarUrl ?? '').isNotEmpty)
                      const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        acc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MomentsPage(
                                baseUrl: widget.baseUrl,
                                originOfficialAccountId: widget.account.id,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: Text(
                          l.isArabic ? 'منشورات في اللحظات' : 'Moments posts',
                        ),
                      ),
                      if (onOpenChat != null && chatPeerId.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            onOpenChat(chatPeerId);
                          },
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          label: Text(
                            l.isArabic ? 'دردشة' : 'Chat',
                          ),
                        ),
                      TextButton.icon(
                        onPressed: () async {
                          final buf = StringBuffer();
                          if ((item.title ?? '').isNotEmpty) {
                            buf.writeln(item.title);
                          }
                          if ((item.snippet ?? '').isNotEmpty) {
                            buf.writeln(item.snippet);
                          }
                          buf.writeln();
                          buf.writeln(
                            l.isArabic ? 'من ${acc.name}' : 'From ${acc.name}',
                          );
                          buf.writeln(
                            'shamell://official/${acc.id}/${item.id}',
                          );
                          final text = buf.toString().trim();
                          if (text.isEmpty) return;
                          await addFavoriteItemQuick(text);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                l.isArabic
                                    ? 'تم حفظ هذا العنصر في المفضلة.'
                                    : 'Saved to favorites.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: Text(
                          l.isArabic ? 'حفظ في المفضلة' : 'Save to favorites',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final buf = StringBuffer();
                          if ((item.title ?? '').isNotEmpty) {
                            buf.writeln(item.title);
                          }
                          if ((item.snippet ?? '').isNotEmpty) {
                            buf.writeln(item.snippet);
                          }
                          buf.writeln();
                          buf.writeln(
                            l.isArabic ? 'من ${acc.name}' : 'From ${acc.name}',
                          );
                          buf.writeln(
                            'shamell://official/${acc.id}/${item.id}',
                          );
                          final text = buf.toString().trim();
                          if (text.isEmpty) return;
                          await Share.share(text);
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: Text(
                          l.isArabic ? 'مشاركة' : 'Share',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMiniAppById(String dl,
      {Map<String, dynamic>? payload}) async {
    if (dl == 'payments' || dl == 'alias' || dl == 'merchant') {
      try {
        final sp = await SharedPreferences.getInstance();
        final walletId = sp.getString('wallet_id') ?? '';
        final devId = await CallSignalingClient.loadDeviceId();
        String? initialSection;
        final p = payload;
        if (p != null) {
          final rawSection = p['section'];
          if (rawSection is String && rawSection.trim().isNotEmpty) {
            initialSection = rawSection.trim();
          }
        }
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentsPage(
              widget.baseUrl,
              walletId,
              devId ?? 'device',
              initialSection: initialSection,
            ),
          ),
        );
      } catch (_) {}
      return;
    }
    final app = miniAppById(dl);
    if (app == null) return;
    // For now, just show a snack; deep integration with home shell would map to _openMod.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Open mini‑app: ${app.title(isArabic: L10n.of(context).isArabic)}',
        ),
      ),
    );
  }

  Future<void> _loadRelatedAccounts() async {
    final acc = widget.account;
    final cat = (acc.category ?? '').trim().toLowerCase();
    if (cat.isEmpty) return;
    setState(() {
      _loadingRelated = true;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/official_accounts')
          .replace(queryParameters: const {'followed_only': 'false'});
      final r = await http
          .get(uri, headers: await _hdr())
          .timeout(_officialRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['accounts'] is List) {
        raw = decoded['accounts'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final sameCity = <OfficialAccountHandle>[];
      final otherCity = <OfficialAccountHandle>[];
      final accCity = (acc.city ?? '').trim().toLowerCase();
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final handle = OfficialAccountHandle.fromJson(m);
        if (handle.id == acc.id) continue;
        final hCat = (handle.category ?? '').trim().toLowerCase();
        if (hCat == cat) {
          final hCity = (handle.city ?? '').trim().toLowerCase();
          if (accCity.isNotEmpty && hCity.isNotEmpty && hCity == accCity) {
            sameCity.add(handle);
          } else {
            otherCity.add(handle);
          }
        }
      }
      final related = <OfficialAccountHandle>[];
      related.addAll(sameCity);
      for (final h in otherCity) {
        if (related.length >= 4) break;
        related.add(h);
      }
      if (!mounted) return;
      setState(() {
        _relatedAccounts = related;
      });
    } catch (_) {
      // ignore; footer is optional
    } finally {
      if (mounted) {
        setState(() {
          _loadingRelated = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final acc = widget.account;
    final items = _items;
    final articleItems =
        items.where((e) => e.type.toLowerCase() == 'article').toList();
    final promoItems =
        items.where((e) => e.type.toLowerCase() != 'article').toList();
    final hasFooter = (acc.miniAppId != null && acc.miniAppId!.isNotEmpty) ||
        _relatedAccounts.isNotEmpty;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundImage: acc.avatarUrl != null
                          ? NetworkImage(acc.avatarUrl!)
                          : null,
                      child: acc.avatarUrl == null
                          ? Text(
                              acc.name.isNotEmpty
                                  ? acc.name.characters.first.toUpperCase()
                                  : '?',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            acc.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (acc.category != null && acc.category!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                acc.category!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.campaign_outlined,
                                    size: 12, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  (acc.kind.toLowerCase() == 'service')
                                      ? (l.isArabic
                                          ? 'حساب خدمة'
                                          : 'Service account')
                                      : (l.isArabic
                                          ? 'حساب اشتراك'
                                          : 'Subscription account'),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (acc.featured) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.star_rounded,
                                    size: 12,
                                    color: theme.colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    l.isArabic ? 'مميز' : 'Featured',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (acc.city != null && acc.city!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 14),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      acc.city!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (acc.openingHours != null &&
                              acc.openingHours!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.access_time, size: 14),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      acc.openingHours!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (acc.description != null &&
                              acc.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                acc.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .70),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _toggleFollow,
                      child: Text(_followed
                          ? (l.isArabic ? 'إلغاء المتابعة' : 'Unfollow')
                          : (l.isArabic ? 'متابعة' : 'Follow')),
                    ),
                    if (widget.onOpenChat != null)
                      TextButton(
                        onPressed: () {
                          final id =
                              widget.account.chatPeerId?.trim().isNotEmpty ==
                                      true
                                  ? widget.account.chatPeerId!.trim()
                                  : widget.account.id.trim();
                          if (id.isEmpty) return;
                          widget.onOpenChat?.call(id);
                        },
                        child: Text(
                          l.isArabic ? 'دردشة' : 'Chat',
                        ),
                      ),
                    if (_hasChatPeer)
                      IconButton(
                        tooltip: l.isArabic
                            ? 'إعدادات الإشعارات'
                            : 'Notification settings',
                        icon: Icon(
                          _notifMode == OfficialNotificationMode.muted || _muted
                              ? Icons.notifications_off_outlined
                              : (_notifMode == OfficialNotificationMode.summary
                                  ? Icons.notifications_none_outlined
                                  : Icons.notifications_active_outlined),
                        ),
                        onPressed: _showNotificationSheet,
                      ),
                    IconButton(
                      tooltip: l.isArabic ? 'مشاركة الحساب' : 'Share account',
                      icon: const Icon(Icons.share),
                      onPressed: () async {
                        final buf = StringBuffer();
                        buf.writeln(acc.name);
                        if (acc.description != null &&
                            acc.description!.isNotEmpty) {
                          buf.writeln(acc.description);
                        }
                        String? link;
                        if (acc.websiteUrl != null &&
                            acc.websiteUrl!.isNotEmpty) {
                          link = acc.websiteUrl;
                        } else if (acc.qrPayload != null &&
                            acc.qrPayload!.isNotEmpty) {
                          link = acc.qrPayload;
                        } else {
                          link = 'shamell://official/${acc.id}';
                        }
                        buf.writeln(link);
                        final text = buf.toString().trim();
                        if (text.isEmpty) return;
                        await Share.share(text);
                      },
                    ),
                    if (acc.websiteUrl != null && acc.websiteUrl!.isNotEmpty)
                      IconButton(
                        tooltip: l.isArabic ? 'موقع الويب' : 'Website',
                        icon: const Icon(Icons.link),
                        onPressed: () async {
                          final url = Uri.tryParse(acc.websiteUrl!);
                          if (url == null) return;
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    if (acc.qrPayload != null && acc.qrPayload!.isNotEmpty)
                      IconButton(
                        tooltip: l.isArabic ? 'رمز QR' : 'QR code',
                        icon: const Icon(Icons.qr_code_2),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) {
                              return AlertDialog(
                                title: Text(
                                  l.isArabic
                                      ? 'رمز QR للحساب'
                                      : 'Account QR code',
                                ),
                                content: SizedBox(
                                  width: 220,
                                  height: 220,
                                  child: Center(
                                    child: QrImageView(
                                      data: (acc.qrPayload != null &&
                                              acc.qrPayload!.isNotEmpty)
                                          ? acc.qrPayload!
                                          : 'shamell://official/${acc.id}',
                                      size: 200,
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildServiceMenu(context, acc, widget.baseUrl),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MomentsPage(
                            baseUrl: widget.baseUrl,
                            originOfficialAccountId: widget.account.id,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      size: 18,
                    ),
                    label: Text(
                      l.isArabic ? 'منشورات في اللحظات' : 'Moments posts',
                    ),
                  ),
                ),
              ),
              if (_momentsSharesTotal > 0)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.insights_outlined,
                        size: 18,
                        color: theme.colorScheme.primary.withValues(alpha: .85),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          () {
                            final total = _momentsSharesTotal;
                            final u30 = _momentsUniqueSharers30d;
                            final spk = _momentsSharesPer1k;
                            final c30 = _momentsComments30d;
                            if (l.isArabic) {
                              var base =
                                  'الأثر الاجتماعي في اللحظات: تمت مشاركة هذا الحساب $total مرة';
                              final parts = <String>[];
                              if (c30 > 0) {
                                parts.add(
                                    '$c30 تعليقات على منشورات اللحظات في آخر ٣٠ يوماً');
                              }
                              if (u30 > 0 || spk > 0) {
                                final parts = <String>[];
                                if (u30 > 0) {
                                  parts.add(
                                      '$u30 مستخدمين مميزين في آخر ٣٠ يوماً');
                                }
                                if (spk > 0) {
                                  parts.add(
                                      '${spk.toStringAsFixed(1)} مشاركات لكل ١٬٠٠٠ متابع');
                                }
                                base = '$base\n${parts.join(' · ')}';
                              }
                              if (parts.isNotEmpty) {
                                base = '$base · ${parts.join(' · ')}';
                              }
                              return base;
                            } else {
                              var base =
                                  'Social impact in Moments: shared $total times';
                              final parts = <String>[];
                              if (c30 > 0) {
                                parts.add(
                                    '$c30 comments on Moments posts in last 30 days');
                              }
                              if (u30 > 0 || spk > 0) {
                                if (u30 > 0) {
                                  parts.add(
                                      '$u30 unique sharers in last 30 days');
                                }
                                if (spk > 0) {
                                  parts.add(
                                      '${spk.toStringAsFixed(1)} shares per 1k followers');
                                }
                                base = '$base\n${parts.join(' · ')}';
                              }
                              if (parts.isNotEmpty) {
                                base = '$base · ${parts.join(' · ')}';
                              }
                              return base;
                            }
                          }(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .80),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                            width: 28, height: 28),
                        icon: Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .65),
                        ),
                        onPressed: () {
                          final isAr = l.isArabic;
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
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isAr
                                              ? 'الأثر الاجتماعي في اللحظات'
                                              : 'Social impact in Moments',
                                          style: t.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          isAr
                                              ? 'يعتمد هذا المؤشر على عدد مرات مشاركة الحساب في اللحظات، وعدد المستخدمين المختلفين الذين قاموا بالمشاركة، والتعليقات.'
                                              : 'This indicator is based on how often this account is shared in Moments, how many different users share it, and comments.',
                                          style:
                                              t.textTheme.bodySmall?.copyWith(
                                            color: t.colorScheme.onSurface
                                                .withValues(alpha: .80),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              if (_latestMoments.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic
                            ? 'منشورات حديثة في اللحظات لهذا الحساب'
                            : 'Recent Moments from this account',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .85),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._latestMoments.take(3).map((p) {
                        final pid = (p['id'] ?? '').toString();
                        final text = (p['text'] ?? '').toString();
                        final likes = (p['likes'] is num)
                            ? (p['likes'] as num).toInt()
                            : 0;
                        final comments = (p['comments'] is num)
                            ? (p['comments'] as num).toInt()
                            : 0;
                        final ts = (p['ts'] ?? '').toString();
                        final meta = <String>[];
                        if (likes > 0) {
                          meta.add(
                            l.isArabic ? 'إعجابات: $likes' : 'Likes: $likes',
                          );
                        }
                        if (comments > 0) {
                          meta.add(
                            l.isArabic
                                ? 'تعليقات: $comments'
                                : 'Comments: $comments',
                          );
                        }
                        if (ts.isNotEmpty) {
                          meta.add(ts);
                        }
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(
                            Icons.photo_library_outlined,
                            size: 20,
                          ),
                          title: Text(
                            text.isNotEmpty
                                ? text
                                : (l.isArabic ? 'منشور لحظات' : 'Moments post'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          subtitle: meta.isEmpty
                              ? null
                              : Text(
                                  meta.join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .70),
                                  ),
                                ),
                          onTap: () {
                            if (pid.isEmpty) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MomentsPage(
                                  baseUrl: widget.baseUrl,
                                  initialPostId: pid,
                                  focusComments: false,
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ],
                  ),
                ),
              if (_locations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic ? 'الفروع' : 'Locations',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      ..._locations.take(3).map((loc) {
                        final subtitle = [
                          loc.address,
                          loc.city,
                        ].where((e) => e != null && e!.isNotEmpty).join(' · ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 20),
                          title: Text(
                            loc.name?.isNotEmpty == true
                                ? loc.name!
                                : (l.isArabic ? 'فرع' : 'Branch'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 13),
                          ),
                          subtitle: subtitle.isNotEmpty
                              ? Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: loc.phone != null &&
                                  loc.phone!.trim().isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.phone, size: 18),
                                  onPressed: () async {
                                    final uri =
                                        Uri.parse('tel:${loc.phone!.trim()}');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  },
                                )
                              : null,
                          onTap: () async {
                            final lat = loc.lat;
                            final lon = loc.lon;
                            Uri? uri;
                            if (lat != null && lon != null) {
                              uri = Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=$lat,$lon');
                            } else if (loc.address != null &&
                                loc.address!.isNotEmpty) {
                              final q =
                                  Uri.encodeComponent(loc.address!.trim());
                              uri = Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=$q');
                            }
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                        );
                      }).toList(),
                    ],
                  ),
                ),
              if (_channelClips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                l.isArabic
                                    ? 'مقاطع من القنوات'
                                    : 'Channels clips',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Builder(
                                builder: (ctx) {
                                  final hasLive = _channelClips.any((c) {
                                    final t =
                                        (c['item_type'] ?? c['type'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                    return t == 'live';
                                  });
                                  if (!hasLive) {
                                    return const SizedBox.shrink();
                                  }
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.error
                                          .withValues(alpha: .10),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.live_tv_outlined,
                                          size: 12,
                                          color: theme.colorScheme.error
                                              .withValues(alpha: .90),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          l.isArabic
                                              ? 'بث مباشر الآن'
                                              : 'Live now',
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChannelsPage(
                                    baseUrl: widget.baseUrl,
                                    officialAccountId: acc.id,
                                    officialName: acc.name,
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              l.isArabic ? 'عرض الكل' : 'View all',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (ctx) {
                          var clips = _channelClips.length;
                          var totalViews = 0;
                          var totalLikes = 0;
                          var totalComments = 0;
                          var hotCount = 0;
                          for (final c in _channelClips) {
                            final v = c['views'];
                            final lcount = c['likes'];
                            final ccount = c['comments'];
                            final isHot =
                                (c['official_is_hot'] as bool?) ?? false;
                            if (v is num) totalViews += v.toInt();
                            if (lcount is num) totalLikes += lcount.toInt();
                            if (ccount is num) totalComments += ccount.toInt();
                            if (isHot) hotCount = 1;
                          }
                          if (clips == 0) return const SizedBox.shrink();
                          final text = l.isArabic
                              ? 'المقاطع: $clips · المشاهدات: $totalViews · الإعجابات: $totalLikes · التعليقات: $totalComments'
                              : 'Clips: $clips · Views: $totalViews · Likes: $totalLikes · Comments: $totalComments';
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  text,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .70),
                                  ),
                                ),
                              ),
                              if (hotCount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: .08),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.local_fire_department_outlined,
                                          size: 12,
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: .85),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          l.isArabic
                                              ? 'رائجة في اللحظات'
                                              : 'Hot in Moments',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _channelClips.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (ctx, i) {
                            final clip = _channelClips[i];
                            final title =
                                (clip['title'] ?? '').toString().trim();
                            final snippet =
                                (clip['snippet'] ?? '').toString().trim();
                            final thumb =
                                (clip['thumb_url'] ?? '').toString().trim();
                            final likesRaw = clip['likes'];
                            final likes =
                                likesRaw is num ? likesRaw.toInt() : 0;
                            final viewsRaw = clip['views'];
                            final views =
                                viewsRaw is num ? viewsRaw.toInt() : 0;
                            return InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChannelsPage(
                                      baseUrl: widget.baseUrl,
                                      officialAccountId: acc.id,
                                      officialName: acc.name,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 200,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: theme.dividerColor
                                        .withValues(alpha: .40),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    if (thumb.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(10),
                                          bottomLeft: Radius.circular(10),
                                        ),
                                        child: Image.network(
                                          thumb,
                                          width: 72,
                                          height: 120,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 72,
                                        height: 120,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: .06),
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(10),
                                            bottomLeft: Radius.circular(10),
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.live_tv_outlined,
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: .75),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (title.isNotEmpty)
                                              Text(
                                                title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            if (snippet.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2.0),
                                                child: Text(
                                                  snippet,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    fontSize: 11,
                                                    color: theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: .70),
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.favorite_border,
                                                  size: 14,
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withValues(alpha: .65),
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '$likes',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: .70),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.remove_red_eye_outlined,
                                                  size: 14,
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withValues(alpha: .65),
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '$views',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: .70),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
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
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              if (items.isEmpty && _error.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l.isArabic ? 'لا توجد تحديثات بعد.' : 'No updates yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                )
              else
                Expanded(
                  child: DefaultTabController(
                    length: articleItems.isNotEmpty ? 2 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (articleItems.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: TabBar(
                              labelStyle: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              labelColor: theme.colorScheme.primary,
                              unselectedLabelColor: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                              tabs: [
                                Tab(
                                  text: l.isArabic ? 'المنشورات' : 'Feed',
                                ),
                                Tab(
                                  text: l.isArabic ? 'المقالات' : 'Articles',
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: TabBarView(
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              ListView.separated(
                                itemCount:
                                    promoItems.length + (hasFooter ? 1 : 0),
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  if (hasFooter && i == promoItems.length) {
                                    if (!_loadingRelated &&
                                        _relatedAccounts.isEmpty &&
                                        (acc.category?.isNotEmpty == true)) {
                                      // Fire and forget; footer will update when data arrives.
                                      // ignore: unawaited_futures
                                      _loadRelatedAccounts();
                                    }
                                    return _buildFeedFooter(context, theme, l,
                                        acc, _relatedAccounts);
                                  }
                                  final it = promoItems[i];
                                  final hasThumb = it.thumbUrl != null &&
                                      it.thumbUrl!.isNotEmpty;
                                  final hasMiniApp =
                                      it.deeplinkMiniAppId != null &&
                                          it.deeplinkMiniAppId!.isNotEmpty;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => _openDeeplink(it),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surface,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: theme.dividerColor
                                                .withValues(alpha: .40),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (hasThumb)
                                              ClipRRect(
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                  top: Radius.circular(12),
                                                ),
                                                child: AspectRatio(
                                                  aspectRatio: 16 / 9,
                                                  child: Image.network(
                                                    it.thumbUrl!,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              )
                                            else
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 12,
                                                    right: 12,
                                                    top: 12),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.campaign_outlined,
                                                      color: theme
                                                          .colorScheme.primary,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      l.isArabic
                                                          ? 'تحديث من الحساب'
                                                          : 'Update from this account',
                                                      style: theme
                                                          .textTheme.bodySmall,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if ((it.title ?? '')
                                                      .isNotEmpty)
                                                    Text(
                                                      it.title!,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  if (it.snippet != null &&
                                                      it.snippet!.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 4),
                                                      child: Text(
                                                        it.snippet!,
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme.bodySmall
                                                            ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                  alpha: .75),
                                                        ),
                                                      ),
                                                    ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        it.tsLabel,
                                                        style: theme
                                                            .textTheme.bodySmall
                                                            ?.copyWith(
                                                          fontSize: 11,
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                  alpha: .60),
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      if (hasMiniApp)
                                                        OutlinedButton.icon(
                                                          onPressed: () =>
                                                              _openDeeplink(it),
                                                          icon: const Icon(
                                                            Icons.open_in_new,
                                                            size: 16,
                                                          ),
                                                          label: Text(
                                                            l.isArabic
                                                                ? 'افتح الميني‑تطبيق'
                                                                : 'Open mini‑app',
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          style: OutlinedButton
                                                              .styleFrom(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 10,
                                                              vertical: 6,
                                                            ),
                                                            foregroundColor:
                                                                theme
                                                                    .colorScheme
                                                                    .primary,
                                                          ),
                                                        )
                                                      else
                                                        TextButton(
                                                          onPressed: () =>
                                                              _openDeeplink(it),
                                                          child: Text(
                                                            l.isArabic
                                                                ? 'عرض التفاصيل'
                                                                : 'View details',
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (articleItems.isNotEmpty)
                                ListView.separated(
                                  itemCount: articleItems.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final it = articleItems[i];
                                    final hasThumb = it.thumbUrl != null &&
                                        it.thumbUrl!.isNotEmpty;
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 4, 12, 8),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _openDeeplink(it),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surface,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: theme.dividerColor
                                                  .withValues(alpha: .40),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (hasThumb)
                                                ClipRRect(
                                                  borderRadius:
                                                      const BorderRadius
                                                          .vertical(
                                                    top: Radius.circular(12),
                                                  ),
                                                  child: AspectRatio(
                                                    aspectRatio: 16 / 9,
                                                    child: Image.network(
                                                      it.thumbUrl!,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if ((it.title ?? '')
                                                        .isNotEmpty)
                                                      Text(
                                                        it.title!,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                    if (it.snippet != null &&
                                                        it.snippet!.isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 4),
                                                        child: Text(
                                                          it.snippet!,
                                                          maxLines: 4,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: theme.textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurface
                                                                .withValues(
                                                                    alpha: .75),
                                                          ),
                                                        ),
                                                      ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      it.tsLabel,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        fontSize: 11,
                                                        color: theme.colorScheme
                                                            .onSurface
                                                            .withValues(
                                                                alpha: .60),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              else
                                const SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(widget.account.name),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: body,
    );
  }

  Future<void> _toggleFollow() async {
    final id = widget.account.id;
    if (id.isEmpty) return;
    final currentlyFollowed = _followed;
    final endpoint = currentlyFollowed ? 'unfollow' : 'follow';
    final kindStr = widget.account.kind.toLowerCase();
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/official_accounts/$id/$endpoint');
      final r = await http
          .post(uri, headers: await _hdr(jsonBody: true))
          .timeout(_officialRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        if (!mounted) return;
        setState(() {
          _followed = !currentlyFollowed;
        });
        Perf.action(
            currentlyFollowed ? 'official_unfollow' : 'official_follow');
        final suffix = kindStr == 'service' ? 'service' : 'subscription';
        Perf.action(currentlyFollowed
            ? 'official_unfollow_kind_$suffix'
            : 'official_follow_kind_$suffix');
      }
    } catch (_) {}
  }

  Widget _buildFeedFooter(
    BuildContext context,
    ThemeData theme,
    L10n l,
    OfficialAccountHandle acc,
    List<OfficialAccountHandle> related,
  ) {
    final hasMiniApp = acc.miniAppId != null && acc.miniAppId!.isNotEmpty;
    final showRelated = related.isNotEmpty;
    if (!hasMiniApp && !showRelated) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasMiniApp) ...[
            Text(
              l.isArabic ? 'المزيد من هذا الحساب' : 'More from this account',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final id = acc.miniAppId!;
                  // ignore: discarded_futures
                  _openMiniAppById(id);
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(
                  l.isArabic ? 'افتح الميني‑تطبيق' : 'Open mini‑app',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
          if (showRelated) ...[
            if (hasMiniApp) const SizedBox(height: 12),
            Builder(builder: (ctx) {
              final catLabel = (acc.category ?? '').trim();
              final cityLabel = (acc.city ?? '').trim();
              String title;
              if (catLabel.isNotEmpty && cityLabel.isNotEmpty) {
                title = l.isArabic
                    ? '$catLabel في $cityLabel'
                    : '$catLabel in $cityLabel';
              } else if (catLabel.isNotEmpty) {
                title = catLabel;
              } else if (cityLabel.isNotEmpty) {
                title = l.isArabic
                    ? 'خدمات رسمية في $cityLabel'
                    : 'Official services in $cityLabel';
              } else {
                title = l.isArabic
                    ? 'حسابات رسمية مشابهة'
                    : 'Similar official accounts';
              }
              return Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: .80),
                ),
              );
            }),
            const SizedBox(height: 6),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: related.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final ra = related[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OfficialAccountFeedPage(
                            baseUrl: widget.baseUrl,
                            account: ra,
                            onOpenChat: widget.onOpenChat,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 180,
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
                            backgroundImage:
                                ra.avatarUrl != null && ra.avatarUrl!.isNotEmpty
                                    ? NetworkImage(ra.avatarUrl!)
                                    : null,
                            child: ra.avatarUrl == null
                                ? Text(
                                    ra.name.isNotEmpty
                                        ? ra.name.characters.first.toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ra.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  ra.category?.isNotEmpty == true
                                      ? (() {
                                          final catLabel =
                                              (ra.category ?? '').trim();
                                          final cityLabel =
                                              (ra.city ?? '').trim();
                                          if (catLabel.isNotEmpty &&
                                              cityLabel.isNotEmpty) {
                                            return '$catLabel · $cityLabel';
                                          }
                                          if (catLabel.isNotEmpty) {
                                            return catLabel;
                                          }
                                          if (cityLabel.isNotEmpty) {
                                            return cityLabel;
                                          }
                                          return l.isArabic
                                              ? 'حساب خدمة رسمي'
                                              : 'Official service account';
                                        })()
                                      : (ra.city?.isNotEmpty == true
                                          ? ra.city!
                                          : (l.isArabic
                                              ? 'حساب خدمة رسمي'
                                              : 'Official service account')),
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
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  _ServiceAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

Widget _buildServiceMenu(
    BuildContext context, OfficialAccountHandle acc, String baseUrl) {
  final l = L10n.of(context);
  final theme = Theme.of(context);
  final actions = <_ServiceAction>[];
  final id = acc.miniAppId ?? '';

  void openMod(String next) {
    final mid = next.trim().toLowerCase();
    if (mid.isEmpty) return;
    if (mid == 'payments' || mid == 'alias' || mid == 'merchant') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentsPage(
            baseUrl,
            '',
            'official',
            contextLabel: acc.name,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MiniProgramPage(
          id: mid,
          baseUrl: baseUrl,
          walletId: '',
          deviceId: 'official',
          onOpenMod: openMod,
        ),
      ),
    );
  }

  void addPayments() {
    actions.add(_ServiceAction(
      icon: Icons.account_balance_wallet_outlined,
      label: l.isArabic ? 'فتح المحفظة' : 'Open wallet',
      onTap: () async {
        try {
          final sp = await SharedPreferences.getInstance();
          final walletId = sp.getString('wallet_id') ?? '';
          final devId = await CallSignalingClient.loadDeviceId();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentsPage(
                baseUrl,
                walletId,
                devId ?? 'device',
                contextLabel: acc.name,
              ),
            ),
          );
        } catch (_) {}
      },
    ));
  }

  void addBus() {
    actions.add(_ServiceAction(
      icon: Icons.directions_bus_filled_outlined,
      label: l.isArabic ? 'فتح الباص' : 'Open bus',
      onTap: () => openMod('bus'),
    ));
  }

  // Prefer server-driven menu_items when present.
  if (acc.menuItems.isNotEmpty) {
    for (final item in acc.menuItems) {
      if (item.kind == 'mini_app') {
        final mid = (item.miniAppId ?? '').trim();
        if (mid.isEmpty) continue;
        IconData icon;
        String fallbackLabel;
        VoidCallback onTap;
        switch (mid) {
          case 'payments':
          case 'alias':
          case 'merchant':
            icon = Icons.account_balance_wallet_outlined;
            fallbackLabel = l.isArabic ? 'فتح المحفظة' : 'Open wallet';
            onTap = () async {
              try {
                final sp = await SharedPreferences.getInstance();
                final walletId = sp.getString('wallet_id') ?? '';
                final devId = await CallSignalingClient.loadDeviceId();
                // ignore: use_build_context_synchronously
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaymentsPage(
                      baseUrl,
                      walletId,
                      devId ?? 'device',
                      contextLabel: acc.name,
                    ),
                  ),
                );
              } catch (_) {}
            };
            break;
          case 'bus':
            icon = Icons.directions_bus_filled_outlined;
            fallbackLabel = l.isArabic ? 'فتح الباص' : 'Open bus';
            onTap = () => openMod(mid);
            break;
          default:
            icon = Icons.open_in_new;
            fallbackLabel = l.isArabic ? 'فتح الخدمة' : 'Open service';
            onTap = () => openMod(mid);
            break;
        }
        final label = item.label(l, fallbackLabel);
        actions.add(
          _ServiceAction(
            icon: icon,
            label: label,
            onTap: onTap,
          ),
        );
      } else if (item.kind == 'url' && item.url != null) {
        final u = item.url!;
        final uri = Uri.tryParse(u);
        if (uri == null) continue;
        final label = item.label(
          l,
          l.isArabic ? 'فتح الرابط' : 'Open link',
        );
        actions.add(
          _ServiceAction(
            icon: Icons.link,
            label: label,
            onTap: () async {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        );
      }
    }
  }

  // Fallback for older BFFs without menu_items.
  if (actions.isEmpty) {
    switch (id) {
      case 'payments':
      case 'alias':
      case 'merchant':
        addPayments();
        break;
      case 'bus':
        addBus();
        break;
      default:
        break;
    }
  }

  if (actions.isEmpty) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.isArabic ? 'التطبيقات المصغرة للخدمة' : 'Service mini‑programs',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: .80),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: actions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final a = actions[i];
              return OutlinedButton.icon(
                onPressed: a.onTap,
                icon: Icon(a.icon, size: 18),
                label: Text(
                  a.label,
                  style: const TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  foregroundColor: theme.colorScheme.primary,
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _OfficialAccount {
  final String id;
  final String kind;
  final String name;
  final String? description;
  final String? avatarUrl;
  final bool verified;
  final bool featured;
  final List<String> badges;
  final int unreadCount;
  final String? lastItemTitle;
  final String? lastItemTs;
  final String? chatPeerId;
  final String? miniAppId;
  final String? category;
  final String? city;
  final String? address;
  final String? openingHours;
  final String? websiteUrl;
  final String? qrPayload;
  final bool followed;
  final List<_OfficialMenuItem> menuItems;
  final OfficialNotificationMode? notifMode;

  _OfficialAccount({
    required this.id,
    required this.kind,
    required this.name,
    this.description,
    this.avatarUrl,
    this.verified = false,
    this.featured = false,
    this.badges = const <String>[],
    this.unreadCount = 0,
    this.lastItemTitle,
    this.lastItemTs,
    this.chatPeerId,
    this.miniAppId,
    this.category,
    this.city,
    this.address,
    this.openingHours,
    this.websiteUrl,
    this.qrPayload,
    this.followed = false,
    this.menuItems = const <_OfficialMenuItem>[],
    this.notifMode,
  });

  factory _OfficialAccount.fromJson(Map<String, dynamic> j) {
    final rawChatId = (j['chat_peer_id'] ?? '').toString().trim();
    String? lastTs;
    if (j['last_item'] is Map) {
      final m = j['last_item'] as Map;
      final raw = (m['ts'] ?? '').toString();
      lastTs = raw.isEmpty ? null : raw;
    }
    List<_OfficialMenuItem> menuItems = const <_OfficialMenuItem>[];
    if (j['menu_items'] is List) {
      final rawMenu = j['menu_items'] as List;
      final parsed = <_OfficialMenuItem>[];
      for (final e in rawMenu) {
        if (e is Map) {
          parsed.add(
            _OfficialMenuItem.fromJson(e.cast<String, dynamic>()),
          );
        }
      }
      menuItems = parsed;
    }
    OfficialNotificationMode? notifMode;
    final rawMode = (j['notif_mode'] ?? '').toString().trim().toLowerCase();
    switch (rawMode) {
      case 'full':
        notifMode = OfficialNotificationMode.full;
        break;
      case 'summary':
        notifMode = OfficialNotificationMode.summary;
        break;
      case 'muted':
        notifMode = OfficialNotificationMode.muted;
        break;
      default:
        notifMode = null;
    }
    final List<String> badges = <String>[];
    final rawBadges = j['badges'];
    if (rawBadges is List) {
      for (final e in rawBadges) {
        final s = (e ?? '').toString().trim();
        if (s.isNotEmpty) {
          badges.add(s);
        }
      }
    }
    return _OfficialAccount(
      id: (j['id'] ?? '').toString(),
      kind: (j['kind'] ?? 'service').toString(),
      name: (j['name'] ?? '').toString(),
      description: (j['description'] ?? '').toString().isEmpty
          ? null
          : (j['description'] ?? '').toString(),
      avatarUrl: (j['avatar_url'] ?? '').toString().isEmpty
          ? null
          : (j['avatar_url'] ?? '').toString(),
      verified: (j['verified'] as bool?) ?? false,
      featured: (j['featured'] as bool?) ?? false,
      badges: badges,
      unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
      lastItemTitle: j['last_item'] is Map
          ? ((j['last_item'] as Map)['title'] ?? '').toString()
          : null,
      lastItemTs: lastTs,
      chatPeerId: rawChatId.isEmpty ? null : rawChatId,
      miniAppId: (j['mini_app_id'] ?? '').toString().isEmpty
          ? null
          : (j['mini_app_id'] ?? '').toString(),
      category: (j['category'] ?? '').toString().isEmpty
          ? null
          : (j['category'] ?? '').toString(),
      city: (j['city'] ?? '').toString().isEmpty
          ? null
          : (j['city'] ?? '').toString(),
      address: (j['address'] ?? '').toString().isEmpty
          ? null
          : (j['address'] ?? '').toString(),
      openingHours: (j['opening_hours'] ?? '').toString().isEmpty
          ? null
          : (j['opening_hours'] ?? '').toString(),
      websiteUrl: (j['website_url'] ?? '').toString().isEmpty
          ? null
          : (j['website_url'] ?? '').toString(),
      qrPayload: (j['qr_payload'] ?? '').toString().isEmpty
          ? null
          : (j['qr_payload'] ?? '').toString(),
      followed: (j['followed'] as bool?) ?? false,
      menuItems: menuItems,
      notifMode: notifMode,
    );
  }

  _OfficialAccount withUnreadFrom(int unread) {
    if (unread <= 0) {
      return this;
    }
    return _OfficialAccount(
      id: id,
      kind: kind,
      name: name,
      description: description,
      avatarUrl: avatarUrl,
      verified: verified,
      featured: featured,
      badges: badges,
      unreadCount: unread,
      lastItemTitle: lastItemTitle,
      lastItemTs: lastItemTs,
      chatPeerId: chatPeerId,
      miniAppId: miniAppId,
      category: category,
      city: city,
      address: address,
      openingHours: openingHours,
      websiteUrl: websiteUrl,
      qrPayload: qrPayload,
      followed: followed,
      menuItems: menuItems,
      notifMode: notifMode,
    );
  }
}

class OfficialAccountHandle {
  final String id;
  final String kind;
  final String name;
  final String? description;
  final String? avatarUrl;
  final bool verified;
  final bool featured;
  final String? chatPeerId;
  final String? miniAppId;
  final String? category;
  final String? city;
  final String? address;
  final String? openingHours;
  final String? websiteUrl;
  final String? qrPayload;
  final bool followed;
  final List<_OfficialMenuItem> menuItems;

  const OfficialAccountHandle({
    required this.id,
    required this.kind,
    required this.name,
    this.description,
    this.avatarUrl,
    this.verified = false,
    this.featured = false,
    this.chatPeerId,
    this.miniAppId,
    this.category,
    this.city,
    this.address,
    this.openingHours,
    this.websiteUrl,
    this.qrPayload,
    this.followed = false,
    this.menuItems = const <_OfficialMenuItem>[],
  });

  factory OfficialAccountHandle.fromJson(Map<String, dynamic> j) {
    final rawChatId = (j['chat_peer_id'] ?? '').toString().trim();
    List<_OfficialMenuItem> menuItems = const <_OfficialMenuItem>[];
    if (j['menu_items'] is List) {
      final rawMenu = j['menu_items'] as List;
      final parsed = <_OfficialMenuItem>[];
      for (final e in rawMenu) {
        if (e is Map) {
          parsed.add(
            _OfficialMenuItem.fromJson(e.cast<String, dynamic>()),
          );
        }
      }
      menuItems = parsed;
    }
    return OfficialAccountHandle(
      id: (j['id'] ?? '').toString(),
      kind: (j['kind'] ?? 'service').toString(),
      name: (j['name'] ?? '').toString(),
      description: (j['description'] ?? '').toString().isEmpty
          ? null
          : (j['description'] ?? '').toString(),
      avatarUrl: (j['avatar_url'] ?? '').toString().isEmpty
          ? null
          : (j['avatar_url'] ?? '').toString(),
      verified: (j['verified'] as bool?) ?? false,
      featured: (j['featured'] as bool?) ?? false,
      chatPeerId: rawChatId.isEmpty ? null : rawChatId,
      miniAppId: (j['mini_app_id'] ?? '').toString().isEmpty
          ? null
          : (j['mini_app_id'] ?? '').toString(),
      category: (j['category'] ?? '').toString().isEmpty
          ? null
          : (j['category'] ?? '').toString(),
      city: (j['city'] ?? '').toString().isEmpty
          ? null
          : (j['city'] ?? '').toString(),
      address: (j['address'] ?? '').toString().isEmpty
          ? null
          : (j['address'] ?? '').toString(),
      openingHours: (j['opening_hours'] ?? '').toString().isEmpty
          ? null
          : (j['opening_hours'] ?? '').toString(),
      websiteUrl: (j['website_url'] ?? '').toString().isEmpty
          ? null
          : (j['website_url'] ?? '').toString(),
      qrPayload: (j['qr_payload'] ?? '').toString().isEmpty
          ? null
          : (j['qr_payload'] ?? '').toString(),
      followed: (j['followed'] as bool?) ?? false,
      menuItems: menuItems,
    );
  }
}

extension _OfficialAccountHandleExt on _OfficialAccount {
  OfficialAccountHandle toHandle() {
    return OfficialAccountHandle(
      id: id,
      kind: kind,
      name: name,
      description: description,
      avatarUrl: avatarUrl,
      verified: verified,
      featured: featured,
      chatPeerId: chatPeerId,
      miniAppId: miniAppId,
      category: category,
      city: city,
      address: address,
      openingHours: openingHours,
      websiteUrl: websiteUrl,
      qrPayload: qrPayload,
      followed: followed,
      menuItems: menuItems,
    );
  }
}

class _OfficialFeedItem {
  final String id;
  final String type;
  final String? title;
  final String? snippet;
  final String? thumbUrl;
  final DateTime? ts;
  final String? deeplinkMiniAppId;
  final Map<String, dynamic>? deeplinkPayload;
  // Optional livestream URL (e.g. HLS) for
  // Channels-style live items; best-effort.
  final String? liveUrl;

  _OfficialFeedItem({
    required this.id,
    required this.type,
    this.title,
    this.snippet,
    this.thumbUrl,
    this.ts,
    this.deeplinkMiniAppId,
    this.deeplinkPayload,
    this.liveUrl,
  });

  String get tsLabel {
    final t = ts;
    if (t == null) return '';
    final dt = t.toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  factory _OfficialFeedItem.fromJson(Map<String, dynamic> j) {
    DateTime? parseTs(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }

    String? miniAppId;
    Map<String, dynamic>? payload;
    String? liveUrl;
    final dl = j['deeplink'];
    if (dl is Map) {
      if (dl['mini_app_id'] != null) {
        miniAppId = dl['mini_app_id'].toString();
      }
      final rawPayload = dl['payload'];
      if (rawPayload is Map) {
        payload = rawPayload.cast<String, dynamic>();
      }
      final liveUrlRaw = dl['live_url'];
      if (liveUrlRaw is String && liveUrlRaw.trim().isNotEmpty) {
        liveUrl = liveUrlRaw.trim();
      }
    }

    return _OfficialFeedItem(
      id: (j['id'] ?? '').toString(),
      type: (j['type'] ?? 'promo').toString(),
      title: (j['title'] ?? '').toString().isEmpty
          ? null
          : (j['title'] ?? '').toString(),
      snippet: (j['snippet'] ?? '').toString().isEmpty
          ? null
          : (j['snippet'] ?? '').toString(),
      thumbUrl: (j['thumb_url'] ?? '').toString().isEmpty
          ? null
          : (j['thumb_url'] ?? '').toString(),
      ts: parseTs((j['ts'] ?? '').toString()),
      deeplinkMiniAppId: miniAppId,
      deeplinkPayload: payload,
      liveUrl: liveUrl,
    );
  }
}

class _OfficialMenuItem {
  final String id;
  final String kind;
  final String? miniAppId;
  final String? url;
  final String? labelEn;
  final String? labelAr;

  const _OfficialMenuItem({
    required this.id,
    required this.kind,
    this.miniAppId,
    this.url,
    this.labelEn,
    this.labelAr,
  });

  factory _OfficialMenuItem.fromJson(Map<String, dynamic> j) {
    return _OfficialMenuItem(
      id: (j['id'] ?? '').toString(),
      kind: (j['kind'] ?? 'mini_app').toString(),
      miniAppId: (j['mini_app_id'] ?? '').toString().isEmpty
          ? null
          : (j['mini_app_id'] ?? '').toString(),
      url: (j['url'] ?? '').toString().isEmpty
          ? null
          : (j['url'] ?? '').toString(),
      labelEn: (j['label_en'] ?? '').toString().isEmpty
          ? null
          : (j['label_en'] ?? '').toString(),
      labelAr: (j['label_ar'] ?? '').toString().isEmpty
          ? null
          : (j['label_ar'] ?? '').toString(),
    );
  }

  String label(L10n l, String fallback) {
    if (l.isArabic) {
      return (labelAr != null && labelAr!.isNotEmpty) ? labelAr! : fallback;
    }
    return (labelEn != null && labelEn!.isNotEmpty) ? labelEn! : fallback;
  }
}

class _OfficialLocation {
  final int id;
  final String? name;
  final String? city;
  final String? address;
  final double? lat;
  final double? lon;
  final String? phone;
  final String? openingHours;

  _OfficialLocation({
    required this.id,
    this.name,
    this.city,
    this.address,
    this.lat,
    this.lon,
    this.phone,
    this.openingHours,
  });

  factory _OfficialLocation.fromJson(Map<String, dynamic> j) {
    double? parseNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString();
      return double.tryParse(s);
    }

    return _OfficialLocation(
      id: (j['id'] as num?)?.toInt() ?? 0,
      name: (j['name'] ?? '').toString().isEmpty
          ? null
          : (j['name'] ?? '').toString(),
      city: (j['city'] ?? '').toString().isEmpty
          ? null
          : (j['city'] ?? '').toString(),
      address: (j['address'] ?? '').toString().isEmpty
          ? null
          : (j['address'] ?? '').toString(),
      lat: parseNum(j['lat']),
      lon: parseNum(j['lon']),
      phone: (j['phone'] ?? '').toString().isEmpty
          ? null
          : (j['phone'] ?? '').toString(),
      openingHours: (j['opening_hours'] ?? '').toString().isEmpty
          ? null
          : (j['opening_hours'] ?? '').toString(),
    );
  }
}
