import 'package:flutter/material.dart';

enum MomentQuickComposerActionKind {
  camera,
  album,
  friends,
  closeFriends,
  onlyMe,
  filters,
}

enum MomentComposerSheetActionKind {
  text,
  camera,
  album,
}

enum MomentComposerVisibilityOptionKind {
  public,
  friends,
  closeFriends,
  onlyMe,
}

class MomentQuickComposerActionMeta {
  final MomentQuickComposerActionKind kind;
  final IconData icon;
  final String label;
  final bool selected;
  final String perfKey;

  const MomentQuickComposerActionMeta({
    required this.kind,
    required this.icon,
    required this.label,
    required this.selected,
    required this.perfKey,
  });
}

class MomentQuickComposerChromeMeta {
  final double darkBorderAlpha;
  final double lightBorderAlpha;
  final double borderWidth;
  final Color lightSurfaceColor;
  final double headerHorizontalPadding;
  final double headerVerticalPadding;
  final double initialBoxSize;
  final double initialBoxRadius;
  final double initialBackgroundAlpha;
  final FontWeight initialFontWeight;
  final double initialFieldGap;
  final double fieldHeight;
  final double fieldHorizontalPadding;
  final double fieldRadius;
  final double placeholderAlpha;
  final double trailingGap;
  final double trailingIconSize;
  final double trailingIconAlpha;
  final double dividerHeight;
  final double dividerThickness;
  final double dividerIndent;
  final double actionsStartPadding;
  final double actionsEndPadding;
  final double actionsVerticalPadding;
  final double actionEndSpacing;
  final double actionHeight;
  final double actionHorizontalPadding;
  final double actionRadius;
  final double selectedFillDarkAlpha;
  final double selectedFillLightAlpha;
  final double unselectedTextAlpha;
  final double actionIconSize;
  final double actionIconGap;
  final double actionFontSize;
  final FontWeight selectedFontWeight;
  final FontWeight unselectedFontWeight;

  const MomentQuickComposerChromeMeta({
    required this.darkBorderAlpha,
    required this.lightBorderAlpha,
    required this.borderWidth,
    required this.lightSurfaceColor,
    required this.headerHorizontalPadding,
    required this.headerVerticalPadding,
    required this.initialBoxSize,
    required this.initialBoxRadius,
    required this.initialBackgroundAlpha,
    required this.initialFontWeight,
    required this.initialFieldGap,
    required this.fieldHeight,
    required this.fieldHorizontalPadding,
    required this.fieldRadius,
    required this.placeholderAlpha,
    required this.trailingGap,
    required this.trailingIconSize,
    required this.trailingIconAlpha,
    required this.dividerHeight,
    required this.dividerThickness,
    required this.dividerIndent,
    required this.actionsStartPadding,
    required this.actionsEndPadding,
    required this.actionsVerticalPadding,
    required this.actionEndSpacing,
    required this.actionHeight,
    required this.actionHorizontalPadding,
    required this.actionRadius,
    required this.selectedFillDarkAlpha,
    required this.selectedFillLightAlpha,
    required this.unselectedTextAlpha,
    required this.actionIconSize,
    required this.actionIconGap,
    required this.actionFontSize,
    required this.selectedFontWeight,
    required this.unselectedFontWeight,
  });
}

class MomentComposerVisibilityOptionMeta {
  final MomentComposerVisibilityOptionKind kind;
  final String scope;
  final IconData icon;
  final String label;
  final bool selected;
  final bool clearsAudienceTag;
  final String perfKey;

  const MomentComposerVisibilityOptionMeta({
    required this.kind,
    required this.scope,
    required this.icon,
    required this.label,
    required this.selected,
    required this.clearsAudienceTag,
    required this.perfKey,
  });
}

class MomentComposerVisibilityChipChromeMeta {
  final double summaryBottomGap;
  final double wrapSpacing;
  final double wrapRunSpacing;
  final double iconSize;
  final double selectedIconAlpha;
  final double unselectedIconAlpha;
  final double helperTopGap;
  final double helperFontSize;
  final double helperAlpha;
  final double helperBottomGap;

  const MomentComposerVisibilityChipChromeMeta({
    required this.summaryBottomGap,
    required this.wrapSpacing,
    required this.wrapRunSpacing,
    required this.iconSize,
    required this.selectedIconAlpha,
    required this.unselectedIconAlpha,
    required this.helperTopGap,
    required this.helperFontSize,
    required this.helperAlpha,
    required this.helperBottomGap,
  });
}

