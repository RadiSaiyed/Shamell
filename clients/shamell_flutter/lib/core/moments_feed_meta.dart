import 'package:flutter/material.dart';

class MomentAudienceMeta {
  final String key;
  final String label;
  final IconData icon;
  final String? audienceTag;
  final bool actionable;

  const MomentAudienceMeta({
    required this.key,
    required this.label,
    required this.icon,
    this.audienceTag,
    this.actionable = true,
  });
}

class MomentAudiencePillChromeMeta {
  final double topGap;
  final double maxWidth;
  final double horizontalPadding;
  final double verticalPadding;
  final double radius;
  final double borderWidth;
  final double publicTextAlpha;
  final double privateTextAlpha;
  final double publicDarkBackgroundAlpha;
  final double publicLightBackgroundAlpha;
  final double privateDarkBackgroundAlpha;
  final double privateLightBackgroundAlpha;
  final double publicDarkBorderAlpha;
  final double publicLightBorderAlpha;
  final double privateDarkBorderAlpha;
  final double privateLightBorderAlpha;
  final double iconSize;
  final double iconGap;
  final double fontSize;
  final double lineHeight;
  final FontWeight labelWeight;

  const MomentAudiencePillChromeMeta({
    required this.topGap,
    required this.maxWidth,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.radius,
    required this.borderWidth,
    required this.publicTextAlpha,
    required this.privateTextAlpha,
    required this.publicDarkBackgroundAlpha,
    required this.publicLightBackgroundAlpha,
    required this.privateDarkBackgroundAlpha,
    required this.privateLightBackgroundAlpha,
    required this.publicDarkBorderAlpha,
    required this.publicLightBorderAlpha,
    required this.privateDarkBorderAlpha,
    required this.privateLightBorderAlpha,
    required this.iconSize,
    required this.iconGap,
    required this.fontSize,
    required this.lineHeight,
    required this.labelWeight,
  });
}

class MomentAvatarMeta {
  final String imageUrl;
  final String fallbackText;
  final double size;
  final double radius;
  final double fallbackDarkAlpha;
  final double fallbackLightAlpha;
  final FontWeight fallbackFontWeight;
  final double fallbackFontSize;

  const MomentAvatarMeta({
    required this.imageUrl,
    required this.fallbackText,
    required this.size,
    required this.radius,
    required this.fallbackDarkAlpha,
    required this.fallbackLightAlpha,
    required this.fallbackFontWeight,
    required this.fallbackFontSize,
  });

  bool get hasImage => imageUrl.isNotEmpty;
}

class MomentContextLineChromeMeta {
  final double topGap;
  final double iconSize;
  final double iconGap;
  final double fontSize;
  final FontWeight accentFontWeight;
  final IconData officialReplyIcon;
  final IconData greenPaketIcon;
  final double officialAlpha;
  final double miniProgramAlpha;
  final double greenPaketIconDarkAlpha;
  final double greenPaketIconLightAlpha;
  final double greenPaketLabelAlpha;
  final double campaignAlpha;
  final double bodyBottomGap;

  const MomentContextLineChromeMeta({
    required this.topGap,
    required this.iconSize,
    required this.iconGap,
    required this.fontSize,
    required this.accentFontWeight,
    required this.officialReplyIcon,
    required this.greenPaketIcon,
    required this.officialAlpha,
    required this.miniProgramAlpha,
    required this.greenPaketIconDarkAlpha,
    required this.greenPaketIconLightAlpha,
    required this.greenPaketLabelAlpha,
    required this.campaignAlpha,
    required this.bodyBottomGap,
  });
}

class MomentLocationMeta {
  final String label;
  final IconData icon;
  final String perfKey;
  final double radius;
  final double verticalPadding;
  final double iconSize;
  final double iconGap;
  final double fontSize;
  final FontWeight fontWeight;
  final double bottomGap;

