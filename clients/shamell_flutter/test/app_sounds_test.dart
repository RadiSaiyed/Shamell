import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/app_sounds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await ShamellSoundEffects.resetForTesting();
  });

  test('sound effects default to enabled', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await ShamellSoundEffects.loadPrefs();

    expect(ShamellSoundEffects.enabled.value, isTrue);
  });

  test('sound effects preference is persisted', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await ShamellSoundEffects.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();

    expect(ShamellSoundEffects.enabled.value, isFalse);
    expect(prefs.getBool(kShamellSoundEffectsEnabledKey), isFalse);
  });

  testWidgets('playback is skipped in widget tests', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kShamellSoundEffectsEnabledKey: true,
    });
    await ShamellSoundEffects.loadPrefs();

    await ShamellSoundEffects.play(ShamellSoundEffect.paymentSent);
    await ShamellSoundEffects.play(ShamellSoundEffect.moneyReceived);

    expect(ShamellSoundEffects.enabled.value, isTrue);
  });
}
