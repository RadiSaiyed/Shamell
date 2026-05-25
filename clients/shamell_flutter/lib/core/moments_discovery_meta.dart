import 'package:flutter/material.dart';

enum MomentDiscoveryFilterKind {
  all,
  official,
  miniPrograms,
  channels,
  greenPaket,
  recent,
  closeFriends,
}

enum MomentOfficialFilterKind {
  all,
  officialShares,
  officialReplies,
  hotOfficialShares,
}

enum MomentTopicFilterKind {
  all,
  wallet,
}

enum MomentTrendingTopicKind {
  miniProgramShares,
  miniProgramTopic,
  hashtag,
}

class MomentDiscoveryFilterMeta {
  final MomentDiscoveryFilterKind kind;
  final IconData icon;
  final String label;
  final bool selected;
  final String perfKey;

  const MomentDiscoveryFilterMeta({
    required this.kind,
    required this.icon,
    required this.label,
    required this.selected,
    required this.perfKey,
  });
}

class MomentOfficialFilterMeta {
  final MomentOfficialFilterKind kind;
  final IconData icon;
  final String label;
  final bool selected;
  final String perfKey;

  const MomentOfficialFilterMeta({
    required this.kind,
    required this.icon,
    required this.label,
    required this.selected,
    required this.perfKey,
  });
}

class MomentTopicFilterMeta {
  final MomentTopicFilterKind kind;
  final IconData? icon;
  final String label;
  final bool selected;
  final String perfKey;

  const MomentTopicFilterMeta({
    required this.kind,
    required this.icon,
    required this.label,
    required this.selected,
    required this.perfKey,
  });
}

class MomentFilterStripChromeMeta {
  final double borderWidth;
  final double darkBorderAlpha;
  final double lightBorderAlpha;
  final double horizontalPadding;
  final double verticalPadding;
  final double buttonEndSpacing;
  final double buttonHeight;
  final double buttonRadius;
  final double buttonHorizontalPadding;
  final double selectedFillDarkAlpha;
  final double selectedFillLightAlpha;
  final double unselectedTextDarkAlpha;
  final double unselectedTextLightAlpha;
  final double selectedUnderlineWidth;
  final double iconSize;
  final double iconGap;
  final double labelFontSize;
  final FontWeight selectedLabelWeight;
  final FontWeight unselectedLabelWeight;

  const MomentFilterStripChromeMeta({
    required this.borderWidth,
    required this.darkBorderAlpha,
    required this.lightBorderAlpha,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.buttonEndSpacing,
    required this.buttonHeight,
    required this.buttonRadius,
    required this.buttonHorizontalPadding,
    required this.selectedFillDarkAlpha,
    required this.selectedFillLightAlpha,
    required this.unselectedTextDarkAlpha,
    required this.unselectedTextLightAlpha,
    required this.selectedUnderlineWidth,
    required this.iconSize,
    required this.iconGap,
    required this.labelFontSize,
    required this.selectedLabelWeight,
    required this.unselectedLabelWeight,
  });
}

class MomentTrendingTopicMeta {
  final MomentTrendingTopicKind kind;
  final String tag;
  final String label;
  final IconData? icon;
  final String perfKey;

  const MomentTrendingTopicMeta({
    required this.kind,
    required this.tag,
    required this.label,
    required this.icon,
    required this.perfKey,
  });
}

class MomentHashtagMeta {
  final String tag;
  final String label;
  final String perfKey;

  const MomentHashtagMeta({
    required this.tag,
    required this.label,
    required this.perfKey,
  });
}

class MomentOfficialImpactMeta {
  final IconData icon;
  final String label;

  const MomentOfficialImpactMeta({
    required this.icon,
    required this.label,
  });
}

class MomentOfficialImpactStripMeta {
  final String title;
  final IconData icon;
  final String perfKey;
  final double bottomMargin;
  final double horizontalPadding;
  final double verticalPadding;
  final double borderWidth;
  final double darkBorderAlpha;
  final double lightBorderAlpha;
  final double headerIconSize;
  final double headerIconAlpha;
  final double headerIconGap;
  final FontWeight headerTitleWeight;
  final double pillTopGap;
  final double pillSpacing;
  final double pillRunSpacing;
  final double pillHorizontalPadding;
  final double pillVerticalPadding;
  final double pillRadius;
  final double pillBackgroundAlpha;
  final double pillIconSize;
  final double pillIconAlpha;
  final double pillIconGap;
  final double pillFontSize;
  final double pillLabelAlpha;
  final double maxWidthInset;

