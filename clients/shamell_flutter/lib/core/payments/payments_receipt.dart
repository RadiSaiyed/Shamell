import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart' show fmtCents;
import '../../core/l10n.dart';
import 'payments_card_style.dart';

int _receiptAmountCents(Map<String, dynamic> txn) {
  final raw = txn['amount_cents'];
  if (raw is num) return raw.toInt();
  return int.tryParse((raw ?? '').toString()) ?? 0;
}

String _receiptKindLabel(String raw, L10n l) {
  final kind = raw.trim().toLowerCase();
  if (kind.startsWith('transfer')) return l.isArabic ? 'تحويل' : 'Transfer';
  if (kind.startsWith('topup')) return l.isArabic ? 'شحن رصيد' : 'Top-up';
  if (kind.startsWith('cash')) return l.isArabic ? 'سحب نقدي' : 'Cash out';
  if (kind.startsWith('bill')) return l.isArabic ? 'فاتورة' : 'Bill payment';
  if (kind.startsWith('savings')) {
    return l.isArabic ? 'حركة ادخار' : 'Savings movement';
  }
  return raw.isEmpty ? (l.isArabic ? 'معاملة' : 'Transaction') : raw;
}

String _receiptExportText({
  required Map<String, dynamic> txn,
  required String walletId,
  required String currency,
  required L10n l,
}) {
  final cents = _receiptAmountCents(txn);
  final isOut = (txn['from_wallet_id'] ?? '').toString() == walletId;
  final sign = isOut ? '-' : '+';
  final lines = <String>[
    'SyrChat receipt',
    'Type: ${_receiptKindLabel((txn['kind'] ?? '').toString(), l)}',
    'Amount: $sign${fmtCents(cents)} $currency',
    'From: ${(txn['from_wallet_id'] ?? '').toString()}',
    'To: ${(txn['to_wallet_id'] ?? '').toString()}',
    'Reference: ${(txn['reference'] ?? '').toString()}',
    'Time: ${(txn['created_at'] ?? '').toString()}',
    'ID: ${(txn['id'] ?? '').toString()}',
  ];
  return lines.join('\n');
}

Widget _receiptLine(
  BuildContext context, {
  required String label,
  required String value,
}) {
  if (value.trim().isEmpty) return const SizedBox.shrink();
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .62),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> showShamellPaymentReceiptSheet(
  BuildContext context, {
  required Map<String, dynamic> transaction,
  required String walletId,
  required String currency,
}) {
  final l = L10n.of(context);
  final cents = _receiptAmountCents(transaction);
  final isOut = (transaction['from_wallet_id'] ?? '').toString() == walletId;
  final sign = isOut ? '-' : '+';
  final kind = _receiptKindLabel((transaction['kind'] ?? '').toString(), l);
  final amount = '$sign${fmtCents(cents)} $currency';
  final exportText = _receiptExportText(
    txn: transaction,
    walletId: walletId,
    currency: currency,
    l: l,
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ShamellPaymentCardSurface(
            tone: ShamellPaymentCardTone.soft,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.isArabic ? 'إيصال الدفع' : 'Payment receipt',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            kind,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .68),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      amount,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: isOut
                            ? theme.colorScheme.onSurface.withValues(alpha: .86)
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _receiptLine(
                  sheetContext,
                  label: l.isArabic ? 'من' : 'From',
                  value: (transaction['from_wallet_id'] ?? '').toString(),
                ),
                _receiptLine(
                  sheetContext,
                  label: l.isArabic ? 'إلى' : 'To',
                  value: (transaction['to_wallet_id'] ?? '').toString(),
                ),
                _receiptLine(
                  sheetContext,
                  label: l.isArabic ? 'المرجع' : 'Reference',
                  value: (transaction['reference'] ?? '').toString(),
                ),
                _receiptLine(
                  sheetContext,
                  label: l.isArabic ? 'الوقت' : 'Time',
                  value: (transaction['created_at'] ?? '').toString(),
                ),
                _receiptLine(
                  sheetContext,
                  label: l.isArabic ? 'المعرّف' : 'ID',
                  value: (transaction['id'] ?? '').toString(),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: exportText));
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      SnackBar(
                        content: Text(
                            l.isArabic ? 'تم نسخ الإيصال.' : 'Receipt copied.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: Text(l.isArabic ? 'نسخ الإيصال' : 'Copy receipt'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
