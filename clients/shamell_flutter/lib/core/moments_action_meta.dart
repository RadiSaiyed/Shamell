import 'package:flutter/material.dart';

enum MomentPostQuickActionKind {
  like,
  comment,
  share,
  save,
}

enum MomentPostSheetActionKind {
  copy,
  share,
  save,
  toggleVisibility,
  delete,
  hide,
  report,
  muteAuthor,
  unmuteAuthor,
}

class MomentPostQuickActionMeta {
  final MomentPostQuickActionKind kind;
  final String label;
  final IconData icon;

  const MomentPostQuickActionMeta({
    required this.kind,
    required this.label,
    required this.icon,
  });
}

class MomentPostActionMenuChromeMeta {
  final Color backgroundColor;
  final double height;
  final double borderRadius;
  final double actionHorizontalPadding;
  final double actionVerticalPadding;
  final double iconSize;
  final double enabledAlpha;
  final double disabledAlpha;
  final double iconLabelGap;
  final double labelFontSize;
  final FontWeight labelFontWeight;
  final double dividerWidth;
  final double dividerHeight;
  final double dividerAlpha;

  const MomentPostActionMenuChromeMeta({
    required this.backgroundColor,
    required this.height,
    required this.borderRadius,
    required this.actionHorizontalPadding,
    required this.actionVerticalPadding,
    required this.iconSize,
    required this.enabledAlpha,
    required this.disabledAlpha,
    required this.iconLabelGap,
    required this.labelFontSize,
    required this.labelFontWeight,
    required this.dividerWidth,
    required this.dividerHeight,
    required this.dividerAlpha,
  });
}

class MomentPostActionPopoverChromeMeta {
  final double minMenuWidth;
  final double maxMenuWidth;
  final double margin;
  final double anchorGap;
  final double arrowWidth;
  final double arrowHeight;
  final double arrowAnchorCenterOffset;
  final double arrowTopInset;
  final double arrowBottomInset;
  final double arrowHorizontalOverlap;
  final Color arrowColor;
  final double slideDx;
  final Duration transitionDuration;

  const MomentPostActionPopoverChromeMeta({
    required this.minMenuWidth,
    required this.maxMenuWidth,
    required this.margin,
    required this.anchorGap,
    required this.arrowWidth,
    required this.arrowHeight,
    required this.arrowAnchorCenterOffset,
    required this.arrowTopInset,
    required this.arrowBottomInset,
    required this.arrowHorizontalOverlap,
    required this.arrowColor,
    required this.slideDx,
    required this.transitionDuration,
  });
}

class MomentPostActionSheetChromeMeta {
  final double darkRowAlpha;
  final double lightRowAlpha;
  final double darkDividerAlpha;
  final double lightDividerAlpha;
  final double dividerHeight;
  final double dividerThickness;
  final double innerDividerIndent;
  final double rowHeight;
  final double edgeGap;
  final double iconTextGap;
  final double iconSize;
  final double labelFontSize;
  final FontWeight actionFontWeight;
  final FontWeight cancelFontWeight;
  final Color destructiveColor;
  final double sectionGap;

  const MomentPostActionSheetChromeMeta({
    required this.darkRowAlpha,
    required this.lightRowAlpha,
    required this.darkDividerAlpha,
    required this.lightDividerAlpha,
    required this.dividerHeight,
    required this.dividerThickness,
    required this.innerDividerIndent,
    required this.rowHeight,
    required this.edgeGap,
    required this.iconTextGap,
    required this.iconSize,
    required this.labelFontSize,
    required this.actionFontWeight,
    required this.cancelFontWeight,
    required this.destructiveColor,
    required this.sectionGap,
  });
}

class MomentModerationOverviewSheetChromeMeta {
  final double sheetEdgePadding;
  final double viewInsetBottomGap;
  final double panelRadius;
  final double panelPadding;
  final FontWeight titleFontWeight;
  final double titleBottomGap;
  final double emptyBottomPadding;
  final double emptyTextAlpha;
  final FontWeight sectionTitleFontWeight;
  final double sectionTitleBottomGap;
  final double chipSpacing;
  final double chipRunSpacing;
  final double chipIconSize;
  final double mutedSectionBottomGap;
  final double hiddenListMaxHeight;
  final double hiddenRowGap;
  final bool hiddenTileDense;
  final EdgeInsets hiddenTileContentPadding;
  final int hiddenPreviewMaxChars;
  final double hiddenSubtitleAlpha;
  final double hiddenSubtitleFontSize;

