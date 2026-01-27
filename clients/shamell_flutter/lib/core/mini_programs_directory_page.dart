import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'mini_program_runtime.dart';

class MiniProgramsDirectoryPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final void Function(String modId) onOpenMod;

  const MiniProgramsDirectoryPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.onOpenMod,
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

  @override
  void initState() {
    super.initState();
    _load();
    _loadPinned();
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
      final ids = sp.getStringList('pinned_miniapps') ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _pinned = ids.toSet();
      });
    } catch (_) {}
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
      const pinnedKey = 'pinned_miniapps';
      const orderKey = 'mini_programs.pinned_order';
      final curPinnedRaw = sp.getStringList(pinnedKey) ?? const <String>[];
      final pinnedList = <String>[];
      final pinnedSet = <String>{};
      for (final raw in curPinnedRaw) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        if (pinnedSet.add(id)) pinnedList.add(id);
      }
      final isPinned = pinnedSet.contains(appId);
      pinnedList.removeWhere((e) => e == appId);
      if (!isPinned) {
        pinnedList.insert(0, appId);
      }
      await sp.setStringList(pinnedKey, pinnedList);

      final curOrderRaw = sp.getStringList(orderKey) ?? const <String>[];
      final orderList = <String>[];
      final orderSet = <String>{};
      for (final raw in curOrderRaw) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        if (orderSet.add(id)) orderList.add(id);
      }
      orderList.removeWhere((e) => e == appId);
      if (!isPinned) {
        orderList.insert(0, appId);
      }
      final nextOrder = orderList.where(pinnedList.contains).toList();
      await sp.setStringList(orderKey, nextOrder);
      if (!mounted) return;
      setState(() {
        _pinned = pinnedList.toSet();
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _programs = const <Map<String, dynamic>>[];
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs');
      final resp = await http.get(uri);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        setState(() {
          _error = resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}';
          _loading = false;
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
        _programs = list;
        _loading = false;
      });
    } catch (e) {
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
      if (haystack.contains('taxi') ||
          haystack.contains('ride') ||
          haystack.contains('transport')) {
        cats.add('transport');
      } else if (haystack.contains('food') ||
          haystack.contains('restaurant') ||
          haystack.contains('delivery')) {
        cats.add('food');
      } else if (haystack.contains('stay') ||
          haystack.contains('hotel') ||
          haystack.contains('travel')) {
        cats.add('stays');
      } else if (haystack.contains('wallet') ||
          haystack.contains('pay') ||
          haystack.contains('payment') ||
          haystack.contains('payments')) {
        cats.add('wallet');
      }
    }
    if (cats.isEmpty) {
      return const SizedBox.shrink();
    }
    String labelFor(String key) {
      switch (key) {
        case 'transport':
          return isArabic ? 'تاكسي والنقل' : 'Taxi & transport';
        case 'food':
          return isArabic ? 'خدمة الطعام' : 'Food service';
        case 'stays':
          return isArabic ? 'الإقامات والسفر' : 'Stays & travel';
        case 'wallet':
          return isArabic ? 'المحفظة والمدفوعات' : 'Wallet & payments';
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
      if (term.isEmpty) return true;
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
            matches = hay.contains('taxi') ||
                hay.contains('ride') ||
                hay.contains('transport');
            break;
          case 'food':
            matches = hay.contains('food') ||
                hay.contains('restaurant') ||
                hay.contains('delivery');
            break;
          case 'stays':
            matches = hay.contains('stay') ||
                hay.contains('hotel') ||
                hay.contains('travel');
            break;
          case 'wallet':
            matches = hay.contains('wallet') ||
                hay.contains('pay') ||
                hay.contains('payment') ||
                hay.contains('payments');
            break;
          default:
            matches = false;
        }
        if (!matches) return false;
      }
      return id.contains(term) ||
          titleEn.contains(term) ||
          titleAr.contains(term) ||
          ownerName.contains(term);
    }).toList()
      ..sort((a, b) {
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
        child: Text(
          l.isArabic
              ? 'لا توجد برامج مصغّرة مسجّلة بعد.'
              : 'No mini‑programs registered yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .6),
          ),
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
        final releasedVersion = (p['released_version'] ?? '').toString();
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
        if (haystack.contains('taxi') ||
            haystack.contains('ride') ||
            haystack.contains('transport')) {
          categoryLabel = isArabic ? 'تاكسي والنقل' : 'Taxi & transport';
        } else if (haystack.contains('food') ||
            haystack.contains('restaurant') ||
            haystack.contains('delivery')) {
          categoryLabel = isArabic ? 'خدمة الطعام' : 'Food service';
        } else if (haystack.contains('stay') ||
            haystack.contains('hotel') ||
            haystack.contains('travel')) {
          categoryLabel = isArabic ? 'الإقامات والسفر' : 'Stays & travel';
        } else if (haystack.contains('wallet') ||
            haystack.contains('pay') ||
            haystack.contains('payment') ||
            haystack.contains('payments')) {
          categoryLabel = isArabic ? 'المحفظة والمدفوعات' : 'Wallet & payments';
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
