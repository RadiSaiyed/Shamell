import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_preference_store.dart';
import 'devices_page.dart';
import 'legacy_sensitive_pref_store.dart';
import 'l10n.dart';
import 'safe_clipboard.dart';
import 'shamell_settings_emergency_contact_page.dart';
import 'shamell_settings_password_page.dart';
import 'shamell_user_id.dart';
import 'shamell_ui.dart';

Widget _settingsReveal({
  required BuildContext context,
  required int order,
  required Widget child,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  if (reduceMotion) return child;
  final start = (order * 0.12).clamp(0.0, 0.72).toDouble();
  return TweenAnimationBuilder<double>(
    key: ValueKey<String>('acc-sec-reveal-$order'),
    duration: const Duration(milliseconds: 460),
    curve: Interval(start, 1, curve: Curves.easeOutCubic),
    tween: Tween<double>(begin: 0, end: 1),
    child: child,
    builder: (context, value, child) {
      final y = (1 - value) * 14;
      return Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, y), child: child),
      );
    },
  );
}

class ShamellSettingsAccountSecurityPage extends StatefulWidget {
  final String baseUrl;
  final String? profileId;

  const ShamellSettingsAccountSecurityPage({
    super.key,
    required this.baseUrl,
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
      final require = await loadRequireBiometricsPreference(
        sp: sp,
        baseUrlOverride: widget.baseUrl,
      );
      final profile = await loadLegacyProfileSummary(
        sp: sp,
        baseUrlOverride: widget.baseUrl,
      );
      final shamellUserId = await loadShamellUserId(
            sp: sp,
            baseUrlOverride: widget.baseUrl,
          ) ??
          '';
      if (!mounted) return;
      setState(() {
        _requireBiometrics = require;
        _profilePhone = profile.phone;
        _profileShamellId = shamellUserId;
      });
    } catch (_) {}
  }

  Future<void> _setRequireBiometrics(bool v) async {
    try {
      await saveRequireBiometricsPreference(
        v,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _requireBiometrics = v);
  }

  Future<void> _copy(BuildContext context, String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    final l = L10n.of(context);
    try {
      await shamellCopyToClipboard(
        text,
        sensitive: true,
      );
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
          color: theme.colorScheme.onSurface.withValues(alpha: .52),
        );

    final profileId = (widget.profileId ?? '').trim();
    final profilePhone = _profilePhone.trim();
    final shamellId =
        profileId.isNotEmpty ? profileId : _profileShamellId.trim();

    Widget trailingValue(String value, {String? emptyLabel}) {
      final v = value.trim();
      return Text(
        v.isEmpty ? (emptyLabel ?? (l.isArabic ? 'غير مضبوط' : 'Not set')) : v,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: .68),
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'أمان الحساب' : 'Account Security',
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        child: ListView(
          children: [
            _settingsReveal(
              context: context,
              order: 0,
              child: ShamellListSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  ListTile(
                    title: Text(l.isArabic ? 'معرّف سرتشات' : 'SyrChat ID'),
                    trailing: trailingValue(shamellId),
                    onTap: shamellId.isEmpty
                        ? null
                        : () => _copy(context, shamellId),
                  ),
                  ListTile(
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
                    title: Text(l.isArabic ? 'كلمة المرور' : 'Password'),
                    trailing: chevron(),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShamellSettingsPasswordPage(
                            baseUrl: widget.baseUrl,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            _settingsReveal(
              context: context,
              order: 1,
              child: ShamellListSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  ListTile(
                    title: Text(
                      l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices',
                    ),
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
                    title: Text(
                      l.isArabic ? 'جهة اتصال الطوارئ' : 'Emergency contact',
                    ),
                    trailing: chevron(),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShamellSettingsEmergencyContactPage(
                            baseUrl: widget.baseUrl,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            _settingsReveal(
              context: context,
              order: 2,
              child: ShamellListSection(
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
                      onChanged: _setRequireBiometrics,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
