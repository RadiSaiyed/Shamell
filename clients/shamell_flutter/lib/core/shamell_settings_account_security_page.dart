import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devices_page.dart';
import 'l10n.dart';
import 'shamell_settings_emergency_contact_page.dart';
import 'shamell_settings_password_page.dart';
import 'shamell_settings_security_center_page.dart';
import 'shamell_user_id.dart';
import 'shamell_ui.dart';

class ShamellSettingsAccountSecurityPage extends StatefulWidget {
  final String baseUrl;
  final String deviceId;
  final String? profileName;
  final String? profileId;

  const ShamellSettingsAccountSecurityPage({
    super.key,
    required this.baseUrl,
    required this.deviceId,
    this.profileName,
    this.profileId,
  });

  @override
  State<ShamellSettingsAccountSecurityPage> createState() =>
      _ShamellSettingsAccountSecurityPageState();
}

class _ShamellSettingsAccountSecurityPageState
    extends State<ShamellSettingsAccountSecurityPage> {
  bool _requireBiometrics = false;
  String _profilePhone = '';
  String _profileShamellId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final require = sp.getBool('require_biometrics') ?? false;
      final storedProfilePhone = sp.getString('last_login_phone') ?? '';
      final shamellUserId = await getOrCreateShamellUserId(sp: sp);
      if (!mounted) return;
      setState(() {
        _requireBiometrics = require;
        _profilePhone = storedProfilePhone;
        _profileShamellId = shamellUserId;
      });
    } catch (_) {}
  }

  Future<void> _setRequireBiometrics(bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('require_biometrics', v);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _requireBiometrics = v);
  }

  Future<void> _copy(BuildContext context, String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    final l = L10n.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تم النسخ.' : 'Copied.',
          ),
          duration: const Duration(milliseconds: 900),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    final profileId = (widget.profileId ?? '').trim();
    final profilePhone = _profilePhone.trim();
    final shamellId = profileId.isNotEmpty ? profileId : _profileShamellId.trim();

    Widget trailingValue(String value, {String? emptyLabel}) {
      final v = value.trim();
      return Text(
        v.isEmpty ? (emptyLabel ?? (l.isArabic ? 'غير مضبوط' : 'Not set')) : v,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'أمان الحساب' : 'Account Security'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'معرّف شامل' : 'Shamell ID'),
                trailing: trailingValue(shamellId),
                onTap:
                    shamellId.isEmpty ? null : () => _copy(context, shamellId),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'رقم الهاتف' : 'Phone'),
                trailing: trailingValue(
                  profilePhone,
                  emptyLabel: l.isArabic ? 'غير مرتبط' : 'Not linked',
                ),
                onTap: profilePhone.isEmpty
                    ? null
                    : () => _copy(context, profilePhone),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'كلمة المرور' : 'Password'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellSettingsPasswordPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DevicesPage(baseUrl: widget.baseUrl),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(
                    l.isArabic ? 'جهة اتصال الطوارئ' : 'Emergency contact'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ShamellSettingsEmergencyContactPage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'مركز الأمان' : 'Security Center'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShamellSettingsSecurityCenterPage(
                        baseUrl: widget.baseUrl,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'تسجيل الدخول بالبصمة' : 'Login with biometrics',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'اطلب المصادقة عند فتح التطبيق.'
                      : 'Require authentication when opening the app.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                trailing: Switch(
                  value: _requireBiometrics,
                  onChanged: _setRequireBiometrics,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
