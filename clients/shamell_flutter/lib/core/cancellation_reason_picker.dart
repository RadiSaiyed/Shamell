// Cycle 200 — Cancellation reason picker.
//
// Surfaced before a rider or driver actually cancels a trip. The
// picker returns a `(reason_code, reason_note)` tuple that the
// caller then ships to the BFF's existing trip-cancel handler
// (which has accepted `cancel_reason_code` since Cycle ~83).
//
// Reason codes are tiny ASCII identifiers — easy to aggregate
// in Postgres — paired with a localized human label for the UI.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';

/// Outcome of the picker. `null` means "user backed out, don't
/// cancel". A non-null value means "go ahead and cancel with this
/// reason".
class CancellationReasonChoice {
  final String reasonCode;
  final String reasonLabel;
  final String? note;

  const CancellationReasonChoice({
    required this.reasonCode,
    required this.reasonLabel,
    this.note,
  });
}

/// The roles the picker is rendered for. Rider and driver get
/// slightly different reason menus.
enum CancellationActor { rider, driver }

class _CancellationReasonItem {
  final String code;
  final String labelEn;
  final String labelAr;
  final IconData icon;
  const _CancellationReasonItem({
    required this.code,
    required this.labelEn,
    required this.labelAr,
    required this.icon,
  });
}

const List<_CancellationReasonItem> _riderReasons = <_CancellationReasonItem>[
  _CancellationReasonItem(
    code: 'changed_mind',
    labelEn: 'Changed my mind',
    labelAr: 'غيّرت رأيي',
    icon: Icons.refresh_rounded,
  ),
  _CancellationReasonItem(
    code: 'driver_taking_too_long',
    labelEn: 'Driver taking too long',
    labelAr: 'السائق يستغرق وقتاً طويلاً',
    icon: Icons.hourglass_bottom_rounded,
  ),
  _CancellationReasonItem(
    code: 'wrong_pickup',
    labelEn: 'Wrong pickup location',
    labelAr: 'موقع التقاط خاطئ',
    icon: Icons.location_off_outlined,
  ),
  _CancellationReasonItem(
    code: 'driver_unprofessional',
    labelEn: 'Driver unprofessional',
    labelAr: 'السائق غير مهني',
    icon: Icons.report_gmailerrorred_outlined,
  ),
  _CancellationReasonItem(
    code: 'price_too_high',
    labelEn: 'Price too high',
    labelAr: 'السعر مرتفع',
    icon: Icons.attach_money_rounded,
  ),
  _CancellationReasonItem(
    code: 'other',
    labelEn: 'Other reason',
    labelAr: 'سبب آخر',
    icon: Icons.more_horiz_rounded,
  ),
];

const List<_CancellationReasonItem> _driverReasons =
    <_CancellationReasonItem>[
  _CancellationReasonItem(
    code: 'rider_no_show',
    labelEn: 'Rider did not show up',
    labelAr: 'الراكب لم يحضر',
    icon: Icons.person_off_outlined,
  ),
  _CancellationReasonItem(
    code: 'wrong_address',
    labelEn: 'Wrong pickup address',
    labelAr: 'عنوان التقاط خاطئ',
    icon: Icons.wrong_location_outlined,
  ),
  _CancellationReasonItem(
    code: 'traffic_blocked',
    labelEn: 'Traffic / route blocked',
    labelAr: 'الطريق مغلق / ازدحام',
    icon: Icons.do_not_disturb_alt_rounded,
  ),
  _CancellationReasonItem(
    code: 'rider_uncooperative',
    labelEn: 'Rider behavior',
    labelAr: 'سلوك الراكب',
    icon: Icons.warning_amber_rounded,
  ),
  _CancellationReasonItem(
    code: 'vehicle_issue',
    labelEn: 'Vehicle issue',
    labelAr: 'مشكلة في المركبة',
    icon: Icons.car_repair_outlined,
  ),
  _CancellationReasonItem(
    code: 'other',
    labelEn: 'Other reason',
    labelAr: 'سبب آخر',
    icon: Icons.more_horiz_rounded,
  ),
];

/// Open the picker. Returns the chosen reason, or null when the
/// user backed out (so the cancel itself should NOT proceed).
Future<CancellationReasonChoice?> showCancellationReasonPicker({
  required BuildContext context,
  required CancellationActor actor,
}) {
  return showModalBottomSheet<CancellationReasonChoice?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      final isArabic = L10n.of(sheetCtx).isArabic;
      final items =
          actor == CancellationActor.rider ? _riderReasons : _driverReasons;
      return _CancellationReasonSheet(items: items, isArabic: isArabic);
    },
  );
}

class _CancellationReasonSheet extends StatefulWidget {
  final List<_CancellationReasonItem> items;
  final bool isArabic;

  const _CancellationReasonSheet({
    required this.items,
    required this.isArabic,
  });

  @override
  State<_CancellationReasonSheet> createState() =>
      _CancellationReasonSheetState();
}

class _CancellationReasonSheetState extends State<_CancellationReasonSheet> {
  _CancellationReasonItem? _selected;
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 6,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isArabic ? 'لماذا تلغي؟' : 'Why are you cancelling?',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'يساعدنا اختيار السبب في تحسين الخدمة.'
                  : 'Picking a reason helps us improve the service.',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...widget.items.map((item) {
              final selected = _selected?.code == item.code;
              return RadioListTile<String>(
                value: item.code,
                groupValue: _selected?.code,
                onChanged: (_) {
                  unawaited(HapticFeedback.selectionClick());
                  setState(() => _selected = item);
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Row(
                  children: <Widget>[
                    Icon(item.icon,
                        size: 18,
                        color: selected
                            ? theme.colorScheme.primary
                            : Colors.black54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isArabic ? item.labelAr : item.labelEn,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_selected?.code == 'other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                maxLength: 240,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'وضّح السبب (اختياري)'
                      : 'Tell us more (optional)',
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(isArabic ? 'تراجع' : 'Back'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: _selected == null
                        ? null
                        : () {
                            final s = _selected!;
                            Navigator.of(context).pop(
                              CancellationReasonChoice(
                                reasonCode: s.code,
                                reasonLabel:
                                    isArabic ? s.labelAr : s.labelEn,
                                note: _noteCtrl.text.trim().isEmpty
                                    ? null
                                    : _noteCtrl.text.trim(),
                              ),
                            );
                          },
                    icon: const Icon(Icons.cancel_outlined),
                    label:
                        Text(isArabic ? 'تأكيد الإلغاء' : 'Confirm cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
