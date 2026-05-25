import 'package:flutter/material.dart';

import 'mini_app_descriptor.dart';

class MomentMiniProgramContextMeta {
  final String id;
  final String title;
  final String category;
  final String momentsTitle;
  final String allLabel;
  final IconData icon;
  final IconData allIcon;
  final String allPerfKey;
  final double iconBoxSize;
  final double iconSize;
  final double iconRadius;
  final double titleFontSize;
  final double categoryFontSize;

  const MomentMiniProgramContextMeta({
    required this.id,
    required this.title,
    required this.category,
    required this.momentsTitle,
    required this.allLabel,
    required this.icon,
    required this.allIcon,
    required this.allPerfKey,
    required this.iconBoxSize,
    required this.iconSize,
    required this.iconRadius,
    required this.titleFontSize,
    required this.categoryFontSize,
  });
}

class MomentMiniProgramContextChromeMeta {
  final double darkBorderAlpha;
  final double lightBorderAlpha;
  final double borderWidth;
  final double horizontalPadding;
  final double verticalPadding;
  final double iconFillDarkAlpha;
  final double iconFillLightAlpha;
  final double iconTitleGap;
  final FontWeight titleFontWeight;
  final double categoryTopGap;
  final double categoryAlpha;
  final double actionGap;
  final double actionMinWidth;
  final double actionHeight;
  final double actionHorizontalPadding;
  final VisualDensity actionVisualDensity;
  final double actionIconGap;
  final double actionIconSize;

  const MomentMiniProgramContextChromeMeta({
    required this.darkBorderAlpha,
    required this.lightBorderAlpha,
    required this.borderWidth,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.iconFillDarkAlpha,
    required this.iconFillLightAlpha,
    required this.iconTitleGap,
    required this.titleFontWeight,
    required this.categoryTopGap,
    required this.categoryAlpha,
    required this.actionGap,
    required this.actionMinWidth,
    required this.actionHeight,
    required this.actionHorizontalPadding,
    required this.actionVisualDensity,
    required this.actionIconGap,
    required this.actionIconSize,
  });
}

class MomentMiniProgramAttachmentMeta {
  final String title;
  final String category;
  final String subtitle;
  final String footer;
  final IconData icon;
  final IconData openIcon;
  final String openTooltip;
  final IconData chevronIcon;
  final double iconBoxSize;
  final double iconSize;
  final double iconRadius;
  final double titleFontSize;
  final double subtitleFontSize;
  final double footerFontSize;

  const MomentMiniProgramAttachmentMeta({
    required this.title,
    required this.category,
    required this.subtitle,
    required this.footer,
    required this.icon,
    required this.openIcon,
    required this.openTooltip,
    required this.chevronIcon,
    required this.iconBoxSize,
    required this.iconSize,
    required this.iconRadius,
    required this.titleFontSize,
    required this.subtitleFontSize,
    required this.footerFontSize,
  });
}

class MomentMiniProgramAttachmentChromeMeta {
  final double darkSurfaceAlpha;
  final double darkBorderAlpha;
  final double lightBorderAlpha;
  final double borderWidth;
  final double splashAlpha;
  final double highlightAlpha;
  final double horizontalPadding;
  final double verticalPadding;
  final double iconFillDarkAlpha;
  final double iconFillLightAlpha;
  final double iconTextGap;
  final FontWeight titleFontWeight;
  final double subtitleTopGap;
  final double footerTopGap;
  final double mutedTextAlpha;
  final double actionGap;
  final double chevronSize;

  const MomentMiniProgramAttachmentChromeMeta({
    required this.darkSurfaceAlpha,
    required this.darkBorderAlpha,
    required this.lightBorderAlpha,
    required this.borderWidth,
    required this.splashAlpha,
    required this.highlightAlpha,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.iconFillDarkAlpha,
    required this.iconFillLightAlpha,
    required this.iconTextGap,
    required this.titleFontWeight,
    required this.subtitleTopGap,
    required this.footerTopGap,
    required this.mutedTextAlpha,
    required this.actionGap,
    required this.chevronSize,
  });
}

MomentMiniProgramContextChromeMeta momentMiniProgramContextChromeMeta() {
  return const MomentMiniProgramContextChromeMeta(
    darkBorderAlpha: .46,
    lightBorderAlpha: .70,
    borderWidth: .6,
    horizontalPadding: 12,
    verticalPadding: 9,
    iconFillDarkAlpha: .22,
    iconFillLightAlpha: .12,
    iconTitleGap: 10,
    titleFontWeight: FontWeight.w700,
    categoryTopGap: 2,
    categoryAlpha: .58,
    actionGap: 8,
    actionMinWidth: 0,
    actionHeight: 32,
    actionHorizontalPadding: 8,
    actionVisualDensity: VisualDensity.compact,
    actionIconGap: 2,
    actionIconSize: 15,
  );
}

