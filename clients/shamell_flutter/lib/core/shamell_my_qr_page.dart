import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'l10n.dart';
import 'shamell_ui.dart';

class ShamellMyQrCodePage extends StatelessWidget {
  final String payload;
  final String profileName;
  final String profilePhone;
  final String profileShamellId;

  const ShamellMyQrCodePage({
    super.key,
    required this.payload,
    required this.profileName,
    required this.profilePhone,
    required this.profileShamellId,
  });

  Future<void> _showActions(BuildContext context) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    Widget actionRow({
      required String label,
      required VoidCallback onTap,
      Color? color,
    }) {
      return ListTile(
        dense: true,
        title: Center(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
        onTap: onTap,
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: .98),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    actionRow(
                      label: l.isArabic ? 'مشاركة' : 'Share',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Share.share(payload);
                      },
                    ),
                    const Divider(height: 1),
                    actionRow(
                      label: l.isArabic ? 'نسخ الرابط' : 'Copy link',
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await Clipboard.setData(ClipboardData(text: payload));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l.isArabic ? 'تم النسخ.' : 'Copied.',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: .98),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: actionRow(
                  label: l.isArabic ? 'إلغاء' : 'Cancel',
                  onTap: () => Navigator.of(ctx).pop(),
                  color: theme.colorScheme.error.withValues(alpha: .90),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    // Best practice: never use/show phone numbers for contact discovery identity.
    final name = profileName.trim().isNotEmpty
        ? profileName.trim()
        : (profileShamellId.trim().isNotEmpty
            ? profileShamellId.trim()
            : (l.isArabic ? 'أنت' : 'You'));
    final initial = name.trim().isNotEmpty ? name.trim().characters.first : '?';

    final info = <String>[];
    if (profileShamellId.trim().isNotEmpty) {
      info.add(l.isArabic
          ? 'معرّف Shamell: ${profileShamellId.trim()}'
          : 'Shamell ID: ${profileShamellId.trim()}');
    }
    final infoLine = info.join(' · ');

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'رمز QR الخاص بي' : 'My QR code'),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'خيارات' : 'Options',
            icon: const Icon(Icons.more_horiz),
            onPressed: () => _showActions(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? .35 : .08,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 56,
                                height: 56,
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: isDark ? .35 : .90),
                                alignment: Alignment.center,
                                child: Text(
                                  initial.toUpperCase(),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (infoLine.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      infoLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .65),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: QrImageView(
                            data: payload,
                            version: QrVersions.auto,
                            size: 220,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l.isArabic
                              ? 'اطلب من صديقك مسح هذا الرمز لإضافتك.'
                              : 'Ask a friend to scan this code to add you.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.isArabic
                        ? 'يمكنك أيضاً مشاركة الرابط أو نسخه من قائمة الخيارات.'
                        : 'You can also share or copy the link from the options menu.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: .55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
