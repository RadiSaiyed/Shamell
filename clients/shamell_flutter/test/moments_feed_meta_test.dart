import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_feed_meta.dart';

void main() {
  group('moment post feed labels', () {
    test('normalizes missing author labels', () {
      expect(
        momentAuthorNameLabel(
          authorName: '  ',
          isLocal: true,
          isArabic: false,
        ),
        'You',
      );
      expect(
        momentAuthorNameLabel(
          authorName: '',
          isLocal: false,
          isArabic: false,
        ),
        'User',
      );
      expect(
        momentAuthorNameLabel(
          authorName: 'Mariam',
          isLocal: false,
          isArabic: false,
        ),
        'Mariam',
      );
    });

    test('normalizes avatar image urls and fallback initials', () {
      final remote = momentAvatarMetaFor(
        authorName: ' Mariam ',
        avatarUrl: ' https://cdn.example/avatar.png ',
        isLocal: false,
        isArabic: false,
      );
      final local = momentAvatarMetaFor(
        authorName: '',
        avatarUrl: '',
        isLocal: true,
        isArabic: false,
      );
      final arabicLocal = momentAvatarMetaFor(
        authorName: '',
        avatarUrl: '',
        isLocal: true,
        isArabic: true,
      );
      final anonymous = momentAvatarMetaFor(
        authorName: '',
        avatarUrl: '',
        isLocal: false,
        isArabic: false,
      );

      expect(remote.hasImage, isTrue);
      expect(remote.imageUrl, 'https://cdn.example/avatar.png');
      expect(remote.fallbackText, 'M');
      expect(remote.size, 40);
      expect(remote.radius, 4);
      expect(remote.fallbackDarkAlpha, .30);
      expect(remote.fallbackLightAlpha, .15);
      expect(remote.fallbackFontWeight, FontWeight.w700);
      expect(remote.fallbackFontSize, 14);
      expect(local.fallbackText, 'Y');
      expect(arabicLocal.fallbackText, 'أ');
      expect(anonymous.fallbackText, '?');
    });

    test('builds official and mini-program context labels', () {
      final chrome = momentContextLineChromeMeta();

      expect(chrome.topGap, 2);
      expect(chrome.iconSize, 14);
      expect(chrome.iconGap, 4);
      expect(chrome.fontSize, 11);
      expect(chrome.accentFontWeight, FontWeight.w600);
      expect(chrome.officialReplyIcon, Icons.verified_outlined);
      expect(chrome.greenPaketIcon, Icons.card_giftcard);
      expect(chrome.officialAlpha, .85);
      expect(chrome.miniProgramAlpha, .70);
      expect(chrome.greenPaketIconDarkAlpha, .90);
      expect(chrome.greenPaketIconLightAlpha, .80);
      expect(chrome.greenPaketLabelAlpha, .80);
      expect(chrome.campaignAlpha, .70);
      expect(chrome.bodyBottomGap, 6);
      expect(
        momentOfficialReplyLabel(
          hasOfficialReply: true,
          accountName: 'City Services',
          isArabic: false,
        ),
        'Replied by an official account: City Services',
      );
      expect(
        momentOfficialReplyLabel(
          hasOfficialReply: false,
          accountName: 'City Services',
          isArabic: false,
        ),
        isNull,
      );
      expect(
        momentOfficialShareLabel(
          accountName: 'Transit',
          featured: true,
          isArabic: false,
        ),
        'Shared from Transit · Featured service',
      );
      expect(
        momentMiniProgramShareLabel(title: 'Taxi', isArabic: false),
        'Shared from mini-app: Taxi',
      );
    });

    test('builds Green Paket labels', () {
      expect(momentGreenPaketLabel(isArabic: false), 'Green Paket');
      expect(
        momentGreenPaketCampaignLabel(
          campaignId: 'camp_42',
          isArabic: false,
        ),
        'From Green-Paket campaign: camp_42',
      );
      expect(
        momentGreenPaketCampaignLabel(
          campaignId: ' ',
          isArabic: false,
        ),
        isNull,
      );
    });

    test('normalizes optional location metadata', () {
      final meta = momentLocationMetaFor('  Tunis   Medina  ');

      expect(meta?.label, 'Tunis Medina');
      expect(meta?.icon, Icons.location_on_outlined);
      expect(meta?.perfKey, 'moments_feed_location_tap');
      expect(meta?.radius, 4);
      expect(meta?.verticalPadding, 2);
      expect(meta?.iconSize, 14);
      expect(meta?.iconGap, 3);
      expect(meta?.fontSize, 13);
      expect(meta?.fontWeight, FontWeight.w500);
      expect(meta?.bottomGap, 6);
      expect(momentLocationMetaFor('   '), isNull);
    });

    test('builds WeChat-style feed text and topic link chrome', () {
      final meta = momentFeedTextChromeMeta();

      expect(meta.nameLinkLightColor, const Color(0xFF576B95));
      expect(meta.authorNameWeight, FontWeight.w600);
      expect(meta.bodyFontSize, 14);
      expect(meta.bodyWeight, FontWeight.w400);
      expect(meta.bottomGap, 6);
      expect(meta.topicTopGap, 4);
      expect(meta.topicSpacing, 10);
      expect(meta.topicRunSpacing, 4);
      expect(meta.topicRadius, 4);
      expect(meta.topicVerticalPadding, 2);
      expect(meta.topicFontSize, 12);
      expect(meta.topicWeight, FontWeight.w600);
    });

    test('builds WeChat-style feed content spacing chrome', () {
      final meta = momentFeedContentChromeMeta();

      expect(meta.officialAttachmentBottomGap, 6);
      expect(meta.miniProgramAttachmentBottomGap, 6);
      expect(meta.mediaBottomGap, 8);
    });

    test('builds compact footer metadata for rendered Moments', () {
      final meta = momentFooterMetaFor(
        rawTimestamp: '2026-05-05T14:19:35',
        hasOfficialReply: true,
        postId: 'post_1',
        isArabic: false,
        now: DateTime.parse('2026-05-05T14:20:00'),
      );

      expect(meta.timestampLabel, 'Just now');
      expect(meta.showOfficialReplyIndicator, isTrue);
      expect(meta.canOpenActions, isTrue);
      expect(meta.actionIcon, Icons.more_horiz);
      expect(meta.actionTooltip, 'Post actions');
      expect(meta.actionPerfKey, 'moments_feed_post_actions_open');
      expect(meta.timestampFontSize, 11);
      expect(meta.timestampAlpha, .55);
      expect(meta.replyIndicatorLeftGap, 8);
      expect(meta.replyIndicatorSize, 6);
      expect(meta.replyIndicatorColor, Colors.redAccent);
      expect(meta.actionButtonWidth, 30);
      expect(meta.actionButtonHeight, 22);
      expect(meta.actionButtonRadius, 2);
      expect(meta.actionButtonDarkFillAlpha, .55);
      expect(meta.actionButtonBorderAlpha, .42);
      expect(meta.actionButtonBorderWidth, .5);
      expect(meta.actionIconSize, 18);
      expect(meta.actionIconAlpha, .70);
    });

    test('hides post actions when footer has no post id', () {
      final meta = momentFooterMetaFor(
        rawTimestamp: '',
        hasOfficialReply: false,
        postId: ' ',
        isArabic: true,
      );

      expect(meta.timestampLabel, '');
      expect(meta.showOfficialReplyIndicator, isFalse);
      expect(meta.canOpenActions, isFalse);
      expect(meta.actionTooltip, 'خيارات المنشور');
    });

    test('builds empty feed copy for main and friend timelines', () {
      final main = momentFeedEmptyMetaFor(
        isArabic: false,
        isFriendTimeline: false,
      );
      final friend = momentFeedEmptyMetaFor(
        isArabic: false,
        isFriendTimeline: true,
      );
      final arabic = momentFeedEmptyMetaFor(
        isArabic: true,
        isFriendTimeline: false,
      );

      expect(main.label, 'No moments yet. Share your first moment!');
      expect(main.isFriendTimeline, isFalse);
      expect(friend.label, 'No moments yet.');
      expect(friend.isFriendTimeline, isTrue);
      expect(arabic.label, 'لا توجد لحظات بعد. شارك أول لحظة لك!');
    });

    test('builds WeChat-style feed list chrome', () {
      final chrome = momentFeedListChromeMeta();

      expect(chrome.emptyPadding, 12);
      expect(chrome.emptyTextAlpha, .70);
      expect(chrome.listTopPadding, 4);
      expect(chrome.postHorizontalPadding, 12);
      expect(chrome.postVerticalPadding, 12);
      expect(chrome.postAvatarGap, 10);
      expect(chrome.lightSurfaceColor, Colors.white);
      expect(chrome.separatorHeight, 1);
      expect(chrome.separatorThickness, .5);
      expect(chrome.separatorIndent, 64);
    });

    test('builds composer visibility summary metadata', () {
      final public = momentComposerVisibilityMetaFor(
        visibilityScope: 'public',
        visibilityTag: '',
        visibilityTagMode: 'only',
        isArabic: false,
      );
      final private = momentComposerVisibilityMetaFor(
        visibilityScope: 'only_me',
        visibilityTag: '',
        visibilityTagMode: 'only',
        isArabic: false,
      );
      final friends = momentComposerVisibilityMetaFor(
        visibilityScope: 'friends',
        visibilityTag: '',
        visibilityTagMode: 'only',
        isArabic: false,
      );

      expect(public.key, 'public');
      expect(public.label, 'Public (all users)');
      expect(public.summaryLabel, 'Share to: Public (all users)');
      expect(public.icon, Icons.public);
      expect(private.key, 'only_me');
      expect(private.label, 'Only me');
      expect(private.icon, Icons.lock_outline);
      expect(friends.key, 'friends');
      expect(friends.label, 'Friends only');
      expect(friends.icon, Icons.group_outlined);
    });

    test('builds composer audience summary pill chrome', () {
      final chrome = momentComposerAudienceSummaryPillChromeMeta();

      expect(chrome.horizontalPadding, 10);
      expect(chrome.verticalPadding, 6);
      expect(chrome.radius, 999);
      expect(chrome.darkBackgroundAlpha, .12);
      expect(chrome.lightBackgroundAlpha, .06);
      expect(chrome.borderAlpha, .35);
      expect(chrome.iconSize, 16);
      expect(chrome.iconAlpha, .95);
      expect(chrome.iconGap, 6);
      expect(chrome.fontSize, 11);
      expect(chrome.textAlpha, .90);
    });

    test('builds composer tag audience summaries', () {
      final only = momentComposerVisibilityMetaFor(
        visibilityScope: 'friends',
        visibilityTag: 'Family',
        visibilityTagMode: 'only',
        isArabic: false,
      );
      final except = momentComposerVisibilityMetaFor(
        visibilityScope: 'friends',
        visibilityTag: 'Work',
        visibilityTagMode: 'except',
        isArabic: false,
      );
      final arabic = momentComposerVisibilityMetaFor(
        visibilityScope: 'friends',
        visibilityTag: 'العائلة',
        visibilityTagMode: 'only',
        isArabic: true,
      );

      expect(only.key, 'friends_tag');
      expect(only.label, 'Only Family');
      expect(only.audienceTag, 'Family');
      expect(only.tagMode, 'only');
      expect(except.key, 'friends_except_tag');
      expect(except.label, 'Friends except Work');
      expect(except.audienceTag, 'Work');
      expect(except.tagMode, 'except');
      expect(arabic.summaryLabel, 'المشاركة مع: فقط العائلة');
    });

    test('formats WeChat-style relative timestamps', () {
      final now = DateTime.parse('2026-05-05T14:20:00');

      expect(
        momentTimestampLabel(
          rawTimestamp: '2026-05-05T14:19:35',
          isArabic: false,
          now: now,
        ),
        'Just now',
      );
      expect(
        momentTimestampLabel(
          rawTimestamp: '2026-05-05T14:05:00',
          isArabic: false,
          now: now,
        ),
        '15 min ago',
      );
      expect(
        momentTimestampLabel(
          rawTimestamp: '2026-05-05T11:20:00',
          isArabic: false,
          now: now,
        ),
        '3 h ago',
      );
    });

    test('formats older Moments with compact day labels', () {
      final now = DateTime.parse('2026-05-05T14:20:00');

      expect(
        momentTimestampLabel(
          rawTimestamp: '2026-05-04T22:05:00',
          isArabic: false,
          now: now,
        ),
        'Yesterday 22:05',
      );
      expect(
        momentTimestampLabel(
          rawTimestamp: '2026-04-30T09:05:00',
          isArabic: false,
          now: now,
        ),
        '04-30 09:05',
      );
      expect(
        momentTimestampLabel(
          rawTimestamp: '2025-12-31T09:05:00',
          isArabic: false,
          now: now,
        ),
        '2025-12-31',
      );
      expect(
        momentTimestampLabel(
          rawTimestamp: 'not-a-date',
          isArabic: false,
          now: now,
        ),
        '',
      );
    });

    test('formats Arabic relative timestamps', () {
      final now = DateTime.parse('2026-05-05T14:20:00');

      expect(
        momentTimestampLabel(
          rawTimestamp: '2026-05-05T14:19:35',
          isArabic: true,
          now: now,
        ),
        'الآن',
      );
      expect(
        momentTimestampLabel(
          rawTimestamp: '2026-05-05T14:05:00',
          isArabic: true,
          now: now,
        ),
        'قبل 15 د',
      );
      expect(
        momentTimestampLabel(
          rawTimestamp: '2026-05-04T22:05:00',
          isArabic: true,
          now: now,
        ),
        'أمس 22:05',
      );
    });
  });

  group('momentAudienceMetaFor', () {
    test('builds WeChat-style audience pill chrome', () {
      final chrome = momentAudiencePillChromeMeta();

      expect(chrome.topGap, 3);
      expect(chrome.maxWidth, 260);
      expect(chrome.horizontalPadding, 7);
      expect(chrome.verticalPadding, 3);
      expect(chrome.radius, 999);
      expect(chrome.borderWidth, .5);
      expect(chrome.publicTextAlpha, .58);
      expect(chrome.privateTextAlpha, .90);
      expect(chrome.publicDarkBackgroundAlpha, .24);
      expect(chrome.publicLightBackgroundAlpha, .44);
      expect(chrome.privateDarkBackgroundAlpha, .18);
      expect(chrome.privateLightBackgroundAlpha, .09);
      expect(chrome.publicDarkBorderAlpha, .34);
      expect(chrome.publicLightBorderAlpha, .56);
      expect(chrome.privateDarkBorderAlpha, .28);
      expect(chrome.privateLightBorderAlpha, .18);
      expect(chrome.iconSize, 12);
      expect(chrome.iconGap, 4);
      expect(chrome.fontSize, 10);
      expect(chrome.lineHeight, 1.1);
      expect(chrome.labelWeight, FontWeight.w600);
    });

    test('describes public and private scopes', () {
      final public = momentAudienceMetaFor(
        visibility: 'public',
        audienceTag: '',
        isArabic: false,
      );
      final private = momentAudienceMetaFor(
        visibility: 'only_me',
        audienceTag: '',
        isArabic: false,
      );

      expect(public?.label, 'Public');
      expect(public?.icon, Icons.public);
      expect(public?.actionable, isTrue);
      expect(private?.label, 'Only me');
      expect(private?.icon, Icons.lock_outline);
      expect(private?.actionable, isFalse);
    });

    test('describes tagged audiences without losing the tag value', () {
      final tagged = momentAudienceMetaFor(
        visibility: 'friends_tag',
        audienceTag: 'Family',
        isArabic: false,
      );
      final except = momentAudienceMetaFor(
        visibility: 'friends_except_tag',
        audienceTag: 'Work',
        isArabic: false,
      );

      expect(tagged?.label, 'Friends: Family');
      expect(tagged?.audienceTag, 'Family');
      expect(tagged?.icon, Icons.label_outline);
      expect(except?.label, 'Friends except: Work');
      expect(except?.audienceTag, 'Work');
      expect(except?.icon, Icons.group_remove_outlined);
    });

    test('can omit public metadata for dense surfaces', () {
      final meta = momentAudienceMetaFor(
        visibility: 'public',
        audienceTag: '',
        isArabic: false,
        includePublic: false,
      );

      expect(meta, isNull);
    });
  });
}
