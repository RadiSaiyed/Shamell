import 'package:flutter/material.dart';

import 'l10n.dart';
import 'ui_kit.dart';
import 'app_shell_widgets.dart' show AppBG;

class IncomingCallPage extends StatelessWidget {
  final String baseUrl;
  final String callId;
  final String fromDeviceId;
  final String mode; // 'audio' | 'video'

  /// Mirrors the mobile widget's optional caller-name hint so callers
  /// (e.g. the FCM remote-tap path in `main_bootstrap.dart`) can pass
  /// `initialCallerName: …` on every platform without conditional code.
  /// The web stub has no live ring UI to upgrade, so the value is accepted
  /// for API parity and otherwise unused.
  final String? initialCallerName;

  const IncomingCallPage({
    super.key,
    required this.baseUrl,
    required this.callId,
    required this.fromDeviceId,
    this.mode = 'video',
    this.initialCallerName,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        CircleAvatar(
          radius: 40,
          child: Text(
            fromDeviceId.isNotEmpty
                ? fromDeviceId.characters.first.toUpperCase()
                : '?',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          fromDeviceId,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l.isArabic
                ? 'تلقي المكالمات عبر المتصفح غير مدعوم حالياً. يمكنك الرد من تطبيق SyrChat على الهاتف.'
                : 'Receiving calls in the browser is not supported yet. Please answer from the SyrChat mobile app.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .70),
                ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.isArabic ? 'حسناً' : 'OK'),
        ),
      ],
    );

    return DomainPageScaffold(
      background: const AppBG(),
      title: mode.toLowerCase() == 'video'
          ? (l.isArabic ? 'مكالمة فيديو واردة' : 'Incoming video call')
          : (l.isArabic ? 'مكالمة صوتية واردة' : 'Incoming voice call'),
      child: Center(child: body),
      scrollable: false,
    );
  }
}