class MomentComposerAudienceTagActionMeta {
  final String tag;
  final String tagMode;
  final IconData icon;
  final String label;
  final bool selected;
  final String perfKey;

  const MomentComposerAudienceTagActionMeta({
    required this.tag,
    required this.tagMode,
    required this.icon,
    required this.label,
    required this.selected,
    required this.perfKey,
  });
}

class MomentComposerAudienceTagChipChromeMeta {
  final double wrapSpacing;
  final double wrapRunSpacing;
  final double iconSize;
  final double bottomGap;

  const MomentComposerAudienceTagChipChromeMeta({
    required this.wrapSpacing,
    required this.wrapRunSpacing,
    required this.iconSize,
    required this.bottomGap,
  });
}

class MomentComposerAudienceCopyMeta {
  final String privacyHelperLabel;
  final IconData tagFieldIcon;
  final String tagFieldLabel;
  final String tagFieldHint;
  final IconData onboardingIcon;
  final String onboardingHint;
  final String onboardingDismissTooltip;
  final String suggestedTagsLabel;

  const MomentComposerAudienceCopyMeta({
    required this.privacyHelperLabel,
    required this.tagFieldIcon,
    required this.tagFieldLabel,
    required this.tagFieldHint,
    required this.onboardingIcon,
    required this.onboardingHint,
    required this.onboardingDismissTooltip,
    required this.suggestedTagsLabel,
  });
}

class MomentComposerAudienceFieldChromeMeta {
  final double fieldPrefixIconSize;
  final double fieldBorderRadius;
  final double onboardingTopGap;
  final double onboardingPadding;
  final double onboardingRadius;
  final double onboardingBackgroundAlpha;
  final double onboardingIconSize;
  final double onboardingIconAlpha;
  final double onboardingIconGap;
  final double onboardingFontSize;
  final double onboardingTextAlpha;
  final VisualDensity onboardingDismissVisualDensity;
  final EdgeInsets onboardingDismissPadding;
  final double onboardingDismissMinSize;
  final double onboardingDismissIconSize;
  final double onboardingDismissIconAlpha;
  final double suggestedTopGap;
  final double suggestedLabelFontSize;
  final double suggestedLabelAlpha;
  final double suggestedChipsTopGap;
  final double suggestedWrapSpacing;
  final double suggestedWrapRunSpacing;
  final double suggestedChipIconSize;
  final VisualDensity suggestedChipVisualDensity;
  final double suggestedSelectedBorderAlpha;

  const MomentComposerAudienceFieldChromeMeta({
    required this.fieldPrefixIconSize,
    required this.fieldBorderRadius,
    required this.onboardingTopGap,
    required this.onboardingPadding,
    required this.onboardingRadius,
    required this.onboardingBackgroundAlpha,
    required this.onboardingIconSize,
    required this.onboardingIconAlpha,
    required this.onboardingIconGap,
    required this.onboardingFontSize,
    required this.onboardingTextAlpha,
    required this.onboardingDismissVisualDensity,
    required this.onboardingDismissPadding,
    required this.onboardingDismissMinSize,
    required this.onboardingDismissIconSize,
    required this.onboardingDismissIconAlpha,
    required this.suggestedTopGap,
    required this.suggestedLabelFontSize,
    required this.suggestedLabelAlpha,
    required this.suggestedChipsTopGap,
    required this.suggestedWrapSpacing,
    required this.suggestedWrapRunSpacing,
    required this.suggestedChipIconSize,
    required this.suggestedChipVisualDensity,
    required this.suggestedSelectedBorderAlpha,
  });
}

class MomentComposerSuggestedAudienceTagMeta {
  final String tag;
  final String label;
  final IconData icon;
  final bool selected;
  final String perfKey;

  const MomentComposerSuggestedAudienceTagMeta({
    required this.tag,
    required this.label,
    required this.icon,
    required this.selected,
    required this.perfKey,
  });
}

class MomentComposerOfficialDirectoryLinkMeta {
  final String city;
  final String label;
  final IconData icon;
  final IconData trailingIcon;
  final String perfKey;
  final double topGap;
  final double radius;
  final double iconSize;
  final double iconGap;
  final double fontSize;
  final double trailingGap;
  final double trailingIconSize;
  final double trailingIconAlpha;

