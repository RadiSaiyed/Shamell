import 'package:flutter/material.dart';

import 'account_privilege_store.dart';
import 'base_url.dart';
import 'capabilities.dart';
import 'payments/payments_platform_contracts.dart';

const List<String> _opsConsolePermissions = <String>[
  'access.assignment.read',
  'audit.export.read',
  'coach.catalog.read',
  'coach.manifest.read',
  'coach.operator.read',
  'coach.settlement.read',
  'control.dashboard.read',
  'rides.dispatch.read',
  'rides.finance.read',
  'rides.operator.read',
  'rides.support.read',
  'wallet.credit.write',
  'wallet.finance.read',
  'wallet.admin.read',
];

const List<String> _adminConsolePermissions = <String>[
  'access.assignment.read',
  'audit.export.read',
  'coach.admin.read',
  'coach.admin.write',
  'control.dashboard.read',
  'rides.admin.read',
  'rides.admin.write',
];

const List<String> _coachBoardingPermissions = <String>[
  'coach.boarding.scan.write',
  'coach.manifest.read',
];

const Set<String> _coachBoardingAllowedRoles = <String>{
  'driver',
  'ride_driver',
  'driver_ops',
  'city_manager',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> _coachAdminAllowedRoles = <String>{
  'admin',
  'superadmin',
  'ops',
  'seller',
};

const Set<String> _coachOperatorAllowedRoles = <String>{
  'driver_ops',
  'city_manager',
  'support_l1',
  'support_l2',
  'finance',
  'compliance_risk',
  'marketing',
  'bi_audit_read_only',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> _coachOperatorFinanceMutationRoles = <String>{
  'finance',
  'admin',
  'superadmin',
  'ops',
};

const Set<String> _coachOperatorCatalogMutationRoles = <String>{
  'city_manager',
  'admin',
  'superadmin',
  'ops',
};

String _normalizeDashboardPolicyBaseUrl(String baseUrl) {
  final rawBaseUrl = baseUrl.trim();
  if (rawBaseUrl.isEmpty) {
    return '';
  }
  return normalizeSecureApiBaseUrl(rawBaseUrl) ?? rawBaseUrl;
}

bool _hasAnyNormalizedRole(
  List<String> roles,
  Set<String> allowedRoles,
) {
  for (final role in roles) {
    if (allowedRoles.contains(role.trim().toLowerCase())) {
      return true;
    }
  }
  return false;
}

bool _hasOpsRole(List<String> roles) {
  if (roles
      .any((role) => role == 'admin' || role == 'seller' || role == 'ops')) {
    return true;
  }
  return roles.any((role) => role.startsWith('operator_'));
}

bool _hasSuperadminRole(List<String> roles) {
  return roles.any((role) => role == 'seller' || role == 'ops');
}

bool _hasAdminRole(List<String> roles) {
  if (_hasSuperadminRole(roles)) {
    return true;
  }
  return roles.contains('admin');
}

String? _permissionProduct(String permission) {
  if (permission.startsWith('access.')) return 'access';
  if (permission.startsWith('audit.')) return 'audit';
  if (permission.startsWith('coach.')) return 'coach';
  if (permission.startsWith('control.')) return 'control';
  if (permission.startsWith('official.')) return 'official_accounts';
  if (permission.startsWith('rides.')) return 'rides';
  if (permission.startsWith('wallet.')) return 'wallet';
  return null;
}

bool _snapshotHasAnyScopedPermission(
  AccountPrivilegeSnapshot snapshot,
  Iterable<String> permissions,
) {
  for (final permission in permissions) {
    final product = _permissionProduct(permission);
    if (product != null) {
      if (snapshot.can(permission, product: product)) {
        return true;
      }
      continue;
    }
    if (snapshot.hasPermission(permission)) {
      return true;
    }
  }
  return false;
}

bool _snapshotHasAnyProductAccess(
  AccountPrivilegeSnapshot snapshot,
  Iterable<String> products,
) {
  for (final product in products) {
    if (snapshot.hasProductAccess(product)) {
      return true;
    }
  }
  return false;
}

bool shamellDashboardAllowsOpsConsoleSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _snapshotHasAnyScopedPermission(snapshot, _opsConsolePermissions) ||
        _snapshotHasAnyScopedPermission(snapshot, _adminConsolePermissions);
  }
  if (snapshot.products.isNotEmpty) {
    return _snapshotHasAnyProductAccess(snapshot, const <String>[
      'access',
      'audit',
      'coach',
      'control',
      'rides',
      'wallet',
    ]);
  }
  return _hasOpsRole(snapshot.roles);
}

bool shamellDashboardAllowsAdminConsoleSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _snapshotHasAnyScopedPermission(snapshot, _adminConsolePermissions);
  }
  if (snapshot.products.isNotEmpty) {
    return _snapshotHasAnyProductAccess(snapshot, const <String>[
      'access',
      'audit',
      'coach',
      'control',
      'rides',
    ]);
  }
  return _hasAdminRole(snapshot.roles);
}

bool shamellDashboardAllowsCoachBoardingSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return _snapshotHasAnyScopedPermission(snapshot, _coachBoardingPermissions);
  }
  return _hasAnyNormalizedRole(snapshot.roles, _coachBoardingAllowedRoles);
}

bool shamellDashboardAllowsCoachAdminConsoleSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin || snapshot.hasPermission('coach.admin.read')) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return false;
  }
  return _hasAnyNormalizedRole(snapshot.roles, _coachAdminAllowedRoles);
}

bool shamellDashboardAllowsCoachOperatorConsoleSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin ||
      snapshot.hasPermission('coach.catalog.read') ||
      snapshot.hasPermission('coach.operator.read')) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return false;
  }
  return _hasAnyNormalizedRole(snapshot.roles, _coachOperatorAllowedRoles);
}

bool shamellDashboardAllowsCoachOperatorFinanceMutationsSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin ||
      snapshot.hasPermission('coach.settlement.write')) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return false;
  }
  return _hasAnyNormalizedRole(
    snapshot.roles,
    _coachOperatorFinanceMutationRoles,
  );
}

bool shamellDashboardAllowsCoachOperatorCatalogMutationsSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin ||
      snapshot.hasPermission('coach.operator.config.write')) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return false;
  }
  return _hasAnyNormalizedRole(
    snapshot.roles,
    _coachOperatorCatalogMutationRoles,
  );
}

bool shamellDashboardAllowsSuperadminDashboardSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  if (snapshot.isSuperadmin) {
    return true;
  }
  if (snapshot.permissions.isNotEmpty) {
    return snapshot.can('control.dashboard.read', product: 'control');
  }
  return false;
}

bool shamellDashboardAllowsPaymentsOperatorSurfaceSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  return shamellHasPaymentsOperatorSnapshotAccess(snapshot) ||
      shamellHasPaymentsAdminSnapshotAccess(snapshot) ||
      shamellHasPaymentsFinanceSnapshotAccess(snapshot) ||
      shamellHasPaymentsCreditSnapshotAccess(snapshot) ||
      shamellHasPaymentsSuperadminSnapshotAccess(snapshot);
}

bool shamellDashboardAllowsPaymentsCashRedeemSurfaceSnapshot(
  AccountPrivilegeSnapshot snapshot,
) {
  return shamellDashboardAllowsPaymentsOperatorSurfaceSnapshot(snapshot) ||
      shamellHasPaymentsCashAgentSnapshotAccess(snapshot);
}

@immutable
class ShamellDashboardPolicy {
  final String baseUrl;
  final AccountPrivilegeSnapshot privilegeSnapshot;
  final ShamellCapabilities capabilities;

  const ShamellDashboardPolicy({
    required this.baseUrl,
    required this.privilegeSnapshot,
    required this.capabilities,
  });

  static Future<ShamellDashboardPolicy> loadForBaseUrl(String baseUrl) async {
    final normalizedBaseUrl = _normalizeDashboardPolicyBaseUrl(baseUrl);
    final results = await Future.wait<Object>(<Future<Object>>[
      loadAccountPrivilegeSnapshotForBaseUrl(baseUrl),
      ShamellCapabilities.loadForBaseUrl(baseUrl),
    ]);
    return ShamellDashboardPolicy(
      baseUrl: normalizedBaseUrl,
      privilegeSnapshot: results[0] as AccountPrivilegeSnapshot,
      capabilities: results[1] as ShamellCapabilities,
    );
  }

  bool matchesBaseUrl(String value) {
    final normalizedBaseUrl = _normalizeDashboardPolicyBaseUrl(value);
    return normalizedBaseUrl.isNotEmpty && normalizedBaseUrl == baseUrl;
  }

  bool get allowsOpsConsole {
    return shamellDashboardAllowsOpsConsoleSnapshot(privilegeSnapshot);
  }

  bool get allowsAdminConsole {
    return shamellDashboardAllowsAdminConsoleSnapshot(privilegeSnapshot);
  }

  bool get allowsCoachBoardingConsole {
    return capabilities.coach &&
        shamellDashboardAllowsCoachBoardingSnapshot(privilegeSnapshot);
  }

  bool get allowsCoachAdminConsole {
    return capabilities.coach &&
        shamellDashboardAllowsCoachAdminConsoleSnapshot(privilegeSnapshot);
  }

  bool get allowsCoachOperatorConsole {
    return capabilities.coach &&
        shamellDashboardAllowsCoachOperatorConsoleSnapshot(privilegeSnapshot);
  }

