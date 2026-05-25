import 'package:flutter/material.dart';

class MomentSocialSummaryMeta {
  final bool showSocial;
  final bool showLikeRow;
  final bool showDivider;
  final bool showAllCommentsLink;
  final bool showCommentCountOnlyLink;
  final int visiblePreviewCount;
  final int commentLinkCount;
  final IconData likeIcon;

  const MomentSocialSummaryMeta({
    required this.showSocial,
    required this.showLikeRow,
    required this.showDivider,
    required this.showAllCommentsLink,
    required this.showCommentCountOnlyLink,
    required this.visiblePreviewCount,
    required this.commentLinkCount,
    required this.likeIcon,
  });
}

class MomentSocialBubbleChromeMeta {
  final double topGap;
  final double horizontalPadding;
  final double verticalPadding;
  final double darkBubbleAlpha;
  final double darkBorderAlpha;
  final double lightBorderAlpha;
  final double borderWidth;
  final double baseFontSize;
  final double baseTextAlpha;
  final FontWeight authorWeight;
  final double unlikedIconAlpha;
  final double likeIconSize;
  final double likeIconGap;
  final int commentMaxLines;
  final double commentVerticalPadding;
  final double dividerHeight;
  final double dividerThickness;
  final double dividerAlpha;
  final double commentsLinkTopGap;
  final double commentLinkAlpha;
  final double pointerStart;
  final double pointerTop;
  final double pointerSize;
  final double pointerRotationRadians;

  const MomentSocialBubbleChromeMeta({
    required this.topGap,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.darkBubbleAlpha,
    required this.darkBorderAlpha,
    required this.lightBorderAlpha,
    required this.borderWidth,
    required this.baseFontSize,
    required this.baseTextAlpha,
    required this.authorWeight,
    required this.unlikedIconAlpha,
    required this.likeIconSize,
    required this.likeIconGap,
    required this.commentMaxLines,
    required this.commentVerticalPadding,
    required this.dividerHeight,
    required this.dividerThickness,
    required this.dividerAlpha,
    required this.commentsLinkTopGap,
    required this.commentLinkAlpha,
    required this.pointerStart,
    required this.pointerTop,
    required this.pointerSize,
    required this.pointerRotationRadians,
  });
}

MomentSocialSummaryMeta momentSocialSummaryMeta({
  required int likeCount,
  required int commentCount,
  required int loadedPreviewCount,
  required bool likedByMe,
  int previewLimit = 2,
}) {
  final cleanLikes = likeCount < 0 ? 0 : likeCount;
  final cleanComments = commentCount < 0 ? 0 : commentCount;
  final cleanPreview = loadedPreviewCount < 0 ? 0 : loadedPreviewCount;
  final cleanLimit = previewLimit <= 0 ? 0 : previewLimit;
  final visiblePreview = cleanPreview < cleanLimit ? cleanPreview : cleanLimit;
  final effectiveCommentCount =
      cleanComments > cleanPreview ? cleanComments : cleanPreview;
  final showLikeRow = cleanLikes > 0;
  final showSocial =
      showLikeRow || effectiveCommentCount > 0 || cleanPreview > 0;

  return MomentSocialSummaryMeta(
    showSocial: showSocial,
    showLikeRow: showLikeRow,
    showDivider: showLikeRow && effectiveCommentCount > 0,
    showAllCommentsLink:
        visiblePreview > 0 && effectiveCommentCount > visiblePreview,
    showCommentCountOnlyLink: visiblePreview == 0 && effectiveCommentCount > 0,
    visiblePreviewCount: visiblePreview,
    commentLinkCount: effectiveCommentCount,
    likeIcon: likedByMe ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
  );
}

MomentSocialBubbleChromeMeta momentSocialBubbleChromeMeta() {
  return const MomentSocialBubbleChromeMeta(
    topGap: 5,
    horizontalPadding: 8,
    verticalPadding: 6,
    darkBubbleAlpha: .55,
    darkBorderAlpha: .32,
    lightBorderAlpha: .64,
    borderWidth: .5,
    baseFontSize: 12,
    baseTextAlpha: .82,
    authorWeight: FontWeight.w600,
    unlikedIconAlpha: .65,
    likeIconSize: 14,
    likeIconGap: 4,
    commentMaxLines: 2,
    commentVerticalPadding: 2,
    dividerHeight: 12,
    dividerThickness: .5,
    dividerAlpha: .10,
    commentsLinkTopGap: 2,
    commentLinkAlpha: .60,
    pointerStart: 18,
    pointerTop: -4,
    pointerSize: 8,
    pointerRotationRadians: 0.7853981633974483,
  );
}

List<String> momentLikerLabels({
  required Iterable<String> likedBy,
  required bool likedByMe,
  required String myPseudonym,
  required String youLabel,
}) {
  final cleanYou = youLabel.trim().isEmpty ? 'You' : youLabel.trim();
  final pseudo = myPseudonym.trim();
  final labels = <String>[];
  final seen = <String>{};

  for (final raw in likedBy) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    final label = pseudo.isNotEmpty && value == pseudo ? cleanYou : value;
    if (seen.add(label)) labels.add(label);
  }

  if (likedByMe) {
    labels.removeWhere((label) => label == cleanYou);
    labels.insert(0, cleanYou);
  }

  return labels;
}

String? momentLikerOverflowLabel({
  required int likeCount,
  required int visibleLabelCount,
  required bool isArabic,
}) {
  final remaining = likeCount - visibleLabelCount;
  if (remaining <= 0) return null;
  if (isArabic) {
    return remaining == 1 ? 'وآخر' : 'و$remaining آخرون';
  }
  return remaining == 1 ? 'and 1 other' : 'and $remaining others';
}

String momentLikeCountLabel({
  required int likeCount,
  required bool isArabic,
}) {
  if (isArabic) return '$likeCount إعجاب';
  return likeCount == 1 ? '1 like' : '$likeCount likes';
}

String momentCommentLinkLabel({
  required int commentCount,
  required bool showAll,
  required bool isArabic,
}) {
  if (commentCount <= 0) return '';
  if (isArabic) {
    return showAll
        ? 'عرض كل التعليقات ($commentCount)'
        : 'عرض $commentCount تعليق';
  }
  if (commentCount == 1) return 'View 1 comment';
  return showAll
      ? 'View all comments ($commentCount)'
      : 'View $commentCount comments';
}
