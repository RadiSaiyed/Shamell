/// Shared cutover policy for legacy analytics keys.
final DateTime legacySubscriptionAnalyticsCutoffUtc = DateTime.utc(2026, 7, 1);

enum AnalyticsNotifMode {
  full,
  summary,
  muted,
}

enum AnalyticsOfficialGroup {
  service,
  nonservice,
}

enum AnalyticsFollowAction {
  follow,
  unfollow,
}

bool shouldEmitLegacySubscriptionAnalytics({DateTime? nowUtc}) {
  final now = (nowUtc ?? DateTime.now()).toUtc();
  return now.isBefore(legacySubscriptionAnalyticsCutoffUtc);
}

const Map<AnalyticsNotifMode, String> _serviceNotificationEventsByMode =
    <AnalyticsNotifMode, String>{
  AnalyticsNotifMode.full: 'official_notifications_service_full',
  AnalyticsNotifMode.summary: 'official_notifications_service_summary',
  AnalyticsNotifMode.muted: 'official_notifications_service_muted',
};

const Map<AnalyticsNotifMode, String> _nonserviceNotificationEventsByMode =
    <AnalyticsNotifMode, String>{
  AnalyticsNotifMode.full: 'official_notifications_nonservice_full',
  AnalyticsNotifMode.summary: 'official_notifications_nonservice_summary',
  AnalyticsNotifMode.muted: 'official_notifications_nonservice_muted',
};

const Map<AnalyticsNotifMode, String>
    _legacySubscriptionNotificationEventsByMode = <AnalyticsNotifMode, String>{
  AnalyticsNotifMode.full: 'official_notifications_subscription_full',
  AnalyticsNotifMode.summary: 'official_notifications_subscription_summary',
  AnalyticsNotifMode.muted: 'official_notifications_subscription_muted',
};

List<String> notificationModeEvents({
  required AnalyticsOfficialGroup group,
  required AnalyticsNotifMode mode,
  DateTime? nowUtc,
}) {
  return switch (group) {
    AnalyticsOfficialGroup.service => <String>[
        _serviceNotificationEventsByMode[mode]!,
      ],
    AnalyticsOfficialGroup.nonservice => _nonserviceNotificationModeEvents(
        mode,
        nowUtc: nowUtc,
      ),
  };
}

List<String> _nonserviceNotificationModeEvents(
  AnalyticsNotifMode mode, {
  DateTime? nowUtc,
}) {
  final next = _nonserviceNotificationEventsByMode[mode]!;
  final legacy = _legacySubscriptionNotificationEventsByMode[mode]!;
  final out = <String>[next];
  if (shouldEmitLegacySubscriptionAnalytics(nowUtc: nowUtc)) {
    out.add(legacy);
  }
  return out;
}

const Map<AnalyticsFollowAction, String> _serviceFollowKindEventsByAction =
    <AnalyticsFollowAction, String>{
  AnalyticsFollowAction.follow: 'official_follow_kind_service',
  AnalyticsFollowAction.unfollow: 'official_unfollow_kind_service',
};

const Map<AnalyticsFollowAction, String> _nonserviceFollowKindEventsByAction =
    <AnalyticsFollowAction, String>{
  AnalyticsFollowAction.follow: 'official_follow_kind_nonservice',
  AnalyticsFollowAction.unfollow: 'official_unfollow_kind_nonservice',
};

const Map<AnalyticsFollowAction, String>
    _legacySubscriptionFollowKindEventsByAction =
    <AnalyticsFollowAction, String>{
  AnalyticsFollowAction.follow: 'official_follow_kind_subscription',
  AnalyticsFollowAction.unfollow: 'official_unfollow_kind_subscription',
};

List<String> followKindEvents({
  required AnalyticsOfficialGroup group,
  required AnalyticsFollowAction action,
  DateTime? nowUtc,
}) {
  return switch (group) {
    AnalyticsOfficialGroup.service => <String>[
        _serviceFollowKindEventsByAction[action]!,
      ],
    AnalyticsOfficialGroup.nonservice => _nonserviceFollowKindEvents(
        action,
        nowUtc: nowUtc,
      ),
  };
}

List<String> _nonserviceFollowKindEvents(
  AnalyticsFollowAction action, {
  DateTime? nowUtc,
}) {
  final next = _nonserviceFollowKindEventsByAction[action]!;
  final legacy = _legacySubscriptionFollowKindEventsByAction[action]!;
  final out = <String>[next];
  if (shouldEmitLegacySubscriptionAnalytics(nowUtc: nowUtc)) {
    out.add(legacy);
  }
  return out;
}
