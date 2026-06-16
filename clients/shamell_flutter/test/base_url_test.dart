import 'package:flutter_test/flutter_test.dart';

import 'package:shamell_flutter/core/base_url.dart';

void main() {
  test('isSecureApiBaseUrl allows https and local-network http in dev', () {
    expect(isSecureApiBaseUrl('https://api.shamell.online'), isTrue);
    expect(isSecureApiBaseUrl('http://localhost:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://127.0.0.1:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://192.168.1.10:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://10.0.0.10:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://172.20.1.7:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://devbox.local:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://api.shamell.online'), isFalse);
    expect(isSecureApiBaseUrl('api.shamell.online'), isFalse);
    expect(isSecureApiBaseUrl(''), isFalse);
  });
}
