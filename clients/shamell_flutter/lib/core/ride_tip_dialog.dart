// Cycle 194 — Tip-your-driver dialog.
//
// Surfaced automatically after the rider submits a 4+ star rating
// (Cycle 195). Renders preset chips (5%, 10%, 15%, 20% of the
// trip fare) plus a custom-amount input. Server enforces the
// per-trip ceiling and the (ride, rider) uniqueness so a re-tap
// adjusts the existing tip instead of stacking.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ride_tip_api.dart';

/// Open the tip dialog. Returns the saved RideTip when the rider
/// submitted; null when they tapped "Skip".
Future<RideTip?> showRideTipDialog({
  required BuildContext context,
  required RideTipApi api,
  required String rideId,
  required int tripFareCents,
  required String driverDisplayName,
  required bool isArabic,
  String currency = 'SYP',
}) {
  return showDialog<RideTip?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RideTipDialog(
      api: api,
      rideId: rideId,
      tripFareCents: tripFareCents,
      driverDisplayName: driverDisplayName,
      currency: currency,
      isArabic: isArabic,
    ),
  );
}

class _RideTipDialog extends StatefulWidget {
  final RideTipApi api;
  final String rideId;
  final int tripFareCents;
  final String driverDisplayName;
  final String currency;
  final bool isArabic;

  const _RideTipDialog({
    required this.api,
    required this.rideId,
    required this.tripFareCents,
    required this.driverDisplayName,
    required this.currency,
    required this.isArabic,
  });

  @override
  State<_RideTipDialog> createState() => _RideTipDialogState();
}

class _RideTipDialogState extends State<_RideTipDialog> {
  static const List<int> _presetPercents = <int>[5, 10, 15, 20];
  int? _selectedPercent;
  int _customCents = 0;
  bool _submitting = false;
  String? _error;
  final TextEditingController _customCtrl = TextEditingController();
  final TextEditingController _msgCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  int get _amountCents {
    if (_selectedPercent != null) {
      // Round to nearest 100 (whole cents/piastres) so the number
      // shown to the rider is readable.
      final raw = widget.tripFareCents * _selectedPercent! / 100;
      return ((raw / 100).round()) * 100;
    }
    return _customCents;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = _amountCents;
    if (amount < 1) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final tip = await widget.api.submitTip(
        rideId: widget.rideId,
        amountCents: amount,
        currency: widget.currency,
        message: _msgCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(tip);
    } on RideTipApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.detail.isNotEmpty
            ? err.detail
            : (widget.isArabic
                ? 'فشل إرسال الإكرامية'
                : 'Failed to submit tip');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = widget.isArabic
            ? 'تعذّر الاتصال بالخادم'
            : 'Could not reach the server';
      });
    }
  }

  String _fmtCents(int cents) {
    if (cents <= 0) return '0';
    // Whole-currency display (no decimals — SYP is large units).
    final whole = (cents / 100).round();
    final s = whole.toString();
    // Insert thousand separators.
    final buf = StringBuffer();
    final reversed = s.split('').reversed.toList();
    for (var i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(',');
      buf.write(reversed[i]);
    }
    return buf.toString().split('').reversed.join();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.volunteer_activism_rounded,
              color: Color(0xFFFFA000), size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(isArabic ? 'إكرامية للسائق؟' : 'Tip your driver?'),
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
                  ? 'إذا أعجبتك الرحلة، اشكر ${widget.driverDisplayName} بإكرامية. تذهب مباشرة إلى رصيد السائق.'
                  : 'Loved the ride? Thank ${widget.driverDisplayName} with a tip. Goes straight to the driver.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final pct in _presetPercents)
                  ChoiceChip(
                    label: Text(
                      '$pct% · ${_fmtCents((widget.tripFareCents * pct / 100).round())} ${widget.currency}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    selected: _selectedPercent == pct,
                    onSelected: _submitting
                        ? null
                        : (sel) {
                            unawaited(HapticFeedback.selectionClick());
                            setState(() {
                              _selectedPercent = sel ? pct : null;
                              if (sel) {
                                _customCents = 0;
                                _customCtrl.clear();
                              }
                            });
                          },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _customCtrl,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: isArabic
                    ? 'مبلغ مخصص (${widget.currency})'
                    : 'Custom amount (${widget.currency})',
                border: const OutlineInputBorder(),
              ),
              onChanged: (s) {
                final n = int.tryParse(s) ?? 0;
                setState(() {
                  _customCents = n * 100;
                  _selectedPercent = null;
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _msgCtrl,
              enabled: !_submitting,
              maxLength: 240,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: isArabic
                    ? 'رسالة شكر (اختياري)'
                    : 'Thank-you note (optional)',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(null),
          child: Text(isArabic ? 'تخطي' : 'Skip'),
        ),
        FilledButton.icon(
          onPressed: (_amountCents < 1 || _submitting) ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_submitting
              ? (isArabic ? 'جارٍ الإرسال…' : 'Sending…')
              : (isArabic
                  ? 'إرسال ${_fmtCents(_amountCents)} ${widget.currency}'
                  : 'Send ${_fmtCents(_amountCents)} ${widget.currency}')),
        ),
      ],
    );
  }
}
