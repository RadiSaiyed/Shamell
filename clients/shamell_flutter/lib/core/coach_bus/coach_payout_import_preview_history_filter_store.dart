import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../base_url.dart';
import '../shamell_user_id.dart';

const String _coachPayoutImportPreviewHistoryFilterScopedPrefKeyPrefix =
    'coach.ops.payout_import_preview_history_filters.v1.';
const String _coachPayoutImportPreviewHistorySavedViewsScopedPrefKeyPrefix =
    'coach.ops.payout_import_preview_history_saved_views.v1.';

class CoachPayoutImportPreviewHistoryFilterPreferences {
  final String status;
  final String? fromCreatedAtIso;
  final String? toCreatedAtIso;
  final String operatorId;

  const CoachPayoutImportPreviewHistoryFilterPreferences({
    this.status = 'all',
    this.fromCreatedAtIso,
    this.toCreatedAtIso,
    this.operatorId = 'all',
  });

  static const empty = CoachPayoutImportPreviewHistoryFilterPreferences();

  bool get hasActiveFilters {
    return status.trim().toLowerCase() != 'all' ||
        (fromCreatedAtIso ?? '').trim().isNotEmpty ||
        (toCreatedAtIso ?? '').trim().isNotEmpty ||
        _normalizeCoachPayoutImportPreviewHistoryOperatorId(operatorId) !=
            'all';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.trim().isEmpty ? 'all' : status.trim(),
      'from_created_at': (fromCreatedAtIso ?? '').trim().isEmpty
          ? null
          : fromCreatedAtIso!.trim(),
      'to_created_at':
          (toCreatedAtIso ?? '').trim().isEmpty ? null : toCreatedAtIso!.trim(),
      'operator_id':
          _normalizeCoachPayoutImportPreviewHistoryOperatorId(operatorId),
    };
  }

  static CoachPayoutImportPreviewHistoryFilterPreferences fromJson(
    Object? raw,
  ) {
    if (raw is! Map) {
      return empty;
    }
    final statusRaw = (raw['status'] ?? '').toString().trim().toLowerCase();
    final status = switch (statusRaw) {
      'active' || 'consumed' || 'expired' || 'invalidated' => statusRaw,
      _ => 'all',
    };
    final fromCreatedAtIso =
        (raw['from_created_at'] ?? '').toString().trim().isEmpty
            ? null
            : (raw['from_created_at'] ?? '').toString().trim();
    final toCreatedAtIso =
        (raw['to_created_at'] ?? '').toString().trim().isEmpty
            ? null
            : (raw['to_created_at'] ?? '').toString().trim();
    final normalizedFromCreatedAtIso =
        _normalizeRfc3339OrNull(fromCreatedAtIso);
    final normalizedToCreatedAtIso = _normalizeRfc3339OrNull(toCreatedAtIso);
    return CoachPayoutImportPreviewHistoryFilterPreferences(
      status: status,
      fromCreatedAtIso: normalizedFromCreatedAtIso,
      toCreatedAtIso: normalizedToCreatedAtIso,
      operatorId: _normalizeCoachPayoutImportPreviewHistoryOperatorId(
        (raw['operator_id'] ?? '').toString(),
      ),
    );
  }
}

class CoachPayoutImportPreviewHistorySavedView {
  final String viewId;
  final String accountId;
  final String name;
  final String visibilityScope;
  final CoachPayoutImportPreviewHistoryFilterPreferences preferences;
  final bool isDefault;
  final bool isFavorite;
  final String? lastUsedAtIso;
  final bool canManage;
  final String createdAtIso;
  final String updatedAtIso;

