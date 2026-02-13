import 'dart:convert';
import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'moments_page.dart';
import 'call_signaling.dart';
import '../mini_apps/payments/payments_shell.dart';
import 'design_tokens.dart';

class RedpacketCampaignsPage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final String accountName;

  const RedpacketCampaignsPage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    required this.accountName,
  });

  @override
  State<RedpacketCampaignsPage> createState() => _RedpacketCampaignsPageState();
}

class _RedpacketCampaignsPageState extends State<RedpacketCampaignsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _statsById =
      <String, Map<String, dynamic>>{};
  final Map<String, List<Map<String, dynamic>>> _topMomentsById =
      <String, List<Map<String, dynamic>>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items = const <Map<String, dynamic>>[];
    });
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/official_accounts/${Uri.encodeComponent(widget.accountId)}/campaigns',
      );
      final r = await http.get(uri);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = r.body.isNotEmpty ? r.body : 'HTTP ${r.statusCode}';
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['campaigns'] is List) {
        raw = decoded['campaigns'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final items = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        items.add(e.cast<String, dynamic>());
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      // Best-effort prefetch of campaign stats so that merchant-level
      // insights can be shown without having to open each campaign.
      _prefetchAllStats();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = sanitizeExceptionForUi(error: e);
      });
    }
  }

  void _prefetchAllStats() {
    try {
      final seen = <String>{};
      for (final c in _items) {
        final cid = (c['id'] ?? '').toString();
        if (cid.isEmpty) continue;
        if (seen.contains(cid)) continue;
        if (_statsById.containsKey(cid)) continue;
        seen.add(cid);
        // Fire and forget; individual failures are acceptable.
        // ignore: discarded_futures
        _loadStats(cid);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadStats(String campaignId) async {
    if (_statsById.containsKey(campaignId)) {
      return _statsById[campaignId];
    }
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/official_accounts/${Uri.encodeComponent(widget.accountId)}/campaigns/${Uri.encodeComponent(campaignId)}/stats',
      );
      final r = await http.get(uri);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return null;
      final m = decoded.cast<String, dynamic>();
      setState(() {
        _statsById[campaignId] = m;
      });
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadTopMoments(
    String campaignId,
  ) async {
    if (_topMomentsById.containsKey(campaignId)) {
      return _topMomentsById[campaignId]!;
    }
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/official_accounts/${Uri.encodeComponent(widget.accountId)}/campaigns/${Uri.encodeComponent(campaignId)}/top_moments',
      );
      final r = await http.get(uri);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return const <Map<String, dynamic>>[];
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['items'] is List) {
        raw = decoded['items'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final list = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) {
          list.add(e.cast<String, dynamic>());
        }
      }
      setState(() {
        _topMomentsById[campaignId] = list;
      });
      return list;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _showCampaignInsights(Map<String, dynamic> c) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final cid = (c['id'] ?? '').toString();
    if (cid.isEmpty) return;
    final title = (c['title'] ?? '').toString();
    final defAmt = c['default_amount_cents'];
    final defCount = c['default_count'];
    final created = (c['created_at'] ?? '').toString();
    final isActive = (c['active'] as bool?) ?? true;
    final stats = await _loadStats(cid);
    final momentsTotal = (stats?['moments_shares_total'] is num)
        ? (stats?['moments_shares_total'] as num).toInt()
        : 0;
    final moments30 = (stats?['moments_shares_30d'] is num)
        ? (stats?['moments_shares_30d'] as num).toInt()
        : 0;
    final uniqTotal = (stats?['moments_unique_sharers_total'] is num)
        ? (stats?['moments_unique_sharers_total'] as num).toInt()
        : 0;
    final uniq30 = (stats?['moments_unique_sharers_30d'] is num)
        ? (stats?['moments_unique_sharers_30d'] as num).toInt()
        : 0;
    final lastShare = (stats?['moments_last_share_ts'] ?? '').toString();
    final pkIssued = (stats?['payments_total_packets_issued'] is num)
        ? (stats?['payments_total_packets_issued'] as num).toInt()
        : 0;
    final pkClaimed = (stats?['payments_total_packets_claimed'] is num)
        ? (stats?['payments_total_packets_claimed'] as num).toInt()
        : 0;
    final amtTotal = (stats?['payments_total_amount_cents'] is num)
        ? (stats?['payments_total_amount_cents'] as num).toInt()
        : 0;
    final amtClaimed = (stats?['payments_claimed_amount_cents'] is num)
        ? (stats?['payments_claimed_amount_cents'] as num).toInt()
        : 0;
    final pkIssued30 = (stats?['payments_total_packets_issued_30d'] is num)
        ? (stats?['payments_total_packets_issued_30d'] as num).toInt()
        : 0;
    final pkClaimed30 = (stats?['payments_total_packets_claimed_30d'] is num)
        ? (stats?['payments_total_packets_claimed_30d'] as num).toInt()
        : 0;
    final amtTotal30 = (stats?['payments_total_amount_cents_30d'] is num)
        ? (stats?['payments_total_amount_cents_30d'] as num).toInt()
        : 0;
    final amtClaimed30 = (stats?['payments_claimed_amount_cents_30d'] is num)
        ? (stats?['payments_claimed_amount_cents_30d'] as num).toInt()
        : 0;
    final topMoments = await _loadTopMoments(cid);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String _fmtAmt(int cents) {
          if (cents <= 0) {
            return isAr ? 'لا بيانات' : 'No data';
          }
          final major = cents / 100.0;
          return major.toStringAsFixed(2);
        }

        Widget pill(IconData icon, String label) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: theme.colorScheme.primary.withValues(alpha: .85),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          );
        }

        final pills = <Widget>[
          pill(
            Icons.campaign_outlined,
            isAr
                ? 'الحالة: ${isActive ? 'نشطة' : 'متوقفة'}'
                : 'Status: ${isActive ? 'Active' : 'Inactive'}',
          ),
        ];
        if (defAmt is num && defAmt > 0) {
          pills.add(
            pill(
              Icons.account_balance_wallet_outlined,
              isAr
                  ? 'إجمالي افتراضي: ${_fmtAmt(defAmt.toInt())}'
                  : 'Default total: ${_fmtAmt(defAmt.toInt())}',
            ),
          );
        }
        if (defCount is num && defCount > 0) {
          pills.add(
            pill(
              Icons.group_outlined,
              isAr
                  ? 'عدد المستلمين: ${defCount.toInt()}'
                  : 'Recipients: ${defCount.toInt()}',
            ),
          );
        }
        if (created.isNotEmpty) {
          pills.add(
            pill(
              Icons.schedule_outlined,
              isAr ? 'أُنشئت: $created' : 'Created: $created',
            ),
          );
        }
        if (momentsTotal > 0 || moments30 > 0) {
          pills.add(
            pill(
              Icons.photo_outlined,
              isAr
                  ? 'مشاركات اللحظات: $momentsTotal (٣٠ي: $moments30)'
                  : 'Moments shares: $momentsTotal (30d: $moments30)',
            ),
          );
        }
        if (uniqTotal > 0 || uniq30 > 0) {
          pills.add(
            pill(
              Icons.group_outlined,
              isAr
                  ? 'مستخدمون فريدون: $uniqTotal (٣٠ي: $uniq30)'
                  : 'Unique users: $uniqTotal (30d: $uniq30)',
            ),
          );
        }
        if (pkIssued > 0 || pkClaimed > 0) {
          pills.add(
            pill(
              Icons.redeem_outlined,
              isAr
                  ? 'الحزم: صادرة $pkIssued · مُطالبة $pkClaimed'
                  : 'Packets: issued $pkIssued · claimed $pkClaimed',
            ),
          );
        }
        if (amtTotal > 0 || amtClaimed > 0) {
          pills.add(
            pill(
              Icons.attach_money_outlined,
              isAr
                  ? 'المبالغ: إجمالي ${_fmtAmt(amtTotal)} · مُطالبة ${_fmtAmt(amtClaimed)}'
                  : 'Amounts: total ${_fmtAmt(amtTotal)} · claimed ${_fmtAmt(amtClaimed)}',
            ),
          );
        }
        if (pkIssued30 > 0 || pkClaimed30 > 0) {
          pills.add(
            pill(
              Icons.timelapse_outlined,
              isAr
                  ? 'الحزم (٣٠ يوماً): صادرة $pkIssued30 · مُطالبة $pkClaimed30'
                  : 'Packets (30d): issued $pkIssued30 · claimed $pkClaimed30',
            ),
          );
        }
        if (amtTotal30 > 0 || amtClaimed30 > 0) {
          pills.add(
            pill(
              Icons.account_balance_wallet_outlined,
              isAr
                  ? 'المبالغ (٣٠ يوماً): إجمالي ${_fmtAmt(amtTotal30)} · مُطالبة ${_fmtAmt(amtClaimed30)}'
                  : 'Amounts (30d): total ${_fmtAmt(amtTotal30)} · claimed ${_fmtAmt(amtClaimed30)}',
            ),
          );
        }
        if (lastShare.isNotEmpty) {
          pills.add(
            pill(
              Icons.access_time_outlined,
              isAr
                  ? 'آخر مشاركة لحظات: $lastShare'
                  : 'Last Moments share: $lastShare',
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title.isNotEmpty ? title : cid,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      cid,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: pills,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isAr
                        ? 'تعرض هذه النظرة العامة تأثير الحملة على نمط Shamell: ارتباط بين مشاركات اللحظات وحزم الحمراء الصادرة والمطالبة بها.'
                        : 'This overview shows the Shamell‑style impact of your campaign, combining Moments shares with issued and claimed red‑packets.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                  if (topMoments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      isAr
                          ? 'أعلى منشورات اللحظات لهذه الحملة'
                          : 'Top Moments for this campaign',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...topMoments.take(3).map((m) {
                      final pid = (m['post_id'] ?? '').toString();
                      final text = (m['text'] ?? '').toString();
                      final likes =
                          (m['likes'] is num) ? (m['likes'] as num).toInt() : 0;
                      final comments = (m['comments'] is num)
                          ? (m['comments'] as num).toInt()
                          : 0;
                      final ts = (m['ts'] ?? '').toString();
                      final meta = <String>[];
                      if (likes > 0) {
                        meta.add(
                          isAr ? 'إعجابات: $likes' : 'Likes: $likes',
                        );
                      }
                      if (comments > 0) {
                        meta.add(
                          isAr ? 'تعليقات: $comments' : 'Comments: $comments',
                        );
                      }
                      if (ts.isNotEmpty) {
                        meta.add(ts);
                      }
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.photo_library_outlined,
                          size: 20,
                        ),
                        title: Text(
                          text.isNotEmpty
                              ? text
                              : (isAr ? 'منشور لحظات' : 'Moments post'),
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
                          Navigator.of(ctx).pop();
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareCampaignToMoments(String campaignId) async {
    final l = L10n.of(context);
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/redpacket/campaigns/${Uri.encodeComponent(campaignId)}/moments_template',
      );
      final r = await http.get(uri);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return;
      final isAr = l.isArabic;
      final txt =
          (decoded[isAr ? 'text_ar' : 'text_en'] ?? '').toString().trim();
      if (txt.isEmpty) return;
      final sp = await SharedPreferences.getInstance();
      await sp.setString('moments_preset_text', txt);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MomentsPage(baseUrl: widget.baseUrl),
        ),
      );
    } catch (_) {}
  }

  Future<void> _openIssueInWallet(String campaignId) async {
    final l = L10n.of(context);
    try {
      final sp = await SharedPreferences.getInstance();
      final walletId = sp.getString('wallet_id') ?? '';
      if (walletId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'يرجى إعداد المحفظة أولاً.'
                  : 'Please set up your wallet first.',
            ),
          ),
        );
        return;
      }
      final devId = await CallSignalingClient.loadDeviceId();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentsPage(
            widget.baseUrl,
            walletId,
            devId ?? 'device',
            initialSection: 'redpacket:$campaignId',
          ),
        ),
      );
    } catch (_) {}
  }

  Widget? _buildMerchantSummaryCard(BuildContext context) {
    if (_items.isEmpty) return null;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    int total = 0;
    int active = 0;
    int defPackets = 0;
    int defBudgetCents = 0;
    int momentsTotal = 0;
    int moments30 = 0;
    int pkIssued = 0;
    int pkClaimed = 0;
    int amtTotal = 0;
    int amtClaimed = 0;
    int pkIssued30 = 0;
    int pkClaimed30 = 0;
    int amtTotal30 = 0;
    int amtClaimed30 = 0;
    for (final c in _items) {
      total++;
      final isActive = (c['active'] as bool?) ?? true;
      if (isActive) active++;
      final defAmt = c['default_amount_cents'];
      final defCount = c['default_count'];
      if (defAmt is num && defCount is num && defAmt > 0 && defCount > 0) {
        final amt = defAmt.toInt();
        final cnt = defCount.toInt();
        defPackets += cnt;
        defBudgetCents += amt * cnt;
      }
      final cid = (c['id'] ?? '').toString();
      if (cid.isEmpty) continue;
      final stats = _statsById[cid];
      if (stats == null) continue;
      final mt = stats['moments_shares_total'];
      final m30 = stats['moments_shares_30d'];
      final pi = stats['payments_total_packets_issued'];
      final pc = stats['payments_total_packets_claimed'];
      final at = stats['payments_total_amount_cents'];
      final ac = stats['payments_claimed_amount_cents'];
      final pi30 = stats['payments_total_packets_issued_30d'];
      final pc30 = stats['payments_total_packets_claimed_30d'];
      final at30 = stats['payments_total_amount_cents_30d'];
      final ac30 = stats['payments_claimed_amount_cents_30d'];
      if (mt is num) momentsTotal += mt.toInt();
      if (m30 is num) moments30 += m30.toInt();
      if (pi is num) pkIssued += pi.toInt();
      if (pc is num) pkClaimed += pc.toInt();
      if (at is num) amtTotal += at.toInt();
      if (ac is num) amtClaimed += ac.toInt();
      if (pi30 is num) pkIssued30 += pi30.toInt();
      if (pc30 is num) pkClaimed30 += pc30.toInt();
      if (at30 is num) amtTotal30 += at30.toInt();
      if (ac30 is num) amtClaimed30 += ac30.toInt();
    }
    String _fmtCents(int cents) {
      if (cents <= 0) return '0';
      final major = cents / 100.0;
      return major.toStringAsFixed(2);
    }

    final chips = <Widget>[
      _merchantChip(
        context,
        Icons.campaign_outlined,
        l.isArabic
            ? 'حملات نشطة: $active / $total'
            : 'Active campaigns: $active / $total',
      ),
    ];
    if (defPackets > 0) {
      chips.add(
        _merchantChip(
          context,
          Icons.people_alt_outlined,
          l.isArabic
              ? 'حزم افتراضية: $defPackets'
              : 'Default packets: $defPackets',
        ),
      );
    }
    if (defBudgetCents > 0) {
      chips.add(
        _merchantChip(
          context,
          Icons.account_balance_wallet_outlined,
          l.isArabic
              ? 'ميزانية افتراضية: ${_fmtCents(defBudgetCents)}'
              : 'Default budget: ${_fmtCents(defBudgetCents)}',
        ),
      );
    }
    if (momentsTotal > 0 || moments30 > 0) {
      chips.add(
        _merchantChip(
          context,
          Icons.photo_outlined,
          l.isArabic
              ? 'مشاركات اللحظات: $momentsTotal (٣٠ي: $moments30)'
              : 'Moments shares: $momentsTotal (30d: $moments30)',
        ),
      );
    }
    if (pkIssued > 0 || pkClaimed > 0) {
      final rate = pkIssued > 0 ? ((pkClaimed * 100) ~/ pkIssued) : 0;
      chips.add(
        _merchantChip(
          context,
          Icons.redeem_outlined,
          l.isArabic
              ? 'الحزم: صادرة $pkIssued · مُطالبة $pkClaimed (معدل $rate٪)'
              : 'Packets: issued $pkIssued · claimed $pkClaimed (rate $rate%)',
        ),
      );
    }
    if (pkIssued30 > 0 || pkClaimed30 > 0) {
      final rate30 = pkIssued30 > 0 ? ((pkClaimed30 * 100) ~/ pkIssued30) : 0;
      chips.add(
        _merchantChip(
          context,
          Icons.timelapse_outlined,
          l.isArabic
              ? 'حزم (٣٠ يوماً): صادرة $pkIssued30 · مُطالبة $pkClaimed30 (معدل $rate30٪)'
              : 'Packets (30d): issued $pkIssued30 · claimed $pkClaimed30 (rate $rate30%)',
        ),
      );
    }
    if (amtTotal30 > 0 || amtClaimed30 > 0) {
      chips.add(
        _merchantChip(
          context,
          Icons.savings_outlined,
          l.isArabic
              ? 'مبالغ (٣٠ يوماً): إجمالي ${_fmtCents(amtTotal30)} · مُطالبة ${_fmtCents(amtClaimed30)}'
              : 'Amounts (30d): total ${_fmtCents(amtTotal30)} · claimed ${_fmtCents(amtClaimed30)}',
        ),
      );
    }
    if (amtTotal > 0 || amtClaimed > 0) {
      chips.add(
        _merchantChip(
          context,
          Icons.attach_money_outlined,
          l.isArabic
              ? 'المبالغ: إجمالي ${_fmtCents(amtTotal)} · مُطالبة ${_fmtCents(amtClaimed)}'
              : 'Amounts: total ${_fmtCents(amtTotal)} · claimed ${_fmtCents(amtClaimed)}',
        ),
      );
    }
    if (chips.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic
                    ? 'نظرة عامة على الحزم الحمراء لهذا الحساب'
                    : 'Red‑packet overview for this account',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: chips,
              ),
              const SizedBox(height: 8),
              Text(
                l.isArabic
                    ? 'هذه الإحصاءات تظهر تأثير كل الحملات معاً (أسلوب شبيه بـ Shamell)، استناداً إلى بيانات اللحظات والدفع المتاحة.'
                    : 'These KPIs summarise the combined impact of all campaigns (Shamell‑style), based on available Moments and payments data.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _merchantChip(BuildContext context, IconData icon, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: theme.colorScheme.primary.withValues(alpha: .85),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    final title = isArabic ? 'حملات الحزم الحمراء' : 'Red‑packet campaigns';
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : (Colors.grey[100] ?? Colors.white);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      backgroundColor: bgColor,
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          Expanded(
            child: _items.isEmpty && !_loading
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _items.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        final summary = _buildMerchantSummaryCard(context);
                        if (summary == null) {
                          return const SizedBox.shrink();
                        }
                        return summary;
                      }
                      final idx = i - 1;
                      if (idx < 0 || idx >= _items.length) {
                        return const SizedBox.shrink();
                      }
                      final c = _items[idx];
                      final cid = (c['id'] ?? '').toString();
                      final title = (c['title'] ?? '').toString();
                      final defAmt = c['default_amount_cents'];
                      final defCount = c['default_count'];
                      final isActive = (c['active'] as bool?) ?? true;
                      final created = (c['created_at'] ?? '').toString();
                      final isAr = l.isArabic;
                      final statusLabel = isActive
                          ? (isAr ? 'نشطة' : 'Active')
                          : (isAr ? 'متوقفة' : 'Inactive');
                      final subtitleParts = <String>[];
                      if (defAmt is num && defAmt > 0) {
                        final major = (defAmt / 100.0).toStringAsFixed(2);
                        subtitleParts.add(
                          isAr
                              ? 'إجمالي افتراضي: $major'
                              : 'Default total: $major',
                        );
                      }
                      if (defCount is num && defCount > 0) {
                        subtitleParts.add(
                          isAr
                              ? 'عدد المستلمين: ${defCount.toInt()}'
                              : 'Recipients: ${defCount.toInt()}',
                        );
                      }
                      if (created.isNotEmpty) {
                        subtitleParts.add(
                          isAr ? 'أنشئت: $created' : 'Created: $created',
                        );
                      }
                      final subtitle = subtitleParts.isEmpty
                          ? ''
                          : subtitleParts.join(' · ');
                      final Color statusColor = isActive
                          ? Tokens.colorPayments
                          : theme.colorScheme.onSurface.withValues(alpha: .60);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.red.shade50,
                                      ),
                                      child: Icon(
                                        Icons.card_giftcard,
                                        size: 20,
                                        color: Colors.red.shade400,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title.isNotEmpty
                                                      ? title
                                                      : cid,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.titleSmall
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: statusColor.withValues(
                                                      alpha: .12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: Text(
                                                  statusLabel,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (subtitle.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              subtitle,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withValues(alpha: .70),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (isActive)
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.card_giftcard_outlined,
                                          size: 16,
                                        ),
                                        onPressed: cid.isEmpty
                                            ? null
                                            : () => _openIssueInWallet(cid),
                                        label: Text(
                                          isAr ? 'إصدار حزم' : 'Issue packets',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
                                        size: 16,
                                      ),
                                      onPressed: cid.isEmpty
                                          ? null
                                          : () => _shareCampaignToMoments(cid),
                                      label: Text(
                                        isAr
                                            ? 'مشاركة في اللحظات'
                                            : 'Share to Moments',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      icon: const Icon(
                                        Icons.insights_outlined,
                                        size: 16,
                                      ),
                                      onPressed: cid.isEmpty
                                          ? null
                                          : () => _showCampaignInsights(c),
                                      label: Text(
                                        isAr ? 'التحليلات' : 'Insights',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 40,
              color: theme.colorScheme.onSurface.withValues(alpha: .45),
            ),
            const SizedBox(height: 8),
            Text(
              l.isArabic
                  ? 'لا توجد حملات حزم حمراء نشطة لهذا الحساب.'
                  : 'There are no active red‑packet campaigns for this account.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
