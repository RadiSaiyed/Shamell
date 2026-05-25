import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/device_binding_guard.dart';

void main() {
  test('ignores successful responses', () {
    expect(
      shamellIsCriticalDeviceBindingMismatch(
        statusCode: 200,
        rawBody: '{"detail":"device_id mismatch"}',
      ),
      isFalse,
    );
  });

  test('detects device_id mismatch from json detail', () {
    expect(
      shamellIsCriticalDeviceBindingMismatch(
        statusCode: 400,
        rawBody: '{"detail":"device_id mismatch"}',
      ),
      isTrue,
    );
  });

  test('detects client_device_id mismatch from plain text body', () {
    expect(
      shamellIsCriticalDeviceBindingMismatch(
        statusCode: 403,
        rawBody: 'client_device_id mismatch',
      ),
      isTrue,
    );
  });

  test('ignores unrelated validation errors', () {
    expect(
      shamellIsCriticalDeviceBindingMismatch(
        statusCode: 400,
        rawBody: '{"detail":"device_id required"}',
      ),
      isFalse,
    );
  });

  test('detects mismatch markers from generic exception text', () {
    expect(
      shamellContainsCriticalDeviceBindingDetail(
        'Exception: device_id mismatch',
      ),
      isTrue,
    );
  });

  test('ignores unrelated generic exception text', () {
    expect(
      shamellContainsCriticalDeviceBindingDetail(
        'Exception: Authentication required',
      ),
      isFalse,
    );
  });

  test('detects chat http exception drift as generic error object', () {
    expect(
      shamellIsCriticalDeviceBindingDriftError(
        const ChatHttpException(
          op: 'registerDevice',
          statusCode: 403,
          body: '{"detail":"client_device_id mismatch"}',
        ),
      ),
      isTrue,
    );
  });

  test('detects auth-session-required detail as critical account session', () {
    expect(
      shamellContainsCriticalAccountSessionDetail(
        '{"detail":"auth session required"}',
      ),
      isTrue,
    );
  });

  test('treats http 401 as critical account session failure', () {
    expect(
      shamellIsCriticalAccountSessionHttpFailure(
        statusCode: 401,
        rawBody: '{}',
      ),
      isTrue,
    );
  });

  test('ignores unrelated validation in account session helper', () {
    expect(
      shamellIsCriticalAccountSessionHttpFailure(
        statusCode: 400,
        rawBody: '{"detail":"device_id required"}',
      ),
      isFalse,
    );
  });
}
