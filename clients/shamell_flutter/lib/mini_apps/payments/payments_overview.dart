import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/history_page.dart';
import '../../core/design_tokens.dart';
import '../../core/perf.dart';
import '../../core/l10n.dart';
import '../../core/ui_kit.dart';
import '../../core/glass.dart';
import 'payments_bills.dart';
import 'payments_receive_pay.dart';
import 'payments_send.dart' show PayActionButton, GroupPayPage;
import 'payments_requests.dart';
import '../../core/moments_page.dart' show MomentsPage;

class PaymentOverviewTab extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String? initialSection;
  const PaymentOverviewTab(
      {super.key,
      required this.baseUrl,
      required this.walletId,
      required this.deviceId,
      this.initialSection});
  @override
  State<PaymentOverviewTab> createState() => _PaymentOverviewTabState();
}

class _PaymentOverviewTabState extends State<PaymentOverviewTab> {
  bool _loading = true;
  int? _balanceCents;
  String _curSym = 'SYP';
  List<Map<String, dynamic>> _recent = [];
  String _out = '';
  int? _savingsCents;
  bool _handledInitialSection = false;
  List<Map<String, String>> _linkedCards = const <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      await _loadPrefs();
      await _loadLinkedCards();
      if (widget.walletId.isNotEmpty) {
        await _loadCachedSnapshot();
        await _loadSnapshot();
      }
      _out = '';
      if (!_handledInitialSection) {
        _handledInitialSection = true;
        await _maybeOpenInitialSection();
      }
    } catch (e) {
      _out = 'Error: $e';
      Perf.action('payments_overview_error');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _maybeOpenInitialSection() async {
    final section = (widget.initialSection ?? '').trim().toLowerCase();
    if (section.isEmpty) return;
    if (!mounted) return;
    if (section == 'redpacket' || section == 'redpacket_history') {
      if (widget.walletId.isEmpty) return;
      final list = _recent
          .where(
              (t) => (t['kind'] ?? '').toString().toLowerCase() == 'redpacket')
          .toList();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HistoryPage(
            baseUrl: widget.baseUrl,
            walletId: widget.walletId,
            initialKind: 'redpacket',
            initialTxns: list.isEmpty ? null : list,
          ),
        ),
      );
    } else if (section.startsWith('redpacket:')) {
      if (widget.walletId.isEmpty) return;
      final parts = section.split(':');
      final campaignId = parts.length > 1 ? parts.sublist(1).join(':') : '';
      final txns = _recent.where((t) {
        if ((t['kind'] ?? '').toString().toLowerCase() != 'redpacket') {
          return false;
        }
        final meta = (t['meta'] ?? '').toString().toLowerCase();
        if (campaignId.isEmpty) return true;
        return meta.contains(campaignId.toLowerCase());
      }).toList();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HistoryPage(
            baseUrl: widget.baseUrl,
            walletId: widget.walletId,
            initialKind: 'redpacket',
            initialTxns: txns.isEmpty ? null : txns,
          ),
        ),
      );
    }
  }

  Future<void> _loadSnapshot() async {
    try {
      final qp = <String, String>{'limit': '25'};
      final uri = Uri.parse('${widget.baseUrl}/wallets/' +
              Uri.encodeComponent(widget.walletId) +
              '/snapshot')
          .replace(queryParameters: qp);
      final r = await http.get(uri, headers: await _hdrPO());
      if (r.statusCode == 200) {
        Perf.action('payments_overview_snapshot_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        await _applySnapshot(j, persist: true, rawBody: r.body);
      } else {
        _out = '${r.statusCode}: ${r.body}';
        Perf.action('payments_overview_snapshot_fail');
      }
      // Savings overview (best-effort)
      try {
        if (widget.walletId.isNotEmpty) {
          final suri = Uri.parse(
              '${widget.baseUrl}/payments/savings/overview?wallet_id=${Uri.encodeComponent(widget.walletId)}');
          final sr = await http.get(suri, headers: await _hdrPO());
          if (sr.statusCode == 200) {
            final sj = jsonDecode(sr.body) as Map<String, dynamic>;
            final sb = sj['savings_balance_cents'];
            if (sb is int) {
              _savingsCents = sb;
            } else if (sb is num) {
              _savingsCents = sb.toInt();
            }
          }
        }
      } catch (_) {}
    } catch (e) {
      _out = 'Error: $e';
      Perf.action('payments_overview_snapshot_error');
    }
  }

  Future<void> _loadCachedSnapshot() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final key = 'wallet_snapshot_${widget.walletId}';
      final raw = sp.getString(key);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      await _applySnapshot(j, persist: false);
      if (mounted) {
        // Sobald Cache-Daten da sind, keinen Spinner mehr anzeigen.
        setState(() => _loading = false);
      }
    } catch (_) {}
  }

  Future<void> _applySnapshot(
    Map<String, dynamic> j, {
    required bool persist,
    String? rawBody,
  }) async {
    try {
      final w = j['wallet'];
      if (w is Map<String, dynamic>) {
        _balanceCents = (w['balance_cents'] ?? 0) as int;
        final cur = (w['currency'] ?? '').toString();
        if (cur.isNotEmpty) _curSym = cur;
      }
      final arr = j['txns'];
      if (arr is List) {
        _recent = arr.whereType<Map<String, dynamic>>().toList();
      }
      if (persist && rawBody != null) {
        final sp = await SharedPreferences.getInstance();
        final key = 'wallet_snapshot_${widget.walletId}';
        await sp.setString(key, rawBody);
      }
    } catch (_) {}
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cs = sp.getString('currency_symbol');
      if (cs != null && cs.isNotEmpty) _curSym = cs;
    } catch (_) {}
  }

  Future<void> _loadLinkedCards() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getStringList('wallet_linked_cards') ?? const <String>[];
      final list = <Map<String, String>>[];
      for (final s in raw) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final label = (m['label'] ?? '').toString();
          final last4 = (m['last4'] ?? '').toString();
          final brand = (m['brand'] ?? '').toString();
          if (label.isEmpty && last4.isEmpty) continue;
          list.add(<String, String>{
            'label': label,
            'last4': last4,
            'brand': brand,
          });
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _linkedCards = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLinkedCards() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = _linkedCards
          .map((m) => jsonEncode(<String, String>{
                'label': m['label'] ?? '',
                'last4': m['last4'] ?? '',
                'brand': m['brand'] ?? '',
              }))
          .toList();
      await sp.setStringList('wallet_linked_cards', list);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await _init();
  }

  Map<String, dynamic>? _computeRecentSummary() {
    try {
      if (_recent.isEmpty || widget.walletId.isEmpty) return null;
      int inC = 0, outC = 0;
      int inCnt = 0, outCnt = 0;
      int rpInC = 0, rpOutC = 0;
      int rpInCnt = 0, rpOutCnt = 0;
      for (final t in _recent) {
        final row = t;
        final cents = (row['amount_cents'] ?? 0) as int;
        final from = (row['from_wallet_id'] ?? '').toString();
        final kind = (row['kind'] ?? '').toString().toLowerCase();
        final isOut = from == widget.walletId;
        final isRedpacket = kind == 'redpacket';
        if (isOut) {
          outC += cents;
          outCnt++;
          if (isRedpacket) {
            rpOutC += cents;
            rpOutCnt++;
          }
        } else {
          inC += cents;
          inCnt++;
          if (isRedpacket) {
            rpInC += cents;
            rpInCnt++;
          }
        }
      }
      return {
        'inC': inC,
        'outC': outC,
        'inCnt': inCnt,
        'outCnt': outCnt,
        'rpInC': rpInC,
        'rpOutC': rpOutC,
        'rpInCnt': rpInCnt,
        'rpOutCnt': rpOutCnt,
      };
    } catch (_) {
      return null;
    }
  }

  void _goToTab(BuildContext context, int index) {
    final ctrl = DefaultTabController.of(context);
    ctrl.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final summary = _computeRecentSummary();
    final children = <Widget>[
      Card(
        color: theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.dividerColor.withValues(
              alpha: isDark ? .28 : .22,
            ),
          ),
        ),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'محفظتك' : 'Wallet & balance',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _walletHero(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (summary != null)
        Card(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.dividerColor.withValues(
                alpha: isDark ? .28 : .22,
              ),
            ),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'ملخص المدفوعات' : 'Payments summary',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _summaryChip(
                      context,
                      label: l.isArabic ? 'خارج المحفظة' : 'Sent',
                      value:
                          '${fmtCents((summary['outC'] ?? 0) as int)} $_curSym · ${(summary['outCnt'] ?? 0)}',
                    ),
                    _summaryChip(
                      context,
                      label: l.isArabic ? 'إلى المحفظة' : 'Received',
                      value:
                          '${fmtCents((summary['inC'] ?? 0) as int)} $_curSym · ${(summary['inCnt'] ?? 0)}',
                    ),
                    _summaryChip(
                      context,
                      label: l.isArabic
                          ? 'حزم حمراء (مرسلة)'
                          : 'Red packets · sent',
                      value:
                          '${fmtCents((summary['rpOutC'] ?? 0) as int)} $_curSym · ${(summary['rpOutCnt'] ?? 0)}',
                    ),
                    _summaryChip(
                      context,
                      label: l.isArabic
                          ? 'حزم حمراء (مستلمة)'
                          : 'Red packets · received',
                      value:
                          '${fmtCents((summary['rpInC'] ?? 0) as int)} $_curSym · ${(summary['rpInCnt'] ?? 0)}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.walletId.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => HistoryPage(
                                  baseUrl: widget.baseUrl,
                                  walletId: widget.walletId,
                                ),
                              ),
                            );
                          },
                    child: Text(
                      l.isArabic
                          ? 'عرض كل الحركات بالتفصيل'
                          : 'Open full payments history',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.primary.withValues(alpha: .85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (summary != null) const SizedBox(height: 12),
      Card(
        color: theme.colorScheme.surface.withValues(alpha: isDark ? .90 : .96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0.5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'إجراءات سريعة' : 'Quick actions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _quickActions(context),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        color: theme.colorScheme.surface.withValues(alpha: isDark ? .90 : .96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0.5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic
                    ? 'تمويل المحفظة والسحب'
                    : 'Wallet funding & cash‑out',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                l.isArabic
                    ? 'شحن الرصيد أو إنشاء رمز سحب نقدي، مشابه لتجربة WeChat Pay.'
                    : 'Top up your balance or create a cash‑out code, similar to WeChat Pay.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PayActionButton(
                      icon: Icons.add_card_outlined,
                      label: l.isArabic ? 'شحن المحفظة' : 'Top up wallet',
                      onTap: widget.walletId.isEmpty
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l.isArabic
                                        ? 'يرجى إعداد المحفظة أولاً.'
                                        : 'Please set up your wallet first.',
                                  ),
                                ),
                              );
                            }
                          : _openTopupSheet,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PayActionButton(
                      icon: Icons.payments_outlined,
                      label: l.isArabic ? 'سحب نقدي (رمز)' : 'Cash out (code)',
                      onTap: () {
                        if (widget.walletId.isEmpty) {
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
                        _openCashoutSheet();
                      },
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_linkedCards.isNotEmpty) ...[
                Text(
                  l.isArabic
                      ? 'بطاقات مرتبطة (محفوظة محلياً)'
                      : 'Linked cards (stored locally)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  ),
                ),
                const SizedBox(height: 4),
                Column(
                  children: _linkedCards.map((c) {
                    final label = (c['label'] ?? '').trim();
                    final last4 = (c['last4'] ?? '').trim();
                    final brand = (c['brand'] ?? '').trim();
                    final title = label.isNotEmpty
                        ? label
                        : (brand.isNotEmpty ? brand : 'Card');
                    final subtitle = last4.isNotEmpty
                        ? (l.isArabic
                            ? 'آخر ٤ أرقام: $last4'
                            : 'Last 4 digits: $last4')
                        : (brand.isNotEmpty ? brand : '');
                    return StandardListTile(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      leading: const Icon(Icons.credit_card_outlined, size: 20),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: subtitle.isEmpty
                          ? null
                          : Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          setState(() {
                            _linkedCards =
                                List<Map<String, String>>.from(_linkedCards)
                                  ..remove(c);
                          });
                          // ignore: discarded_futures
                          _saveLinkedCards();
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_card_outlined, size: 18),
                  label: Text(
                    l.isArabic
                        ? 'إدارة البطاقات المرتبطة'
                        : 'Manage linked cards',
                  ),
                  onPressed: _openManageCardsSheet,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        color: theme.colorScheme.surface.withValues(alpha: isDark ? .90 : .96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0.5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic ? 'الادخار' : 'Savings',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _savingsSection(context),
            ],
          ),
        ),
      ),
      FormSection(
        title: l.isArabic ? 'الحزم الحمراء' : 'Red packets',
        children: [
          Text(
            l.isArabic
                ? 'سجل الحزم الحمراء التي أرسلتها وتلقيتها.'
                : 'History of red packets you sent and received.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .70),
                ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.card_giftcard),
            label: Text(
              l.isArabic ? 'عرض سجل الحزم الحمراء' : 'View red packet history',
            ),
            onPressed: widget.walletId.isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HistoryPage(
                          baseUrl: widget.baseUrl,
                          walletId: widget.walletId,
                          initialKind: 'redpacket',
                          initialTxns: _recent
                              .where((t) =>
                                  (t['kind'] ?? '').toString().toLowerCase() ==
                                  'redpacket')
                              .toList(),
                        ),
                      ),
                    );
                  },
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              // ignore: discarded_futures
              _shareRedPacketToMoments();
            },
            child: Text(
              l.isArabic ? 'مشاركة في اللحظات' : 'Share to Moments',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .85),
              ),
            ),
          ),
        ],
      ),
      FormSection(
        title: l.isArabic ? 'النشاط الأخير' : 'Recent activity',
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  l.isArabic
                      ? 'أحدث الحركات على محفظتك.'
                      : 'Latest payments on your wallet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.walletId.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HistoryPage(
                              baseUrl: widget.baseUrl,
                              walletId: widget.walletId,
                            ),
                          ),
                        );
                      },
                child: Text(l.viewAll),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(
                l.isArabic ? 'سجل الفواتير' : 'Bill history',
              ),
              onPressed: widget.walletId.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HistoryPage(
                            baseUrl: widget.baseUrl,
                            walletId: widget.walletId,
                            initialKind: 'bill',
                          ),
                        ),
                      );
                    },
            ),
          ),
          const SizedBox(height: 8),
          if (_loading && _balanceCents == null && _recent.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator()))
          else if (widget.walletId.isEmpty)
            Text(
              l.isArabic ? 'لم يتم تعيين المحفظة بعد' : 'Wallet not set yet',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .60),
              ),
            )
          else if (_recent.isEmpty)
            Text(
              l.isArabic ? 'لا توجد مدفوعات حديثة' : 'No recent payments yet.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .60),
              ),
            )
          else
            _recentList(),
          if (_out.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _out,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }

  Widget _summaryChip(BuildContext context,
      {required String label, required String value}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletHero() {
    final bal = _balanceCents;
    final sav = _savingsCents;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final isDark = theme.brightness == Brightness.dark;
    final walletLabel = l.homeWallet;
    final walletIdLabel = widget.walletId.isEmpty ? l.notSet : widget.walletId;
    final balanceLabel = isAr ? 'الرصيد' : 'Balance';
    final savingsLabel = isAr ? 'الادخار' : 'Savings';
    final bg = Tokens.colorPayments.withValues(alpha: isDark ? .20 : .10);
    final fgPrimary = isDark ? Colors.white : Colors.black87;
    final fgSecondary =
        (isDark ? Colors.white : Colors.black87).withValues(alpha: .70);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  walletLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: fgPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  walletIdLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: fgSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                balanceLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: fgSecondary,
                ),
              ),
              Text(
                bal == null
                    ? (_loading ? '…' : '—')
                    : '${fmtCents(bal)} $_curSym',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: fgPrimary,
                ),
              ),
              if (sav != null && sav > 0) ...[
                const SizedBox(height: 4),
                Text(
                  savingsLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: fgSecondary,
                  ),
                ),
                Text(
                  '${fmtCents(sav)} $_curSym',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fgPrimary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 80,
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
                  color: Tokens.colorPayments.withValues(alpha: .08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: Tokens.colorPayments.withValues(alpha: .95),
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

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        item(
          icon: Icons.qr_code_2,
          label: l.isArabic ? 'الدفع والاستلام' : 'Pay & receive',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReceivePayPage(
                  baseUrl: widget.baseUrl,
                  fromWalletId: widget.walletId,
                ),
              ),
            );
          },
        ),
        item(
          icon: Icons.arrow_upward_rounded,
          label: l.isArabic ? 'تحويل' : 'Transfer',
          onTap: () => _goToTab(context, 2),
        ),
        item(
          icon: Icons.receipt_long_outlined,
          label: l.isArabic ? 'الفواتير' : 'Bills',
          onTap: () {
            if (widget.walletId.isEmpty) {
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
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BillsPage(
                  widget.baseUrl,
                  widget.walletId,
                  widget.deviceId,
                ),
              ),
            );
          },
        ),
        item(
          icon: Icons.groups_2_outlined,
          label: l.isArabic ? 'تقسيم الفاتورة' : 'Split bill',
          onTap: () {
            if (widget.walletId.isEmpty) {
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
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupPayPage(
                  baseUrl: widget.baseUrl,
                  fromWalletId: widget.walletId,
                  deviceId: widget.deviceId,
                ),
              ),
            );
          },
        ),
        item(
          icon: Icons.pending_actions_outlined,
          label: l.isArabic ? 'طلبات الدفع' : 'Payment requests',
          onTap: () {
            if (widget.walletId.isEmpty) {
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
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RequestsPage(
                  baseUrl: widget.baseUrl,
                  walletId: widget.walletId,
                ),
              ),
            );
          },
        ),
        item(
          icon: Icons.arrow_downward_rounded,
          label: l.isArabic ? 'استلام' : 'Receive',
          onTap: () => _goToTab(context, 3),
        ),
      ],
    );
  }

  Future<void> _openTopupSheet() async {
    final l = L10n.of(context);
    if (widget.walletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'الرجاء إعداد المحفظة أولاً'
                : 'Please set up your wallet first',
          ),
        ),
      );
      return;
    }
    final amountCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding:
              EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 12),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: StatefulBuilder(
              builder: (ctx2, setStateSB) {
                final theme = Theme.of(ctx2);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.isArabic ? 'شحن المحفظة' : 'Top up wallet',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.isArabic
                          ? 'أدخل المبلغ الذي تريد شحنه إلى محفظتك.'
                          : 'Enter the amount you want to add to your wallet balance.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l.isArabic
                            ? 'المبلغ ($_curSym)'
                            : 'Amount ($_curSym)',
                      ),
                    ),
                    if (error != null && error!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(ctx2).pop(),
                            child: Text(l.mirsaalDialogCancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PrimaryButton(
                            label: submitting
                                ? (l.isArabic ? 'جارٍ الشحن…' : 'Topping up…')
                                : (l.isArabic ? 'شحن' : 'Top up'),
                            onPressed: submitting
                                ? null
                                : () async {
                                    final raw = amountCtrl.text
                                        .trim()
                                        .replaceAll(',', '.');
                                    final amt = double.tryParse(raw) ?? 0;
                                    if (amt <= 0) {
                                      setStateSB(() {
                                        error = l.payCheckInputs;
                                      });
                                      return;
                                    }
                                    setStateSB(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      await _submitTopup(amt);
                                      if (context.mounted) {
                                        Navigator.of(ctx2).pop();
                                      }
                                    } catch (e) {
                                      setStateSB(() {
                                        submitting = false;
                                        error = e.toString();
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitTopup(double amountMajor) async {
    final l = L10n.of(context);
    final uri = Uri.parse(
        '${widget.baseUrl}/payments/wallets/${Uri.encodeComponent(widget.walletId)}/topup');
    final headers = await _hdrPO(json: true);
    headers['Idempotency-Key'] =
        'topup-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final payload = <String, Object?>{
      'amount': double.parse(amountMajor.toStringAsFixed(2)),
    };
    final r = await http.post(uri, headers: headers, body: jsonEncode(payload));
    if (r.statusCode >= 200 && r.statusCode < 300) {
      await _loadSnapshot();
      if (mounted) {
        setState(() {});
      }
      final msg =
          l.isArabic ? 'تم شحن المحفظة بنجاح.' : 'Wallet top‑up successful.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      String msg = l.isArabic ? 'تعذّر شحن المحفظة.' : 'Top‑up failed.';
      try {
        final body = jsonDecode(r.body);
        final detail =
            body is Map<String, dynamic> ? body['detail']?.toString() : null;
        if (detail != null && detail.isNotEmpty) {
          msg = detail;
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<void> _openCashoutSheet() async {
    final l = L10n.of(context);
    if (widget.walletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'الرجاء إعداد المحفظة أولاً'
                : 'Please set up your wallet first',
          ),
        ),
      );
      return;
    }
    final amountCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding:
              EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 12),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: StatefulBuilder(
              builder: (ctx2, setStateSB) {
                final theme = Theme.of(ctx2);
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.isArabic ? 'سحب نقدي برمز' : 'Cash out with code',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.isArabic
                            ? 'إنشاء رمز سحب نقدي لتسليمه إلى وكيل أو مستلم، مشابه لرموز السحب في المحافظ الفائقة.'
                            : 'Create a cash‑out code you can redeem via an agent or recipient, similar to cash‑out codes in super‑app wallets.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'المبلغ ($_curSym)'
                              : 'Amount ($_curSym)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: secretCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'كلمة سر للرمز (مطلوبة)'
                              : 'Secret phrase for code (required)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'هاتف المستلم (اختياري)'
                              : 'Recipient phone (optional)',
                        ),
                      ),
                      if (error != null && error!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: submitting
                                  ? null
                                  : () => Navigator.of(ctx2).pop(),
                              child: Text(l.mirsaalDialogCancel),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrimaryButton(
                              label: submitting
                                  ? (l.isArabic ? 'جارٍ الإنشاء…' : 'Creating…')
                                  : (l.isArabic ? 'إنشاء رمز' : 'Create code'),
                              onPressed: submitting
                                  ? null
                                  : () async {
                                      final rawAmt = amountCtrl.text
                                          .trim()
                                          .replaceAll(',', '.');
                                      final amt = double.tryParse(rawAmt) ?? 0;
                                      final secret = secretCtrl.text.trim();
                                      if (amt <= 0 || secret.length < 3) {
                                        setStateSB(() {
                                          error = l.payCheckInputs;
                                        });
                                        return;
                                      }
                                      setStateSB(() {
                                        submitting = true;
                                        error = null;
                                      });
                                      try {
                                        final resp = await _submitCashout(
                                          amountMajor: amt,
                                          secret: secret,
                                          recipientPhone: phoneCtrl.text.trim(),
                                        );
                                        if (!context.mounted) return;
                                        Navigator.of(ctx2).pop();
                                        final code =
                                            (resp['code'] ?? '').toString();
                                        final amtC =
                                            (resp['amount_cents'] ?? 0) as int;
                                        final cur = (resp['currency'] ?? 'SYP')
                                            .toString();
                                        final formatted = fmtCents(amtC);
                                        final snack = l.isArabic
                                            ? 'رمز السحب: $code · $formatted $cur'
                                            : 'Cash‑out code: $code · $formatted $cur';
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                                SnackBar(content: Text(snack)));
                                      } catch (e) {
                                        setStateSB(() {
                                          submitting = false;
                                          error = e.toString();
                                        });
                                      }
                                    },
                            ),
                          ),
                        ],
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

  Future<Map<String, dynamic>> _submitCashout({
    required double amountMajor,
    required String secret,
    String? recipientPhone,
  }) async {
    final l = L10n.of(context);
    final uri = Uri.parse('${widget.baseUrl}/payments/cash/create');
    final headers = await _hdrPO(json: true);
    headers['Idempotency-Key'] =
        'cash-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final payload = <String, Object?>{
      'from_wallet_id': widget.walletId,
      'amount_cents': (amountMajor * 100).round(),
      'secret_phrase': secret,
    };
    if (recipientPhone != null && recipientPhone.trim().isNotEmpty) {
      payload['recipient_phone'] = recipientPhone.trim();
    }
    final r = await http.post(uri, headers: headers, body: jsonEncode(payload));
    if (r.statusCode >= 200 && r.statusCode < 300) {
      try {
        final body = jsonDecode(r.body);
        if (body is Map<String, dynamic>) {
          await _loadSnapshot();
          if (mounted) {
            setState(() {});
          }
          return body;
        }
      } catch (_) {}
      return <String, dynamic>{};
    } else {
      String msg = l.isArabic
          ? 'تعذّر إنشاء رمز السحب.'
          : 'Failed to create cash‑out code.';
      try {
        final body = jsonDecode(r.body);
        final detail =
            body is Map<String, dynamic> ? body['detail']?.toString() : null;
        if (detail != null && detail.isNotEmpty) {
          msg = detail;
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<void> _openManageCardsSheet() async {
    final l = L10n.of(context);
    String label = '';
    String last4 = '';
    String brand = '';
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        final labelCtrl = TextEditingController(text: label);
        final last4Ctrl = TextEditingController(text: last4);
        final brandCtrl = TextEditingController(text: brand);
        return Padding(
          padding:
              EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 12),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: StatefulBuilder(
              builder: (ctx2, setStateSB) {
                final theme = Theme.of(ctx2);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.isArabic
                          ? 'إضافة بطاقة مرتبطة (محلياً)'
                          : 'Add linked card (local only)',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.isArabic
                          ? 'هذه المعلومات تُحفظ فقط على هذا الجهاز لتسهيل التعرف على بطاقاتك. لا تُستخدم مباشرة في المعاملات.'
                          : 'This information is stored only on this device to help you recognise your cards. It is not used directly for payments.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelCtrl,
                      decoration: InputDecoration(
                        labelText: l.isArabic
                            ? 'اسم البطاقة (مثال: بطاقتي الرئيسية)'
                            : 'Card label (e.g. Main card)',
                      ),
                      onChanged: (v) {
                        label = v;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: last4Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.isArabic ? 'آخر ٤ أرقام' : 'Last 4 digits',
                      ),
                      onChanged: (v) {
                        last4 = v;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: brandCtrl,
                      decoration: InputDecoration(
                        labelText: l.isArabic
                            ? 'النوع (اختياري، مثال: Visa)'
                            : 'Brand (optional, e.g. Visa)',
                      ),
                      onChanged: (v) {
                        brand = v;
                      },
                    ),
                    if (error != null && error!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx2).pop(),
                            child: Text(l.mirsaalDialogCancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PrimaryButton(
                            label: l.isArabic ? 'حفظ البطاقة' : 'Save card',
                            onPressed: () {
                              final lbl = label.trim();
                              final l4 = last4.trim();
                              if (lbl.isEmpty && l4.isEmpty) {
                                setStateSB(() {
                                  error = l.payCheckInputs;
                                });
                                return;
                              }
                              final card = <String, String>{
                                'label': lbl,
                                'last4': l4,
                                'brand': brand.trim(),
                              };
                              setState(() {
                                final list = List<Map<String, String>>.from(
                                    _linkedCards);
                                list.insert(0, card);
                                _linkedCards = list;
                              });
                              // ignore: discarded_futures
                              _saveLinkedCards();
                              Navigator.of(ctx2).pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _savingsSection(BuildContext context) {
    final l = L10n.of(context);
    final sav = _savingsCents ?? 0;
    final bal = _balanceCents ?? 0;
    final hasWallet = widget.walletId.isNotEmpty;
    final isLoadingSavings = _loading && _savingsCents == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        l.isArabic
            ? 'حوّل الأموال بين رصيد المحفظة ورصيد الادخار، كما في المحافظ الفائقة.'
            : 'Move money between your wallet balance and savings, similar to super‑app wallets.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .70),
            ),
      ),
      const SizedBox(height: 8),
      if (isLoadingSavings)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l.isArabic ? 'رصيد الادخار' : 'Savings balance',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${fmtCents(sav)} $_curSym',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                icon: Icons.savings_outlined,
                label: l.isArabic ? 'إلى الادخار' : 'Move to savings',
                expanded: true,
                onPressed: hasWallet
                    ? () => _promptSavingsMove(toSavings: true)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                  l.isArabic ? 'سحب من الادخار' : 'Withdraw to wallet',
                ),
                onPressed: hasWallet && sav > 0
                    ? () => _promptSavingsMove(toSavings: false)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l.isArabic
              ? 'المحفظة: ${fmtCents(bal)} $_curSym · الادخار: ${fmtCents(sav)} $_curSym'
              : 'Wallet: ${fmtCents(bal)} $_curSym · Savings: ${fmtCents(sav)} $_curSym',
          style: TextStyle(
            fontSize: 11,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .60),
          ),
        ),
        const SizedBox(height: 8),
        _savingsRecentList(context),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.walletId.isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HistoryPage(
                          baseUrl: widget.baseUrl,
                          walletId: widget.walletId,
                          initialKind: 'savings',
                        ),
                      ),
                    );
                  },
            child: Text(
              l.isArabic
                  ? 'عرض سجل الادخار بالكامل'
                  : 'View full savings history',
            ),
          ),
        ),
      ],
    ]);
  }

  Future<void> _shareRedPacketToMoments() async {
    final l = L10n.of(context);
    String text;
    String? campaignId;
    final sec = (widget.initialSection ?? '').trim();
    if (sec.toLowerCase().startsWith('redpacket:')) {
      final parts = sec.split(':');
      if (parts.length > 1) {
        campaignId = parts.sublist(1).join(':').trim();
        if (campaignId.isEmpty) {
          campaignId = null;
        }
      }
    }
    if (campaignId != null && campaignId.isNotEmpty) {
      try {
        final uri = Uri.parse(
            '${widget.baseUrl}/redpacket/campaigns/${Uri.encodeComponent(campaignId)}/moments_template');
        final r = await http.get(uri, headers: await _hdrPO());
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final te = (j['text_en'] ?? '').toString();
          final ta = (j['text_ar'] ?? '').toString();
          if (l.isArabic && ta.trim().isNotEmpty) {
            text = ta.trim();
          } else if (!l.isArabic && te.trim().isNotEmpty) {
            text = te.trim();
          } else {
            text = l.isArabic
                ? 'أرسل حزمًا حمراء عبر Shamell Pay 🎁'
                : 'I am sending red packets via Shamell Pay 🎁';
          }
        } else {
          text = l.isArabic
              ? 'أرسل حزمًا حمراء عبر Shamell Pay 🎁'
              : 'I am sending red packets via Shamell Pay 🎁';
        }
      } catch (_) {
        text = l.isArabic
            ? 'أرسل حزمًا حمراء عبر Shamell Pay 🎁'
            : 'I am sending red packets via Shamell Pay 🎁';
      }
    } else {
      text = l.isArabic
          ? 'أرسل حزمًا حمراء عبر Shamell Pay 🎁'
          : 'I am sending red packets via Shamell Pay 🎁';
    }
    if (!text.contains('#')) {
      text += l.isArabic ? ' #شامل_باي #حزمة_حمراء' : ' #ShamellPay #RedPacket';
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('moments_preset_text', text);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MomentsPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  Future<void> _promptSavingsMove({required bool toSavings}) async {
    final l = L10n.of(context);
    if (widget.walletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic
            ? 'الرجاء إعداد المحفظة أولاً'
            : 'Please set up your wallet first'),
      ));
      return;
    }
    final amountCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding:
              EdgeInsets.only(bottom: bottom, left: 12, right: 12, top: 12),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: StatefulBuilder(
              builder: (ctx2, setStateSB) {
                final theme = Theme.of(ctx2);
                final sav = _savingsCents ?? 0;
                final bal = _balanceCents ?? 0;
                final title = toSavings
                    ? (l.isArabic ? 'تحويل إلى الادخار' : 'Move to savings')
                    : (l.isArabic ? 'سحب من الادخار' : 'Withdraw from savings');
                final description = toSavings
                    ? (l.isArabic
                        ? 'سيتم تحويل المبلغ من رصيد المحفظة إلى رصيد الادخار.'
                        : 'Move money from your wallet balance into savings.')
                    : (l.isArabic
                        ? 'سيتم سحب المبلغ من رصيد الادخار إلى رصيد المحفظة.'
                        : 'Withdraw money from savings back to your wallet.');
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.isArabic
                          ? 'المحفظة: ${fmtCents(bal)} $_curSym · الادخار: ${fmtCents(sav)} $_curSym'
                          : 'Wallet: ${fmtCents(bal)} $_curSym · Savings: ${fmtCents(sav)} $_curSym',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l.isArabic
                            ? 'المبلغ ($_curSym)'
                            : 'Amount ($_curSym)',
                      ),
                    ),
                    if (error != null && error!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(ctx2).pop(),
                            child: Text(l.mirsaalDialogCancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PrimaryButton(
                            label: submitting
                                ? (l.isArabic ? 'جارٍ التنفيذ…' : 'Processing…')
                                : (toSavings
                                    ? (l.isArabic
                                        ? 'إيداع في الادخار'
                                        : 'Move to savings')
                                    : (l.isArabic
                                        ? 'سحب من الادخار'
                                        : 'Withdraw')),
                            onPressed: submitting
                                ? null
                                : () async {
                                    final raw = amountCtrl.text
                                        .trim()
                                        .replaceAll(',', '.');
                                    final amt = double.tryParse(raw) ?? 0;
                                    if (amt <= 0) {
                                      setStateSB(() {
                                        error = l.payCheckInputs;
                                      });
                                      return;
                                    }
                                    setStateSB(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      await _submitSavingsMove(
                                          toSavings: toSavings,
                                          amountMajor: amt);
                                      if (context.mounted) {
                                        Navigator.of(ctx2).pop();
                                      }
                                    } catch (e) {
                                      setStateSB(() {
                                        submitting = false;
                                        error = e.toString();
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitSavingsMove(
      {required bool toSavings, required double amountMajor}) async {
    final l = L10n.of(context);
    final uri = Uri.parse(
        '${widget.baseUrl}/payments/savings/${toSavings ? 'deposit' : 'withdraw'}');
    final headers = await _hdrPO(json: true);
    headers['Idempotency-Key'] =
        '${toSavings ? 'sav-dep-' : 'sav-wd-'}${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final payload = <String, Object?>{
      'wallet_id': widget.walletId,
      'amount': double.parse(amountMajor.toStringAsFixed(2)),
    };
    try {
      final r =
          await http.post(uri, headers: headers, body: jsonEncode(payload));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        // Refresh wallet + savings overview so the UI stays in sync.
        await _loadSnapshot();
        if (mounted) {
          setState(() {});
        }
        final msg = toSavings
            ? (l.isArabic
                ? 'تم تحويل المبلغ إلى الادخار'
                : 'Moved amount to savings')
            : (l.isArabic ? 'تم السحب من الادخار' : 'Withdrawn from savings');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      } else {
        String msg = l.paySendFailed;
        try {
          final body = jsonDecode(r.body);
          final detail =
              body is Map<String, dynamic> ? body['detail']?.toString() : null;
          if (detail != null && detail.isNotEmpty) {
            msg = detail;
          }
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      rethrow;
    }
  }

  Widget _savingsRecentList(BuildContext context) {
    final l = L10n.of(context);
    final items = _recent
        .where((t) {
          final kind = (t['kind'] ?? '').toString().toLowerCase();
          return kind.startsWith('savings_');
        })
        .take(3)
        .toList();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.isArabic ? 'أحدث حركات الادخار' : 'Recent savings activity',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        for (final t in items) _savingsRecentTile(context, t),
      ],
    );
  }

  Widget _savingsRecentTile(BuildContext context, Map<String, dynamic> t) {
    final l = L10n.of(context);
    final kind = (t['kind'] ?? '').toString().toLowerCase();
    final isDep = kind.startsWith('savings_deposit');
    final cents = (t['amount_cents'] ?? 0) as int;
    final amt = fmtCents(cents);
    final sign = isDep ? '-' : '+';
    final ts = (t['created_at'] ?? '').toString();
    final label = isDep
        ? (l.isArabic ? 'إلى الادخار' : 'To savings')
        : (l.isArabic ? 'من الادخار' : 'From savings');
    return StandardListTile(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: const Icon(Icons.savings_outlined, size: 20),
      title: Text(
        '$sign$amt $_curSym',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        '$label • $ts',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
        ),
      ),
    );
  }

  Widget _recentList() {
    final items = _recent.take(5).toList();
    return Column(children: [
      for (final t in items) _recentTile(t),
    ]);
  }

  Widget _recentTile(Map<String, dynamic> t) {
    final cents = (t['amount_cents'] ?? 0) as int;
    final isOut = (t['from_wallet_id'] ?? '').toString() == widget.walletId;
    final sign = isOut ? '-' : '+';
    final who = isOut ? (t['to_wallet_id'] ?? '') : (t['from_wallet_id'] ?? '');
    final amt = fmtCents(cents);
    final kindRaw = (t['kind'] ?? '').toString();
    final kind = kindRaw.toLowerCase();
    final ref = (t['reference'] ?? '').toString();
    final ts = (t['created_at'] ?? '').toString();
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final bool isRedpacket = kind == 'redpacket';

    String mainLabel;
    if (isRedpacket) {
      mainLabel = L10n.of(context).isArabic
          ? (isOut ? 'حزمة حمراء مرسلة' : 'حزمة حمراء مستلمة')
          : (isOut ? 'Red packet sent' : 'Red packet received');
    } else if (kind.startsWith('transfer')) {
      mainLabel = L10n.of(context).isArabic ? 'تحويل' : 'Transfer';
    } else if (kind.startsWith('topup')) {
      mainLabel = L10n.of(context).isArabic ? 'شحن رصيد' : 'Top‑up';
    } else if (kind.startsWith('cash')) {
      mainLabel = L10n.of(context).isArabic ? 'سحب نقدي' : 'Cash out';
    } else if (kind.startsWith('bill')) {
      mainLabel = L10n.of(context).isArabic ? 'فاتورة' : 'Bill payment';
    } else if (kind.startsWith('savings')) {
      mainLabel = L10n.of(context).isArabic ? 'ادخار' : 'Savings movement';
    } else {
      mainLabel = kindRaw;
    }

    String subtitleText;
    if (ref.isNotEmpty && who.toString().isNotEmpty) {
      subtitleText = '$ts · $who\n$ref';
    } else if (who.toString().isNotEmpty) {
      subtitleText = '$ts · $who';
    } else if (ref.isNotEmpty) {
      subtitleText = '$ts\n$ref';
    } else {
      subtitleText = ts;
    }

    final Color amountColor = isRedpacket
        ? Colors.red.shade400
        : (sign == '+'
            ? Tokens.colorPayments
            : onSurface.withValues(alpha: .85));
    final Color iconColor =
        isRedpacket ? Colors.red.shade400 : Tokens.colorPayments;
    final Color iconBg = isRedpacket
        ? Colors.red.shade50
        : Tokens.colorPayments.withValues(alpha: .08);
    final IconData iconData;
    if (isRedpacket) {
      iconData = Icons.card_giftcard;
    } else if (sign == '+') {
      iconData = Icons.call_received_rounded;
    } else {
      iconData = Icons.call_made_rounded;
    }

    return StandardListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconBg,
          shape: BoxShape.circle,
        ),
        child: Icon(iconData, color: iconColor, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              mainLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$sign$amt $_curSym',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: amountColor,
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitleText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: onSurface.withValues(alpha: .70),
        ),
      ),
    );
  }
}

Future<String?> _getCookiePO() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getString('sa_cookie');
}

Future<Map<String, String>> _hdrPO({bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final c = await _getCookiePO();
  if (c != null && c.isNotEmpty) h['Cookie'] = c;
  return h;
}
