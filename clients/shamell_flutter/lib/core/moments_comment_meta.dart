import 'package:flutter/material.dart';

class MomentCommentPreviewMeta {
  final String authorLabel;
  final String? replyToLabel;
  final String text;

  const MomentCommentPreviewMeta({
    required this.authorLabel,
    required this.replyToLabel,
    required this.text,
  });

  bool get hasReply => (replyToLabel ?? '').trim().isNotEmpty;
}

class MomentInlineCommentBarChromeMeta {
  final double darkFieldFillAlpha;
  final double darkDisabledSendAlpha;
  final double secondaryTextAlpha;
  final double disabledForegroundAlpha;
  final double containerHorizontalPadding;
  final double containerVerticalPadding;
  final double topBorderWidth;
  final double replyBottomGap;
  final VisualDensity closeVisualDensity;
  final EdgeInsets closePadding;
  final double closeMinSize;
  final double closeIconSize;
  final double closeIconAlpha;
  final double baseFontSize;
  final double secondaryFontSize;
  final double fieldRadius;
  final double fieldBorderWidth;
  final int fieldMinLines;
  final int fieldMaxLines;
  final double fieldContentHorizontalPadding;
  final double fieldContentVerticalPadding;
  final double sendGap;
  final double sendHorizontalPadding;
  final double sendVerticalPadding;
  final double sendMinWidth;
  final double sendMinHeight;
  final double sendRadius;
  final double progressSize;
  final double progressStrokeWidth;
  final double progressAlpha;
  final FontWeight sendFontWeight;

  const MomentInlineCommentBarChromeMeta({
    required this.darkFieldFillAlpha,
    required this.darkDisabledSendAlpha,
    required this.secondaryTextAlpha,
    required this.disabledForegroundAlpha,
    required this.containerHorizontalPadding,
    required this.containerVerticalPadding,
    required this.topBorderWidth,
    required this.replyBottomGap,
    required this.closeVisualDensity,
    required this.closePadding,
    required this.closeMinSize,
    required this.closeIconSize,
    required this.closeIconAlpha,
    required this.baseFontSize,
    required this.secondaryFontSize,
    required this.fieldRadius,
    required this.fieldBorderWidth,
    required this.fieldMinLines,
    required this.fieldMaxLines,
    required this.fieldContentHorizontalPadding,
    required this.fieldContentVerticalPadding,
    required this.sendGap,
    required this.sendHorizontalPadding,
    required this.sendVerticalPadding,
    required this.sendMinWidth,
    required this.sendMinHeight,
    required this.sendRadius,
    required this.progressSize,
    required this.progressStrokeWidth,
    required this.progressAlpha,
    required this.sendFontWeight,
  });
}

class MomentCommentSheetChromeMeta {
  final double barrierAlpha;
  final Duration keyboardInsetDuration;
  final double emptyInitialChildSize;
  final double populatedInitialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final double handleTopGap;
  final double handleWidth;
  final double handleHeight;
  final double handleAlpha;
  final double handleRadius;
  final double handleBottomGap;
  final double headerHeight;
  final double headerActionInset;
  final double headerIconSize;
  final VisualDensity headerActionVisualDensity;
  final FontWeight titleFontWeight;
  final double countGap;
  final double dividerHeight;
  final double dividerThickness;
  final double emptyPadding;
  final double listHorizontalPadding;
  final double listVerticalPadding;
  final double highlightedTopMargin;
  final double commentVerticalPadding;
  final double highlightedFillAlpha;
  final double highlightedRadius;
  final double officialReplyDialogFieldTopGap;

  const MomentCommentSheetChromeMeta({
    required this.barrierAlpha,
    required this.keyboardInsetDuration,
    required this.emptyInitialChildSize,
    required this.populatedInitialChildSize,
    required this.minChildSize,
    required this.maxChildSize,
    required this.handleTopGap,
    required this.handleWidth,
    required this.handleHeight,
    required this.handleAlpha,
    required this.handleRadius,
    required this.handleBottomGap,
    required this.headerHeight,
    required this.headerActionInset,
    required this.headerIconSize,
    required this.headerActionVisualDensity,
    required this.titleFontWeight,
    required this.countGap,
    required this.dividerHeight,
    required this.dividerThickness,
    required this.emptyPadding,
    required this.listHorizontalPadding,
    required this.listVerticalPadding,
    required this.highlightedTopMargin,
    required this.commentVerticalPadding,
    required this.highlightedFillAlpha,
    required this.highlightedRadius,
    required this.officialReplyDialogFieldTopGap,
  });
}

