import 'package:flutter/material.dart';

import '../l10n.dart';
import 'syrcom_theme.dart';
import 'workforce_dev_auth_api.dart';

/// Show the dev workforce sign-in chooser as a modal bottom sheet.
///
/// Returns `true` if the user successfully signed in (the caller should
/// then reload its data). Returns `false` if the user dismissed the sheet
/// without signing in. Never throws — error states are rendered inline.
Future<bool> showSyrComDevLoginSheet(
  BuildContext context, {
  required String baseUrl,
  WorkforceDevAuthApi? api,
}) async {
  if (!workforceDevAuthAvailable()) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SyrComDevLoginSheet(
      baseUrl: baseUrl,
      api: api ?? WorkforceDevAuthApi(baseUrl: baseUrl),
    ),
  );
  return result ?? false;
}

class _SyrComDevLoginSheet extends StatefulWidget {
  const _SyrComDevLoginSheet({
    required this.baseUrl,
    required this.api,
  });

  final String baseUrl;
  final WorkforceDevAuthApi api;

  @override
  State<_SyrComDevLoginSheet> createState() => _SyrComDevLoginSheetState();
}

class _SyrComDevLoginSheetState extends State<_SyrComDevLoginSheet> {
  String? _signingInEmail;
  String? _errorDetail;

  Future<void> _signInAs(String email) async {
    setState(() {
      _signingInEmail = email;
      _errorDetail = null;
    });
    final result = await widget.api.signIn(email: email);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _signingInEmail = null;
        _errorDetail = result.error ?? 'unknown error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    final emails = workforceDevAuthAllowedEmails();
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F27) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 0,
        right: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: kSyrComPrimary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.developer_mode_outlined,
                      color: kSyrComPrimary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isArabic
                              ? 'تسجيل دخول مطوّر — سركم'
                              : 'SyrCom dev sign-in',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isArabic
                              ? 'متاح فقط في إصدارات التطوير.'
                              : 'Available in dev builds only.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (emails.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  isArabic
                      ? 'لم يتم إعداد أي بريد إلكتروني مسموح به في الإصدار.'
                      : 'No allowed dev emails are compiled into this build.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ...emails.map(
                (email) => _SyrComDevEmailRow(
                  email: email,
                  isBusy: _signingInEmail == email,
                  isAnyBusy: _signingInEmail != null,
                  onTap: () => _signInAs(email),
                ),
              ),
            if (_errorDetail != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: .35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorDetail!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _SyrComDevEmailRow extends StatelessWidget {
  const _SyrComDevEmailRow({
    required this.email,
    required this.isBusy,
    required this.isAnyBusy,
    required this.onTap,
  });

  final String email;
  final bool isBusy;
  final bool isAnyBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: !isAnyBusy,
      onTap: isAnyBusy ? null : onTap,
      leading: CircleAvatar(
        backgroundColor: kSyrComPrimary.withValues(alpha: .14),
        child: Text(
          email.characters.first.toUpperCase(),
          style: const TextStyle(
            color: kSyrComPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        email,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(kSyrComPrimary),
              ),
            )
          : const Icon(Icons.chevron_right, color: kSyrComPrimary),
    );
  }
}
