import 'package:shared_preferences/shared_preferences.dart';

const String miniProgramPinnedIdsPrefsKey = 'mini_programs.pinned_ids';
const String miniProgramPinnedOrderPrefsKey = 'mini_programs.pinned_order';
const String miniProgramRecentIdsPrefsKey = 'recent_mini_programs';
const String legacyPinnedMiniAppsPrefsKey = 'pinned_miniapps';
const String legacyRecentModulesPrefsKey = 'recent_modules';

List<String> cleanMiniProgramIdList(Iterable<String> raw, {int? limit}) {
  final out = <String>[];
  final seen = <String>{};
  for (final item in raw) {
    final id = item.trim();
    if (id.isEmpty) continue;
    if (!seen.add(id)) continue;
    out.add(id);
    if (limit != null && out.length >= limit) break;
  }
  return out;
}

List<String> loadMiniProgramPinnedIdsSync(SharedPreferences sp) {
  return cleanMiniProgramIdList(<String>[
    ...(sp.getStringList(miniProgramPinnedIdsPrefsKey) ?? const <String>[]),
    ...(sp.getStringList(legacyPinnedMiniAppsPrefsKey) ?? const <String>[]),
  ]);
}

List<String> miniProgramPinnedOrderFromLists({
  required Iterable<String> pinnedIds,
  required Iterable<String> orderedIds,
}) {
  final pinned = cleanMiniProgramIdList(pinnedIds);
  final pinnedSet = pinned.toSet();
  final ordered = cleanMiniProgramIdList(
    orderedIds,
  ).where(pinnedSet.contains).toList(growable: true);
  for (final id in pinned) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  return ordered;
}

List<String> loadMiniProgramPinnedOrderSync(SharedPreferences sp) {
  return miniProgramPinnedOrderFromLists(
    pinnedIds: loadMiniProgramPinnedIdsSync(sp),
    orderedIds:
        sp.getStringList(miniProgramPinnedOrderPrefsKey) ?? const <String>[],
  );
}

List<String> loadMiniProgramRecentIdsSync(
  SharedPreferences sp, {
  bool includeLegacyModules = false,
  int limit = 10,
}) {
  return cleanMiniProgramIdList(
    <String>[
      ...(sp.getStringList(miniProgramRecentIdsPrefsKey) ?? const <String>[]),
      if (includeLegacyModules)
        ...(sp.getStringList(legacyRecentModulesPrefsKey) ?? const <String>[]),
    ],
    limit: limit,
  );
}

Future<void> saveMiniProgramPinnedIds(
  SharedPreferences sp,
  Iterable<String> ids, {
  bool mirrorLegacy = false,
}) async {
  final cleaned = cleanMiniProgramIdList(ids);
  await sp.setStringList(miniProgramPinnedIdsPrefsKey, cleaned);
  if (mirrorLegacy) {
    await sp.setStringList(legacyPinnedMiniAppsPrefsKey, cleaned);
  } else {
    await sp.remove(legacyPinnedMiniAppsPrefsKey);
  }
}

Future<void> saveMiniProgramPinnedOrder(
  SharedPreferences sp,
  Iterable<String> orderedIds, {
  Iterable<String>? pinnedIds,
}) async {
  final cleaned = miniProgramPinnedOrderFromLists(
    pinnedIds: pinnedIds ?? loadMiniProgramPinnedIdsSync(sp),
    orderedIds: orderedIds,
  );
  await sp.setStringList(miniProgramPinnedOrderPrefsKey, cleaned);
}

Future<void> saveMiniProgramShelfPrefs(
  SharedPreferences sp, {
  required Iterable<String> pinnedIds,
  Iterable<String>? pinnedOrder,
  Iterable<String>? recentIds,
  bool mirrorLegacyPinned = false,
}) async {
  final pinned = cleanMiniProgramIdList(pinnedIds);
  final order = miniProgramPinnedOrderFromLists(
    pinnedIds: pinned,
    orderedIds: pinnedOrder ?? pinned,
  );
  await saveMiniProgramPinnedIds(
    sp,
    pinned,
    mirrorLegacy: mirrorLegacyPinned,
  );
  await sp.setStringList(miniProgramPinnedOrderPrefsKey, order);
  if (recentIds != null) {
    await saveMiniProgramRecentIds(sp, recentIds);
  }
}

Future<void> saveMiniProgramRecentIds(
  SharedPreferences sp,
  Iterable<String> ids, {
  int limit = 10,
}) async {
  await sp.setStringList(
    miniProgramRecentIdsPrefsKey,
    cleanMiniProgramIdList(ids, limit: limit),
  );
}

Future<void> clearMiniProgramRecentIds(SharedPreferences sp) async {
  await sp.remove(miniProgramRecentIdsPrefsKey);
}

Future<void> clearLegacyRecentModules(SharedPreferences sp) async {
  await sp.remove(legacyRecentModulesPrefsKey);
}