  const MomentComposerOfficialDirectoryLinkMeta({
    required this.city,
    required this.label,
    required this.icon,
    required this.trailingIcon,
    required this.perfKey,
    required this.topGap,
    required this.radius,
    required this.iconSize,
    required this.iconGap,
    required this.fontSize,
    required this.trailingGap,
    required this.trailingIconSize,
    required this.trailingIconAlpha,
  });
}

class MomentComposerTrendingTopicsSectionMeta {
  final String titleLabel;
  final IconData icon;
  final int visibleTopicLimit;
  final double topGap;
  final double headerIconSize;
  final double headerIconAlpha;
  final double headerIconGap;
  final double titleFontSize;
  final FontWeight titleWeight;
  final double titleAlpha;
  final double chipsTopGap;
  final double chipSpacing;
  final double chipRunSpacing;
  final double chipIconSize;
  final VisualDensity chipVisualDensity;
  final double chipIconAlpha;

  const MomentComposerTrendingTopicsSectionMeta({
    required this.titleLabel,
    required this.icon,
    required this.visibleTopicLimit,
    required this.topGap,
    required this.headerIconSize,
    required this.headerIconAlpha,
    required this.headerIconGap,
    required this.titleFontSize,
    required this.titleWeight,
    required this.titleAlpha,
    required this.chipsTopGap,
    required this.chipSpacing,
    required this.chipRunSpacing,
    required this.chipIconSize,
    required this.chipVisualDensity,
    required this.chipIconAlpha,
  });
}

class MomentComposerMediaActionMeta {
  final double previewHeight;
  final double previewBorderRadius;
  final double controlsTopGap;
  final IconData removePhotoIcon;
  final double removePhotoIconSize;
  final String removePhotoTooltip;
  final String removePhotoPerfKey;
  final double previewBottomGap;
  final IconData addPhotoIcon;
  final double addPhotoIconSize;
  final String addPhotoTooltip;
  final String addPhotoPerfKey;
  final IconData publishIcon;
  final String publishLabel;
  final String publishPerfKey;

  const MomentComposerMediaActionMeta({
    required this.previewHeight,
    required this.previewBorderRadius,
    required this.controlsTopGap,
    required this.removePhotoIcon,
    required this.removePhotoIconSize,
    required this.removePhotoTooltip,
    required this.removePhotoPerfKey,
    required this.previewBottomGap,
    required this.addPhotoIcon,
    required this.addPhotoIconSize,
    required this.addPhotoTooltip,
    required this.addPhotoPerfKey,
    required this.publishIcon,
    required this.publishLabel,
    required this.publishPerfKey,
  });
}

class MomentInlineComposerTextMeta {
  final IconData titleIcon;
  final String titleLabel;
  final String textHint;
  final int minLines;
  final int maxLines;
  final double panelPadding;
  final double titleIconSize;
  final double titleIconAlpha;
  final double titleIconGap;
  final FontWeight titleWeight;
  final double titleBottomGap;
  final double textFieldBottomGap;

  const MomentInlineComposerTextMeta({
    required this.titleIcon,
    required this.titleLabel,
    required this.textHint,
    required this.minLines,
    required this.maxLines,
    required this.panelPadding,
    required this.titleIconSize,
    required this.titleIconAlpha,
    required this.titleIconGap,
    required this.titleWeight,
    required this.titleBottomGap,
    required this.textFieldBottomGap,
  });
}

class MomentInlineComposerPublishStateMeta {
  final bool canPublish;
  final String effectiveText;
  final String miniProgramId;
  final bool hasMedia;
  final bool hasMiniProgram;

  const MomentInlineComposerPublishStateMeta({
    required this.canPublish,
    required this.effectiveText,
    required this.miniProgramId,
    required this.hasMedia,
    required this.hasMiniProgram,
  });
}

class MomentComposerSheetActionMeta {
  final MomentComposerSheetActionKind kind;
  final IconData icon;
  final String label;
  final String perfKey;

  const MomentComposerSheetActionMeta({
    required this.kind,
    required this.icon,
    required this.label,
    required this.perfKey,
  });
}

class MomentComposerSheetMeta {
  final List<MomentComposerSheetActionMeta> actions;
  final String cancelLabel;

  const MomentComposerSheetMeta({
    required this.actions,
    required this.cancelLabel,
  });
}

class MomentComposerSheetChromeMeta {
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
  final double sectionGap;

