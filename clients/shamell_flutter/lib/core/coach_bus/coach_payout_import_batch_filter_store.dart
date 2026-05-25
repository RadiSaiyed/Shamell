import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../base_url.dart';
import '../shamell_user_id.dart';

const String _coachPayoutImportBatchFilterScopedPrefKeyPrefix =
    'coach.ops.payout_import_batch_filters.v1.';
const String _coachPayoutImportBatchSavedViewsScopedPrefKeyPrefix =
    'coach.ops.payout_import_batch_saved_views.v1.';

class CoachPayoutImportBatchFilterPreferences {
  final String operatorId;

  const CoachPayoutImportBatchFilterPreferences({
    this.operatorId = 'all',
  });

  static const empty = CoachPayoutImportBatchFilterPreferences();

  bool get hasActiveFilters =>
      _normalizeCoachPayoutImportBatchOperatorId(operatorId) != 'all';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'operator_id': _normalizeCoachPayoutImportBatchOperatorId(operatorId),
    };
  }

  static CoachPayoutImportBatchFilterPreferences fromJson(Object? raw) {
    if (raw is! Map) {
      return empty;
    }
    return CoachPayoutImportBatchFilterPreferences(
      operatorId: _normalizeCoachPayoutImportBatchOperatorId(
        (raw['operator_id'] ?? '').toString(),
      ),
    );
  }
}

class CoachPayoutImportBatchSavedView {
  final String viewId;
  final String accountId;
  final String name;
  final String visibilityScope;
  final CoachPayoutImportBatchFilterPreferences preferences;
  final bool isDefault;
  final bool isFavorite;
  final String? lastUsedAtIso;
  final bool canManage;
  final String createdAtIso;
  final String updatedAtIso;

  const CoachPayoutImportBatchSavedView({
    required this.viewId,
    this.accountId = '',
    required this.name,
    this.visibilityScope = 'personal',
    required this.preferences,
    this.isDefault = false,
    this.isFavorite = false,
    this.lastUsedAtIso,
    this.canManage = true,
    required this.createdAtIso,
    required this.updatedAtIso,
  });

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'view_id': viewId.trim(),
      'account_id': accountId.trim(),
      'name': name.trim(),
      'visibility_scope':
          _normalizeCoachPayoutImportSavedViewVisibilityScope(visibilityScope),
      'preferences': preferences.toJson(),
      'is_default': isDefault,
      'is_favorite': isFavorite,
      'last_used_at':
          (lastUsedAtIso ?? '').trim().isEmpty ? null : lastUsedAtIso!.trim(),
      'can_manage': canManage,
      'created_at': createdAtIso.trim(),
      'updated_at': updatedAtIso.trim(),
    };
  }

  static CoachPayoutImportBatchSavedView? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final viewId = (raw['view_id'] ?? '').toString().trim();
    final accountId = (raw['account_id'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();
    final visibilityScope = _normalizeCoachPayoutImportSavedViewVisibilityScope(
      (raw['visibility_scope'] ?? '').toString(),
    );
    final preferences = CoachPayoutImportBatchFilterPreferences.fromJson(
      raw['preferences'],
    );
    final isDefault =
        visibilityScope == 'personal' && raw['is_default'] == true;
    final isFavorite = raw['is_favorite'] == true;
    final lastUsedAtIso = _normalizeRfc3339OrNull(
      (raw['last_used_at'] ?? '').toString(),
    );
    final canManage = raw['can_manage'] != false;
    final createdAtIso = _normalizeRfc3339OrNull(
      (raw['created_at'] ?? '').toString(),
    );
    final updatedAtIso = _normalizeRfc3339OrNull(
      (raw['updated_at'] ?? '').toString(),
    );
    if (viewId.isEmpty ||
        name.isEmpty ||
        !preferences.hasActiveFilters ||
        createdAtIso == null ||
        updatedAtIso == null) {
      return null;
    }
    return CoachPayoutImportBatchSavedView(
      viewId: viewId,
      accountId: accountId,
      name: name,
      visibilityScope: visibilityScope,
      preferences: preferences,
      isDefault: isDefault,
      isFavorite: isFavorite,
      lastUsedAtIso: lastUsedAtIso,
      canManage: canManage,
      createdAtIso: createdAtIso,
      updatedAtIso: updatedAtIso,
    );
  }
}

Future<CoachPayoutImportBatchFilterPreferences>
    loadCoachPayoutImportBatchFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportBatchFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return CoachPayoutImportBatchFilterPreferences.empty;
  }
  try {
    return CoachPayoutImportBatchFilterPreferences.fromJson(jsonDecode(raw));
  } catch (_) {
    return CoachPayoutImportBatchFilterPreferences.empty;
  }
}

Future<void> saveCoachPayoutImportBatchFilterPreferences({
  required String baseUrl,
  required CoachPayoutImportBatchFilterPreferences preferences,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportBatchFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  await prefs.setString(key, jsonEncode(preferences.toJson()));
}

Future<void> clearCoachPayoutImportBatchFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportBatchFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  await prefs.remove(key);
}

