import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/offline_queue.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => <String>[]).add(
          value.toString(),
        );
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = <String>[value.toString()];
  }

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(',');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticHttpClient implements HttpClient {
  _StaticHttpClient({
    required this.statusCode,
    required this.responseBody,
    this.onRequestClosed,
  });

  final int statusCode;
  final String responseBody;
  final Future<void> Function(Uri uri, String method, String body)?
      onRequestClosed;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = Duration.zero;

  @override
  int? maxConnectionsPerHost;

  @override
  bool Function(X509Certificate cert, String host, int port)?
      badCertificateCallback;

  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _StaticHttpRequest(
      method: method,
      uri: url,
      statusCode: statusCode,
      responseBody: responseBody,
      onClosed: onRequestClosed,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticHttpRequest implements HttpClientRequest {
  _StaticHttpRequest({
    required this.method,
    required this.uri,
    required this.statusCode,
    required this.responseBody,
    required Future<void> Function(Uri uri, String method, String body)?
        onClosed,
  }) : _onClosed = onClosed;

  final Future<void> Function(Uri uri, String method, String body)? _onClosed;
  final List<int> _writtenBody = <int>[];

  @override
  final String method;

  @override
  final Uri uri;

  final int statusCode;
  final String responseBody;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  Encoding encoding = utf8;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _writtenBody.addAll(chunk);
    }
  }

  @override
  void add(List<int> data) {
    _writtenBody.addAll(data);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    final onClosed = _onClosed;
    if (onClosed != null) {
      await onClosed(uri, method, utf8.decode(_writtenBody));
    }
    return _StaticHttpResponse(
      statusCode: statusCode,
      body: responseBody,
    );
  }

  @override
  Future<HttpClientResponse> get done => close();

  @override
  void write(Object? obj) {
    add(encoding.encode(obj?.toString() ?? ''));
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    add(<int>[charCode]);
  }

  @override
  void writeln([Object? obj = '']) {
    write('${obj ?? ''}\n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _StaticHttpResponse({
    required int statusCode,
    required String body,
  })  : _statusCode = statusCode,
        _body = utf8.encode(body) {
    headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  }

  final List<int> _body;

  final int _statusCode;

  final HttpHeaders _headers = _FakeHttpHeaders();

  @override
  int get statusCode => _statusCode;

  @override
  HttpHeaders get headers => _headers;

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  int get contentLength => _body.length;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  Future<Socket> detachSocket() {
    throw UnimplementedError();
  }

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'Mocked';

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_body]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secStore = <String, String>{};
  var throwOnSecureRead = false;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secChannel,
      (call) async {
        final args = (call.arguments as Map?) ?? const <String, Object?>{};
        final key = (args['key'] ?? '').toString();
        switch (call.method) {
          case 'write':
            secStore[key] = (args['value'] ?? '').toString();
            return null;
          case 'read':
            if (throwOnSecureRead) {
              throw PlatformException(code: 'secure-read-failed');
            }
            return secStore[key];
          case 'delete':
            secStore.remove(key);
            return null;
          case 'deleteAll':
            secStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secStore);
          case 'containsKey':
            return secStore.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secStore.clear();
    throwOnSecureRead = false;
    await OfflineQueue.clearPersistentState();
  });

  test('sanitizeOfflineHeadersForStorage strips sensitive headers', () {
    final input = <String, String>{
      'cookie': '__Host-sa_session=abcd',
      'Authorization': 'Bearer secret',
      'X-Role-Auth': 'edge-secret',
      'X-Auth-Roles': 'admin',
      'X-Internal-Service-Id': 'bff',
      'X-Internal-Audience': 'payments',
      'X-Internal-Identity-TS': '1710000000',
      'X-Internal-Identity-Nonce': 'nonce123',
      'X-Internal-Identity-Sig': 'sig-v1',
      'X-Internal-Identity-Sig-V2': 'sig-v2',
      'X-SyrChat-Payment-Attestation-Challenge': 'challenge-token',
      'X-SyrChat-Payment-Play-Integrity': 'integrity-token',
      'X-SyrChat-Payment-Apple-DeviceCheck': 'devicecheck-token',
      'Idempotency-Key': 'k1',
      'X-Device-ID': 'd1',
      '': 'ignored',
    };

    final out = sanitizeOfflineHeadersForStorage(input);
    expect(out.containsKey('cookie'), isFalse);
    expect(out.containsKey('Authorization'), isFalse);
    expect(out.containsKey('X-Role-Auth'), isFalse);
    expect(out.containsKey('X-Auth-Roles'), isFalse);
    expect(out.containsKey('X-Internal-Service-Id'), isFalse);
    expect(out.containsKey('X-Internal-Audience'), isFalse);
    expect(out.containsKey('X-Internal-Identity-TS'), isFalse);
    expect(out.containsKey('X-Internal-Identity-Nonce'), isFalse);
    expect(out.containsKey('X-Internal-Identity-Sig'), isFalse);
    expect(out.containsKey('X-Internal-Identity-Sig-V2'), isFalse);
    expect(
      out.containsKey('X-SyrChat-Payment-Attestation-Challenge'),
      isFalse,
    );
    expect(out.containsKey('X-SyrChat-Payment-Play-Integrity'), isFalse);
    expect(out.containsKey('X-SyrChat-Payment-Apple-DeviceCheck'), isFalse);
    expect(out['Idempotency-Key'], 'k1');
    expect(out['X-Device-ID'], 'd1');
  });

  test('offlineTaskHasReplayProtection requires idempotency for mutations', () {
    expect(
      offlineTaskHasReplayProtection(
        OfflineTask(
          id: 'get-1',
          method: 'GET',
          url: 'https://api.example.com/status',
          headers: const <String, String>{},
          body: '',
          tag: 'status',
          createdAt: 1,
        ),
      ),
      isTrue,
    );
    expect(
      offlineTaskHasReplayProtection(
        OfflineTask(
          id: 'post-1',
          method: 'POST',
          url: 'https://api.example.com/pay',
          headers: const <String, String>{'X-Device-ID': 'd1'},
          body: '{}',
          tag: 'payments_transfer',
          createdAt: 2,
        ),
      ),
      isFalse,
    );
    expect(
      offlineTaskHasReplayProtection(
        OfflineTask(
          id: 'post-2',
          method: 'POST',
          url: 'https://api.example.com/pay',
          headers: const <String, String>{
            'Idempotency-Key': 'ikey-1',
            'X-Device-ID': 'd1',
          },
          body: '{}',
          tag: 'payments_transfer',
          createdAt: 3,
        ),
      ),
      isTrue,
    );
  });

  test('offlineAuthBaseFromTaskUrl extracts normalized base URL', () {
    expect(
      offlineAuthBaseFromTaskUrl('https://Api.SyrChat.Online:8443/payments/x'),
      'https://api.shamell.online:8443',
    );
    expect(
      offlineAuthBaseFromTaskUrl('http://localhost:8080/path?q=1'),
      'http://localhost:8080',
    );
    expect(offlineAuthBaseFromTaskUrl('not a url'), isNull);
    expect(offlineAuthBaseFromTaskUrl('mailto:test@example.com'), isNull);
  });

  test('offlineTaskMayAttachSessionCookie only trusts same-origin base URL',
      () {
    expect(
      offlineTaskMayAttachSessionCookie(
        'https://api.shamell.online/payments/send',
        configuredBaseUrl: 'https://api.shamell.online',
      ),
      isTrue,
    );
    expect(
      offlineTaskMayAttachSessionCookie(
        'https://api.shamell.online:8443/payments/send',
        configuredBaseUrl: 'https://api.shamell.online',
      ),
      isFalse,
    );
    expect(
      offlineTaskMayAttachSessionCookie(
        'https://evil.test/payments/send',
        configuredBaseUrl: 'https://api.shamell.online',
      ),
      isFalse,
    );
    expect(
      offlineTaskMayAttachSessionCookie(
        'https://api.shamell.online/payments/send',
        configuredBaseUrl: 'https://user:pass@api.shamell.online',
      ),
      isFalse,
    );
  });

  test('buildOfflineHeadersForTask reattaches session cookie only same-origin',
      () async {
    await setSessionTokenForBaseUrl(
      'https://api.shamell.online',
      '0123456789abcdef0123456789abcdef',
    );
    final task = OfflineTask(
      id: 't-cookie',
      method: 'POST',
      url: 'https://api.shamell.online/payments/send',
      headers: <String, String>{
        'Idempotency-Key': 'k1',
        'Cookie': 'old=stale',
      },
      body: '{}',
      tag: 'payments_transfer',
      createdAt: 3,
    );

    final sameOrigin = await buildOfflineHeadersForTask(
      task,
      configuredBaseUrl: 'https://api.shamell.online',
    );
    expect(
      sameOrigin['cookie'],
      '__Host-sa_session=0123456789abcdef0123456789abcdef',
    );
    expect(sameOrigin['Idempotency-Key'], 'k1');

    final crossOrigin = await buildOfflineHeadersForTask(
      task,
      configuredBaseUrl: 'https://evil.test',
    );
    expect(crossOrigin.containsKey('cookie'), isFalse);
    expect(crossOrigin['Idempotency-Key'], 'k1');
  });

  test(
      'buildOfflineHeadersForTask adds localhost client-ip hint for trusted loopback tasks',
      () async {
    await setSessionTokenForBaseUrl(
      'http://127.0.0.1:8080',
      '0123456789abcdef0123456789abcdef',
    );
    final task = OfflineTask(
      id: 't-localhost-cookie',
      method: 'POST',
      url: 'http://127.0.0.1:8080/payments/send',
      headers: <String, String>{'Idempotency-Key': 'k2'},
      body: '{}',
      tag: 'payments_transfer',
      createdAt: 4,
    );

    final headers = await buildOfflineHeadersForTask(
      task,
      configuredBaseUrl: 'http://127.0.0.1:8080',
    );
    expect(
      headers['cookie'],
      '__Host-sa_session=0123456789abcdef0123456789abcdef',
    );
    expect(headers['x-shamell-client-ip'], '127.0.0.1');
    expect(headers['Idempotency-Key'], 'k2');
  });

  test('offlineTaskShouldDropAfterHttpFailure drops permanent auth failures',
      () {
    expect(
      offlineTaskShouldDropAfterHttpFailure(
        statusCode: 401,
        rawBody: '{"detail":"auth session required"}',
      ),
      isTrue,
    );
    expect(
      offlineTaskShouldDropAfterHttpFailure(
        statusCode: 400,
        rawBody: '{"detail":"device_id mismatch"}',
      ),
      isTrue,
    );
    expect(
      offlineTaskShouldDropAfterHttpFailure(
        statusCode: 403,
        rawBody: '{"detail":"attestation required"}',
      ),
      isTrue,
    );
    expect(
      offlineTaskShouldDropAfterHttpFailure(
        statusCode: 400,
        rawBody: '{"detail":"device attestation unavailable"}',
      ),
      isTrue,
    );
    expect(
      offlineTaskShouldDropAfterHttpFailure(
        statusCode: 500,
        rawBody: '{"detail":"server error"}',
      ),
      isFalse,
    );
  });

  test('offline queue ignores legacy plaintext prefs by default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'offline_queue_v1': <String>[
        '{"id":"t1","method":"POST","url":"https://api.example.com/pay","headers":{"Cookie":"secret","Idempotency-Key":"k1","X-Device-ID":"d1"},"body":"{\\"amount\\":7,\\"to\\":\\"u1\\"}","tag":"payments_transfer","createdAt":1,"retries":0,"nextAt":0}',
      ],
    });

    await OfflineQueue.init();

    final pending = OfflineQueue.pending();
    expect(pending, isEmpty);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('offline_queue_v1'), isNull);
  });

  test(
      'offline queue remains enqueueable after fail-closed init with empty secure store',
      () async {
    await OfflineQueue.init();

    await OfflineQueue.enqueue(
      OfflineTask(
        id: 'enqueue-after-init',
        method: 'POST',
        url: 'https://api.example.com/pay',
        headers: const <String, String>{
          'Idempotency-Key': 'k-enqueue-after-init',
          'X-Device-ID': 'd1',
        },
        body: '{"amount":11}',
        tag: 'payments_transfer',
        createdAt: 11,
      ),
    );

    final pending = OfflineQueue.pending(tag: 'payments_transfer');
    expect(pending, hasLength(1));
    expect(pending.first.id, 'enqueue-after-init');
  });

  test('offline queue allows legacy plaintext prefs when secure reads fail',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'offline_queue_v1': <String>[
        '{"id":"t1","method":"POST","url":"https://api.example.com/pay","headers":{"Cookie":"secret","Idempotency-Key":"k1","X-Device-ID":"d1"},"body":"{\\"amount\\":7,\\"to\\":\\"u1\\"}","tag":"payments_transfer","createdAt":1,"retries":0,"nextAt":0}',
      ],
    });
    throwOnSecureRead = true;

    await OfflineQueue.init();

    final pending = OfflineQueue.pending();
    expect(pending, hasLength(1));
    expect(pending.first.body, contains('"amount":7'));
    expect(pending.first.headers.containsKey('Cookie'), isFalse);
  });

  test('offline queue persists and clears through secure storage', () async {
    await OfflineQueue.enqueue(
      OfflineTask(
        id: 't2',
        method: 'POST',
        url: 'https://api.example.com/pay',
        headers: <String, String>{
          'Idempotency-Key': 'k2',
          'X-Device-ID': 'd1',
        },
        body: '{"amount":42,"to":"u2"}',
        tag: 'payments_transfer',
        createdAt: 2,
      ),
    );

    await OfflineQueue.init();
    expect(OfflineQueue.pending(), hasLength(1));
    expect(OfflineQueue.pending().first.body, contains('"amount":42'));

    await OfflineQueue.clearPersistentState();
    await OfflineQueue.init();

    expect(OfflineQueue.pending(), isEmpty);
  });

  test('offline queue flush drops queued task after auth session failure',
      () async {
    int requestCount = 0;
    const origin = 'http://127.0.0.1:8080';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', origin);
    await OfflineQueue.enqueue(
      OfflineTask(
        id: 'drop-auth-failure',
        method: 'POST',
        url: '$origin/pay',
        headers: const <String, String>{
          'Idempotency-Key': 'k-auth-drop',
          'X-Device-ID': 'd1',
        },
        body: '{"amount":7}',
        tag: 'payments_transfer',
        createdAt: 8,
      ),
      baseUrlOverride: origin,
    );

    await OfflineQueue.init(baseUrlOverride: origin);
    final delivered = await HttpOverrides.runZoned(
      () => OfflineQueue.flush(baseUrlOverride: origin),
      createHttpClient: (_) => _StaticHttpClient(
        statusCode: HttpStatus.unauthorized,
        responseBody: '{"detail":"auth session required"}',
        onRequestClosed: (uri, method, body) async {
          requestCount += 1;
          expect(uri.toString(), '$origin/pay');
          expect(method, 'POST');
          expect(jsonDecode(body), <String, Object?>{'amount': 7});
        },
      ),
    );

    expect(delivered, 0);
    expect(requestCount, 1);
    expect(
      OfflineQueue.pending(baseUrlOverride: origin),
      isEmpty,
    );
  });

  test('offline queue flushOne drops queued task after device mismatch',
      () async {
    int requestCount = 0;
    const origin = 'http://127.0.0.1:8080';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', origin);
    await OfflineQueue.enqueue(
      OfflineTask(
        id: 'drop-device-mismatch',
        method: 'POST',
        url: '$origin/pay',
        headers: const <String, String>{
          'Idempotency-Key': 'k-device-drop',
          'X-Device-ID': 'd1',
        },
        body: '{"amount":8}',
        tag: 'payments_transfer',
        createdAt: 9,
      ),
      baseUrlOverride: origin,
    );

    await OfflineQueue.init(baseUrlOverride: origin);
    final delivered = await HttpOverrides.runZoned(
      () => OfflineQueue.flushOne(
        'drop-device-mismatch',
        baseUrlOverride: origin,
      ),
      createHttpClient: (_) => _StaticHttpClient(
        statusCode: HttpStatus.badRequest,
        responseBody: '{"detail":"device_id mismatch"}',
        onRequestClosed: (uri, method, body) async {
          requestCount += 1;
          expect(uri.toString(), '$origin/pay');
          expect(method, 'POST');
          expect(jsonDecode(body), <String, Object?>{'amount': 8});
        },
      ),
    );

    expect(delivered, isFalse);
    expect(requestCount, 1);
    expect(
      OfflineQueue.pending(baseUrlOverride: origin),
      isEmpty,
    );
  });

  test('offline queue flush drops queued task after attestation failure',
      () async {
    int requestCount = 0;
    const origin = 'http://127.0.0.1:8080';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', origin);
    await OfflineQueue.enqueue(
      OfflineTask(
        id: 'drop-attestation-failure',
        method: 'POST',
        url: '$origin/pay',
        headers: const <String, String>{
          'Idempotency-Key': 'k-attestation-drop',
          'X-Device-ID': 'd1',
        },
        body: '{"amount":9}',
        tag: 'payments_transfer',
        createdAt: 10,
      ),
      baseUrlOverride: origin,
    );

    await OfflineQueue.init(baseUrlOverride: origin);
    final delivered = await HttpOverrides.runZoned(
      () => OfflineQueue.flush(baseUrlOverride: origin),
      createHttpClient: (_) => _StaticHttpClient(
        statusCode: HttpStatus.forbidden,
        responseBody: '{"detail":"attestation required"}',
        onRequestClosed: (uri, method, body) async {
          requestCount += 1;
          expect(uri.toString(), '$origin/pay');
          expect(method, 'POST');
          expect(jsonDecode(body), <String, Object?>{'amount': 9});
        },
      ),
    );

    expect(delivered, 0);
    expect(requestCount, 1);
    expect(
      OfflineQueue.pending(baseUrlOverride: origin),
      isEmpty,
    );
  });

  test('offline queue keeps tasks isolated across API origins', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await OfflineQueue.enqueue(
      OfflineTask(
        id: 't-scope',
        method: 'POST',
        url: 'https://api.one.example/pay',
        headers: <String, String>{
          'Idempotency-Key': 'k-scope',
          'X-Device-ID': 'd1',
        },
        body: '{"amount":1}',
        tag: 'payments_transfer',
        createdAt: 4,
      ),
    );

    await OfflineQueue.init();
    expect(OfflineQueue.pending(), hasLength(1));

    await sp.setString('base_url', 'https://api.two.example');
    await OfflineQueue.init();
    expect(OfflineQueue.pending(), isEmpty);

    await sp.setString('base_url', 'https://api.one.example');
    await OfflineQueue.init();
    expect(OfflineQueue.pending(), hasLength(1));
  });

  test(
      'offline queue honors explicit baseUrlOverride over stored scope for init, pending, and flush',
      () async {
    const originOne = 'http://127.0.0.1:1';
    const originTwo = 'http://127.0.0.1:2';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originTwo);

    await OfflineQueue.enqueue(
      OfflineTask(
        id: 't-override',
        method: 'POST',
        url: '$originOne/pay',
        headers: const <String, String>{
          'Idempotency-Key': 'k-override',
          'X-Device-ID': 'd1',
        },
        body: '{"amount":9}',
        tag: 'payments_transfer',
        createdAt: 7,
      ),
      baseUrlOverride: originOne,
    );

    await OfflineQueue.init(baseUrlOverride: originOne);

    expect(
      OfflineQueue.pending(baseUrlOverride: originOne),
      hasLength(1),
    );
    expect(
      OfflineQueue.pending(baseUrlOverride: originTwo),
      isEmpty,
    );

    await OfflineQueue.flush(baseUrlOverride: originOne);

    expect(
      OfflineQueue.pending(baseUrlOverride: originOne),
      hasLength(1),
    );
    expect(
      OfflineQueue.pending(baseUrlOverride: originTwo),
      isEmpty,
    );
  });

  test(
      'offline queue does not rebind legacy global tasks into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'offline_queue_v1': <String>[
        '{"id":"t1","method":"POST","url":"https://api.example.com/pay","headers":{"Idempotency-Key":"k3","X-Device-ID":"d1"},"body":"{\\"amount\\":7}","tag":"payments_transfer","createdAt":1,"retries":0,"nextAt":0}',
      ],
    });

    await OfflineQueue.init();

    final sp = await SharedPreferences.getInstance();
    expect(OfflineQueue.pending(), isEmpty);
    expect(sp.getStringList('offline_queue_v1'), isNull);
  });

  test('offline queue rejects mutating tasks without replay protection',
      () async {
    await expectLater(
      OfflineQueue.enqueue(
        OfflineTask(
          id: 'unsafe-1',
          method: 'POST',
          url: 'https://api.example.com/sonic/redeem',
          headers: const <String, String>{'X-Device-ID': 'd1'},
          body: '{"token":"abc"}',
          tag: 'payments_sonic',
          createdAt: 5,
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('replay protection'),
        ),
      ),
    );
    expect(OfflineQueue.pending(), isEmpty);
  });

  test('offline queue drops legacy mutating tasks without replay protection',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'offline_queue_v1': <String>[
        '{"id":"unsafe-legacy","method":"POST","url":"https://api.example.com/sonic/redeem","headers":{"X-Device-ID":"d1"},"body":"{\\"token\\":\\"abc\\"}","tag":"payments_sonic","createdAt":6,"retries":0,"nextAt":0}',
      ],
    });

    await OfflineQueue.init();

    final sp = await SharedPreferences.getInstance();
    expect(OfflineQueue.pending(), isEmpty);
    expect(sp.getStringList('offline_queue_v1'), isNull);
  });
}
