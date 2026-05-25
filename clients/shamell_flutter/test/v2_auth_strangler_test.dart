import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/v2_auth_strangler.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('v2 auth strangler flag defaults true and can be persisted', () async {
    expect(await V2AuthStranglerStore.isV2AuthEnabled(), isTrue);

    await V2AuthStranglerStore.setV2AuthEnabled(false);
    expect(await V2AuthStranglerStore.isV2AuthEnabled(), isFalse);
  });

  test('v2 auth strangler flag stays isolated across API origins', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await V2AuthStranglerStore.setV2AuthEnabled(false, sp: sp);
    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isFalse);

    await sp.setString('base_url', 'https://api.two.example');
    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isTrue);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isFalse);
  });

  test('resolveBaseUrl returns canonical stored API origin', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.shamell.online',
    });

    expect(
      await V2AuthStranglerStore.resolveBaseUrl(),
      'https://api.shamell.online',
    );
  });

  test('resolveBaseUrl fails closed on invalid stored base_url', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://user:pass@api.shamell.online/admin?x=1',
    });

    final resolved = await V2AuthStranglerStore.resolveBaseUrl();
    expect(resolved, isEmpty);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('base_url'), isNull);
  });

  test('auth attempts are persisted and aggregated', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.example.com');
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.legacy,
      elapsedMs: 980,
      success: true,
      sp: sp,
    );
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.legacy,
      elapsedMs: 410,
      success: false,
      sp: sp,
    );
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.v2,
      elapsedMs: 620,
      success: true,
      sp: sp,
    );

    final snapshot = await V2AuthStranglerStore.readBenchmarks(sp: sp);
    expect(snapshot.legacy.attempts, 2);
    expect(snapshot.legacy.successes, 1);
    expect(snapshot.legacy.failures, 1);
    expect(snapshot.legacy.successTotalMs, 980);
    expect(snapshot.v2.attempts, 1);
    expect(snapshot.v2.successes, 1);
    expect(snapshot.v2.avgSuccessMs, 620);

    final line = V2AuthStranglerStore.formatBenchmarkLine(
      benchmarks: snapshot,
      isArabic: false,
    );
    expect(line, contains('current'));
    expect(line, contains('secure'));
    expect(line, contains('ms'));
  });

  test('auth attempts honor explicit baseUrl override over stored scope',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');

    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.v2,
      elapsedMs: 333,
      success: true,
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );

    final scoped = await V2AuthStranglerStore.readBenchmarks(
      sp: sp,
      baseUrlOverride: 'https://api.two.example',
    );
    final stored = await V2AuthStranglerStore.readBenchmarks(
      sp: sp,
      baseUrlOverride: 'https://api.one.example',
    );

    expect(scoped.v2.attempts, 1);
    expect(scoped.v2.successes, 1);
    expect(stored.hasAnySamples, isFalse);
  });

  test('clearBenchmarks removes auth benchmark samples', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.example.com');
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.v2,
      elapsedMs: 333,
      success: true,
      sp: sp,
    );
    var snapshot = await V2AuthStranglerStore.readBenchmarks(sp: sp);
    expect(snapshot.hasAnySamples, isTrue);

    await V2AuthStranglerStore.clearBenchmarks(sp: sp);
    snapshot = await V2AuthStranglerStore.readBenchmarks(sp: sp);
    expect(snapshot.hasAnySamples, isFalse);
    expect(snapshot.legacy.attempts, 0);
    expect(snapshot.v2.attempts, 0);
  });

  test('clearEnabledOverride removes auth override but keeps benchmarks',
      () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.example.com');
    await V2AuthStranglerStore.setV2AuthEnabled(false, sp: sp);
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.v2,
      elapsedMs: 333,
      success: true,
      sp: sp,
    );

    await V2AuthStranglerStore.clearEnabledOverride(sp: sp);

    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isTrue);
    expect((await V2AuthStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
        isTrue);
  });

  test('clearPersistedState removes overrides and benchmarks across origins',
      () async {
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await V2AuthStranglerStore.setV2AuthEnabled(false, sp: sp);
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.v2,
      elapsedMs: 111,
      success: true,
      sp: sp,
    );

    await sp.setString('base_url', 'https://api.two.example');
    await V2AuthStranglerStore.setV2AuthEnabled(false, sp: sp);
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: AuthFlowVariant.legacy,
      elapsedMs: 222,
      success: false,
      sp: sp,
    );

    await V2AuthStranglerStore.clearPersistedState(sp: sp);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isTrue);
    expect(
      (await V2AuthStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
      isFalse,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isTrue);
    expect(
      (await V2AuthStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
      isFalse,
    );
  });

  test(
      'legacy global auth strangler state does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'v2_auth_strangler_enabled': false,
      'v2_auth_strangler_metrics_v1':
          '{"v":1,"legacy":{"attempts":1,"successes":1,"failures":0,"success_total_ms":50},"v2":{"attempts":0,"successes":0,"failures":0,"success_total_ms":0}}',
    });

    final sp = await SharedPreferences.getInstance();
    expect(await V2AuthStranglerStore.isV2AuthEnabled(sp: sp), isTrue);
    expect((await V2AuthStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
        isFalse);
    expect(sp.getBool('v2_auth_strangler_enabled'), isNull);
    expect(sp.getString('v2_auth_strangler_metrics_v1'), isNull);
  });
}
