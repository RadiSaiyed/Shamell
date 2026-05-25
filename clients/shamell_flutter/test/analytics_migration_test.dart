import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/analytics_migration.dart';

void main() {
  test('legacy subscription analytics are emitted before cutoff', () {
    final emit = shouldEmitLegacySubscriptionAnalytics(
      nowUtc: DateTime.utc(2026, 6, 30, 23, 59, 59),
    );
    expect(emit, isTrue);
  });

  test('legacy subscription analytics are disabled at cutoff', () {
    final emit = shouldEmitLegacySubscriptionAnalytics(
      nowUtc: DateTime.utc(2026, 7, 1),
    );
    expect(emit, isFalse);
  });

  test('legacy subscription analytics stay disabled after cutoff', () {
    final emit = shouldEmitLegacySubscriptionAnalytics(
      nowUtc: DateTime.utc(2026, 7, 1, 0, 0, 1),
    );
    expect(emit, isFalse);
  });

  test('cutoff constant is pinned to 2026-07-01 UTC', () {
    expect(legacySubscriptionAnalyticsCutoffUtc, DateTime.utc(2026, 7, 1));
  });

  test('nonservice notification mode events dual-write before cutoff', () {
    final events = notificationModeEvents(
      group: AnalyticsOfficialGroup.nonservice,
      mode: AnalyticsNotifMode.summary,
      nowUtc: DateTime.utc(2026, 6, 30, 23, 59, 59),
    );
    expect(events, <String>[
      'official_notifications_nonservice_summary',
      'official_notifications_subscription_summary',
    ]);
  });

  test('nonservice notification mode events only new key at cutoff', () {
    final events = notificationModeEvents(
      group: AnalyticsOfficialGroup.nonservice,
      mode: AnalyticsNotifMode.summary,
      nowUtc: DateTime.utc(2026, 7, 1),
    );
    expect(events, <String>['official_notifications_nonservice_summary']);
  });

  test('service notification mode events never dual-write', () {
    final events = notificationModeEvents(
      group: AnalyticsOfficialGroup.service,
      mode: AnalyticsNotifMode.summary,
      nowUtc: DateTime.utc(2026, 6, 30, 23, 59, 59),
    );
    expect(events, <String>['official_notifications_service_summary']);
  });

  test('nonservice follow-kind events dual-write before cutoff', () {
    final events = followKindEvents(
      group: AnalyticsOfficialGroup.nonservice,
      action: AnalyticsFollowAction.follow,
      nowUtc: DateTime.utc(2026, 6, 30, 23, 59, 59),
    );
    expect(events, <String>[
      'official_follow_kind_nonservice',
      'official_follow_kind_subscription',
    ]);
  });

  test('nonservice follow-kind events only new key at cutoff', () {
    final events = followKindEvents(
      group: AnalyticsOfficialGroup.nonservice,
      action: AnalyticsFollowAction.unfollow,
      nowUtc: DateTime.utc(2026, 7, 1),
    );
    expect(events, <String>['official_unfollow_kind_nonservice']);
  });

  test('service follow-kind events never dual-write', () {
    final events = followKindEvents(
      group: AnalyticsOfficialGroup.service,
      action: AnalyticsFollowAction.follow,
      nowUtc: DateTime.utc(2026, 6, 30, 23, 59, 59),
    );
    expect(events, <String>['official_follow_kind_service']);
  });

  test('service notification mode events are stable', () {
    expect(
      notificationModeEvents(
        group: AnalyticsOfficialGroup.service,
        mode: AnalyticsNotifMode.full,
      ).single,
      'official_notifications_service_full',
    );
    expect(
      notificationModeEvents(
        group: AnalyticsOfficialGroup.service,
        mode: AnalyticsNotifMode.summary,
      ).single,
      'official_notifications_service_summary',
    );
    expect(
      notificationModeEvents(
        group: AnalyticsOfficialGroup.service,
        mode: AnalyticsNotifMode.muted,
      ).single,
      'official_notifications_service_muted',
    );
  });

  test('service follow-kind events are stable', () {
    expect(
      followKindEvents(
        group: AnalyticsOfficialGroup.service,
        action: AnalyticsFollowAction.follow,
      ).single,
      'official_follow_kind_service',
    );
    expect(
      followKindEvents(
        group: AnalyticsOfficialGroup.service,
        action: AnalyticsFollowAction.unfollow,
      ).single,
      'official_unfollow_kind_service',
    );
  });
}
