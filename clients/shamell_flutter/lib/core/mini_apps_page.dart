import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'mini_app_registry.dart';
import 'mini_apps_config.dart';
import 'moments_page.dart';
import 'moments_preset_store.dart';
import 'mini_program_shelf_prefs.dart';
import 'mini_program_runtime.dart';
import 'session_cookie_store.dart';
import 'ui_kit.dart';

class MiniAppsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final void Function(String modId) onOpenMod;

  const MiniAppsPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.onOpenMod,
  });

  @override
  State<MiniAppsPage> createState() => _MiniAppsPageState();
}

class _MiniAppsPageState extends State<MiniAppsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  List<String> _recent = const [];
  List<String> _pinned = const [];
  List<MiniAppDescriptor> _remoteApps = const [];
  Map<String, Map<String, dynamic>> _shelfMeta =
      const <String, Map<String, dynamic>>{};
  bool _shelfSyncing = false;

  static const Duration _networkTimeout = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _syncShelfFromServer();
    _loadRemoteApps();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final recent = loadMiniProgramRecentIdsSync(sp);
      final pinned = loadMiniProgramPinnedIdsSync(sp);
      if (!mounted) return;
      setState(() {
        _recent = recent;
        _pinned = pinned;
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

  String _descriptorLaunchId(MiniAppDescriptor m) {
    final runtimeId = (m.runtimeAppId ?? '').trim();
    if (runtimeId.isNotEmpty) return runtimeId;
    return m.id.trim();
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

  String _shelfUsageLabel(String appId, L10n l) {
    final opens = _shelfOpenCount(appId);
    if (opens <= 0) return '';
    return l.isArabic ? 'فتحت $opens مرات' : '$opens opens';
  }

  Widget _miniAppShelfChipLabel(
    MiniAppDescriptor app,
    L10n l,
    ThemeData theme,
  ) {
    final usage = _shelfUsageLabel(_descriptorLaunchId(app), l);
    if (usage.isEmpty) {
      return Text(app.title(isArabic: l.isArabic));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(app.title(isArabic: l.isArabic)),
        Text(
          usage,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: theme.colorScheme.onSurface.withValues(alpha: .62),
          ),
        ),
      ],
    );
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
        _pinned = nextPinned;
        _recent = nextRecent;
        _shelfMeta = shelfMeta;
      });
    } catch (_) {
    } finally {
      _shelfSyncing = false;
    }
  }

  Future<void> _togglePinned(String id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cur = List<String>.from(_pinned);
      final wasPinned = cur.contains(id);
      if (wasPinned) {
        cur.remove(id);
      } else {
        cur.insert(0, id);
      }
      await saveMiniProgramShelfPrefs(sp, pinnedIds: cur, pinnedOrder: cur);
      if (!mounted) return;
      setState(() {
        _pinned = cur;
      });
      // ignore: discarded_futures
      _syncPinnedStateToServer(id, !wasPinned);
      // ignore: discarded_futures
      _syncPinnedOrderToServer(cur);
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
            headers: await shamellSessionHeadersForBaseUrl(
              widget.baseUrl,
              json: true,
            ),
            body: jsonEncode({'pinned': pinned}),
          )
          .timeout(const Duration(seconds: 4));
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

  Future<void> _trackOpen(MiniAppDescriptor m) async {
    final id = _descriptorLaunchId(m);
    if (id.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final nextRecent = _cleanIds(<String>[
        id,
        ..._recent,
        ...loadMiniProgramRecentIdsSync(sp),
      ]).take(10).toList();
      await saveMiniProgramRecentIds(sp, nextRecent);
      if (mounted) {
        setState(() {
          _recent = nextRecent;
        });
      }
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

  void _openMiniApp(MiniAppDescriptor m) {
    final id = _descriptorLaunchId(m);
    if (id.isEmpty) return;
    // ignore: discarded_futures
    _trackOpen(m);
    if (MiniAppRegistry.byId(id) != null) {
      widget.onOpenMod(id);
      return;
    }
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
  }

  List<MiniAppDescriptor> _allApps() {
    final local = visibleMiniApps();
    if (_remoteApps.isEmpty) return local;
    final existingIds = local.map((m) => m.id).toSet();
    final merged = <MiniAppDescriptor>[...local];
    for (final m in _remoteApps) {
      if (m.id.isEmpty) continue;
      if (existingIds.contains(m.id)) continue;
      merged.add(m);
    }
    return merged;
  }

  Future<void> _loadRemoteApps() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs');
      final resp = await http
          .get(uri, headers: await _authHeaders())
          .timeout(_networkTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final decoded = jsonDecode(resp.body);
      final list = <MiniAppDescriptor>[];
      if (decoded is Map) {
        final raw = decoded['apps'] is List
            ? decoded['apps'] as List
            : decoded['programs'] is List
                ? decoded['programs'] as List
                : const <dynamic>[];
        for (final e in raw) {
          if (e is Map) {
            final m = MiniAppDescriptor.fromJson(e.cast<String, dynamic>());
            if (m.id.isNotEmpty) {
              list.add(m);
            }
          }
        }
      }
      if (!mounted || list.isEmpty) return;
      setState(() {
        _remoteApps = list;
      });
    } catch (_) {}
  }

  Future<void> _rateMiniApp(MiniAppDescriptor m) async {
    final l = L10n.of(context);
    int selected = 5;
    bool submitting = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
              left: 16, right: 16, top: 16, bottom: bottom + 16),
          child: StatefulBuilder(
            builder: (ctx2, setModalState) {
              return Material(
                borderRadius: BorderRadius.circular(16),
                color: theme.cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic
                            ? 'تقييم البرنامج المصغر'
                            : 'Rate this Mini Program',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m.title(isArabic: l.isArabic),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: List.generate(5, (idx) {
                          final v = idx + 1;
                          final filled = v <= selected;
                          return IconButton(
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: submitting
                                ? null
                                : () {
                                    setModalState(() {
                                      selected = v;
                                      error = null;
                                    });
                                  },
                            icon: Icon(
                              filled ? Icons.star : Icons.star_border,
                              color: filled
                                  ? Colors.amber
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: .40),
                            ),
                          );
                        }),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(ctx).pop(),
                            child: Text(
                              l.isArabic ? 'إلغاء' : 'Cancel',
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: submitting
                                ? null
                                : () async {
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final uri = Uri.parse(
                                          '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(m.id)}/rate');
                                      final resp = await http.post(
                                        uri,
                                        headers: await _authHeaders(json: true),
                                        body: jsonEncode(
                                          <String, dynamic>{
                                            'rating': selected,
                                          },
                                        ),
                                      );
                                      if (resp.statusCode < 200 ||
                                          resp.statusCode >= 300) {
                                        setModalState(() {
                                          submitting = false;
                                          error = l.isArabic
                                              ? 'تعذّر إرسال التقييم.'
                                              : 'Failed to submit rating.';
                                        });
                                        return;
                                      }
                                      if (context.mounted) {
                                        Navigator.of(ctx).pop();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              l.isArabic
                                                  ? 'شكرًا لتقييم التطبيق.'
                                                  : 'Thanks for rating this Mini Program.',
                                            ),
                                          ),
                                        );
                                      }
                                      // Refresh remote apps best-effort so ratings are reflected.
                                      // ignore: discarded_futures
                                      _loadRemoteApps();
                                    } catch (_) {
                                      setModalState(() {
                                        submitting = false;
                                        error = l.isArabic
                                            ? 'تعذّر إرسال التقييم.'
                                            : 'Failed to submit rating.';
                                      });
                                    }
                                  },
                            child: submitting
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                  )
                                : Text(
                                    l.isArabic
                                        ? 'إرسال التقييم'
                                        : 'Submit rating',
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final apps = _allApps();
    final term = _query.trim().toLowerCase();
    final filtered = term.isEmpty
        ? apps
        : apps
            .where((a) =>
                a.titleEn.toLowerCase().contains(term) ||
                a.titleAr.toLowerCase().contains(term) ||
                a.categoryEn.toLowerCase().contains(term) ||
                a.categoryAr.toLowerCase().contains(term))
            .toList();

    // Mini Programs that are actively shared in Moments.
    final hotInMoments = [...apps]
      ..removeWhere((m) => m.momentsShares <= 0)
      ..sort((a, b) => b.momentsShares.compareTo(a.momentsShares));

    // Simple "trending" sort: usageScore + Moments shares, then rating.
    final trending = [...apps]..sort((a, b) {
        final scoreA = a.usageScore + (a.momentsShares * 2);
        final scoreB = b.usageScore + (b.momentsShares * 2);
        final s = scoreB.compareTo(scoreA);
        if (s != 0) return s;
        return b.rating.compareTo(a.rating);
      });

    final recentMeta = _recent
        .map((id) => apps.firstWhere(
              (a) => a.id == id,
              orElse: () => const MiniAppDescriptor(
                id: '',
                icon: Icons.apps_outlined,
                titleEn: '',
                titleAr: '',
                categoryEn: '',
                categoryAr: '',
              ),
            ))
        .where((m) => m.id.isNotEmpty)
        .toList();

    final pinnedMeta = _pinned
        .map((id) => apps.firstWhere(
              (a) => a.id == id,
              orElse: () => const MiniAppDescriptor(
                id: '',
                icon: Icons.apps_outlined,
                titleEn: '',
                titleAr: '',
                categoryEn: '',
                categoryAr: '',
              ),
            ))
        .where((m) => m.id.isNotEmpty)
        .toList();

    final hasWalletTopic = apps.any((m) => m.id == 'payments');
    final hasAnyTopic = hasWalletTopic;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .98)
        : (Colors.grey[100] ?? Colors.white);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0.5,
        title: Text(l.isArabic ? 'البرامج المصغّرة' : 'Mini Programs'),
      ),
      backgroundColor: bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormSection(
              title:
                  l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs directory',
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText:
                        l.isArabic ? 'ابحث في البرامج' : 'Search mini programs',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    setState(() {
                      _query = v;
                    });
                  },
                ),
              ],
            ),
            if (trending.isNotEmpty)
              FormSection(
                title: l.isArabic ? 'الشائعة' : 'Trending mini‑programs',
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: trending.take(8).map((m) {
                        final title = m.title(isArabic: l.isArabic);
                        final cat = m.category(isArabic: l.isArabic);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ActionChip(
                            avatar: Icon(m.icon, size: 18),
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.star,
                                      size: 12,
                                      color:
                                          Colors.amber.withValues(alpha: .95),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      m.rating.toStringAsFixed(1),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    if (m.momentsShares > 0) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.photo_library_outlined,
                                        size: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .80),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${m.momentsShares}',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ] else if (cat.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        cat,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: .60),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            onPressed: () => _openMiniApp(m),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            if (hotInMoments.isNotEmpty)
              FormSection(
                title: l.isArabic
                    ? 'التطبيقات المصغرة الرائجة في اللحظات'
                    : 'Hot Mini Programs in Moments',
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: hotInMoments.take(8).map((m) {
                        final title = m.title(isArabic: l.isArabic);
                        final count = m.momentsShares;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.photo_library_outlined,
                              size: 18,
                            ),
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  l.isArabic
                                      ? 'مشاركات في اللحظات: $count'
                                      : 'Shares in Moments: $count',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: 10,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: .65),
                                      ),
                                ),
                              ],
                            ),
                            onPressed: () => _openMiniApp(m),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            if (hasAnyTopic)
              FormSection(
                title: l.isArabic
                    ? 'مواضيع اللحظات للبرامج المصغّرة'
                    : 'Mini‑programs Moments topics',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (hasWalletTopic)
                        ActionChip(
                          avatar: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 18,
                          ),
                          label: Text(
                            l.isArabic
                                ? 'لحظات تطبيقات المحفظة'
                                : 'Wallet Mini Programs Moments',
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MomentsPage(
                                  baseUrl: widget.baseUrl,
                                  topicTag: '#WalletMiniApp',
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            if (pinnedMeta.isNotEmpty)
              FormSection(
                title: l.isArabic ? 'تطبيقاتي' : 'My mini‑programs',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: pinnedMeta
                        .map(
                          (m) => ActionChip(
                            avatar: Icon(m.icon, size: 18),
                            label: _miniAppShelfChipLabel(m, l, theme),
                            onPressed: () => _openMiniApp(m),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            if (recentMeta.isNotEmpty)
              FormSection(
                title: l.isArabic ? 'المستخدمة مؤخراً' : 'Recently used',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: recentMeta
                        .map(
                          (m) => ActionChip(
                            avatar: Icon(m.icon, size: 18),
                            label: _miniAppShelfChipLabel(m, l, theme),
                            onPressed: () => _openMiniApp(m),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            FormSection(
              title: l.isArabic ? 'كل البرامج' : 'All mini programs',
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final m = filtered[i];
                    final title = m.title(isArabic: l.isArabic);
                    final isPinned = _pinned.contains(m.id);
                    final canRate = _remoteApps.any((e) => e.id == m.id);
                    final runtimeId = m.runtimeAppId;
                    final isHotInMoments = m.momentsShares >= 3;
                    final isTrending =
                        m.usageScore >= 50 || m.momentsShares >= 5;
                    final personalOpens =
                        _shelfOpenCount(_descriptorLaunchId(m));
                    return GestureDetector(
                      onTap: () => _openMiniApp(m),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface
                                  .withValues(alpha: isDark ? .32 : .08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(m.icon, size: 28),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          if (isHotInMoments || isTrending)
                            Icon(
                              Icons.local_fire_department_outlined,
                              size: 12,
                              color: theme.colorScheme.primary
                                  .withValues(alpha: .85),
                            ),
                          if (isHotInMoments || isTrending)
                            const SizedBox(height: 2),
                          if (runtimeId != null && runtimeId.isNotEmpty)
                            Text(
                              l.isArabic ? 'برنامج مصغر' : 'Mini‑program',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                color: theme.colorScheme.primary
                                    .withValues(alpha: .80),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          if (personalOpens > 0)
                            Text(
                              l.isArabic
                                  ? '$personalOpens فتح'
                                  : '$personalOpens opens',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .58),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canRate) ...[
                                IconButton(
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: l.isArabic
                                      ? 'تقييم التطبيق المصغر'
                                      : 'Rate Mini Program',
                                  onPressed: () => _rateMiniApp(m),
                                  icon: Icon(
                                    Icons.star_rate_outlined,
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: .80),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              IconButton(
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: l.isArabic
                                    ? 'تثبيت في تطبيقاتي'
                                    : 'Pin to My mini‑programs',
                                onPressed: () => _togglePinned(m.id),
                                icon: Icon(
                                  isPinned ? Icons.star : Icons.star_border,
                                  color: isPinned
                                      ? Colors.amber
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: .45),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: l.isArabic
                                    ? 'رمز QR للتطبيق'
                                    : 'Mini Program QR',
                                onPressed: () => _showMiniAppQr(context, m, l),
                                icon: Icon(
                                  Icons.qr_code_2,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .55),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMiniAppQr(BuildContext context, MiniAppDescriptor m, L10n l) {
    final payload = 'MINIPROGRAM|id=${Uri.encodeComponent(m.id)}';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.isArabic ? 'رمز البرنامج المصغر' : 'Mini Program QR code',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                ),
                const SizedBox(height: 8),
                Text(
                  m.title(isArabic: l.isArabic),
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  payload,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .65),
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      var txt = l.isArabic
                          ? 'اكتشف ${m.title(isArabic: true)} في تطبيق SyrChat.'
                          : 'Check out ${m.title(isArabic: false)} in the SyrChat super app.';
                      if (!txt.contains('#')) {
                        if (l.isArabic) {
                          txt += ' #سرتشات_الخدمات #MiniApp';
                        } else {
                          txt += ' #ShamellMiniApp #Services';
                        }
                        switch (m.id) {
                          case 'payments':
                            txt += ' #WalletMiniApp';
                            break;
                        }
                      }
                      // Append a canonical deep-link so Moments can render
                      // a Mini Program card and allow tap-to-open.
                      txt += '\nshamell://mini_program/${m.id}';
                      await saveMiniProgramMomentsPreset(
                        text: txt,
                        miniProgramId: m.id,
                      );
                    } catch (_) {}
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MomentsPage(
                            baseUrl: widget.baseUrl,
                            miniProgramId: m.id,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: Text(
                    l.isArabic ? 'مشاركة في اللحظات' : 'Share to Moments',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
