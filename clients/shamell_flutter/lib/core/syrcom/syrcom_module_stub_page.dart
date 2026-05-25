import 'package:flutter/material.dart';

import '../l10n.dart';
import 'syrcom_theme.dart';

class SyrComModuleStubPage extends StatelessWidget {
  const SyrComModuleStubPage({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: kSyrComPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kSyrComPrimary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: kSyrComPrimary, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? 'هذه الوحدة قيد التحضير وستكون متاحة قريباً ضمن سركم.'
                    : 'This SyrCom module is being prepared and will be available soon.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .72),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