class MomentCommentTileChromeMeta {
  final double textAlpha;
  final double replyConnectorAlpha;
  final FontWeight authorFontWeight;
  final int maxLines;

  const MomentCommentTileChromeMeta({
    required this.textAlpha,
    required this.replyConnectorAlpha,
    required this.authorFontWeight,
    required this.maxLines,
  });
}

class MomentCommentActionPopoverChromeMeta {
  final double copyOnlyWidth;
  final double copyDeleteWidth;
  final double height;
  final double arrowWidth;
  final double arrowHeight;
  final double margin;
  final double gap;
  final double anchorYOffset;
  final double arrowHorizontalInset;
  final Color backgroundColor;
  final double borderRadius;
  final Color copyTextColor;
  final Color deleteTextColor;
  final FontWeight copyFontWeight;
  final FontWeight deleteFontWeight;
  final double labelFontSize;
  final double dividerWidth;
  final double dividerHeight;
  final double dividerAlpha;
  final double slideDx;
  final Duration transitionDuration;

  const MomentCommentActionPopoverChromeMeta({
    required this.copyOnlyWidth,
    required this.copyDeleteWidth,
    required this.height,
    required this.arrowWidth,
    required this.arrowHeight,
    required this.margin,
    required this.gap,
    required this.anchorYOffset,
    required this.arrowHorizontalInset,
    required this.backgroundColor,
    required this.borderRadius,
    required this.copyTextColor,
    required this.deleteTextColor,
    required this.copyFontWeight,
    required this.deleteFontWeight,
    required this.labelFontSize,
    required this.dividerWidth,
    required this.dividerHeight,
    required this.dividerAlpha,
    required this.slideDx,
    required this.transitionDuration,
  });
}

class MomentCommentActionSheetChromeMeta {
  final double fallbackHorizontalPadding;
  final double fallbackTopPadding;
  final double fallbackBottomPadding;
  final double fallbackCardRadius;
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
  final Color deleteTextColor;
  final double sectionGap;

  const MomentCommentActionSheetChromeMeta({
    required this.fallbackHorizontalPadding,
    required this.fallbackTopPadding,
    required this.fallbackBottomPadding,
    required this.fallbackCardRadius,
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
    required this.deleteTextColor,
    required this.sectionGap,
  });
}

MomentCommentSheetChromeMeta momentCommentSheetChromeMeta() {
  return const MomentCommentSheetChromeMeta(
    barrierAlpha: .28,
    keyboardInsetDuration: Duration(milliseconds: 180),
    emptyInitialChildSize: .55,
    populatedInitialChildSize: .75,
    minChildSize: .35,
    maxChildSize: .95,
    handleTopGap: 8,
    handleWidth: 36,
    handleHeight: 4,
    handleAlpha: .20,
    handleRadius: 2,
    handleBottomGap: 6,
    headerHeight: 44,
    headerActionInset: 2,
    headerIconSize: 20,
    headerActionVisualDensity: VisualDensity.compact,
    titleFontWeight: FontWeight.w600,
    countGap: 6,
    dividerHeight: 1,
    dividerThickness: .5,
    emptyPadding: 20,
    listHorizontalPadding: 16,
    listVerticalPadding: 10,
    highlightedTopMargin: 4,
    commentVerticalPadding: 6,
    highlightedFillAlpha: .06,
    highlightedRadius: 8,
    officialReplyDialogFieldTopGap: 8,
  );
}

MomentCommentTileChromeMeta momentCommentTileChromeMeta() {
  return const MomentCommentTileChromeMeta(
    textAlpha: .92,
    replyConnectorAlpha: .70,
    authorFontWeight: FontWeight.w600,
    maxLines: 3,
  );
}