  const CoachPayoutImportPreviewHistorySavedView({
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

  static CoachPayoutImportPreviewHistorySavedView? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final viewId = (raw['view_id'] ?? '').toString().trim();
    final accountId = (raw['account_id'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();
    final visibilityScope = _normalizeCoachPayoutImportSavedViewVisibilityScope(
      (raw['visibility_scope'] ?? '').toString(),
    );
    final preferences =
        CoachPayoutImportPreviewHistoryFilterPreferences.fromJson(
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
    return CoachPayoutImportPreviewHistorySavedView(
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

Future<CoachPayoutImportPreviewHistoryFilterPreferences>
    loadCoachPayoutImportPreviewHistoryFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportPreviewHistoryFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return CoachPayoutImportPreviewHistoryFilterPreferences.empty;
  }
  try {
    return CoachPayoutImportPreviewHistoryFilterPreferences.fromJson(
      jsonDecode(raw),
    );
  } catch (_) {
    return CoachPayoutImportPreviewHistoryFilterPreferences.empty;
  }
}

Future<void> saveCoachPayoutImportPreviewHistoryFilterPreferences({
  required String baseUrl,
  required CoachPayoutImportPreviewHistoryFilterPreferences preferences,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportPreviewHistoryFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  await prefs.setString(key, jsonEncode(preferences.toJson()));
}

Future<void> clearCoachPayoutImportPreviewHistoryFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportPreviewHistoryFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  await prefs.remove(key);
}

Future<List<CoachPayoutImportPreviewHistorySavedView>>
    loadCoachPayoutImportPreviewHistorySavedViews({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportPreviewHistorySavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  return _loadCoachPayoutImportPreviewHistorySavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
}

Future<List<CoachPayoutImportPreviewHistorySavedView>>
    upsertCoachPayoutImportPreviewHistorySavedView({
  required String baseUrl,
  required CoachPayoutImportPreviewHistorySavedView view,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
  int maxViews = 8,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportPreviewHistorySavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existingViews = _loadCoachPayoutImportPreviewHistorySavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
  final normalizedName = view.name.trim().toLowerCase();
  final normalizedScope =
      _normalizeCoachPayoutImportSavedViewVisibilityScope(view.visibilityScope);
  final normalizedView = CoachPayoutImportPreviewHistorySavedView(
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
  final updatedViews = <CoachPayoutImportPreviewHistorySavedView>[
    normalizedView,
    ...existingViews.where(
      (entry) =>
          entry.viewId != normalizedView.viewId &&
          !(entry.visibilityScope == normalizedScope &&
              entry.name.trim().toLowerCase() == normalizedName),
    ),
  ].map((entry) {
    if (normalizedView.isDefault &&
        entry.viewId != normalizedView.viewId &&
        entry.visibilityScope == 'personal') {
      return CoachPayoutImportPreviewHistorySavedView(
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
    return entry;
  }).toList(growable: false)
    ..sort((left, right) {
      final defaultCompare =
          (right.isDefault ? 1 : 0).compareTo(left.isDefault ? 1 : 0);
      if (defaultCompare != 0) {
        return defaultCompare;
      }
      return right.updatedAtIso.compareTo(left.updatedAtIso);
    });
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

Future<List<CoachPayoutImportPreviewHistorySavedView>>
    deleteCoachPayoutImportPreviewHistorySavedView({
  required String baseUrl,
  required String viewId,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachPayoutImportPreviewHistorySavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existingViews = _loadCoachPayoutImportPreviewHistorySavedViewsFromPrefs(
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

String _normalizeCoachPayoutImportPreviewHistoryOperatorId(String? value) {
  final normalized = (value ?? '').trim();
  return normalized.isEmpty ? 'all' : normalized;
}

String _normalizeCoachPayoutImportSavedViewVisibilityScope(String? value) {
  return switch ((value ?? '').trim().toLowerCase()) {
    'shared_ops' => 'shared_ops',
    _ => 'personal',
  };
}

Future<String> _coachPayoutImportPreviewHistoryFilterScopedPrefKey({
  required String baseUrl,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final scope = await _coachPayoutImportPreviewHistoryFilterScope(
    baseUrl: baseUrl,
    sp: sp,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachPayoutImportPreviewHistoryFilterScopedPrefKeyPrefix$suffix';
}

Future<String> _coachPayoutImportPreviewHistorySavedViewsScopedPrefKey({
  required String baseUrl,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final scope = await _coachPayoutImportPreviewHistoryFilterScope(
    baseUrl: baseUrl,
    sp: sp,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachPayoutImportPreviewHistorySavedViewsScopedPrefKeyPrefix$suffix';
}

List<CoachPayoutImportPreviewHistorySavedView>
    _loadCoachPayoutImportPreviewHistorySavedViewsFromPrefs({
  required SharedPreferences prefs,
  required String key,
}) {
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return const <CoachPayoutImportPreviewHistorySavedView>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <CoachPayoutImportPreviewHistorySavedView>[];
    }
    final views = decoded
        .map(CoachPayoutImportPreviewHistorySavedView.fromJson)
        .whereType<CoachPayoutImportPreviewHistorySavedView>()
        .toList(growable: false)
      ..sort((left, right) {
        final defaultCompare =
            (right.isDefault ? 1 : 0).compareTo(left.isDefault ? 1 : 0);
        if (defaultCompare != 0) {
          return defaultCompare;
        }
        return right.updatedAtIso.compareTo(left.updatedAtIso);
      });
    return views;
  } catch (_) {
    return const <CoachPayoutImportPreviewHistorySavedView>[];
  }
}

Future<String> _coachPayoutImportPreviewHistoryFilterScope({
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
