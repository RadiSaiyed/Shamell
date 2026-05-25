import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/mini_app_registry.dart';

void main() {
  group('MiniAppRegistry — Gaming category', () {
    test('Jump-Jump is registered under the Gaming category', () {
      final descriptors = MiniAppRegistry.descriptors;
      final jumpJump = descriptors.firstWhere(
        (d) => d.id == 'jump_jump',
        orElse: () =>
            fail('jump_jump should be registered in MiniAppRegistry'),
      );
      expect(jumpJump.categoryEn, 'Gaming');
      expect(jumpJump.categoryAr, 'الألعاب');
      expect(jumpJump.titleEn, 'Jump Jump');
    });

    test('MiniAppRegistry.byId resolves the canonical "jump_jump" id', () {
      final app = MiniAppRegistry.byId('jump_jump');
      expect(app, isNotNull);
      expect(app!.id, 'jump_jump');
    });

    test('MiniAppRegistry.byId also accepts case-insensitive variants', () {
      final upper = MiniAppRegistry.byId('JUMP_JUMP');
      final mixed = MiniAppRegistry.byId(' Jump_Jump ');
      expect(upper, isNotNull);
      expect(mixed, isNotNull);
      expect(upper!.id, 'jump_jump');
      expect(mixed!.id, 'jump_jump');
    });

    test('At least one Gaming-category descriptor exists (for Discover tile)',
        () {
      final gaming = MiniAppRegistry.descriptors
          .where((d) => d.enabled && d.categoryEn == 'Gaming')
          .toList();
      expect(
        gaming,
        isNotEmpty,
        reason:
            'Discover Gaming tile is gated on gamingCount > 0; if this is '
            'empty the tile will be hidden and Jump-Jump will be unreachable '
            'from the home screen.',
      );
    });

    test('Jump-Jump manifest exposes the play-mod action', () {
      final manifest = MiniAppRegistry.localManifestById('jump_jump');
      expect(manifest, isNotNull);
      expect(manifest!.id, 'jump_jump');
      // The play action is what the directory page's "Play" button
      // wires to. If it's missing the user lands on a dead screen.
      final hasPlay = manifest.actions.any((a) => a.id == 'open_jump_jump');
      expect(hasPlay, isTrue);
    });
  });

  // Three Men's Morris (Drei-Männer-Mühle) ships under the historical
  // `tic_tac_toe` storage id — these tests pin the label/manifest
  // contract so the descriptor stays aligned with the actual game
  // (placement+movement, NOT classic 3-in-a-row).
  group("MiniAppRegistry — Three Men's Morris", () {
    test('descriptor advertises the morris labels under the legacy id', () {
      final descriptor = MiniAppRegistry.descriptors.firstWhere(
        (d) => d.id == 'tic_tac_toe',
        orElse: () =>
            fail('tic_tac_toe (Three Men\'s Morris) must be registered'),
      );
      expect(descriptor.categoryEn, 'Gaming');
      expect(descriptor.titleEn, "Three Men's Morris");
      expect(descriptor.titleAr, 'طاحونة الثلاثة');
    });

    test('local manifest carries the morris title + description', () {
      final manifest = MiniAppRegistry.localManifestById('tic_tac_toe');
      expect(manifest, isNotNull);
      expect(manifest!.titleEn, "Three Men's Morris");
      expect(manifest.titleAr, 'طاحونة الثلاثة');
      expect(manifest.descriptionEn,
          contains('Three Men\'s Morris'));
      // Old "3-in-a-row only" wording must not resurface — the actual
      // game has placement + movement phases.
      expect(manifest.descriptionEn, isNot(contains('Classic 3-in-a-row')));
      final hasPlay =
          manifest.actions.any((a) => a.id == 'open_tic_tac_toe');
      expect(hasPlay, isTrue);
    });

    test('byId resolves both legacy and morris-style aliases', () {
      // Legacy: stays for back-compat with persisted deep links.
      for (final alias in const ['tictactoe', 'tic-tac-toe', 'xo', 'x_o']) {
        final app = MiniAppRegistry.byId(alias);
        expect(app, isNotNull, reason: 'legacy alias $alias must resolve');
        expect(app!.id, 'tic_tac_toe');
      }
      // New: aliases for the actual game name.
      for (final alias in const [
        'morris',
        'three_mens_morris',
        'drei_maenner_muehle',
        'dreimaennermuehle',
      ]) {
        final app = MiniAppRegistry.byId(alias);
        expect(app, isNotNull, reason: 'morris alias $alias must resolve');
        expect(app!.id, 'tic_tac_toe');
      }
    });
  });
}
