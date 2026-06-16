import 'package:flutter/material.dart';

import 'l10n.dart';
import 'shamell_new_message_notification_page.dart';
import 'shamell_settings_about_page.dart';
import 'shamell_settings_account_security_page.dart';
import 'shamell_settings_general_page.dart';
import 'shamell_settings_privacy_page.dart';
import 'shamell_ui.dart';

class ShamellSettingsHubPage extends StatelessWidget {
  final String baseUrl;
  final String deviceId;
  final String? profileName;
  final String? profileId;

  const ShamellSettingsHubPage({
    super.key,
    required this.baseUrl,
    required this.deviceId,
    this.profileName,
    this.profileId,
  });

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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.settingsTitle),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 0),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'أمان الحساب' : 'Account Security'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShamellSettingsAccountSecurityPage(
                        baseUrl: baseUrl,
                        deviceId: deviceId,
                        profileName: profileName,
                        profileId: profileId,
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
                  l.isArabic
                      ? 'إشعارات الرسائل الجديدة'
                      : 'New Message Notification',
                ),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShamellNewMessageNotificationPage(
                        baseUrl: baseUrl,
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
                title: Text(l.isArabic ? 'الخصوصية' : 'Privacy'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShamellSettingsPrivacyPage(
                        baseUrl: baseUrl,
                        deviceId: deviceId,
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
                title: Text(l.isArabic ? 'عام' : 'General'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellSettingsGeneralPage(),
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
                title: Text(l.isArabic ? 'حول شامل' : 'About Shamell'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellSettingsAboutPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
