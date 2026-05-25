import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_composer_meta.dart';

void main() {
  group('momentQuickComposerHeaderMeta', () {
    test('builds WeChat-style quick composer chrome', () {
      final chrome = momentQuickComposerChromeMeta();

      expect(chrome.darkBorderAlpha, .55);
      expect(chrome.lightBorderAlpha, .70);
      expect(chrome.borderWidth, .6);
      expect(chrome.lightSurfaceColor, Colors.white);
      expect(chrome.headerHorizontalPadding, 12);
      expect(chrome.headerVerticalPadding, 10);
      expect(chrome.initialBoxSize, 38);
      expect(chrome.initialBoxRadius, 6);
      expect(chrome.initialBackgroundAlpha, .12);
      expect(chrome.initialFontWeight, FontWeight.w800);
      expect(chrome.initialFieldGap, 10);
      expect(chrome.fieldHeight, 38);
      expect(chrome.fieldHorizontalPadding, 12);
      expect(chrome.fieldRadius, 8);
      expect(chrome.placeholderAlpha, .58);
      expect(chrome.trailingGap, 8);
      expect(chrome.trailingIconSize, 22);
      expect(chrome.trailingIconAlpha, .62);
      expect(chrome.dividerHeight, 1);
      expect(chrome.dividerThickness, .5);
      expect(chrome.dividerIndent, 60);
      expect(chrome.actionsStartPadding, 60);
      expect(chrome.actionsEndPadding, 12);
      expect(chrome.actionsVerticalPadding, 7);
      expect(chrome.actionEndSpacing, 14);
      expect(chrome.actionHeight, 32);
      expect(chrome.actionHorizontalPadding, 8);
      expect(chrome.actionRadius, 6);
      expect(chrome.selectedFillDarkAlpha, .18);
      expect(chrome.selectedFillLightAlpha, .08);
      expect(chrome.unselectedTextAlpha, .76);
      expect(chrome.actionIconSize, 17);
      expect(chrome.actionIconGap, 5);
      expect(chrome.actionFontSize, 12);
      expect(chrome.selectedFontWeight, FontWeight.w700);
      expect(chrome.unselectedFontWeight, FontWeight.w500);
    });

    test('builds English header metadata from display name', () {
      final meta = momentQuickComposerHeaderMeta(
        displayName: ' Radi ',
        isArabic: false,
      );

      expect(meta.initial, 'R');
      expect(meta.placeholder, 'Share a moment...');
      expect(meta.trailingIcon, Icons.camera_alt_outlined);
      expect(meta.openPerfKey, 'moments_quick_composer_open');
    });

    test('falls back to localized user initial', () {
      final english = momentQuickComposerHeaderMeta(
        displayName: '',
        isArabic: false,
      );
      final arabic = momentQuickComposerHeaderMeta(
        displayName: ' ',
        isArabic: true,
      );

      expect(english.initial, 'Y');
      expect(arabic.initial, 'أ');
      expect(arabic.placeholder, 'شارك لحظة...');
    });
  });

  group('momentQuickComposerActionMetas', () {
    test('builds quick actions in stable WeChat-style order', () {
      final actions = momentQuickComposerActionMetas(
        isArabic: false,
        filtersSelected: false,
      );

      expect(actions.map((a) => a.kind), <MomentQuickComposerActionKind>[
        MomentQuickComposerActionKind.camera,
        MomentQuickComposerActionKind.album,
        MomentQuickComposerActionKind.friends,
        MomentQuickComposerActionKind.closeFriends,
        MomentQuickComposerActionKind.onlyMe,
        MomentQuickComposerActionKind.filters,
      ]);
      expect(actions.first.icon, Icons.photo_camera_outlined);
      expect(actions.first.label, 'Camera');
      expect(actions.last.icon, Icons.tune);
      expect(actions.last.label, 'Filters');
      expect(actions.last.selected, isFalse);
      expect(actions.last.perfKey, 'moments_quick_filters_on');
    });

    test('uses off perf key when filters are selected', () {
      final actions = momentQuickComposerActionMetas(
        isArabic: false,
        filtersSelected: true,
      );

      final filters = actions.last;
      expect(filters.kind, MomentQuickComposerActionKind.filters);
      expect(filters.selected, isTrue);
      expect(filters.perfKey, 'moments_quick_filters_off');
    });

    test('localizes Arabic quick action labels', () {
      final actions = momentQuickComposerActionMetas(
        isArabic: true,
        filtersSelected: false,
      );

      expect(actions.map((a) => a.label), <String>[
        'كاميرا',
        'ألبوم',
        'الأصدقاء',
        'المقرّبون',
        'أنا فقط',
        'الفلاتر',
      ]);
    });
  });

  group('momentComposerVisibilityOptionMetas', () {
    test('builds inline privacy chip chrome', () {
      final chrome = momentComposerVisibilityChipChromeMeta();

      expect(chrome.summaryBottomGap, 8);
      expect(chrome.wrapSpacing, 8);
      expect(chrome.wrapRunSpacing, 8);
      expect(chrome.iconSize, 16);
      expect(chrome.selectedIconAlpha, 1);
      expect(chrome.unselectedIconAlpha, .64);
      expect(chrome.helperTopGap, 4);
      expect(chrome.helperFontSize, 11);
      expect(chrome.helperAlpha, .65);
      expect(chrome.helperBottomGap, 6);
    });

    test('builds inline privacy choices in stable order', () {
      final options = momentComposerVisibilityOptionMetas(
        isArabic: false,
        selectedScope: 'friends',
      );

      expect(options.map((o) => o.kind), <MomentComposerVisibilityOptionKind>[
        MomentComposerVisibilityOptionKind.public,
        MomentComposerVisibilityOptionKind.friends,
        MomentComposerVisibilityOptionKind.closeFriends,
        MomentComposerVisibilityOptionKind.onlyMe,
      ]);
      expect(options.map((o) => o.scope), <String>[
        'public',
        'friends',
        'close_friends',
        'only_me',
      ]);
      expect(options.map((o) => o.label), <String>[
        'Public',
        'Friends only',
        'Close friends',
        'Only me',
      ]);
      expect(options[0].icon, Icons.public);
      expect(options[1].selected, isTrue);
      expect(options[0].clearsAudienceTag, isTrue);
      expect(options[1].clearsAudienceTag, isFalse);
      expect(options[3].clearsAudienceTag, isTrue);
      expect(options[2].perfKey, 'moments_inline_privacy_close_friends');
    });

    test('localizes inline privacy choices', () {
      final options = momentComposerVisibilityOptionMetas(
        isArabic: true,
        selectedScope: 'only_me',
      );

      expect(options.map((o) => o.label), <String>[
        'عام',
        'الأصدقاء فقط',
        'الأصدقاء المقرّبون',
        'أنا فقط',
      ]);
      expect(options.last.selected, isTrue);
    });
  });

  group('momentComposerAudienceTagActionMetas', () {
    test('builds audience tag chip chrome', () {
      final chrome = momentComposerAudienceTagChipChromeMeta();

      expect(chrome.wrapSpacing, 8);
      expect(chrome.wrapRunSpacing, 4);
      expect(chrome.iconSize, 15);
      expect(chrome.bottomGap, 6);
    });

    test('builds only and except actions for each clean tag', () {
      final actions = momentComposerAudienceTagActionMetas(
        tags: const <String>[' Family ', '', 'Work', 'Family'],
        selectedTag: 'Work',
        selectedTagMode: 'except',
        isArabic: false,
      );

      expect(actions.map((a) => a.tag), <String>[
        'Family',
        'Family',
        'Work',
        'Work',
      ]);
      expect(actions.map((a) => a.tagMode), <String>[
        'only',
        'except',
        'only',
        'except',
      ]);
      expect(actions.map((a) => a.label), <String>[
        'Only Family',
        'Friends except Family',
        'Only Work',
        'Friends except Work',
      ]);
      expect(actions[0].icon, Icons.label_outline);
      expect(actions[1].icon, Icons.group_remove_outlined);
      expect(actions[2].selected, isFalse);
      expect(actions[3].selected, isTrue);
      expect(actions[3].perfKey, 'moments_inline_audience_tag_except');
    });

    test('localizes audience tag action labels', () {
      final actions = momentComposerAudienceTagActionMetas(
        tags: const <String>['العائلة'],
        selectedTag: 'العائلة',
        selectedTagMode: 'only',
        isArabic: true,
      );

      expect(actions.map((a) => a.label), <String>[
        'فقط العائلة',
        'الأصدقاء باستثناء العائلة',
      ]);
      expect(actions.first.selected, isTrue);
      expect(actions.last.selected, isFalse);
    });
  });

  group('momentComposerAudienceCopyMeta', () {
    test('builds polished English audience helper copy', () {
      final meta = momentComposerAudienceCopyMeta(isArabic: false);

      expect(meta.privacyHelperLabel, 'Control who can view this Moment.');
      expect(meta.tagFieldIcon, Icons.label_outline);
      expect(meta.tagFieldLabel, 'Audience label');
      expect(meta.tagFieldHint, 'Family, Work, Close friends');
      expect(meta.onboardingIcon, Icons.info_outline);
      expect(
        meta.onboardingHint,
        'Use labels like Family or Work to share with a precise circle.',
      );
      expect(meta.onboardingDismissTooltip, 'Dismiss');
      expect(meta.suggestedTagsLabel, 'Suggested labels');
    });

    test('localizes audience helper copy', () {
      final meta = momentComposerAudienceCopyMeta(isArabic: true);

      expect(meta.privacyHelperLabel, 'تحكّم بمن يمكنه رؤية هذه اللحظة.');
      expect(meta.tagFieldLabel, 'وسم الجمهور');
      expect(meta.tagFieldHint, 'العائلة، العمل، المقرّبون');
      expect(
        meta.onboardingHint,
        'استخدم وسوماً مثل العائلة أو العمل للمشاركة مع دائرة محددة.',
      );
      expect(meta.onboardingDismissTooltip, 'إغلاق');
      expect(meta.suggestedTagsLabel, 'وسوم مقترحة');
    });
  });

  group('momentComposerSuggestedAudienceTagMetas', () {
    test('builds audience tag field and suggestions chrome', () {
      final chrome = momentComposerAudienceFieldChromeMeta();

      expect(chrome.fieldPrefixIconSize, 18);
      expect(chrome.fieldBorderRadius, 16);
      expect(chrome.onboardingTopGap, 6);
      expect(chrome.onboardingPadding, 8);
      expect(chrome.onboardingRadius, 8);
      expect(chrome.onboardingBackgroundAlpha, .06);
      expect(chrome.onboardingIconSize, 16);
      expect(chrome.onboardingIconAlpha, .80);
      expect(chrome.onboardingIconGap, 6);
      expect(chrome.onboardingFontSize, 11);
      expect(chrome.onboardingTextAlpha, .70);
      expect(chrome.onboardingDismissVisualDensity, VisualDensity.compact);
      expect(chrome.onboardingDismissPadding, EdgeInsets.zero);
      expect(chrome.onboardingDismissMinSize, 28);
      expect(chrome.onboardingDismissIconSize, 16);
      expect(chrome.onboardingDismissIconAlpha, .60);
      expect(chrome.suggestedTopGap, 6);
      expect(chrome.suggestedLabelFontSize, 11);
      expect(chrome.suggestedLabelAlpha, .65);
      expect(chrome.suggestedChipsTopGap, 4);
      expect(chrome.suggestedWrapSpacing, 6);
      expect(chrome.suggestedWrapRunSpacing, 6);
      expect(chrome.suggestedChipIconSize, 15);
      expect(chrome.suggestedChipVisualDensity, VisualDensity.compact);
      expect(chrome.suggestedSelectedBorderAlpha, .42);
    });

    test('normalizes suggested labels and caps the visible list', () {
      final metas = momentComposerSuggestedAudienceTagMetas(
        tags: const <String>[
          ' Family ',
          '',
          'Work',
          'Family',
          'VIP',
          'School',
          'Gym',
          'Travel',
          'Market',
          'Extra',
        ],
        selectedTag: 'VIP',
      );

      expect(metas.map((m) => m.tag), <String>[
        'Family',
        'Work',
        'VIP',
        'School',
        'Gym',
        'Travel',
        'Market',
        'Extra',
      ]);
      expect(metas.map((m) => m.label), metas.map((m) => m.tag));
      expect(metas.first.icon, Icons.label_important_outline);
      expect(metas[2].selected, isTrue);
      expect(metas.first.perfKey, 'moments_inline_suggested_audience_tag');
    });

    test('allows tighter suggested label limits', () {
      final metas = momentComposerSuggestedAudienceTagMetas(
        tags: const <String>['Family', 'Work', 'VIP'],
        selectedTag: '',
        limit: 2,
      );

      expect(metas.map((m) => m.tag), <String>['Family', 'Work']);
    });
  });

  group('momentComposerOfficialDirectoryLinkMeta', () {
    test('builds a city official directory link', () {
      final meta = momentComposerOfficialDirectoryLinkMeta(
        city: ' Tunis ',
        isArabic: false,
      );

      expect(meta?.city, 'Tunis');
      expect(meta?.label, 'Services in Tunis');
      expect(meta?.icon, Icons.verified_outlined);
      expect(meta?.trailingIcon, Icons.chevron_right);
      expect(meta?.perfKey, 'moments_inline_official_directory_open');
      expect(meta?.topGap, 6);
      expect(meta?.radius, 6);
      expect(meta?.iconSize, 16);
      expect(meta?.iconGap, 4);
      expect(meta?.fontSize, 11);
      expect(meta?.trailingGap, 2);
      expect(meta?.trailingIconSize, 14);
      expect(meta?.trailingIconAlpha, .80);
    });

    test('hides official directory link without a city', () {
      final meta = momentComposerOfficialDirectoryLinkMeta(
        city: ' ',
        isArabic: false,
      );

      expect(meta, isNull);
    });

    test('localizes official directory link labels', () {
      final meta = momentComposerOfficialDirectoryLinkMeta(
        city: 'تونس',
        isArabic: true,
      );

      expect(meta?.label, 'خدمات في تونس');
    });
  });

  group('momentComposerTrendingTopicsSectionMeta', () {
    test('builds compact trending topic section metadata', () {
      final meta = momentComposerTrendingTopicsSectionMeta(isArabic: false);

      expect(meta.titleLabel, 'Trending topics');
      expect(meta.icon, Icons.trending_up);
      expect(meta.visibleTopicLimit, 8);
      expect(meta.topGap, 8);
      expect(meta.headerIconSize, 15);
      expect(meta.headerIconAlpha, .82);
      expect(meta.headerIconGap, 4);
      expect(meta.titleFontSize, 11);
      expect(meta.titleWeight, FontWeight.w700);
      expect(meta.titleAlpha, .72);
      expect(meta.chipsTopGap, 4);
      expect(meta.chipSpacing, 6);
      expect(meta.chipRunSpacing, 6);
      expect(meta.chipIconSize, 16);
      expect(meta.chipVisualDensity, VisualDensity.compact);
      expect(meta.chipIconAlpha, .90);
    });

    test('localizes trending topic section label', () {
      final meta = momentComposerTrendingTopicsSectionMeta(isArabic: true);

      expect(meta.titleLabel, 'المواضيع الشائعة');
    });
  });

  group('momentComposerMediaActionMeta', () {
    test('builds media preview and publish controls', () {
      final meta = momentComposerMediaActionMeta(isArabic: false);

      expect(meta.previewHeight, 180);
      expect(meta.previewBorderRadius, 8);
      expect(meta.controlsTopGap, 8);
      expect(meta.removePhotoIcon, Icons.close);
      expect(meta.removePhotoIconSize, 20);
      expect(meta.removePhotoTooltip, 'Remove photo');
      expect(meta.removePhotoPerfKey, 'moments_inline_photo_remove');
      expect(meta.previewBottomGap, 4);
      expect(meta.addPhotoIcon, Icons.photo_camera_outlined);
      expect(meta.addPhotoIconSize, 20);
      expect(meta.addPhotoTooltip, 'Add photo');
      expect(meta.addPhotoPerfKey, 'moments_inline_photo_add');
      expect(meta.publishIcon, Icons.send_outlined);
      expect(meta.publishLabel, 'Post');
      expect(meta.publishPerfKey, 'moments_inline_publish');
    });

    test('localizes media action labels', () {
      final meta = momentComposerMediaActionMeta(isArabic: true);

      expect(meta.removePhotoTooltip, 'إزالة الصورة');
      expect(meta.addPhotoTooltip, 'إضافة صورة');
      expect(meta.publishLabel, 'نشر');
    });
  });

  group('momentInlineComposerTextMeta', () {
    test('builds polished inline composer text metadata', () {
      final meta = momentInlineComposerTextMeta(isArabic: false);

      expect(meta.titleIcon, Icons.edit_note_outlined);
      expect(meta.titleLabel, 'Share a Moment');
      expect(meta.textHint, 'Share what is happening');
      expect(meta.minLines, 1);
      expect(meta.maxLines, 3);
      expect(meta.panelPadding, 12);
      expect(meta.titleIconSize, 18);
      expect(meta.titleIconAlpha, .92);
      expect(meta.titleIconGap, 6);
      expect(meta.titleWeight, FontWeight.w700);
      expect(meta.titleBottomGap, 8);
      expect(meta.textFieldBottomGap, 8);
    });

    test('localizes inline composer text metadata', () {
      final meta = momentInlineComposerTextMeta(isArabic: true);

      expect(meta.titleLabel, 'مشاركة لحظة');
      expect(meta.textHint, 'شارك ما يحدث الآن');
    });
  });

  group('momentInlineComposerPublishStateMeta', () {
    test('disables publishing empty inline Moments', () {
      final meta = momentInlineComposerPublishStateMeta(
        draftText: ' ',
        presetText: ' ',
        hasPendingImage: false,
        hasPresetImage: false,
        miniProgramId: ' ',
      );

      expect(meta.canPublish, isFalse);
      expect(meta.effectiveText, '');
      expect(meta.hasMedia, isFalse);
      expect(meta.hasMiniProgram, isFalse);
    });

    test('allows text, photo-only, preset, and mini-program Moments', () {
      final text = momentInlineComposerPublishStateMeta(
        draftText: ' Hello ',
        presetText: 'Preset',
        hasPendingImage: false,
        hasPresetImage: false,
        miniProgramId: '',
      );
      final photoOnly = momentInlineComposerPublishStateMeta(
        draftText: '',
        presetText: '',
        hasPendingImage: true,
        hasPresetImage: false,
        miniProgramId: '',
      );
      final preset = momentInlineComposerPublishStateMeta(
        draftText: '',
        presetText: ' Preset text ',
        hasPendingImage: false,
        hasPresetImage: false,
        miniProgramId: '',
      );
      final miniProgram = momentInlineComposerPublishStateMeta(
        draftText: '',
        presetText: '',
        hasPendingImage: false,
        hasPresetImage: false,
        miniProgramId: ' payments ',
      );

      expect(text.canPublish, isTrue);
      expect(text.effectiveText, 'Hello');
      expect(photoOnly.canPublish, isTrue);
      expect(photoOnly.hasMedia, isTrue);
      expect(preset.canPublish, isTrue);
      expect(preset.effectiveText, 'Preset text');
      expect(miniProgram.canPublish, isTrue);
      expect(miniProgram.miniProgramId, 'payments');
      expect(miniProgram.hasMiniProgram, isTrue);
    });
  });

  group('momentInlineComposerMiniProgramId', () {
    test('prefers preset mini-program ids over active context', () {
      expect(
        momentInlineComposerMiniProgramId(
          activeMiniProgramId: 'taxi',
          presetMiniProgramId: ' Payments ',
        ),
        'payments',
      );
    });

    test('falls back to the active mini-program id', () {
      expect(
        momentInlineComposerMiniProgramId(
          activeMiniProgramId: ' Taxi ',
          presetMiniProgramId: ' ',
        ),
        'taxi',
      );
    });
  });

  group('momentComposerSheetMeta', () {
    test('builds WeChat-style app bar composer sheet chrome', () {
      final chrome = momentComposerSheetChromeMeta();

      expect(chrome.darkRowAlpha, .96);
      expect(chrome.lightRowAlpha, 1);
      expect(chrome.darkDividerAlpha, .44);
      expect(chrome.lightDividerAlpha, .72);
      expect(chrome.dividerHeight, 1);
      expect(chrome.dividerThickness, .5);
      expect(chrome.innerDividerIndent, 52);
      expect(chrome.rowHeight, 52);
      expect(chrome.edgeGap, 16);
      expect(chrome.iconTextGap, 16);
      expect(chrome.iconSize, 21);
      expect(chrome.labelFontSize, 15);
      expect(chrome.actionFontWeight, FontWeight.w500);
      expect(chrome.cancelFontWeight, FontWeight.w600);
      expect(chrome.sectionGap, 8);
    });

    test('builds app bar sheet actions in stable order', () {
      final meta = momentComposerSheetMeta(isArabic: false);

      expect(meta.actions.map((a) => a.kind), <MomentComposerSheetActionKind>[
        MomentComposerSheetActionKind.text,
        MomentComposerSheetActionKind.camera,
        MomentComposerSheetActionKind.album,
      ]);
      expect(meta.actions[0].icon, Icons.edit_note_outlined);
      expect(meta.actions[0].label, 'Text-only Moment');
      expect(meta.actions[0].perfKey, 'moments_sheet_text_only');
      expect(meta.actions[1].label, 'Take Photo');
      expect(meta.actions[2].label, 'Choose from Album');
      expect(meta.cancelLabel, 'Cancel');
    });

    test('localizes app bar sheet labels', () {
      final meta = momentComposerSheetMeta(isArabic: true);

      expect(meta.actions.map((a) => a.label), <String>[
        'لحظة نصية',
        'التقاط صورة',
        'اختيار من الألبوم',
      ]);
      expect(meta.cancelLabel, 'إلغاء');
    });
  });
}
