import 'package:flutter/material.dart';

class MomentOfficialAttachmentMeta {
  final String title;
  final String subtitle;
  final String serviceActionLabel;
  final String channelsActionLabel;
  final String followActionLabel;
  final String chatActionLabel;
  final bool isServiceAccount;
  final IconData serviceActionIcon;
  final IconData channelsActionIcon;
  final IconData followActionIcon;
  final IconData chatActionIcon;
  final IconData fallbackIcon;
  final IconData chevronIcon;
  final double avatarRadius;
  final double fallbackIconBoxSize;
  final double fallbackIconSize;
  final double fallbackIconRadius;
  final double titleFontSize;
  final double subtitleFontSize;
  final double actionsMaxWidth;
  final double actionButtonSize;
  final double actionIconSize;
  final double chevronSize;

  const MomentOfficialAttachmentMeta({
    required this.title,
    required this.subtitle,
    required this.serviceActionLabel,
    required this.channelsActionLabel,
    required this.followActionLabel,
    required this.chatActionLabel,
    required this.isServiceAccount,
    required this.serviceActionIcon,
    required this.channelsActionIcon,
    required this.followActionIcon,
    required this.chatActionIcon,
    required this.fallbackIcon,
    required this.chevronIcon,
    required this.avatarRadius,
    required this.fallbackIconBoxSize,
    required this.fallbackIconSize,
    required this.fallbackIconRadius,
    required this.titleFontSize,
    required this.subtitleFontSize,
    required this.actionsMaxWidth,
    required this.actionButtonSize,
    required this.actionIconSize,
    required this.chevronSize,
  });
}

class MomentOfficialAttachmentChromeMeta {
  final double darkSurfaceAlpha;
  final double darkBorderAlpha;
  final double lightBorderAlpha;
  final double borderWidth;
  final double splashAlpha;
  final double highlightAlpha;
  final double horizontalPadding;
  final double verticalPadding;
  final double fallbackIconFillDarkAlpha;
  final double fallbackIconFillLightAlpha;
  final double iconTextGap;
  final FontWeight titleFontWeight;
  final double subtitleTopGap;
  final double mutedTextAlpha;
  final double actionGap;
  final double actionWrapSpacing;
  final double actionWrapRunSpacing;

  const MomentOfficialAttachmentChromeMeta({
    required this.darkSurfaceAlpha,
    required this.darkBorderAlpha,
    required this.lightBorderAlpha,
    required this.borderWidth,
    required this.splashAlpha,
    required this.highlightAlpha,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.fallbackIconFillDarkAlpha,
    required this.fallbackIconFillLightAlpha,
    required this.iconTextGap,
    required this.titleFontWeight,
    required this.subtitleTopGap,
    required this.mutedTextAlpha,
    required this.actionGap,
    required this.actionWrapSpacing,
    required this.actionWrapRunSpacing,
  });
}

class MomentAttachmentIconActionChromeMeta {
  final double defaultIconAlpha;
  final VisualDensity visualDensity;
  final EdgeInsets padding;
  final MaterialTapTargetSize tapTargetSize;

  const MomentAttachmentIconActionChromeMeta({
    required this.defaultIconAlpha,
    required this.visualDensity,
    required this.padding,
    required this.tapTargetSize,
  });
}

MomentOfficialAttachmentChromeMeta momentOfficialAttachmentChromeMeta() {
  return const MomentOfficialAttachmentChromeMeta(
    darkSurfaceAlpha: .42,
    darkBorderAlpha: .50,
    lightBorderAlpha: .86,
    borderWidth: .5,
    splashAlpha: .08,
    highlightAlpha: .04,
    horizontalPadding: 8,
    verticalPadding: 8,
    fallbackIconFillDarkAlpha: .30,
    fallbackIconFillLightAlpha: .12,
    iconTextGap: 10,
    titleFontWeight: FontWeight.w600,
    subtitleTopGap: 2,
    mutedTextAlpha: .58,
    actionGap: 8,
    actionWrapSpacing: 2,
    actionWrapRunSpacing: 2,
  );
}

