import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../base_url.dart';
import '../shamell_user_id.dart';

const String _coachCatalogImportRunFilterScopedPrefKeyPrefix =
    'coach.ops.catalog_import_run_filters.v1.';
const String _coachCatalogImportRunIssueFilterScopedPrefKeyPrefix =
    'coach.ops.catalog_import_run_issue_filters.v1.';
const String _coachCatalogImportRunSavedViewsScopedPrefKeyPrefix =
    'coach.ops.catalog_import_run_saved_views.v1.';
const String _coachCatalogImportRunIssueSavedViewsScopedPrefKeyPrefix =
    'coach.ops.catalog_import_run_issue_saved_views.v1.';

class CoachCatalogImportRunFilterPreferences {
  final String status;
  final String replayScope;
  final String issueSeverity;
  final String issueStage;

  const CoachCatalogImportRunFilterPreferences({
    this.status = 'all',
    this.replayScope = 'all',
    this.issueSeverity = 'all',
    this.issueStage = 'all',
  });

  static const empty = CoachCatalogImportRunFilterPreferences();

  bool get hasActiveFilters {
    return status.trim().toLowerCase() != 'all' ||
        replayScope.trim().toLowerCase() != 'all' ||
        issueSeverity.trim().toLowerCase() != 'all' ||
        issueStage.trim().toLowerCase() != 'all';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': _normalizeCatalogImportRunStatus(status),
      'replay_scope': _normalizeCatalogImportRunReplayScope(replayScope),
      'severity': _normalizeCatalogImportRunIssueSeverity(issueSeverity),
      'stage': _normalizeCatalogImportRunIssueStage(issueStage),
    };
  }

  static CoachCatalogImportRunFilterPreferences fromJson(Object? raw) {
    if (raw is! Map) {
      return empty;
    }
    return CoachCatalogImportRunFilterPreferences(
      status: _normalizeCatalogImportRunStatus(
        (raw['status'] ?? '').toString(),
      ),
      replayScope: _normalizeCatalogImportRunReplayScope(
        (raw['replay_scope'] ?? '').toString(),
      ),
      issueSeverity: _normalizeCatalogImportRunIssueSeverity(
        (raw['severity'] ?? '').toString(),
      ),
      issueStage: _normalizeCatalogImportRunIssueStage(
        (raw['stage'] ?? '').toString(),
      ),
    );
  }
}

class CoachCatalogImportRunSavedView {
  final String viewId;
  final String accountId;
  final String name;
  final String visibilityScope;
  final List<String> operatorIds;
  final CoachCatalogImportRunFilterPreferences preferences;
  final bool isDefault;
  final bool isFavorite;
  final String? lastUsedAtIso;
  final bool canManage;
  final String createdAtIso;
  final String updatedAtIso;

