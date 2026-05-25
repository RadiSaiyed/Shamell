// Cycle 174 — Schedule-a-ride booking dialog.
//
// Opens from the passenger ride flow when the rider toggles
// "Schedule for later" before requesting. Captures pickup/destination
// (passed in from the active route picker) plus a date + time
// using the platform showDatePicker/showTimePicker.
//
// Validation: server requires pickup_at >= now+10min and <= now+30d.
// We mirror those rules locally so the rider gets immediate feedback
// instead of a server roundtrip rejection.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scheduled_ride_api.dart';

/// Open the booking dialog. Returns the created `ScheduledRide`
/// on success, or null when the user cancelled / failed.
Future<ScheduledRide?> showScheduledRideDialog({
  required BuildContext context,
  required ScheduledRideApi api,
  required String pickupText,
  required String destinationText,
  required bool isArabic,
  String? pickupLabel,
  String? destinationLabel,
  double? pickupLat,
  double? pickupLon,
  double? destinationLat,
  double? destinationLon,
  String rideClass = 'economy',
  int fareEstimateCents = 0,
}) {
  return showDialog<ScheduledRide?>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _ScheduledRideDialog(
      api: api,
      pickupText: pickupText,
      destinationText: destinationText,
      pickupLabel: pickupLabel,
      destinationLabel: destinationLabel,
      pickupLat: pickupLat,
      pickupLon: pickupLon,
      destinationLat: destinationLat,
      destinationLon: destinationLon,
      rideClass: rideClass,
      fareEstimateCents: fareEstimateCents,
      isArabic: isArabic,
    ),
  );
}

class _ScheduledRideDialog extends StatefulWidget {
  final ScheduledRideApi api;
  final String pickupText;
  final String destinationText;
  final String? pickupLabel;
  final String? destinationLabel;
  final double? pickupLat;
  final double? pickupLon;
  final double? destinationLat;
  final double? destinationLon;
  final String rideClass;
  final int fareEstimateCents;
  final bool isArabic;

  const _ScheduledRideDialog({
    required this.api,
    required this.pickupText,
    required this.destinationText,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.pickupLat,
    required this.pickupLon,
    required this.destinationLat,
    required this.destinationLon,
    required this.rideClass,
    required this.fareEstimateCents,
    required this.isArabic,
  });

  @override
  State<_ScheduledRideDialog> createState() => _ScheduledRideDialogState();
}

class _ScheduledRideDialogState extends State<_ScheduledRideDialog> {
  DateTime? _selected;
  bool _busy = false;
  String? _error;
  final TextEditingController _notesCtrl = TextEditingController();

  static const int _minLeadMinutes = 12;
  static const int _maxLeadDays = 30;

  DateTime get _minAllowed =>
      DateTime.now().add(const Duration(minutes: _minLeadMinutes));
  DateTime get _maxAllowed => DateTime.now().add(const Duration(days: _maxLeadDays));

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final initial = _selected ?? DateTime.now().add(const Duration(hours: 2));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(_minAllowed) ? _minAllowed : initial,
      firstDate: _minAllowed,
      lastDate: _maxAllowed,
      helpText: widget.isArabic ? 'تاريخ الالتقاط' : 'Pickup date',
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: widget.isArabic ? 'وقت الالتقاط' : 'Pickup time',
    );
    if (pickedTime == null || !mounted) return;
    final dt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (dt.isBefore(_minAllowed)) {
      setState(() {
        _error = widget.isArabic
            ? 'يجب أن يكون موعد الالتقاط بعد $_minLeadMinutes دقيقة على الأقل من الآن'
            : 'Pickup must be at least $_minLeadMinutes minutes from now';
      });
      return;
    }
    setState(() {
      _selected = dt;
      _error = null;
    });
  }

  String _fmt(DateTime dt, {required bool isArabic}) {
    final wd = <String>[
      'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
    ][dt.weekday % 7];
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mn = dt.minute.toString().padLeft(2, '0');
    return '$wd $dd.$mm.$yy · $hh:$mn';
  }

  Future<void> _submit() async {
    final dt = _selected;
    if (dt == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ride = await widget.api.create(
        pickupText: widget.pickupText,
        destinationText: widget.destinationText,
        scheduledPickupAtUtc: dt.toUtc(),
        pickupLabel: widget.pickupLabel,
        destinationLabel: widget.destinationLabel,
        pickupLat: widget.pickupLat,
        pickupLon: widget.pickupLon,
        destinationLat: widget.destinationLat,
        destinationLon: widget.destinationLon,
        rideClass: widget.rideClass,
        fareEstimateCents: widget.fareEstimateCents,
        notes: _notesCtrl.text,
      );
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      Navigator.of(context).pop(ride);
    } on ScheduledRideApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.detail.isNotEmpty
            ? err.detail
            : (widget.isArabic
                ? 'فشل حجز الرحلة'
                : 'Failed to schedule the trip');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.isArabic
            ? 'تعذّر الاتصال بالخادم'
            : 'Could not reach the server';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.event_rounded,
              color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                isArabic ? 'احجز رحلة في وقت لاحق' : 'Schedule for later'),
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
                  ? 'سيتم تعيين سائق تلقائياً قبل وقت الالتقاط بحوالي 15 دقيقة.'
                  : 'A driver will be matched automatically ~15 minutes before pickup.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: .35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isArabic ? 'الرحلة' : 'Trip',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.pickupText} → ${widget.destinationText}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _busy ? null : _pick,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.schedule_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selected == null
                            ? (isArabic
                                ? 'اختر تاريخ ووقت الالتقاط'
                                : 'Pick pickup date + time')
                            : _fmt(_selected!, isArabic: isArabic),
                        style: TextStyle(
                          fontWeight:
                              _selected == null ? FontWeight.w400 : FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              enabled: !_busy,
              maxLength: 240,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText:
                    isArabic ? 'ملاحظات للسائق (اختياري)' : 'Notes for driver (optional)',
                border: const OutlineInputBorder(),
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(null),
          child: Text(isArabic ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton.icon(
          onPressed: (_selected == null || _busy) ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.check_circle_rounded, size: 18),
          label: Text(_busy
              ? (isArabic ? 'جاري الحجز…' : 'Booking…')
              : (isArabic ? 'احجز' : 'Schedule')),
        ),
      ],
    );
  }
}
