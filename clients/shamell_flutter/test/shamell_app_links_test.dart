import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/shamell_app_links.dart';

void main() {
  test('buildShamellAppLinkUri normalizes host/path/query values', () {
    final uri = buildShamellAppLinkUri(
      '  INVITE  ',
      pathSegments: const <String>['  token  ', '', ' value '],
      queryParameters: const <String, String>{
        '  a  ': '  1  ',
        ' ': '2',
        'b': ' ',
      },
    );

    expect(
      uri.toString(),
      'https://online.shamell.online/app/invite/token/value?a=1',
    );
  });

  test('buildShamellInviteAppLink keeps token out of query parameters', () {
    final uri = buildShamellInviteAppLink('abc123');

    expect(uri.host, shamellAppLinkHost);
    expect(uri.path, '/app/invite');
    expect(uri.query, isEmpty);
    expect(uri.fragment, 'token=abc123');
    expect(
      uri.toString(),
      'https://online.shamell.online/app/invite#token=abc123',
    );
  });

  test(
      'buildShamellDeviceLoginAppLink keeps token/label in fragment and URL-encodes label',
      () {
    final uri = buildShamellDeviceLoginAppLink(
      token: 'abc123',
      label: 'Demo Phone',
    );

    expect(uri.host, shamellAppLinkHost);
    expect(uri.path, '/app/device_login');
    expect(uri.query, isEmpty);
    expect(uri.fragment, 'token=abc123&label=Demo+Phone');
    expect(
      uri.toString(),
      'https://online.shamell.online/app/device_login#token=abc123&label=Demo+Phone',
    );
  });
}
