import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_social_meta.dart';

void main() {
  group('moments social meta', () {
    test('dedupes likers and puts You first when liked by me', () {
      final labels = momentLikerLabels(
        likedBy: const <String>['Alice', 'me.public', 'Alice', 'Bob'],
        likedByMe: true,
        myPseudonym: 'me.public',
        youLabel: 'You',
      );

      expect(labels, const <String>['You', 'Alice', 'Bob']);
    });

    test('adds overflow labels when the like count is larger than names', () {
      expect(
        momentLikerOverflowLabel(
          likeCount: 5,
          visibleLabelCount: 2,
          isArabic: false,
        ),
        'and 3 others',
      );
      expect(
        momentLikerOverflowLabel(
          likeCount: 2,
          visibleLabelCount: 2,
          isArabic: false,
        ),
        isNull,
      );
    });

    test('formats fallback like counts', () {
      expect(momentLikeCountLabel(likeCount: 1, isArabic: false), '1 like');
      expect(momentLikeCountLabel(likeCount: 3, isArabic: false), '3 likes');
    });

    test('builds WeChat-style social bubble chrome', () {
      final chrome = momentSocialBubbleChromeMeta();

      expect(chrome.topGap, 5);
      expect(chrome.horizontalPadding, 8);
      expect(chrome.verticalPadding, 6);
      expect(chrome.darkBubbleAlpha, .55);
      expect(chrome.darkBorderAlpha, .32);
      expect(chrome.lightBorderAlpha, .64);
      expect(chrome.borderWidth, .5);
      expect(chrome.baseFontSize, 12);
      expect(chrome.baseTextAlpha, .82);
      expect(chrome.authorWeight, FontWeight.w600);
      expect(chrome.unlikedIconAlpha, .65);
      expect(chrome.likeIconSize, 14);
      expect(chrome.likeIconGap, 4);
      expect(chrome.commentMaxLines, 2);
      expect(chrome.commentVerticalPadding, 2);
      expect(chrome.dividerHeight, 12);
      expect(chrome.dividerThickness, .5);
      expect(chrome.dividerAlpha, .10);
      expect(chrome.commentsLinkTopGap, 2);
      expect(chrome.commentLinkAlpha, .60);
      expect(chrome.pointerStart, 18);
      expect(chrome.pointerTop, -4);
      expect(chrome.pointerSize, 8);
      expect(chrome.pointerRotationRadians, closeTo(0.7853981633974483, 0));
    });

    test('summarizes empty social state without rendering a bubble', () {
      final meta = momentSocialSummaryMeta(
        likeCount: 0,
        commentCount: 0,
        loadedPreviewCount: 0,
        likedByMe: false,
      );

      expect(meta.showSocial, isFalse);
      expect(meta.showLikeRow, isFalse);
      expect(meta.showDivider, isFalse);
      expect(meta.visiblePreviewCount, 0);
      expect(meta.likeIcon, Icons.thumb_up_alt_outlined);
    });

    test('summarizes liked Moments with preview comments', () {
      final meta = momentSocialSummaryMeta(
        likeCount: 3,
        commentCount: 5,
        loadedPreviewCount: 4,
        likedByMe: true,
      );

      expect(meta.showSocial, isTrue);
      expect(meta.showLikeRow, isTrue);
      expect(meta.showDivider, isTrue);
      expect(meta.visiblePreviewCount, 2);
      expect(meta.showAllCommentsLink, isTrue);
      expect(meta.showCommentCountOnlyLink, isFalse);
      expect(meta.commentLinkCount, 5);
      expect(meta.likeIcon, Icons.thumb_up_alt);
    });

    test('summarizes comment-count-only state', () {
      final meta = momentSocialSummaryMeta(
        likeCount: 0,
        commentCount: 3,
        loadedPreviewCount: 0,
        likedByMe: false,
      );

      expect(meta.showSocial, isTrue);
      expect(meta.showLikeRow, isFalse);
      expect(meta.showDivider, isFalse);
      expect(meta.visiblePreviewCount, 0);
      expect(meta.showAllCommentsLink, isFalse);
      expect(meta.showCommentCountOnlyLink, isTrue);
      expect(meta.commentLinkCount, 3);
    });

    test('formats comment navigation labels', () {
      expect(
        momentCommentLinkLabel(
          commentCount: 1,
          showAll: false,
          isArabic: false,
        ),
        'View 1 comment',
      );
      expect(
        momentCommentLinkLabel(
          commentCount: 3,
          showAll: true,
          isArabic: false,
        ),
        'View all comments (3)',
      );
      expect(
        momentCommentLinkLabel(
          commentCount: 3,
          showAll: false,
          isArabic: false,
        ),
        'View 3 comments',
      );
    });
  });
}
