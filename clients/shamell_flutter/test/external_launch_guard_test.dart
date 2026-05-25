import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/external_launch_guard.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('external launch mode forces external application for tel and mailto',
      () {
    expect(
      shamellExternalLaunchMode(Uri.parse('tel:+15551234567')),
      LaunchMode.externalApplication,
    );
    expect(
      shamellExternalLaunchMode(Uri.parse('mailto:help@example.com')),
      LaunchMode.externalApplication,
    );
  });

  test('external launch mode keeps unknown schemes on platform default', () {
    expect(
      shamellExternalLaunchMode(Uri.parse('sms:+15551234567')),
      LaunchMode.platformDefault,
    );
  });

  test('normalizeExternalMapUri allows bounded finite coordinates only', () {
    expect(
      normalizeExternalMapUri(latitude: 35.529167, longitude: 35.790278)
          ?.toString(),
      'https://www.google.com/maps/search/?api=1&query=35.529167%2C35.790278',
    );
    expect(normalizeExternalMapUri(latitude: double.nan, longitude: 1), isNull);
    expect(normalizeExternalMapUri(latitude: 91, longitude: 1), isNull);
    expect(normalizeExternalMapUri(latitude: 1, longitude: -181), isNull);
  });

  test('normalizeExternalDialUri rejects malformed or oversized numbers', () {
    expect(
      normalizeExternalDialUri('+1 (555) 123-4567')?.toString(),
      'tel:+15551234567',
    );
    expect(normalizeExternalDialUri('12'), isNull);
    expect(normalizeExternalDialUri('++1555'), isNull);
    expect(normalizeExternalDialUri('9' * 40), isNull);
  });

  test('normalizeExternalTranslateUri bounds language and text input', () {
    expect(
      normalizeExternalTranslateUri(
        'hello world',
        targetLanguage: 'en',
      )?.toString(),
      'https://translate.google.com/?sl=auto&tl=en&text=hello+world',
    );
    expect(
      normalizeExternalTranslateUri(
        'bad\u0000payload',
        targetLanguage: 'en',
      ),
      isNull,
    );
    expect(
      normalizeExternalTranslateUri(
        'hello',
        targetLanguage: 'javascript',
      ),
      isNull,
    );
    expect(
      normalizeExternalTranslateUri(
        'x' * 2001,
        targetLanguage: 'en',
      ),
      isNull,
    );
  });
}
