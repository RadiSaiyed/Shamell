import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'mini_program_runtime.dart';
import 'official_accounts_page.dart'
    show OfficialAccountDeepLinkPage, OfficialFeedItemDeepLinkPage;
import 'moments_page.dart';
import 'channels_page.dart' show ChannelsPage;
import 'global_media_page.dart';
import 'wechat_ui.dart';

class GlobalSearchPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final void Function(String modId) onOpenMod;

  const GlobalSearchPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.onOpenMod,
  });

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _qCtrl = TextEditingController();
  Timer? _searchDebounce;
  int _searchSeq = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = const [];
  late TabController _tabCtrl;
  List<String> _history = const [];
  List<String> _trendingTopics = const [];
  String? _miniProgramCategoryFilter;
  bool _miniProgramMineOnly = false;
  bool _miniProgramTrendingOnly = false;
  bool _channelCampaignOnly = false;
  bool _channelPromoOnly = false;
  bool _momentRedpacketOnly = false;
  bool _officialCampaignOnly = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _loadHistory();
    _loadTrendingTopics();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _qCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final items =
          sp.getStringList('global_search_history') ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _history = items;
      });
    } catch (_) {}
  }

  Future<void> _updateHistory(String q) async {
    final term = q.trim();
    if (term.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final cur = [..._history];
      cur.removeWhere((e) => e == term);
      cur.insert(0, term);
      if (cur.length > 10) {
        cur.removeRange(10, cur.length);
      }
      await sp.setStringList('global_search_history', cur);
      if (!mounted) return;
      setState(() {
        _history = cur;
      });
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('global_search_history');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _history = const [];
    });
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    final h = <String, String>{};
    if (jsonBody) h['content-type'] = 'application/json';
    try {
      final sp = await SharedPreferences.getInstance();
      final cookie = sp.getString('sa_cookie') ?? '';
      if (cookie.isNotEmpty) {
        h['sa_cookie'] = cookie;
      }
    } catch (_) {}
    return h;
  }

  Future<void> _loadTrendingTopics() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/moments/topics/trending')
          .replace(queryParameters: const {'limit': '8'});
      final resp = await http.get(uri, headers: await _hdr());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        // Fallback: still show the Red‑packet Moments topic even if trending API fails.
        if (!mounted) return;
        setState(() {
          _trendingTopics = const ['ShamellRedPacket'];
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
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
      // Ensure the Red‑packet Moments topic is always visible in search.
      const redTag = 'ShamellRedPacket';
      if (!tags.any((t) => t.toLowerCase() == redTag.toLowerCase())) {
        tags.add(redTag);
      }
      if (!mounted || tags.isEmpty) return;
      setState(() {
        _trendingTopics = tags;
      });
    } catch (_) {}
  }

  Future<void> _runSearch({bool commitHistory = true}) async {
    final q = _qCtrl.text.trim();
    if (q.isEmpty) return;
    final seq = ++_searchSeq;
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
    });
    // Best-effort lokale Suchhistorie aktualisieren.
    if (commitHistory) {
      // ignore: discarded_futures
      _updateHistory(q);
    }
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/search').replace(queryParameters: {
        'q': q,
        'limit': '30',
      });
      final resp = await http.get(uri, headers: await _hdr());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _error = resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}';
          _loading = false;
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
      final list = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['results'] is List) {
        for (final e in decoded['results'] as List) {
          if (e is Map) {
            list.add(e.cast<String, dynamic>());
          }
        }
      }
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;
    final dividerColor = isDark ? theme.dividerColor : WeChatPalette.divider;

    final tabs = <Tab>[
      Tab(text: isArabic ? 'الكل' : 'All'),
      Tab(text: isArabic ? 'الخدمات' : 'Mini‑apps'),
      Tab(text: isArabic ? 'البرامج المصغّرة' : 'Mini‑programs'),
      Tab(text: isArabic ? 'الرسمي' : 'Official'),
      Tab(text: isArabic ? 'اللحظات' : 'Moments'),
      Tab(text: isArabic ? 'القنوات' : 'Channels'),
    ];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: bgColor,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? WeChatPalette.searchFillDark
                        : WeChatPalette.searchFill,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextField(
                    controller: _qCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {
                      final q = _qCtrl.text.trim();
                      _searchDebounce?.cancel();
                      if (q.isEmpty) {
                        _searchSeq++;
                        setState(() {
                          _loading = false;
                          _error = null;
                          _results = const [];
                        });
                        return;
                      }
                      setState(() {});
                      if (q.length < 2) return;
                      _searchDebounce =
                          Timer(const Duration(milliseconds: 380), () {
                        if (!mounted) return;
                        // ignore: discarded_futures
                        _runSearch(commitHistory: false);
                      });
                    },
                    onSubmitted: (_) {
                      _searchDebounce?.cancel();
                      // ignore: discarded_futures
                      _runSearch();
                    },
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 8),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 18,
                        color: isDark
                            ? theme.colorScheme.onSurface.withValues(alpha: .55)
                            : WeChatPalette.textSecondary,
                      ),
                      hintText: isArabic ? 'بحث' : 'Search',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: isDark
                            ? theme.colorScheme.onSurface.withValues(alpha: .55)
                            : WeChatPalette.textSecondary,
                      ),
                      suffixIcon: _qCtrl.text.trim().isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: 18,
                                color: isDark
                                    ? theme.colorScheme.onSurface
                                        .withValues(alpha: .55)
                                    : WeChatPalette.textSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _qCtrl.clear();
                                  _results = const [];
                                  _error = null;
                                });
                              },
                            ),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l.mirsaalDialogCancel),
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? theme.colorScheme.surface : Colors.white,
              border: Border(
                bottom: BorderSide(color: dividerColor, width: 0.6),
              ),
            ),
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabs: tabs,
              labelColor: theme.colorScheme.onSurface,
              unselectedLabelColor:
                  theme.colorScheme.onSurface.withValues(alpha: .55),
              indicatorColor: WeChatPalette.green,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 2.4,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          if (!_loading &&
              _error == null &&
              _results.isEmpty &&
              _history.isNotEmpty)
            WeChatSection(
              margin: const EdgeInsets.only(top: 12),
              dividerIndent: 0,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isArabic
                                ? 'عمليات البحث الأخيرة'
                                : 'Recent searches',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: isArabic ? 'مسح' : 'Clear',
                            onPressed: _clearHistory,
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .55),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final term in _history)
                            ActionChip(
                              backgroundColor: isDark
                                  ? theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: .35)
                                  : WeChatPalette.searchFill,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              label: Text(
                                term,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .85),
                                ),
                              ),
                              onPressed: () {
                                _qCtrl.text = term;
                                _runSearch();
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (!_loading &&
              _error == null &&
              _results.isEmpty &&
              _trendingTopics.isNotEmpty)
            WeChatSection(
              margin: const EdgeInsets.only(top: 12),
              dividerIndent: 0,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isArabic
                                ? 'المواضيع الشائعة في اللحظات'
                                : 'Trending Moments topics',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: isArabic ? 'تحديث' : 'Refresh',
                            onPressed: () {
                              // ignore: discarded_futures
                              _loadTrendingTopics();
                            },
                            icon: Icon(
                              Icons.refresh,
                              size: 20,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .55),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final tag in _trendingTopics)
                            ActionChip(
                              backgroundColor: isDark
                                  ? theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: .35)
                                  : WeChatPalette.searchFill,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              label: Text(
                                '#$tag',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .85),
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => MomentsPage(
                                      baseUrl: widget.baseUrl,
                                      topicTag: '#$tag',
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (!_loading && _error == null)
            WeChatSection(
              margin: const EdgeInsets.only(top: 12),
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(
                    Icons.photo_library_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    isArabic
                        ? 'الوسائط والملفات في الدردشات'
                        : 'Media & files in chats',
                  ),
                  subtitle: Text(
                    isArabic
                        ? 'استعرض الصور والملفات والروابط من كل الدردشات في مكان واحد.'
                        : 'Browse photos, files and links from all chats in one place.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: .45),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            GlobalMediaPage(baseUrl: widget.baseUrl),
                      ),
                    );
                  },
                ),
              ],
            ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(context, filter: null),
                _buildList(context, filter: 'mini_app'),
                _buildList(context, filter: 'mini_program'),
                _buildList(context, filter: 'official'),
                _buildList(context, filter: 'moment'),
                _buildList(context, filter: 'channel'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, {String? filter}) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tileBg = isDark ? theme.colorScheme.surface : Colors.white;
    final dividerColor = isDark ? theme.dividerColor : WeChatPalette.divider;

    Widget resultsList(List<Map<String, dynamic>> entries) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        separatorBuilder: (_, __) => Container(
          color: tileBg,
          child: Divider(
            height: 1,
            thickness: 0.5,
            indent: 72,
            color: dividerColor,
          ),
        ),
        itemBuilder: (_, i) {
          final e = entries[i];
          final extra = (e['extra'] is Map)
              ? (e['extra'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          return Container(
            color: tileBg,
            child: _buildResultTile(context, e, extra, theme, l),
          );
        },
      );
    }

    final items = filter == null
        ? _results
        : _results.where((e) => (e['kind'] ?? '') == filter).toList();
    if (items.isEmpty) {
      if (filter == 'channel') {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.live_tv_outlined,
                  size: 40,
                  color: theme.colorScheme.onSurface.withValues(alpha: .45),
                ),
                const SizedBox(height: 8),
                Text(
                  l.isArabic
                      ? 'لا توجد نتائج قنوات بعد.\nاستخدم اكتشاف القنوات لرؤية المقاطع الرائجة.'
                      : 'No channel results yet.\nUse Channels discover to browse hot clips.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChannelsPage(
                          baseUrl: widget.baseUrl,
                          initialHotOnly: true,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: Text(
                    l.isArabic
                        ? 'فتح اكتشاف القنوات'
                        : 'Open Channels discover',
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Text(
          l.isArabic ? 'لا نتائج بعد.' : 'No results yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .6)),
        ),
      );
    }
    if (filter == 'mini_program') {
      final filtered = <Map<String, dynamic>>[];
      final categories = <String>{};
      for (final e in items) {
        final extra = (e['extra'] is Map)
            ? (e['extra'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        final badgesRaw = extra['badges'];
        final List<String> badges = badgesRaw is List
            ? badgesRaw.whereType<String>().toList()
            : const <String>[];
        final categoryKey = (extra['category'] ?? '').toString();
        if (categoryKey.isNotEmpty) {
          categories.add(categoryKey);
        }
        if (_miniProgramMineOnly && !badges.contains('mine')) {
          continue;
        }
        if (_miniProgramTrendingOnly &&
            !badges.contains('trending') &&
            !badges.contains('hot_in_moments')) {
          continue;
        }
        if (_miniProgramCategoryFilter != null &&
            _miniProgramCategoryFilter!.isNotEmpty &&
            categoryKey.isNotEmpty &&
            categoryKey != _miniProgramCategoryFilter) {
          continue;
        }
        filtered.add(e);
      }
      final keys = categories.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(l.isArabic ? 'الكل' : 'All'),
                    selected: !_miniProgramMineOnly &&
                        !_miniProgramTrendingOnly &&
                        (_miniProgramCategoryFilter == null ||
                            _miniProgramCategoryFilter!.isEmpty),
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _miniProgramMineOnly = false;
                        _miniProgramTrendingOnly = false;
                        _miniProgramCategoryFilter = null;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Text(
                      l.isArabic ? 'برامجي فقط' : 'My mini‑programs only',
                    ),
                    selected: _miniProgramMineOnly,
                    onSelected: (sel) {
                      setState(() {
                        _miniProgramMineOnly = sel;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department_outlined,
                            size: 14),
                        const SizedBox(width: 4),
                        Text(l.isArabic ? 'الرائجة' : 'Trending'),
                      ],
                    ),
                    selected: _miniProgramTrendingOnly,
                    onSelected: (sel) {
                      setState(() {
                        _miniProgramTrendingOnly = sel;
                      });
                    },
                  ),
                  for (final key in keys)
                    ChoiceChip(
                      label: Text(_labelForOfficialCategory(key, l)),
                      selected: _miniProgramCategoryFilter == key,
                      onSelected: (sel) {
                        setState(() {
                          _miniProgramCategoryFilter = sel ? key : null;
                        });
                      },
                    ),
                ],
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.isArabic
                            ? 'لا توجد برامج مصغّرة مطابقة.'
                            : 'No matching mini‑programs.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                    ),
                  )
                : resultsList(filtered),
          ),
        ],
      );
    }
    if (filter == 'official') {
      final filtered = <Map<String, dynamic>>[];
      for (final e in items) {
        final extra = (e['extra'] is Map)
            ? (e['extra'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        final badgesRaw = extra['badges'];
        final List<String> badges = badgesRaw is List
            ? badgesRaw.whereType<String>().toList()
            : const <String>[];
        if (_officialCampaignOnly && !badges.contains('campaign')) {
          continue;
        }
        filtered.add(e);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(l.isArabic ? 'الكل' : 'All accounts'),
                    selected: !_officialCampaignOnly,
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _officialCampaignOnly = false;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.campaign_outlined, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          l.isArabic ? 'حسابات بها حملات' : 'Campaign accounts',
                        ),
                      ],
                    ),
                    selected: _officialCampaignOnly,
                    onSelected: (sel) {
                      setState(() {
                        _officialCampaignOnly = sel;
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.isArabic
                            ? 'لا توجد حسابات رسمية مطابقة.'
                            : 'No matching official accounts.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                    ),
                  )
                : resultsList(filtered),
          ),
        ],
      );
    }
    if (filter == 'moment') {
      final filtered = <Map<String, dynamic>>[];
      for (final e in items) {
        final extra = (e['extra'] is Map)
            ? (e['extra'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        final badgesRaw = extra['badges'];
        final List<String> badges = badgesRaw is List
            ? badgesRaw.whereType<String>().toList()
            : const <String>[];
        if (_momentRedpacketOnly && !badges.contains('redpacket')) {
          continue;
        }
        filtered.add(e);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(l.isArabic ? 'الكل' : 'All moments'),
                    selected: !_momentRedpacketOnly,
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _momentRedpacketOnly = false;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.card_giftcard_outlined, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          l.isArabic ? 'حزم حمراء' : 'Red‑packet moments',
                        ),
                      ],
                    ),
                    selected: _momentRedpacketOnly,
                    onSelected: (sel) {
                      setState(() {
                        _momentRedpacketOnly = sel;
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.isArabic
                            ? 'لا توجد لحظات مطابقة.'
                            : 'No matching moments.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                    ),
                  )
                : resultsList(filtered),
          ),
        ],
      );
    }
    if (filter == 'channel') {
      final filtered = <Map<String, dynamic>>[];
      for (final e in items) {
        final extra = (e['extra'] is Map)
            ? (e['extra'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        final badgesRaw = extra['badges'];
        final List<String> badges = badgesRaw is List
            ? badgesRaw.whereType<String>().toList()
            : const <String>[];
        if (_channelCampaignOnly && !badges.contains('campaign')) {
          continue;
        }
        if (_channelPromoOnly && !badges.contains('promo')) {
          continue;
        }
        filtered.add(e);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(l.isArabic ? 'الكل' : 'All clips'),
                    selected: !_channelCampaignOnly && !_channelPromoOnly,
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _channelCampaignOnly = false;
                        _channelPromoOnly = false;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.campaign_outlined, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          l.isArabic ? 'مقاطع الحملات' : 'Campaign clips',
                        ),
                      ],
                    ),
                    selected: _channelCampaignOnly,
                    onSelected: (sel) {
                      setState(() {
                        _channelCampaignOnly = sel;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department_outlined,
                            size: 14),
                        const SizedBox(width: 4),
                        Text(
                          l.isArabic ? 'مقاطع ترويجية' : 'Promo clips',
                        ),
                      ],
                    ),
                    selected: _channelPromoOnly,
                    onSelected: (sel) {
                      setState(() {
                        _channelPromoOnly = sel;
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.isArabic
                            ? 'لا توجد مقاطع قنوات مطابقة.'
                            : 'No matching channel clips.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                    ),
                  )
                : resultsList(filtered),
          ),
        ],
      );
    }
    return resultsList(items);
  }

  Widget _buildResultTile(
    BuildContext context,
    Map<String, dynamic> e,
    Map<String, dynamic> extra,
    ThemeData theme,
    L10n l,
  ) {
    final kind = (e['kind'] ?? '').toString();
    final title = (e['title'] ?? '').toString();
    final titleAr = (e['title_ar'] ?? '').toString();
    final snippet = (e['snippet'] ?? '').toString();
    IconData icon;
    switch (kind) {
      case 'mini_app':
        icon = Icons.apps_outlined;
        break;
      case 'mini_program':
        icon = Icons.widgets_outlined;
        break;
      case 'official':
        icon = Icons.verified_outlined;
        break;
      case 'moment':
        icon = Icons.photo_outlined;
        break;
      case 'channel':
        icon = Icons.play_circle_outline;
        break;
      default:
        icon = Icons.search;
    }
    final label = l.isArabic && titleAr.isNotEmpty ? titleAr : title;
    // Build optional metadata row (rating/badges) for different kinds.
    Widget? subtitle;
    final List<Widget> metaChips = <Widget>[];
    if (kind == 'mini_app') {
      final ratingRaw = extra['rating'];
      final rating = ratingRaw is num ? ratingRaw.toDouble() : 0.0;
      final badgesRaw = extra['badges'];
      final List<String> badges = badgesRaw is List
          ? badgesRaw.whereType<String>().toList()
          : const <String>[];
      if (rating > 0) {
        metaChips.addAll([
          Icon(
            Icons.star,
            size: 14,
            color: Colors.amber.withValues(alpha: .95),
          ),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 11),
          ),
        ]);
      }
      _appendBadges(metaChips, badges, l, theme);
    } else if (kind == 'mini_program') {
      final ratingRaw = extra['rating'];
      final rating = ratingRaw is num ? ratingRaw.toDouble() : 0.0;
      final usageRaw = extra['usage_score'];
      final usage = usageRaw is num ? usageRaw.toInt() : 0;
      final m30Raw = extra['moments_shares_30d'];
      final m30 = m30Raw is num ? m30Raw.toInt() : 0;
      final badgesRaw = extra['badges'];
      final List<String> badges = badgesRaw is List
          ? badgesRaw.whereType<String>().toList()
          : const <String>[];
      final mine = badges.contains('mine') || badges.contains('owned_by_you');
      if (rating > 0) {
        metaChips.addAll([
          Icon(
            Icons.star,
            size: 14,
            color: Colors.amber.withValues(alpha: .95),
          ),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 11),
          ),
        ]);
      }
      if (usage > 0) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            l.isArabic ? 'الفتحات: $usage' : 'Opens: $usage',
            style: const TextStyle(fontSize: 10),
          ),
        ));
      }
      if (m30 > 0) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            l.isArabic ? 'لحظات (٣٠ي): $m30' : 'Moments (30d): $m30',
            style: const TextStyle(fontSize: 10),
          ),
        ));
      }
      if (mine) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              l.isArabic ? 'برنامجي' : 'My mini‑program',
              style: TextStyle(
                fontSize: 9,
                color: theme.colorScheme.primary.withValues(alpha: .85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ));
      }
      _appendBadges(metaChips, badges, l, theme);
    } else if (kind == 'official') {
      final badgesRaw = extra['badges'];
      final List<String> badges = badgesRaw is List
          ? badgesRaw.whereType<String>().toList()
          : const <String>[];
      final city = (extra['city'] ?? '').toString();
      final category = (extra['category'] ?? '').toString();
      final campaignsRaw = extra['campaigns_active'];
      final campaignsActive = campaignsRaw is num ? campaignsRaw.toInt() : 0;
      _appendBadges(metaChips, badges, l, theme);
      if (campaignsActive > 0) {
        metaChips.add(
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.campaign_outlined, size: 12),
                const SizedBox(width: 2),
                Text(
                  l.isArabic
                      ? 'حملات حزم حمراء: $campaignsActive'
                      : 'Red‑packet campaigns: $campaignsActive',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (city.isNotEmpty) {
        metaChips.add(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_outlined, size: 12),
            const SizedBox(width: 2),
            Text(
              city,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ));
      }
      if (category.isNotEmpty) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            _labelForOfficialCategory(category, l),
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: .65),
            ),
          ),
        ));
      }
    } else if (kind == 'mini_program') {
      final ratingRaw = extra['rating'];
      final rating = ratingRaw is num ? ratingRaw.toDouble() : 0.0;
      final usageRaw = extra['usage_score'];
      final usageScore = usageRaw is num ? usageRaw.toInt() : 0;
      final badgesRaw = extra['badges'];
      final List<String> badges = badgesRaw is List
          ? badgesRaw.whereType<String>().toList()
          : const <String>[];
      final ownerName = (extra['owner_name'] ?? '').toString();
      final categoryKey = (extra['category'] ?? '').toString();
      final isMine = badges.contains('mine');
      if (rating > 0) {
        metaChips.addAll([
          Icon(
            Icons.star,
            size: 14,
            color: Colors.amber.withValues(alpha: .95),
          ),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 11),
          ),
        ]);
      }
      if (usageScore > 0) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department_outlined, size: 12),
              const SizedBox(width: 2),
              Text(
                l.isArabic ? 'استخدام $usageScore' : 'Usage $usageScore',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
                ),
              ),
            ],
          ),
        ));
      }
      _appendBadges(metaChips, badges, l, theme);
      if (ownerName.isNotEmpty) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            isMine ? (l.isArabic ? 'أنت (المالك)' : 'You (owner)') : ownerName,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: .75),
            ),
          ),
        ));
      }
      if (categoryKey.isNotEmpty) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            _labelForOfficialCategory(categoryKey, l),
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: .65),
            ),
          ),
        ));
      }
    } else if (kind == 'moment') {
      final badgesRaw = extra['badges'];
      final List<String> badges = badgesRaw is List
          ? badgesRaw.whereType<String>().toList()
          : const <String>[];
      _appendBadges(metaChips, badges, l, theme);
    } else if (kind == 'channel') {
      final badgesRaw = extra['badges'];
      final List<String> badges = badgesRaw is List
          ? badgesRaw.whereType<String>().toList()
          : const <String>[];
      final officialName = (extra['official_name'] ?? '').toString();
      final likesRaw = extra['likes'];
      final viewsRaw = extra['views'];
      final commentsRaw = extra['comments'];
      final likes = likesRaw is num ? likesRaw.toInt() : 0;
      final views = viewsRaw is num ? viewsRaw.toInt() : 0;
      final comments = commentsRaw is num ? commentsRaw.toInt() : 0;
      _appendBadges(metaChips, badges, l, theme);
      if (officialName.isNotEmpty) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            officialName,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: .75),
            ),
          ),
        ));
      }
      if (likes > 0 || views > 0 || comments > 0) {
        metaChips.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (likes > 0) ...[
                const Icon(Icons.favorite_border, size: 12),
                const SizedBox(width: 2),
                Text(
                  '$likes',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
              if (views > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.remove_red_eye_outlined, size: 12),
                const SizedBox(width: 2),
                Text(
                  '$views',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
              if (comments > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.mode_comment_outlined, size: 12),
                const SizedBox(width: 2),
                Text(
                  '$comments',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
            ],
          ),
        ));
      }
    }

    if (snippet.isNotEmpty || metaChips.isNotEmpty) {
      final children = <Widget>[];
      if (snippet.isNotEmpty) {
        children.add(
          Text(
            snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
      if (metaChips.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: metaChips,
            ),
          ),
        );
      }
      subtitle = children.length == 1
          ? children.first
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children,
            );
    }

    Widget? trailing;
    if (kind == 'mini_program') {
      trailing = TextButton(
        onPressed: () => _openResult(context, kind, e, extra),
        child: Text(
          l.isArabic ? 'فتح' : 'Open',
          style: const TextStyle(fontSize: 12),
        ),
      );
    }

    return ListTile(
      leading: Icon(icon),
      title: Text(label.isNotEmpty ? label : kind),
      subtitle: subtitle,
      trailing: trailing,
      onTap: () => _openResult(context, kind, e, extra),
    );
  }

  void _openResult(
    BuildContext context,
    String kind,
    Map<String, dynamic> e,
    Map<String, dynamic> extra,
  ) {
    final id = (e['id'] ?? '').toString();
    if (id.isEmpty) return;
    switch (kind) {
      case 'mini_app':
        final runtimeId = (extra['runtime_app_id'] ?? '').toString();
        if (runtimeId.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MiniProgramPage(
                id: runtimeId,
                baseUrl: widget.baseUrl,
                walletId: widget.walletId,
                deviceId: widget.deviceId,
                onOpenMod: widget.onOpenMod,
              ),
            ),
          );
        } else {
          widget.onOpenMod(id);
        }
        break;
      case 'mini_program':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MiniProgramPage(
              id: id,
              baseUrl: widget.baseUrl,
              walletId: widget.walletId,
              deviceId: widget.deviceId,
              onOpenMod: widget.onOpenMod,
            ),
          ),
        );
        break;
      case 'official':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OfficialAccountDeepLinkPage(
              baseUrl: widget.baseUrl,
              accountId: id,
            ),
          ),
        );
        break;
      case 'moment':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MomentsPage(
              baseUrl: widget.baseUrl,
              initialPostId: id,
            ),
          ),
        );
        break;
      case 'channel':
        final accId = (extra['official_account_id'] ?? '').toString();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OfficialFeedItemDeepLinkPage(
              baseUrl: widget.baseUrl,
              accountId: accId,
              itemId: id,
            ),
          ),
        );
        break;
      default:
        break;
    }
  }
}

