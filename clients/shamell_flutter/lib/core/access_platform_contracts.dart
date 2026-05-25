import 'account_privilege_store.dart';

const Set<String> _controlAccessAssignmentLegacyRoles = <String>{
  'admin',
  'superadmin',
  'ops',
  'seller',
};

bool _snapshotHasAccessAdminProduct(AccountPrivilegeSnapshot snapshot) {
  return snapshot.hasProductAccess('access') ||
      snapshot.hasProductAccess('access_admin');
}

bool shamellHasControlAccessAssignmentReadSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return snapshot.hasPermission('access.assignment.read') ||
        snapshot.hasPermission('access.assignment.write');
  }
  if (snapshot.products.isNotEmpty) {
    return _snapshotHasAccessAdminProduct(snapshot) ||
        snapshot.hasProductAccess('control');
  }
  return snapshot.roles.any((role) {
    final normalized = role.trim().toLowerCase();
    return _controlAccessAssignmentLegacyRoles.contains(normalized);
  });
}

bool shamellHasControlAccessAssignmentWriteSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return snapshot.hasPermission('access.assignment.write');
  }
  if (snapshot.products.isNotEmpty) {
    return _snapshotHasAccessAdminProduct(snapshot);
  }
  return snapshot.roles.any((role) {
    final normalized = role.trim().toLowerCase();
    return _controlAccessAssignmentLegacyRoles.contains(normalized);
  });
}

bool shamellHasOfficialDashboardReadSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
  String officialAccountId,
) {
  final normalizedOfficialAccountId = officialAccountId.trim().toLowerCase();
  if (normalizedOfficialAccountId.isEmpty) {
    return false;
  }
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return snapshot.can(
          'official.dashboard.read',
          product: 'official_accounts',
          officialAccountId: normalizedOfficialAccountId,
        ) ||
        snapshot.can(
          'official.dashboard.write',
          product: 'official_accounts',
          officialAccountId: normalizedOfficialAccountId,
        );
  }
  if (snapshot.products.isNotEmpty) {
    return snapshot.hasProductAccess('official_accounts') &&
        (_legacyOfficialDashboardScopeAllowed(
              snapshot.roles,
              normalizedOfficialAccountId,
            ) ||
            snapshot.hasOfficialAccountScope(normalizedOfficialAccountId));
  }
  return _legacyOfficialDashboardScopeAllowed(
    snapshot.roles,
    normalizedOfficialAccountId,
  );
}

bool shamellHasOfficialDashboardWriteSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
  String officialAccountId,
) {
  final normalizedOfficialAccountId = officialAccountId.trim().toLowerCase();
  if (normalizedOfficialAccountId.isEmpty) {
    return false;
  }
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return snapshot.can(
      'official.dashboard.write',
      product: 'official_accounts',
      officialAccountId: normalizedOfficialAccountId,
    );
  }
  if (snapshot.products.isNotEmpty) {
    return snapshot.hasProductAccess('official_accounts') &&
        (_legacyOfficialDashboardScopeAllowed(
              snapshot.roles,
              normalizedOfficialAccountId,
            ) ||
            snapshot.hasOfficialAccountScope(normalizedOfficialAccountId));
  }
  return _legacyOfficialDashboardScopeAllowed(
    snapshot.roles,
    normalizedOfficialAccountId,
  );
}

bool _legacyOfficialDashboardScopeAllowed(
  Iterable<String> roles,
  String officialAccountId,
) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (role == 'admin' || role == 'superadmin') {
      return true;
    }
    if (!role.startsWith('official_owner:')) {
      continue;
    }
    final scope = role.substring('official_owner:'.length).trim();
    if (scope == '*' || scope == officialAccountId) {
      return true;
    }
  }
  return false;
}
