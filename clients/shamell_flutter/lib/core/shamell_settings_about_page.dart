import 'package:flutter/material.dart';

import 'l10n.dart';
import 'shamell_ui.dart';

class ShamellSettingsAboutPage extends StatelessWidget {
  const ShamellSettingsAboutPage({super.key});

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

    final appVersion = const String.fromEnvironment('APP_VERSION');
    final build = const String.fromEnvironment('APP_BUILD');

    String versionText() {
      final parts = <String>[
        if (appVersion.trim().isNotEmpty) appVersion.trim(),
        if (build.trim().isNotEmpty) build.trim(),
      ];
      return parts.join(' ');
    }

    final version = versionText();

    Widget trailingVersion() {
      return Text(
        version.isEmpty ? '—' : version,
        style: shamellSettingsValueStyle(context),
      );
    }

    void openLicenses() {
      showLicensePage(
        context: context,
        applicationName: l.appTitle,
        applicationVersion: version.isEmpty ? null : version,
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'حول سرتشات' : 'About SyrChat',
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ShamellLeadingIcon(
                      icon: Icons.chat_bubble_rounded,
                      background: ShamellPalette.green,
                      size: 64,
                      iconSize: 34,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.appTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (version.isNotEmpty)
                      Text(
                        '${l.isArabic ? 'الإصدار' : 'Version'} $version',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ShamellListSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                ListTile(
                  title: Text(l.isArabic ? 'الإصدار' : 'Version'),
                  trailing: trailingVersion(),
                ),
                ListTile(
                  title: Text(l.isArabic ? 'الترخيص' : 'Licenses'),
                  trailing: chevron(),
                  onTap: openLicenses,
                ),
              ],
            ),
            ShamellListSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                ListTile(
                  title: Text(l.isArabic ? 'التحديثات' : 'Updates'),
                  subtitle: Text(
                    l.isArabic
                        ? 'يتم تثبيت التحديثات من خلال متجر التطبيقات على جهازك.'
                        : 'Updates are installed through your device app store.',
                  ),
                ),
              ],
            ),
            ShamellListSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                ListTile(
                  title: Text(
                    l.isArabic ? 'ملخص الشروط' : 'Terms summary',
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'ملخص داخل التطبيق فقط: تسجيل دخول ببصمة الجهاز، ومسؤولية المستخدم عن أمان الجهاز، وقد تتغير الميزات أثناء التطوير. تواصل مع الدعم للحصول على النص القانوني الرسمي.'
                        : 'In-app summary only: biometric sign-in, device-security responsibility, and features may change during development. Contact support for the official legal text.',
                  ),
                ),
                ListTile(
                  title: Text(
                    l.isArabic ? 'ملخص الخصوصية' : 'Privacy summary',
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'ملخص داخل التطبيق فقط: قد يخزن التطبيق تفضيلات محلية على الجهاز، ويمكن إدارة بعض خيارات الخصوصية من صفحة الخصوصية. تواصل مع الدعم للحصول على السياسة الرسمية أو طلب حذف البيانات.'
                        : 'In-app summary only: the app may store local device preferences, and some privacy options are managed from Settings -> Privacy. Contact support for the official policy or data-deletion requests.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
