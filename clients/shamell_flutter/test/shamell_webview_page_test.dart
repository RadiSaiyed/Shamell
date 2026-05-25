import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/shamell_webview_page.dart';

void main() {
  test('webview external launch uri allows bounded schemes only', () {
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('https://safe.example.com/x'),
      )?.toString(),
      'https://safe.example.com/x',
    );
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('mailto:help@shamell.test'),
      )?.toString(),
      'mailto:help@shamell.test',
    );
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('tel:+15551234567'),
      )?.toString(),
      'tel:+15551234567',
    );
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('http://127.0.0.1:8080/devtools'),
      )?.toString(),
      'http://127.0.0.1:8080/devtools',
    );
  });

  test('webview external launch uri rejects unsafe schemes and credentials',
      () {
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('javascript:alert(1)'),
      ),
      isNull,
    );
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('data:text/html,<script>alert(1)</script>'),
      ),
      isNull,
    );
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('file:///tmp/x'),
      ),
      isNull,
    );
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('intent://evil.test/#Intent;scheme=https;end'),
      ),
      isNull,
    );
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('https://user:pass@evil.test/x'),
      ),
      isNull,
    );
    expect(
      normalizeShamellWebViewExternalUri(
        Uri.parse('http://evil.test/plaintext'),
      ),
      isNull,
    );
  });

  test('webview dev session bridge uses only legacy session cookie payload',
      () {
    final cookies = buildShamellWebViewSessionBridgeCookies(
      baseUri: Uri.parse('http://localhost:8080/admin'),
      sessionToken: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(cookies, hasLength(3));
    expect(cookies.first.name, '__Host-sa_session');
    expect(cookies.first.value, isEmpty);
    expect(cookies[1].name, 'sa_session');
    expect(cookies[1].value, isEmpty);
    expect(cookies.last.name, 'sa_session');
    expect(cookies.last.value, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    expect(cookies.every((cookie) => cookie.domain == 'localhost'), isTrue);
    expect(cookies.every((cookie) => cookie.path == '/'), isTrue);
  });

  test('webview dev session bridge clears stale cookies when no token exists',
      () {
    final cookies = buildShamellWebViewSessionBridgeCookies(
      baseUri: Uri.parse('http://localhost:8081/admin'),
    );

    expect(cookies, hasLength(2));
    expect(cookies.first.name, '__Host-sa_session');
    expect(cookies.first.value, isEmpty);
    expect(cookies.last.name, 'sa_session');
    expect(cookies.last.value, isEmpty);
  });

  test('webview javascript is allowed only for trusted same-origin targets',
      () {
    expect(
      shamellWebViewAllowsJavaScript(
        initialUri: Uri.parse('https://mini.shamell.test/app'),
        baseUri: Uri.parse('https://mini.shamell.test'),
      ),
      isTrue,
    );
    expect(
      shamellWebViewAllowsJavaScript(
        initialUri: Uri.parse('http://127.0.0.1:8080/devtools'),
        baseUri: Uri.parse('http://127.0.0.1:8080'),
      ),
      isTrue,
    );
  });

  test('webview javascript is disabled for untrusted or basisless targets', () {
    expect(
      shamellWebViewAllowsJavaScript(
        initialUri: Uri.parse('https://evil.example/app'),
        baseUri: Uri.parse('https://mini.shamell.test'),
      ),
      isFalse,
    );
    expect(
      shamellWebViewAllowsJavaScript(
        initialUri: Uri.parse('https://mini.shamell.test/app'),
      ),
      isFalse,
    );
    expect(
      shamellWebViewAllowsJavaScript(
        initialUri: Uri.parse('http://mini.shamell.test/app'),
        baseUri: Uri.parse('http://mini.shamell.test'),
      ),
      isFalse,
    );
  });

  test('webview copied link is sensitive for same-origin or tokenized urls',
      () {
    final baseUri = Uri.parse('https://app.shamell.test');
    expect(
      shamellWebViewCopiedLinkIsSensitive(
        Uri.parse('https://app.shamell.test/admin/overview'),
        baseUri: baseUri,
      ),
      isTrue,
    );
    expect(
      shamellWebViewCopiedLinkIsSensitive(
        Uri.parse('https://external.example/invite?token=abc'),
        baseUri: baseUri,
      ),
      isTrue,
    );
    expect(
      shamellWebViewCopiedLinkIsSensitive(
        Uri.parse('https://external.example/page#frag'),
        baseUri: baseUri,
      ),
      isTrue,
    );
  });

  test('webview copied link is not sensitive for plain external urls', () {
    expect(
      shamellWebViewCopiedLinkIsSensitive(
        Uri.parse('https://external.example/page'),
        baseUri: Uri.parse('https://app.shamell.test'),
      ),
      isFalse,
    );
    expect(
      shamellWebViewCopiedLinkIsSensitive(
        Uri.parse('mailto:help@shamell.test'),
      ),
      isFalse,
    );
  });
}
