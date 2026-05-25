import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/account_identity_store.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/biometric_preference_store.dart';
import 'package:shamell_flutter/core/emergency_contact_store.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/safe_clipboard.dart';
import 'package:shamell_flutter/core/shamell_settings_account_security_page.dart';
import 'package:shamell_flutter/core/shamell_settings_emergency_contact_page.dart';
import 'package:shamell_flutter/main.dart' show LoginPage, ProfilePage;

Widget _testApp(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

List<String> _visibleTexts(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .where((text) => text.trim().isNotEmpty)
      .toList();
}

String _scopedLegacySensitiveKey(String prefix, String scope) {
  final suffix = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
  return '$prefix$suffix';
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

class _AuthSessionRequiredHttpClient implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost = 8;

  @override
  bool Function(X509Certificate cert, String host, int port)?
      badCertificateCallback;

  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _AuthSessionRequiredHttpRequest(url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthSessionRequiredHttpRequest implements HttpClientRequest {
  _AuthSessionRequiredHttpRequest(this.uri);

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
    await stream.drain<void>();
  }

  @override
  void add(List<int> data) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    return _AuthSessionRequiredHttpResponse(uri);
  }

  @override
  Future<HttpClientResponse> get done => close();

  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? obj = '']) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthSessionRequiredHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _AuthSessionRequiredHttpResponse(this.uri) {
    headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  }

  final Uri uri;
  final List<int> _body = utf8.encode('{"detail":"auth session required"}');

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
  String get reasonPhrase => 'Unauthorized';

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  int get statusCode => HttpStatus.unauthorized;

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

