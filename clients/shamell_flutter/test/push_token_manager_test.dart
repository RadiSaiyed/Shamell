import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/notification_service.dart';
import 'package:shamell_flutter/core/push_token_manager.dart';

void main() {
  tearDown(() async {
    await PushTokenManager.resetForTesting();
  });

  test('PushTokenManager skips token warmup when notification consent denied',
      () async {
    var tokenReads = 0;

    final token = await PushTokenManager.warmUpPushToken(
      ensurePermissionOverride: () async => NotificationPermissionState.denied,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async {
        tokenReads++;
        return 'tok-1';
      },
    );

    expect(token, isNull);
    expect(tokenReads, 0);
  });

  test(
      'PushTokenManager registers current token once and re-registers on refresh',
      () async {
    final calls = <String>[];
    final refresh = StreamController<String>();
    addTearDown(refresh.close);
    final scope = Object();

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: refresh.stream,
      targetPlatformOverride: TargetPlatform.android,
    );

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('duplicate:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-duplicate-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: refresh.stream,
      targetPlatformOverride: TargetPlatform.android,
    );

    refresh.add('tok-2');
    await Future<void>.delayed(Duration.zero);

    expect(
      calls,
      <String>[
        'device-1|tok-1|android',
        'device-1|tok-2|android',
      ],
    );
  });

  test('PushTokenManager unregisters device and clears in-memory binding',
      () async {
    final calls = <String>[];
    final scope = Object();

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('register:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-initial-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    await PushTokenManager.unregisterForDevice(
      deviceId: 'device-1',
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unregister:$deviceId');
      },
    );

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('reregister:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-reregister-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    expect(
      calls,
      <String>[
        'register:device-1|tok-1|android',
        'unregister:device-1',
        'reregister:device-1|tok-1|android',
      ],
    );
  });

  test(
      'PushTokenManager unregisters current device when notification consent is later denied',
      () async {
    final calls = <String>[];
    final scope = Object();

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('register:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-initial-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('unexpected-register:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.denied,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-2',
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    expect(
      calls,
      <String>[
        'register:device-1|tok-1|android',
        'unregister:device-1',
      ],
    );
  });

  test(
      'PushTokenManager unregisters current device when token lookup later returns null',
      () async {
    final calls = <String>[];
    final scope = Object();

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('register:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-initial-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('unexpected-register:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => null,
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    expect(
      calls,
      <String>[
        'register:device-1|tok-1|android',
        'unregister:device-1',
      ],
    );
  });

  test(
      'PushTokenManager reconcile registers current device when valid token exists without active binding',
      () async {
    final calls = <String>[];

    await PushTokenManager.reconcileRegistrationForDevice(
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('register:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
    );

    expect(calls, <String>['register:device-1|tok-1|android']);
  });

  test(
      'PushTokenManager reconcile re-registers current device when token changed in foreground',
      () async {
    final calls = <String>[];
    final scope = Object();

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: scope,
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('register:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-initial-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: const Stream<String>.empty(),
      targetPlatformOverride: TargetPlatform.android,
    );

    await PushTokenManager.reconcileRegistrationForDevice(
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('reregister:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-reconcile-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-2',
    );

    expect(
      calls,
      <String>[
        'register:device-1|tok-1|android',
        'reregister:device-1|tok-2|android',
      ],
    );
  });

  test(
      'PushTokenManager re-registers on cold start even when persisted binding fingerprint matches current token',
      () async {
    final calls = <String>[];
    final persisted = <String, String>{
      'device-1': pushTokenBindingFingerprint(
        token: 'tok-1',
        platform: 'android',
      ),
    };
    final refresh = StreamController<String>();
    addTearDown(refresh.close);

    await PushTokenManager.reconcileRegistrationForDevice(
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('reconcile:$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-reconcile-unregister:$deviceId');
      },
      loadPersistedBindingFingerprint: ({
        required String deviceId,
      }) async =>
          persisted[deviceId],
      savePersistedBindingFingerprint: ({
        required String deviceId,
        required String fingerprint,
      }) async {
        persisted[deviceId] = fingerprint;
      },
      clearPersistedBindingFingerprint: ({
        required String deviceId,
      }) async {
        persisted.remove(deviceId);
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      targetPlatformOverride: TargetPlatform.android,
    );

    await PushTokenManager.ensureRegisteredForDevice(
      registrationScope: Object(),
      deviceId: 'device-1',
      registerToken: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('$deviceId|$token|$platform');
      },
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-ensure-unregister:$deviceId');
      },
      loadPersistedBindingFingerprint: ({
        required String deviceId,
      }) async =>
          persisted[deviceId],
      savePersistedBindingFingerprint: ({
        required String deviceId,
        required String fingerprint,
      }) async {
        persisted[deviceId] = fingerprint;
      },
      clearPersistedBindingFingerprint: ({
        required String deviceId,
      }) async {
        persisted.remove(deviceId);
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
      onTokenRefreshOverride: refresh.stream,
      targetPlatformOverride: TargetPlatform.android,
    );

    refresh.add('tok-2');
    await Future<void>.delayed(Duration.zero);

    expect(
      calls,
      <String>[
        'reconcile:device-1|tok-1|android',
        'device-1|tok-2|android',
      ],
    );
    expect(
      persisted['device-1'],
      pushTokenBindingFingerprint(
        token: 'tok-2',
        platform: 'android',
      ),
    );
  });

  test(
      'PushTokenManager clears persisted binding fingerprint when unregistering device',
      () async {
    final persisted = <String, String>{
      'device-1': 'sha256:test',
    };
    final calls = <String>[];

    await PushTokenManager.unregisterForDevice(
      deviceId: 'device-1',
      unregisterToken: ({
        required String deviceId,
      }) async {
        calls.add('unregister:$deviceId');
      },
      clearPersistedBindingFingerprint: ({
        required String deviceId,
      }) async {
        persisted.remove(deviceId);
      },
    );

    expect(calls, <String>['unregister:device-1']);
    expect(persisted, isEmpty);
  });
}
