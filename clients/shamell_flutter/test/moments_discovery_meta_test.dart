import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_discovery_meta.dart';

void main() {
  group('momentDiscoveryFilterMetas', () {
    test('builds filters in stable WeChat-style order', () {
      final filters = momentDiscoveryFilterMetas(
        isArabic: false,
        allSelected: true,
        officialSelected: false,
        miniProgramsSelected: false,
        channelsSelected: false,
        greenPaketSelected: false,
        recentSelected: false,
        closeFriendsSelected: false,
      );

      expect(filters.map((f) => f.kind), <MomentDiscoveryFilterKind>[
        MomentDiscoveryFilterKind.all,
        MomentDiscoveryFilterKind.official,
        MomentDiscoveryFilterKind.miniPrograms,
        MomentDiscoveryFilterKind.channels,
        MomentDiscoveryFilterKind.greenPaket,
        MomentDiscoveryFilterKind.recent,
        MomentDiscoveryFilterKind.closeFriends,
      ]);
      expect(filters.first.label, 'All');
      expect(filters.first.icon, Icons.dynamic_feed_outlined);
      expect(filters.first.selected, isTrue);
    });

    test('marks selected filters and keeps perf keys stable', () {
      final filters = momentDiscoveryFilterMetas(
        isArabic: false,
        allSelected: false,
        officialSelected: true,
        miniProgramsSelected: true,
        channelsSelected: false,
        greenPaketSelected: true,
        recentSelected: false,
        closeFriendsSelected: true,
      );

      expect(
        filters.where((f) => f.selected).map((f) => f.kind),
        <MomentDiscoveryFilterKind>[
          MomentDiscoveryFilterKind.official,
          MomentDiscoveryFilterKind.miniPrograms,
          MomentDiscoveryFilterKind.greenPaket,
          MomentDiscoveryFilterKind.closeFriends,
        ],
      );
      expect(
        filters
            .firstWhere((f) => f.kind == MomentDiscoveryFilterKind.greenPaket)
            .perfKey,
        'moments_discovery_filter_green_paket',
      );
    });

    test('localizes Arabic labels', () {
      final filters = momentDiscoveryFilterMetas(
        isArabic: true,
        allSelected: false,
        officialSelected: false,
        miniProgramsSelected: false,
        channelsSelected: false,
        greenPaketSelected: false,
        recentSelected: true,
        closeFriendsSelected: false,
      );

      expect(filters[0].label, 'الكل');
      expect(filters[1].label, 'رسمي');
      expect(filters[5].label, 'آخر ٣ أيام');
      expect(filters[5].selected, isTrue);
    });
  });

  group('momentOfficialFilterMetas', () {
    test('builds shared WeChat-style filter strip chrome', () {
      final chrome = momentFilterStripChromeMeta();

      expect(chrome.borderWidth, .6);
      expect(chrome.darkBorderAlpha, .46);
      expect(chrome.lightBorderAlpha, .70);
      expect(chrome.horizontalPadding, 12);
      expect(chrome.verticalPadding, 6);
      expect(chrome.buttonEndSpacing, 12);
      expect(chrome.buttonHeight, 34);
      expect(chrome.buttonRadius, 6);
      expect(chrome.buttonHorizontalPadding, 8);
      expect(chrome.selectedFillDarkAlpha, .18);
      expect(chrome.selectedFillLightAlpha, .08);
      expect(chrome.unselectedTextDarkAlpha, .78);
      expect(chrome.unselectedTextLightAlpha, .68);
      expect(chrome.selectedUnderlineWidth, 2);
      expect(chrome.iconSize, 16);
      expect(chrome.iconGap, 5);
      expect(chrome.labelFontSize, 12);
      expect(chrome.selectedLabelWeight, FontWeight.w700);
      expect(chrome.unselectedLabelWeight, FontWeight.w500);
    });

    test('builds official subfilters with stable perf keys', () {
      final filters = momentOfficialFilterMetas(
        isArabic: false,
        officialOnlySelected: false,
        officialRepliesSelected: true,
        hotOfficialsSelected: false,
      );

      expect(filters.map((f) => f.kind), <MomentOfficialFilterKind>[
        MomentOfficialFilterKind.all,
        MomentOfficialFilterKind.officialShares,
        MomentOfficialFilterKind.officialReplies,
        MomentOfficialFilterKind.hotOfficialShares,
      ]);
      expect(filters[2].selected, isTrue);
      expect(filters[2].icon, Icons.mark_chat_read_outlined);
      expect(filters[2].perfKey, 'moments_filter_official_replies_on');
    });

    test('selects All when no official subfilter is active', () {
      final filters = momentOfficialFilterMetas(
        isArabic: false,
        officialOnlySelected: false,
        officialRepliesSelected: false,
        hotOfficialsSelected: false,
      );

      expect(filters.first.kind, MomentOfficialFilterKind.all);
      expect(filters.first.selected, isTrue);
      expect(filters.first.label, 'All');
    });
  });

  group('momentTopicFilterMetas', () {
    test('builds wallet topic toggle metadata', () {
      final filters = momentTopicFilterMetas(
        isArabic: false,
        topicCategory: null,
        officialSelected: false,
        officialRepliesSelected: false,
      );

      expect(filters.map((f) => f.kind), <MomentTopicFilterKind>[
        MomentTopicFilterKind.all,
        MomentTopicFilterKind.wallet,
      ]);
      expect(filters.first.selected, isTrue);
      expect(filters[1].label, 'Wallet');
      expect(filters[1].perfKey, 'moments_topic_wallet_on');
    });

    test('uses wallet off perf key when selected', () {
      final filters = momentTopicFilterMetas(
        isArabic: false,
        topicCategory: 'wallet',
        officialSelected: true,
        officialRepliesSelected: false,
      );

      expect(filters.first.selected, isFalse);
      expect(filters[1].selected, isTrue);
      expect(filters[1].perfKey, 'moments_topic_wallet_off');
    });
  });

  group('momentTrendingTopicMetas', () {
    test('returns no chips until backend topics are available', () {
      final topics = momentTrendingTopicMetas(
        isArabic: false,
        rawTopics: const <Map<String, dynamic>>[],
      );

      expect(topics, isEmpty);
    });

    test('builds mini-program and hashtag chips with stable actions', () {
      final topics = momentTrendingTopicMetas(
        isArabic: false,
        rawTopics: const <Map<String, dynamic>>[
          {'tag': 'mp_wallet'},
          {'tag': '#Food'},
          {'tag': 'food'},
          {'tag': '  '},
        ],
      );

      expect(topics.map((t) => t.kind), <MomentTrendingTopicKind>[
        MomentTrendingTopicKind.miniProgramShares,
        MomentTrendingTopicKind.miniProgramTopic,
        MomentTrendingTopicKind.hashtag,
      ]);
      expect(topics[0].tag, '#ShamellMiniApp');
      expect(topics[0].icon, Icons.widgets_outlined);
      expect(topics[1].label, 'Mini-program: wallet');
      expect(topics[1].tag, '#mp_wallet');
      expect(topics[1].perfKey, 'moments_topic_mini_program');
      expect(topics[2].label, '#Food');
    });
  });

  group('momentHashtagMetasFromText', () {
    test('extracts sorted unique topic links from post text', () {
      final tags = momentHashtagMetasFromText(
        'Launch #Wallet and #Food with #Wallet today',
      );

      expect(tags.map((t) => t.label), <String>['#Food', '#Wallet']);
      expect(tags.map((t) => t.tag), <String>['#Food', '#Wallet']);
      expect(tags.map((t) => t.perfKey).toSet(),
          <String>{'moments_feed_hashtag_tap'});
    });

    test('ignores empty text without emitting feed topic links', () {
      expect(momentHashtagMetasFromText('no topics here'), isEmpty);
    });
  });

  group('momentOfficialImpactMetas', () {
    test('builds official impact strip chrome metadata', () {
      final meta = momentOfficialImpactStripMeta(isArabic: false);

      expect(meta.title, 'Your impact with official accounts');
      expect(meta.icon, Icons.insights_outlined);
      expect(meta.perfKey, 'moments_official_impact_strip');
      expect(meta.bottomMargin, 8);
      expect(meta.horizontalPadding, 12);
      expect(meta.verticalPadding, 10);
      expect(meta.borderWidth, .6);
      expect(meta.darkBorderAlpha, .46);
      expect(meta.lightBorderAlpha, .72);
      expect(meta.headerIconSize, 18);
      expect(meta.headerIconAlpha, .9);
      expect(meta.headerIconGap, 6);
      expect(meta.headerTitleWeight, FontWeight.w600);
      expect(meta.pillTopGap, 4);
      expect(meta.pillSpacing, 8);
      expect(meta.pillRunSpacing, 4);
      expect(meta.pillHorizontalPadding, 8);
      expect(meta.pillVerticalPadding, 4);
      expect(meta.pillRadius, 999);
      expect(meta.pillBackgroundAlpha, .06);
      expect(meta.pillIconSize, 14);
      expect(meta.pillIconAlpha, .85);
      expect(meta.pillIconGap, 4);
      expect(meta.pillFontSize, 11);
      expect(meta.pillLabelAlpha, .8);
      expect(meta.maxWidthInset, 40);
    });

    test('localizes official impact strip title', () {
      expect(momentOfficialImpactTitle(isArabic: true),
          'أثرك مع الحسابات الرسمية');
      expect(
        momentOfficialImpactStripMeta(isArabic: true).title,
        'أثرك مع الحسابات الرسمية',
      );
    });

    test('hides impact strip when no meaningful stats exist', () {
      final metas = momentOfficialImpactMetas(
        isArabic: false,
        stats: const <String, dynamic>{
          'total_shares': 0,
          'redpacket_shares_30d': 0,
          'hot_accounts': 0,
        },
      );

      expect(metas, isEmpty);
    });

    test('builds official impact pills and parses string counts', () {
      final metas = momentOfficialImpactMetas(
        isArabic: false,
        stats: const <String, dynamic>{
          'total_shares': '12',
          'service_shares': 7,
          'subscription_shares': '5',
          'redpacket_shares_30d': 3,
          'hot_accounts': '2',
        },
      );

      expect(momentOfficialImpactTitle(isArabic: false),
          'Your impact with official accounts');
      expect(metas.map((m) => m.label), <String>[
        'Official shares: 12',
        'Services: 7 · Subscriptions: 5',
        'Green-Paket moments (30d): 3',
        'Hot official accounts: 2',
      ]);
      expect(metas.map((m) => m.icon), <IconData>[
        Icons.share_outlined,
        Icons.verified_outlined,
        Icons.redeem_outlined,
        Icons.local_fire_department_outlined,
      ]);
    });

    test('does not show a zero official shares pill', () {
      final metas = momentOfficialImpactMetas(
        isArabic: false,
        stats: const <String, dynamic>{
          'total_shares': 0,
          'hot_accounts': 2,
        },
      );

      expect(metas.map((m) => m.label), <String>[
        'Hot official accounts: 2',
      ]);
    });
  });
}
