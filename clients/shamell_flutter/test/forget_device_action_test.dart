import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shamell_flutter/core/forget_device_action.dart';

void main() {
  test('forgetDeviceOnServer sends authenticated delete to device endpoint',
      () async {
    final mock = MockClient((req) async {
      expect(req.method, 'DELETE');
      expect(
        req.url.toString(),
        'https://api.shamell.test/auth/devices/device_123',
      );
      expect(req.headers['cookie'], 'session-cookie');
      return http.Response('{"status":"ok"}', 200, headers: {
        'content-type': 'application/json',
      });
    });

    await forgetDeviceOnServer(
      baseUrl: 'https://api.shamell.test',
      deviceId: 'device_123',
      sessionCookie: 'session-cookie',
      isArabic: false,
      client: mock,
    );
  });

  test('forgetDeviceOnServer adds localhost client-ip hint for loopback bases',
      () async {
    final mock = MockClient((req) async {
      expect(req.method, 'DELETE');
      expect(
          req.url.toString(), 'http://127.0.0.1:8080/auth/devices/device_123');
      expect(req.headers['cookie'], 'session-cookie');
      expect(req.headers['x-shamell-client-ip'], '127.0.0.1');
      return http.Response('{"status":"ok"}', 200, headers: {
        'content-type': 'application/json',
      });
    });

    await forgetDeviceOnServer(
      baseUrl: 'http://127.0.0.1:8080',
      deviceId: 'device_123',
      sessionCookie: 'session-cookie',
      isArabic: false,
      client: mock,
    );
  });

  test('forgetDeviceOnServer rejects ignored server removals', () async {
    final mock = MockClient((_) async {
      return http.Response('{"status":"ignored"}', 200, headers: {
        'content-type': 'application/json',
      });
    });

    expect(
      () => forgetDeviceOnServer(
        baseUrl: 'https://api.shamell.test',
        deviceId: 'device_123',
        sessionCookie: 'session-cookie',
        isArabic: false,
        client: mock,
      ),
      throwsA(
        isA<ForgetDeviceException>().having(
          (e) => e.message,
          'message',
          'Could not confirm device removal on the server.',
        ),
      ),
    );
  });

  test('forgetDeviceOnServer surfaces sanitized auth failures', () async {
    final mock = MockClient((_) async {
      return http.Response('{"detail":"unauthorized"}', 401, headers: {
        'content-type': 'application/json',
      });
    });

    expect(
      () => forgetDeviceOnServer(
        baseUrl: 'https://api.shamell.test',
        deviceId: 'device_123',
        sessionCookie: 'session-cookie',
        isArabic: false,
        client: mock,
      ),
      throwsA(
        isA<ForgetDeviceException>().having(
          (e) => e.message,
          'message',
          'Sign-in required.',
        ),
      ),
    );
  });

  test('forgetDeviceOnServer rejects malformed base urls before network',
      () async {
    var called = false;
    final mock = MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    });

    expect(
      () => forgetDeviceOnServer(
        baseUrl: 'https://user:pass@api.shamell.test',
        deviceId: 'device_123',
        sessionCookie: 'session-cookie',
        isArabic: false,
        client: mock,
      ),
      throwsA(
        isA<ForgetDeviceException>().having(
          (e) => e.message,
          'message',
          'Invalid server URL.',
        ),
      ),
    );
    expect(called, isFalse);
  });
}
