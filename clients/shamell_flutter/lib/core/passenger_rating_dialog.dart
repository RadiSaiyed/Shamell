// Cycle 142 — rate-your-passenger dialog (driver side).
//
// Shown in the driver app right after the trip flips to
// `tripCompleted`. Captures 1-5 stars + optional comment and POSTs
// to the BFF. Mirrors `showRideRatingDialog` (Cycle 135) with the
// roles flipped: the driver is the rater, the rider is the rated.
//
// Returns `true` when the driver submitted a rating, `false` (or
// null) when they dismissed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'passenger_rating_api.dart';

/// Show the rating dialog and POST the result on submit. Returns
/// `true` when a rating was successfully submitted, otherwise
/// `null` (cancelled or failed).
Future<bool?> showPassengerRatingDialog({
  required BuildContext context,
  required PassengerRatingApi api,
  required String rideId,
  required String passengerDisplayName,
  required bool isArabic,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PassengerRatingDialog(
      api: api,
      rideId: rideId,
      passengerDisplayName: passengerDisplayName,
      isArabic: isArabic,
    ),
  );
}

class _PassengerRatingDialog extends StatefulWidget {
  final PassengerRatingApi api;
  final String rideId;
  final String passengerDisplayName;
  final bool isArabic;

  const _PassengerRatingDialog({
    required this.api,
    required this.rideId,
    required this.passengerDisplayName,
    required this.isArabic,
  });

  @override
  State<_PassengerRatingDialog> createState() => _PassengerRatingDialogState();
}

class _PassengerRatingDialogState extends State<_PassengerRatingDialog> {
  int _stars = 0;
  bool _submitting = false;
  String? _error;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0 || _submitting) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.api.submitRating(
        rideId: widget.rideId,
        stars: _stars,
        comment: _commentCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PassengerRatingApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.detail.isNotEmpty
            ? err.detail
            : (widget.isArabic
                ? 'فشل إرسال التقييم'
                : 'Failed to submit rating');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return AlertDialog(
      title: Text(
        isArabic ? 'كيف كان الراكب؟' : 'How was your passenger?',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isArabic
                ? 'قيّم ${widget.passengerDisplayName}'
                : 'Rate ${widget.passengerDisplayName}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 40,
                  onPressed: _submitting
                      ? null
                      : () {
                          unawaited(HapticFeedback.selectionClick());
                          setState(() => _stars = i);
                        },
                  icon: Icon(
                    _stars >= i
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _stars >= i
                        ? const Color(0xFFFFA000)
                        : theme.colorScheme.onSurface.withValues(alpha: .40),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _commentCtrl,
            maxLength: 240,
            maxLines: 3,
            enabled: !_submitting,
            decoration: InputDecoration(
              labelText: isArabic
                  ? 'تعليق (اختياري)'
                  : 'Comment (optional)',
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
      actions: <Widget>[
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(isArabic ? 'لاحقاً' : 'Later'),
        ),
        FilledButton.icon(
          onPressed: (_stars == 0 || _submitting) ? null : _submit,
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
          label: Text(
            _submitting
                ? (isArabic ? 'جارٍ الإرسال…' : 'Submitting…')
                : (isArabic ? 'إرسال' : 'Submit'),
          ),
        ),
      ],
    );
  }
}