  const CoachCatalogImportRunSavedView({
    required this.viewId,
    this.accountId = '',
    required this.name,
    this.visibilityScope = 'personal',
    this.operatorIds = const <String>[],
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
      'visibility_scope': _normalizeCatalogSavedViewVisibilityScope(
        visibilityScope,
      ),
      'operator_ids': operatorIds,
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

  static CoachCatalogImportRunSavedView? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final viewId = (raw['view_id'] ?? '').toString().trim();
    final accountId = (raw['account_id'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();
    final visibilityScope = _normalizeCatalogSavedViewVisibilityScope(
      (raw['visibility_scope'] ?? '').toString(),
    );
    final operatorIds = _loadNormalizedStringList(raw['operator_ids']);
    final preferences = CoachCatalogImportRunFilterPreferences.fromJson(
      raw['preferences'],
    );
    final isDefault = raw['is_default'] == true;
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
    return CoachCatalogImportRunSavedView(
      viewId: viewId,
      accountId: accountId,
      name: name,
      visibilityScope: visibilityScope,
      operatorIds: operatorIds,
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

class CoachCatalogImportRunIssueFilterPreferences {
  final String severity;
  final String stage;

  const CoachCatalogImportRunIssueFilterPreferences({
    this.severity = 'all',
    this.stage = 'all',
  });

  static const empty = CoachCatalogImportRunIssueFilterPreferences();

  bool get hasActiveFilters {
    return severity.trim().toLowerCase() != 'all' ||
        stage.trim().toLowerCase() != 'all';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'severity': _normalizeCatalogImportRunIssueSeverity(severity),
      'stage': _normalizeCatalogImportRunIssueStage(stage),
    };
  }

  static CoachCatalogImportRunIssueFilterPreferences fromJson(Object? raw) {
    if (raw is! Map) {
      return empty;
    }
    return CoachCatalogImportRunIssueFilterPreferences(
      severity: _normalizeCatalogImportRunIssueSeverity(
        (raw['severity'] ?? '').toString(),
      ),
      stage: _normalizeCatalogImportRunIssueStage(
        (raw['stage'] ?? '').toString(),
      ),
    );
  }
}

class CoachCatalogImportRunIssueSavedView {
  final String viewId;
  final String accountId;
  final String name;
  final String visibilityScope;
  final List<String> operatorIds;
  final CoachCatalogImportRunIssueFilterPreferences preferences;
  final bool isDefault;
  final bool isFavorite;
  final String? lastUsedAtIso;
  final bool canManage;
  final String createdAtIso;
  final String updatedAtIso;

  const CoachCatalogImportRunIssueSavedView({
    required this.viewId,
    this.accountId = '',
    required this.name,
    this.visibilityScope = 'personal',
    this.operatorIds = const <String>[],
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
      'visibility_scope': _normalizeCatalogSavedViewVisibilityScope(
        visibilityScope,
      ),
      'operator_ids': operatorIds,
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

  static CoachCatalogImportRunIssueSavedView? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final viewId = (raw['view_id'] ?? '').toString().trim();
    final accountId = (raw['account_id'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();
    final visibilityScope = _normalizeCatalogSavedViewVisibilityScope(
      (raw['visibility_scope'] ?? '').toString(),
    );
    final operatorIds = _loadNormalizedStringList(raw['operator_ids']);
    final preferences = CoachCatalogImportRunIssueFilterPreferences.fromJson(
      raw['preferences'],
    );
    final isDefault = raw['is_default'] == true;
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
    return CoachCatalogImportRunIssueSavedView(
      viewId: viewId,
      accountId: accountId,
      name: name,
      visibilityScope: visibilityScope,
      operatorIds: operatorIds,
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

Future<CoachCatalogImportRunFilterPreferences>
    loadCoachCatalogImportRunFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return CoachCatalogImportRunFilterPreferences.empty;
  }
  try {
    return CoachCatalogImportRunFilterPreferences.fromJson(jsonDecode(raw));
  } catch (_) {
    return CoachCatalogImportRunFilterPreferences.empty;
  }
}

Future<void> saveCoachCatalogImportRunFilterPreferences({
  required String baseUrl,
  required CoachCatalogImportRunFilterPreferences preferences,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  await prefs.setString(key, jsonEncode(preferences.toJson()));
}

Future<void> clearCoachCatalogImportRunFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  await prefs.remove(key);
}

Future<CoachCatalogImportRunIssueFilterPreferences>
    loadCoachCatalogImportRunIssueFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunIssueFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return CoachCatalogImportRunIssueFilterPreferences.empty;
  }
  try {
    return CoachCatalogImportRunIssueFilterPreferences.fromJson(
        jsonDecode(raw));
  } catch (_) {
    return CoachCatalogImportRunIssueFilterPreferences.empty;
  }
}

Future<void> saveCoachCatalogImportRunIssueFilterPreferences({
  required String baseUrl,
  required CoachCatalogImportRunIssueFilterPreferences preferences,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunIssueFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  await prefs.setString(key, jsonEncode(preferences.toJson()));
}

Future<void> clearCoachCatalogImportRunIssueFilterPreferences({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunIssueFilterScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  await prefs.remove(key);
}

Future<List<CoachCatalogImportRunIssueSavedView>>
    loadCoachCatalogImportRunIssueSavedViews({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunIssueSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  return _loadCoachCatalogImportRunIssueSavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
}

Future<List<CoachCatalogImportRunIssueSavedView>>
    upsertCoachCatalogImportRunIssueSavedView({
  required String baseUrl,
  required CoachCatalogImportRunIssueSavedView view,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
  int maxViews = 8,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunIssueSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existingViews = _loadCoachCatalogImportRunIssueSavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
  final normalizedName = view.name.trim().toLowerCase();
  final normalizedScope = _normalizeCatalogSavedViewVisibilityScope(
    view.visibilityScope,
  );
  final persistedView = CoachCatalogImportRunIssueSavedView(
    viewId: view.viewId,
    accountId: view.accountId,
    name: view.name,
    visibilityScope: normalizedScope,
    operatorIds: view.operatorIds,
    preferences: view.preferences,
    isDefault: view.isDefault && normalizedScope == 'personal',
    isFavorite: view.isFavorite,
    lastUsedAtIso: view.lastUsedAtIso,
    canManage: view.canManage,
    createdAtIso: view.createdAtIso,
    updatedAtIso: view.updatedAtIso,
  );
  final remainingViews = existingViews
      .where(
        (entry) =>
            entry.viewId != persistedView.viewId &&
            !(entry.name.trim().toLowerCase() == normalizedName &&
                entry.visibilityScope == normalizedScope),
      )
      .map(
        (entry) => persistedView.isDefault &&
                entry.isDefault &&
                entry.visibilityScope == 'personal'
            ? CoachCatalogImportRunIssueSavedView(
                viewId: entry.viewId,
                accountId: entry.accountId,
                name: entry.name,
                visibilityScope: entry.visibilityScope,
                operatorIds: entry.operatorIds,
                preferences: entry.preferences,
                isDefault: false,
                isFavorite: entry.isFavorite,
                lastUsedAtIso: entry.lastUsedAtIso,
                canManage: entry.canManage,
                createdAtIso: entry.createdAtIso,
                updatedAtIso: entry.updatedAtIso,
              )
            : entry,
      )
      .toList(growable: false);
  final updatedViews = <CoachCatalogImportRunIssueSavedView>[
    persistedView,
    ...remainingViews,
  ]..sort((left, right) {
      if (left.isDefault != right.isDefault) {
        return left.isDefault ? -1 : 1;
      }
      final scopeOrder = left.visibilityScope.compareTo(right.visibilityScope);
      if (scopeOrder != 0) {
        return scopeOrder;
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

Future<List<CoachCatalogImportRunIssueSavedView>>
    deleteCoachCatalogImportRunIssueSavedView({
  required String baseUrl,
  required String viewId,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunIssueSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existingViews = _loadCoachCatalogImportRunIssueSavedViewsFromPrefs(
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

Future<List<CoachCatalogImportRunSavedView>>
    loadCoachCatalogImportRunSavedViews({
  required String baseUrl,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  return _loadCoachCatalogImportRunSavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
}

Future<List<CoachCatalogImportRunSavedView>>
    upsertCoachCatalogImportRunSavedView({
  required String baseUrl,
  required CoachCatalogImportRunSavedView view,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
  int maxViews = 8,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existingViews = _loadCoachCatalogImportRunSavedViewsFromPrefs(
    prefs: prefs,
    key: key,
  );
  final normalizedName = view.name.trim().toLowerCase();
  final normalizedScope = _normalizeCatalogSavedViewVisibilityScope(
    view.visibilityScope,
  );
  final persistedView = CoachCatalogImportRunSavedView(
    viewId: view.viewId,
    accountId: view.accountId,
    name: view.name,
    visibilityScope: normalizedScope,
    operatorIds: view.operatorIds,
    preferences: view.preferences,
    isDefault: view.isDefault && normalizedScope == 'personal',
    isFavorite: view.isFavorite,
    lastUsedAtIso: view.lastUsedAtIso,
    canManage: view.canManage,
    createdAtIso: view.createdAtIso,
    updatedAtIso: view.updatedAtIso,
  );
  final remainingViews = existingViews
      .where(
        (entry) =>
            entry.viewId != persistedView.viewId &&
            !(entry.name.trim().toLowerCase() == normalizedName &&
                entry.visibilityScope == normalizedScope),
      )
      .map(
        (entry) => persistedView.isDefault &&
                entry.isDefault &&
                entry.visibilityScope == 'personal'
            ? CoachCatalogImportRunSavedView(
                viewId: entry.viewId,
                accountId: entry.accountId,
                name: entry.name,
                visibilityScope: entry.visibilityScope,
                operatorIds: entry.operatorIds,
                preferences: entry.preferences,
                isDefault: false,
                isFavorite: entry.isFavorite,
                lastUsedAtIso: entry.lastUsedAtIso,
                canManage: entry.canManage,
                createdAtIso: entry.createdAtIso,
                updatedAtIso: entry.updatedAtIso,
              )
            : entry,
      )
      .toList(growable: false);
  final updatedViews = <CoachCatalogImportRunSavedView>[
    persistedView,
    ...remainingViews,
  ]..sort((left, right) {
      if (left.isDefault != right.isDefault) {
        return left.isDefault ? -1 : 1;
      }
      final scopeOrder = left.visibilityScope.compareTo(right.visibilityScope);
      if (scopeOrder != 0) {
        return scopeOrder;
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

Future<List<CoachCatalogImportRunSavedView>>
    deleteCoachCatalogImportRunSavedView({
  required String baseUrl,
  required String viewId,
  SharedPreferences? sp,
  String? shamellUserIdOverride,
}) async {
  final prefs = sp ?? await SharedPreferences.getInstance();
  final key = await _coachCatalogImportRunSavedViewsScopedPrefKey(
    baseUrl: baseUrl,
    sp: prefs,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final existingViews = _loadCoachCatalogImportRunSavedViewsFromPrefs(
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

String _normalizeCatalogImportRunStatus(String value) {
  return switch (value.trim().toLowerCase()) {
    'failed' || 'running' || 'succeeded' => value.trim().toLowerCase(),
    _ => 'all',
  };
}

String _normalizeCatalogImportRunReplayScope(String value) {
  return switch (value.trim().toLowerCase()) {
    'attention' ||
    'replays_only' ||
    'with_replays' =>
      value.trim().toLowerCase(),
    _ => 'all',
  };
}

String _normalizeCatalogImportRunIssueSeverity(String value) {
  return switch (value.trim().toLowerCase()) {
    'error' || 'warning' || 'info' => value.trim().toLowerCase(),
    _ => 'all',
  };
}

String _normalizeCatalogImportRunIssueStage(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'all') {
    return 'all';
  }
  return normalized;
}

String _normalizeCatalogSavedViewVisibilityScope(String value) {
  return switch (value.trim().toLowerCase()) {
    'shared_ops' => 'shared_ops',
    _ => 'personal',
  };
}

List<String> _loadNormalizedStringList(Object? raw) {
  if (raw is! List) {
    return const <String>[];
  }
  final values = raw
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toSet()
      .toList(growable: true)
    ..sort();
  return values;
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

Future<String> _coachCatalogImportRunFilterScopedPrefKey({
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
  final scope = '$origin|$userScope';
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachCatalogImportRunFilterScopedPrefKeyPrefix$suffix';
}

Future<String> _coachCatalogImportRunIssueFilterScopedPrefKey({
  required String baseUrl,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final scope = await _coachCatalogImportRunScope(
    baseUrl: baseUrl,
    sp: sp,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachCatalogImportRunIssueFilterScopedPrefKeyPrefix$suffix';
}

Future<String> _coachCatalogImportRunSavedViewsScopedPrefKey({
  required String baseUrl,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final scope = await _coachCatalogImportRunScope(
    baseUrl: baseUrl,
    sp: sp,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachCatalogImportRunSavedViewsScopedPrefKeyPrefix$suffix';
}

Future<String> _coachCatalogImportRunIssueSavedViewsScopedPrefKey({
  required String baseUrl,
  required SharedPreferences sp,
  String? shamellUserIdOverride,
}) async {
  final scope = await _coachCatalogImportRunScope(
    baseUrl: baseUrl,
    sp: sp,
    shamellUserIdOverride: shamellUserIdOverride,
  );
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$_coachCatalogImportRunIssueSavedViewsScopedPrefKeyPrefix$suffix';
}

List<CoachCatalogImportRunSavedView>
    _loadCoachCatalogImportRunSavedViewsFromPrefs({
  required SharedPreferences prefs,
  required String key,
}) {
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return const <CoachCatalogImportRunSavedView>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <CoachCatalogImportRunSavedView>[];
    }
    final views = decoded
        .map(CoachCatalogImportRunSavedView.fromJson)
        .whereType<CoachCatalogImportRunSavedView>()
        .toList(growable: false)
      ..sort((left, right) => right.updatedAtIso.compareTo(left.updatedAtIso));
    return views;
  } catch (_) {
    return const <CoachCatalogImportRunSavedView>[];
  }
}

List<CoachCatalogImportRunIssueSavedView>
    _loadCoachCatalogImportRunIssueSavedViewsFromPrefs({
  required SharedPreferences prefs,
  required String key,
}) {
  final raw = (prefs.getString(key) ?? '').trim();
  if (raw.isEmpty) {
    return const <CoachCatalogImportRunIssueSavedView>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <CoachCatalogImportRunIssueSavedView>[];
    }
    final views = decoded
        .map(CoachCatalogImportRunIssueSavedView.fromJson)
        .whereType<CoachCatalogImportRunIssueSavedView>()
        .toList(growable: false)
      ..sort((left, right) => right.updatedAtIso.compareTo(left.updatedAtIso));
    return views;
  } catch (_) {
    return const <CoachCatalogImportRunIssueSavedView>[];
  }
}

Future<String> _coachCatalogImportRunScope({
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
