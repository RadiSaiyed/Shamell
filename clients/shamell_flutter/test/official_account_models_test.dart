import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/official_account_models.dart';

void main() {
  test('normalizeOfficialRemoteImageUrl allows https and local dev http only',
      () {
    expect(
      normalizeOfficialRemoteImageUrl('https://cdn.shamell.test/avatar.png'),
      'https://cdn.shamell.test/avatar.png',
    );
    expect(
      normalizeOfficialRemoteImageUrl('http://127.0.0.1:8080/avatar.png'),
      'http://127.0.0.1:8080/avatar.png',
    );
    expect(
      normalizeOfficialRemoteImageUrl('http://cdn.shamell.test/avatar.png'),
      isNull,
    );
    expect(
      normalizeOfficialRemoteImageUrl('data:image/png;base64,AAAA'),
      isNull,
    );
    expect(normalizeOfficialRemoteImageUrl('javascript:alert(1)'), isNull);
    expect(normalizeOfficialRemoteImageUrl('file:///tmp/x.png'), isNull);
  });

  test('release mode rejects non-local plaintext media and website urls', () {
    expect(
      normalizeOfficialRemoteHttpUrlForRuntime(
        'http://cdn.shamell.test/avatar.png',
        releaseMode: true,
      ),
      isNull,
    );
    expect(
      normalizeOfficialRemoteHttpUrlForRuntime(
        'http://www.shamell.test/shop',
        releaseMode: true,
      ),
      isNull,
    );
    expect(
      normalizeOfficialRemoteHttpUrlForRuntime(
        'http://127.0.0.1:8080/avatar.png',
        releaseMode: true,
      ),
      'http://127.0.0.1:8080/avatar.png',
    );
  });

  test('OfficialAccountHandle.fromJson drops unsafe avatar urls', () {
    final unsafe = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_1',
      'kind': 'service',
      'name': 'Demo',
      'avatar_url': 'data:image/svg+xml;base64,AAAA',
    });
    expect(unsafe.avatarUrl, isNull);

    final safe = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_1',
      'kind': 'service',
      'name': 'Demo',
      'avatar_url': 'https://cdn.shamell.test/avatar.png',
    });
    expect(safe.avatarUrl, 'https://cdn.shamell.test/avatar.png');
  });

  test('official avatar autoload only allows same-origin media', () {
    expect(
      normalizeOfficialRemoteImageUrlForAutoloadRuntime(
        'https://api.example.com/media/avatar.png',
        baseUrl: 'https://api.example.com',
        releaseMode: true,
      ),
      'https://api.example.com/media/avatar.png',
    );
    expect(
      normalizeOfficialRemoteImageUrlForAutoloadRuntime(
        'https://cdn.shamell.test/avatar.png',
        baseUrl: 'https://api.example.com',
        releaseMode: true,
      ),
      isNull,
    );
    expect(
      normalizeOfficialRemoteImageUrlForAutoloadRuntime(
        'http://127.0.0.1:8080/avatar.png',
        baseUrl: 'http://127.0.0.1:8080',
        releaseMode: false,
      ),
      'http://127.0.0.1:8080/avatar.png',
    );
  });

  test('normalizeOfficialRemoteWebsiteUrl allows https and local dev http only',
      () {
    expect(
      normalizeOfficialRemoteWebsiteUrl('https://www.shamell.test/shop'),
      'https://www.shamell.test/shop',
    );
    expect(
      normalizeOfficialRemoteWebsiteUrl('http://127.0.0.1:8080/shop'),
      'http://127.0.0.1:8080/shop',
    );
    expect(
      normalizeOfficialRemoteWebsiteUrl('http://www.shamell.test/shop'),
      isNull,
    );
    expect(normalizeOfficialRemoteWebsiteUrl('javascript:alert(1)'), isNull);
    expect(normalizeOfficialRemoteWebsiteUrl('file:///tmp/x.html'), isNull);
  });

  test('OfficialAccountHandle.fromJson drops unsafe website urls', () {
    final unsafe = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_1',
      'kind': 'service',
      'name': 'Demo',
      'website_url': 'javascript:alert(1)',
    });
    expect(unsafe.websiteUrl, isNull);

    final safe = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_1',
      'kind': 'service',
      'name': 'Demo',
      'website_url': 'https://www.shamell.test/shop',
    });
    expect(safe.websiteUrl, 'https://www.shamell.test/shop');
  });

  test('normalizeOfficialQrPayload rejects oversized or control payloads', () {
    expect(
      normalizeOfficialQrPayload('shamell://official/shop_1'),
      'shamell://official/shop_1',
    );
    expect(normalizeOfficialQrPayload('bad\u0000payload'), isNull);
    expect(normalizeOfficialQrPayload('x' * 1025), isNull);
  });

  test('OfficialAccountHandle.fromJson drops unsafe qr payloads', () {
    final unsafe = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_1',
      'kind': 'service',
      'name': 'Demo',
      'qr_payload': 'bad\u0000payload',
    });
    expect(unsafe.qrPayload, isNull);

    final safe = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_1',
      'kind': 'service',
      'name': 'Demo',
      'qr_payload': 'shamell://official/shop_1',
    });
    expect(safe.qrPayload, 'shamell://official/shop_1');
  });

  test('OfficialAccountHandle.fromJson ignores legacy menu_items payload', () {
    final handle = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_1',
      'kind': 'service',
      'name': 'Demo',
      'menu_items': <Map<String, Object?>>[
        <String, Object?>{'title': 'Legacy menu'},
      ],
      'followed': true,
    });

    expect(handle.id, 'acc_1');
    expect(handle.followed, isTrue);
  });

  test('OfficialAccountHandle.fromJson prefers canonical mini program id', () {
    final canonical = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_1',
      'kind': 'service',
      'name': 'Demo',
      'mini_program_id': 'payments',
      'module_app_id': 'legacy_payments',
    });
    expect(canonical.moduleAppId, 'payments');

    final legacy = OfficialAccountHandle.fromJson(<String, dynamic>{
      'id': 'acc_2',
      'kind': 'service',
      'name': 'Demo',
      'module_app_id': 'bus',
    });
    expect(legacy.moduleAppId, 'bus');
  });
}