MomentCommentActionSheetChromeMeta momentCommentActionSheetChromeMeta() {
  return const MomentCommentActionSheetChromeMeta(
    fallbackHorizontalPadding: 12,
    fallbackTopPadding: 0,
    fallbackBottomPadding: 12,
    fallbackCardRadius: 8,
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
    deleteTextColor: Color(0xFFFA5151),
    sectionGap: 8,
  );
}

MomentInlineCommentBarChromeMeta momentInlineCommentBarChromeMeta() {
  return const MomentInlineCommentBarChromeMeta(
    darkFieldFillAlpha: .55,
    darkDisabledSendAlpha: .45,
    secondaryTextAlpha: .60,
    disabledForegroundAlpha: .38,
    containerHorizontalPadding: 12,
    containerVerticalPadding: 8,
    topBorderWidth: .5,
    replyBottomGap: 6,
    closeVisualDensity: VisualDensity.compact,
    closePadding: EdgeInsets.zero,
    closeMinSize: 28,
    closeIconSize: 18,
    closeIconAlpha: .60,
    baseFontSize: 13,
    secondaryFontSize: 11,
    fieldRadius: 6,
    fieldBorderWidth: .8,
    fieldMinLines: 1,
    fieldMaxLines: 4,
    fieldContentHorizontalPadding: 10,
    fieldContentVerticalPadding: 10,
    sendGap: 8,
    sendHorizontalPadding: 14,
    sendVerticalPadding: 9,
    sendMinWidth: 0,
    sendMinHeight: 34,
    sendRadius: 4,
    progressSize: 14,
    progressStrokeWidth: 2,
    progressAlpha: .90,
    sendFontWeight: FontWeight.w600,
  );
}

MomentCommentActionPopoverChromeMeta momentCommentActionPopoverChromeMeta() {
  return const MomentCommentActionPopoverChromeMeta(
    copyOnlyWidth: 104,
    copyDeleteWidth: 168,
    height: 40,
    arrowWidth: 14,
    arrowHeight: 10,
    margin: 8,
    gap: 10,
    anchorYOffset: 8,
    arrowHorizontalInset: 10,
    backgroundColor: Color(0xFF2C2C2C),
    borderRadius: 2,
    copyTextColor: Colors.white,
    deleteTextColor: Color(0xFFFA5151),
    copyFontWeight: FontWeight.w600,
    deleteFontWeight: FontWeight.w700,
    labelFontSize: 13,
    dividerWidth: 1,
    dividerHeight: 22,
    dividerAlpha: .14,
    slideDx: 14,
    transitionDuration: Duration(milliseconds: 150),
  );
}

String normalizeMomentPersonLabel({
  required String rawName,
  required String youLabel,
  String? myPseudonym,
}) {
  final you = youLabel.trim().isEmpty ? 'You' : youLabel.trim();
  final raw = rawName.trim();
  if (raw.isEmpty || raw == 'You' || raw == 'أنت') return you;
  if ((myPseudonym ?? '').trim().isNotEmpty &&
      raw == (myPseudonym ?? '').trim()) {
    return you;
  }
  return raw;
}

bool isMomentPersonMe({
  required String rawName,
  required String youLabel,
  String? myPseudonym,
}) {
  final you = youLabel.trim();
  final raw = rawName.trim();
  if (raw.isEmpty) return true;
  if (raw == you || raw == 'You' || raw == 'أنت') return true;
  return (myPseudonym ?? '').trim().isNotEmpty &&
      raw == (myPseudonym ?? '').trim();
}

MomentCommentPreviewMeta? momentCommentPreviewMeta({
  required String authorName,
  required String text,
  required String replyToId,
  required String replyToName,
  required String youLabel,
  String? myPseudonym,
}) {
  final cleanText = text.trim();
  if (cleanText.isEmpty) return null;
  final author = normalizeMomentPersonLabel(
    rawName: authorName,
    youLabel: youLabel,
    myPseudonym: myPseudonym,
  );
  final cleanReplyId = replyToId.trim();
  final reply = cleanReplyId.isEmpty
      ? null
      : normalizeMomentPersonLabel(
          rawName: replyToName,
          youLabel: youLabel,
          myPseudonym: myPseudonym,
        );

  return MomentCommentPreviewMeta(
    authorLabel: author,
    replyToLabel: (reply ?? '').trim().isEmpty ? null : reply,
    text: cleanText,
  );
}
