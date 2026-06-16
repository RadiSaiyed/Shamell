import 'package:flutter_test/flutter_test.dart';

import 'package:shamell_flutter/core/http_error.dart';

void main() {
  test('maps unauthorized detail to sign-in required', () {
    final msg = sanitizeHttpError(
      statusCode: 401,
      rawBody: '{"detail":"internal auth required"}',
      isArabic: false,
    );
    expect(msg, 'Sign-in required.');
  });

  test('maps rate limiting to friendly retry message', () {
    final msg = sanitizeHttpError(
      statusCode: 429,
      rawBody: '{"detail":"too many attempts"}',
      isArabic: false,
    );
    expect(msg, 'Too many requests. Try again later.');
  });

  test('maps server errors to generic message', () {
    final msg = sanitizeHttpError(
      statusCode: 500,
      rawBody: '{"detail":"stacktrace..."}',
      isArabic: false,
    );
    expect(msg, 'Server error. Try again later.');
  });

  test('does not expose raw backend detail for 400', () {
    final msg = sanitizeHttpError(
      statusCode: 400,
      rawBody: '{"detail":"internal auth required"}',
      isArabic: false,
    );
    expect(msg, 'Sign-in required.');
  });
}
