import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/perf.dart';

void main() {
  tearDown(() {
    Perf.debugReset();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Perf skips remote metrics when base url is malformed', () async {
    var calls = 0;
    Perf.debugReset(
      httpClient: MockClient((request) async {
        calls += 1;
        return http.Response('{}', 200);
      }),
    );

    Perf.configure(
      baseUrl: 'https://user:pass@api.example.com/root',
      deviceId: 'dev-1',
      remote: true,
    );
    Perf.action('wallet_snapshot_ok');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(calls, 0);
  });

  test('Perf posts remote metrics only to canonical /metrics child uri',
      () async {
    final requests = <http.Request>[];
    Perf.debugReset(
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );

    Perf.configure(
      baseUrl: 'HTTPS://api.example.com/',
      deviceId: 'dev-1',
      remote: true,
    );
    Perf.sample('pay_send_ms', 42);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(requests, hasLength(1));
    expect(requests.single.url.toString(), 'https://api.example.com/metrics');
    expect(requests.single.headers['X-Device-ID'], 'dev-1');
    final body = jsonDecode(requests.single.body) as Map<String, Object?>;
    expect(body['type'], 'sample');
  });

  test('Perf remote preference stays isolated across API origins', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await Perf.saveRemotePreference(true, sp: sp);
    expect(await Perf.loadRemotePreference(sp: sp), isTrue);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await Perf.loadRemotePreference(sp: sp), isFalse);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await Perf.loadRemotePreference(sp: sp), isTrue);
  });

  test(
      'Perf remote preference honors explicit baseUrl override over global scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.two.example');

    await Perf.saveRemotePreference(
      false,
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );
    await Perf.saveRemotePreference(
      true,
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    expect(
      await Perf.loadRemotePreference(
        sp: sp,
        baseUrlOverride: 'https://api.one.example',
      ),
      isFalse,
    );
    expect(
      await Perf.loadRemotePreference(
        sp: sp,
        baseUrlOverride: 'https://api.two.example',
      ),
      isTrue,
    );
  });

  test(
      'legacy global Perf remote preference does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'metrics_remote': true,
    });

    final sp = await SharedPreferences.getInstance();
    expect(await Perf.loadRemotePreference(sp: sp), isFalse);
    expect(sp.getBool('metrics_remote'), isNull);
  });
}
