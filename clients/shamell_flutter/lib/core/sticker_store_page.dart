import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'sticker_store.dart';

class StickerStorePage extends StatefulWidget {
  final String baseUrl;
  final String? initialPackId;
  const StickerStorePage({
    super.key,
    required this.baseUrl,
    this.initialPackId,
  });

  @override
  State<StickerStorePage> createState() => _StickerStorePageState();
}

class _StickerStorePageState extends State<StickerStorePage> {
  bool _loading = true;
  List<String> _installed = const <String>[];
  Map<String, int> _usage = const <String, int>{};
  Map<String, Map<String, dynamic>> _remoteMeta =
      const <String, Map<String, dynamic>>{};
  String? _purchasingPackId;
  final Set<String> _copiedForShare = <String>{};
  String _filterTag = 'all';
  bool _filterInstalledOnly = false;
  List<StickerPack> _featured = const <StickerPack>[];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final ids = await loadInstalledStickerPackIds();
    final usage = await loadAllStickerUsage();
    // Best-effort fetch of remote catalog metadata and ownership flags.
    final meta = <String, Map<String, dynamic>>{};
    try {
      final uri = Uri.parse('${widget.baseUrl}/stickers/packs');
      final r = await http.get(uri);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(r.body);
        List<dynamic> raw = const <dynamic>[];
        if (decoded is Map && decoded['packs'] is List) {
          raw = decoded['packs'] as List;
        } else if (decoded is List) {
          raw = decoded;
        }
        for (final e in raw) {
          if (e is! Map) continue;
          final m = e.cast<String, dynamic>();
          final id = (m['id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          meta[id] = m;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _installed = ids;
      _usage = usage;
      _remoteMeta = meta;
      _loading = false;
      _purchasingPackId = null;
      _featured = _computeFeaturedPacks();
    });
  }

  List<StickerPack> _computeFeaturedPacks() {
    final featured = <StickerPack>[];
    final recommendedIds = _remoteMeta.entries
        .where((e) => e.value['recommended'] == true)
        .map((e) => e.key)
        .toSet();
    if (recommendedIds.isNotEmpty) {
      for (final pack in kStickerPacks) {
        if (recommendedIds.contains(pack.id)) {
          featured.add(pack);
        }
      }
    }
    if (featured.isEmpty && _usage.isNotEmpty) {
      final entries = _usage.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries.take(4)) {
        final pack = kStickerPacks.firstWhere((p) => p.id == e.key,
            orElse: () => kStickerPacks.first);
        featured.add(pack);
      }
    }
    if (featured.isEmpty) {
      featured.addAll(kStickerPacks.take(3));
    }
    return featured;
  }

  Future<void> _togglePack(String id) async {
    final installed = List<String>.from(_installed);
    if (installed.contains(id)) {
      installed.remove(id);
    } else {
      installed.add(id);
    }
    await saveInstalledStickerPackIds(installed);
    if (!mounted) return;
    setState(() {
      _installed = installed;
    });
  }

  Future<void> _sharePack(String packId) async {
    final l = L10n.of(context);
    final isAr = l.isArabic;
    final uri = Uri.parse('shamell://stickers/pack/$packId');
    try {
      final data = ClipboardData(text: uri.toString());
      await Clipboard.setData(data);
      if (!mounted) return;
      setState(() {
        _copiedForShare.add(packId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'رابط حزمة الملصقات نُسخ – ألصقه في الدردشة لإرساله إلى صديق.'
                : 'Sticker pack link copied – paste it into a chat to send it to a friend.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'تعذر نسخ رابط حزمة الملصقات.'
                : 'Could not copy sticker pack link.',
          ),
        ),
      );
    }
  }

