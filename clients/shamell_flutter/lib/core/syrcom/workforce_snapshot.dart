import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../base_url.dart';
import '../session_cookie_store.dart';

/// One `(scope_kind, scope_value)` pair attached to a role or permission grant.
///
/// Mirrors the BFF `WorkforceScopeOut` shape. `scope_value` is null only for
/// `kind == "platform"`; every other kind carries a non-empty value.
class WorkforceScope {
  final String kind;
  final String? value;

  const WorkforceScope({required this.kind, this.value});

  factory WorkforceScope.fromJson(Map<String, dynamic> json) {
    return WorkforceScope(
      kind: (json['scope_kind'] as String?) ?? '',
      value: json['scope_value'] as String?,
    );
  }

  @override
  String toString() => value == null ? kind : '$kind:$value';
}

/// One organization the calling workforce account is a member of.
class WorkforceMembership {
  final String organizationId;
  final String organizationDisplayName;
  final String orgKind;
  final bool isPrimary;
  final String status;

  const WorkforceMembership({
    required this.organizationId,
    required this.organizationDisplayName,
    required this.orgKind,
    required this.isPrimary,
    required this.status,
  });

  factory WorkforceMembership.fromJson(Map<String, dynamic> json) {
    return WorkforceMembership(
      organizationId: (json['organization_id'] as String?) ?? '',
      organizationDisplayName:
          (json['organization_display_name'] as String?) ?? '',
      orgKind: (json['org_kind'] as String?) ?? '',
      isPrimary: json['is_primary'] == true,
      status: (json['status'] as String?) ?? '',
    );
  }
}

/// One derived permission and the scopes it's valid in.
class WorkforcePermissionGrant {
  final String permissionId;
  final List<WorkforceScope> scopes;

  const WorkforcePermissionGrant({
    required this.permissionId,
    required this.scopes,
  });

  factory WorkforcePermissionGrant.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['scopes'];
    final scopes = <WorkforceScope>[];
    if (rawScopes is List) {
      for (final entry in rawScopes) {
        if (entry is Map<String, dynamic>) {
          scopes.add(WorkforceScope.fromJson(entry));
        }
      }
    }
    return WorkforcePermissionGrant(
      permissionId: (json['permission_id'] as String?) ?? '',
      scopes: scopes,
    );
  }
}

/// Snapshot of the calling workforce account's permissions + memberships.
///
/// Built from either:
///   • `GET /me/permissions` → fills `permissions` + the workforce metadata
///   • `GET /me/access-context` → fills `organizations` + role-level data
///
/// `snapshotVersion` is a stable digest from the BFF — two snapshots with the
/// same version describe the exact same underlying assignments. Clients can
/// use it to skip re-renders.
class WorkforceAccessSnapshot {
  final String workforceAccountId;
  final String? humanId;
  final String? accountType;
  final String? status;
  final String snapshotVersion;
  final List<WorkforceMembership> organizations;
  final List<WorkforcePermissionGrant> permissions;

  const WorkforceAccessSnapshot({
    required this.workforceAccountId,
    required this.snapshotVersion,
    this.humanId,
    this.accountType,
    this.status,
    this.organizations = const <WorkforceMembership>[],
    this.permissions = const <WorkforcePermissionGrant>[],
  });

  /// Does this snapshot grant the given permission?
  ///
  /// Scope filtering is intentionally not exposed yet — the BFF returns the
  /// scopes attached to each grant, but the SyrCom Workbench's first
  /// permission-aware iteration only cares about "is this permission granted
  /// at all". A scope-aware variant (`canForScope`) lands when individual
  /// modules need to enforce e.g. organization-specific behavior.
  bool can(String permissionId) {
    return permissions.any((p) => p.permissionId == permissionId);
  }

