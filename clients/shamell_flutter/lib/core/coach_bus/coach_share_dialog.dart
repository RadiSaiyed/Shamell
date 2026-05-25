// Cycle 244 — Coach journey share dialog.
//
// Opens when the rider taps "Share journey" on the live coach
// journey page. Mints a fresh token on open, displays the share
// URL with three actions: copy, native share intent, revoke. The
// recipient opens the URL in any browser — no app install needed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import 'coach_share_api.dart';

Future<void> showCoachShareDialog({
  required BuildContext context,
  required CoachShareApi api,
  required String journeyId,
  required String bookingId,
  required String operatorId,
  required bool isArabic,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _CoachShareDialog(
      api: api,
      journeyId: journeyId,
      bookingId: bookingId,
      operatorId: operatorId,
      isArabic: isArabic,
    ),
  );
}

class _CoachShareDialog extends StatefulWidget {
  final CoachShareApi api;
  final String journeyId;
  final String bookingId;
  final String operatorId;
  final bool isArabic;

  const _CoachShareDialog({
    required this.api,
    required this.journeyId,
    required this.bookingId,
    required this.operatorId,
    required this.isArabic,
  });

  @override
  State<_CoachShareDialog> createState() => _CoachShareDialogState();
}

class _CoachShareDialogState extends State<_CoachShareDialog> {
  CoachShareToken? _token;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_mint());
  }

  Future<void> _mint() async {
    try {
      final token = await widget.api.mintShare(
        journeyId: widget.journeyId,
        bookingId: widget.bookingId,
        operatorId: widget.operatorId,
      );
      if (!mounted) return;
      setState(() {
        _token = token;
        _loading = false;
      });
    } on CoachShareApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.detail.isNotEmpty
            ? err.detail
            : (widget.isArabic
                ? 'فشل إنشاء رابط المشاركة'
                : 'Could not create share link');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.isArabic
            ? 'تعذّر الاتصال بالخادم'
            : 'Could not reach the server';
      });
    }
  }

  Future<void> _copy() async {
    final share = _token;
    if (share == null) return;
    await Clipboard.setData(ClipboardData(text: share.shareUrl));
    unawaited(HapticFeedback.selectionClick());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isArabic ? 'تم النسخ' : 'Copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareIntent() async {
    final share = _token;
    if (share == null) return;
    setState(() => _busy = true);
    try {
      await Share.share(
        widget.isArabic
            ? 'تتبّع رحلتي بالباص عبر سرتشات: ${share.shareUrl}'
            : 'Follow my SyrChat coach journey live: ${share.shareUrl}',
        subject:
            widget.isArabic ? 'رحلة سرتشات بالباص' : 'My SyrChat coach journey',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    final isArabic = widget.isArabic;
    setState(() => _busy = true);
    final n = await widget.api.revokeShares(journeyId: widget.journeyId);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isArabic
            ? 'تم إلغاء $n من روابط المشاركة'
            : 'Revoked $n share link${n == 1 ? '' : 's'}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.share_location_rounded,
              color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isArabic ? 'مشاركة الرحلة' : 'Share live journey',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : _buildContent(theme, isArabic),
      ),
      actions: <Widget>[
        if (_token != null)
          TextButton.icon(
            onPressed: _busy ? null : _revoke,
            icon: const Icon(Icons.link_off_rounded, size: 18),
            label: Text(isArabic ? 'إلغاء جميع الروابط' : 'Revoke all'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isArabic ? 'إغلاق' : 'Close'),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, bool isArabic) {
    final share = _token!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          isArabic
              ? 'يمكن لمن يستلم الرابط متابعة رحلتك المباشرة من المتصفح دون الحاجة إلى تثبيت التطبيق. سينتهي الرابط تلقائياً.'
              : 'Anyone with this link can follow your live coach journey from a browser — no app needed. The link expires automatically.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: .30)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  share.shareUrl,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  maxLines: 2,
                ),
              ),
              IconButton(
                tooltip: isArabic ? 'نسخ' : 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: _copy,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isArabic
              ? 'تنتهي الصلاحية: ${share.expiresAt}'
              : 'Expires: ${share.expiresAt}',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _shareIntent,
            icon: const Icon(Icons.send_rounded),
            label: Text(isArabic ? 'مشاركة الرابط' : 'Share link'),
          ),
        ),
      ],
    );
  }
}