MomentMiniProgramAttachmentChromeMeta momentMiniProgramAttachmentChromeMeta() {
  return const MomentMiniProgramAttachmentChromeMeta(
    darkSurfaceAlpha: .42,
    darkBorderAlpha: .50,
    lightBorderAlpha: .86,
    borderWidth: .5,
    splashAlpha: .08,
    highlightAlpha: .04,
    horizontalPadding: 8,
    verticalPadding: 8,
    iconFillDarkAlpha: .22,
    iconFillLightAlpha: .12,
    iconTextGap: 10,
    titleFontWeight: FontWeight.w700,
    subtitleTopGap: 2,
    footerTopGap: 3,
    mutedTextAlpha: .58,
    actionGap: 8,
    chevronSize: 18,
  );
}

Color momentMiniProgramAccentColor(String id) {
  switch (id.trim().toLowerCase()) {
    case 'payments':
    case 'alias':
    case 'merchant':
      return const Color(0xFF07C160);
    case 'green_paket':
      return const Color(0xFF16A34A);
    case 'cards':
      return const Color(0xFFB7791F);
    case 'moments':
      return const Color(0xFF2563EB);
    case 'favorites':
      return const Color(0xFFF59E0B);
    case 'official_accounts':
      return const Color(0xFF0EA5E9);
    case 'channels':
      return const Color(0xFFEF4444);
    case 'people_nearby':
      return const Color(0xFF14B8A6);
    case 'stickers':
      return const Color(0xFFF97316);
    case 'bus':
    case 'coach':
    case 'taxi':
      return const Color(0xFF0EA5E9);
    default:
      return const Color(0xFF64748B);
  }
}

MomentMiniProgramContextMeta? momentMiniProgramContextMeta({
  required String id,
  required MiniAppDescriptor? descriptor,
  required bool isArabic,
}) {
  final normalizedId = id.trim().toLowerCase();
  if (normalizedId.isEmpty) return null;
  final categoryFallback = isArabic ? 'برنامج مصغّر' : 'Mini Program';
  final title = (descriptor?.title(isArabic: isArabic) ?? '').trim().isNotEmpty
      ? descriptor!.title(isArabic: isArabic).trim()
      : _fallbackMiniProgramTitle(normalizedId);
  final category =
      (descriptor?.category(isArabic: isArabic) ?? '').trim().isNotEmpty
          ? descriptor!.category(isArabic: isArabic).trim()
          : categoryFallback;

  return MomentMiniProgramContextMeta(
    id: normalizedId,
    title: title,
    category: category,
    momentsTitle: isArabic ? 'لحظات $title' : '$title Moments',
    allLabel: isArabic ? 'الكل' : 'All',
    icon: descriptor?.icon ?? Icons.widgets_outlined,
    allIcon: Icons.chevron_right,
    allPerfKey: 'moments_mini_program_context_all',
    iconBoxSize: 34,
    iconSize: 20,
    iconRadius: 7,
    titleFontSize: 13,
    categoryFontSize: 11,
  );
}

MomentMiniProgramAttachmentMeta momentMiniProgramAttachmentMeta({
  required String id,
  required String resourceId,
  required MiniAppDescriptor? descriptor,
  required bool isArabic,
}) {
  final normalizedId = id.trim().toLowerCase();
  final categoryFallback = isArabic ? 'برنامج مصغّر' : 'Mini Program';
  final title = (descriptor?.title(isArabic: isArabic) ?? '').trim().isNotEmpty
      ? descriptor!.title(isArabic: isArabic).trim()
      : _fallbackMiniProgramTitle(normalizedId);
  final category =
      (descriptor?.category(isArabic: isArabic) ?? '').trim().isNotEmpty
          ? descriptor!.category(isArabic: isArabic).trim()
          : categoryFallback;
  final cleanResourceId = resourceId.trim();
  final subtitle = cleanResourceId.isNotEmpty
      ? _resourceSubtitle(
          normalizedId,
          isArabic: isArabic,
        )
      : category;

  return MomentMiniProgramAttachmentMeta(
    title: title,
    category: category,
    subtitle: subtitle,
    footer: isArabic ? 'برنامج SyrChat مصغّر' : 'SyrChat Mini Program',
    icon: descriptor?.icon ?? Icons.widgets_outlined,
    openIcon: Icons.open_in_new,
    openTooltip: isArabic ? 'فتح' : 'Open',
    chevronIcon: Icons.chevron_right,
    iconBoxSize: 36,
    iconSize: 21,
    iconRadius: 7,
    titleFontSize: 13,
    subtitleFontSize: 11,
    footerFontSize: 10,
  );
}

String _resourceSubtitle(
  String id, {
  required bool isArabic,
}) {
  switch (id) {
    case 'green_paket':
      return isArabic
          ? 'افتح أو طالب بالحزمة داخل سرتشات'
          : 'Open or claim inside SyrChat';
    case 'payments':
      return isArabic
          ? 'افتح عملية الدفع المرتبطة داخل سرتشات'
          : 'Open linked payment inside SyrChat';
    case 'bus':
    case 'coach':
      return isArabic
          ? 'افتح الرحلة المرتبطة داخل سرتشات'
          : 'Open linked trip inside SyrChat';
    default:
      return isArabic
          ? 'افتح العنصر المرتبط داخل سرتشات'
          : 'Open linked item inside SyrChat';
  }
}

String _fallbackMiniProgramTitle(String id) {
  if (id == 'green_paket') return 'Green Paket';
  final clean = id.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (clean.isEmpty) return 'Mini Program';
  return clean
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
