import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emergency_contact_store.dart';
import 'external_launch_guard.dart';
import 'http_error.dart';

import 'l10n.dart';
import 'shamell_ui.dart';

class ShamellSettingsEmergencyContactPage extends StatefulWidget {
  final String baseUrl;

  const ShamellSettingsEmergencyContactPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<ShamellSettingsEmergencyContactPage> createState() =>
      _ShamellSettingsEmergencyContactPageState();
}

class _ShamellSettingsEmergencyContactPageState
    extends State<ShamellSettingsEmergencyContactPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await loadEmergencyContactRecord(
        baseUrlOverride: widget.baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = record.name;
        _phoneCtrl.text = record.phone;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
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

      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      final saved = await saveEmergencyContactRecord(
        name: name,
        phone: phone,
        baseUrlOverride: widget.baseUrl,
      );
      if (!saved) {
        throw StateError('failed to persist emergency contact');
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
      _snack(l.isArabic ? 'تم الحفظ.' : 'Saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = sanitizeExceptionForUi(error: e);
      });
      _snack(l.isArabic ? 'تعذّر الحفظ.' : 'Could not save.');
    }
  }

  Future<void> _call() async {
    final l = L10n.of(context);
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    final uri = normalizeExternalDialUri(phone);
    if (uri == null) {
      _snack(
        l.isArabic
            ? 'لا يوجد رقم هاتف صالح.'
            : 'No valid phone number is available.',
      );
      return;
    }
    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) {
        _snack(
          l.isArabic
              ? 'لا يمكن فتح واجهة الاتصال على هذا الجهاز.'
              : 'Cannot open dialer on this device.',
        );
        return;
      }
      await launchUrl(
        uri,
        mode: shamellExternalLaunchMode(uri),
      );
    } catch (_) {}
  }

  Future<void> _clear() async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l.isArabic ? 'إزالة جهة الاتصال' : 'Remove contact'),
          content: Text(
            l.isArabic
                ? 'سيتم حذف جهة اتصال الطوارئ من هذا الجهاز.'
                : 'This will remove the emergency contact from this device.',
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
              child: Text(l.isArabic ? 'حذف' : 'Remove'),
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
      await clearEmergencyContactRecord(baseUrlOverride: widget.baseUrl);
      if (!mounted) return;
      setState(() {
        _nameCtrl.clear();
        _phoneCtrl.clear();
        _saving = false;
      });
      _snack(l.isArabic ? 'تمت الإزالة.' : 'Removed.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = sanitizeExceptionForUi(error: e);
      });
      _snack(l.isArabic ? 'تعذّر الإزالة.' : 'Could not remove.');
    }
  }

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
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

    final disabled = _loading || _saving;
    final phone = _phoneCtrl.text.trim();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'جهة اتصال الطوارئ' : 'Emergency contact',
        backgroundColor: bgColor,
        actions: [
          if (phone.isNotEmpty)
            IconButton(
              tooltip: l.isArabic ? 'اتصال' : 'Call',
              icon: const Icon(Icons.call),
              onPressed: disabled ? null : _call,
            ),
        ],
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
                l.isArabic
                    ? 'يمكنك إعداد جهة اتصال للطوارئ لسهولة الاتصال عند الحاجة.'
                    : 'Set an emergency contact for quick access when needed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .60),
                ),
              ),
            ),
            ShamellListSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                _inputField(
                  label: l.isArabic ? 'الاسم' : 'Name',
                  controller: _nameCtrl,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  enabled: !disabled,
                ),
                _inputField(
                  label: l.isArabic ? 'رقم الهاتف' : 'Phone',
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    LengthLimitingTextInputFormatter(32),
                  ],
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
                onPressed: disabled ? null : _clear,
                child: Text(l.isArabic ? 'إزالة' : 'Remove'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