  const MomentComposerSheetChromeMeta({
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
    required this.sectionGap,
  });
}

class MomentQuickComposerHeaderMeta {
  final String initial;
  final String placeholder;
  final IconData trailingIcon;
  final String openPerfKey;

  const MomentQuickComposerHeaderMeta({
    required this.initial,
    required this.placeholder,
    required this.trailingIcon,
    required this.openPerfKey,
  });
}

MomentQuickComposerHeaderMeta momentQuickComposerHeaderMeta({
  required String displayName,
  required bool isArabic,
}) {
  final cleanName = displayName.trim();
  final fallbackName = isArabic ? 'أنت' : 'You';
  final name = cleanName.isNotEmpty ? cleanName : fallbackName;
  return MomentQuickComposerHeaderMeta(
    initial: _firstVisibleCharacter(name).toUpperCase(),
    placeholder: isArabic ? 'شارك لحظة...' : 'Share a moment...',
    trailingIcon: Icons.camera_alt_outlined,
    openPerfKey: 'moments_quick_composer_open',
  );
}

MomentQuickComposerChromeMeta momentQuickComposerChromeMeta() {
  return const MomentQuickComposerChromeMeta(
    darkBorderAlpha: .55,
    lightBorderAlpha: .70,
    borderWidth: .6,
    lightSurfaceColor: Colors.white,
    headerHorizontalPadding: 12,
    headerVerticalPadding: 10,
    initialBoxSize: 38,
    initialBoxRadius: 6,
    initialBackgroundAlpha: .12,
    initialFontWeight: FontWeight.w800,
    initialFieldGap: 10,
    fieldHeight: 38,
    fieldHorizontalPadding: 12,
    fieldRadius: 8,
    placeholderAlpha: .58,
    trailingGap: 8,
    trailingIconSize: 22,
    trailingIconAlpha: .62,
    dividerHeight: 1,
    dividerThickness: .5,
    dividerIndent: 60,
    actionsStartPadding: 60,
    actionsEndPadding: 12,
    actionsVerticalPadding: 7,
    actionEndSpacing: 14,
    actionHeight: 32,
    actionHorizontalPadding: 8,
    actionRadius: 6,
    selectedFillDarkAlpha: .18,
    selectedFillLightAlpha: .08,
    unselectedTextAlpha: .76,
    actionIconSize: 17,
    actionIconGap: 5,
    actionFontSize: 12,
    selectedFontWeight: FontWeight.w700,
    unselectedFontWeight: FontWeight.w500,
  );
}

MomentComposerSheetMeta momentComposerSheetMeta({
  required bool isArabic,
}) {
  return MomentComposerSheetMeta(
    actions: <MomentComposerSheetActionMeta>[
      MomentComposerSheetActionMeta(
        kind: MomentComposerSheetActionKind.text,
        icon: Icons.edit_note_outlined,
        label: isArabic ? 'لحظة نصية' : 'Text-only Moment',
        perfKey: 'moments_sheet_text_only',
      ),
      MomentComposerSheetActionMeta(
        kind: MomentComposerSheetActionKind.camera,
        icon: Icons.photo_camera_outlined,
        label: isArabic ? 'التقاط صورة' : 'Take Photo',
        perfKey: 'moments_sheet_take_photo',
      ),
      MomentComposerSheetActionMeta(
        kind: MomentComposerSheetActionKind.album,
        icon: Icons.photo_library_outlined,
        label: isArabic ? 'اختيار من الألبوم' : 'Choose from Album',
        perfKey: 'moments_sheet_choose_album',
      ),
    ],
    cancelLabel: isArabic ? 'إلغاء' : 'Cancel',
  );
}

MomentComposerSheetChromeMeta momentComposerSheetChromeMeta() {
  return const MomentComposerSheetChromeMeta(
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
    sectionGap: 8,
  );
}

