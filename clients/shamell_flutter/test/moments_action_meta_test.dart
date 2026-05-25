import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_action_meta.dart';

void main() {
  group('momentPostQuickActionMetas', () {
    test('builds WeChat-style post action menu chrome', () {
      final chrome = momentPostActionMenuChromeMeta();

      expect(chrome.backgroundColor, const Color(0xFF2C2C2C));
      expect(chrome.height, 40);
      expect(chrome.borderRadius, 2);
      expect(chrome.actionHorizontalPadding, 8);
      expect(chrome.actionVerticalPadding, 10);
      expect(chrome.iconSize, 18);
      expect(chrome.enabledAlpha, .95);
      expect(chrome.disabledAlpha, .45);
      expect(chrome.iconLabelGap, 5);
      expect(chrome.labelFontSize, 12);
      expect(chrome.labelFontWeight, FontWeight.w600);
      expect(chrome.dividerWidth, 1);
      expect(chrome.dividerHeight, 22);
      expect(chrome.dividerAlpha, .14);
    });

    test('builds WeChat-style post action popover chrome', () {
      final chrome = momentPostActionPopoverChromeMeta();

      expect(chrome.minMenuWidth, 252);
      expect(chrome.maxMenuWidth, 360);
      expect(chrome.margin, 8);
      expect(chrome.anchorGap, 10);
      expect(chrome.arrowWidth, 10);
      expect(chrome.arrowHeight, 12);
      expect(chrome.arrowAnchorCenterOffset, 6);
      expect(chrome.arrowTopInset, 8);
      expect(chrome.arrowBottomInset, 14);
      expect(chrome.arrowHorizontalOverlap, 1);
      expect(chrome.arrowColor, const Color(0xFF2C2C2C));
      expect(chrome.slideDx, 18);
      expect(chrome.transitionDuration, const Duration(milliseconds: 160));
    });

    test('builds WeChat-style post action sheet chrome', () {
      final chrome = momentPostActionSheetChromeMeta();

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
      expect(chrome.destructiveColor, const Color(0xFFFA5151));
      expect(chrome.sectionGap, 8);
    });

    test('builds WeChat-style moderation overview sheet chrome', () {
      final chrome = momentModerationOverviewSheetChromeMeta();

      expect(chrome.sheetEdgePadding, 12);
      expect(chrome.viewInsetBottomGap, 12);
      expect(chrome.panelRadius, 16);
      expect(chrome.panelPadding, 12);
      expect(chrome.titleFontWeight, FontWeight.w700);
      expect(chrome.titleBottomGap, 8);
      expect(chrome.emptyBottomPadding, 4);
      expect(chrome.emptyTextAlpha, .70);
      expect(chrome.sectionTitleFontWeight, FontWeight.w700);
      expect(chrome.sectionTitleBottomGap, 4);
      expect(chrome.chipSpacing, 6);
      expect(chrome.chipRunSpacing, 4);
      expect(chrome.chipIconSize, 16);
      expect(chrome.mutedSectionBottomGap, 12);
      expect(chrome.hiddenListMaxHeight, 260);
      expect(chrome.hiddenRowGap, 6);
      expect(chrome.hiddenTileDense, isTrue);
      expect(chrome.hiddenTileContentPadding, EdgeInsets.zero);
      expect(chrome.hiddenPreviewMaxChars, 80);
      expect(chrome.hiddenSubtitleAlpha, .65);
      expect(chrome.hiddenSubtitleFontSize, 11);
    });

    test('builds English Like action when not liked', () {
      final actions = momentPostQuickActionMetas(
        isLiked: false,
        isArabic: false,
      );

      expect(actions.map((a) => a.kind), <MomentPostQuickActionKind>[
        MomentPostQuickActionKind.like,
        MomentPostQuickActionKind.comment,
        MomentPostQuickActionKind.share,
        MomentPostQuickActionKind.save,
      ]);
      expect(actions.first.label, 'Like');
      expect(actions.first.icon, Icons.thumb_up_alt_outlined);
    });

    test('builds Unlike action when already liked', () {
      final actions = momentPostQuickActionMetas(
        isLiked: true,
        isArabic: false,
      );

      expect(actions.first.label, 'Unlike');
      expect(actions.first.icon, Icons.thumb_up_alt);
    });

    test('localizes core labels to Arabic', () {
      final actions = momentPostQuickActionMetas(
        isLiked: false,
        isArabic: true,
      );

      expect(actions.map((a) => a.label), <String>[
        'إعجاب',
        'تعليق',
        'مشاركة',
        'حفظ',
      ]);
    });
  });

  group('momentPostSheetActionMetas', () {
    test('builds owner actions for a local post', () {
      final actions = momentPostSheetActionMetas(
        hasShareText: true,
        canToggleVisibility: true,
        isPrivate: false,
        isLocal: true,
        canHideOrReport: false,
        hasAuthor: true,
        isMutedAuthor: false,
        isArabic: false,
      );

      expect(actions.map((a) => a.kind), <MomentPostSheetActionKind>[
        MomentPostSheetActionKind.copy,
        MomentPostSheetActionKind.share,
        MomentPostSheetActionKind.save,
        MomentPostSheetActionKind.toggleVisibility,
        MomentPostSheetActionKind.delete,
      ]);
      expect(actions[3].label, 'Make visible to me only');
      expect(actions[4].destructive, isTrue);
    });

    test('builds moderation actions for a remote post', () {
      final actions = momentPostSheetActionMetas(
        hasShareText: true,
        canToggleVisibility: false,
        isPrivate: false,
        isLocal: false,
        canHideOrReport: true,
        hasAuthor: true,
        isMutedAuthor: false,
        isArabic: false,
      );

      expect(
          actions.map((a) => a.kind),
          containsAll(<MomentPostSheetActionKind>[
            MomentPostSheetActionKind.hide,
            MomentPostSheetActionKind.report,
            MomentPostSheetActionKind.muteAuthor,
          ]));
      expect(actions.last.label, 'Mute this user in Moments');
    });

    test('uses unmute label for muted authors', () {
      final actions = momentPostSheetActionMetas(
        hasShareText: false,
        canToggleVisibility: false,
        isPrivate: false,
        isLocal: false,
        canHideOrReport: false,
        hasAuthor: true,
        isMutedAuthor: true,
        isArabic: false,
      );

      expect(actions.single.kind, MomentPostSheetActionKind.unmuteAuthor);
      expect(actions.single.icon, Icons.volume_up_outlined);
      expect(actions.single.label, 'Unmute this user in Moments');
    });
  });
}
