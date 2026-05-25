import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/mini_program_runtime.dart';
import 'package:shamell_flutter/core/moments_preset_store.dart';

void main() {
  group('Moments preset store', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
    });

    test('saves mini-program Moments presets as single-use drafts', () async {
      await saveMiniProgramMomentsPreset(
        text: '  SyrChat Pay\nshamell://mini_program/payments  ',
        miniProgramId: ' payments ',
      );

      final sp = await SharedPreferences.getInstance();
      expect(
        sp.getString(momentsPresetTextPrefsKey),
        'SyrChat Pay\nshamell://mini_program/payments',
      );
      expect(sp.getString(momentsPresetMiniProgramIdPrefsKey), 'payments');

      final preset = await loadAndClearMomentsPreset();

      expect(preset.text, 'SyrChat Pay\nshamell://mini_program/payments');
      expect(preset.miniProgramId, 'payments');
      expect(preset.imageBytes, isNull);
      expect(preset.hasContent, isTrue);
      expect(sp.getString(momentsPresetTextPrefsKey), isNull);
      expect(sp.getString(momentsPresetMiniProgramIdPrefsKey), isNull);
    });

    test('builds WeChat-style share text with Mini Program context', () {
      final text = buildMiniProgramMomentsShareText(
        miniProgramId: 'payments',
        title: 'SyrChat Pay',
        description: 'Wallet, transfers and QR payments.',
        isArabic: false,
      );

      expect(text, contains('SyrChat Pay'));
      expect(text, contains('Wallet, transfers and QR payments.'));
      expect(text, contains('shamell://mini_program/payments'));
      expect(text, contains('#ShamellMiniApp'));
      expect(text, contains('#mp_payments'));
      expect(text, contains('#Wallet'));
    });
  });
}
