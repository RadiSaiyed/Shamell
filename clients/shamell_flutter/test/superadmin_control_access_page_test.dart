import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/superadmin_control_access_page.dart';

void main() {
  const baseUrl = 'http://localhost:8080';
  const sessionToken = '0123456789abcdef0123456789abcdef';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await clearSessionCookie();
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
  });

  tearDown(() async {
    await clearSessionCookie();
  });

  test('control access validators accept expected identity formats', () {
    expect(
      isValidShamellControlAdminPhoneE164('+963944444444'),
      isTrue,
    );
    expect(
      isValidShamellControlAdminPhoneE164('0944444444'),
      isFalse,
    );
    expect(
      isValidShamellControlAdminAccountId('a' * 64),
      isTrue,
    );
    expect(
      isValidShamellControlAdminAccountId('abc123'),
      isFalse,
    );
  });

  test('sensitive reveal helper only stays valid before expiry', () {
    final unlockedUntil = DateTime.parse('2026-04-06T10:02:00Z');

    expect(shamellControlSensitiveRevealStillValid(null), isFalse);
    expect(
      shamellControlSensitiveRevealStillValid(
        unlockedUntil,
        now: DateTime.parse('2026-04-06T10:01:59Z'),
      ),
      isTrue,
    );
    expect(
      shamellControlSensitiveRevealStillValid(
        unlockedUntil,
        now: DateTime.parse('2026-04-06T10:02:00Z'),
      ),
      isFalse,
    );
  });

  test('platform helper requires local auth only on supported native surfaces',
      () {
    expect(
      shamellControlPlatformRequiresSensitiveLocalAuth(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      shamellControlPlatformRequiresSensitiveLocalAuth(
        isWeb: false,
        platform: TargetPlatform.iOS,
      ),
      isTrue,
    );
    expect(
      shamellControlPlatformRequiresSensitiveLocalAuth(
        isWeb: true,
      ),
      isFalse,
    );
    expect(
      shamellControlPlatformRequiresSensitiveLocalAuth(
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      isFalse,
    );
  });

  testWidgets('superadmin control access page grants a role by phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode(<String, Object>{'assignments': <Object>[]}),
          200,
        );
      }
      if (request.method == 'POST') {
        return http.Response(jsonEncode(<String, Object>{'ok': true}), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SuperadminControlAccessPage(
          baseUrl: baseUrl,
          httpClient: client,
          sensitiveRevealOverride: () async => true,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            permissions: <String>[
              'access.assignment.read',
              'access.assignment.write',
            ],
            products: <String>['access'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '+963944444444',
    );
    final grantRoleButton = find.text('Grant role').last;
    await tester.tap(grantRoleButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final post = requests.singleWhere((request) => request.method == 'POST');
    expect(post.url.path, '/admin/access/assignments');
    expect(post.headers['idempotency-key'], isNotNull);
    expect(post.headers['cookie'], contains(sessionToken));
    expect(
      jsonDecode(post.body),
      <String, Object>{
        'phone': '+963944444444',
        'role_id': 'platform.ops_manager',
      },
    );
  });

  testWidgets(
      'superadmin control access page blocks mutation when local auth is denied',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<String, Object>{'assignments': <Object>[]}),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SuperadminControlAccessPage(
          baseUrl: baseUrl,
          httpClient: client,
          sensitiveRevealOverride: () async => false,
          privilegeSnapshotOverride: const AccountPrivilegeSnapshot(
            permissions: <String>[
              'access.assignment.read',
              'access.assignment.write',
            ],
            products: <String>['access'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '+963944444444');
    await tester.tap(find.text('Grant role').last, warnIfMissed: false);
    await tester.pump();

    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    expect(
      find.text(
        'Device authentication is required to change sensitive SyrChat Control access.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('superadmin control access page denies access without grants',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SuperadminControlAccessPage(
          baseUrl: baseUrl,
          privilegeSnapshotOverride: AccountPrivilegeSnapshot.empty,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Your account is not allowed to manage SyrChat Control access.',
      ),
      findsOneWidget,
    );
    expect(find.text('Grant role'), findsNothing);
  });
}
