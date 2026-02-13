import 'package:shared_preferences/shared_preferences.dart';

class StickerPack {
  final String id;
  final String nameEn;
  final String nameAr;
  final List<String> stickers;
  final int priceCents;
  final String currency;
  final List<String> tags;

  const StickerPack({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.stickers,
    this.priceCents = 0,
    this.currency = 'SYP',
    this.tags = const <String>[],
  });
}

const List<StickerPack> kStickerPacks = [
  StickerPack(
    id: 'classic_smileys',
    nameEn: 'Classic smileys',
    nameAr: 'الابتسامات الكلاسيكية',
    stickers: ['😀', '😂', '🥲', '😅', '😍', '😎', '😭', '😡'],
    tags: ['classic', 'emoji'],
  ),
  StickerPack(
    id: 'celebration',
    nameEn: 'Celebrations',
    nameAr: 'الاحتفالات',
    stickers: ['🎉', '🎂', '🎁', '🕌', '🕋', '🕯️', '🪅', '🥳'],
    tags: ['celebration', 'events'],
  ),
  StickerPack(
    id: 'shamell_payments',
    nameEn: 'Shamell Pay',
    nameAr: 'مرسال باي',
    stickers: ['💸', '💳', '📲', '🏧', '🧾', '✅'],
    tags: ['shamell', 'pay', 'wallet'],
  ),
  StickerPack(
    id: 'shamell_services',
    nameEn: 'Shamell essentials',
    nameAr: 'أساسيات شامل',
    stickers: ['🚌', '💳', '📲', '✅', '🔔', '🧾'],
    tags: ['shamell', 'essentials'],
  ),
  StickerPack(
    id: 'daily_reactions',
    nameEn: 'Daily reactions',
    nameAr: 'تفاعلات يومية',
    stickers: ['🤝', '🙏', '🔥', '✅', '❌', '⏳', '⭐', '❤️'],
    tags: ['reactions', 'emoji'],
  ),
];

const String _kInstalledKey = 'stickers.installed_packs';
const String _kUsageKeyPrefix = 'stickers.usage.';
const String _kRecentKey = 'stickers.recent';

Future<List<String>> loadInstalledStickerPackIds() async {
  try {
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_kInstalledKey) ?? const <String>[];
  } catch (_) {
    return const <String>[];
  }
}

Future<void> saveInstalledStickerPackIds(List<String> ids) async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kInstalledKey, ids);
  } catch (_) {}
}

Future<List<StickerPack>> loadInstalledStickerPacks() async {
  final ids = await loadInstalledStickerPackIds();
  if (ids.isEmpty) return const <StickerPack>[];
  final list = <StickerPack>[];
  for (final pack in kStickerPacks) {
    if (ids.contains(pack.id)) {
      list.add(pack);
    }
  }
  return list;
}

Future<int> loadStickerPackUsage(String packId) async {
  if (packId.isEmpty) return 0;
  try {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt('$_kUsageKeyPrefix$packId') ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<Map<String, int>> loadAllStickerUsage() async {
  final map = <String, int>{};
  try {
    final sp = await SharedPreferences.getInstance();
    for (final pack in kStickerPacks) {
      final key = '$_kUsageKeyPrefix${pack.id}';
      final v = sp.getInt(key) ?? 0;
      if (v > 0) {
        map[pack.id] = v;
      }
    }
  } catch (_) {}
  return map;
}

Future<void> incrementStickerUsage(String packId) async {
  if (packId.isEmpty) return;
  try {
    final sp = await SharedPreferences.getInstance();
    final key = '$_kUsageKeyPrefix$packId';
    final cur = sp.getInt(key) ?? 0;
    await sp.setInt(key, cur + 1);
  } catch (_) {}
}

Future<List<String>> loadRecentStickers({int maxItems = 24}) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kRecentKey) ?? const <String>[];
    if (list.length <= maxItems) return List<String>.from(list);
    return List<String>.from(list.take(maxItems));
  } catch (_) {
    return const <String>[];
  }
}

Future<void> pushRecentSticker(String emoji, {int maxItems = 24}) async {
  final e = emoji.trim();
  if (e.isEmpty) return;
  try {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kRecentKey) ?? const <String>[];
    final next = <String>[];
    next.add(e);
    for (final v in list) {
      if (v == e) continue;
      next.add(v);
      if (next.length >= maxItems) break;
    }
    await sp.setStringList(_kRecentKey, next);
  } catch (_) {}
}
