import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'mini_apps_config.dart';
import 'moments_page.dart';
import 'mini_program_runtime.dart';
import 'ui_kit.dart';
import 'safe_set_state.dart';

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

class _MiniAppsPageState extends State<MiniAppsPage>
    with SafeSetStateMixin<MiniAppsPage> {
  static const Duration _miniAppsRequestTimeout = Duration(seconds: 15);
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  List<String> _recent = const [];
  List<String> _pinned = const [];
  List<MiniAppDescriptor> _remoteApps = const [];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
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
      final arr = sp.getStringList('recent_modules') ?? const <String>[];
      final pinned = sp.getStringList('pinned_miniapps') ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _recent = arr;
        _pinned = pinned;
      });
    } catch (_) {}
  }

  Future<void> _togglePinned(String id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cur = List<String>.from(_pinned);
      if (cur.contains(id)) {
        cur.remove(id);
      } else {
        cur.insert(0, id);
      }
      await sp.setStringList('pinned_miniapps', cur);
      if (!mounted) return;
      setState(() {
        _pinned = cur;
      });
    } catch (_) {}
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
      final uri = Uri.parse('${widget.baseUrl}/mini_apps');
      final resp = await http.get(uri).timeout(_miniAppsRequestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final decoded = jsonDecode(resp.body);
      final list = <MiniAppDescriptor>[];
      if (decoded is Map && decoded['apps'] is List) {
        for (final e in decoded['apps'] as List) {
          if (e is Map) {
            final m = MiniAppDescriptor.fromJson(e.cast<String, dynamic>());
            if (m.id.isNotEmpty) {
              list.add(m);
            }
          }
        }
      }
      // Bus-only build: ignore remote mini-apps that are not allow-listed.
      const allowedIds = <String>{'bus'};
      final filtered = list
          .where((m) => allowedIds.contains(m.id.trim().toLowerCase()))
          .toList();
      if (!mounted || filtered.isEmpty) return;
      setState(() {
        _remoteApps = filtered;
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
                            ? 'تقييم التطبيق المصغر'
                            : 'Rate this mini‑app',
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
                                          '${widget.baseUrl}/mini_apps/${Uri.encodeComponent(m.id)}/rate');
                                      final resp = await http
                                          .post(
                                            uri,
                                            headers: const {
                                              'content-type':
                                                  'application/json',
                                            },
                                            body: jsonEncode(
                                              <String, dynamic>{
                                                'rating': selected,
                                              },
                                            ),
                                          )
                                          .timeout(_miniAppsRequestTimeout);
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
                                                  : 'Thanks for rating this mini‑app.',
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

    // Mini-apps that are actively shared in Moments.
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
        title: Text(l.miniAppsTitle),
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
                    labelText: l.miniAppsSearchHint,
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
                            onPressed: () => widget.onOpenMod(m.id),
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
                    : 'Hot mini‑apps in Moments',
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
                            onPressed: () => widget.onOpenMod(m.id),
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
                                : 'Wallet mini‑apps Moments',
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
                            label: Text(m.title(isArabic: l.isArabic)),
                            onPressed: () => widget.onOpenMod(m.id),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            if (recentMeta.isNotEmpty)
              FormSection(
                title: l.miniAppsRecentTitle,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: recentMeta
                        .map(
                          (m) => ActionChip(
                            avatar: Icon(m.icon, size: 18),
                            label: Text(m.title(isArabic: l.isArabic)),
                            onPressed: () => widget.onOpenMod(m.id),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            FormSection(
              title: l.miniAppsAllTitle,
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
                    return GestureDetector(
                      onTap: () {
                        if (runtimeId != null && runtimeId.isNotEmpty) {
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
                          widget.onOpenMod(m.id);
                        }
                      },
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
                                      : 'Rate mini‑app',
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
                                    : 'Mini‑app QR',
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
    final payload = 'MINIAPP|id=${Uri.encodeComponent(m.id)}';
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
                  l.isArabic ? 'رمز التطبيق المصغر' : 'Mini‑app QR code',
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
                      final sp = await SharedPreferences.getInstance();
                      var txt = l.isArabic
                          ? 'اكتشف ${m.title(isArabic: true)} في تطبيق Shamell.'
                          : 'Check out ${m.title(isArabic: false)} in the Shamell super app.';
                      if (!txt.contains('#')) {
                        if (l.isArabic) {
                          txt += ' #شامل_الخدمات #MiniApp';
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
                      // a Mini‑app card and allow tap-to-open.
                      txt += '\nshamell://miniapp/${m.id}';
                      await sp.setString('moments_preset_text', txt);
                    } catch (_) {}
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MomentsPage(baseUrl: widget.baseUrl),
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
