import 'package:flutter/material.dart';

import '../l10n.dart';

/// What the creator dialog returns when the user taps "Send". The
/// chat page hands these to a regular `_send` (with body = poll-
/// pointer envelope) + then `ChatService.createPoll` to register
/// the server-side tally bookkeeping.
class ChatPollDraft {
  final String question;
  final List<String> options;
  final bool multiSelect;
  final bool anonymous;
  const ChatPollDraft({
    required this.question,
    required this.options,
    this.multiSelect = false,
    this.anonymous = false,
  });
}

/// Cycle 14 — composer-side "create a poll" dialog.
/// Two TextFields for the question + 2..10 dynamic option fields.
class ChatPollCreatorDialog extends StatefulWidget {
  static const int minOptions = 2;
  static const int maxOptions = 10;
  static const int maxQuestionLen = 500;
  static const int maxOptionLen = 100;

  const ChatPollCreatorDialog({super.key});

  /// Convenience helper: open the dialog and return the draft (or
  /// `null` on cancel).
  static Future<ChatPollDraft?> show(BuildContext context) =>
      showDialog<ChatPollDraft>(
        context: context,
        builder: (_) => const ChatPollCreatorDialog(),
      );

  @override
  State<ChatPollCreatorDialog> createState() => _ChatPollCreatorDialogState();
}

class _ChatPollCreatorDialogState extends State<ChatPollCreatorDialog> {
  final TextEditingController _qCtrl = TextEditingController();
  final List<TextEditingController> _optCtrls = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multiSelect = false;
  bool _anonymous = false;
  String? _error;

  @override
  void dispose() {
    _qCtrl.dispose();
    for (final c in _optCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optCtrls.length >= ChatPollCreatorDialog.maxOptions) return;
    setState(() => _optCtrls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optCtrls.length <= ChatPollCreatorDialog.minOptions) return;
    setState(() => _optCtrls.removeAt(i).dispose());
  }

  void _onSubmit() {
    final q = _qCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _error = 'q-empty');
      return;
    }
    final opts = _optCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (opts.length < ChatPollCreatorDialog.minOptions) {
      setState(() => _error = 'opts-too-few');
      return;
    }
    if (opts.toSet().length != opts.length) {
      setState(() => _error = 'opts-duplicate');
      return;
    }
    Navigator.of(context).pop(ChatPollDraft(
      question: q,
      options: opts,
      multiSelect: _multiSelect,
      anonymous: _anonymous,
    ));
  }

  String? _errorText(L10n l) {
    switch (_error) {
      case 'q-empty':
        return l.isArabic ? 'السؤال مطلوب' : 'Question required';
      case 'opts-too-few':
        return l.isArabic
            ? 'يجب توفير خيارين على الأقل'
            : 'At least 2 options required';
      case 'opts-duplicate':
        return l.isArabic
            ? 'لا يمكن تكرار الخيارات'
            : 'Options must be unique';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.isArabic ? 'استطلاع جديد' : 'New poll'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _qCtrl,
              maxLength: ChatPollCreatorDialog.maxQuestionLen,
              decoration: InputDecoration(
                labelText: l.isArabic ? 'السؤال' : 'Question',
                hintText: l.isArabic
                    ? 'مثل: ما هي وجبة الغداء؟'
                    : 'e.g. What\'s for lunch?',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 4),
            for (int i = 0; i < _optCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _optCtrls[i],
                        maxLength: ChatPollCreatorDialog.maxOptionLen,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'الخيار ${i + 1}'
                              : 'Option ${i + 1}',
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                    ),
                    if (_optCtrls.length > ChatPollCreatorDialog.minOptions)
                      IconButton(
                        tooltip: l.isArabic ? 'حذف الخيار' : 'Remove option',
                        icon: const Icon(Icons.remove_circle_outline),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeOption(i),
                      ),
                  ],
                ),
              ),
            if (_optCtrls.length < ChatPollCreatorDialog.maxOptions)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l.isArabic ? 'إضافة خيار' : 'Add option'),
                  onPressed: _addOption,
                ),
              ),
            CheckboxListTile(
              value: _multiSelect,
              onChanged: (v) => setState(() => _multiSelect = v ?? false),
              title: Text(
                l.isArabic ? 'السماح بتعدد الخيارات' : 'Allow multiple choices',
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v ?? false),
              title: Text(
                l.isArabic ? 'تصويت مجهول' : 'Anonymous voting',
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_errorText(l) != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                _errorText(l)!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.shamellDialogCancel),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: Text(l.chatSend),
          onPressed: _onSubmit,
        ),
      ],
    );
  }
}