List<MomentQuickComposerActionMeta> momentQuickComposerActionMetas({
  required bool isArabic,
  required bool filtersSelected,
}) {
  return <MomentQuickComposerActionMeta>[
    MomentQuickComposerActionMeta(
      kind: MomentQuickComposerActionKind.camera,
      icon: Icons.photo_camera_outlined,
      label: isArabic ? 'كاميرا' : 'Camera',
      selected: false,
      perfKey: 'moments_quick_camera',
    ),
    MomentQuickComposerActionMeta(
      kind: MomentQuickComposerActionKind.album,
      icon: Icons.photo_library_outlined,
      label: isArabic ? 'ألبوم' : 'Album',
      selected: false,
      perfKey: 'moments_quick_album',
    ),
    MomentQuickComposerActionMeta(
      kind: MomentQuickComposerActionKind.friends,
      icon: Icons.group_outlined,
      label: isArabic ? 'الأصدقاء' : 'Friends',
      selected: false,
      perfKey: 'moments_quick_privacy_friends',
    ),
    MomentQuickComposerActionMeta(
      kind: MomentQuickComposerActionKind.closeFriends,
      icon: Icons.star_outline,
      label: isArabic ? 'المقرّبون' : 'Close',
      selected: false,
      perfKey: 'moments_quick_privacy_close_friends',
    ),
    MomentQuickComposerActionMeta(
      kind: MomentQuickComposerActionKind.onlyMe,
      icon: Icons.lock_outline,
      label: isArabic ? 'أنا فقط' : 'Only me',
      selected: false,
      perfKey: 'moments_quick_privacy_only_me',
    ),
    MomentQuickComposerActionMeta(
      kind: MomentQuickComposerActionKind.filters,
      icon: Icons.tune,
      label: isArabic ? 'الفلاتر' : 'Filters',
      selected: filtersSelected,
      perfKey: filtersSelected
          ? 'moments_quick_filters_off'
          : 'moments_quick_filters_on',
    ),
  ];
}

List<MomentComposerVisibilityOptionMeta> momentComposerVisibilityOptionMetas({
  required bool isArabic,
  required String selectedScope,
}) {
  final scope = selectedScope.trim().toLowerCase();
  return <MomentComposerVisibilityOptionMeta>[
    MomentComposerVisibilityOptionMeta(
      kind: MomentComposerVisibilityOptionKind.public,
      scope: 'public',
      icon: Icons.public,
      label: isArabic ? 'عام' : 'Public',
      selected: scope == 'public',
      clearsAudienceTag: true,
      perfKey: 'moments_inline_privacy_public',
    ),
    MomentComposerVisibilityOptionMeta(
      kind: MomentComposerVisibilityOptionKind.friends,
      scope: 'friends',
      icon: Icons.group_outlined,
      label: isArabic ? 'الأصدقاء فقط' : 'Friends only',
      selected: scope == 'friends',
      clearsAudienceTag: false,
      perfKey: 'moments_inline_privacy_friends',
    ),
    MomentComposerVisibilityOptionMeta(
      kind: MomentComposerVisibilityOptionKind.closeFriends,
      scope: 'close_friends',
      icon: Icons.star_outline,
      label: isArabic ? 'الأصدقاء المقرّبون' : 'Close friends',
      selected: scope == 'close_friends',
      clearsAudienceTag: false,
      perfKey: 'moments_inline_privacy_close_friends',
    ),
    MomentComposerVisibilityOptionMeta(
      kind: MomentComposerVisibilityOptionKind.onlyMe,
      scope: 'only_me',
      icon: Icons.lock_outline,
      label: isArabic ? 'أنا فقط' : 'Only me',
      selected: scope == 'only_me',
      clearsAudienceTag: true,
      perfKey: 'moments_inline_privacy_only_me',
    ),
  ];
}

MomentComposerVisibilityChipChromeMeta
    momentComposerVisibilityChipChromeMeta() {
  return const MomentComposerVisibilityChipChromeMeta(
    summaryBottomGap: 8,
    wrapSpacing: 8,
    wrapRunSpacing: 8,
    iconSize: 16,
    selectedIconAlpha: 1,
    unselectedIconAlpha: .64,
    helperTopGap: 4,
    helperFontSize: 11,
    helperAlpha: .65,
    helperBottomGap: 6,
  );
}

