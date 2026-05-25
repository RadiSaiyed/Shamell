import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/shamell_moments_composer_page.dart';

void main() {
  test('reverse geocode uri rounds coordinates before first-party proxy call',
      () {
    final uri = shamellMomentsReverseGeocodeUri(
      baseUrl: 'https://api.example.com',
      lat: 36.8064948123,
      lon: 10.1815317456,
    );

    expect(uri, isNotNull);
    expect(uri!.host, 'api.example.com');
    expect(uri.path, '/me/geo/reverse');
    expect(uri.queryParameters['lat'], '36.8065');
    expect(uri.queryParameters['lon'], '10.1815');
  });

  test('location search uri stays on first-party origin', () {
    final uri = shamellMomentsLocationSearchUri(
      baseUrl: 'https://api.example.com',
      query: ' Tunis ',
    );

    expect(uri, isNotNull);
    expect(uri!.host, 'api.example.com');
    expect(uri.path, '/me/geo/search');
    expect(uri.queryParameters['q'], 'Tunis');
  });
}
