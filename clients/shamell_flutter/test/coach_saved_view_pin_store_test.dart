import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/coach_bus/coach_saved_view_pin_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('saved view pin store persists pinned ids per collection', () async {
    final sp = await SharedPreferences.getInstance();

    await setCoachSavedViewPinned(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'catalog_import_run',
      viewId: 'view_a',
      pinned: true,
      sp: sp,
      shamellUserIdOverride: 'acct_ops',
    );
    final pins = await setCoachSavedViewPinned(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'catalog_import_run',
      viewId: 'view_b',
      pinned: true,
      sp: sp,
      shamellUserIdOverride: 'acct_ops',
    );

    expect(pins, <String>{'view_a', 'view_b'});
    expect(
      await loadCoachSavedViewPinnedIds(
        baseUrl: 'https://api.shamell.online',
        collectionKey: 'catalog_import_run',
        sp: sp,
        shamellUserIdOverride: 'acct_ops',
      ),
      <String>{'view_a', 'view_b'},
    );
  });

  test('saved view pin store scopes entries by collection key', () async {
    final sp = await SharedPreferences.getInstance();

    await setCoachSavedViewPinned(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'catalog_import_run',
      viewId: 'view_shared',
      pinned: true,
      sp: sp,
      shamellUserIdOverride: 'acct_ops',
    );
    await setCoachSavedViewPinned(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'payout_import_preview',
      viewId: 'view_other',
      pinned: true,
      sp: sp,
      shamellUserIdOverride: 'acct_ops',
    );

    expect(
      await loadCoachSavedViewPinnedIds(
        baseUrl: 'https://api.shamell.online',
        collectionKey: 'catalog_import_run',
        sp: sp,
        shamellUserIdOverride: 'acct_ops',
      ),
      <String>{'view_shared'},
    );
    expect(
      await loadCoachSavedViewPinnedIds(
        baseUrl: 'https://api.shamell.online',
        collectionKey: 'payout_import_preview',
        sp: sp,
        shamellUserIdOverride: 'acct_ops',
      ),
      <String>{'view_other'},
    );
  });

  test('saved view pin store removes unpinned ids', () async {
    final sp = await SharedPreferences.getInstance();

    await setCoachSavedViewPinned(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'payout_import_batch',
      viewId: 'view_a',
      pinned: true,
      sp: sp,
      shamellUserIdOverride: 'acct_finance',
    );
    final pins = await setCoachSavedViewPinned(
      baseUrl: 'https://api.shamell.online',
      collectionKey: 'payout_import_batch',
      viewId: 'view_a',
      pinned: false,
      sp: sp,
      shamellUserIdOverride: 'acct_finance',
    );

    expect(pins, isEmpty);
  });
}
