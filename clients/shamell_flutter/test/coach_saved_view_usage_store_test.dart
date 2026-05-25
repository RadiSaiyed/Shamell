import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/coach_bus/coach_saved_view_usage_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('saved view usage store persists most recent usage per collection',
      () async {
    final sp = await SharedPreferences.getInstance();

    await markCoachSavedViewUsed(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'catalog_import_run',
      viewId: 'view_a',
      usedAtIso: '2026-04-18T10:00:00Z',
      sp: sp,
      shamellUserIdOverride: 'acct_ops',
    );
    final usage = await markCoachSavedViewUsed(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'catalog_import_run',
      viewId: 'view_b',
      usedAtIso: '2026-04-18T11:00:00Z',
      sp: sp,
      shamellUserIdOverride: 'acct_ops',
    );

    expect(
      usage,
      <String, String>{
        'view_b': '2026-04-18T11:00:00Z',
        'view_a': '2026-04-18T10:00:00Z',
      },
    );
    expect(
      await loadCoachSavedViewUsageMap(
        baseUrl: 'https://api.shamell.online',
        collectionKey: 'catalog_import_run',
        sp: sp,
        shamellUserIdOverride: 'acct_ops',
      ),
      usage,
    );
  });

  test('saved view usage store scopes entries by collection key', () async {
    final sp = await SharedPreferences.getInstance();

    await markCoachSavedViewUsed(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'catalog_import_run',
      viewId: 'view_shared',
      usedAtIso: '2026-04-18T10:00:00Z',
      sp: sp,
      shamellUserIdOverride: 'acct_ops',
    );
    await markCoachSavedViewUsed(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'payout_import_preview',
      viewId: 'view_shared',
      usedAtIso: '2026-04-18T11:00:00Z',
      sp: sp,
      shamellUserIdOverride: 'acct_ops',
    );

    expect(
      await loadCoachSavedViewUsageMap(
        baseUrl: 'https://api.shamell.online',
        collectionKey: 'catalog_import_run',
        sp: sp,
        shamellUserIdOverride: 'acct_ops',
      ),
      <String, String>{'view_shared': '2026-04-18T10:00:00Z'},
    );
    expect(
      await loadCoachSavedViewUsageMap(
        baseUrl: 'https://api.shamell.online',
        collectionKey: 'payout_import_preview',
        sp: sp,
        shamellUserIdOverride: 'acct_ops',
      ),
      <String, String>{'view_shared': '2026-04-18T11:00:00Z'},
    );
  });
}
