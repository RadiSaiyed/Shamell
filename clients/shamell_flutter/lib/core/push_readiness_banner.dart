import 'package:flutter/material.dart';

import 'notification_service.dart';

class PushReadinessBanner extends StatelessWidget {
  const PushReadinessBanner({
    super.key,
    required this.isArabic,
    this.availabilityProbe,
  });

  final bool isArabic;
  final Future<bool> Function()? availabilityProbe;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: (availabilityProbe ??
          NotificationService.isFirebaseRuntimeAvailable)(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.data == true) {
          return const SizedBox.shrink();
        }
        return Semantics(
          container: true,
          label: isArabic
              ? 'تنبيه: الإشعارات الخلفية غير مفعلة في هذا البناء'
              : 'Warning: background push notifications are unavailable in this build',
          child: Card(
            color: Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: .35),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isArabic
                        ? 'الإشعارات الخلفية غير مفعلة'
                        : 'Push unavailable in this build',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isArabic
                        ? 'هذا التطبيق لا يملك حالياً إعداد Firebase الصحيح لهذا الـ flavor. ثبّت ملف google-services.json المطابق أو مرّر SHAMELL_FIREBASE_* dart-defines قبل الاعتماد على إشعارات الرحلات عن بُعد.'
                        : 'This app currently has no usable Firebase config for this flavor. Install the matching google-services.json or pass SHAMELL_FIREBASE_* dart-defines before relying on remote ride alerts.',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
