import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_comment_meta.dart';

void main() {
  group('moments comment meta', () {
    test('builds WeChat-style comment sheet chrome', () {
      final chrome = momentCommentSheetChromeMeta();

      expect(chrome.barrierAlpha, .28);
      expect(chrome.keyboardInsetDuration, const Duration(milliseconds: 180));
      expect(chrome.emptyInitialChildSize, .55);
      expect(chrome.populatedInitialChildSize, .75);
      expect(chrome.minChildSize, .35);
      expect(chrome.maxChildSize, .95);
      expect(chrome.handleTopGap, 8);
      expect(chrome.handleWidth, 36);
      expect(chrome.handleHeight, 4);
      expect(chrome.handleAlpha, .20);
      expect(chrome.handleRadius, 2);
      expect(chrome.handleBottomGap, 6);
      expect(chrome.headerHeight, 44);
      expect(chrome.headerActionInset, 2);
      expect(chrome.headerIconSize, 20);
      expect(chrome.headerActionVisualDensity, VisualDensity.compact);
      expect(chrome.titleFontWeight, FontWeight.w600);
      expect(chrome.countGap, 6);
      expect(chrome.dividerHeight, 1);
      expect(chrome.dividerThickness, .5);
      expect(chrome.emptyPadding, 20);
      expect(chrome.listHorizontalPadding, 16);
      expect(chrome.listVerticalPadding, 10);
      expect(chrome.highlightedTopMargin, 4);
      expect(chrome.commentVerticalPadding, 6);
      expect(chrome.highlightedFillAlpha, .06);
      expect(chrome.highlightedRadius, 8);
      expect(chrome.officialReplyDialogFieldTopGap, 8);
    });

    test('builds WeChat-style comment tile chrome', () {
      final chrome = momentCommentTileChromeMeta();

      expect(chrome.textAlpha, .92);
      expect(chrome.replyConnectorAlpha, .70);
      expect(chrome.authorFontWeight, FontWeight.w600);
      expect(chrome.maxLines, 3);
    });

    test('builds WeChat-style inline comment bar chrome', () {
      final chrome = momentInlineCommentBarChromeMeta();

      expect(chrome.darkFieldFillAlpha, .55);
      expect(chrome.darkDisabledSendAlpha, .45);
      expect(chrome.secondaryTextAlpha, .60);
      expect(chrome.disabledForegroundAlpha, .38);
      expect(chrome.containerHorizontalPadding, 12);
      expect(chrome.containerVerticalPadding, 8);
      expect(chrome.topBorderWidth, .5);
      expect(chrome.replyBottomGap, 6);
      expect(chrome.closeVisualDensity, VisualDensity.compact);
      expect(chrome.closePadding, EdgeInsets.zero);
      expect(chrome.closeMinSize, 28);
      expect(chrome.closeIconSize, 18);
      expect(chrome.closeIconAlpha, .60);
      expect(chrome.baseFontSize, 13);
      expect(chrome.secondaryFontSize, 11);
      expect(chrome.fieldRadius, 6);
      expect(chrome.fieldBorderWidth, .8);
      expect(chrome.fieldMinLines, 1);
      expect(chrome.fieldMaxLines, 4);
      expect(chrome.fieldContentHorizontalPadding, 10);
      expect(chrome.fieldContentVerticalPadding, 10);
      expect(chrome.sendGap, 8);
      expect(chrome.sendHorizontalPadding, 14);
      expect(chrome.sendVerticalPadding, 9);
      expect(chrome.sendMinWidth, 0);
      expect(chrome.sendMinHeight, 34);
      expect(chrome.sendRadius, 4);
      expect(chrome.progressSize, 14);
      expect(chrome.progressStrokeWidth, 2);
      expect(chrome.progressAlpha, .90);
      expect(chrome.sendFontWeight, FontWeight.w600);
    });

    test('builds WeChat-style comment action popover chrome', () {
      final chrome = momentCommentActionPopoverChromeMeta();

      expect(chrome.copyOnlyWidth, 104);
      expect(chrome.copyDeleteWidth, 168);
      expect(chrome.height, 40);
      expect(chrome.arrowWidth, 14);
      expect(chrome.arrowHeight, 10);
      expect(chrome.margin, 8);
      expect(chrome.gap, 10);
      expect(chrome.anchorYOffset, 8);
      expect(chrome.arrowHorizontalInset, 10);
      expect(chrome.backgroundColor, const Color(0xFF2C2C2C));
      expect(chrome.borderRadius, 2);
      expect(chrome.copyTextColor, Colors.white);
      expect(chrome.deleteTextColor, const Color(0xFFFA5151));
      expect(chrome.copyFontWeight, FontWeight.w600);
      expect(chrome.deleteFontWeight, FontWeight.w700);
      expect(chrome.labelFontSize, 13);
      expect(chrome.dividerWidth, 1);
      expect(chrome.dividerHeight, 22);
      expect(chrome.dividerAlpha, .14);
      expect(chrome.slideDx, 14);
      expect(chrome.transitionDuration, const Duration(milliseconds: 150));
    });

    test('builds WeChat-style comment action sheet chrome', () {
      final chrome = momentCommentActionSheetChromeMeta();

      expect(chrome.fallbackHorizontalPadding, 12);
      expect(chrome.fallbackTopPadding, 0);
      expect(chrome.fallbackBottomPadding, 12);
      expect(chrome.fallbackCardRadius, 8);
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
      expect(chrome.deleteTextColor, const Color(0xFFFA5151));
      expect(chrome.sectionGap, 8);
    });

    test('normalizes my pseudonym and localized You labels', () {
      expect(
        normalizeMomentPersonLabel(
          rawName: 'User abc123',
          youLabel: 'You',
          myPseudonym: 'User abc123',
        ),
        'You',
      );
      expect(
        normalizeMomentPersonLabel(
          rawName: 'أنت',
          youLabel: 'You',
        ),
        'You',
      );
    });

    test('builds reply preview metadata', () {
      final meta = momentCommentPreviewMeta(
        authorName: 'User abc123',
        text: ' Nice one ',
        replyToId: 'c_1',
        replyToName: 'Alice',
        youLabel: 'You',
        myPseudonym: 'User abc123',
      );

      expect(meta?.authorLabel, 'You');
      expect(meta?.replyToLabel, 'Alice');
      expect(meta?.text, 'Nice one');
      expect(meta?.hasReply, isTrue);
    });

    test('drops empty comment previews', () {
      final meta = momentCommentPreviewMeta(
        authorName: 'Alice',
        text: '   ',
        replyToId: '',
        replyToName: '',
        youLabel: 'You',
      );

      expect(meta, isNull);
    });
  });
}
