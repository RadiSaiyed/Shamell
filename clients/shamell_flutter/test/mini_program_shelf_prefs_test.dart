import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/mini_program_shelf_prefs.dart';

void main() {
  group('mini program shelf prefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
    });

    test('loads legacy pinned ids through the canonical shelf API', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        legacyPinnedMiniAppsPrefsKey: <String>[
          'payments',
          '',
          'payments',
          'coach',
        ],
        miniProgramPinnedOrderPrefsKey: <String>[
          'coach',
          'ghost',
          'payments',
        ],
      });
      final sp = await SharedPreferences.getInstance();

      expect(loadMiniProgramPinnedIdsSync(sp), <String>['payments', 'coach']);
      expect(loadMiniProgramPinnedOrderSync(sp), <String>[
        'coach',
        'payments',
      ]);
    });

    test('saves canonical pinned ids and clears the legacy key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        legacyPinnedMiniAppsPrefsKey: <String>['old_module'],
      });
      final sp = await SharedPreferences.getInstance();

      await saveMiniProgramShelfPrefs(
        sp,
        pinnedIds: <String>['coach', 'payments', 'coach'],
        pinnedOrder: <String>['payments'],
        recentIds: <String>['moments', 'moments', 'green_paket'],
      );

      expect(sp.getStringList(miniProgramPinnedIdsPrefsKey), <String>[
        'coach',
        'payments',
      ]);
      expect(sp.getStringList(legacyPinnedMiniAppsPrefsKey), isNull);
      expect(sp.getStringList(miniProgramPinnedOrderPrefsKey), <String>[
        'payments',
        'coach',
      ]);
      expect(sp.getStringList(miniProgramRecentIdsPrefsKey), <String>[
        'moments',
        'green_paket',
      ]);
    });

    test('keeps legacy module recents as an explicit migration source',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        miniProgramRecentIdsPrefsKey: <String>['payments', 'green_paket'],
        legacyRecentModulesPrefsKey: <String>['coach', 'payments'],
      });
      final sp = await SharedPreferences.getInstance();

      expect(loadMiniProgramRecentIdsSync(sp), <String>[
        'payments',
        'green_paket',
      ]);
      expect(
        loadMiniProgramRecentIdsSync(sp, includeLegacyModules: true),
        <String>['payments', 'green_paket', 'coach'],
      );
    });
  });
}