  Future<void> _buyPack(String packId) async {
    final l = L10n.of(context);
    final isAr = l.isArabic;
    String? walletId;
    try {
      final sp = await SharedPreferences.getInstance();
      walletId = sp.getString('wallet_id');
    } catch (_) {
      walletId = null;
    }
    if (walletId == null || walletId.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'عيّن محفظتك أولاً في قسم المدفوعات.'
                : 'Please configure your wallet in the Payments section first.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _purchasingPackId = packId;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/stickers/purchase');
      final body = jsonEncode({
        'pack_id': packId,
        'from_wallet_id': walletId,
      });
      final r = await http.post(
        uri,
        headers: const {"content-type": "application/json"},
        body: body,
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        // Ensure the pack is marked as installed locally.
        final installed = List<String>.from(_installed);
        if (!installed.contains(packId)) {
          installed.add(packId);
          await saveInstalledStickerPackIds(installed);
        }
        if (!mounted) return;
        setState(() {
          _installed = installed;
        });
        // Refresh remote metadata (owned flag etc.).
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr ? 'تم شراء الحزمة بنجاح.' : 'Sticker pack purchased.',
            ),
          ),
        );
      } else {
        if (!mounted) return;
        String msg;
        try {
          final decoded = jsonDecode(r.body);
          if (decoded is Map && decoded['detail'] is String) {
            msg = decoded['detail'] as String;
          } else {
            msg = '${r.statusCode}: ${r.reasonPhrase ?? 'error'}';
          }
        } catch (_) {
          msg = '${r.statusCode}: ${r.reasonPhrase ?? 'error'}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? 'تعذر إتمام عملية الشراء: $msg'
                  : 'Could not purchase pack: $msg',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'تعذر إتمام عملية الشراء.' : 'Could not purchase pack.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _purchasingPackId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    int maxUsage = 0;
    _usage.forEach((_, count) {
      if (count > maxUsage) {
        maxUsage = count;
      }
    });

    final availableTags = <String>{};
    for (final pack in kStickerPacks) {
      for (final tag in pack.tags) {
        final t = tag.trim();
        if (t.isNotEmpty) {
          availableTags.add(t);
        }
      }
    }
    final filteredPacks = kStickerPacks.where((pack) {
      if (_filterInstalledOnly && !_installed.contains(pack.id)) {
        return false;
      }
      if (_filterTag != 'all' && !pack.tags.contains(_filterTag)) {
        return false;
      }
      return true;
    }).toList();

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView.builder(
        controller: _scrollController,
        itemCount: filteredPacks.length,
        itemBuilder: (ctx, i) {
          final pack = filteredPacks[i];
          final installed = _installed.contains(pack.id);
          final title = isAr ? pack.nameAr : pack.nameEn;
          final preview = pack.stickers.take(6).join(' ');
          final usage = _usage[pack.id] ?? 0;
          final isTop = usage > 0 && usage == maxUsage;
          final meta = _remoteMeta[pack.id];
          int priceCents = 0;
          String currency = 'SYP';
          bool recommended = false;
          bool owned = false;
          if (meta != null) {
            final p = meta['price_cents'];
            if (p is num) {
              priceCents = p.toInt();
            }
            final cur = (meta['currency'] ?? '').toString().trim();
            if (cur.isNotEmpty) {
              currency = cur;
            }
            recommended = meta['recommended'] == true;
            owned = meta['owned'] == true;
          }
          final usageLabel = usage > 0
              ? (isAr ? 'مرات الاستخدام: $usage' : 'Used $usage times')
              : (isAr ? 'لم يُستخدم بعد' : 'Not used yet');
          final bool isInitialTarget = widget.initialPackId != null &&
              widget.initialPackId!.isNotEmpty &&
              widget.initialPackId == pack.id;
          return ListTile(
            leading: CircleAvatar(
              child: Text(
                pack.stickers.isNotEmpty ? pack.stickers.first : '🙂',
                style: const TextStyle(fontSize: 20),
              ),
            ),
            title: Row(
              children: [
                Expanded(child: Text(title)),
                if (isInitialTarget)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: theme.colorScheme.primary.withValues(alpha: .10),
                    ),
                    child: Text(
                      isAr ? 'من الرابط' : 'From link',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (installed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color:
                              theme.colorScheme.primary.withValues(alpha: .08),
                        ),
                        child: Text(
                          isAr ? 'مثبّت' : 'Installed',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    if (!installed && owned)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color:
                              theme.colorScheme.primary.withValues(alpha: .06),
                        ),
                        child: Text(
                          isAr ? 'مملوكة' : 'Owned',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .85),
                          ),
                        ),
                      ),
                    if (isTop)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: theme.colorScheme.secondary
                              .withValues(alpha: .10),
                        ),
                        child: Text(
                          isAr ? 'الأكثر استخداماً' : 'Most used',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                    if (recommended && !installed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color:
                              theme.colorScheme.primary.withValues(alpha: .06),
                        ),
                        child: Text(
                          isAr ? 'مقترَح' : 'Featured',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .85),
                          ),
                        ),
                      ),
                  ],
                ),
                if (priceCents > 0)
                  Text(
                    isAr
                        ? 'السعر: ${(priceCents / 100).toStringAsFixed(2)} $currency'
                        : 'Price: ${(priceCents / 100).toStringAsFixed(2)} $currency',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  )
                else
                  Text(
                    isAr ? 'مجاني' : 'Free',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                Text(
                  usageLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (priceCents > 0 && !owned)
                  FilledButton.tonal(
                    onPressed: _purchasingPackId == pack.id
                        ? null
                        : () => _buyPack(pack.id),
                    child: _purchasingPackId == pack.id
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
                            isAr ? 'شراء وتثبيت' : 'Buy & install',
                          ),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => _togglePack(pack.id),
                    child: Text(
                      installed
                          ? (isAr ? 'إزالة' : 'Remove')
                          : (isAr ? 'تثبيت' : 'Install'),
                    ),
                  ),
                TextButton(
                  onPressed: () => _sharePack(pack.id),
                  child: Text(
                    _copiedForShare.contains(pack.id)
                        ? (isAr ? 'نُسخ الرابط' : 'Link copied')
                        : (isAr ? 'إرسال إلى صديق' : 'Send to friend'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final installedCount = _installed.length;
    String? topPackLabel;
    int totalUsage = 0;
    String? topPackName;
    int topPackUsage = 0;
    _usage.forEach((id, count) {
      totalUsage += count;
      if (count > topPackUsage) {
        topPackUsage = count;
        final pack = kStickerPacks.firstWhere((p) => p.id == id,
            orElse: () => kStickerPacks.first);
        topPackName = isAr ? pack.nameAr : pack.nameEn;
      }
    });
    if (topPackName != null && topPackUsage > 0) {
      topPackLabel = isAr
          ? 'الأكثر استخداماً: $topPackName ($topPackUsage)'
          : 'Most used: $topPackName ($topPackUsage)';
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_emotions_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isAr
                    ? 'الحزم المثبّتة: $installedCount'
                    : 'Installed sticker packs: $installedCount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (_featured.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              isAr ? 'الحزم المميزة' : 'Featured packs',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _featured.map((pack) {
                  final title = isAr ? pack.nameAr : pack.nameEn;
                  final preview =
                      pack.stickers.isNotEmpty ? pack.stickers.first : '🙂';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ActionChip(
                      avatar: Text(
                        preview,
                        style: const TextStyle(fontSize: 18),
                      ),
                      label: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () {
                        setState(() {
                          _filterInstalledOnly = false;
                          _filterTag = 'all';
                        });
                        final index =
                            kStickerPacks.indexWhere((p) => p.id == pack.id);
                        if (index >= 0) {
                          _scrollController.animateTo(
                            index * 96.0,
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (topPackLabel != null || totalUsage > 0) ...[
            const SizedBox(height: 2),
            Text(
              topPackLabel ??
                  (isAr ? 'لا توجد بيانات استخدام بعد.' : 'No usage data yet.'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
              ),
            ),
            if (totalUsage > 0)
              Text(
                isAr
                    ? 'إجمالي الملصقات المرسلة: $totalUsage'
                    : 'Total stickers sent: $totalUsage',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
                ),
              ),
          ],
          if (availableTags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: Text(l.mirsaalStickersFilterAll),
                  selected: !_filterInstalledOnly && _filterTag == 'all',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _filterInstalledOnly = false;
                      _filterTag = 'all';
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(l.mirsaalStickersFilterInstalled),
                  selected: _filterInstalledOnly,
                  onSelected: (sel) {
                    setState(() {
                      _filterInstalledOnly = sel;
                    });
                  },
                ),
                ...availableTags.take(6).map((tag) {
                  final selected = _filterTag == tag;
                  return ChoiceChip(
                    label: Text(tag),
                    selected: selected,
                    onSelected: (sel) {
                      setState(() {
                        _filterTag = sel ? tag : 'all';
                      });
                    },
                  );
                }),
              ],
            ),
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.emoji_emotions_outlined,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              isAr ? 'متجر الملصقات' : 'Sticker store',
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Divider(height: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
