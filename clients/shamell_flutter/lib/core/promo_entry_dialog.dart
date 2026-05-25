// Cycle 207-208 — Promo entry dialog (rider side).
//
// MVP: lets the rider validate a promo code and see what discount
// it resolves to. The actual fare deduction at request-time lands
// in a follow-up cycle once the pricing pipeline wires through;
// this dialog ensures the validation path + operator analytics
// signal already work end-to-end.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'promo_api.dart';

Future<PromoValidation?> showPromoEntryDialog({
  required BuildContext context,
  required PromoApi api,
  required bool isArabic,
  int? fareEstimateCents,
}) {
  return showDialog<PromoValidation?>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PromoEntryDialog(
      api: api,
      isArabic: isArabic,
      fareEstimateCents: fareEstimateCents,
    ),
  );
}

class _PromoEntryDialog extends StatefulWidget {
  final PromoApi api;
  final bool isArabic;
  final int? fareEstimateCents;

  const _PromoEntryDialog({
    required this.api,
    required this.isArabic,
    required this.fareEstimateCents,
  });

  @override
  State<_PromoEntryDialog> createState() => _PromoEntryDialogState();
}

class _PromoEntryDialogState extends State<_PromoEntryDialog> {
  final TextEditingController _codeCtrl = TextEditingController();
  PromoValidation? _resolved;
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final raw = _codeCtrl.text.trim();
    if (raw.isEmpty || _checking) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _checking = true;
      _error = null;
      _resolved = null;
    });
    try {
      final v = await widget.api.validate(
        code: raw,
        fareEstimateCents: widget.fareEstimateCents,
      );
      if (!mounted) return;
      setState(() {
        _resolved = v;
        _checking = false;
      });
    } on PromoApiException catch (err) {
      if (!mounted) return;
      String detail = err.detail;
      if (detail.isEmpty) {
        detail = widget.isArabic
            ? 'كود غير صالح'
            : 'Invalid code';
      }
      // Localize a few common server messages.
      if (err.isNotFound) {
        detail = widget.isArabic
            ? 'الكود غير موجود أو منتهي'
            : 'Code not found or expired';
      } else if (err.isGone) {
        detail = widget.isArabic ? 'الكود منتهي' : 'Code expired';
      } else if (err.isConflict) {
        detail = widget.isArabic
            ? 'تم استنفاد عدد مرات الاستخدام'
            : 'Code redemption limit reached';
      }
      setState(() {
        _error = detail;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = widget.isArabic
            ? 'تعذّر الاتصال بالخادم'
            : 'Could not reach the server';
        _checking = false;
      });
    }
  }

  String _fmtAmount(int cents, String currency, {required bool isArabic}) {
    final whole = (cents / 100).round();
    final s = whole.toString();
    final buf = StringBuffer();
    final reversed = s.split('').reversed.toList();
    for (var i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(',');
      buf.write(reversed[i]);
    }
    final pretty = buf.toString().split('').reversed.join();
    return '$pretty $currency';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    final r = _resolved;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.local_offer_outlined,
              color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isArabic ? 'كود الخصم' : 'Promo code',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isArabic
                  ? 'أدخل كود الخصم للتحقق من صلاحيته.'
                  : 'Enter a promo code to check its validity.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              enabled: !_checking,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: <TextInputFormatter>[
                UpperCaseTextFormatter(),
                FilteringTextInputFormatter.allow(
                    RegExp(r'[A-Z0-9_\-]')),
                LengthLimitingTextInputFormatter(32),
              ],
              decoration: InputDecoration(
                labelText: isArabic ? 'الكود' : 'Code',
                hintText: 'FIRSTRIDE20',
                border: const OutlineInputBorder(),
                suffixIcon: _checking
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onSubmitted: (_) => _check(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (r != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF388E3C).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF388E3C).withValues(alpha: .35)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF388E3C)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            r.isPercent
                                ? (isArabic
                                    ? 'خصم ${(r.value / 100).toStringAsFixed(0)}%'
                                    : '${(r.value / 100).toStringAsFixed(0)}% off')
                                : (isArabic
                                    ? 'خصم ${_fmtAmount(r.value, r.currency, isArabic: isArabic)}'
                                    : '${_fmtAmount(r.value, r.currency, isArabic: isArabic)} off'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                          if (r.resolvedDiscountCents > 0)
                            Text(
                              isArabic
                                  ? 'توفير ${_fmtAmount(r.resolvedDiscountCents, r.currency, isArabic: isArabic)} على هذه الرحلة'
                                  : 'Save ${_fmtAmount(r.resolvedDiscountCents, r.currency, isArabic: isArabic)} on this ride',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                          if ((r.description ?? '').trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                r.description!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed:
              _checking ? null : () => Navigator.of(context).pop(null),
          child: Text(isArabic ? 'إغلاق' : 'Close'),
        ),
        if (r == null)
          FilledButton.icon(
            onPressed: _checking ? null : _check,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(isArabic ? 'تحقق' : 'Check'),
          )
        else
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(r),
            icon: const Icon(Icons.done_rounded, size: 18),
            label: Text(isArabic ? 'تطبيق' : 'Apply'),
          ),
      ],
    );
  }
}

/// Force uppercase as the user types so we don't need a UX explanation.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