  const MomentModerationOverviewSheetChromeMeta({
    required this.sheetEdgePadding,
    required this.viewInsetBottomGap,
    required this.panelRadius,
    required this.panelPadding,
    required this.titleFontWeight,
    required this.titleBottomGap,
    required this.emptyBottomPadding,
    required this.emptyTextAlpha,
    required this.sectionTitleFontWeight,
    required this.sectionTitleBottomGap,
    required this.chipSpacing,
    required this.chipRunSpacing,
    required this.chipIconSize,
    required this.mutedSectionBottomGap,
    required this.hiddenListMaxHeight,
    required this.hiddenRowGap,
    required this.hiddenTileDense,
    required this.hiddenTileContentPadding,
    required this.hiddenPreviewMaxChars,
    required this.hiddenSubtitleAlpha,
    required this.hiddenSubtitleFontSize,
  });
}

class MomentPostSheetActionMeta {
  final MomentPostSheetActionKind kind;
  final String label;
  final IconData icon;
  final bool destructive;

  const MomentPostSheetActionMeta({
    required this.kind,
    required this.label,
    required this.icon,
    this.destructive = false,
  });
}

MomentPostActionSheetChromeMeta momentPostActionSheetChromeMeta() {
  return const MomentPostActionSheetChromeMeta(
    darkRowAlpha: .96,
    lightRowAlpha: 1,
    darkDividerAlpha: .44,
    lightDividerAlpha: .72,
    dividerHeight: 1,
    dividerThickness: .5,
    innerDividerIndent: 52,
    rowHeight: 52,
    edgeGap: 16,
    iconTextGap: 16,
    iconSize: 21,
    labelFontSize: 15,
    actionFontWeight: FontWeight.w500,
    cancelFontWeight: FontWeight.w600,
    destructiveColor: Color(0xFFFA5151),
    sectionGap: 8,
  );
}

MomentModerationOverviewSheetChromeMeta
    momentModerationOverviewSheetChromeMeta() {
  return const MomentModerationOverviewSheetChromeMeta(
    sheetEdgePadding: 12,
    viewInsetBottomGap: 12,
    panelRadius: 16,
    panelPadding: 12,
    titleFontWeight: FontWeight.w700,
    titleBottomGap: 8,
    emptyBottomPadding: 4,
    emptyTextAlpha: .70,
    sectionTitleFontWeight: FontWeight.w700,
    sectionTitleBottomGap: 4,
    chipSpacing: 6,
    chipRunSpacing: 4,
    chipIconSize: 16,
    mutedSectionBottomGap: 12,
    hiddenListMaxHeight: 260,
    hiddenRowGap: 6,
    hiddenTileDense: true,
    hiddenTileContentPadding: EdgeInsets.zero,
    hiddenPreviewMaxChars: 80,
    hiddenSubtitleAlpha: .65,
    hiddenSubtitleFontSize: 11,
  );
}

MomentPostActionMenuChromeMeta momentPostActionMenuChromeMeta() {
  return const MomentPostActionMenuChromeMeta(
    backgroundColor: Color(0xFF2C2C2C),
    height: 40,
    borderRadius: 2,
    actionHorizontalPadding: 8,
    actionVerticalPadding: 10,
    iconSize: 18,
    enabledAlpha: .95,
    disabledAlpha: .45,
    iconLabelGap: 5,
    labelFontSize: 12,
    labelFontWeight: FontWeight.w600,
    dividerWidth: 1,
    dividerHeight: 22,
    dividerAlpha: .14,
  );
}

MomentPostActionPopoverChromeMeta momentPostActionPopoverChromeMeta() {
  return const MomentPostActionPopoverChromeMeta(
    minMenuWidth: 252,
    maxMenuWidth: 360,
    margin: 8,
    anchorGap: 10,
    arrowWidth: 10,
    arrowHeight: 12,
    arrowAnchorCenterOffset: 6,
    arrowTopInset: 8,
    arrowBottomInset: 14,
    arrowHorizontalOverlap: 1,
    arrowColor: Color(0xFF2C2C2C),
    slideDx: 18,
    transitionDuration: Duration(milliseconds: 160),
  );
}

