import 'package:flutter/material.dart';

import 'l10n.dart';
import 'ui_kit.dart';
import 'app_shell_widgets.dart' show AppBG;

class VoipCallPage extends StatelessWidget {
  final String baseUrl;
  final String peerId;
  final String? displayName;
  final String mode; // 'audio' | 'video'

  const VoipCallPage({
    super.key,
    required this.baseUrl,
    required this.peerId,
    this.displayName,
    this.mode = 'video',
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final name = (displayName != null && displayName!.isNotEmpty)
        ? displayName!
        : peerId;
    final body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        CircleAvatar(
          radius: 40,
          child: Text(
            name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l.isArabic
                ? 'المكالمات الصوتية عبر المتصفح غير مدعومة حالياً. استخدم تطبيق Shamell على الهاتف للمكالمات.'
                : 'Browser voice calls are not supported yet. Please use the Shamell mobile app for calls.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .70),
                ),
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.isArabic ? 'رجوع' : 'Back'),
        ),
      ],
    );

    return DomainPageScaffold(
      background: const AppBG(),
      title: mode.toLowerCase() == 'video'
          ? (l.isArabic ? 'مكالمة فيديو' : 'Video call')
          : (l.isArabic ? 'مكالمة صوتية' : 'Voice call'),
      child: Center(child: body),
      scrollable: false,
    );
  }
}
