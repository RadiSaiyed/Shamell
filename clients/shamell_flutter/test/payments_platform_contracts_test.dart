import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/payments/payments_platform_contracts.dart';

void main() {
  test('payments role helpers keep operator admin finance access separated',
      () {
    expect(
      shamellHasPaymentsOperatorAccess(const <String>['merchant']),
      isTrue,
    );
    expect(
      shamellHasPaymentsOperatorAccess(const <String>['operator_demo']),
      isTrue,
    );
    expect(
      shamellHasPaymentsCashAgentAccess(const <String>['cashout_operator']),
      isTrue,
    );
    expect(
      shamellHasPaymentsAdminAccess(const <String>['cashout_operator']),
      isFalse,
    );
    expect(
      shamellHasPaymentsFinanceAccess(const <String>['finance']),
      isTrue,
    );
    expect(
      shamellHasPaymentsFinanceAccess(const <String>['merchant']),
      isFalse,
    );
    expect(
      shamellHasPaymentsCreditAccess(const <String>['ops']),
      isTrue,
    );
    expect(
      shamellHasPaymentsCreditAccess(const <String>['bi_audit_read_only']),
      isFalse,
    );
    expect(
      shamellHasPaymentsSuperadminAccess(const <String>['superadmin']),
      isTrue,
    );
    expect(
      shamellHasPaymentsSuperadminAccess(const <String>['admin']),
      isFalse,
    );
  });

  test(
      'permission-only payments snapshot grants operator cash admin and guardrail access',
      () {
    final operatorSnapshot = AccountPrivilegeSnapshot(
      permissions: const <String>['wallet.operator.read'],
      products: const <String>['wallet'],
    );
    final cashAgentSnapshot = AccountPrivilegeSnapshot(
      permissions: const <String>['cash.agent.read'],
      products: const <String>['wallet'],
    );
    final adminSnapshot = AccountPrivilegeSnapshot(
      permissions: const <String>['wallet.admin.read'],
      products: const <String>['wallet'],
    );
    final guardrailSnapshot = AccountPrivilegeSnapshot(
      permissions: const <String>['wallet.guardrails.write'],
      products: const <String>['wallet'],
    );
    final creditSnapshot = AccountPrivilegeSnapshot(
      permissions: const <String>['wallet.credit.write'],
      products: const <String>['wallet'],
    );

    expect(shamellHasPaymentsOperatorSnapshotAccess(operatorSnapshot), isTrue);
    expect(
        shamellHasPaymentsCashAgentSnapshotAccess(cashAgentSnapshot), isTrue);
    expect(shamellHasPaymentsAdminSnapshotAccess(adminSnapshot), isTrue);
    expect(shamellHasPaymentsCreditSnapshotAccess(creditSnapshot), isTrue);
    expect(
      shamellHasPaymentsSuperadminSnapshotAccess(guardrailSnapshot),
      isTrue,
    );
  });

  test('explicit payments permissions fail closed for broader legacy roles',
      () {
    final snapshot = AccountPrivilegeSnapshot(
      roles: const <String>['seller', 'superadmin'],
      permissions: const <String>['wallet.finance.read'],
      products: const <String>['wallet'],
    );

    expect(shamellHasPaymentsOperatorSnapshotAccess(snapshot), isFalse);
    expect(shamellHasPaymentsFinanceSnapshotAccess(snapshot), isTrue);
    expect(shamellHasPaymentsCreditSnapshotAccess(snapshot), isFalse);
    expect(shamellHasPaymentsAdminSnapshotAccess(snapshot), isFalse);
    expect(shamellHasPaymentsSuperadminSnapshotAccess(snapshot), isFalse);
  });
}
