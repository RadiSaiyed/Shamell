// Cycle 56 — profile editor: avatar + display name.
//
// Surfaced from the chat-list AppBar leading icon. The page is
// dumb: it takes load + save callbacks so the chat page owns the
// `ChatService.getMyProfile / setMyProfile` round-trips and the
// device id resolution.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';

class ChatProfileEditorPage extends StatefulWidget {
  /// Load my current profile. Empty map = never set.
  final Future<Map<String, Object?>> Function() onLoad;

  /// Save the new profile. `displayName`/`avatarB64`/`avatarMime` are
  /// the trimmed-to-send values; `clearAvatar` is set when the user
  /// taps the "Remove avatar" action. Cycle 58 added the status
  /// fields with the same "null = leave alone, clearStatus = drop"
  /// semantic.
  final Future<void> Function({
    String? displayName,
    String? avatarB64,
    String? avatarMime,
    bool clearAvatar,
    String? statusEmoji,
    String? statusText,
    bool clearStatus,
  }) onSave;

  const ChatProfileEditorPage({
    super.key,
    required this.onLoad,
    required this.onSave,
  });

  @override
  State<ChatProfileEditorPage> createState() => _ChatProfileEditorPageState();
}

class _ChatProfileEditorPageState extends State<ChatProfileEditorPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  /// Cycle 58 — Slack-style status. Emoji + short text are separate
  /// fields so the renderer can show "🌴 vacation" with the emoji
  /// in its own slot.
  final TextEditingController _statusEmojiCtrl = TextEditingController();
  final TextEditingController _statusTextCtrl = TextEditingController();
  Uint8List? _avatarBytes;
  String? _avatarMime;
  bool _firstLoad = true;
  bool _saving = false;
  /// `true` when the user has dropped the existing avatar via the
  /// "Remove" action — different from "I haven't touched the avatar".
  bool _avatarClearPending = false;
  bool _statusClearPending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _statusEmojiCtrl.dispose();
    _statusTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await widget.onLoad();
      if (!mounted) return;
      _nameCtrl.text = (me['display_name'] as String?)?.trim() ?? '';
      _statusEmojiCtrl.text = (me['status_emoji'] as String?)?.trim() ?? '';
      _statusTextCtrl.text = (me['status_text'] as String?)?.trim() ?? '';
      final b64 = (me['avatar_b64'] as String?)?.trim();
      Uint8List? bytes;
      if (b64 != null && b64.isNotEmpty) {
        try {
          bytes = base64Decode(b64);
        } catch (_) {}
      }
      setState(() {
        _avatarBytes = bytes;
        _avatarMime = me['avatar_mime'] as String?;
        _firstLoad = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _firstLoad = false);
    }
  }

  Future<void> _pickAvatar() async {
    final l = L10n.of(context);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 150 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.isArabic
              ? 'الصورة كبيرة جدًا (حد 150 ك.ب).'
              : 'Avatar too large (150 KB max).')),
        );
        return;
      }
      setState(() {
        _avatarBytes = bytes;
        _avatarMime = file.mimeType ?? 'image/jpeg';
        _avatarClearPending = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.isArabic
            ? 'تعذّر اختيار الصورة.'
            : 'Could not pick image.')),
      );
    }
  }

  void _clearAvatar() {
    setState(() {
      _avatarBytes = null;
      _avatarMime = null;
      _avatarClearPending = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final l = L10n.of(context);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic ? 'الاسم مطلوب.' : 'Name is required.'),
      ));
      return;
    }
    if (name.length > 40) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic
            ? 'الاسم طويل جدًا (حد 40 حرفًا).'
            : 'Name too long (40 chars max).'),
      ));
      return;
    }
    final statusEmoji = _statusEmojiCtrl.text.trim();
    final statusText = _statusTextCtrl.text.trim();
    if (statusEmoji.isNotEmpty && statusEmoji.runes.length > 8) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic
            ? 'الرمز التعبيري طويل جدًا.'
            : 'Status emoji is too long.'),
      ));
      return;
    }
    if (statusText.length > 60) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic
            ? 'نص الحالة طويل جدًا (حد 60 حرفًا).'
            : 'Status text too long (60 chars max).'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      String? avatarB64;
      String? avatarMime;
      if (_avatarClearPending) {
        avatarB64 = null;
        avatarMime = null;
      } else if (_avatarBytes != null) {
        avatarB64 = base64Encode(_avatarBytes!);
        avatarMime = _avatarMime ?? 'image/jpeg';
      }
      // Cycle 58 — status payload. Empty strings on both fields with
      // no `_statusClearPending` means "no change"; if either is
      // explicitly cleared via the "Clear status" action we route
      // through the `clearStatus: true` flag.
      String? emojiPayload;
      String? textPayload;
      if (!_statusClearPending) {
        if (statusEmoji.isNotEmpty) emojiPayload = statusEmoji;
        if (statusText.isNotEmpty) textPayload = statusText;
      }
      await widget.onSave(
        displayName: name,
        avatarB64: avatarB64,
        avatarMime: avatarMime,
        clearAvatar: _avatarClearPending,
        statusEmoji: emojiPayload,
        statusText: textPayload,
        clearStatus: _statusClearPending,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic ? 'تم الحفظ.' : 'Saved.'),
      ));
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic ? 'تعذّر الحفظ.' : 'Save failed.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'الملف الشخصي' : 'My profile'),
      ),
      body: _firstLoad
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: <Widget>[
                Center(
                  child: GestureDetector(
                    onTap: _saving ? null : _pickAvatar,
                    child: Stack(
                      children: <Widget>[
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _avatarBytes != null
                              ? Image.memory(_avatarBytes!,
                                  fit: BoxFit.cover)
                              : Icon(Icons.person_outline,
                                  size: 64,
                                  color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.surface,
                                width: 2,
                              ),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_avatarBytes != null)
                  Center(
                    child: TextButton.icon(
                      onPressed: _saving ? null : _clearAvatar,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(
                          l.isArabic ? 'إزالة الصورة' : 'Remove avatar'),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  l.isArabic ? 'الاسم المعروض' : 'Display name',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  maxLength: 40,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    hintText: l.isArabic ? 'اسمك' : 'Your name',
                    counterText: '',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Cycle 58 — status (emoji + short text).
                Text(
                  l.isArabic ? 'الحالة' : 'Status',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 56,
                      child: TextField(
                        controller: _statusEmojiCtrl,
                        enabled: !_saving,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22),
                        maxLength: 8,
                        decoration: InputDecoration(
                          hintText: '🌴',
                          counterText: '',
                          filled: true,
                          fillColor:
                              theme.colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _statusTextCtrl,
                        enabled: !_saving,
                        maxLength: 60,
                        decoration: InputDecoration(
                          hintText:
                              l.isArabic ? 'في رحلة' : 'On vacation',
                          counterText: '',
                          filled: true,
                          fillColor:
                              theme.colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_statusEmojiCtrl.text.trim().isNotEmpty ||
                    _statusTextCtrl.text.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              _statusEmojiCtrl.clear();
                              _statusTextCtrl.clear();
                              setState(() => _statusClearPending = true);
                            },
                      icon:
                          const Icon(Icons.cancel_outlined, size: 18),
                      label: Text(
                          l.isArabic ? 'مسح الحالة' : 'Clear status'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(l.isArabic ? 'حفظ' : 'Save'),
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}
