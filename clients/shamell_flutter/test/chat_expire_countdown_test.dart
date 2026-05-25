import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_expire_countdown.dart';

void main() {
  test('zero or negative remaining → empty', () {
    expect(formatExpireCountdown(Duration.zero), '');
    expect(formatExpireCountdown(const Duration(seconds: -5)), '');
  });

  test('seconds-resolution under 1 minute', () {
    expect(formatExpireCountdown(const Duration(seconds: 1)), '1s');
    expect(formatExpireCountdown(const Duration(seconds: 30)), '30s');
    expect(formatExpireCountdown(const Duration(seconds: 59)), '59s');
  });

  test('minutes-resolution under 1 hour', () {
    expect(formatExpireCountdown(const Duration(minutes: 1)), '1m');
    expect(formatExpireCountdown(const Duration(minutes: 30)), '30m');
    expect(formatExpireCountdown(const Duration(minutes: 59, seconds: 59)),
        '59m');
  });

  test('hours-resolution under 24h', () {
    expect(formatExpireCountdown(const Duration(hours: 1)), '1h');
    expect(formatExpireCountdown(const Duration(hours: 12)), '12h');
    expect(formatExpireCountdown(const Duration(hours: 23, minutes: 59)),
        '23h');
  });

  test('days-resolution at 24h+', () {
    expect(formatExpireCountdown(const Duration(days: 1)), '1d');
    expect(formatExpireCountdown(const Duration(days: 7)), '7d');
    expect(formatExpireCountdown(const Duration(days: 99)), '99d');
  });

  test('caps at >99d for very-far-future windows', () {
    expect(formatExpireCountdown(const Duration(days: 100)), '>99d');
    expect(formatExpireCountdown(const Duration(days: 365)), '>99d');
  });
}