  const MomentOfficialImpactStripMeta({
    required this.title,
    required this.icon,
    required this.perfKey,
    required this.bottomMargin,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.borderWidth,
    required this.darkBorderAlpha,
    required this.lightBorderAlpha,
    required this.headerIconSize,
    required this.headerIconAlpha,
    required this.headerIconGap,
    required this.headerTitleWeight,
    required this.pillTopGap,
    required this.pillSpacing,
    required this.pillRunSpacing,
    required this.pillHorizontalPadding,
    required this.pillVerticalPadding,
    required this.pillRadius,
    required this.pillBackgroundAlpha,
    required this.pillIconSize,
    required this.pillIconAlpha,
    required this.pillIconGap,
    required this.pillFontSize,
    required this.pillLabelAlpha,
    required this.maxWidthInset,
  });
}

List<MomentDiscoveryFilterMeta> momentDiscoveryFilterMetas({
  required bool isArabic,
  required bool allSelected,
  required bool officialSelected,
  required bool miniProgramsSelected,
  required bool channelsSelected,
  required bool greenPaketSelected,
  required bool recentSelected,
  required bool closeFriendsSelected,
}) {
  return <MomentDiscoveryFilterMeta>[
    MomentDiscoveryFilterMeta(
      kind: MomentDiscoveryFilterKind.all,
      icon: Icons.dynamic_feed_outlined,
      label: isArabic ? 'الكل' : 'All',
      selected: allSelected,
      perfKey: 'moments_discovery_filter_all',
    ),
    MomentDiscoveryFilterMeta(
      kind: MomentDiscoveryFilterKind.official,
      icon: Icons.verified_outlined,
      label: isArabic ? 'رسمي' : 'Official',
      selected: officialSelected,
      perfKey: 'moments_discovery_filter_official',
    ),
    MomentDiscoveryFilterMeta(
      kind: MomentDiscoveryFilterKind.miniPrograms,
      icon: Icons.widgets_outlined,
      label: isArabic ? 'برامج مصغرة' : 'Mini Programs',
      selected: miniProgramsSelected,
      perfKey: 'moments_discovery_filter_miniprograms',
    ),
    MomentDiscoveryFilterMeta(
      kind: MomentDiscoveryFilterKind.channels,
      icon: Icons.play_circle_outline,
      label: isArabic ? 'قنوات' : 'Channels',
      selected: channelsSelected,
      perfKey: 'moments_discovery_filter_channels',
    ),
    MomentDiscoveryFilterMeta(
      kind: MomentDiscoveryFilterKind.greenPaket,
      icon: Icons.card_giftcard_outlined,
      label: 'Green Paket',
      selected: greenPaketSelected,
      perfKey: 'moments_discovery_filter_green_paket',
    ),
    MomentDiscoveryFilterMeta(
      kind: MomentDiscoveryFilterKind.recent,
      icon: Icons.schedule_outlined,
      label: isArabic ? 'آخر ٣ أيام' : 'Last 3 days',
      selected: recentSelected,
      perfKey: 'moments_discovery_filter_recent',
    ),
    MomentDiscoveryFilterMeta(
      kind: MomentDiscoveryFilterKind.closeFriends,
      icon: Icons.star_outline,
      label: isArabic ? 'المقرّبون' : 'Close friends',
      selected: closeFriendsSelected,
      perfKey: 'moments_discovery_filter_close_friends',
    ),
  ];
}

MomentFilterStripChromeMeta momentFilterStripChromeMeta() {
  return const MomentFilterStripChromeMeta(
    borderWidth: .6,
    darkBorderAlpha: .46,
    lightBorderAlpha: .70,
    horizontalPadding: 12,
    verticalPadding: 6,
    buttonEndSpacing: 12,
    buttonHeight: 34,
    buttonRadius: 6,
    buttonHorizontalPadding: 8,
    selectedFillDarkAlpha: .18,
    selectedFillLightAlpha: .08,
    unselectedTextDarkAlpha: .78,
    unselectedTextLightAlpha: .68,
    selectedUnderlineWidth: 2,
    iconSize: 16,
    iconGap: 5,
    labelFontSize: 12,
    selectedLabelWeight: FontWeight.w700,
    unselectedLabelWeight: FontWeight.w500,
  );
}

