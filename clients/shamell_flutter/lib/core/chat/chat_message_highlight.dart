import 'dart:async';

typedef ChatMessageHighlightTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

class ChatMessageHighlightController {
  ChatMessageHighlightController({
    this.duration = const Duration(milliseconds: 1400),
    ChatMessageHighlightTimerFactory? timerFactory,
  }) : _timerFactory =
            timerFactory ?? ((duration, callback) => Timer(duration, callback));

  final Duration duration;
  final ChatMessageHighlightTimerFactory _timerFactory;
  Timer? _timer;
  String? _highlightedMessageId;

  String? get highlightedMessageId => _highlightedMessageId;

  void flash(
    String messageId, {
    required void Function(String? highlightedMessageId) onChanged,
  }) {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return;
    }
    _timer?.cancel();
    _highlightedMessageId = normalizedMessageId;
    onChanged(_highlightedMessageId);
    _timer = _timerFactory(duration, () {
      if (_highlightedMessageId != normalizedMessageId) {
        return;
      }
      _highlightedMessageId = null;
      onChanged(null);
    });
  }

  void clear({
    void Function(String? highlightedMessageId)? onChanged,
  }) {
    final hadValue = _highlightedMessageId != null;
    _timer?.cancel();
    _timer = null;
    _highlightedMessageId = null;
    if (hadValue) {
      onChanged?.call(null);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _highlightedMessageId = null;
  }
}
