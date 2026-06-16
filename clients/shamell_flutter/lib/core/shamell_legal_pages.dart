import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'shamell_ui.dart';

class ShamellTermsOfServicePage extends StatelessWidget {
  const ShamellTermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    final title = l.isArabic ? 'شروط الاستخدام' : 'Terms of Service';

    TextStyle? bodyStyle() => theme.textTheme.bodyMedium?.copyWith(
          height: 1.45,
          color: theme.colorScheme.onSurface.withValues(alpha: .85),
        );

    Future<void> copyText(String text) async {
      try {
        await Clipboard.setData(ClipboardData(text: text));
      } catch (_) {}
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(l.isArabic ? 'تم النسخ.' : 'Copied.')),
        );
    }

    final content = l.isArabic
        ? '''
هذه صفحة \"شروط الاستخدام\" داخل Shamell.

• يستخدم Shamell تسجيل الدخول عبر القياسات الحيوية على الجهاز.
• أنت مسؤول عن الحفاظ على أمان جهازك وبيانات تسجيل الدخول.
• قد تتغير الميزات أو تتوقف مؤقتاً أثناء التطوير.

إذا كانت لديك أسئلة قانونية أو تريد نص الشروط الرسمي، تواصل مع الدعم.
'''
        : '''
This is the in‑app “Terms of Service” page for Shamell.

- Shamell uses biometric sign‑in.
- You’re responsible for keeping your device and credentials secure.
- Features may change or be temporarily unavailable during development.

For official legal text, please contact support.
''';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'نسخ' : 'Copy',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => copyText(content.trim()),
          ),
        ],
      ),
      body: ListView(
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SelectableText(
                  content.trim(),
                  style: bodyStyle(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellPrivacyPolicyPage extends StatelessWidget {
  const ShamellPrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    final title = l.isArabic ? 'سياسة الخصوصية' : 'Privacy Policy';

    TextStyle? bodyStyle() => theme.textTheme.bodyMedium?.copyWith(
          height: 1.45,
          color: theme.colorScheme.onSurface.withValues(alpha: .85),
        );

    Future<void> copyText(String text) async {
      try {
        await Clipboard.setData(ClipboardData(text: text));
      } catch (_) {}
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(l.isArabic ? 'تم النسخ.' : 'Copied.')),
        );
    }

    final content = l.isArabic
        ? '''
هذه صفحة \"سياسة الخصوصية\" داخل Shamell.

• قد يقوم التطبيق بتخزين بيانات محلية مثل إعدادات الإشعارات والتفضيلات.
• يمكنك التحكم في بعض إعدادات الخصوصية من داخل صفحة \"الخصوصية\" في الإعدادات.

للحصول على نص السياسة الرسمي أو طلب حذف البيانات، تواصل مع الدعم.
'''
        : '''
This is the in‑app “Privacy Policy” page for Shamell.

- The app may store local data such as notification settings and preferences.
- You can control some privacy options from Settings → Privacy.

For official policy text or data‑deletion requests, contact support.
''';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'نسخ' : 'Copy',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => copyText(content.trim()),
          ),
        ],
      ),
      body: ListView(
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SelectableText(
                  content.trim(),
                  style: bodyStyle(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
