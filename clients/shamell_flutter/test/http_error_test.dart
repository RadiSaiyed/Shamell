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

  test('maps rate limiting with retry_after_secs to countdown message', () {
    final msg = sanitizeHttpError(
      statusCode: 429,
      rawBody: '{"detail":"too many requests; retry_after_secs=23"}',
      isArabic: false,
    );
    expect(msg, 'Too many requests. Try again in 23s.');
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

  test('maps contact invite requirement to friendly message', () {
    final msg = sanitizeExceptionForUi(
      error: Exception('contact invite required'),
      isArabic: false,
    );
    expect(
      msg,
      'Adding a new contact requires an invite token or QR from the other person.',
    );
  });

  test('maps too many requests exception to friendly retry message', () {
    final msg = sanitizeExceptionForUi(
      error: Exception('too many requests; retry_after_secs=12'),
      isArabic: false,
    );
    expect(msg, 'Too many requests. Try again in 12s.');
  });

  test('maps oversized group avatar to friendly message', () {
    final msg = sanitizeHttpError(
      statusCode: 400,
      rawBody: '{"detail":"group avatar too large"}',
      isArabic: false,
    );
    expect(msg, 'Group photo is too large. Choose a smaller image.');
  });

  test('maps unsupported group avatar mime to friendly message', () {
    final msg = sanitizeHttpError(
      statusCode: 400,
      rawBody: '{"detail":"invalid avatar_mime"}',
      isArabic: false,
    );
    expect(msg, 'Unsupported group photo format.');
  });

  test('maps oversized direct message envelope to friendly message', () {
    final msg = sanitizeHttpError(
      statusCode: 400,
      rawBody: '{"detail":"direct message too large"}',
      isArabic: false,
    );
    expect(msg, 'Message is too large to send securely.');
  });

  test('maps local oversized direct message exception to friendly message', () {
    final msg = sanitizeExceptionForUi(
      error: StateError('direct message too large'),
      isArabic: false,
    );
    expect(msg, 'Message is too large to send securely.');
  });

  test('maps invalid official feed thumbnail url to friendly message', () {
    final msg = sanitizeHttpError(
      statusCode: 400,
      rawBody: '{"detail":"invalid thumb_url"}',
      isArabic: false,
    );
    expect(
      msg,
      'Use a valid https image URL, or localhost http for development only.',
    );
  });

  test('maps redeem-own-invite detail to explicit self-add message', () {
    final msg = sanitizeHttpError(
      statusCode: 400,
      rawBody: '{"detail":"cannot redeem own invite"}',
      isArabic: false,
    );
    expect(
      msg,
      'You cannot add yourself as a contact. Scan another person\'s invite QR.',
    );
  });

  test('maps invalid invite token exception to explicit validation message',
      () {
    final msg = sanitizeExceptionForUi(
      error: Exception('invalid token'),
      isArabic: false,
    );
    expect(msg, 'Invalid invite token.');
  });

  test('maps unregistered chat device detail to actionable retry message', () {
    final msg = sanitizeHttpError(
      statusCode: 409,
      rawBody: '{"detail":"chat device not registered"}',
      isArabic: false,
    );
    expect(
        msg, 'This device is not linked to the account yet. Please try again.');
  });

  test('maps superapp same-origin guard to invalid server url', () {
    final msg = sanitizeExceptionForUi(
      error: ArgumentError(
        'Superapp API only allows same-origin http(s) requests.',
      ),
      isArabic: false,
    );
    expect(msg, 'Invalid server URL.');
  });

  test('maps own-shamell-id resolve detail to explicit self-add message', () {
    final msg = sanitizeHttpError(
      statusCode: 400,
      rawBody: '{"detail":"cannot add own shamell id"}',
      isArabic: false,
    );
    expect(msg, 'You cannot add your own SyrChat ID.');
  });
}