List<MomentComposerAudienceTagActionMeta> momentComposerAudienceTagActionMetas({
  required Iterable<String> tags,
  required String selectedTag,
  required String selectedTagMode,
  required bool isArabic,
}) {
  final selected = selectedTag.trim();
  final selectedMode =
      selectedTagMode.trim().toLowerCase() == 'except' ? 'except' : 'only';
  final cleanTags = <String>[];
  for (final rawTag in tags) {
    final tag = rawTag.trim();
    if (tag.isEmpty || cleanTags.contains(tag)) continue;
    cleanTags.add(tag);
  }

  return cleanTags.expand((tag) {
    return <MomentComposerAudienceTagActionMeta>[
      MomentComposerAudienceTagActionMeta(
        tag: tag,
        tagMode: 'only',
        icon: Icons.label_outline,
        label: isArabic ? 'فقط $tag' : 'Only $tag',
        selected: selected == tag && selectedMode == 'only',
        perfKey: 'moments_inline_audience_tag_only',
      ),
      MomentComposerAudienceTagActionMeta(
        tag: tag,
        tagMode: 'except',
        icon: Icons.group_remove_outlined,
        label: isArabic ? 'الأصدقاء باستثناء $tag' : 'Friends except $tag',
        selected: selected == tag && selectedMode == 'except',
        perfKey: 'moments_inline_audience_tag_except',
      ),
    ];
  }).toList(growable: false);
}

MomentComposerAudienceTagChipChromeMeta
    momentComposerAudienceTagChipChromeMeta() {
  return const MomentComposerAudienceTagChipChromeMeta(
    wrapSpacing: 8,
    wrapRunSpacing: 4,
    iconSize: 15,
    bottomGap: 6,
  );
}

MomentComposerAudienceCopyMeta momentComposerAudienceCopyMeta({
  required bool isArabic,
}) {
  return MomentComposerAudienceCopyMeta(
    privacyHelperLabel: isArabic
        ? 'تحكّم بمن يمكنه رؤية هذه اللحظة.'
        : 'Control who can view this Moment.',
    tagFieldIcon: Icons.label_outline,
    tagFieldLabel: isArabic ? 'وسم الجمهور' : 'Audience label',
    tagFieldHint:
        isArabic ? 'العائلة، العمل، المقرّبون' : 'Family, Work, Close friends',
    onboardingIcon: Icons.info_outline,
    onboardingHint: isArabic
        ? 'استخدم وسوماً مثل العائلة أو العمل للمشاركة مع دائرة محددة.'
        : 'Use labels like Family or Work to share with a precise circle.',
    onboardingDismissTooltip: isArabic ? 'إغلاق' : 'Dismiss',
    suggestedTagsLabel: isArabic ? 'وسوم مقترحة' : 'Suggested labels',
  );
}

MomentComposerAudienceFieldChromeMeta momentComposerAudienceFieldChromeMeta() {
  return const MomentComposerAudienceFieldChromeMeta(
    fieldPrefixIconSize: 18,
    fieldBorderRadius: 16,
    onboardingTopGap: 6,
    onboardingPadding: 8,
    onboardingRadius: 8,
    onboardingBackgroundAlpha: .06,
    onboardingIconSize: 16,
    onboardingIconAlpha: .80,
    onboardingIconGap: 6,
    onboardingFontSize: 11,
    onboardingTextAlpha: .70,
    onboardingDismissVisualDensity: VisualDensity.compact,
    onboardingDismissPadding: EdgeInsets.zero,
    onboardingDismissMinSize: 28,
    onboardingDismissIconSize: 16,
    onboardingDismissIconAlpha: .60,
    suggestedTopGap: 6,
    suggestedLabelFontSize: 11,
    suggestedLabelAlpha: .65,
    suggestedChipsTopGap: 4,
    suggestedWrapSpacing: 6,
    suggestedWrapRunSpacing: 6,
    suggestedChipIconSize: 15,
    suggestedChipVisualDensity: VisualDensity.compact,
    suggestedSelectedBorderAlpha: .42,
  );
}

List<MomentComposerSuggestedAudienceTagMeta>
    momentComposerSuggestedAudienceTagMetas({
  required Iterable<String> tags,
  required String selectedTag,
  int limit = 8,
}) {
  final selected = selectedTag.trim();
  final cleanTags = <String>[];
  for (final rawTag in tags) {
    final tag = rawTag.trim();
    if (tag.isEmpty || cleanTags.contains(tag)) continue;
    cleanTags.add(tag);
    if (cleanTags.length >= limit) break;
  }

  return cleanTags.map((tag) {
    return MomentComposerSuggestedAudienceTagMeta(
      tag: tag,
      label: tag,
      icon: Icons.label_important_outline,
      selected: tag == selected,
      perfKey: 'moments_inline_suggested_audience_tag',
    );
  }).toList(growable: false);
}