  const MomentLocationMeta({
    required this.label,
    required this.icon,
    required this.perfKey,
    required this.radius,
    required this.verticalPadding,
    required this.iconSize,
    required this.iconGap,
    required this.fontSize,
    required this.fontWeight,
    required this.bottomGap,
  });
}

class MomentFeedTextChromeMeta {
  final Color nameLinkLightColor;
  final FontWeight authorNameWeight;
  final double bodyFontSize;
  final FontWeight bodyWeight;
  final double bottomGap;
  final double topicTopGap;
  final double topicSpacing;
  final double topicRunSpacing;
  final double topicRadius;
  final double topicVerticalPadding;
  final double topicFontSize;
  final FontWeight topicWeight;

  const MomentFeedTextChromeMeta({
    required this.nameLinkLightColor,
    required this.authorNameWeight,
    required this.bodyFontSize,
    required this.bodyWeight,
    required this.bottomGap,
    required this.topicTopGap,
    required this.topicSpacing,
    required this.topicRunSpacing,
    required this.topicRadius,
    required this.topicVerticalPadding,
    required this.topicFontSize,
    required this.topicWeight,
  });
}

class MomentFeedContentChromeMeta {
  final double officialAttachmentBottomGap;
  final double miniProgramAttachmentBottomGap;
  final double mediaBottomGap;

  const MomentFeedContentChromeMeta({
    required this.officialAttachmentBottomGap,
    required this.miniProgramAttachmentBottomGap,
    required this.mediaBottomGap,
  });
}

class MomentFooterMeta {
  final String timestampLabel;
  final bool showOfficialReplyIndicator;
  final bool canOpenActions;
  final IconData actionIcon;
  final String actionTooltip;
  final String actionPerfKey;
  final double timestampFontSize;
  final double timestampAlpha;
  final double replyIndicatorLeftGap;
  final double replyIndicatorSize;
  final Color replyIndicatorColor;
  final double actionButtonWidth;
  final double actionButtonHeight;
  final double actionButtonRadius;
  final double actionButtonDarkFillAlpha;
  final double actionButtonBorderAlpha;
  final double actionButtonBorderWidth;
  final double actionIconSize;
  final double actionIconAlpha;

  const MomentFooterMeta({
    required this.timestampLabel,
    required this.showOfficialReplyIndicator,
    required this.canOpenActions,
    required this.actionIcon,
    required this.actionTooltip,
    required this.actionPerfKey,
    required this.timestampFontSize,
    required this.timestampAlpha,
    required this.replyIndicatorLeftGap,
    required this.replyIndicatorSize,
    required this.replyIndicatorColor,
    required this.actionButtonWidth,
    required this.actionButtonHeight,
    required this.actionButtonRadius,
    required this.actionButtonDarkFillAlpha,
    required this.actionButtonBorderAlpha,
    required this.actionButtonBorderWidth,
    required this.actionIconSize,
    required this.actionIconAlpha,
  });
}

class MomentFeedEmptyMeta {
  final String label;
  final bool isFriendTimeline;

  const MomentFeedEmptyMeta({
    required this.label,
    required this.isFriendTimeline,
  });
}

class MomentFeedListChromeMeta {
  final double emptyPadding;
  final double emptyTextAlpha;
  final double listTopPadding;
  final double postHorizontalPadding;
  final double postVerticalPadding;
  final double postAvatarGap;
  final Color lightSurfaceColor;
  final double separatorHeight;
  final double separatorThickness;
  final double separatorIndent;

  const MomentFeedListChromeMeta({
    required this.emptyPadding,
    required this.emptyTextAlpha,
    required this.listTopPadding,
    required this.postHorizontalPadding,
    required this.postVerticalPadding,
    required this.postAvatarGap,
    required this.lightSurfaceColor,
    required this.separatorHeight,
    required this.separatorThickness,
    required this.separatorIndent,
  });
}

