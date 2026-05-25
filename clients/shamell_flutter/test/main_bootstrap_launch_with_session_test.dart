import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/notification_service.dart';
import 'package:shamell_flutter/core/push_token_manager.dart';
import 'package:shamell_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await PushTokenManager.resetForTesting();
  });

  test('launchWithSession trusts only same-origin web targets', () {
    final trusted = shamellTrustedWebLaunchBaseForUri(
      Uri.parse('https://api.shamell.online/admin/risk?tab=1'),
      storedBaseUrl: 'https://api.shamell.online',
    );
    expect(trusted, isNotNull);
    expect(trusted.toString(), 'https://api.shamell.online');
  });

  test(
      'launchWithSession trust resolution prefers active base over stored base',
      () {
    final resolved = shamellResolveBootstrapBaseUrl(
      storedBaseUrl: 'https://api.one.example',
      activeBaseUrl: 'https://api.two.example',
    );
    final trusted = shamellTrustedWebLaunchBaseForUri(
      Uri.parse('https://api.two.example/admin/risk?tab=1'),
      storedBaseUrl: resolved,
    );
    expect(trusted, isNotNull);
    expect(trusted.toString(), 'https://api.two.example');
  });

  test('launchWithSession rejects credentialed or cross-origin web targets',
      () {
    expect(
      shamellTrustedWebLaunchBaseForUri(
        Uri.parse('https://user:pass@api.shamell.online/admin/risk'),
        storedBaseUrl: 'https://api.shamell.online',
      ),
      isNull,
    );
    expect(
      shamellTrustedWebLaunchBaseForUri(
        Uri.parse('https://api.shamell.online:8443/admin/risk'),
        storedBaseUrl: 'https://api.shamell.online',
      ),
      isNull,
    );
    expect(
      shamellTrustedWebLaunchBaseForUri(
        Uri.parse('https://evil.test/admin/risk'),
        storedBaseUrl: 'https://api.shamell.online',
      ),
      isNull,
    );
  });

  test('launchWithSession rejects non-http or invalid stored bases', () {
    expect(
      shamellTrustedWebLaunchBaseForUri(
        Uri.parse('mailto:test@example.com'),
        storedBaseUrl: 'https://api.shamell.online',
      ),
      isNull,
    );
    expect(
      shamellTrustedWebLaunchBaseForUri(
        Uri.parse('https://api.shamell.online/admin/risk'),
        storedBaseUrl: 'https://user:pass@api.shamell.online',
      ),
      isNull,
    );
  });

  test('trusted web child uri builder canonicalizes first-party paths', () {
    final uri = shamellTrustedWebChildUri(
      baseUrl: 'HTTPS://api.shamell.online/',
      pathSegments: const ['admin', 'risk'],
    );
    expect(uri, isNotNull);
    expect(uri.toString(), 'https://api.shamell.online/admin/risk');

    final encoded = shamellTrustedWebChildUri(
      baseUrl: 'http://127.0.0.1:8080',
      pathSegments: const ['topup', 'print', 'batch/42'],
    );
    expect(
      encoded.toString(),
      'http://127.0.0.1:8080/topup/print/batch%2F42',
    );
  });

  test('trusted web child uri builder rejects malformed bases or segments', () {
    expect(
      shamellTrustedWebChildUri(
        baseUrl: 'https://user:pass@api.shamell.online',
        pathSegments: const ['admin', 'risk'],
      ),
      isNull,
    );
    expect(
      shamellTrustedWebChildUri(
        baseUrl: 'https://api.shamell.online/app',
        pathSegments: const ['admin', 'risk'],
      ),
      isNull,
    );
    expect(
      shamellTrustedWebChildUri(
        baseUrl: 'https://api.shamell.online',
        pathSegments: const ['admin', ' '],
      ),
      isNull,
    );
  });

  test(
      'launchWithSession fallback keeps http targets out of in-app default launch',
      () {
    expect(
      shamellLaunchWithSessionFallbackMode(
        Uri.parse('https://api.shamell.online/admin/risk'),
      ),
      LaunchMode.externalApplication,
    );
    expect(
      shamellLaunchWithSessionFallbackMode(
        Uri.parse('http://127.0.0.1:8080/topup/print'),
      ),
      LaunchMode.externalApplication,
    );
    expect(
      shamellLaunchWithSessionFallbackMode(
        Uri.parse('mailto:test@example.com'),
      ),
      LaunchMode.platformDefault,
    );
  });

  test('launchWithSession uses embedded webview only for local dev bridging',
      () {
    expect(
      shamellLaunchWithSessionUsesEmbeddedWebView(
        isWeb: false,
        hasNavigator: true,
        trustedBaseUri: Uri.parse('http://127.0.0.1:8080'),
        injectSessionForSameOrigin: true,
      ),
      isTrue,
    );
    expect(
      shamellLaunchWithSessionUsesEmbeddedWebView(
        isWeb: false,
        hasNavigator: true,
        trustedBaseUri: Uri.parse('https://api.shamell.online'),
        injectSessionForSameOrigin: false,
      ),
      isFalse,
    );
    expect(
      shamellLaunchWithSessionUsesEmbeddedWebView(
        isWeb: false,
        hasNavigator: false,
        trustedBaseUri: Uri.parse('http://127.0.0.1:8080'),
        injectSessionForSameOrigin: true,
      ),
      isFalse,
    );
  });

  test(
      'shamellReconcileCurrentPushBinding unregisters stored chat device when push is unavailable',
      () async {
    final unregistrations = <String>[];

    await shamellReconcileCurrentPushBinding(
      baseUrlOverride: 'https://api.example.com',
      loadIdentityOverride: ({String? baseUrlOverride}) async =>
          const ChatIdentity(
        id: 'chat_dev_1',
        publicKeyB64: 'pk',
        privateKeyB64: 'sk',
        fingerprint: 'fp',
      ),
      unregisterTokenOverride: ({
        required String deviceId,
      }) async {
        unregistrations.add(deviceId);
      },
      ensurePermissionOverride: () async => NotificationPermissionState.denied,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
    );

    expect(unregistrations, <String>['chat_dev_1']);
  });

  test(
      'shamellReconcileCurrentPushBinding re-registers stored chat device when valid token exists',
      () async {
    final registrations = <String>[];

    await shamellReconcileCurrentPushBinding(
      baseUrlOverride: 'https://api.example.com',
      loadIdentityOverride: ({String? baseUrlOverride}) async =>
          const ChatIdentity(
        id: 'chat_dev_1',
        publicKeyB64: 'pk',
        privateKeyB64: 'sk',
        fingerprint: 'fp',
      ),
      registerTokenOverride: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        registrations.add('$deviceId|$token|$platform');
      },
      unregisterTokenOverride: ({
        required String deviceId,
      }) async {
        registrations.add('unexpected-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
    );

    expect(registrations, <String>['chat_dev_1|tok-1|android']);
  });

  test(
      'shamellReconcileCurrentPushBinding ensures chat registration before push registration',
      () async {
    final calls = <String>[];

    await shamellReconcileCurrentPushBinding(
      baseUrlOverride: 'https://api.example.com',
      ensureAccountChatReadyOverride: () async {
        calls.add('ensure-chat-ready');
      },
      loadIdentityOverride: ({String? baseUrlOverride}) async =>
          const ChatIdentity(
        id: 'chat_dev_1',
        publicKeyB64: 'pk',
        privateKeyB64: 'sk',
        fingerprint: 'fp',
      ),
      registerTokenOverride: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('register:$deviceId:$token:$platform');
      },
      unregisterTokenOverride: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
    );

    expect(
      calls,
      <String>['ensure-chat-ready', 'register:chat_dev_1:tok-1:android'],
    );
  });

  test(
      'shamellReconcileCurrentPushBinding skips push registration when chat readiness fails',
      () async {
    final calls = <String>[];

    await shamellReconcileCurrentPushBinding(
      baseUrlOverride: 'https://api.example.com',
      ensureAccountChatReadyOverride: () async {
        calls.add('ensure-chat-ready');
        throw StateError('chat device not registered');
      },
      loadIdentityOverride: ({String? baseUrlOverride}) async =>
          const ChatIdentity(
        id: 'chat_dev_1',
        publicKeyB64: 'pk',
        privateKeyB64: 'sk',
        fingerprint: 'fp',
      ),
      registerTokenOverride: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        calls.add('unexpected-register:$deviceId');
      },
      unregisterTokenOverride: ({
        required String deviceId,
      }) async {
        calls.add('unexpected-unregister:$deviceId');
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
    );

    expect(calls, <String>['ensure-chat-ready']);
  });

  test(
      'shamellReconcileCurrentPushBinding skips re-register when persisted fingerprint already matches',
      () async {
    final registrations = <String>[];
    final persisted = <String, String>{
      'chat_dev_1': pushTokenBindingFingerprint(
        token: 'tok-1',
        platform: 'android',
      ),
    };

    await shamellReconcileCurrentPushBinding(
      baseUrlOverride: 'https://api.example.com',
      loadIdentityOverride: ({String? baseUrlOverride}) async =>
          const ChatIdentity(
        id: 'chat_dev_1',
        publicKeyB64: 'pk',
        privateKeyB64: 'sk',
        fingerprint: 'fp',
      ),
      registerTokenOverride: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        registrations.add('$deviceId|$token|$platform');
      },
      unregisterTokenOverride: ({
        required String deviceId,
      }) async {
        registrations.add('unexpected-unregister:$deviceId');
      },
      loadPersistedFingerprintOverride: ({
        required String deviceId,
      }) async =>
          persisted[deviceId],
      savePersistedFingerprintOverride: ({
        required String deviceId,
        required String fingerprint,
      }) async {
        persisted[deviceId] = fingerprint;
      },
      clearPersistedFingerprintOverride: ({
        required String deviceId,
      }) async {
        persisted.remove(deviceId);
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
    );

    expect(registrations, isEmpty);
    expect(
      persisted['chat_dev_1'],
      pushTokenBindingFingerprint(
        token: 'tok-1',
        platform: 'android',
      ),
    );
  });

  test(
      'shamellReconcileCurrentPushBinding re-registers when only a legacy persisted fingerprint exists',
      () async {
    final registrations = <String>[];
    final persisted = <String, String>{
      'chat_dev_1': 'sha256:legacy-fingerprint',
    };

    await shamellReconcileCurrentPushBinding(
      baseUrlOverride: 'https://api.example.com',
      loadIdentityOverride: ({String? baseUrlOverride}) async =>
          const ChatIdentity(
        id: 'chat_dev_1',
        publicKeyB64: 'pk',
        privateKeyB64: 'sk',
        fingerprint: 'fp',
      ),
      registerTokenOverride: ({
        required String deviceId,
        required String token,
        String? platform,
      }) async {
        registrations.add('$deviceId|$token|$platform');
      },
      unregisterTokenOverride: ({
        required String deviceId,
      }) async {
        registrations.add('unexpected-unregister:$deviceId');
      },
      loadPersistedFingerprintOverride: ({
        required String deviceId,
      }) async =>
          persisted[deviceId],
      savePersistedFingerprintOverride: ({
        required String deviceId,
        required String fingerprint,
      }) async {
        persisted[deviceId] = fingerprint;
      },
      clearPersistedFingerprintOverride: ({
        required String deviceId,
      }) async {
        persisted.remove(deviceId);
      },
      ensurePermissionOverride: () async => NotificationPermissionState.granted,
      initializeFirebaseOverride: () async {},
      getTokenOverride: () async => 'tok-1',
    );

    expect(registrations, <String>['chat_dev_1|tok-1|android']);
    expect(
      persisted['chat_dev_1'],
      pushTokenBindingFingerprint(
        token: 'tok-1',
        platform: 'android',
      ),
    );
  });
}
