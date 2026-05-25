import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/v2_chat_strangler.dart';

const bool _forceLegacyChat = bool.fromEnvironment(
  'SHAMELL_FORCE_LEGACY_CHAT',
  defaultValue: true,
);
const String _v2ChatEnvFlagRaw = String.fromEnvironment(
  'V2_CHAT_STRANGLER',
  defaultValue: 'false',
);

bool _parseV2ChatFlag(String raw) {
  switch (raw.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
    case 'enabled':
      return true;
    default:
      return false;
  }
}

bool get _defaultV2ChatEnabled =>
    _forceLegacyChat ? false : _parseV2ChatFlag(_v2ChatEnvFlagRaw);
bool get _storedTrueVisible => !_forceLegacyChat;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('chat strangler toggle defaults true and can be persisted', () async {
    expect(await V2ChatStranglerStore.isEnabled(), _defaultV2ChatEnabled);
    await V2ChatStranglerStore.setEnabled(false);
    expect(await V2ChatStranglerStore.isEnabled(), isFalse);
  });

  test('chat strangler toggle stays isolated across API origins', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.one.example');
    await V2ChatStranglerStore.setEnabled(false, sp: sp);
    expect(await V2ChatStranglerStore.isEnabled(sp: sp), isFalse);

    await sp.setString('base_url', 'https://api.two.example');
    expect(
      await V2ChatStranglerStore.isEnabled(sp: sp),
      _defaultV2ChatEnabled,
    );

    await sp.setString('base_url', 'https://api.one.example');
    expect(await V2ChatStranglerStore.isEnabled(sp: sp), isFalse);
  });

  test('chat send benchmarks persist for legacy and v2', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.example.com');
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.legacy,
      elapsedMs: 700,
      success: true,
      sp: sp,
    );
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.v2,
      elapsedMs: 340,
      success: true,
      sp: sp,
    );
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.v2,
      elapsedMs: 210,
      success: false,
      sp: sp,
    );

    final b = await V2ChatStranglerStore.readBenchmarks(sp: sp);
    expect(b.legacy.attempts, 1);
    expect(b.legacy.successes, 1);
    expect(b.v2.attempts, 2);
    expect(b.v2.successes, 1);
    expect(b.v2.failures, 1);
    expect(b.v2.successTotalMs, 340);
    expect(
      V2ChatStranglerStore.formatSummary(benchmarks: b, isArabic: false),
      allOf(contains('current'), contains('secure')),
    );
  });

  test('chat benchmarks can be cleared', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', 'https://api.example.com');
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.v2,
      elapsedMs: 100,
      success: true,
      sp: sp,
    );
    var b = await V2ChatStranglerStore.readBenchmarks(sp: sp);
    expect(b.hasAnySamples, isTrue);
    await V2ChatStranglerStore.clearBenchmarks(sp: sp);
    b = await V2ChatStranglerStore.readBenchmarks(sp: sp);
    expect(b.hasAnySamples, isFalse);
  });

  test(
      'chat strangler state honors explicit baseUrl override over global scope and clears only current scope',
      () async {
    const originOne = 'https://api.one.example';
    const originTwo = 'https://api.two.example';
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', originTwo);

    await V2ChatStranglerStore.setEnabled(
      false,
      sp: sp,
      baseUrlOverride: originOne,
    );
    await V2ChatStranglerStore.setEnabled(
      true,
      sp: sp,
      baseUrlOverride: originTwo,
    );
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.legacy,
      elapsedMs: 120,
      success: true,
      sp: sp,
      baseUrlOverride: originOne,
    );
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.v2,
      elapsedMs: 80,
      success: true,
      sp: sp,
      baseUrlOverride: originTwo,
    );

    expect(
      await V2ChatStranglerStore.isEnabled(
        sp: sp,
        baseUrlOverride: originOne,
      ),
      isFalse,
    );
    expect(
      await V2ChatStranglerStore.isEnabled(
        sp: sp,
        baseUrlOverride: originTwo,
      ),
      _storedTrueVisible,
    );
    expect(
      (await V2ChatStranglerStore.readBenchmarks(
        sp: sp,
        baseUrlOverride: originOne,
      ))
          .legacy
          .attempts,
      1,
    );
    expect(
      (await V2ChatStranglerStore.readBenchmarks(
        sp: sp,
        baseUrlOverride: originTwo,
      ))
          .v2
          .attempts,
      1,
    );

    await V2ChatStranglerStore.clearBenchmarks(
      sp: sp,
      baseUrlOverride: originOne,
    );

    expect(
      (await V2ChatStranglerStore.readBenchmarks(
        sp: sp,
        baseUrlOverride: originOne,
      ))
          .hasAnySamples,
      isFalse,
    );
    expect(
      (await V2ChatStranglerStore.readBenchmarks(
        sp: sp,
        baseUrlOverride: originTwo,
      ))
          .hasAnySamples,
      isTrue,
    );
  });

  test('clearPersistedState removes toggles and benchmarks across origins',
      () async {
    final sp = await SharedPreferences.getInstance();

    await sp.setString('base_url', 'https://api.one.example');
    await V2ChatStranglerStore.setEnabled(false, sp: sp);
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.v2,
      elapsedMs: 100,
      success: true,
      sp: sp,
    );

    await sp.setString('base_url', 'https://api.two.example');
    await V2ChatStranglerStore.setEnabled(false, sp: sp);
    await V2ChatStranglerStore.recordSendAttempt(
      variant: V2ChatFlowVariant.legacy,
      elapsedMs: 200,
      success: false,
      sp: sp,
    );

    await V2ChatStranglerStore.clearPersistedState(sp: sp);

    await sp.setString('base_url', 'https://api.one.example');
    expect(await V2ChatStranglerStore.isEnabled(sp: sp), _defaultV2ChatEnabled);
    expect(
      (await V2ChatStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
      isFalse,
    );

    await sp.setString('base_url', 'https://api.two.example');
    expect(await V2ChatStranglerStore.isEnabled(sp: sp), _defaultV2ChatEnabled);
    expect(
      (await V2ChatStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
      isFalse,
    );
  });

  test(
      'legacy global chat strangler state does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'v2_chat_strangler_enabled': false,
      'v2_chat_strangler_metrics_v1':
          '{"v":1,"legacy":{"attempts":1,"successes":1,"failures":0,"success_total_ms":50},"v2":{"attempts":0,"successes":0,"failures":0,"success_total_ms":0}}',
    });

    final sp = await SharedPreferences.getInstance();
    expect(await V2ChatStranglerStore.isEnabled(sp: sp), _defaultV2ChatEnabled);
    expect((await V2ChatStranglerStore.readBenchmarks(sp: sp)).hasAnySamples,
        isFalse);
    expect(sp.getBool('v2_chat_strangler_enabled'), isNull);
    expect(sp.getString('v2_chat_strangler_metrics_v1'), isNull);
  });
}
