// ignore_for_file: deprecated_member_use

import 'http_error.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'local_password_hash.dart';
import 'shamell_settings_password_store.dart';
import 'shamell_ui.dart';

class ShamellSettingsPasswordPage extends StatefulWidget {
  final String baseUrl;

  const ShamellSettingsPasswordPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<ShamellSettingsPasswordPage> createState() =>
      _ShamellSettingsPasswordPageState();
}

class _ShamellSettingsPasswordPageState
    extends State<ShamellSettingsPasswordPage> {
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hash = await loadStoredLocalPasswordHash(
        baseUrlOverride: widget.baseUrl,
      );
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
        _error = sanitizeExceptionForUi(error: e);
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
        if (stored.isEmpty || !verifyLocalPassword(current, stored)) {
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

      final newHash = hashLocalPassword(_newCtrl.text.trim());
      await saveStoredLocalPasswordHash(
        newHash,
        baseUrlOverride: widget.baseUrl,
      );
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
        _error = sanitizeExceptionForUi(error: e);
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
              child: Text(l.shamellDialogCancel),
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
      await clearStoredLocalPasswordHashForCurrentScope(
        baseUrlOverride: widget.baseUrl,
      );
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
        _error = sanitizeExceptionForUi(error: e);
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: true,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        decoration: shamellSettingsInputDecoration(
          context,
          label: label,
        ),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    final title = l.isArabic ? 'كلمة المرور' : 'Password';
    final hint = l.isArabic
        ? 'ملاحظة: هذه كلمة مرور محلية لهذا الجهاز.'
        : 'Note: This is a local password for this device.';

    final disabled = _loading || _saving;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: title,
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        child: ListView(
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
            ShamellListSection(
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
                  backgroundColor: ShamellPalette.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: theme.colorScheme.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: disabled ? null : _remove,
                  child: Text(
                      l.isArabic ? 'إيقاف كلمة المرور' : 'Turn off password'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
