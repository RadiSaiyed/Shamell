import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/hardware_attestation_io.dart';

void main() {
  test('parseRuntimeCompromiseState parses native compromise signals', () {
    final state = parseRuntimeCompromiseState(<String, Object?>{
      'compromised': true,
      'signals': <String>['debugger', 'suspicious_maps'],
    });

    expect(state.compromised, isTrue);
    expect(state.signals, ['debugger', 'suspicious_maps']);
  });

  test('runtimeCompromiseCheckUnavailableState fails closed', () {
    final state = runtimeCompromiseCheckUnavailableState();

    expect(state.compromised, isTrue);
    expect(state.signals, contains('runtime_compromise_check_unavailable'));
  });
}