class MomentComposerVisibilityMeta {
  final String key;
  final String label;
  final String prefix;
  final IconData icon;
  final String? audienceTag;
  final String tagMode;

  const MomentComposerVisibilityMeta({
    required this.key,
    required this.label,
    required this.prefix,
    required this.icon,
    this.audienceTag,
    this.tagMode = 'only',
  });

  String get summaryLabel => '$prefix$label';
}

class MomentComposerAudienceSummaryPillChromeMeta {
  final double horizontalPadding;
  final double verticalPadding;
  final double radius;
  final double darkBackgroundAlpha;
  final double lightBackgroundAlpha;
  final double borderAlpha;
  final double iconSize;
  final double iconAlpha;
  final double iconGap;
  final double fontSize;
  final double textAlpha;

  const MomentComposerAudienceSummaryPillChromeMeta({
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.radius,
    required this.darkBackgroundAlpha,
    required this.lightBackgroundAlpha,
    required this.borderAlpha,
    required this.iconSize,
    required this.iconAlpha,
    required this.iconGap,
    required this.fontSize,
    required this.textAlpha,
  });
}

String momentAuthorNameLabel({
  required String authorName,
  required bool isLocal,
  required bool isArabic,
}) {
  final clean = authorName.trim();
  if (clean.isNotEmpty) return clean;
  if (isLocal) return isArabic ? 'أنت' : 'You';
  return isArabic ? 'مستخدم' : 'User';
}

MomentAvatarMeta momentAvatarMetaFor({
  required String authorName,
  required String avatarUrl,
  required bool isLocal,
  required bool isArabic,
}) {
  final cleanName = authorName.trim();
  final cleanUrl = avatarUrl.trim();
  final fallback = cleanName.isNotEmpty
      ? _firstVisibleCharacter(cleanName).toUpperCase()
      : (isLocal ? (isArabic ? 'أ' : 'Y') : '?');
  return MomentAvatarMeta(
    imageUrl: cleanUrl,
    fallbackText: fallback,
    size: 40,
    radius: 4,
    fallbackDarkAlpha: .30,
    fallbackLightAlpha: .15,
    fallbackFontWeight: FontWeight.w700,
    fallbackFontSize: 14,
  );
}

String _firstVisibleCharacter(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return '?';
  return String.fromCharCode(clean.runes.first);
}

MomentAudiencePillChromeMeta momentAudiencePillChromeMeta() {
  return const MomentAudiencePillChromeMeta(
    topGap: 3,
    maxWidth: 260,
    horizontalPadding: 7,
    verticalPadding: 3,
    radius: 999,
    borderWidth: .5,
    publicTextAlpha: .58,
    privateTextAlpha: .90,
    publicDarkBackgroundAlpha: .24,
    publicLightBackgroundAlpha: .44,
    privateDarkBackgroundAlpha: .18,
    privateLightBackgroundAlpha: .09,
    publicDarkBorderAlpha: .34,
    publicLightBorderAlpha: .56,
    privateDarkBorderAlpha: .28,
    privateLightBorderAlpha: .18,
    iconSize: 12,
    iconGap: 4,
    fontSize: 10,
    lineHeight: 1.1,
    labelWeight: FontWeight.w600,
  );
}

MomentContextLineChromeMeta momentContextLineChromeMeta() {
  return const MomentContextLineChromeMeta(
    topGap: 2,
    iconSize: 14,
    iconGap: 4,
    fontSize: 11,
    accentFontWeight: FontWeight.w600,
    officialReplyIcon: Icons.verified_outlined,
    greenPaketIcon: Icons.card_giftcard,
    officialAlpha: .85,
    miniProgramAlpha: .70,
    greenPaketIconDarkAlpha: .90,
    greenPaketIconLightAlpha: .80,
    greenPaketLabelAlpha: .80,
    campaignAlpha: .70,
    bodyBottomGap: 6,
  );
}

