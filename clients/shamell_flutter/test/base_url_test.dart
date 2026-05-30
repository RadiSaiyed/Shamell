import 'package:flutter_test/flutter_test.dart';

import 'package:shamell_flutter/core/base_url.dart';

void main() {
  test('isSecureApiBaseUrl allows https and localhost http only', () {
    expect(isSecureApiBaseUrl('https://api.shamell.online'), isTrue);
    expect(isSecureApiBaseUrl('http://localhost:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://127.0.0.1:8080'), isTrue);
    expect(isSecureApiBaseUrl('http://api.shamell.online'), isFalse);
    expect(isSecureApiBaseUrl('api.shamell.online'), isFalse);
    expect(isSecureApiBaseUrl(''), isFalse);
  });
}

