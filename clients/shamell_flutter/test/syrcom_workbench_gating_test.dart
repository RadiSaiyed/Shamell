import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/syrcom/syrcom_workbench_page.dart';
import 'package:shamell_flutter/core/syrcom/workforce_snapshot.dart';

Widget _testApp(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

class _FakeWorkforceAccessApi extends WorkforceAccessApi {
  _FakeWorkforceAccessApi(this._snapshot) : super(baseUrl: 'https://test');

  final WorkforceAccessSnapshot? _snapshot;

  @override
  Future<WorkforceAccessSnapshot?> fetchPermissions() async => _snapshot;

  @override
  Future<WorkforceAccessSnapshot> enrichWithAccessContext(
    WorkforceAccessSnapshot snapshot,
  ) async {
    // Add a fake membership so the header subtitle test path is exercised
    // without going through the real /me/access-context endpoint.
    return WorkforceAccessSnapshot(
      workforceAccountId: snapshot.workforceAccountId,
      snapshotVersion: snapshot.snapshotVersion,
      humanId: 'hum_test',
      accountType: 'internal_staff',
      status: 'active',
      organizations: const <WorkforceMembership>[
        WorkforceMembership(
          organizationId: 'org_shamell_internal',
          organizationDisplayName: 'Shamell — Internal',
          orgKind: 'platform_internal',
          isPrimary: true,
          status: 'active',
        ),
      ],
      permissions: snapshot.permissions,
    );
  }
}

WorkforceAccessSnapshot _snapshotWithPermissions(List<String> ids) {
  return WorkforceAccessSnapshot(
    workforceAccountId: 'wfa_test',
    snapshotVersion: 'v1:test',
    permissions: ids
        .map((id) => WorkforcePermissionGrant(
              permissionId: id,
              scopes: const <WorkforceScope>[],
            ))
        .toList(growable: false),
  );
}

/// Several tile labels (Approvals, Meetings, Tasks) also appear as stat
/// labels in the always-visible Today card. Constrain finders to the
/// `SliverGrid` so assertions actually measure the gated module tiles, not
/// the dashboard widgets that live above them.
Finder _gridTile(String label) => find.descendant(
      of: find.byType(SliverGrid),
      matching: find.text(label),
    );

/// `SliverGrid` only materializes tiles inside the viewport. The Workbench's
/// three category sections plus the header card don't fit in the default
/// 800×600 test surface, so lower-section tiles (Payroll, CRM) would not be
/// in the widget tree and assertions about them would spuriously fail. Use a
/// generously tall surface for these tests so every section gets rendered.
void _useTallTestViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'Workbench shows every tile when there is no workforce snapshot',
    (tester) async {
      _useTallTestViewport(tester);
      final api = _FakeWorkforceAccessApi(null);
      await tester.pumpWidget(
        _testApp(SyrComWorkbenchPage(baseUrl: 'https://test', workforceApi: api)),
      );
      await tester.pumpAndSettle();

      // Every named module — gated or ungated — is visible in the legacy
      // permissive fallback. The server still rejects unauthorized calls.
      expect(_gridTile('Approvals'), findsOneWidget);
      expect(_gridTile('Reports'), findsOneWidget);
      expect(_gridTile('Payroll'), findsOneWidget);
      expect(_gridTile('CRM'), findsOneWidget);
      expect(_gridTile('Tasks'), findsOneWidget);
    },
  );

  testWidgets(
    'Workbench hides finance-gated tiles when snapshot grants only support.case.read',
    (tester) async {
      _useTallTestViewport(tester);
      final api = _FakeWorkforceAccessApi(
        _snapshotWithPermissions(<String>['support.case.read']),
      );
      await tester.pumpWidget(
        _testApp(SyrComWorkbenchPage(baseUrl: 'https://test', workforceApi: api)),
      );
      await tester.pumpAndSettle();

      expect(_gridTile('Approvals'), findsOneWidget);
      expect(_gridTile('CRM'), findsOneWidget);
      expect(_gridTile('Tasks'), findsOneWidget);
      expect(_gridTile('Reports'), findsNothing);
      expect(_gridTile('Payroll'), findsNothing);
    },
  );

  testWidgets(
    'Workbench hides support-gated tiles when snapshot grants only finance.journal.read',
    (tester) async {
      _useTallTestViewport(tester);
      final api = _FakeWorkforceAccessApi(
        _snapshotWithPermissions(<String>['finance.journal.read']),
      );
      await tester.pumpWidget(
        _testApp(SyrComWorkbenchPage(baseUrl: 'https://test', workforceApi: api)),
      );
      await tester.pumpAndSettle();

      expect(_gridTile('Reports'), findsOneWidget);
      expect(_gridTile('Payroll'), findsOneWidget);
      expect(_gridTile('Tasks'), findsOneWidget);
      expect(_gridTile('Approvals'), findsNothing);
      expect(_gridTile('CRM'), findsNothing);
    },
  );

  testWidgets(
    'Workbench filters every gated tile when snapshot grants only unrelated permissions',
    (tester) async {
      // Snapshot with an unrelated permission — every gated tile drops out.
      // The ungated placeholder tiles remain visible: they document intent
      // for future permission-aware features without locking out the
      // surface while those features don't have backends yet.
      _useTallTestViewport(tester);
      final api = _FakeWorkforceAccessApi(
        _snapshotWithPermissions(<String>['unrelated.permission']),
      );
      await tester.pumpWidget(
        _testApp(SyrComWorkbenchPage(baseUrl: 'https://test', workforceApi: api)),
      );
      await tester.pumpAndSettle();

      expect(_gridTile('Approvals'), findsNothing);
      expect(_gridTile('Reports'), findsNothing);
      expect(_gridTile('Payroll'), findsNothing);
      expect(_gridTile('CRM'), findsNothing);
      expect(_gridTile('Tasks'), findsOneWidget);
      expect(_gridTile('Meetings'), findsOneWidget);
      expect(_gridTile('Drive'), findsOneWidget);
    },
  );

  testWidgets(
    'Access Admin tile is hidden when snapshot lacks access.assignment.write',
    (tester) async {
      _useTallTestViewport(tester);
      final api = _FakeWorkforceAccessApi(
        _snapshotWithPermissions(<String>['support.case.read']),
      );
      await tester.pumpWidget(
        _testApp(SyrComWorkbenchPage(baseUrl: 'https://test', workforceApi: api)),
      );
      await tester.pumpAndSettle();
      expect(_gridTile('Access Admin'), findsNothing);
    },
  );

  testWidgets(
    'Access Admin tile appears when snapshot grants access.assignment.write',
    (tester) async {
      _useTallTestViewport(tester);
      final api = _FakeWorkforceAccessApi(
        _snapshotWithPermissions(<String>['access.assignment.write']),
      );
      await tester.pumpWidget(
        _testApp(SyrComWorkbenchPage(baseUrl: 'https://test', workforceApi: api)),
      );
      await tester.pumpAndSettle();
      expect(_gridTile('Access Admin'), findsOneWidget);
    },
  );

  testWidgets(
    'Workbench header subtitle reflects the primary organization once the access context loads',
    (tester) async {
      final api = _FakeWorkforceAccessApi(
        _snapshotWithPermissions(<String>['support.case.read']),
      );
      await tester.pumpWidget(
        _testApp(SyrComWorkbenchPage(baseUrl: 'https://test', workforceApi: api)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shamell — Internal'), findsOneWidget);
      // The generic legacy subtitle is replaced once the snapshot lands.
      expect(find.text('Workbench'), findsNothing);
    },
  );
}