Future<List<CoachPayoutImportBatchSavedView>>
    loadCoachPayoutImportBatchSavedViews({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportBatchSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  return _loadCoachPayoutImportBatchSavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
}

Future<List<CoachPayoutImportBatchSavedView>>
    upsertCoachPayoutImportBatchSavedView({
  required String baseUrl,
  required CoachPayoutImportBatchSavedView view,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
  int maxViews = 8,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportBatchSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existingViews = _loadCoachPayoutImportBatchSavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
  final normalizedName = view.name.trim().toLowerCase();
  final normalizedScope =
      _normalizeCoachPayoutImportSavedViewVisibilityScope(view.visibilityScope);
  final normalizedView = CoachPayoutImportBatchSavedView(
    viewId: view.viewId,
    accountId: view.accountId,
    name: view.name,
    visibilityScope: normalizedScope,
    preferences: view.preferences,
    isDefault: normalizedScope == 'personal' && view.isDefault,
    isFavorite: view.isFavorite,
    lastUsedAtIso: view.lastUsedAtIso,
    canManage: view.canManage,
    createdAtIso: view.createdAtIso,
    updatedAtIso: view.updatedAtIso,
  );
  final updatedViews = <CoachPayoutImportBatchSavedView>[
    normalizedView,
    ...existingViews.where(
      (entry) =>
          entry.viewId != normalizedView.viewId &&
          !(entry.visibilityScope == normalizedScope &&
              entry.name.trim().toLowerCase() == normalizedName),
    ),
  ]..sort((left, right) {
      if (left.isDefault != right.isDefault) {
        return left.isDefault ? -1 : 1;
      }
      return right.updatedAtIso.compareTo(left.updatedAtIso);
    });
  if (normalizedView.isDefault) {
    for (var index = 0; index < updatedViews.length; index += 1) {
      final entry = updatedViews[index];
      if (entry.viewId == normalizedView.viewId) {
        continue;
      }
      if (!entry.isDefault || entry.visibilityScope != 'personal') {
        continue;
      }
      updatedViews[index] = CoachPayoutImportBatchSavedView(
        viewId: entry.viewId,
        accountId: entry.accountId,
        name: entry.name,
        visibilityScope: entry.visibilityScope,
        preferences: entry.preferences,
        isDefault: false,
        isFavorite: entry.isFavorite,
        lastUsedAtIso: entry.lastUsedAtIso,
        canManage: entry.canManage,
        createdAtIso: entry.createdAtIso,
        updatedAtIso: entry.updatedAtIso,
      );
    }
  }
  if (updatedViews.length > maxViews) {
    updatedViews.removeRange(maxViews, updatedViews.length);
  }
  await prefs.setString(
    key,
    jsonEncode(
      updatedViews.map((entry) => entry.toJson()).toList(growable: false),
    ),
  );
  return updatedViews;
}

Future<List<CoachPayoutImportBatchSavedView>>
    deleteCoachPayoutImportBatchSavedView({
  required String baseUrl,
  required String viewId,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportBatchSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existingViews = _loadCoachPayoutImportBatchSavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
  final updatedViews = existingViews
      .where((entry) => entry.viewId != viewId.trim())
      .toList(growable: false);
  await prefs.setString(
    key,
    jsonEncode(
      updatedViews.map((entry) => entry.toJson()).toList(growable: false),
    ),
  );
  return updatedViews;
}

String _normalizeCoachPayoutImportBatchOperatorId(String? value) {
  final normalized = (value ?? '').trim();
  return normalized.isEmpty ? 'all' : normalized;
}

String _normalizeCoachPayoutImportSavedViewVisibilityScope(String? value) {
  return switch ((value ?? '').trim().toLowerCase()) {
    'shared_ops' => 'shared_ops',
    _ => 'personal',
  };
}

String? _normalizeRfc3339OrNull(String? value) {
  final normalized = (value ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) {
    return null;
  }
  return parsed.toUtc().toIso8601String().replaceFirst('.000Z', 'Z');
}

Future<String> _coachPayoutImportBatchFilterScopedPrefKey({
  required String baseUrl,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final scope = await _coachPayoutImportBatchFilterScope(
    baseUrl: baseUrl,
    sp: sp,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachPayoutImportBatchFilterScopedPrefKeyPrefix$suffix';
}

Future<String> _coachPayoutImportBatchSavedViewsScopedPrefKey({
  required String baseUrl,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final scope = await _coachPayoutImportBatchFilterScope(
    baseUrl: baseUrl,
    sp: sp,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachPayoutImportBatchSavedViewsScopedPrefKeyPrefix$suffix';
}

List<CoachPayoutImportBatchSavedView>
    _loadCoachPayoutImportBatchSavedViewsFromPrefs({
  required SharedPreferences prefs,
  required String key,
}) {
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return const <CoachPayoutImportBatchSavedView>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <CoachPayoutImportBatchSavedView>[];
    }
    final views = decoded
        .map(CoachPayoutImportBatchSavedView.fromJson)
        .whereType<CoachPayoutImportBatchSavedView>()
        .toList(growable: false)
      ..sort((left, right) {
        if (left.isDefault != right.isDefault) {
          return left.isDefault ? -1 : 1;
        }
        return right.updatedAtIso.compareTo(left.updatedAtIso);
      });
    return views;
  } catch (_) {
    return const <CoachPayoutImportBatchSavedView>[];
  }
}

Future<String> _coachPayoutImportBatchFilterScope({
  required String baseUrl,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final normalizedBaseUrl = normalizeSecureApiBaseUrl(baseUrl) ?? '';
  final origin = normalizedBaseUrl.isEmpty
      ? 'unknown-origin'
      : Uri.parse(normalizedBaseUrl).origin;
  final resolvedShamellUserId = (shamellUserIdOverride ?? '').trim().isNotEmpty
      ? shamellUserIdOverride!.trim().toUpperCase()
      : ((await loadShamellUserId(sp: sp, baseUrlOverride: baseUrl)) ?? '')
          .trim()
          .toUpperCase();
  final userScope = isValidShamellUserId(resolvedShamellUserId)
      ? resolvedShamellUserId
      : 'unknown-user';
  return '$origin|$userScope';
}
