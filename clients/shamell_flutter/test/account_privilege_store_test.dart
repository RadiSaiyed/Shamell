import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/account_snapshot_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  var throwOnSecureRead = false;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = (args['value'] ?? '').toString();
            return null;
          case 'read':
            if (throwOnSecureRead) {
              throw PlatformException(code: 'secure-read-failed');
            }
            return secStore[key];
          case 'delete':
            secStore.remove(key);
            return null;
          case 'deleteAll':
            secStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secStore);
          case 'containsKey':
            return secStore.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    throwOnSecureRead = false;
    await clearAccountPrivilegeSnapshot();
  });

  test('account privileges ignore legacy SharedPreferences by default',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'roles': <String>['admin', 'ops', 'admin', ''],
      'is_superadmin': true,
      'phone': '+963955000111',
    });

    final snapshot = await loadAccountPrivilegeSnapshot();

    expect(snapshot.roles, isEmpty);
    expect(snapshot.isSuperadmin, isFalse);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('roles'), isNull);
    expect(sp.getBool('is_superadmin'), isNull);
    expect(sp.getString('phone'), isNull);
  });

  test('account privileges allow legacy fallback when secure reads fail',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'roles': <String>['admin', 'ops', 'admin', ''],
      'is_superadmin': true,
      'phone': '+963955000111',
    });
    throwOnSecureRead = true;

    final snapshot = await loadAccountPrivilegeSnapshot();

    expect(snapshot.roles, <String>['admin', 'ops']);
    expect(snapshot.isSuperadmin, isTrue);
  });

  test('account privileges save, load, and clear via secure storage', () async {
    final saved = await saveAccountPrivilegeSnapshot(
      roles: <String>['seller', 'ops', 'seller'],
      isSuperadmin: false,
      operatorIds: <String>['op_demo_express', 'op_demo_express', ''],
    );

    expect(saved, isTrue);

    final snapshot = await loadAccountPrivilegeSnapshot();
    expect(snapshot.roles, <String>['seller', 'ops']);
    expect(snapshot.isSuperadmin, isFalse);
    expect(snapshot.operatorIds, <String>['op_demo_express']);

    await clearAccountPrivilegeSnapshot();

    final cleared = await loadAccountPrivilegeSnapshot();
    expect(cleared.roles, isEmpty);
    expect(cleared.isSuperadmin, isFalse);
    expect(cleared.operatorIds, isEmpty);
  });

  test('account privileges persist extended permission snapshot fields',
      () async {
    final saved = await saveAccountPrivilegeSnapshot(
      roles: <String>['admin', 'admin'],
      isSuperadmin: false,
      operatorIds: <String>['op_demo_express', 'op_demo_express'],
      permissions: <String>[
        'coach.catalog.read',
        'coach.catalog.read',
        'rides.dispatch.read',
      ],
      products: <String>['coach', 'rides', 'coach'],
      officialAccountIds: <String>['shamell_pay', 'shamell_pay'],
      officialAccountWildcard: false,
      hasPlatformScope: true,
      isAdmin: true,
    );

    expect(saved, isTrue);

    final snapshot = await loadAccountPrivilegeSnapshot();
    expect(snapshot.roles, <String>['admin']);
    expect(snapshot.operatorIds, <String>['op_demo_express']);
    expect(
      snapshot.permissions,
      <String>['coach.catalog.read', 'rides.dispatch.read'],
    );
    expect(snapshot.products, <String>['coach', 'rides']);
    expect(snapshot.officialAccountIds, <String>['shamell_pay']);
    expect(snapshot.officialAccountWildcard, isFalse);
    expect(snapshot.hasPlatformScope, isTrue);
    expect(snapshot.isAdmin, isTrue);
    expect(snapshot.isSuperadmin, isFalse);
    expect(snapshot.hasPermission('coach.catalog.read'), isTrue);
    expect(snapshot.hasProductAccess('coach'), isTrue);
    expect(snapshot.hasOperatorScope('op_demo_express'), isTrue);
    expect(snapshot.hasOfficialAccountScope('shamell_pay'), isTrue);
    expect(
      snapshot.can(
        'coach.catalog.read',
        product: 'coach',
        operatorId: 'op_demo_express',
      ),
      isTrue,
    );
  });

  test('accountPrivilegeSnapshotHasData recognizes permission-only snapshots',
      () {
    expect(
      accountPrivilegeSnapshotHasData(
        const AccountPrivilegeSnapshot(
          permissions: <String>['rides.operator.read'],
          products: <String>['rides'],
        ),
      ),
      isTrue,
    );
    expect(
      accountPrivilegeSnapshotHasData(AccountPrivilegeSnapshot.empty),
      isFalse,
    );
  });

  test('account privileges stay isolated across canonical API origins',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await saveAccountPrivilegeSnapshot(
      roles: <String>['admin'],
      isSuperadmin: true,
    );

    await sp.setString('base_url', 'https://api.two.example');
    final secondOrigin = await loadAccountPrivilegeSnapshot();
    expect(secondOrigin.roles, isEmpty);
    expect(secondOrigin.isSuperadmin, isFalse);

    await saveAccountPrivilegeSnapshot(
      roles: <String>['seller'],
      isSuperadmin: false,
    );

    await sp.setString('base_url', 'https://api.one.example');
    final firstOrigin = await loadAccountPrivilegeSnapshot();
    expect(firstOrigin.roles, <String>['admin']);
    expect(firstOrigin.isSuperadmin, isTrue);

    await sp.setString('base_url', 'https://api.two.example');
    final reloadedSecondOrigin = await loadAccountPrivilegeSnapshot();
    expect(reloadedSecondOrigin.roles, <String>['seller']);
    expect(reloadedSecondOrigin.isSuperadmin, isFalse);
  });

  test(
      'legacy global account privileges do not rebind into trusted canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'roles': <String>['admin', 'ops'],
      'is_superadmin': true,
      'phone': '+963955000111',
    });

    final snapshot = await loadAccountPrivilegeSnapshot();

    expect(snapshot.roles, isEmpty);
    expect(snapshot.isSuperadmin, isFalse);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('roles'), isNull);
    expect(sp.getBool('is_superadmin'), isNull);
    expect(sp.getString('phone'), isNull);
  });

  test(
      'account privileges honor explicit baseUrl override over global scope and clear only current scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.two.example');

    await saveAccountPrivilegeSnapshot(
      roles: <String>['admin'],
      isSuperadmin: true,
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await saveAccountPrivilegeSnapshot(
      roles: <String>['seller'],
      isSuperadmin: false,
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    final originOne = await loadAccountPrivilegeSnapshotForBaseUrl(
      'https://api.one.example',
      sp: sp,
    );
    final originTwo = await loadAccountPrivilegeSnapshotForBaseUrl(
      'https://api.two.example',
      sp: sp,
    );
    expect(originOne.roles, <String>['admin']);
    expect(originOne.isSuperadmin, isTrue);
    expect(originTwo.roles, <String>['seller']);
    expect(originTwo.isSuperadmin, isFalse);

    await clearAccountPrivilegeSnapshot(
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );

    final clearedOriginOne = await loadAccountPrivilegeSnapshotForBaseUrl(
      'https://api.one.example',
      sp: sp,
    );
    final preservedOriginTwo = await loadAccountPrivilegeSnapshotForBaseUrl(
      'https://api.two.example',
      sp: sp,
    );
    expect(clearedOriginOne.roles, isEmpty);
    expect(clearedOriginOne.isSuperadmin, isFalse);
    expect(preservedOriginTwo.roles, <String>['seller']);
    expect(preservedOriginTwo.isSuperadmin, isFalse);
  });

  test('account privileges can fall back to cached home snapshot', () async {
    const baseUrl = 'https://api.example.com';
    await saveCachedHomeSnapshotRaw(
      '{"roles":["ops","driver","ops"],"operator_ids":["op_demo_express","op_demo_express"],"is_superadmin":true}',
      baseUrlOverride: baseUrl,
    );

    final snapshot = await loadAccountPrivilegeSnapshotFromCachedHomeSnapshot(
      baseUrlOverride: baseUrl,
    );

    expect(snapshot.roles, <String>['ops', 'driver']);
    expect(snapshot.isSuperadmin, isTrue);
    expect(snapshot.operatorIds, <String>['op_demo_express']);
  });

  test('cached home snapshot fallback parses permissions and scope fields',
      () async {
    const baseUrl = 'https://api.example.com';
    await saveCachedHomeSnapshotRaw(
      '{"roles":["support_l1"],"operator_ids":["op_demo_express"],"permissions":["coach.manifest.read","coach.boarding.scan.write"],"products":["coach"],"official_account_ids":["shamell_pay"],"official_account_wildcard":false,"has_platform_scope":true,"is_admin":true,"is_superadmin":false}',
      baseUrlOverride: baseUrl,
    );

    final snapshot = await loadAccountPrivilegeSnapshotFromCachedHomeSnapshot(
      baseUrlOverride: baseUrl,
    );

    expect(snapshot.roles, <String>['support_l1']);
    expect(snapshot.operatorIds, <String>['op_demo_express']);
    expect(
      snapshot.permissions,
      <String>['coach.manifest.read', 'coach.boarding.scan.write'],
    );
    expect(snapshot.products, <String>['coach']);
    expect(snapshot.officialAccountIds, <String>['shamell_pay']);
    expect(snapshot.officialAccountWildcard, isFalse);
    expect(snapshot.hasPlatformScope, isTrue);
    expect(snapshot.isAdmin, isTrue);
    expect(snapshot.isSuperadmin, isFalse);
  });

  test('cached home snapshot fallback ignores invalid payloads', () async {
    const baseUrl = 'https://api.example.com';
    await saveCachedHomeSnapshotRaw(
      '{"roles":"ops"}',
      baseUrlOverride: baseUrl,
    );

    final snapshot = await loadAccountPrivilegeSnapshotFromCachedHomeSnapshot(
      baseUrlOverride: baseUrl,
    );

    expect(snapshot.roles, isEmpty);
    expect(snapshot.isSuperadmin, isFalse);
  });
}
