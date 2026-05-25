import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/access_platform_contracts.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';

void main() {
  test('control access read accepts legacy access_admin product snapshots', () {
    const snapshot = AccountPrivilegeSnapshot(
      products: <String>['access_admin'],
    );

    expect(
      shamellHasControlAccessAssignmentReadSnapshotAccess(snapshot),
      isTrue,
    );
  });

  test('control access write accepts explicit assignment permission', () {
    const snapshot = AccountPrivilegeSnapshot(
      permissions: <String>['access.assignment.write'],
      products: <String>['access_admin'],
    );

    expect(
      shamellHasControlAccessAssignmentWriteSnapshotAccess(snapshot),
      isTrue,
    );
  });
}