class _HomeSnapshotHttpClient implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost = 8;

  @override
  bool Function(X509Certificate cert, String host, int port)?
      badCertificateCallback;

  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _HomeSnapshotHttpRequest(url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HomeSnapshotHttpRequest implements HttpClientRequest {
  _HomeSnapshotHttpRequest(this.uri);

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
    await stream.drain<void>();
  }

  @override
  void add(List<int> data) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    if (uri.path == '/me/home_snapshot') {
      return _StaticJsonHttpResponse(
        uri: uri,
        statusCode: HttpStatus.ok,
        reasonPhrase: 'OK',
        body: '{"shamell_id":"ABCD2345","wallet":{"wallet_id":"wallet_sync"}}',
      );
    }
    return _StaticJsonHttpResponse(
      uri: uri,
      statusCode: HttpStatus.notFound,
      reasonPhrase: 'Not Found',
      body: '{"detail":"not found"}',
    );
  }

  @override
  Future<HttpClientResponse> get done => close();

  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? obj = '']) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticJsonHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _StaticJsonHttpResponse({
    required this.uri,
    required this.statusCode,
    required this.reasonPhrase,
    required String body,
  }) : _body = utf8.encode(body) {
    headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  }

  final Uri uri;
  final List<int> _body;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  final String reasonPhrase;

  @override
  final int statusCode;

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

  testWidgets('ProfilePage reauths on critical invite-token bootstrap failure',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          _testApp(
            const ProfilePage('http://127.0.0.1:8080'),
          ),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text('My SyrChat QR'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      createHttpClient: (_) => _AuthSessionRequiredHttpClient(),
    );

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
      'ProfilePage does not invent a local SyrChat ID when none is stored',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await saveStoredWalletId(
      'wallet_1',
      sp: sp,
      baseUrlOverride: 'https://api.example.com',
    );
    secStore[_scopedLegacySensitiveKey(
      'legacy.profile.name.v2.',
      'https://api.example.com',
    )] = 'Ada';
    secStore[_scopedLegacySensitiveKey(
      'legacy.profile.phone.v2.',
      'https://api.example.com',
    )] = '+963900000001';

    await tester.pumpWidget(
      _testApp(
        const ProfilePage('https://api.example.com'),
      ),
    );

    await tester.pumpAndSettle();

    final texts = _visibleTexts(tester);
    expect(texts, contains('Ada'));
    expect(texts, contains('+963900000001'));
    expect(texts, contains('wallet_1'));
    expect(texts.any((text) => text.contains('Not set')), isTrue);
    expect(
        texts,
        isNot(contains(
            matches(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$')))));
  });

  testWidgets(
      'ProfilePage hydrates SyrChat ID from home snapshot when session exists',
      (tester) async {
    const baseUrl = 'http://127.0.0.1:8080';
    await setSessionTokenForBaseUrl(
      baseUrl,
      '0123456789abcdef0123456789abcdef',
    );

    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          _testApp(
            const ProfilePage(baseUrl),
          ),
        );
        await tester.pumpAndSettle();
      },
      createHttpClient: (_) => _HomeSnapshotHttpClient(),
    );

    final texts = _visibleTexts(tester);
    expect(texts, contains('ABCD2345'));
    expect(await loadStoredShamellUserId(baseUrlOverride: baseUrl), 'ABCD2345');
  });

  testWidgets(
      'ProfilePage loads scoped profile identity from explicit baseUrl context',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    secStore[_scopedLegacySensitiveKey(
      'legacy.profile.name.v2.',
      'https://api.two.example',
    )] = 'Ada Two';
    secStore[_scopedLegacySensitiveKey(
      'legacy.profile.phone.v2.',
      'https://api.two.example',
    )] = '+963900000002';

    await tester.pumpWidget(
      _testApp(
        const ProfilePage('https://api.two.example'),
      ),
    );

    await tester.pumpAndSettle();

    final texts = _visibleTexts(tester);
    expect(texts, contains('Ada Two'));
    expect(texts, contains('+963900000002'));
    expect(texts, isNot(contains('+963900000001')));
  });

  testWidgets(
      'ShamellSettingsAccountSecurityPage does not invent a local SyrChat ID when none is stored',
      (tester) async {
    secStore[_scopedLegacySensitiveKey(
      'legacy.profile.phone.v2.',
      'https://api.example.com',
    )] = '+963900000001';

    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsAccountSecurityPage(
          baseUrl: 'https://api.example.com',
          profileId: null,
        ),
      ),
    );

    await tester.pumpAndSettle();

    final texts = _visibleTexts(tester);
    expect(texts, contains('+963900000001'));
    expect(texts.any((text) => text.contains('Not set')), isTrue);
    expect(
        texts,
        isNot(contains(
            matches(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$')))));
  });

  testWidgets(
      'ShamellSettingsAccountSecurityPage does not expose a redundant Security Center loop',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsAccountSecurityPage(
          baseUrl: 'https://api.example.com',
          profileId: 'ADA12345',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Security Center'), findsNothing);
    expect(find.text('Linked devices'), findsOneWidget);
    expect(find.text('Emergency contact'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets(
      'ShamellSettingsAccountSecurityPage loads biometric preference from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await saveRequireBiometricsPreference(
      true,
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsAccountSecurityPage(
          baseUrl: 'https://api.two.example',
          profileId: 'ADA12345',
        ),
      ),
    );

    await tester.pumpAndSettle();

    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isTrue);
  });

  testWidgets(
      'ShamellSettingsAccountSecurityPage clipboard copies auto-clear pii',
      (tester) async {
    secStore[_scopedLegacySensitiveKey(
      'legacy.profile.phone.v2.',
      'https://api.example.com',
    )] = '+963900000001';

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var clipboardText = '';
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            final args = Map<String, dynamic>.from(
                call.arguments as Map<Object?, Object?>);
            clipboardText = (args['text'] ?? '').toString();
            return null;
          case 'Clipboard.getData':
            return <String, dynamic>{'text': clipboardText};
          default:
            return null;
        }
      },
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsAccountSecurityPage(
          baseUrl: 'https://api.example.com',
          profileId: 'ADA12345',
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('SyrChat ID'));
    await tester.pump();
    expect(clipboardText, 'ADA12345');

    await tester.pump(shamellSensitiveClipboardClearAfter());
    await tester.pump();
    expect(clipboardText, isEmpty);

    await tester.tap(find.text('Phone'));
    await tester.pump();
    expect(clipboardText, '+963900000001');

    await tester.pump(shamellSensitiveClipboardClearAfter());
    await tester.pump();
    expect(clipboardText, isEmpty);
  });

  testWidgets(
      'ShamellSettingsEmergencyContactPage loads contact from explicit baseUrl scope',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await saveEmergencyContactRecord(
      name: 'Ada Two',
      phone: '+963900000002',
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    await tester.pumpWidget(
      _testApp(
        const ShamellSettingsEmergencyContactPage(
          baseUrl: 'https://api.two.example',
        ),
      ),
    );

    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(find.byType(TextField).at(0));
    final phoneField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(nameField.controller?.text, 'Ada Two');
    expect(phoneField.controller?.text, '+963900000002');
  });
}