  bool get allowsCoachOperatorFinanceMutations {
    return capabilities.coach &&
        shamellDashboardAllowsCoachOperatorFinanceMutationsSnapshot(
          privilegeSnapshot,
        );
  }

  bool get allowsCoachOperatorCatalogMutations {
    return capabilities.coach &&
        shamellDashboardAllowsCoachOperatorCatalogMutationsSnapshot(
          privilegeSnapshot,
        );
  }

  bool get allowsSuperadminDashboard {
    return shamellDashboardAllowsSuperadminDashboardSnapshot(privilegeSnapshot);
  }

  bool get allowsPaymentsOperatorSurface {
    return capabilities.payments &&
        shamellDashboardAllowsPaymentsOperatorSurfaceSnapshot(
            privilegeSnapshot);
  }

  bool get allowsPaymentsCashRedeemSurface {
    return capabilities.payments &&
        shamellDashboardAllowsPaymentsCashRedeemSurfaceSnapshot(
          privilegeSnapshot,
        );
  }
}

ShamellDashboardPolicy? shamellDashboardPolicyOverrideOrScope(
  BuildContext context, {
  required String baseUrl,
  ShamellDashboardPolicy? policyOverride,
}) {
  if (policyOverride != null && policyOverride.matchesBaseUrl(baseUrl)) {
    return policyOverride;
  }
  return ShamellDashboardPolicyScope.maybeRead(context, baseUrl: baseUrl);
}

Future<ShamellDashboardPolicy> shamellResolveDashboardPolicy(
  BuildContext context, {
  required String baseUrl,
  ShamellDashboardPolicy? policyOverride,
  AccountPrivilegeSnapshot? privilegeSnapshotOverride,
}) async {
  final scopedPolicy = shamellDashboardPolicyOverrideOrScope(
    context,
    baseUrl: baseUrl,
    policyOverride: policyOverride,
  );
  if (privilegeSnapshotOverride == null) {
    return scopedPolicy ?? await ShamellDashboardPolicy.loadForBaseUrl(baseUrl);
  }
  if (scopedPolicy != null) {
    return ShamellDashboardPolicy(
      baseUrl: scopedPolicy.baseUrl,
      privilegeSnapshot: privilegeSnapshotOverride,
      capabilities: scopedPolicy.capabilities,
    );
  }
  final normalizedBaseUrl = _normalizeDashboardPolicyBaseUrl(baseUrl);
  return ShamellDashboardPolicy(
    baseUrl: normalizedBaseUrl.isEmpty ? baseUrl.trim() : normalizedBaseUrl,
    privilegeSnapshot: privilegeSnapshotOverride,
    capabilities: policyOverride?.matchesBaseUrl(baseUrl) == true
        ? policyOverride!.capabilities
        : ShamellCapabilities.conservativeDefaults,
  );
}

MaterialPageRoute<T> shamellDashboardPolicyRoute<T>({
  required BuildContext context,
  required String baseUrl,
  required Widget child,
  ShamellDashboardPolicy? policyOverride,
}) {
  final policy = shamellDashboardPolicyOverrideOrScope(
    context,
    baseUrl: baseUrl,
    policyOverride: policyOverride,
  );
  return MaterialPageRoute<T>(
    builder: (_) => policy == null
        ? child
        : ShamellDashboardPolicyScope(
            policy: policy,
            child: child,
          ),
  );
}

class ShamellDashboardPolicyScope extends InheritedWidget {
  final ShamellDashboardPolicy policy;

  const ShamellDashboardPolicyScope({
    super.key,
    required this.policy,
    required super.child,
  });

  static ShamellDashboardPolicy? maybeOf(
    BuildContext context, {
    String? baseUrl,
  }) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShamellDashboardPolicyScope>();
    return _matchBaseUrl(scope?.policy, baseUrl);
  }

  static ShamellDashboardPolicy? maybeRead(
    BuildContext context, {
    String? baseUrl,
  }) {
    final element = context
        .getElementForInheritedWidgetOfExactType<ShamellDashboardPolicyScope>();
    final scope = element?.widget as ShamellDashboardPolicyScope?;
    return _matchBaseUrl(scope?.policy, baseUrl);
  }

  static ShamellDashboardPolicy? _matchBaseUrl(
    ShamellDashboardPolicy? policy,
    String? baseUrl,
  ) {
    if (policy == null) {
      return null;
    }
    final rawBaseUrl = (baseUrl ?? '').trim();
    if (rawBaseUrl.isEmpty) {
      return policy;
    }
    return policy.matchesBaseUrl(rawBaseUrl) ? policy : null;
  }

  @override
  bool updateShouldNotify(ShamellDashboardPolicyScope oldWidget) {
    return policy.baseUrl != oldWidget.policy.baseUrl ||
        policy.privilegeSnapshot != oldWidget.policy.privilegeSnapshot ||
        policy.capabilities != oldWidget.policy.capabilities;
  }
}