String? momentOfficialReplyLabel({
  required bool hasOfficialReply,
  required String accountName,
  required bool isArabic,
}) {
  if (!hasOfficialReply) return null;
  final cleanAccountName = accountName.trim();
  final base =
      isArabic ? 'تم الرد من حساب رسمي' : 'Replied by an official account';
  if (cleanAccountName.isEmpty) return base;
  return '$base: $cleanAccountName';
}

String momentOfficialShareLabel({
  required String accountName,
  required bool featured,
  required bool isArabic,
}) {
  final cleanName = accountName.trim();
  final suffix =
      featured ? (isArabic ? ' · خدمة مميزة' : ' · Featured service') : '';
  return isArabic
      ? 'مُشارَكة من $cleanName$suffix'
      : 'Shared from $cleanName$suffix';
}

String momentMiniProgramShareLabel({
  required String title,
  required bool isArabic,
}) {
  final cleanTitle = title.trim();
  return isArabic
      ? 'من تطبيق مصغر: $cleanTitle'
      : 'Shared from mini-app: $cleanTitle';
}

String momentGreenPaketLabel({required bool isArabic}) {
  return isArabic ? 'حزمة خضراء' : 'Green Paket';
}

String? momentGreenPaketCampaignLabel({
  required String campaignId,
  required bool isArabic,
}) {
  final cleanId = campaignId.trim();
  if (cleanId.isEmpty) return null;
  return isArabic
      ? 'من حملة حزم خضراء: $cleanId'
      : 'From Green-Paket campaign: $cleanId';
}

MomentLocationMeta? momentLocationMetaFor(String rawLabel) {
  final clean = rawLabel.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.isEmpty) return null;
  return MomentLocationMeta(
    label: clean,
    icon: Icons.location_on_outlined,
    perfKey: 'moments_feed_location_tap',
    radius: 4,
    verticalPadding: 2,
    iconSize: 14,
    iconGap: 3,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    bottomGap: 6,
  );
}

MomentFeedTextChromeMeta momentFeedTextChromeMeta() {
  return const MomentFeedTextChromeMeta(
    nameLinkLightColor: Color(0xFF576B95),
    authorNameWeight: FontWeight.w600,
    bodyFontSize: 14,
    bodyWeight: FontWeight.w400,
    bottomGap: 6,
    topicTopGap: 4,
    topicSpacing: 10,
    topicRunSpacing: 4,
    topicRadius: 4,
    topicVerticalPadding: 2,
    topicFontSize: 12,
    topicWeight: FontWeight.w600,
  );
}

MomentFeedContentChromeMeta momentFeedContentChromeMeta() {
  return const MomentFeedContentChromeMeta(
    officialAttachmentBottomGap: 6,
    miniProgramAttachmentBottomGap: 6,
    mediaBottomGap: 8,
  );
}

MomentFooterMeta momentFooterMetaFor({
  required String rawTimestamp,
  required bool hasOfficialReply,
  required String postId,
  required bool isArabic,
  DateTime? now,
}) {
  return MomentFooterMeta(
    timestampLabel: momentTimestampLabel(
      rawTimestamp: rawTimestamp,
      isArabic: isArabic,
      now: now,
    ),
    showOfficialReplyIndicator: hasOfficialReply,
    canOpenActions: postId.trim().isNotEmpty,
    actionIcon: Icons.more_horiz,
    actionTooltip: isArabic ? 'خيارات المنشور' : 'Post actions',
    actionPerfKey: 'moments_feed_post_actions_open',
    timestampFontSize: 11,
    timestampAlpha: .55,
    replyIndicatorLeftGap: 8,
    replyIndicatorSize: 6,
    replyIndicatorColor: Colors.redAccent,
    actionButtonWidth: 30,
    actionButtonHeight: 22,
    actionButtonRadius: 2,
    actionButtonDarkFillAlpha: .55,
    actionButtonBorderAlpha: .42,
    actionButtonBorderWidth: .5,
    actionIconSize: 18,
    actionIconAlpha: .70,
  );
}

