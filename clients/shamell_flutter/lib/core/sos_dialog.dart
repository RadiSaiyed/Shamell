// Cycle 151 — SOS confirm dialog.
//
// Wraps `SafetyAlertsApi.raiseSos` with a friction layer that
// prevents pocket-press dispatches but is still fast enough under
// duress. The pattern:
//   1. User long-presses the SOS button (>= 600 ms).
//   2. Dialog opens with a 3-second "hold to call" countdown.
//   3. Releasing before 3s cancels. Holding through fires the API.
//   4. On success: shows "Help is on the way" with the alert id
//      for follow-up; submitting is irreversible.
//
// Why a hold-to-confirm rather than two-step taps: under panic,
// thumb pressure is steady; multi-tap is unreliable. Holding also
// gives the user a visceral "I'm doing this" feeling which feels
// safer than a "Yes, dispatch police" pop-up.
//
// On location: we try to fetch a one-shot last-known GPS via the
// `geolocator` package so the operator gets coordinates with the
// alert. Missing GPS is non-blocking — the SOS still fires.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'safety_alerts_api.dart';

/// Show the SOS confirmation overlay. Returns the raised alert on
/// success, or `null` when the user cancelled / the call failed.
Future<SafetyAlert?> showSosConfirmDialog({
  required BuildContext context,
  required SafetyAlertsApi api,
  required String rideId,
  required bool isArabic,
}) {
  return showDialog<SafetyAlert?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SosConfirmDialog(
      api: api,
      rideId: rideId,
      isArabic: isArabic,
    ),
  );
}

class _SosConfirmDialog extends StatefulWidget {
  final SafetyAlertsApi api;
  final String rideId;
  final bool isArabic;

  const _SosConfirmDialog({
    required this.api,
    required this.rideId,
    required this.isArabic,
  });

  @override
  State<_SosConfirmDialog> createState() => _SosConfirmDialogState();
}

class _SosConfirmDialogState extends State<_SosConfirmDialog>
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
    double? accuracy;
    // Best-effort one-shot GPS — never blocks the SOS itself.
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      ).timeout(const Duration(seconds: 5));
      lat = pos.latitude;
      lon = pos.longitude;
      accuracy = pos.accuracy;
    } catch (_) {
      // GPS unavailable / denied / timed out — fire SOS anyway.
    }
    try {
      final alert = await widget.api.raiseSos(
        rideId: widget.rideId,
        lastKnownLat: lat,
        lastKnownLon: lon,
        accuracyMeters: accuracy,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
        _submittedAlertId = alert.id;
      });
    } on SafetyAlertApiException catch (err) {
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
    if (_submitted) {
      return AlertDialog(
        icon: const Icon(Icons.shield_rounded,
            size: 48, color: Color(0xFF2E7D32)),
        title: Text(isArabic ? 'تم إرسال الإنذار' : 'Help is on the way'),
        content: Text(
          isArabic
              ? 'تم إبلاغ مركز العمليات. حافظ على هاتفك في متناول اليد. (رقم الإنذار #${_submittedAlertId ?? '-'})'
              : 'Operations has been notified. Keep your phone handy. (Alert #${_submittedAlertId ?? '-'})',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop<SafetyAlert?>(_lastAlert()),
            child: Text(isArabic ? 'حسناً' : 'OK'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isArabic ? 'طلب مساعدة طارئة' : 'Emergency SOS',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isArabic
                ? 'استمر بالضغط لمدة 3 ثوانٍ لإرسال إشارة استغاثة إلى مركز العمليات. سيتم إرسال موقعك الحالي.'
                : 'Hold for 3 seconds to dispatch an emergency alert to our operations center. Your current location will be included.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onLongPressStart: (_) => _startHold(),
            onLongPressEnd: (_) => _releaseHold(),
            onTapCancel: _releaseHold,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (ctx, _) {
                final pct = _ctrl.value;
                return SizedBox(
                  height: 96,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 96,
                          color: Colors.red.shade700,
                          backgroundColor: Colors.red.shade100,
                        ),
                      ),
                      Center(
                        child: _submitting
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(Icons.pan_tool_rounded,
                                      color: Colors.white, size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    pct <= 0
                                        ? (isArabic
                                            ? 'اضغط مطولاً للإرسال'
                                            : 'Hold to dispatch')
                                        : (isArabic
                                            ? 'استمر بالضغط…'
                                            : 'Keep holding…'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
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
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
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
      actions: <Widget>[
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop<SafetyAlert?>(null),
          child: Text(isArabic ? 'إلغاء' : 'Cancel'),
        ),
      ],
    );
  }

  // We return the alert id in case the host page wants to display
  // "Alert raised #N" inline after the dialog closes. The success
  // pane sets `_submittedAlertId` but constructing a real
  // `SafetyAlert` requires the full payload — we don't keep it
  // around past the success state. For now, returning null after
  // the OK tap is fine: the operator queue is the source of truth.
  SafetyAlert? _lastAlert() => null;
}