List<MomentOfficialFilterMeta> momentOfficialFilterMetas({
  required bool isArabic,
  required bool officialOnlySelected,
  required bool officialRepliesSelected,
  required bool hotOfficialsSelected,
}) {
  final allSelected = !officialOnlySelected &&
      !officialRepliesSelected &&
      !hotOfficialsSelected;
  return <MomentOfficialFilterMeta>[
    MomentOfficialFilterMeta(
      kind: MomentOfficialFilterKind.all,
      icon: Icons.dynamic_feed_outlined,
      label: isArabic ? 'الكل' : 'All',
      selected: allSelected,
      perfKey: 'moments_filter_official_only_off',
    ),
    MomentOfficialFilterMeta(
      kind: MomentOfficialFilterKind.officialShares,
      icon: Icons.verified_outlined,
      label: isArabic ? 'المشاركات الرسمية فقط' : 'Only official shares',
      selected: officialOnlySelected,
      perfKey: 'moments_filter_official_only_on',
    ),
    MomentOfficialFilterMeta(
      kind: MomentOfficialFilterKind.officialReplies,
      icon: Icons.mark_chat_read_outlined,
      label: isArabic ? 'منشورات بها رد رسمي' : 'Only with official reply',
      selected: officialRepliesSelected,
      perfKey: 'moments_filter_official_replies_on',
    ),
    MomentOfficialFilterMeta(
      kind: MomentOfficialFilterKind.hotOfficialShares,
      icon: Icons.local_fire_department_outlined,
      label: isArabic ? 'الحسابات الرائجة فقط' : 'Only hot official shares',
      selected: hotOfficialsSelected,
      perfKey: 'moments_filter_hot_official_on',
    ),
  ];
}

List<MomentTopicFilterMeta> momentTopicFilterMetas({
  required bool isArabic,
  required String? topicCategory,
  required bool officialSelected,
  required bool officialRepliesSelected,
}) {
  final walletSelected = (topicCategory ?? '').trim().toLowerCase() == 'wallet';
  final allSelected =
      !walletSelected && !officialSelected && !officialRepliesSelected;
  return <MomentTopicFilterMeta>[
    MomentTopicFilterMeta(
      kind: MomentTopicFilterKind.all,
      icon: Icons.dynamic_feed_outlined,
      label: isArabic ? 'الكل' : 'All',
      selected: allSelected,
      perfKey: 'moments_topic_all',
    ),
    MomentTopicFilterMeta(
      kind: MomentTopicFilterKind.wallet,
      icon: Icons.account_balance_wallet_outlined,
      label: isArabic ? 'المحفظة' : 'Wallet',
      selected: walletSelected,
      perfKey: walletSelected
          ? 'moments_topic_wallet_off'
          : 'moments_topic_wallet_on',
    ),
  ];
}

List<MomentTrendingTopicMeta> momentTrendingTopicMetas({
  required bool isArabic,
  required Iterable<Map<String, dynamic>> rawTopics,
}) {
  final normalizedTags = <String>[];
  final seen = <String>{};
  for (final item in rawTopics) {
    final raw = (item['tag'] ?? '').toString().trim();
    final tag = raw.startsWith('#') ? raw.substring(1).trim() : raw;
    if (tag.isEmpty) continue;
    final key = tag.toLowerCase();
    if (!seen.add(key)) continue;
    normalizedTags.add(tag);
  }
  if (normalizedTags.isEmpty) return const <MomentTrendingTopicMeta>[];

  return <MomentTrendingTopicMeta>[
    MomentTrendingTopicMeta(
      kind: MomentTrendingTopicKind.miniProgramShares,
      tag: '#ShamellMiniApp',
      label: isArabic ? 'من مشاركات البرامج المصغّرة' : 'Mini-program shares',
      icon: Icons.widgets_outlined,
      perfKey: 'moments_topic_mini_program_shares',
    ),
    ...normalizedTags.map((tag) {
      final isMiniProgramTopic = tag.toLowerCase().startsWith('mp_');
      if (isMiniProgramTopic) {
        final core = tag.substring(3).trim();
        return MomentTrendingTopicMeta(
          kind: MomentTrendingTopicKind.miniProgramTopic,
          tag: '#$tag',
          label: isArabic ? 'برنامج مصغّر: $core' : 'Mini-program: $core',
          icon: Icons.widgets_outlined,
          perfKey: 'moments_topic_mini_program',
        );
      }
      return MomentTrendingTopicMeta(
        kind: MomentTrendingTopicKind.hashtag,
        tag: '#$tag',
        label: '#$tag',
        icon: null,
        perfKey: 'moments_topic_hashtag',
      );
    }),
  ];
}

