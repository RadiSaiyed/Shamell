import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/coach_bus/coach_payout_import_batch_filter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('coach payout import batch filter store scopes by baseUrl and userId',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';
    const preferences = CoachPayoutImportBatchFilterPreferences(
      operatorId: 'op_demo_express',
    );

    await saveCoachPayoutImportBatchFilterPreferences(
      baseUrl: baseUrl,
      preferences: preferences,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final sameScope = await loadCoachPayoutImportBatchFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final otherUser = await loadCoachPayoutImportBatchFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'BCDEFGH2',
    );
    final otherBaseUrl = await loadCoachPayoutImportBatchFilterPreferences(
      baseUrl: 'https://ops.shamell.online',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(sameScope.operatorId, 'op_demo_express');
    expect(sameScope.hasActiveFilters, isTrue);
    expect(otherUser.operatorId, 'all');
    expect(otherBaseUrl.operatorId, 'all');
  });

  test('coach payout import batch filter store clears persisted scope',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await saveCoachPayoutImportBatchFilterPreferences(
      baseUrl: baseUrl,
      preferences: const CoachPayoutImportBatchFilterPreferences(
        operatorId: 'op_demo_express',
      ),
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    await clearCoachPayoutImportBatchFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final restored = await loadCoachPayoutImportBatchFilterPreferences(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    expect(restored.operatorId, 'all');
    expect(restored.hasActiveFilters, isFalse);
  });

  test('coach payout import batch saved views scope by baseUrl and userId',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';
    const view = CoachPayoutImportBatchSavedView(
      viewId: 'batchview_demo_express',
      name: 'Demo Express batches',
      preferences: CoachPayoutImportBatchFilterPreferences(
        operatorId: 'op_demo_express',
      ),
      createdAtIso: '2026-04-15T10:08:00Z',
      updatedAtIso: '2026-04-15T10:08:00Z',
    );

    await upsertCoachPayoutImportBatchSavedView(
      baseUrl: baseUrl,
      view: view,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    final sameScope = await loadCoachPayoutImportBatchSavedViews(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    final otherUser = await loadCoachPayoutImportBatchSavedViews(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'BCDEFGH2',
    );
    final otherBaseUrl = await loadCoachPayoutImportBatchSavedViews(
      baseUrl: 'https://ops.shamell.online',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );

    expect(sameScope, hasLength(1));
    expect(sameScope.first.name, 'Demo Express batches');
    expect(sameScope.first.preferences.operatorId, 'op_demo_express');
    expect(otherUser, isEmpty);
    expect(otherBaseUrl, isEmpty);
  });

  test('coach payout import batch saved views upsert and delete by name',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await upsertCoachPayoutImportBatchSavedView(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
      view: const CoachPayoutImportBatchSavedView(
        viewId: 'batchview_demo_a',
        name: 'Demo batches',
        preferences: CoachPayoutImportBatchFilterPreferences(
          operatorId: 'op_demo_a',
        ),
        createdAtIso: '2026-04-15T10:08:00Z',
        updatedAtIso: '2026-04-15T10:08:00Z',
      ),
    );

    final updatedViews = await upsertCoachPayoutImportBatchSavedView(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
      view: const CoachPayoutImportBatchSavedView(
        viewId: 'batchview_demo_b',
        name: 'Demo batches',
        preferences: CoachPayoutImportBatchFilterPreferences(
          operatorId: 'op_demo_b',
        ),
        createdAtIso: '2026-04-15T10:09:00Z',
        updatedAtIso: '2026-04-15T10:09:00Z',
      ),
    );

    expect(updatedViews, hasLength(1));
    expect(updatedViews.first.viewId, 'batchview_demo_b');
    expect(updatedViews.first.preferences.operatorId, 'op_demo_b');

    final remainingViews = await deleteCoachPayoutImportBatchSavedView(
      baseUrl: baseUrl,
      viewId: 'batchview_demo_b',
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
    );
    expect(remainingViews, isEmpty);
  });

  test('coach payout import batch saved views keep only one default view',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    await upsertCoachPayoutImportBatchSavedView(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
      view: const CoachPayoutImportBatchSavedView(
        viewId: 'batchview_demo_a',
        name: 'Demo A',
        preferences: CoachPayoutImportBatchFilterPreferences(
          operatorId: 'op_demo_a',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T10:08:00Z',
        updatedAtIso: '2026-04-15T10:08:00Z',
      ),
    );

    final updatedViews = await upsertCoachPayoutImportBatchSavedView(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
      view: const CoachPayoutImportBatchSavedView(
        viewId: 'batchview_demo_b',
        name: 'Demo B',
        preferences: CoachPayoutImportBatchFilterPreferences(
          operatorId: 'op_demo_b',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T10:09:00Z',
        updatedAtIso: '2026-04-15T10:09:00Z',
      ),
    );

    expect(updatedViews, hasLength(2));
    expect(updatedViews.first.viewId, 'batchview_demo_b');
    expect(updatedViews.first.isDefault, isTrue);
    expect(updatedViews.last.viewId, 'batchview_demo_a');
    expect(updatedViews.last.isDefault, isFalse);
  });

  test(
      'coach payout import batch saved views keep same names across personal and shared scope',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const baseUrl = 'https://api.shamell.online';

    final updatedViews = await upsertCoachPayoutImportBatchSavedView(
      baseUrl: baseUrl,
      sp: prefs,
      shamellUserIdOverride: 'ABCDEFGH',
      view: const CoachPayoutImportBatchSavedView(
        viewId: 'batchview_demo_personal',
        name: 'Demo batches',
        visibilityScope: 'personal',
        preferences: CoachPayoutImportBatchFilterPreferences(
          operatorId: 'op_demo_a',
        ),
        isDefault: true,
        createdAtIso: '2026-04-15T10:08:00Z',
        updatedAtIso: '2026-04-15T10:08:00Z',
      ),
    ).then(
      (_) => upsertCoachPayoutImportBatchSavedView(
        baseUrl: baseUrl,
        sp: prefs,
        shamellUserIdOverride: 'ABCDEFGH',
        view: const CoachPayoutImportBatchSavedView(
          viewId: 'batchview_demo_shared',
          name: 'Demo batches',
          visibilityScope: 'shared_ops',
          preferences: CoachPayoutImportBatchFilterPreferences(
            operatorId: 'op_demo_b',
          ),
          isDefault: true,
          createdAtIso: '2026-04-15T10:09:00Z',
          updatedAtIso: '2026-04-15T10:09:00Z',
        ),
      ),
    );

    expect(updatedViews, hasLength(2));
    expect(
      updatedViews.where((entry) => entry.name == 'Demo batches'),
      hasLength(2),
    );
    expect(
      updatedViews
          .singleWhere((entry) => entry.viewId == 'batchview_demo_shared')
          .isDefault,
      isFalse,
    );
  });
}
