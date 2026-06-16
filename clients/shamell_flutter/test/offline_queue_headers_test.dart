import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/offline_queue.dart';

void main() {
  test('sanitizeOfflineHeadersForStorage strips sensitive headers', () {
    final input = <String, String>{
      'cookie': '__Host-sa_session=abcd',
      'Authorization': 'Bearer secret',
      'Idempotency-Key': 'k1',
      'X-Device-ID': 'd1',
      '': 'ignored',
    };

    final out = sanitizeOfflineHeadersForStorage(input);
    expect(out.containsKey('cookie'), isFalse);
    expect(out.containsKey('Authorization'), isFalse);
    expect(out['Idempotency-Key'], 'k1');
    expect(out['X-Device-ID'], 'd1');
  });

  test('offlineAuthBaseFromTaskUrl extracts normalized base URL', () {
    expect(
      offlineAuthBaseFromTaskUrl('https://Api.Shamell.Online:8443/payments/x'),
      'https://api.shamell.online:8443',
    );
    expect(
      offlineAuthBaseFromTaskUrl('http://localhost:8080/path?q=1'),
      'http://localhost:8080',
    );
    expect(offlineAuthBaseFromTaskUrl('not a url'), isNull);
    expect(offlineAuthBaseFromTaskUrl('mailto:test@example.com'), isNull);
  });
}
