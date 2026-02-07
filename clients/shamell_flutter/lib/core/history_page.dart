import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'glass.dart';
import 'skeleton.dart';
import 'offline_queue.dart';
import 'format.dart' show fmtCents;
import 'ui_kit.dart';
import 'l10n.dart';
import 'design_tokens.dart';
import 'app_shell_widgets.dart' show AppBG; // reuse background only

class HistoryPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final List<Map<String, dynamic>>? initialTxns;
  final String? initialKind;
  const HistoryPage(
      {super.key,
      required this.baseUrl,
      required this.walletId,
      this.initialTxns,
      this.initialKind});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<dynamic> txns = [];
  String out = '';
  bool loading = true;
  String _dirFilter = 'all';
  String _kindFilter = 'all';
  String _dateFilter = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;
  final _dirs = const ['all', 'out', 'in'];
  final _kinds = const [
    'all',
    'transfer',
    'topup',
    'cash',
    'sonic',
    'redpacket',
    'bill',
    'savings',
  ];
  final _dates = const ['all', '7d', '30d', 'custom'];
  String _curSym = 'SYP';
  int _limit = 25;
  bool _mirsaalOnly = false;
  @override
  void initState() {
    super.initState();
    _loadPrefs();
    if (widget.initialKind != null && widget.initialKind!.trim().isNotEmpty) {
      _kindFilter = widget.initialKind!.trim();
    }
    if (widget.initialTxns != null) {
      txns = widget.initialTxns!;
      loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final qp = <String, String>{'limit': _limit.toString()};
      if (_dirFilter != 'all') qp['dir'] = _dirFilter;
      if (_kindFilter != 'all') qp['kind'] = _kindFilter;
      DateTime? f;
      DateTime? t;
      if (_dateFilter == '7d') {
        f = DateTime.now().subtract(const Duration(days: 7));
      } else if (_dateFilter == '30d') {
        f = DateTime.now().subtract(const Duration(days: 30));
      } else if (_dateFilter == 'custom') {
        f = _fromDate;
        t = _toDate;
      }
      String toIso(DateTime d) => d.toUtc().toIso8601String();
      if (f != null) qp['from_iso'] = toIso(f);
      if (t != null) qp['to_iso'] = toIso(t);
      final u = Uri.parse('${widget.baseUrl}/wallets/' +
              Uri.encodeComponent(widget.walletId) +
              '/snapshot')
          .replace(queryParameters: qp);
      final r = await http.get(u, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final arr = j['txns'];
        if (arr is List) {
          txns = arr;
          out = '';
        } else {
          out = L10n.of(context).historyUnexpectedFormat;
        }
        final w = j['wallet'];
        if (w is Map<String, dynamic>) {
          final cur = (w['currency'] ?? '').toString();
          if (cur.isNotEmpty) _curSym = cur;
        }
      } else {
        out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      out = '${L10n.of(context).historyErrorPrefix}: $e';
    }
    setState(() => loading = false);
  }

  Future<void> _loadMore() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final next = _limit + 25;
      _limit = next > 200 ? 200 : next;
      await _load();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _exportCsv() {
    try {
      final headers = [
        'time',
        'kind',
        'amount_cents',
        'amount_fmt',
        'from_wallet',
        'to_wallet',
        'note'
      ];
      final rows = <List<String>>[headers];
      for (final t in _filtered()) {
        final ac = (t['amount_cents'] ?? 0) as int;
        final af = fmtCents(ac) + ' ' + (_curSym);
        rows.add([
          (t['created_at'] ?? '').toString(),
          (t['kind'] ?? '').toString(),
          (t['amount_cents'] ?? '').toString(),
          af,
          (t['from_wallet_id'] ?? '').toString(),
          (t['to_wallet_id'] ?? '').toString(),
          (t['reference'] ?? '').toString(),
        ]);
      }
      final csv = rows
          .map((r) =>
              r.map((c) => '"' + c.replaceAll('"', '""') + '"').join(','))
          .join('\n');
      final subject = L10n.of(context).historyExportSubject;
      Share.share(csv, subject: subject);
    } catch (e) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.historyCsvErrorPrefix}: $e')),
      );
    }
  }

  List<Map<String, dynamic>> _filtered() {
    final now = DateTime.now();
    int? minEpoch;
    if (_dateFilter == '7d') {
      minEpoch = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    } else if (_dateFilter == '30d') {
      minEpoch = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    }
    return txns.whereType<Map<String, dynamic>>().where((t) {
      final from = (t['from_wallet_id'] ?? '').toString();
      final dirOkay = _dirFilter == 'all' ||
          (_dirFilter == 'out'
              ? from == widget.walletId
              : from != widget.walletId);
      final kind = (t['kind'] ?? '').toString().toLowerCase();
      final kindOkay = _kindFilter == 'all' || kind.contains(_kindFilter);
      final groupId = (t['group_id'] ?? '').toString().toLowerCase();
      final mirsaalOnlyActive = _mirsaalOnly && _kindFilter == 'redpacket';
      final mirsaalOkay = !mirsaalOnlyActive || groupId.startsWith('mirsaal:');
      bool dateOkay = true;
      if (minEpoch != null) {
        try {
          final ts = DateTime.tryParse((t['created_at'] ?? '').toString())
              ?.millisecondsSinceEpoch;
          if (ts != null) dateOkay = ts >= minEpoch;
        } catch (_) {}
      }
      return dirOkay && kindOkay && dateOkay && mirsaalOkay;
    }).toList();
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _dirFilter = sp.getString('ph_dir') ?? _dirFilter;
      _kindFilter = sp.getString('ph_kind') ?? _kindFilter;
      _dateFilter = sp.getString('ph_date') ?? _dateFilter;
      final f = sp.getString('ph_from');
      final t = sp.getString('ph_to');
      if (f != null) _fromDate = DateTime.tryParse(f);
      if (t != null) _toDate = DateTime.tryParse(t);
      final cs = sp.getString('currency_symbol');
      if (cs != null && cs.isNotEmpty) _curSym = cs;
      _mirsaalOnly = sp.getBool('ph_mirsaal_only') ?? _mirsaalOnly;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('ph_dir', _dirFilter);
      await sp.setString('ph_kind', _kindFilter);
      await sp.setString('ph_date', _dateFilter);
      if (_fromDate != null)
        await sp.setString('ph_from', _fromDate!.toIso8601String());
      if (_toDate != null)
        await sp.setString('ph_to', _toDate!.toIso8601String());
      await sp.setBool('ph_mirsaal_only', _mirsaalOnly);
    } catch (_) {}
  }

  Future<void> _pickDate(BuildContext context, bool from) async {
    final now = DateTime.now();
    final cur = from
        ? (_fromDate ?? now.subtract(const Duration(days: 7)))
        : (_toDate ?? now);
    final picked = await showDatePicker(
        context: context,
        initialDate: cur,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year + 1));
    if (picked != null) {
      setState(() {
        if (from)
          _fromDate = picked;
        else
          _toDate = picked;
      });
      await _savePrefs();
      await _load();
    }
  }

  Future<void> _pickDates(BuildContext context) async {
    await _pickDate(context, true);
    await _pickDate(context, false);
  }

  Future<void> _setMonthRange(int offsetMonths) async {
    final now = DateTime.now();
    int year = now.year;
    int month = now.month + offsetMonths;
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    while (month > 12) {
      month -= 12;
      year += 1;
    }
    final from = DateTime(year, month, 1);
    final to =
        DateTime(year, month + 1, 1).subtract(const Duration(seconds: 1));
    setState(() {
      _dateFilter = 'custom';
      _fromDate = from;
      _toDate = to;
    });
    await _savePrefs();
    await _load();
  }

  Widget? _buildPhSummary(List<Map<String, dynamic>> list) {
    try {
      int inC = 0, outC = 0;
      int inCnt = 0, outCnt = 0;
      int savDepC = 0, savWdrC = 0;
      int savDepCnt = 0, savWdrCnt = 0;
      int rpInC = 0, rpOutC = 0;
      int rpInCnt = 0, rpOutCnt = 0;
      for (final t in list) {
        final amt = (t['amount_cents'] ?? 0) as int;
        final isOut = (t['from_wallet_id'] ?? '') == widget.walletId;
        final kind = (t['kind'] ?? '').toString().toLowerCase();
        final isSavDep = kind.startsWith('savings_deposit');
        final isSavWdr = kind.startsWith('savings_withdraw');
        final isRedpacket = kind == 'redpacket';
        if (isOut) {
          outC += amt;
          outCnt++;
          if (isRedpacket) {
            rpOutC += amt;
            rpOutCnt++;
          }
        } else {
          inC += amt;
          inCnt++;
          if (isRedpacket) {
            rpInC += amt;
            rpInCnt++;
          }
        }
        if (isSavDep) {
          savDepC += amt;
          savDepCnt++;
        } else if (isSavWdr) {
          savWdrC += amt;
          savWdrCnt++;
        }
      }
      if (list.isEmpty) {
        return null;
      }
      final totalCents = inC + outC;
      final isBillsView = _kindFilter == 'bill';
      final isSavingsView = _kindFilter == 'savings';
      final isRedpacketView = _kindFilter == 'redpacket';
      final l = L10n.of(context);
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurface.withValues(alpha: .70);
      Widget inner;
      if (isBillsView) {
        inner = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.isArabic ? 'ملخص الفواتير' : 'Bills summary',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '${fmtCents(outC)} $_curSym',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              l.isArabic
                  ? 'إجمالي المدفوعات في الفترة المحددة.'
                  : 'Total bill payments in the selected window.',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        );
      } else if (isSavingsView) {
        inner = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.isArabic ? 'ملخص حركات الادخار' : 'Savings movements summary',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              l.isArabic
                  ? 'إلى الادخار: ${fmtCents(savDepC)} $_curSym'
                  : 'Into savings: ${fmtCents(savDepC)} $_curSym',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              l.isArabic
                  ? 'من الادخار: ${fmtCents(savWdrC)} $_curSym'
                  : 'From savings: ${fmtCents(savWdrC)} $_curSym',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              l.isArabic
                  ? 'عدد الحركات: ${savDepCnt + savWdrCnt}'
                  : 'Movements: ${savDepCnt + savWdrCnt}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        );
      } else if (isRedpacketView) {
        inner = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.isArabic ? 'ملخص الحزم الحمراء' : 'Red packet summary',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              l.isArabic
                  ? 'أرسلت: ${fmtCents(rpOutC)} $_curSym'
                  : 'Sent: ${fmtCents(rpOutC)} $_curSym',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              l.isArabic
                  ? 'استلمت: ${fmtCents(rpInC)} $_curSym'
                  : 'Received: ${fmtCents(rpInC)} $_curSym',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              l.isArabic
                  ? 'عدد الحزم: ${rpOutCnt + rpInCnt}'
                  : 'Packets: ${rpOutCnt + rpInCnt}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        );
      } else {
        inner = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.isArabic ? 'ملخص الحركات' : 'Transactions summary',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic ? 'المبلغ المرسل' : 'Sent',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${fmtCents(outC)} $_curSym ($outCnt)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic ? 'المبلغ المستلم' : 'Received',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${fmtCents(inC)} $_curSym ($inCnt)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l.isArabic
                  ? 'الصافي: ${fmtCents(totalCents)} $_curSym'
                  : 'Net: ${fmtCents(totalCents)} $_curSym',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: GlassPanel(
          padding: const EdgeInsets.all(12),
          radius: 18,
          child: inner,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildTxnTile(Map<String, dynamic> t, String currency, L10n l) {
    final cents = (t['amount_cents'] ?? 0) as int;
    final fromWallet = (t['from_wallet_id'] ?? '').toString();
    final toWallet = (t['to_wallet_id'] ?? '').toString();
    final isOut = fromWallet == widget.walletId;
    final kindRaw = (t['kind'] ?? '').toString();
    final kind = kindRaw.toLowerCase();
    final isSavDep = kind.startsWith('savings_deposit');
    final isSavWdr = kind.startsWith('savings_withdraw');
    final isRedpacket = kind == 'redpacket';
    final isBill = kind.startsWith('bill');
    final sign = isSavDep ? '-' : (isSavWdr ? '+' : (isOut ? '-' : '+'));
    final who = isOut ? toWallet : fromWallet;
    final amt = fmtCents(cents);
    final createdAt = (t['created_at'] ?? '').toString();
    final reference = (t['reference'] ?? '').toString();
    String subtitleText;
    if (reference.isNotEmpty && who.isNotEmpty) {
      subtitleText = '$createdAt · $who\n$reference';
    } else if (who.isNotEmpty) {
      subtitleText = '$createdAt · $who';
    } else if (reference.isNotEmpty) {
      subtitleText = '$createdAt\n$reference';
    } else {
      subtitleText = createdAt;
    }

    final amountColor = isRedpacket
        ? Colors.red.shade400
        : (isBill
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.90)
            : (sign == '+'
                ? Tokens.colorPayments
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.85)));

    String mainLabel;
    if (isRedpacket) {
      mainLabel = l.isArabic
          ? (isOut ? 'حزمة حمراء مرسلة' : 'حزمة حمراء مستلمة')
          : (isOut ? 'Red packet sent' : 'Red packet received');
    } else if (kind.startsWith('transfer')) {
      mainLabel = l.isArabic ? 'تحويل' : 'Transfer';
    } else if (kind.startsWith('topup')) {
      mainLabel = l.isArabic ? 'شحن رصيد' : 'Top‑up';
    } else if (kind.startsWith('cash')) {
      mainLabel = l.isArabic ? 'سحب نقدي' : 'Cash out';
    } else if (kind.startsWith('sonic')) {
      mainLabel = l.isArabic ? 'سونك' : 'Sonic transfer';
    } else if (kind.startsWith('bill')) {
      mainLabel = l.isArabic ? 'دفع فاتورة' : 'Bill paid';
    } else if (kind.startsWith('savings_deposit')) {
      mainLabel = l.isArabic ? 'إيداع ادخار' : 'Savings deposit';
    } else if (kind.startsWith('savings_withdraw')) {
      mainLabel = l.isArabic ? 'سحب ادخار' : 'Savings withdrawal';
    } else {
      mainLabel = kindRaw;
    }

    final bool isIncoming = sign == '+';
    final Color iconColor = isRedpacket
        ? Colors.red.shade400
        : (isBill
            ? Theme.of(context).colorScheme.primary
            : Tokens.colorPayments);
    final Color iconBg = isRedpacket
        ? Colors.red.shade50
        : (isBill
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
            : Tokens.colorPayments.withValues(alpha: 0.08));
    final IconData iconData;
    if (isRedpacket) {
      iconData = Icons.card_giftcard;
    } else if (isBill) {
      iconData = Icons.receipt_long_outlined;
    } else if (isIncoming) {
      iconData = Icons.call_received_rounded;
    } else {
      iconData = Icons.call_made_rounded;
    }

    return GestureDetector(
      onTap: () {
        _showTxnDetailSheet(t, currency, l,
            mainLabel: mainLabel,
            sign: sign,
            isRedpacket: isRedpacket,
            amountColor: amountColor,
            iconData: iconData,
            iconBg: iconBg);
      },
      child: StandardListTile(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                mainLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$sign$amt $currency',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: amountColor,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitleText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.70),
            ),
          ),
        ),
      ),
    );
  }

  void _showTxnDetailSheet(
    Map<String, dynamic> t,
    String currency,
    L10n l, {
    required String mainLabel,
    required String sign,
    required bool isRedpacket,
    required Color amountColor,
    required IconData iconData,
    required Color iconBg,
  }) {
    final theme = Theme.of(context);
    final cents = (t['amount_cents'] ?? 0) as int;
    final amt = fmtCents(cents);
    final fromWallet = (t['from_wallet_id'] ?? '').toString();
    final toWallet = (t['to_wallet_id'] ?? '').toString();
    final isOut = fromWallet == widget.walletId;
    final peer = isOut ? toWallet : fromWallet;
    final createdAtRaw = (t['created_at'] ?? '').toString();
    final reference = (t['reference'] ?? '').toString();
    final status = (t['status'] ?? '').toString();
    final kindRaw = (t['kind'] ?? '').toString().toLowerCase();
    final bool isBill = kindRaw.startsWith('bill');
    String statusLabel;
    if (status == 'ok') {
      if (isBill) {
        statusLabel = l.isArabic ? 'فاتورة مدفوعة' : 'Bill paid';
      } else {
        statusLabel = l.isArabic ? 'مكتمل' : 'Completed';
      }
    } else if (status == 'pending') {
      if (isBill) {
        statusLabel = l.isArabic ? 'فاتورة قيد الدفع' : 'Bill pending';
      } else {
        statusLabel = l.isArabic ? 'قيد المعالجة' : 'Pending';
      }
    } else if (status == 'failed') {
      if (isBill) {
        statusLabel = l.isArabic ? 'فشل دفع الفاتورة' : 'Bill payment failed';
      } else {
        statusLabel = l.isArabic ? 'فشل' : 'Failed';
      }
    } else {
      statusLabel =
          status.isEmpty ? (l.isArabic ? 'مكتمل' : 'Completed') : status;
    }

    DateTime? created;
    try {
      created = DateTime.tryParse(createdAtRaw);
    } catch (_) {}
    final createdLabel =
        created != null ? '${created.toLocal()}' : createdAtRaw;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: bottom + 12,
            top: 12,
          ),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        iconData,
                        color: amountColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mainLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                statusLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .70),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '$sign$amt $currency',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    () {
                      if (isBill) {
                        if (status == 'ok') {
                          return l.isArabic
                              ? 'تم دفع الفاتورة بنجاح'
                              : 'Bill payment successful';
                        } else if (status == 'pending') {
                          return l.isArabic
                              ? 'دفع الفاتورة قيد التنفيذ'
                              : 'Bill payment in progress';
                        } else if (status == 'failed') {
                          return l.isArabic
                              ? 'فشل دفع الفاتورة'
                              : 'Bill payment failed';
                        }
                      }
                      return isOut
                          ? (l.isArabic ? 'تم الإرسال' : 'Paid')
                          : (l.isArabic ? 'تم الاستلام' : 'Received');
                    }(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (peer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          isOut
                              ? (l.isArabic ? 'إلى' : 'To')
                              : (l.isArabic ? 'من' : 'From'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            peer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isArabic ? 'الوقت' : 'Time',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        createdLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (reference.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic ? 'الملاحظة' : 'Note',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reference,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        l.isArabic ? 'إغلاق' : 'Close',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pTransfer = OfflineQueue.pending(tag: 'payments_transfer');
    final pTopup = OfflineQueue.pending(tag: 'payments_topup');
    final pSonic = OfflineQueue.pending(tag: 'payments_sonic');
    final pCash = OfflineQueue.pending(tag: 'payments_cash');
    List<Widget> sections = [];
    Widget section(String title, List pending) {
      if (pending.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        ...pending
            .map<Widget>((p) => ListTile(
                leading: const CircleAvatar(child: Text('~')),
                title: const Text('Pending (offline)'),
                subtitle:
                    Text(p.body, maxLines: 2, overflow: TextOverflow.ellipsis)))
            .toList(),
        const Divider(height: 16),
      ]);
    }

    final l = L10n.of(context);
    sections.add(section(l.isArabic ? 'تحويلات' : 'Transfers', pTransfer));
    sections.add(section(l.isArabic ? 'شحنات' : 'Top‑Up', pTopup));
    sections.add(section(l.isArabic ? 'سونك' : 'Sonic', pSonic));
    sections.add(section(l.isArabic ? 'نقداً' : 'Cash', pCash));
    final filtered = _filtered();
    final header = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(l.historyDirLabel),
              const SizedBox(width: 6),
              DropdownButton<String>(
                  value: _dirFilter,
                  items: _dirs
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _dirFilter = v);
                    _savePrefs();
                  }),
              const SizedBox(width: 12),
              Text(l.historyTypeLabel),
              const SizedBox(width: 6),
              DropdownButton<String>(
                  value: _kindFilter,
                  items: _kinds
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _kindFilter = v);
                    _savePrefs();
                  }),
              const SizedBox(width: 12),
              Text(l.historyPeriodLabel),
              const SizedBox(width: 6),
              DropdownButton<String>(
                  value: _dateFilter,
                  items: _dates
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _dateFilter = v);
                    if (v == 'custom') {
                      await _pickDates(context);
                    }
                    _savePrefs();
                    await _load();
                  }),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                label: Text(l.isArabic ? 'الفواتير' : 'Bills'),
                selected: _kindFilter == 'bill',
                onSelected: (sel) {
                  setState(() => _kindFilter = sel ? 'bill' : 'all');
                  _savePrefs();
                },
              ),
              FilterChip(
                label: Text(l.isArabic ? 'الحزم الحمراء' : 'Red packets'),
                selected: _kindFilter == 'redpacket',
                onSelected: (sel) {
                  setState(() => _kindFilter = sel ? 'redpacket' : 'all');
                  _savePrefs();
                },
              ),
              if (_kindFilter == 'redpacket')
                FilterChip(
                  label: Text(
                    l.isArabic
                        ? (_mirsaalOnly
                            ? 'كل الحزم الحمراء'
                            : 'حزم Mirsaal فقط')
                        : (_mirsaalOnly
                            ? 'All red packets'
                            : 'Only Mirsaal red packets'),
                  ),
                  selected: _mirsaalOnly,
                  onSelected: (sel) {
                    setState(() => _mirsaalOnly = sel);
                    _savePrefs();
                  },
                ),
              FilterChip(
                label: Text(l.isArabic ? 'الادخار' : 'Savings'),
                selected: _kindFilter == 'savings',
                onSelected: (sel) {
                  setState(() => _kindFilter = sel ? 'savings' : 'all');
                  _savePrefs();
                },
              ),
              ActionChip(
                label: Text(l.isArabic ? 'هذا الشهر' : 'This month'),
                onPressed: () async {
                  await _setMonthRange(0);
                },
              ),
              ActionChip(
                label: Text(l.isArabic ? 'الشهر السابق' : 'Last month'),
                onPressed: () async {
                  await _setMonthRange(-1);
                },
              ),
            ],
          ),
        ],
      ),
    );
    final customRow = (_dateFilter == 'custom')
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              OutlinedButton.icon(
                  onPressed: () async {
                    await _pickDate(context, true);
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(_fromDate == null
                      ? l.historyFromLabel
                      : _fromDate!.toLocal().toString().split(' ').first)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  onPressed: () async {
                    await _pickDate(context, false);
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(_toDate == null
                      ? l.historyToLabel
                      : _toDate!.toLocal().toString().split(' ').first)),
            ]))
        : const SizedBox.shrink();
    final summary = _buildPhSummary(filtered);
    final cs = _curSym;
    final txnList = Column(children: [
      header,
      customRow,
      if (summary != null) summary,
      ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final t = filtered[i];
            return _buildTxnTile(t, cs, l);
          }),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: filtered.isEmpty || loading
            ? null
            : () async {
                await _loadMore();
              },
        icon: const Icon(Icons.expand_more),
        label: Text(L10n.of(context).isArabic
            ? 'تحميل المزيد (الحد: $_limit)'
            : 'Load more (limit: $_limit)'),
      ),
    ]);
    Widget listWidget = loading
        ? ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 6,
            itemBuilder: (_, i) => SkeletonListTile())
        : ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ...sections,
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  l.historyPostedTransactions,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .65),
                      ),
                ),
              ),
              txnList,
            ],
          );
    const bg = AppBG();
    return Scaffold(
      appBar: AppBar(
          title: Text(l.historyTitle),
          actions: [
            IconButton(
                onPressed: _exportCsv,
                icon: const Icon(Icons.ios_share_outlined))
          ],
          backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
            child: SafeArea(
                child: GlassPanel(
                    padding: const EdgeInsets.all(16),
                    child: RefreshIndicator(
                        onRefresh: () async {
                          await OfflineQueue.flush();
                          await _load();
                        },
                        child: listWidget))))
      ]),
    );
  }
}

Future<String?> _getCookie() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getString('sa_cookie');
}

Future<Map<String, String>> _hdr({bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final c = await _getCookie();
  if (c != null && c.isNotEmpty) h['Cookie'] = c;
  return h;
}