MomentComposerOfficialDirectoryLinkMeta?
    momentComposerOfficialDirectoryLinkMeta({
  required String city,
  required bool isArabic,
}) {
  final cleanCity = city.trim();
  if (cleanCity.isEmpty) return null;
  return MomentComposerOfficialDirectoryLinkMeta(
    city: cleanCity,
    label: isArabic ? 'خدمات في $cleanCity' : 'Services in $cleanCity',
    icon: Icons.verified_outlined,
    trailingIcon: Icons.chevron_right,
    perfKey: 'moments_inline_official_directory_open',
    topGap: 6,
    radius: 6,
    iconSize: 16,
    iconGap: 4,
    fontSize: 11,
    trailingGap: 2,
    trailingIconSize: 14,
    trailingIconAlpha: .80,
  );
}

MomentComposerTrendingTopicsSectionMeta
    momentComposerTrendingTopicsSectionMeta({
  required bool isArabic,
}) {
  return MomentComposerTrendingTopicsSectionMeta(
    titleLabel: isArabic ? 'المواضيع الشائعة' : 'Trending topics',
    icon: Icons.trending_up,
    visibleTopicLimit: 8,
    topGap: 8,
    headerIconSize: 15,
    headerIconAlpha: .82,
    headerIconGap: 4,
    titleFontSize: 11,
    titleWeight: FontWeight.w700,
    titleAlpha: .72,
    chipsTopGap: 4,
    chipSpacing: 6,
    chipRunSpacing: 6,
    chipIconSize: 16,
    chipVisualDensity: VisualDensity.compact,
    chipIconAlpha: .90,
  );
}

MomentComposerMediaActionMeta momentComposerMediaActionMeta({
  required bool isArabic,
}) {
  return MomentComposerMediaActionMeta(
    previewHeight: 180,
    previewBorderRadius: 8,
    controlsTopGap: 8,
    removePhotoIcon: Icons.close,
    removePhotoIconSize: 20,
    removePhotoTooltip: isArabic ? 'إزالة الصورة' : 'Remove photo',
    removePhotoPerfKey: 'moments_inline_photo_remove',
    previewBottomGap: 4,
    addPhotoIcon: Icons.photo_camera_outlined,
    addPhotoIconSize: 20,
    addPhotoTooltip: isArabic ? 'إضافة صورة' : 'Add photo',
    addPhotoPerfKey: 'moments_inline_photo_add',
    publishIcon: Icons.send_outlined,
    publishLabel: isArabic ? 'نشر' : 'Post',
    publishPerfKey: 'moments_inline_publish',
  );
}

MomentInlineComposerTextMeta momentInlineComposerTextMeta({
  required bool isArabic,
}) {
  return MomentInlineComposerTextMeta(
    titleIcon: Icons.edit_note_outlined,
    titleLabel: isArabic ? 'مشاركة لحظة' : 'Share a Moment',
    textHint: isArabic ? 'شارك ما يحدث الآن' : 'Share what is happening',
    minLines: 1,
    maxLines: 3,
    panelPadding: 12,
    titleIconSize: 18,
    titleIconAlpha: .92,
    titleIconGap: 6,
    titleWeight: FontWeight.w700,
    titleBottomGap: 8,
    textFieldBottomGap: 8,
  );
}

MomentInlineComposerPublishStateMeta momentInlineComposerPublishStateMeta({
  required String draftText,
  required String presetText,
  required bool hasPendingImage,
  required bool hasPresetImage,
  required String miniProgramId,
}) {
  final cleanDraftText = draftText.trim();
  final cleanPresetText = presetText.trim();
  final effectiveText =
      cleanDraftText.isNotEmpty ? cleanDraftText : cleanPresetText;
  final cleanMiniProgramId = miniProgramId.trim();
  final hasMedia = hasPendingImage || hasPresetImage;
  final hasMiniProgram = cleanMiniProgramId.isNotEmpty;
  return MomentInlineComposerPublishStateMeta(
    canPublish: effectiveText.isNotEmpty || hasMedia || hasMiniProgram,
    effectiveText: effectiveText,
    miniProgramId: cleanMiniProgramId,
    hasMedia: hasMedia,
    hasMiniProgram: hasMiniProgram,
  );
}

String momentInlineComposerMiniProgramId({
  required String activeMiniProgramId,
  required String presetMiniProgramId,
}) {
  final preset = presetMiniProgramId.trim().toLowerCase();
  if (preset.isNotEmpty) return preset;
  return activeMiniProgramId.trim().toLowerCase();
}

String _firstVisibleCharacter(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return '?';
  return String.fromCharCode(clean.runes.first);
}