MomentFeedEmptyMeta momentFeedEmptyMetaFor({
  required bool isArabic,
  required bool isFriendTimeline,
}) {
  final label = isFriendTimeline
      ? (isArabic ? 'لا توجد لحظات بعد.' : 'No moments yet.')
      : (isArabic
          ? 'لا توجد لحظات بعد. شارك أول لحظة لك!'
          : 'No moments yet. Share your first moment!');
  return MomentFeedEmptyMeta(
    label: label,
    isFriendTimeline: isFriendTimeline,
  );
}

MomentFeedListChromeMeta momentFeedListChromeMeta() {
  return const MomentFeedListChromeMeta(
    emptyPadding: 12,
    emptyTextAlpha: .70,
    listTopPadding: 4,
    postHorizontalPadding: 12,
    postVerticalPadding: 12,
    postAvatarGap: 10,
    lightSurfaceColor: Colors.white,
    separatorHeight: 1,
    separatorThickness: .5,
    separatorIndent: 64,
  );
}

MomentComposerAudienceSummaryPillChromeMeta
    momentComposerAudienceSummaryPillChromeMeta() {
  return const MomentComposerAudienceSummaryPillChromeMeta(
    horizontalPadding: 10,
    verticalPadding: 6,
    radius: 999,
    darkBackgroundAlpha: .12,
    lightBackgroundAlpha: .06,
    borderAlpha: .35,
    iconSize: 16,
    iconAlpha: .95,
    iconGap: 6,
    fontSize: 11,
    textAlpha: .90,
  );
}

MomentComposerVisibilityMeta momentComposerVisibilityMetaFor({
  required String visibilityScope,
  required String visibilityTag,
  required String visibilityTagMode,
  required bool isArabic,
}) {
  final scope = visibilityScope.trim().toLowerCase();
  final tag = visibilityTag.trim();
  final tagMode =
      visibilityTagMode.trim().toLowerCase() == 'except' ? 'except' : 'only';
  final prefix = isArabic ? 'المشاركة مع: ' : 'Share to: ';

  switch (scope) {
    case 'public':
      return MomentComposerVisibilityMeta(
        key: 'public',
        label: isArabic ? 'عام (كل المستخدمين)' : 'Public (all users)',
        prefix: prefix,
        icon: Icons.public,
      );
    case 'only_me':
      return MomentComposerVisibilityMeta(
        key: 'only_me',
        label: isArabic ? 'أنا فقط' : 'Only me',
        prefix: prefix,
        icon: Icons.lock_outline,
      );
    case 'close_friends':
      return MomentComposerVisibilityMeta(
        key: 'close_friends',
        label: isArabic ? 'الأصدقاء المقرّبون' : 'Close friends',
        prefix: prefix,
        icon: Icons.group_outlined,
      );
    case 'friends':
    default:
      if (tag.isNotEmpty) {
        return MomentComposerVisibilityMeta(
          key: tagMode == 'except' ? 'friends_except_tag' : 'friends_tag',
          label: tagMode == 'except'
              ? (isArabic ? 'الأصدقاء باستثناء $tag' : 'Friends except $tag')
              : (isArabic ? 'فقط $tag' : 'Only $tag'),
          prefix: prefix,
          icon: Icons.group_outlined,
          audienceTag: tag,
          tagMode: tagMode,
        );
      }
      return MomentComposerVisibilityMeta(
        key: 'friends',
        label: isArabic ? 'الأصدقاء فقط' : 'Friends only',
        prefix: prefix,
        icon: Icons.group_outlined,
      );
  }
}

