import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_preview_history_filter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test(
      'coach payout import preview history filter store scopes by baseUrl and userId',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';
    const preferences = CoachPayoutImportPreviewHistoryFilterPreferences(
      status: 'invalidated',
      fromCreatedAtIso: '2026-04-14T00:00:00Z',
      toCreatedAtIso: '2026-04-14T23:59:59Z',
      operatorId: 'op_demo_express',
    );

    await saveCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: baseUrl,
      preferences: preferences,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final sameScope =
        await loadCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final otherUser =
        await loadCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'BCDEFGH2',
    );
    final otherBaseUrl =
        await loadCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: 'https://ops.shamell.online',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(sameScope.status, 'invalidated');
    expect(sameScope.fromCreatedAtIso, '2026-04-14T00:00:00Z');
    expect(sameScope.toCreatedAtIso, '2026-04-14T23:59:59Z');
    expect(sameScope.operatorId, 'op_demo_express');
    expect(otherUser.hasActiveFilters, isFalse);
    expect(otherBaseUrl.hasActiveFilters, isFalse);
  });

  test(
      'coach payout import preview history filter store clears persisted scope',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await saveCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: baseUrl,
      preferences: const CoachPayoutImportPreviewHistoryFilterPreferences(
        status: 'expired',
        fromCreatedAtIso: '2026-04-01T00:00:00Z',
        operatorId: 'op_demo_express',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    await clearCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final restored = await loadCoachPayoutImportPreviewHistoryFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    expect(restored.status, 'all');
    expect(restored.fromCreatedAtIso, isNull);
    expect(restored.toCreatedAtIso, isNull);
    expect(restored.operatorId, 'all');
    expect(restored.hasActiveFilters, isFalse);
  });

  test(
      'coach payout import preview history saved views scope by baseUrl and userId',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';
    const view = CoachPayoutImportPreviewHistorySavedView(
      viewId: 'previewview_demo_invalidated',
      name: 'Invalidated day',
      preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
        status: 'invalidated',
        fromCreatedAtIso: '2026-04-14T00:00:00Z',
        toCreatedAtIso: '2026-04-14T23:59:59Z',
        operatorId: 'op_demo_express',
      ),
      createdAtIso: '2026-04-14T18:30:45Z',
      updatedAtIso: '2026-04-14T18:30:45Z',
    );

    await upsertCoachPayoutImportPreviewHistorySavedView(
      baseUrl: baseUrl,
      view: view,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final sameScope = await loadCoachPayoutImportPreviewHistorySavedViews(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final otherUser = await loadCoachPayoutImportPreviewHistorySavedViews(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'BCDEFGH2',
    );
    final otherBaseUrl = await loadCoachPayoutImportPreviewHistorySavedViews(
      baseUrl: 'https://ops.shamell.online',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(sameScope, hasLength(1));
    expect(sameScope.first.name, 'Invalidated day');
    expect(sameScope.first.preferences.status, 'invalidated');
    expect(sameScope.first.preferences.operatorId, 'op_demo_express');
    expect(otherUser, isEmpty);
    expect(otherBaseUrl, isEmpty);
  });

  test(
      'coach payout import preview history saved views update by name and delete by view id',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await upsertCoachPayoutImportPreviewHistorySavedView(
      baseUrl: baseUrl,
      view: const CoachPayoutImportPreviewHistorySavedView(
        viewId: 'previewview_demo_invalidated',
        name: 'Invalidated day',
        preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
          status: 'invalidated',
          fromCreatedAtIso: '2026-04-14T00:00:00Z',
          toCreatedAtIso: '2026-04-14T23:59:59Z',
          operatorId: 'op_demo_express',
        ),
        createdAtIso: '2026-04-14T18:30:45Z',
        updatedAtIso: '2026-04-14T18:30:45Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final updatedViews = await upsertCoachPayoutImportPreviewHistorySavedView(
      baseUrl: baseUrl,
      view: const CoachPayoutImportPreviewHistorySavedView(
        viewId: 'previewview_demo_invalidated',
        name: 'Invalidated day',
        preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
          status: 'invalidated',
          fromCreatedAtIso: '2026-04-07T18:30:45Z',
          toCreatedAtIso: '2026-04-14T18:30:45Z',
          operatorId: 'op_demo_express',
        ),
        createdAtIso: '2026-04-14T18:30:45Z',
        updatedAtIso: '2026-04-15T08:00:00Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    expect(updatedViews, hasLength(1));
    expect(
      updatedViews.first.preferences.fromCreatedAtIso,
      '2026-04-07T18:30:45Z',
    );
    expect(updatedViews.first.preferences.operatorId, 'op_demo_express');

    final remainingViews = await deleteCoachPayoutImportPreviewHistorySavedView(
      baseUrl: baseUrl,
      viewId: 'previewview_demo_invalidated',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    expect(remainingViews, isEmpty);
  });

  test(
      'coach payout import preview history saved views keep only one default view',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await upsertCoachPayoutImportPreviewHistorySavedView(
      baseUrl: baseUrl,
      view: const CoachPayoutImportPreviewHistorySavedView(
        viewId: 'previewview_demo_invalidated',
        name: 'Invalidated day',
        preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
          status: 'invalidated',
          fromCreatedAtIso: '2026-04-14T00:00:00Z',
          toCreatedAtIso: '2026-04-14T23:59:59Z',
          operatorId: 'op_demo_express',
        ),
        isDefault: true,
        createdAtIso: '2026-04-14T18:30:45Z',
        updatedAtIso: '2026-04-14T18:30:45Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final updatedViews = await upsertCoachPayoutImportPreviewHistorySavedView(
      baseUrl: baseUrl,
      view: const CoachPayoutImportPreviewHistorySavedView(
        viewId: 'previewview_demo_active',
        name: 'Active day',
        preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
          status: 'active',
          fromCreatedAtIso: '2026-04-15T00:00:00Z',
          toCreatedAtIso: '2026-04-15T23:59:59Z',
          operatorId: 'op_demo_express',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T18:30:45Z',
        updatedAtIso: '2026-04-15T18:30:45Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(updatedViews.where((entry) => entry.isDefault), hasLength(1));
    expect(updatedViews.first.viewId, 'previewview_demo_active');
    expect(updatedViews.first.isDefault, isTrue);
    expect(
      updatedViews
          .singleWhere(
            (entry) => entry.viewId == 'previewview_demo_invalidated',
          )
          .isDefault,
      isFalse,
    );
  });

  test(
      'coach payout import preview history saved views keep same names across personal and shared scope',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    final updatedViews = await upsertCoachPayoutImportPreviewHistorySavedView(
      baseUrl: baseUrl,
      view: const CoachPayoutImportPreviewHistorySavedView(
        viewId: 'previewview_demo_personal',
        name: 'Invalidated day',
        visibilityScope: 'personal',
        preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
          status: 'invalidated',
          fromCreatedAtIso: '2026-04-14T00:00:00Z',
          toCreatedAtIso: '2026-04-14T23:59:59Z',
          operatorId: 'op_demo_express',
        ),
        isDefault: true,
        createdAtIso: '2026-04-14T18:30:45Z',
        updatedAtIso: '2026-04-14T18:30:45Z',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    ).then(
      (_) => upsertCoachPayoutImportPreviewHistorySavedView(
        baseUrl: baseUrl,
        view: const CoachPayoutImportPreviewHistorySavedView(
          viewId: 'previewview_demo_shared',
          name: 'Invalidated day',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportPreviewHistoryFilterPreferences(
            status: 'invalidated',
            fromCreatedAtIso: '2026-04-07T00:00:00Z',
            toCreatedAtIso: '2026-04-14T23:59:59Z',
            operatorId: 'op_demo_express',
          ),
          isDefault: true,
          createdAtIso: '2026-04-15T18:30:45Z',
          updatedAtIso: '2026-04-15T18:30:45Z',
        ),
        sp: prefs,
        shamellUserIdOverride: 'ABCDEFGH',
      ),
    );

    expect(updatedViews, hasLength(2));
    expect(
      updatedViews.where((entry) => entry.name == 'Invalidated day'),
      hasLength(2),
    );
    expect(
      updatedViews
          .singleWhere((entry) => entry.viewId == 'previewview_demo_shared')
          .isDefault,
      isFalse,
    );
  });
}
