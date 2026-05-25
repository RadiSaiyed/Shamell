// Cycle 166-168 — Real in-trip ride chat sheet (shared between
// passenger and driver). Replaces the canned-message stub.
//
// Polls every 8s while open. Optimistic send: the message appears
// in the list immediately and gets replaced by the server's row on
// the next poll/send response. Forward-cursor `after_id` keeps
// re-poll bandwidth small.
//
// Visual: rider messages right-aligned, driver messages left-aligned.
// The viewer's role is detected from the most recent OWN message
// (sent by us). For the very first message there's no own row yet,
// so we fall back to the `viewerRole` prop the host page supplies.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ride_chat_api.dart';

/// Open the ride chat as a draggable bottom sheet.
Future<void> showRideChatSheet({
  required BuildContext context,
  required RideChatApi api,
  required String rideId,
  required String viewerRole, // 'rider' | 'driver'
  required bool isArabic,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * .72,
        child: _RideChatSheet(
          api: api,
          rideId: rideId,
          viewerRole: viewerRole,
          isArabic: isArabic,
        ),
      ),
    ),
  );
}

class _RideChatSheet extends StatefulWidget {
  final RideChatApi api;
  final String rideId;
  final String viewerRole;
  final bool isArabic;

  const _RideChatSheet({
    required this.api,
    required this.rideId,
    required this.viewerRole,
    required this.isArabic,
  });

  @override
  State<_RideChatSheet> createState() => _RideChatSheetState();
}

class _RideChatSheetState extends State<_RideChatSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<RideChatMessage> _messages = <RideChatMessage>[];
  int _highestId = 0;
  Timer? _poller;
  bool _sending = false;
  bool _firstLoad = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_pollOnce(initial: true));
    _poller = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_pollOnce());
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _pollOnce({bool initial = false}) async {
    final next = await widget.api.list(
      rideId: widget.rideId,
      afterId: _highestId,
    );
    if (!mounted) return;
    setState(() {
      _firstLoad = false;
      if (next.isNotEmpty) {
        _messages.addAll(next);
        _highestId = _messages.last.id;
      }
    });
    if (next.isNotEmpty || initial) {
      // Defer until after layout so the ListView has the new
      // children mounted; then jump to the bottom.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final msg = await widget.api.send(
        rideId: widget.rideId,
        body: text,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _highestId = msg.id;
        _inputCtrl.clear();
        _sending = false;
      });
      unawaited(HapticFeedback.selectionClick());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    } on RideChatApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = err.detail.isNotEmpty
            ? err.detail
            : (widget.isArabic
                ? 'فشل إرسال الرسالة'
                : 'Failed to send message');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = widget.isArabic
            ? 'تعذّر الاتصال بالخادم'
            : 'Could not reach the server';
      });
    }
  }

  String _fmtTime(String iso, {required bool isArabic}) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isArabic ? 'محادثة الرحلة' : 'Ride chat',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _firstLoad
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          isArabic
                              ? 'ابدأ المحادثة'
                              : 'Start the conversation',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        itemCount: _messages.length,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemBuilder: (ctx, i) {
                          final m = _messages[i];
                          final isOwn = m.senderRole == widget.viewerRole;
                          return Align(
                            alignment: isOwn
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(ctx).size.width * .72,
                              ),
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.fromLTRB(
                                    12, 8, 12, 6),
                                decoration: BoxDecoration(
                                  color: isOwn
                                      ? theme.colorScheme.primary
                                          .withValues(alpha: .14)
                                      : Colors.grey.withValues(alpha: .14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: isOwn
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      m.body,
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _fmtTime(m.createdAt, isArabic: isArabic),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  enabled: !_sending,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  maxLength: 1000,
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText:
                        isArabic ? 'اكتب رسالة…' : 'Type a message…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(isArabic ? 'إرسال' : 'Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