String momentTimestampLabel({
  required String rawTimestamp,
  required bool isArabic,
  DateTime? now,
}) {
  final raw = rawTimestamp.trim();
  if (raw.isEmpty) return '';

  DateTime createdAt;
  try {
    createdAt = DateTime.parse(raw).toLocal();
  } catch (_) {
    return '';
  }

  final localNow = (now ?? DateTime.now()).toLocal();
  final diff = localNow.difference(createdAt);
  if (diff.inSeconds < 60 && diff.inSeconds >= -60) {
    return isArabic ? 'الآن' : 'Just now';
  }
  if (!diff.isNegative && diff.inMinutes < 60) {
    final minutes = diff.inMinutes <= 0 ? 1 : diff.inMinutes;
    return isArabic ? 'قبل $minutes د' : '$minutes min ago';
  }
  if (!diff.isNegative &&
      _isSameDay(createdAt, localNow) &&
      diff.inHours < 24) {
    final hours = diff.inHours <= 0 ? 1 : diff.inHours;
    return isArabic ? 'قبل $hours س' : '$hours h ago';
  }
  if (_isYesterday(createdAt, localNow)) {
    return isArabic
        ? 'أمس ${_hhmm(createdAt)}'
        : 'Yesterday ${_hhmm(createdAt)}';
  }
  if (createdAt.year == localNow.year) {
    return '${_two(createdAt.month)}-${_two(createdAt.day)} ${_hhmm(createdAt)}';
  }
  return '${createdAt.year}-${_two(createdAt.month)}-${_two(createdAt.day)}';
}

bool _isSameDay(DateTime value, DateTime now) {
  return value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
}

bool _isYesterday(DateTime value, DateTime now) {
  final valueDay = DateTime(value.year, value.month, value.day);
  final today = DateTime(now.year, now.month, now.day);
  return today.difference(valueDay).inDays == 1;
}

String _hhmm(DateTime value) => '${_two(value.hour)}:${_two(value.minute)}';

String _two(int value) => value.toString().padLeft(2, '0');

MomentAudienceMeta? momentAudienceMetaFor({
  required String visibility,
  required String audienceTag,
  required bool isArabic,
  bool includePublic = true,
}) {
  final scope = visibility.trim().toLowerCase();
  final tag = audienceTag.trim();
  switch (scope) {
    case 'friends':
    case 'friends_only':
      return MomentAudienceMeta(
        key: 'friends',
        label: isArabic ? 'الأصدقاء فقط' : 'Friends only',
        icon: Icons.group_outlined,
      );
    case 'close_friends':
      return MomentAudienceMeta(
        key: 'close_friends',
        label: isArabic ? 'الأصدقاء المقرّبون' : 'Close friends',
        icon: Icons.star_outline,
      );
    case 'only_me':
    case 'private':
      return MomentAudienceMeta(
        key: 'private',
        label: isArabic ? 'أنا فقط' : 'Only me',
        icon: Icons.lock_outline,
        actionable: false,
      );
    case 'friends_tag':
      return MomentAudienceMeta(
        key: 'friends_tag',
        label: tag.isNotEmpty
            ? (isArabic ? 'الأصدقاء: $tag' : 'Friends: $tag')
            : (isArabic ? 'الأصدقاء الموسومون' : 'Tagged friends'),
        icon: Icons.label_outline,
        audienceTag: tag.isEmpty ? null : tag,
      );
    case 'friends_except_tag':
      return MomentAudienceMeta(
        key: 'friends_except_tag',
        label: tag.isNotEmpty
            ? (isArabic ? 'الأصدقاء باستثناء: $tag' : 'Friends except: $tag')
            : (isArabic ? 'الأصدقاء مع استثناء' : 'Friends with exclusion'),
        icon: Icons.group_remove_outlined,
        audienceTag: tag.isEmpty ? null : tag,
      );
    case 'public':
    default:
      if (!includePublic) return null;
      return MomentAudienceMeta(
        key: 'public',
        label: isArabic ? 'عام' : 'Public',
        icon: Icons.public,
      );
  }
}
