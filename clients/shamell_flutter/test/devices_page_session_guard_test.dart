import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/device_id.dart';
import 'package:shamell_flutter/core/devices_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/main.dart' show LoginPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};

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
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
  });

  testWidgets('DevicesPage reauths on critical account session failure',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.example.com/auth/devices?limit=50',
      );
      return http.Response('{"detail":"auth session required"}', 401);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('DevicesPage reauths on critical forget-device failure',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await saveStableDeviceId(
      'device_me',
      baseUrlOverride: 'https://api.example.com',
    );
    await setSessionTokenForBaseUrl(
      'https://api.example.com',
      '0123456789abcdef0123456789abcdef',
    );

    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/auth/devices?limit=50') {
        return http.Response(
          '{"devices":[{"device_id":"device_me","name":"This device"}]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/auth/devices/device_me') {
        expect(request.method, 'DELETE');
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Logout & forget this device'), findsOneWidget);
    await tester.tap(find.text('Logout & forget this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Forget device'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('DevicesPage reauths on critical remove-other-device failure',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await saveStableDeviceId(
      'device_me',
      baseUrlOverride: 'https://api.example.com',
    );
    await setSessionTokenForBaseUrl(
      'https://api.example.com',
      '0123456789abcdef0123456789abcdef',
    );

    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/auth/devices?limit=50') {
        return http.Response(
          '{"devices":[{"device_id":"device_me","name":"This device"},{"device_id":"device_other","name":"Old phone"}]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/auth/devices/device_other') {
        expect(request.method, 'DELETE');
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove this device'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Remove this device').last);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('DevicesPage rejects malformed base urls before loading',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://user:pass@api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Could not load devices.'), findsOneWidget);
  });

  testWidgets(
      'DevicesPage forget-device uses page-scoped stable device id over stored scope',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    expect(
      await saveStableDeviceId(
        'device-stored',
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      isTrue,
    );
    expect(
      await saveStableDeviceId(
        'device-active',
        sp: sp,
        baseUrlOverride: 'https://api.example.com',
      ),
      isTrue,
    );
    await setSessionTokenForBaseUrl(
      'https://api.example.com',
      '0123456789abcdef0123456789abcdef',
    );

    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/auth/devices?limit=50') {
        return http.Response(
          '{"devices":[{"device_id":"device-active","name":"This device"}]}',
          200,
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/auth/devices/device-active') {
        expect(request.method, 'DELETE');
        return http.Response('{"detail":"auth session required"}', 401);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Logout & forget this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Forget device'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('DevicesPage loads older devices with a stable before cursor',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final requests = <Uri>[];
    List<Map<String, Object?>> buildPage(int startId, int endId) {
      final items = <Map<String, Object?>>[];
      for (var id = startId; id >= endId; id--) {
        final minute = (id % 60).toString().padLeft(2, '0');
        items.add(<String, Object?>{
          'id': id,
          'device_id': 'device_$id',
          'device_type': 'Phone $id',
          'last_seen_at': '2026-03-18T10:$minute:00Z',
        });
      }
      return items;
    }

    final client = MockClient((request) async {
      requests.add(request.url);
      final beforeId = request.url.queryParameters['before_id'];
      if (beforeId == null) {
        return http.Response(
          jsonEncode(<String, Object?>{'devices': buildPage(60, 11)}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      expect(beforeId, '11');
      expect(
        request.url.queryParameters['before_last_seen_at'],
        startsWith('2026-03-18T10:11:00'),
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'devices': <Map<String, Object?>>[
            <String, Object?>{
              'id': 10,
              'device_id': 'device_10',
              'device_type': 'Phone 10',
              'last_seen_at': '2026-03-18T10:10:00Z',
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Load more'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Load more'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    expect(find.text('Phone 10'), findsOneWidget);
  });

  testWidgets('DevicesPage ignores double-tap remove while delete is in flight',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await saveStableDeviceId(
      'device_me',
      baseUrlOverride: 'https://api.example.com',
    );
    await setSessionTokenForBaseUrl(
      'https://api.example.com',
      '0123456789abcdef0123456789abcdef',
    );

    final responseGate = Completer<void>();
    var listRequests = 0;
    var deleteRequests = 0;
    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/auth/devices?limit=50') {
        listRequests += 1;
        if (listRequests == 1) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'devices': <Map<String, Object?>>[
                <String, Object?>{
                  'device_id': 'device_me',
                  'device_type': 'This'
                },
                <String, Object?>{
                  'device_id': 'device_other',
                  'device_type': 'Phone B',
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'devices': <Map<String, Object?>>[
              <String, Object?>{
                'device_id': 'device_me',
                'device_type': 'This'
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.toString() ==
          'https://api.example.com/auth/devices/device_other') {
        deleteRequests += 1;
        await responseGate.future;
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    final removeButton = find.byTooltip('Remove this device').last;
    await tester.tap(removeButton);
    await tester.pump();

    await tester.tap(removeButton, warnIfMissed: false);
    await tester.pump();

    expect(deleteRequests, 1);

    responseGate.complete();
    await tester.pumpAndSettle();

    expect(deleteRequests, 1);
    expect(listRequests, 2);
  });

  testWidgets(
      'DevicesPage logout-others stops after critical reauth on first delete',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await saveStableDeviceId(
      'device_me',
      baseUrlOverride: 'https://api.example.com',
    );
    await setSessionTokenForBaseUrl(
      'https://api.example.com',
      '0123456789abcdef0123456789abcdef',
    );

    final deleteRequests = <String>[];
    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/auth/devices?limit=50') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'devices': <Map<String, Object?>>[
              <String, Object?>{
                'device_id': 'device_me',
                'device_type': 'This'
              },
              <String, Object?>{
                'device_id': 'device_a',
                'device_type': 'Phone A'
              },
              <String, Object?>{
                'device_id': 'device_b',
                'device_type': 'Phone B'
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE') {
        deleteRequests.add(request.url.toString());
        if (request.url.toString() ==
            'https://api.example.com/auth/devices/device_a') {
          return http.Response('{"detail":"auth session required"}', 401);
        }
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Log out of other devices'), findsOneWidget);
    await tester.tap(find.text('Log out of other devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(LoginPage), findsOneWidget);
    expect(
      deleteRequests,
      <String>['https://api.example.com/auth/devices/device_a'],
    );
  });

  testWidgets(
      'DevicesPage logout-others refreshes once after successful bulk removal',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await saveStableDeviceId(
      'device_me',
      baseUrlOverride: 'https://api.example.com',
    );
    await setSessionTokenForBaseUrl(
      'https://api.example.com',
      '0123456789abcdef0123456789abcdef',
    );

    var listRequests = 0;
    final deleteRequests = <String>[];
    final client = MockClient((request) async {
      if (request.url.toString() ==
          'https://api.example.com/auth/devices?limit=50') {
        listRequests += 1;
        if (listRequests == 1) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'devices': <Map<String, Object?>>[
                <String, Object?>{
                  'device_id': 'device_me',
                  'device_type': 'This'
                },
                <String, Object?>{
                  'device_id': 'device_a',
                  'device_type': 'Phone A'
                },
                <String, Object?>{
                  'device_id': 'device_b',
                  'device_type': 'Phone B'
                },
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'devices': <Map<String, Object?>>[
              <String, Object?>{
                'device_id': 'device_me',
                'device_type': 'This'
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE') {
        deleteRequests.add(request.url.toString());
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(
          baseUrl: 'https://api.example.com',
          client: client,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log out of other devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(listRequests, 2);
    expect(
      deleteRequests,
      <String>[
        'https://api.example.com/auth/devices/device_a',
        'https://api.example.com/auth/devices/device_b',
      ],
    );
    expect(find.text('Phone A'), findsNothing);
    expect(find.text('Phone B'), findsNothing);
  });
}
