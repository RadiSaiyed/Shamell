import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart';
import 'package:shamell_flutter/core/chat/chat_service.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/shamell_settings_privacy_page.dart';

Widget _wrapWithL10n(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const [
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

ChatContact _contact({
  required String id,
  required String name,
  required bool blocked,
}) {
  return ChatContact(
    id: id,
    publicKeyB64: 'pk-$id',
    fingerprint: 'fp-$id',
    name: name,
    blocked: blocked,
  );
}

Future<void> _seedContacts(
  String baseUrl,
  List<ChatContact> contacts,
) async {
  final store = ChatLocalStore();
  await store.saveContacts(contacts, baseUrlOverride: baseUrl);
}

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

class _BlockUpdateHttpClient implements HttpClient {
  _BlockUpdateHttpClient({
    required this.onRequestClosed,
  });

  final Future<void> Function(Uri uri, String body) onRequestClosed;
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
    return _BlockUpdateHttpRequest(
      method: method,
      uri: url,
      onClosed: onRequestClosed,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CloseTrackingHttpClient implements HttpClient {
  int closeCalls = 0;
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
  void close({bool force = false}) {
    closeCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockUpdateHttpRequest implements HttpClientRequest {
  _BlockUpdateHttpRequest({
    required this.method,
    required this.uri,
    required Future<void> Function(Uri uri, String body) onClosed,
  }) : _onClosed = onClosed;

  final Future<void> Function(Uri uri, String body) _onClosed;
  final BytesBuilder _body = BytesBuilder(copy: false);

  @override
  final String method;

  @override
  final Uri uri;

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
      _body.add(chunk);
    }
  }

  @override
  void add(List<int> data) {
    _body.add(data);
  }

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
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    await _onClosed(uri, utf8.decode(_body.takeBytes()));
    return _BlockUpdateHttpResponse(uri);
  }

  @override
  Future<HttpClientResponse> get done => close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockUpdateHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _BlockUpdateHttpResponse(this.uri) {
    headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  }

  final Uri uri;

  final List<int> _body = utf8.encode('{}');

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

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
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  int get statusCode => HttpStatus.ok;

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
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    secStore.clear();
  });

  testWidgets('Blocked list shows empty state when no blocked contacts',
      (tester) async {
    const baseUrl = 'https://api.shamell.online';
    await _seedContacts(
      baseUrl,
      <ChatContact>[
        _contact(id: 'u1', name: 'Alice', blocked: false),
      ],
    );

    await tester.pumpWidget(
      _wrapWithL10n(
        const ShamellSettingsBlockedListPage(
          baseUrl: baseUrl,
          deviceId: 'device-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Block management'), findsOneWidget);
    expect(find.text('Blocked contacts: 0'), findsOneWidget);
    expect(find.text('No blocked contacts'), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
  });

  testWidgets('Blocked list shows busy state while unblocking and refreshes',
      (tester) async {
    final received = <Map<String, Object?>>[];
    final responseGate = Completer<void>();
    final baseUrl = 'http://127.0.0.1:8080';
    final httpClient = _BlockUpdateHttpClient(
      onRequestClosed: (uri, body) async {
        received.add(<String, Object?>{
          'method': 'POST',
          'path': uri.path,
          'body': jsonDecode(body) as Map<String, Object?>,
        });
        await responseGate.future;
      },
    );

    await _seedContacts(
      baseUrl,
      <ChatContact>[
        _contact(id: 'u1', name: 'Alice', blocked: true),
      ],
    );

    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          _wrapWithL10n(
            ShamellSettingsBlockedListPage(
              baseUrl: baseUrl,
              deviceId: 'device-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Blocked contacts: 1'), findsOneWidget);

        final button = tester.widget<TextButton>(
          find.byKey(const ValueKey('ready')).first,
        );
        button.onPressed!.call();
        await tester.pump();
      },
      createHttpClient: (_) => httpClient,
    );

    responseGate.complete();
    await tester.pumpAndSettle();

    final store = ChatLocalStore();
    final contacts = await store.loadContacts(baseUrlOverride: baseUrl);

    expect(received, hasLength(1));
    expect(received.first['method'], 'POST');
    expect(received.first['path'], '/chat/devices/device-1/block');
    expect(received.first['body'], <String, Object?>{
      'peer_id': 'u1',
      'blocked': false,
      'hidden': false,
    });
    expect(contacts.where((c) => c.id == 'u1').single.blocked, isFalse);
    expect(find.text('Alice is unblocked'), findsOneWidget);
    expect(find.text('Blocked contacts: 0'), findsOneWidget);
    expect(find.text('No blocked contacts'), findsOneWidget);
  });

  testWidgets('Blocked list closes owned chat service on dispose',
      (tester) async {
    const baseUrl = 'http://127.0.0.1:8080';
    final httpClient = _CloseTrackingHttpClient();

    await _seedContacts(
      baseUrl,
      <ChatContact>[
        _contact(id: 'u1', name: 'Alice', blocked: true),
      ],
    );

    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          _wrapWithL10n(
            const ShamellSettingsBlockedListPage(
              baseUrl: baseUrl,
              deviceId: 'device-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      createHttpClient: (_) => httpClient,
    );

    expect(httpClient.closeCalls, 1);
  });
}