void _appendBadges(
  List<Widget> metaChips,
  List<String> badges,
  L10n l,
  ThemeData theme,
) {
  for (final b in badges) {
    final labelText = () {
      switch (b) {
        case 'official':
          return l.isArabic ? 'رسمي' : 'Official';
        case 'active':
          return l.isArabic ? 'نشط' : 'Active';
        case 'draft':
          return l.isArabic ? 'مسودة' : 'Draft';
        case 'owner':
          return l.isArabic ? 'المالك' : 'Owner';
        case 'mine':
          return l.isArabic ? 'برنامجي' : 'My mini‑program';
        case 'beta':
          return 'Beta';
        case 'trending':
          return l.isArabic ? 'شائع' : 'Trending';
        case 'hot_in_moments':
          return l.isArabic ? 'رائج في اللحظات' : 'Hot in Moments';
        case 'service':
          return l.isArabic ? 'خدمة' : 'Service account';
        case 'subscription':
          return l.isArabic ? 'اشتراك' : 'Subscription';
        case 'featured':
          return l.isArabic ? 'مميز' : 'Featured';
        case 'verified':
          return l.isArabic ? 'موثّق' : 'Verified';
        case 'campaign':
          return l.isArabic ? 'حملة' : 'Campaign';
        case 'promo':
          return l.isArabic ? 'ترويج' : 'Promo';
        case 'popular_clip':
          return l.isArabic ? 'مقطع شائع' : 'Popular clip';
        case 'discussed':
          return l.isArabic ? 'نقاشات' : 'Discussed';
        case 'redpacket':
          return l.isArabic ? 'حزم حمراء' : 'Red‑packet';
        case 'live':
          return l.isArabic ? 'بث مباشر' : 'Live now';
        default:
          return b;
      }
    }();
    metaChips.add(Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          labelText,
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.primary.withValues(alpha: .85),
          ),
        ),
      ),
    ));
  }
}

String _labelForOfficialCategory(String raw, L10n l) {
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
