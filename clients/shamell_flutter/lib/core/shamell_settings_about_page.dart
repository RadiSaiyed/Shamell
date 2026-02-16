import 'package:flutter/material.dart';

import 'l10n.dart';
import 'shamell_legal_pages.dart';
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
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        ),
      );
    }

    void openLicenses() {
      showLicensePage(
        context: context,
        applicationName: l.appTitle,
        applicationVersion: version.isEmpty ? null : version,
      );
    }

    void snack(String msg) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'حول شامل' : 'About Shamell'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ShamellLeadingIcon(
                    icon: Icons.chat_bubble_rounded,
                    background: ShamellPalette.green,
                    size: 64,
                    iconSize: 34,
                    borderRadius: BorderRadius.all(Radius.circular(16)),
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
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .55),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ShamellSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الإصدار' : 'Version'),
                trailing: trailingVersion(),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الترخيص' : 'Licenses'),
                trailing: chevron(),
                onTap: openLicenses,
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
                    l.isArabic ? 'التحقق من التحديثات' : 'Check for updates'),
                trailing: chevron(),
                onTap: () => snack(
                  l.isArabic ? 'لا توجد تحديثات.' : 'No updates available.',
                ),
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.shamellSettingsTerms),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellTermsOfServicePage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.shamellSettingsPrivacyPolicy),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellPrivacyPolicyPage(),
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
