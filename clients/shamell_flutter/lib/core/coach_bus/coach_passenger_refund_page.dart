// Cycle 225 — Coach Bus refund + rebook page.
//
// Reached from My-Bookings / Live-Journey for a booking that
// supports refunds or rebooks. Pulls the BFF-side eligibility +
// change options and lets the rider:
//   * pick a refund kind (original payment vs refund credit)
//   * submit a refund request with an optional reason
//   * see available change options + request a rebook to one
//
// The actual financial movement is operator-side; this page just
// records the request and shows the confirmation.

import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n.dart';
import 'coach_mobility_api.dart';
import 'coach_platform_contracts.dart';

class CoachPassengerRefundPage extends StatefulWidget {
  final String baseUrl;
  final String bookingId;

  const CoachPassengerRefundPage({
    required this.baseUrl,
    required this.bookingId,
    super.key,
  });

  @override
  State<CoachPassengerRefundPage> createState() =>
      _CoachPassengerRefundPageState();
}

class _CoachPassengerRefundPageState
    extends State<CoachPassengerRefundPage> {
  late final CoachMobilityApi _api;
  CoachRefundEligibilityResponse? _refundEligibility;
  CoachChangeOptionsResponse? _changeOptions;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  CoachRefundKind? _selectedKind;
  String? _confirmation;
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _api = CoachMobilityApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final refund = await _api.getRefundEligibility(widget.bookingId);
      final changes = await _api.getChangeOptions(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _refundEligibility = refund;
        _changeOptions = changes;
        _selectedKind =
            refund.eligibility.recommendedKind ??
                (refund.eligibility.options.isNotEmpty
                    ? refund.eligibility.options.first.kind
                    : null);
        _loading = false;
      });
    } on CoachApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = L10n.of(context).isArabic
            ? 'تعذّر تحميل التفاصيل'
            : 'Could not load details';
      });
    }
  }

  Future<void> _submitRefund() async {
    final isArabic = L10n.of(context).isArabic;
    final kind = _selectedKind;
    if (kind == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.requestRefund(
        bookingId: widget.bookingId,
        refundKind: kind,
        reason: _reasonCtrl.text.trim().isEmpty
            ? null
            : _reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirmation = isArabic
            ? 'تم تقديم طلب الاسترداد. ستتلقى تحديثاً قريباً.'
            : 'Refund request submitted. You will receive an update shortly.';
      });
    } on CoachApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = isArabic
            ? 'فشل إرسال طلب الاسترداد'
            : 'Refund request failed';
      });
    }
  }

  Future<void> _rebookTo(CoachChangeOption option) async {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.requestRebook(
        bookingId: widget.bookingId,
        targetOfferId: option.targetOfferId,
        reason: _reasonCtrl.text.trim().isEmpty
            ? null
            : _reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirmation = isArabic
            ? 'تم تقديم طلب الإعادة. سيتم تأكيد المقعد الجديد قريباً.'
            : 'Rebook request submitted. We will confirm the new seat soon.';
      });
    } on CoachApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = isArabic
            ? 'فشل إرسال طلب الإعادة'
            : 'Rebook request failed';
      });
    }
  }

  String _fmtIso(String iso) {
    final p = DateTime.tryParse(iso);
    if (p == null) return iso;
    final local = p.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm $hh:$mn';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = L10n.of(context).isArabic;
    final refund = _refundEligibility?.eligibility;
    final changes = _changeOptions?.eligibility.options ??
        const <CoachChangeOption>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'تغيير أو استرداد' : 'Change or refund'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null && refund == null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: <Widget>[
                    if (_confirmation != null)
                      Card(
                        color: const Color(0xFF388E3C).withValues(alpha: .12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF388E3C)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _confirmation!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1B5E20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_confirmation == null && refund != null) ...[
                      Text(
                        isArabic ? 'استرداد' : 'Refund',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      _refundCard(refund, isArabic: isArabic, theme: theme),
                    ],
                    if (_confirmation == null && changes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        isArabic ? 'إعادة الحجز' : 'Rebook',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ...changes.map((c) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const Icon(
                                  Icons.swap_horiz_rounded),
                              title: Text(
                                '${_fmtIso(c.departureAtIso)} → ${_fmtIso(c.arrivalAtIso)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                isArabic
                                    ? 'فرق السعر ${fmtCents(c.fareDifferenceMinorUnits)} ${c.currency} · المستحق ${fmtCents(c.totalDueMinorUnits)}'
                                    : 'Price delta ${fmtCents(c.fareDifferenceMinorUnits)} ${c.currency} · due ${fmtCents(c.totalDueMinorUnits)}',
                              ),
                              trailing: FilledButton(
                                onPressed:
                                    _busy ? null : () => _rebookTo(c),
                                child: Text(isArabic ? 'إعادة الحجز' : 'Rebook'),
                              ),
                            ),
                          )),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _refundCard(CoachRefundEligibility refund,
      {required bool isArabic, required ThemeData theme}) {
    if (!refund.refundable) {
      return Card(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            refund.reason ?? (isArabic
                ? 'هذا الحجز غير قابل للاسترداد.'
                : 'This booking is not refundable.'),
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (refund.refundCutoffAtIso != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.schedule_rounded,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      isArabic
                          ? 'آخر موعد للاسترداد: ${_fmtIso(refund.refundCutoffAtIso!)}'
                          : 'Cutoff: ${_fmtIso(refund.refundCutoffAtIso!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ...refund.options.map((opt) {
              final isSelected = _selectedKind == opt.kind;
              return RadioListTile<CoachRefundKind>(
                value: opt.kind,
                groupValue: _selectedKind,
                onChanged: _busy
                    ? null
                    : (k) => setState(() => _selectedKind = k),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  opt.label,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${fmtCents(opt.refundMinorUnits)} ${opt.currency} '
                  '${opt.feeMinorUnits > 0 ? "(${isArabic ? "رسوم" : "fee"} ${fmtCents(opt.feeMinorUnits)})" : ""}',
                ),
              );
            }),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonCtrl,
              enabled: !_busy,
              maxLength: 240,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: isArabic
                    ? 'سبب الاسترداد (اختياري)'
                    : 'Reason (optional)',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_selectedKind == null || _busy) ? null : _submitRefund,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.money_off_rounded),
                label: Text(
                  isArabic ? 'طلب الاسترداد' : 'Request refund',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
