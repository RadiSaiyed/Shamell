import '../account_privilege_store.dart';

const Set<String> shamellPaymentsOperatorRoles = <String>{
  'merchant',
  'qr_seller',
  'seller',
};

const Set<String> shamellPaymentsCashAgentRoles = <String>{
  'cashout_operator',
};

const Set<String> shamellPaymentsAdminRoles = <String>{
  'admin',
  'superadmin',
};

const Set<String> shamellPaymentsFinanceRoles = <String>{
  'finance',
  'bi_audit_read_only',
  'admin',
  'superadmin',
};

const Set<String> shamellPaymentsCreditRoles = <String>{
  'finance',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> shamellPaymentsSuperadminRoles = <String>{
  'superadmin',
};

bool shamellHasPaymentsOperatorAccess(Iterable<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellPaymentsOperatorRoles.contains(role) ||
        role.startsWith('operator_')) {
      return true;
    }
  }
  return false;
}

bool shamellHasPaymentsCashAgentAccess(Iterable<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellPaymentsCashAgentRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasPaymentsAdminAccess(Iterable<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellPaymentsAdminRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasPaymentsFinanceAccess(Iterable<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellPaymentsFinanceRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasPaymentsCreditAccess(Iterable<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellPaymentsCreditRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool shamellHasPaymentsSuperadminAccess(Iterable<String> roles) {
  for (final rawRole in roles) {
    final role = rawRole.trim().toLowerCase();
    if (shamellPaymentsSuperadminRoles.contains(role)) {
      return true;
    }
  }
  return false;
}

bool _paymentsSnapshotHasPermission(
  AccountPrivilegeSnapshot snapshot,
  String permission,
) {
  return snapshot.can(permission, product: 'wallet') ||
      snapshot.hasPermission(permission);
}

bool _paymentsSnapshotHasAnyPermission(
  AccountPrivilegeSnapshot snapshot,
  Iterable<String> permissions,
) {
  for (final permission in permissions) {
    if (_paymentsSnapshotHasPermission(snapshot, permission)) {
      return true;
    }
  }
  return false;
}

bool shamellHasPaymentsOperatorSnapshotAccess(
    AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _paymentsSnapshotHasAnyPermission(snapshot, const <String>[
      'wallet.operator.read',
      'cash.agent.read',
    ]);
  }
  return shamellHasPaymentsOperatorAccess(snapshot.roles) ||
      shamellHasPaymentsCashAgentAccess(snapshot.roles);
}

bool shamellHasPaymentsCashAgentSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _paymentsSnapshotHasAnyPermission(snapshot, const <String>[
      'cash.agent.read',
      'cash.agent.redeem.write',
    ]);
  }
  return shamellHasPaymentsCashAgentAccess(snapshot.roles);
}

bool shamellHasPaymentsAdminSnapshotAccess(AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _paymentsSnapshotHasPermission(snapshot, 'wallet.admin.read');
  }
  if (shamellHasPaymentsAdminAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

bool shamellHasPaymentsFinanceSnapshotAccess(
    AccountPrivilegeSnapshot snapshot) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _paymentsSnapshotHasPermission(snapshot, 'wallet.finance.read');
  }
  if (shamellHasPaymentsFinanceAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

bool shamellHasPaymentsCreditSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _paymentsSnapshotHasPermission(snapshot, 'wallet.credit.write');
  }
  if (shamellHasPaymentsCreditAccess(snapshot.roles)) {
    return true;
  }
  return snapshot.isAdmin;
}

bool shamellHasPaymentsSuperadminSnapshotAccess(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _paymentsSnapshotHasAnyPermission(snapshot, const <String>[
      'wallet.admin.write',
      'wallet.finance.write',
      'wallet.guardrails.write',
    ]);
  }
  return shamellHasPaymentsSuperadminAccess(snapshot.roles);
}