List<MomentPostQuickActionMeta> momentPostQuickActionMetas({
  required bool isLiked,
  required bool isArabic,
}) {
  return <MomentPostQuickActionMeta>[
    MomentPostQuickActionMeta(
      kind: MomentPostQuickActionKind.like,
      label: isLiked
          ? (isArabic ? 'إلغاء الإعجاب' : 'Unlike')
          : (isArabic ? 'إعجاب' : 'Like'),
      icon: isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
    ),
    MomentPostQuickActionMeta(
      kind: MomentPostQuickActionKind.comment,
      label: isArabic ? 'تعليق' : 'Comment',
      icon: Icons.chat_bubble_outline,
    ),
    MomentPostQuickActionMeta(
      kind: MomentPostQuickActionKind.share,
      label: isArabic ? 'مشاركة' : 'Share',
      icon: Icons.share_outlined,
    ),
    MomentPostQuickActionMeta(
      kind: MomentPostQuickActionKind.save,
      label: isArabic ? 'حفظ' : 'Save',
      icon: Icons.bookmark_add_outlined,
    ),
  ];
}

List<MomentPostSheetActionMeta> momentPostSheetActionMetas({
  required bool hasShareText,
  required bool canToggleVisibility,
  required bool isPrivate,
  required bool isLocal,
  required bool canHideOrReport,
  required bool hasAuthor,
  required bool isMutedAuthor,
  required bool isArabic,
}) {
  final actions = <MomentPostSheetActionMeta>[];

  if (hasShareText) {
    actions.addAll(<MomentPostSheetActionMeta>[
      MomentPostSheetActionMeta(
        kind: MomentPostSheetActionKind.copy,
        label: isArabic ? 'نسخ' : 'Copy',
        icon: Icons.copy,
      ),
      MomentPostSheetActionMeta(
        kind: MomentPostSheetActionKind.share,
        label: isArabic ? 'مشاركة' : 'Share',
        icon: Icons.share_outlined,
      ),
      MomentPostSheetActionMeta(
        kind: MomentPostSheetActionKind.save,
        label: isArabic ? 'حفظ في المفضلة' : 'Save to Favorites',
        icon: Icons.bookmark_add_outlined,
      ),
    ]);
  }

  if (canToggleVisibility) {
    actions.add(
      MomentPostSheetActionMeta(
        kind: MomentPostSheetActionKind.toggleVisibility,
        label: isPrivate
            ? (isArabic ? 'جعلها عامة' : 'Make post public')
            : (isArabic ? 'جعلها مرئية لي فقط' : 'Make visible to me only'),
        icon: isPrivate ? Icons.public_outlined : Icons.lock_outline,
      ),
    );
  }

  if (isLocal) {
    actions.add(
      MomentPostSheetActionMeta(
        kind: MomentPostSheetActionKind.delete,
        label: isArabic ? 'حذف المنشور' : 'Delete this post',
        icon: Icons.delete_outline,
        destructive: true,
      ),
    );
  }

  if (canHideOrReport) {
    actions.addAll(<MomentPostSheetActionMeta>[
      MomentPostSheetActionMeta(
        kind: MomentPostSheetActionKind.hide,
        label: isArabic ? 'إخفاء هذا المنشور' : 'Hide this post',
        icon: Icons.visibility_off_outlined,
      ),
      MomentPostSheetActionMeta(
        kind: MomentPostSheetActionKind.report,
        label: isArabic ? 'الإبلاغ عن هذا المنشور' : 'Report this post',
        icon: Icons.flag_outlined,
      ),
    ]);
  }

  if (!isLocal && hasAuthor) {
    actions.add(
      MomentPostSheetActionMeta(
        kind: isMutedAuthor
            ? MomentPostSheetActionKind.unmuteAuthor
            : MomentPostSheetActionKind.muteAuthor,
        label: isMutedAuthor
            ? (isArabic
                ? 'إلغاء كتم هذا المستخدم في اللحظات'
                : 'Unmute this user in Moments')
            : (isArabic
                ? 'كتم هذا المستخدم في اللحظات'
                : 'Mute this user in Moments'),
        icon: isMutedAuthor
            ? Icons.volume_up_outlined
            : Icons.volume_off_outlined,
      ),
    );
  }

  return actions;
}
