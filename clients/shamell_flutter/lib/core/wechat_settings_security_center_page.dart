import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devices_page.dart';
import 'l10n.dart';
import 'wechat_settings_emergency_contact_page.dart';
import 'wechat_settings_password_page.dart';
import 'wechat_ui.dart';

class WeChatSettingsSecurityCenterPage extends StatefulWidget {
  final String baseUrl;

  const WeChatSettingsSecurityCenterPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<WeChatSettingsSecurityCenterPage> createState() =>
      _WeChatSettingsSecurityCenterPageState();
}

class _WeChatSettingsSecurityCenterPageState
    extends State<WeChatSettingsSecurityCenterPage> {
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
      final sp = await SharedPreferences.getInstance();
      final require = sp.getBool('require_biometrics') ?? false;
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
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('require_biometrics', v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

    Icon chevron({bool enabled = true}) => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface
              .withValues(alpha: enabled ? .40 : .20),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'مركز الأمان' : 'Security Center'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
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
          WeChatSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'كلمة المرور' : 'Password'),
                trailing: chevron(enabled: !_loading),
                onTap: _loading
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WeChatSettingsPasswordPage(),
                          ),
                        );
                      },
              ),
              ListTile(
                dense: true,
                title: Text(
                    l.isArabic ? 'جهة اتصال الطوارئ' : 'Emergency contact'),
                trailing: chevron(enabled: !_loading),
                onTap: _loading
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const WeChatSettingsEmergencyContactPage(),
                          ),
                        );
                      },
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices'),
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
          WeChatSection(
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
    );
  }
}
