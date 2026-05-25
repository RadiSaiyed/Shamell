// Cycle 229 — Coach journey rating dialog.
//
// Shown from the live journey page when the rider taps "Rate this
// journey" (or automatically when the journey transitions to
// completed in the future). Captures overall 1-5★ plus optional
// sub-ratings (on-time, cleanliness, comfort, crew) and an
// optional comment.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import 'coach_journey_rating_api.dart';

Future<bool?> showCoachJourneyRatingDialog({
  required BuildContext context,
  required CoachJourneyRatingApi api,
  required String journeyId,
  required String bookingId,
  required String operatorId,
  required String operatorDisplayName,
  required bool isArabic,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CoachJourneyRatingDialog(
      api: api,
      journeyId: journeyId,
      bookingId: bookingId,
      operatorId: operatorId,
      operatorDisplayName: operatorDisplayName,
      isArabic: isArabic,
    ),
  );
}

class _CoachJourneyRatingDialog extends StatefulWidget {
  final CoachJourneyRatingApi api;
  final String journeyId;
  final String bookingId;
  final String operatorId;
  final String operatorDisplayName;
  final bool isArabic;

  const _CoachJourneyRatingDialog({
    required this.api,
    required this.journeyId,
    required this.bookingId,
    required this.operatorId,
    required this.operatorDisplayName,
    required this.isArabic,
  });

  @override
  State<_CoachJourneyRatingDialog> createState() =>
      _CoachJourneyRatingDialogState();
}

class _CoachJourneyRatingDialogState
    extends State<_CoachJourneyRatingDialog> {
  int _stars = 0;
  int? _onTime;
  int? _cleanliness;
  int? _comfort;
  int? _crew;
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
      await widget.api.submit(
        journeyId: widget.journeyId,
        bookingId: widget.bookingId,
        operatorId: widget.operatorId,
        stars: _stars,
        comment: _commentCtrl.text,
        onTimeStars: _onTime,
        cleanlinessStars: _cleanliness,
        comfortStars: _comfort,
        crewStars: _crew,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CoachJourneyRatingApiException catch (err) {
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

  Widget _starRow({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var i = 1; i <= 5; i++)
          IconButton(
            iconSize: 28,
            onPressed: _submitting
                ? null
                : () {
                    unawaited(HapticFeedback.selectionClick());
                    onChanged(i);
                  },
            icon: Icon(
              value >= i ? Icons.star_rounded : Icons.star_outline_rounded,
              color: value >= i
                  ? const Color(0xFFFFA000)
                  : Colors.black.withValues(alpha: .35),
            ),
          ),
      ],
    );
  }

  Widget _subRatingRow({
    required String label,
    required int? value,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          for (var i = 1; i <= 5; i++)
            InkResponse(
              radius: 14,
              onTap: _submitting ? null : () => onChanged(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Icon(
                  (value ?? 0) >= i
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 18,
                  color: (value ?? 0) >= i
                      ? const Color(0xFFFFA000)
                      : Colors.black.withValues(alpha: .25),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return AlertDialog(
      title: Text(
        isArabic ? 'كيف كانت رحلتك؟' : 'How was your journey?',
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isArabic
                    ? 'قيّم رحلتك مع ${widget.operatorDisplayName}'
                    : 'Rate your trip with ${widget.operatorDisplayName}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _starRow(
                value: _stars,
                onChanged: (v) => setState(() => _stars = v),
              ),
              const SizedBox(height: 12),
              if (_stars > 0) ...[
                Text(
                  isArabic ? 'تفاصيل (اختياري)' : 'Details (optional)',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 4),
                _subRatingRow(
                  label: isArabic ? 'الالتزام بالوقت' : 'On time',
                  value: _onTime,
                  onChanged: (v) => setState(() => _onTime = v),
                ),
                _subRatingRow(
                  label: isArabic ? 'نظافة المركبة' : 'Cleanliness',
                  value: _cleanliness,
                  onChanged: (v) => setState(() => _cleanliness = v),
                ),
                _subRatingRow(
                  label: isArabic ? 'الراحة' : 'Comfort',
                  value: _comfort,
                  onChanged: (v) => setState(() => _comfort = v),
                ),
                _subRatingRow(
                  label: isArabic ? 'الطاقم' : 'Crew',
                  value: _crew,
                  onChanged: (v) => setState(() => _crew = v),
                ),
                const SizedBox(height: 10),
              ],
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
