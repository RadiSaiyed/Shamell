// Cycle 236 — Coach journey SOS confirmation dialog.
//
// Mirror of the taxi `sos_dialog.dart` (Cycle 151) scoped to a
// coach journey (journey_id + booking_id + operator_id). Same
// hold-to-confirm pattern: rider presses + holds for 3 seconds
// to dispatch. Best-effort GPS capture before submission so the
// operator gets a coordinate breadcrumb.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n.dart';
import 'coach_safety_alerts_api.dart';

Future<CoachSafetyAlert?> showCoachSosConfirmDialog({
  required BuildContext context,
  required CoachSafetyAlertsApi api,
  required String journeyId,
  required String bookingId,
  required String operatorId,
  required bool isArabic,
}) {
  return showDialog<CoachSafetyAlert?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CoachSosConfirmDialog(
      api: api,
      journeyId: journeyId,
      bookingId: bookingId,
      operatorId: operatorId,
      isArabic: isArabic,
    ),
  );
}

class _CoachSosConfirmDialog extends StatefulWidget {
  final CoachSafetyAlertsApi api;
  final String journeyId;
  final String bookingId;
  final String operatorId;
  final bool isArabic;

  const _CoachSosConfirmDialog({
    required this.api,
    required this.journeyId,
    required this.bookingId,
    required this.operatorId,
    required this.isArabic,
  });

  @override
  State<_CoachSosConfirmDialog> createState() =>
      _CoachSosConfirmDialogState();
}

class _CoachSosConfirmDialogState extends State<_CoachSosConfirmDialog>
    with SingleTickerProviderStateMixin {
  static const Duration _holdDuration = Duration(seconds: 3);

  late final AnimationController _ctrl;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;
  int? _submittedAlertId;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _holdDuration);
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_submitting && !_submitted) {
        unawaited(_submit());
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _startHold() {
    if (_submitting || _submitted) return;
    unawaited(HapticFeedback.heavyImpact());
    _ctrl.forward(from: _ctrl.value);
  }

  void _releaseHold() {
    if (_ctrl.status == AnimationStatus.completed) return;
    _ctrl.reverse();
  }

  Future<void> _submit() async {
    if (_submitting || _submitted) return;
    unawaited(HapticFeedback.heavyImpact());
    setState(() {
      _submitting = true;
      _error = null;
    });
    double? lat;
    double? lon;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      ).timeout(const Duration(seconds: 5));
      lat = pos.latitude;
      lon = pos.longitude;
    } catch (_) {
      // GPS unavailable / denied — fire SOS anyway.
    }
    try {
      final alert = await widget.api.submit(
        journeyId: widget.journeyId,
        bookingId: widget.bookingId,
        operatorId: widget.operatorId,
        lastKnownLat: lat,
        lastKnownLon: lon,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
        _submittedAlertId = alert.id;
      });
    } on CoachSafetyAlertsApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.detail.isNotEmpty
            ? err.detail
            : (widget.isArabic
                ? 'فشل إرسال إشارة الطوارئ'
                : 'Failed to dispatch SOS');
      });
      _ctrl.reverse();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = widget.isArabic
            ? 'تعذّر الاتصال بالخادم'
            : 'Could not reach the server';
      });
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.warning_rounded,
              color: theme.colorScheme.error, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isArabic ? 'طلب الطوارئ' : 'Emergency SOS',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _submitted
                ? (isArabic
                    ? 'تم إرسال الإنذار. مركز عمليات سرتشات على اطلاع.'
                    : 'SOS dispatched — SyrChat operations is on it.')
                : (isArabic
                    ? 'اضغط واستمر لمدة 3 ثوانٍ لإطلاق إنذار الطوارئ. سيتم إعلام مركز التشغيل فوراً مع موقعك التقريبي.'
                    : 'Press and HOLD for 3 seconds to dispatch the SOS. Operations will see your alert + last-known position instantly.'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (!_submitted)
            GestureDetector(
              onTapDown: (_) => _startHold(),
              onTapUp: (_) => _releaseHold(),
              onTapCancel: _releaseHold,
              onLongPressDown: (_) => _startHold(),
              onLongPressEnd: (_) => _releaseHold(),
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (ctx, _) {
                  final progress = _ctrl.value;
                  return Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.error,
                        width: 2,
                      ),
                    ),
                    child: Stack(
                      children: <Widget>[
                        // Hold-progress bar.
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: FractionallySizedBox(
                              alignment: AlignmentDirectional.centerStart,
                              widthFactor: progress,
                              child: Container(
                                color: theme.colorScheme.error
                                    .withValues(alpha: .35),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.shield_rounded,
                                  color: theme.colorScheme.error, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                _submitting
                                    ? (isArabic ? 'جارٍ الإرسال…' : 'Dispatching…')
                                    : (isArabic
                                        ? 'اضغط واستمر للإرسال'
                                        : 'Hold to send'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.error,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            )
          else
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF388E3C).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF388E3C), size: 40),
              ),
            ),
          if (_submittedAlertId != null) ...[
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'رقم الإنذار: $_submittedAlertId'
                  : 'Alert ID: $_submittedAlertId',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
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
      actions: <Widget>[
        if (!_submitted)
          TextButton(
            onPressed:
                _submitting ? null : () => Navigator.of(context).pop(null),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(isArabic ? 'إغلاق' : 'Close'),
          ),
      ],
    );
  }
}
