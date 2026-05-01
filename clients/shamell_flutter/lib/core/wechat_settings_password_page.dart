import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'l10n.dart';
import 'wechat_ui.dart';

class WeChatSettingsPasswordPage extends StatefulWidget {
  const WeChatSettingsPasswordPage({super.key});

  @override
  State<WeChatSettingsPasswordPage> createState() =>
      _WeChatSettingsPasswordPageState();
}

class _WeChatSettingsPasswordPageState
    extends State<WeChatSettingsPasswordPage> {
  static const _storage = FlutterSecureStorage();
  static const _kPasswordHashKey = 'wechat.security.password_hash.v1';

  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _hasPassword = false;
  String? _storedHash;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _hash(String raw) {
    final bytes = utf8.encode(raw);
    return crypto.sha256.convert(bytes).toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hash = await _storage.read(key: _kPasswordHashKey);
      if (!mounted) return;
      setState(() {
        _storedHash = hash;
        _hasPassword = (hash ?? '').trim().isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storedHash = null;
        _hasPassword = false;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validateNewPassword(L10n l, String pass, String confirm) {
    final p = pass.trim();
    if (p.length < 6) {
      return l.isArabic
          ? 'يجب أن تكون كلمة المرور 6 أحرف على الأقل.'
          : 'Password must be at least 6 characters.';
    }
    if (p != confirm.trim()) {
      return l.isArabic
          ? 'كلمتا المرور غير متطابقتين.'
          : 'Passwords do not match.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    final l = L10n.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}

      if (_hasPassword) {
        final current = _currentCtrl.text.trim();
        final stored = (_storedHash ?? '').trim();
        if (stored.isEmpty || _hash(current) != stored) {
          setState(() {
            _saving = false;
          });
          _showSnack(l.isArabic
              ? 'كلمة المرور الحالية غير صحيحة.'
              : 'Incorrect current password.');
          return;
        }
      }

      final err = _validateNewPassword(l, _newCtrl.text, _confirmCtrl.text);
      if (err != null) {
        setState(() {
          _saving = false;
        });
        _showSnack(err);
        return;
      }

      final newHash = _hash(_newCtrl.text.trim());
      await _storage.write(key: _kPasswordHashKey, value: newHash);
      if (!mounted) return;
      setState(() {
        _storedHash = newHash;
        _hasPassword = true;
        _saving = false;
        _currentCtrl.clear();
        _newCtrl.clear();
        _confirmCtrl.clear();
      });
      _showSnack(l.isArabic ? 'تم تحديث كلمة المرور.' : 'Password updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
      _showSnack(
          l.isArabic ? 'تعذّر حفظ كلمة المرور.' : 'Could not save password.');
    }
  }

  Future<void> _remove() async {
    if (_saving || _loading) return;
    final l = L10n.of(context);
    if (!_hasPassword) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l.isArabic ? 'إيقاف كلمة المرور' : 'Turn off password'),
          content: Text(
            l.isArabic
                ? 'سيتم حذف كلمة المرور من هذا الجهاز.'
                : 'This will remove the password from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.mirsaalDialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFA5151),
                foregroundColor: Colors.white,
              ),
              child: Text(l.isArabic ? 'إيقاف' : 'Turn off'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _storage.delete(key: _kPasswordHashKey);
      if (!mounted) return;
      setState(() {
        _storedHash = null;
        _hasPassword = false;
        _saving = false;
        _currentCtrl.clear();
        _newCtrl.clear();
        _confirmCtrl.clear();
      });
      _showSnack(l.isArabic ? 'تم إيقاف كلمة المرور.' : 'Password turned off.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
      _showSnack(l.isArabic
          ? 'تعذّر إيقاف كلمة المرور.'
          : 'Could not turn off password.');
    }
  }

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: true,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .65),
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

    final title = l.isArabic ? 'كلمة المرور' : 'Password';
    final hint = l.isArabic
        ? 'ملاحظة: هذه كلمة مرور محلية لهذا الجهاز.'
        : 'Note: This is a local password for this device.';

    final disabled = _loading || _saving;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .60),
              ),
            ),
          ),
          WeChatSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              if (_hasPassword)
                _inputField(
                  label:
                      l.isArabic ? 'كلمة المرور الحالية' : 'Current password',
                  controller: _currentCtrl,
                  textInputAction: TextInputAction.next,
                  enabled: !disabled,
                ),
              _inputField(
                label: _hasPassword
                    ? (l.isArabic ? 'كلمة مرور جديدة' : 'New password')
                    : (l.isArabic ? 'كلمة المرور' : 'Password'),
                controller: _newCtrl,
                textInputAction: TextInputAction.next,
                enabled: !disabled,
              ),
              _inputField(
                label: l.isArabic ? 'تأكيد كلمة المرور' : 'Confirm password',
                controller: _confirmCtrl,
                textInputAction: TextInputAction.done,
                enabled: !disabled,
                onSubmitted: (_) => _save(),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: WeChatPalette.green,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: disabled ? null : _save,
              child: Text(l.isArabic ? 'حفظ' : 'Save'),
            ),
          ),
          if (_hasPassword)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: disabled ? null : _remove,
                child: Text(
                    l.isArabic ? 'إيقاف كلمة المرور' : 'Turn off password'),
              ),
            ),
        ],
      ),
    );
  }
}
