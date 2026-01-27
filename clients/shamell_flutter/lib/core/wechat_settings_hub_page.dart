import 'package:flutter/material.dart';

import 'l10n.dart';
import 'wechat_new_message_notification_page.dart';
import 'wechat_settings_about_page.dart';
import 'wechat_settings_account_security_page.dart';
import 'wechat_settings_general_page.dart';
import 'wechat_settings_privacy_page.dart';
import 'wechat_ui.dart';

class WeChatSettingsHubPage extends StatelessWidget {
  final String baseUrl;
  final String deviceId;
  final String? profileName;
  final String? profileId;

  const WeChatSettingsHubPage({
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
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

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
          WeChatSection(
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
                      builder: (_) => WeChatSettingsAccountSecurityPage(
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
          WeChatSection(
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
                      builder: (_) => WeChatNewMessageNotificationPage(
                        baseUrl: baseUrl,
                      ),
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
                title: Text(l.isArabic ? 'الخصوصية' : 'Privacy'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WeChatSettingsPrivacyPage(
                        baseUrl: baseUrl,
                        deviceId: deviceId,
                      ),
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
                title: Text(l.isArabic ? 'عام' : 'General'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WeChatSettingsGeneralPage(),
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
                title: Text(l.isArabic ? 'حول شامل' : 'About Shamell'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WeChatSettingsAboutPage(),
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