List<MomentHashtagMeta> momentHashtagMetasFromText(String text) {
  final tags = <String>{};
  final re = RegExp(r'#([\w]+)', unicode: true);
  for (final match in re.allMatches(text)) {
    final raw = (match.group(1) ?? '').trim();
    if (raw.isEmpty) continue;
    tags.add(raw);
  }
  final sorted = tags.toList()..sort();
  return sorted
      .map(
        (tag) => MomentHashtagMeta(
          tag: '#$tag',
          label: '#$tag',
          perfKey: 'moments_feed_hashtag_tap',
        ),
      )
      .toList(growable: false);
}

String momentOfficialImpactTitle({required bool isArabic}) {
  return momentOfficialImpactStripMeta(isArabic: isArabic).title;
}

MomentOfficialImpactStripMeta momentOfficialImpactStripMeta({
  required bool isArabic,
}) {
  return MomentOfficialImpactStripMeta(
    title: isArabic
        ? 'أثرك مع الحسابات الرسمية'
        : 'Your impact with official accounts',
    icon: Icons.insights_outlined,
    perfKey: 'moments_official_impact_strip',
    bottomMargin: 8,
    horizontalPadding: 12,
    verticalPadding: 10,
    borderWidth: .6,
    darkBorderAlpha: .46,
    lightBorderAlpha: .72,
    headerIconSize: 18,
    headerIconAlpha: .9,
    headerIconGap: 6,
    headerTitleWeight: FontWeight.w600,
    pillTopGap: 4,
    pillSpacing: 8,
    pillRunSpacing: 4,
    pillHorizontalPadding: 8,
    pillVerticalPadding: 4,
    pillRadius: 999,
    pillBackgroundAlpha: .06,
    pillIconSize: 14,
    pillIconAlpha: .85,
    pillIconGap: 4,
    pillFontSize: 11,
    pillLabelAlpha: .8,
    maxWidthInset: 40,
  );
}

List<MomentOfficialImpactMeta> momentOfficialImpactMetas({
  required bool isArabic,
  required Map<String, dynamic>? stats,
}) {
  final total = _intStat(stats?['total_shares']);
  final service = _intStat(stats?['service_shares']);
  final subscription = _intStat(stats?['subscription_shares']);
  final greenPaket30d = _intStat(stats?['redpacket_shares_30d']);
  final hot = _intStat(stats?['hot_accounts']);
  if (total <= 0 && greenPaket30d <= 0 && hot <= 0) {
    return const <MomentOfficialImpactMeta>[];
  }

  final metas = <MomentOfficialImpactMeta>[];
  if (total > 0) {
    metas.add(
      MomentOfficialImpactMeta(
        icon: Icons.share_outlined,
        label: isArabic
            ? 'مشاركات الحسابات الرسمية: $total'
            : 'Official shares: $total',
      ),
    );
  }
  if (service > 0 || subscription > 0) {
    metas.add(
      MomentOfficialImpactMeta(
        icon: Icons.verified_outlined,
        label: isArabic
            ? 'خدمات: $service · اشتراكات: $subscription'
            : 'Services: $service · Subscriptions: $subscription',
      ),
    );
  }
  if (greenPaket30d > 0) {
    metas.add(
      MomentOfficialImpactMeta(
        icon: Icons.redeem_outlined,
        label: isArabic
            ? 'حزم خضراء في ٣٠ يوماً: $greenPaket30d'
            : 'Green-Paket moments (30d): $greenPaket30d',
      ),
    );
  }
  if (hot > 0) {
    metas.add(
      MomentOfficialImpactMeta(
        icon: Icons.local_fire_department_outlined,
        label: isArabic ? 'حسابات رائجة: $hot' : 'Hot official accounts: $hot',
      ),
    );
  }
  return metas;
}

int _intStat(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}
