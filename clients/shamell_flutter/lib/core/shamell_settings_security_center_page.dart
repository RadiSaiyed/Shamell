import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'biometric_preference_store.dart';
import 'devices_page.dart';
import 'l10n.dart';
import 'shamell_settings_emergency_contact_page.dart';
import 'shamell_settings_password_page.dart';
import 'shamell_ui.dart';

class ShamellSettingsSecurityCenterPage extends StatefulWidget {
  final String baseUrl;

  const ShamellSettingsSecurityCenterPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<ShamellSettingsSecurityCenterPage> createState() =>
      _ShamellSettingsSecurityCenterPageState();
}

class _ShamellSettingsSecurityCenterPageState
    extends State<ShamellSettingsSecurityCenterPage> {
  bool _loading = true;
  bool _requireBiometrics = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final require = await loadRequireBiometricsPreference(
        baseUrlOverride: widget.baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _requireBiometrics = require;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _setRequireBiometrics(bool v) async {
    setState(() => _requireBiometrics = v);
    try {
      await saveRequireBiometricsPreference(
        v,
        baseUrlOverride: widget.baseUrl,
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

    Icon chevron({bool enabled = true}) => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface
              .withValues(alpha: enabled ? .40 : .20),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'مركز الأمان' : 'Security Center',
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        child: ListView(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                l.isArabic
                    ? 'إدارة خيارات الأمان لحسابك وهذا الجهاز.'
                    : 'Manage security options for your account and this device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .60),
                ),
              ),
            ),
            ShamellListSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                ListTile(
                  title: Text(l.isArabic ? 'كلمة المرور' : 'Password'),
                  trailing: chevron(enabled: !_loading),
                  onTap: _loading
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ShamellSettingsPasswordPage(
                                baseUrl: widget.baseUrl,
                              ),
                            ),
                          );
                        },
                ),
                ListTile(
                  title: Text(
                      l.isArabic ? 'جهة اتصال الطوارئ' : 'Emergency contact'),
                  trailing: chevron(enabled: !_loading),
                  onTap: _loading
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ShamellSettingsEmergencyContactPage(
                                baseUrl: widget.baseUrl,
                              ),
                            ),
                          );
                        },
                ),
                ListTile(
                  title:
                      Text(l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices'),
                  trailing: chevron(enabled: !_loading),
                  onTap: _loading
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  DevicesPage(baseUrl: widget.baseUrl),
                            ),
                          );
                        },
                ),
              ],
            ),
            ShamellListSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                ListTile(
                  title: Text(
                    l.isArabic
                        ? 'تسجيل الدخول بالبصمة'
                        : 'Login with biometrics',
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'اطلب المصادقة عند فتح التطبيق.'
                        : 'Require authentication when opening the app.',
                  ),
                  trailing: ShamellCompactSwitch(
                    value: _requireBiometrics,
                    onChanged: _loading
                        ? null
                        : (v) async {
                            try {
                              await HapticFeedback.selectionClick();
                            } catch (_) {}
                            await _setRequireBiometrics(v);
                          },
                  ),
                  onTap: _loading
                      ? null
                      : () => _setRequireBiometrics(!_requireBiometrics),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
