import 'package:flutter/material.dart';

class MomentPageAppBarActionMeta {
  final bool showComposerAction;
  final IconData icon;
  final String tooltip;
  final String openSheetPerfKey;
  final String quickOpenPerfKey;

  const MomentPageAppBarActionMeta({
    required this.showComposerAction,
    required this.icon,
    required this.tooltip,
    required this.openSheetPerfKey,
    required this.quickOpenPerfKey,
  });
}

class MomentPageChromeMeta {
  final double inlineComposerBottomGap;
  final double miniProgramContextBottomGap;

  const MomentPageChromeMeta({
    required this.inlineComposerBottomGap,
    required this.miniProgramContextBottomGap,
  });
}

class MomentCoverHeaderMeta {
  final double height;
  final List<Color> gradientColors;
  final String assetPath;
  final double assetOpacity;
  final double horizontalInset;
  final double bottomInset;
  final double tapRadius;
  final Color nameColor;
  final double nameFontSize;
  final FontWeight nameFontWeight;
  final double nameShadowBlurRadius;
  final Color nameShadowColor;
  final double nameAvatarGap;
  final double avatarSize;
  final double avatarRadius;
  final Color avatarFillColor;
  final double avatarFillAlpha;
  final Color avatarBorderColor;
  final double avatarBorderAlpha;
  final double avatarBorderWidth;
  final Color avatarShadowColor;
  final double avatarShadowBlurRadius;
  final Offset avatarShadowOffset;
  final double initialFontSize;
  final FontWeight initialFontWeight;

  const MomentCoverHeaderMeta({
    required this.height,
    required this.gradientColors,
    required this.assetPath,
    required this.assetOpacity,
    required this.horizontalInset,
    required this.bottomInset,
    required this.tapRadius,
    required this.nameColor,
    required this.nameFontSize,
    required this.nameFontWeight,
    required this.nameShadowBlurRadius,
    required this.nameShadowColor,
    required this.nameAvatarGap,
    required this.avatarSize,
    required this.avatarRadius,
    required this.avatarFillColor,
    required this.avatarFillAlpha,
    required this.avatarBorderColor,
    required this.avatarBorderAlpha,
    required this.avatarBorderWidth,
    required this.avatarShadowColor,
    required this.avatarShadowBlurRadius,
    required this.avatarShadowOffset,
    required this.initialFontSize,
    required this.initialFontWeight,
  });
}

MomentPageChromeMeta momentPageChromeMeta() {
  return const MomentPageChromeMeta(
    inlineComposerBottomGap: 12,
    miniProgramContextBottomGap: 8,
  );
}

String momentPageTitleLabel({
  required bool isArabic,
  required bool isFriendTimeline,
  required String miniProgramMomentsTitle,
  required String timelineAuthorName,
  required String timelineAuthorId,
}) {
  final defaultTitle = isArabic ? 'اللحظات' : 'Moments';
  if (!isFriendTimeline) {
    final miniTitle = miniProgramMomentsTitle.trim();
    return miniTitle.isEmpty ? defaultTitle : miniTitle;
  }
  final explicitName = timelineAuthorName.trim();
  if (explicitName.isNotEmpty) return explicitName;
  final id = timelineAuthorId.trim();
  return id.isEmpty ? defaultTitle : id;
}

MomentPageAppBarActionMeta momentPageAppBarActionMeta({
  required bool showComposer,
  required bool isFriendTimeline,
  required bool isArabic,
}) {
  return MomentPageAppBarActionMeta(
    showComposerAction: showComposer && !isFriendTimeline,
    icon: Icons.photo_camera_outlined,
    tooltip: isArabic ? 'إضافة لحظة' : 'New moment',
    openSheetPerfKey: 'moments_appbar_new_sheet_open',
    quickOpenPerfKey: 'moments_appbar_quick_composer_open',
  );
}

MomentCoverHeaderMeta momentCoverHeaderMeta({required bool isDark}) {
  return MomentCoverHeaderMeta(
    height: 280,
    gradientColors: isDark
        ? const <Color>[
            Color(0xFF0B1220),
            Color(0xFF111827),
          ]
        : const <Color>[
            Color(0xFF64748B),
            Color(0xFF334155),
          ],
    assetPath: 'assets/shamell_steering.png',
    assetOpacity: isDark ? .12 : .16,
    horizontalInset: 16,
    bottomInset: 16,
    tapRadius: 10,
    nameColor: Colors.white,
    nameFontSize: 16,
    nameFontWeight: FontWeight.w600,
    nameShadowBlurRadius: 10,
    nameShadowColor: Colors.black45,
    nameAvatarGap: 10,
    avatarSize: 64,
    avatarRadius: 8,
    avatarFillColor: Colors.white,
    avatarFillAlpha: .92,
    avatarBorderColor: Colors.white,
    avatarBorderAlpha: .95,
    avatarBorderWidth: 1,
    avatarShadowColor: Colors.black26,
    avatarShadowBlurRadius: 8,
    avatarShadowOffset: const Offset(0, 4),
    initialFontSize: 28,
    initialFontWeight: FontWeight.w800,
  );
}
