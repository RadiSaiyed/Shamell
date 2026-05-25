import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/base64_bytes_cache.dart';

void main() {
  test('Base64BytesCache reuses decoded bytes and caches invalid payloads', () {
    final cache = Base64BytesCache(maxEntries: 4);

    final first = cache.decode(base64Encode(utf8.encode('hello')));
    final second = cache.decode(base64Encode(utf8.encode('hello')));
    final invalidFirst = cache.decode('%%%');
    final invalidSecond = cache.decode('%%%');

    expect(first, isNotNull);
    expect(utf8.decode(first!), 'hello');
    expect(identical(first, second), isTrue);
    expect(invalidFirst, isNull);
    expect(invalidSecond, isNull);
    expect(cache.size, 2);
  });

  test('Base64BytesCache evicts the oldest cached entry at capacity', () {
    final cache = Base64BytesCache(maxEntries: 2);
    final firstPayload = base64Encode(utf8.encode('one'));
    final secondPayload = base64Encode(utf8.encode('two'));
    final thirdPayload = base64Encode(utf8.encode('three'));

    final first = cache.decode(firstPayload);
    cache.decode(secondPayload);
    cache.decode(thirdPayload);
    final firstAfterEviction = cache.decode(firstPayload);

    expect(cache.size, 2);
    expect(first, isNotNull);
    expect(firstAfterEviction, isNotNull);
    expect(identical(first, firstAfterEviction), isFalse);
  });
}