  /// Try to parse a `/me/permissions` response. Returns null when the
  /// response is missing the `workforce_permissions` block — that's the
  /// consumer / legacy case where there is no workforce identity.
  static WorkforceAccessSnapshot? tryFromMePermissionsJson(
    Map<String, dynamic> root,
  ) {
    final wp = root['workforce_permissions'];
    if (wp is! Map<String, dynamic>) return null;
    final accountId = wp['workforce_account_id'];
    final version = wp['snapshot_version'];
    if (accountId is! String || accountId.isEmpty) return null;
    if (version is! String || version.isEmpty) return null;
    final rawPerms = wp['permissions'];
    final perms = <WorkforcePermissionGrant>[];
    if (rawPerms is List) {
      for (final entry in rawPerms) {
        if (entry is Map<String, dynamic>) {
          perms.add(WorkforcePermissionGrant.fromJson(entry));
        }
      }
    }
    return WorkforceAccessSnapshot(
      workforceAccountId: accountId,
      snapshotVersion: version,
      permissions: perms,
    );
  }

  /// Merge memberships and account metadata from a `/me/access-context`
  /// response into an existing snapshot. Returns the merged snapshot, or
  /// the original if the response has no workforce block.
  WorkforceAccessSnapshot mergedWithAccessContextJson(
    Map<String, dynamic> root,
  ) {
    final wf = root['workforce'];
    if (wf is! Map<String, dynamic>) return this;
    final rawOrgs = wf['organizations'];
    final orgs = <WorkforceMembership>[];
    if (rawOrgs is List) {
      for (final entry in rawOrgs) {
        if (entry is Map<String, dynamic>) {
          orgs.add(WorkforceMembership.fromJson(entry));
        }
      }
    }
    return WorkforceAccessSnapshot(
      workforceAccountId:
          (wf['workforce_account_id'] as String?) ?? workforceAccountId,
      humanId: (wf['human_id'] as String?) ?? humanId,
      accountType: (wf['account_type'] as String?) ?? accountType,
      status: (wf['status'] as String?) ?? status,
      snapshotVersion: (wf['snapshot_version'] as String?) ?? snapshotVersion,
      organizations: orgs,
      permissions: permissions,
    );
  }
}

/// HTTP client for the BFF `/me/*` workforce-IAM endpoints.
///
/// Modeled after the existing `RideRatingApi` pattern — same session-cookie
/// handling, same `secureApiChildUri()` builder, same optional injectable
/// `http.Client` for tests. Returns null on any error so callers can fall
/// through to the legacy permissive UI rather than blocking the surface.
class WorkforceAccessApi {
  static const Duration _requestTimeout = Duration(seconds: 12);

  final String? baseUrl;
  final http.Client? _httpClient;

  const WorkforceAccessApi({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  /// Fetch the workforce permission snapshot. Returns null when:
  ///   • there is no usable base URL configured
  ///   • the BFF returns a non-2xx response (including 401 → not signed in)
  ///   • the session is a consumer session with no workforce block
  ///   • the network call fails or times out
  Future<WorkforceAccessSnapshot?> fetchPermissions() async {
    final base = baseUrl;
    if (base == null || base.isEmpty) return null;
    final uri = secureApiChildUri(
      baseUrl: base,
      pathSegments: const <String>['me', 'permissions'],
    );
    if (uri == null) return null;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(base);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;
      return WorkforceAccessSnapshot.tryFromMePermissionsJson(decoded);
    } catch (_) {
      return null;
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Fetch the workforce access context (memberships + roles) and merge it
  /// into an already-loaded permissions snapshot. Returns the original
  /// snapshot if the access-context call fails — the workbench can still
  /// gate tiles correctly even without the organization metadata.
  Future<WorkforceAccessSnapshot> enrichWithAccessContext(
    WorkforceAccessSnapshot snapshot,
  ) async {
    final base = baseUrl;
    if (base == null || base.isEmpty) return snapshot;
    final uri = secureApiChildUri(
      baseUrl: base,
      pathSegments: const <String>['me', 'access-context'],
    );
    if (uri == null) return snapshot;
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final headers = await shamellSessionHeadersForBaseUrl(base);
      final resp =
          await client.get(uri, headers: headers).timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return snapshot;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return snapshot;
      return snapshot.mergedWithAccessContextJson(decoded);
    } catch (_) {
      return snapshot;
    } finally {
      if (closeClient) client.close();
    }
  }
}