MomentAttachmentIconActionChromeMeta momentAttachmentIconActionChromeMeta() {
  return const MomentAttachmentIconActionChromeMeta(
    defaultIconAlpha: .64,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

MomentOfficialAttachmentMeta momentOfficialAttachmentMeta({
  required String accountName,
  required String accountKind,
  required String? itemId,
  required String? itemTitle,
  required String? linkedMiniProgramId,
  required bool isArabic,
}) {
  final cleanAccountName = accountName.trim().isEmpty
      ? (isArabic ? 'حساب رسمي' : 'Official account')
      : accountName.trim();
  final kind = accountKind.trim().toLowerCase();
  final isService = kind.isEmpty || kind == 'service';
  final kindLabel = isService
      ? (isArabic ? 'حساب خدمة' : 'Service account')
      : (isArabic ? 'حساب اشتراك' : 'Subscription account');
  final hasItem = (itemId ?? '').trim().isNotEmpty;
  final cleanItemTitle = (itemTitle ?? '').trim();

  final title = cleanItemTitle.isNotEmpty
      ? cleanItemTitle
      : hasItem
          ? (isArabic ? 'منشور رسمي' : 'Official update')
          : (isArabic ? 'حساب رسمي' : 'Official account');

  return MomentOfficialAttachmentMeta(
    title: title,
    subtitle: '$cleanAccountName · $kindLabel',
    serviceActionLabel: officialAttachmentServiceActionLabel(
      linkedMiniProgramId: linkedMiniProgramId,
      isArabic: isArabic,
    ),
    channelsActionLabel: isArabic ? 'القناة' : 'Channels',
    followActionLabel: isArabic ? 'متابعة' : 'Follow',
    chatActionLabel: isArabic ? 'دردشة' : 'Chat',
    isServiceAccount: isService,
    serviceActionIcon: officialAttachmentServiceActionIcon(
      linkedMiniProgramId: linkedMiniProgramId,
    ),
    channelsActionIcon: Icons.article_outlined,
    followActionIcon: Icons.person_add_alt_1_outlined,
    chatActionIcon: Icons.chat_bubble_outline,
    fallbackIcon: Icons.verified_outlined,
    chevronIcon: Icons.chevron_right,
    avatarRadius: 17,
    fallbackIconBoxSize: 34,
    fallbackIconSize: 18,
    fallbackIconRadius: 7,
    titleFontSize: 13,
    subtitleFontSize: 11,
    actionsMaxWidth: 112,
    actionButtonSize: 30,
    actionIconSize: 17,
    chevronSize: 18,
  );
}

String officialAttachmentServiceActionLabel({
  required String? linkedMiniProgramId,
  required bool isArabic,
}) {
  final id = (linkedMiniProgramId ?? '').trim().toLowerCase();
  if (id == 'bus' || id == 'coach') {
    return isArabic ? 'فتح الباص' : 'Open bus';
  }
  if (id == 'payments' || id == 'wallet' || id == 'pay') {
    return isArabic ? 'فتح المحفظة' : 'Open wallet';
  }
  return isArabic ? 'فتح الخدمة' : 'Open service';
}

IconData officialAttachmentServiceActionIcon({
  required String? linkedMiniProgramId,
}) {
  final id = (linkedMiniProgramId ?? '').trim().toLowerCase();
  if (id == 'bus' || id == 'coach') return Icons.directions_bus_outlined;
  if (id == 'payments' || id == 'wallet' || id == 'pay') {
    return Icons.account_balance_wallet_outlined;
  }
  return Icons.apps_outlined;
}

String? officialAttachmentItemTitleFromMomentText(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return null;
  final first = lines.first;
  final lower = first.toLowerCase();
  if (lower.startsWith('from ') || lower.startsWith('من ')) return null;
  if (lower.startsWith('shamell://official/')) return null;
  return first;
}
