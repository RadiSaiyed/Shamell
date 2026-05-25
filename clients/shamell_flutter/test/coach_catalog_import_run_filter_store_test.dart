import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/coach_bus/coach_catalog_import_run_filter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('coach catalog import run filter store scopes by baseUrl and userId',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';
    const preferences = CoachCatalogImportRunFilterPreferences(
      status: 'failed',
      replayScope: 'attention',
      issueSeverity: 'error',
      issueStage: 'load_feed',
    );

    await saveCoachCatalogImportRunFilterPreferences(
      baseUrl: baseUrl,
      preferences: preferences,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final sameScope = await loadCoachCatalogImportRunFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final otherUser = await loadCoachCatalogImportRunFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'BCDEFGH2',
    );
    final otherBaseUrl = await loadCoachCatalogImportRunFilterPreferences(
      baseUrl: 'https://ops.shamell.online',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(sameScope.status, 'failed');
    expect(sameScope.replayScope, 'attention');
    expect(sameScope.issueSeverity, 'error');
    expect(sameScope.issueStage, 'load_feed');
    expect(otherUser.hasActiveFilters, isFalse);
    expect(otherBaseUrl.hasActiveFilters, isFalse);
  });

  test('coach catalog import run filter store clears persisted scope',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await saveCoachCatalogImportRunFilterPreferences(
      baseUrl: baseUrl,
      preferences: const CoachCatalogImportRunFilterPreferences(
        status: 'running',
        replayScope: 'with_replays',
        issueSeverity: 'warning',
        issueStage: 'hydrate_trip',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    await clearCoachCatalogImportRunFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final restored = await loadCoachCatalogImportRunFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(restored.status, 'all');
    expect(restored.replayScope, 'all');
    expect(restored.issueSeverity, 'all');
    expect(restored.issueStage, 'all');
    expect(restored.hasActiveFilters, isFalse);
  });

  test(
      'coach catalog import run issue filter store scopes by baseUrl and userId',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';
    const preferences = CoachCatalogImportRunIssueFilterPreferences(
      severity: 'error',
      stage: 'load_feed',
    );

    await saveCoachCatalogImportRunIssueFilterPreferences(
      baseUrl: baseUrl,
      preferences: preferences,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final sameScope = await loadCoachCatalogImportRunIssueFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final otherUser = await loadCoachCatalogImportRunIssueFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'BCDEFGH2',
    );
    final otherBaseUrl = await loadCoachCatalogImportRunIssueFilterPreferences(
      baseUrl: 'https://ops.shamell.online',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(sameScope.severity, 'error');
    expect(sameScope.stage, 'load_feed');
    expect(otherUser.hasActiveFilters, isFalse);
    expect(otherBaseUrl.hasActiveFilters, isFalse);
  });

  test('coach catalog import run issue filter store clears persisted scope',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await saveCoachCatalogImportRunIssueFilterPreferences(
      baseUrl: baseUrl,
      preferences: const CoachCatalogImportRunIssueFilterPreferences(
        severity: 'warning',
        stage: 'hydrate_trip',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    await clearCoachCatalogImportRunIssueFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final restored = await loadCoachCatalogImportRunIssueFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(restored.severity, 'all');
    expect(restored.stage, 'all');
    expect(restored.hasActiveFilters, isFalse);
  });

  test(
      'coach catalog import run saved views update by name and delete by view id',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await upsertCoachCatalogImportRunSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunSavedView(
        viewId: 'catalogview_failed_attention',
        name: 'Failed attention',
        preferences: CoachCatalogImportRunFilterPreferences(
          status: 'failed',
          replayScope: 'attention',
          issueSeverity: 'error',
          issueStage: 'load_feed',
        ),
        createdAtIso: '2026-04-14T18:30:45Z',
        updatedAtIso: '2026-04-14T18:30:45Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final updatedViews = await upsertCoachCatalogImportRunSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunSavedView(
        viewId: 'catalogview_failed_attention',
        name: 'Failed attention',
        preferences: CoachCatalogImportRunFilterPreferences(
          status: 'failed',
          replayScope: 'with_replays',
          issueSeverity: 'warning',
          issueStage: 'hydrate_trip',
        ),
        createdAtIso: '2026-04-14T18:30:45Z',
        updatedAtIso: '2026-04-15T08:00:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    expect(updatedViews, hasLength(1));
    expect(updatedViews.first.preferences.replayScope, 'with_replays');
    expect(updatedViews.first.preferences.issueSeverity, 'warning');
    expect(updatedViews.first.preferences.issueStage, 'hydrate_trip');
    expect(updatedViews.first.isDefault, isFalse);

    final remainingViews = await deleteCoachCatalogImportRunSavedView(
      baseUrl: baseUrl,
      viewId: 'catalogview_failed_attention',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    expect(remainingViews, isEmpty);
  });

  test('coach catalog import run saved views keep only one default view',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await upsertCoachCatalogImportRunSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunSavedView(
        viewId: 'catalogview_failed_attention',
        name: 'Failed attention',
        preferences: CoachCatalogImportRunFilterPreferences(
          status: 'failed',
          replayScope: 'attention',
          issueSeverity: 'error',
          issueStage: 'load_feed',
        ),
        isDefault: true,
        createdAtIso: '2026-04-14T18:30:45Z',
        updatedAtIso: '2026-04-14T18:30:45Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final views = await upsertCoachCatalogImportRunSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunSavedView(
        viewId: 'catalogview_running_replays',
        name: 'Running replays',
        preferences: CoachCatalogImportRunFilterPreferences(
          status: 'running',
          replayScope: 'with_replays',
          issueSeverity: 'warning',
          issueStage: 'hydrate_trip',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T08:00:00Z',
        updatedAtIso: '2026-04-15T08:00:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(views, hasLength(2));
    expect(views.first.viewId, 'catalogview_running_replays');
    expect(views.first.isDefault, isTrue);
    expect(
      views.where((entry) => entry.isDefault).map((entry) => entry.viewId),
      <String>['catalogview_running_replays'],
    );
  });

  test(
      'coach catalog import run saved views keep shared scope separate and never default',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    final views = await upsertCoachCatalogImportRunSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunSavedView(
        viewId: 'catalogview_failed_attention_shared',
        accountId: 'acct_ops_shared',
        name: 'Failed attention',
        visibilityScope: 'shared_ops',
        preferences: CoachCatalogImportRunFilterPreferences(
          status: 'failed',
          replayScope: 'attention',
        ),
        isDefault: true,
        canManage: false,
        createdAtIso: '2026-04-15T09:00:00Z',
        updatedAtIso: '2026-04-15T09:00:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final secondViews = await upsertCoachCatalogImportRunSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunSavedView(
        viewId: 'catalogview_failed_attention_personal',
        name: 'Failed attention',
        visibilityScope: 'personal',
        preferences: CoachCatalogImportRunFilterPreferences(
          status: 'failed',
          replayScope: 'with_replays',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T09:05:00Z',
        updatedAtIso: '2026-04-15T09:05:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(views.single.visibilityScope, 'shared_ops');
    expect(views.single.isDefault, isFalse);
    expect(views.single.accountId, 'acct_ops_shared');
    expect(views.single.canManage, isFalse);
    expect(secondViews, hasLength(2));
    expect(
      secondViews.map((entry) => entry.visibilityScope),
      <String>['personal', 'shared_ops'],
    );
    expect(
      secondViews
          .where((entry) => entry.isDefault)
          .map((entry) => entry.viewId),
      <String>['catalogview_failed_attention_personal'],
    );
  });

  test(
      'coach catalog import run issue saved views update by name, preserve one default, and delete by view id',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await upsertCoachCatalogImportRunIssueSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunIssueSavedView(
        viewId: 'catalogissueview_errors',
        name: 'Errors only',
        preferences: CoachCatalogImportRunIssueFilterPreferences(
          severity: 'error',
          stage: 'all',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T08:00:00Z',
        updatedAtIso: '2026-04-15T08:00:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final updatedViews = await upsertCoachCatalogImportRunIssueSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunIssueSavedView(
        viewId: 'catalogissueview_errors',
        name: 'Errors only',
        preferences: CoachCatalogImportRunIssueFilterPreferences(
          severity: 'error',
          stage: 'load_feed',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T08:00:00Z',
        updatedAtIso: '2026-04-15T08:05:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final secondViewSet = await upsertCoachCatalogImportRunIssueSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunIssueSavedView(
        viewId: 'catalogissueview_warnings',
        name: 'Warnings only',
        preferences: CoachCatalogImportRunIssueFilterPreferences(
          severity: 'warning',
          stage: 'all',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T08:06:00Z',
        updatedAtIso: '2026-04-15T08:06:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(updatedViews, hasLength(1));
    expect(updatedViews.first.preferences.severity, 'error');
    expect(updatedViews.first.preferences.stage, 'load_feed');
    expect(updatedViews.first.isDefault, isTrue);
    expect(secondViewSet, hasLength(2));
    expect(secondViewSet.first.viewId, 'catalogissueview_warnings');
    expect(secondViewSet.first.isDefault, isTrue);
    expect(
      secondViewSet
          .where((entry) => entry.isDefault)
          .map((entry) => entry.viewId),
      <String>['catalogissueview_warnings'],
    );

    final remainingViews = await deleteCoachCatalogImportRunIssueSavedView(
      baseUrl: baseUrl,
      viewId: 'catalogissueview_errors',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(remainingViews, hasLength(1));
    expect(remainingViews.single.viewId, 'catalogissueview_warnings');
  });

  test(
      'coach catalog import run issue saved views keep shared scope separate and never default',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    final views = await upsertCoachCatalogImportRunIssueSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunIssueSavedView(
        viewId: 'catalogissueview_errors_shared',
        accountId: 'acct_ops_shared',
        name: 'Errors only',
        visibilityScope: 'shared_ops',
        preferences: CoachCatalogImportRunIssueFilterPreferences(
          severity: 'error',
          stage: 'all',
        ),
        isDefault: true,
        canManage: false,
        createdAtIso: '2026-04-15T09:10:00Z',
        updatedAtIso: '2026-04-15T09:10:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final secondViews = await upsertCoachCatalogImportRunIssueSavedView(
      baseUrl: baseUrl,
      view: const CoachCatalogImportRunIssueSavedView(
        viewId: 'catalogissueview_errors_personal',
        name: 'Errors only',
        visibilityScope: 'personal',
        preferences: CoachCatalogImportRunIssueFilterPreferences(
          severity: 'error',
          stage: 'load_feed',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T09:12:00Z',
        updatedAtIso: '2026-04-15T09:12:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(views.single.visibilityScope, 'shared_ops');
    expect(views.single.isDefault, isFalse);
    expect(views.single.accountId, 'acct_ops_shared');
    expect(views.single.canManage, isFalse);
    expect(secondViews, hasLength(2));
    expect(
      secondViews.map((entry) => entry.visibilityScope),
      <String>['personal', 'shared_ops'],
    );
    expect(
      secondViews
          .where((entry) => entry.isDefault)
          .map((entry) => entry.viewId),
      <String>['catalogissueview_errors_personal'],
    );
  });
}
