import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_page_meta.dart';

void main() {
  group('momentPageChromeMeta', () {
    test('builds WeChat-style page rhythm chrome', () {
      final meta = momentPageChromeMeta();

      expect(meta.inlineComposerBottomGap, 12);
      expect(meta.miniProgramContextBottomGap, 8);
    });
  });

  group('momentPageTitleLabel', () {
    test('uses Mini Program Moments title before default title', () {
      expect(
        momentPageTitleLabel(
          isArabic: false,
          isFriendTimeline: false,
          miniProgramMomentsTitle: 'SyrChat Pay Moments',
          timelineAuthorName: '',
          timelineAuthorId: '',
        ),
        'SyrChat Pay Moments',
      );
      expect(
        momentPageTitleLabel(
          isArabic: false,
          isFriendTimeline: false,
          miniProgramMomentsTitle: '',
          timelineAuthorName: '',
          timelineAuthorId: '',
        ),
        'Moments',
      );
    });

    test('uses friend timeline name or id', () {
      expect(
        momentPageTitleLabel(
          isArabic: false,
          isFriendTimeline: true,
          miniProgramMomentsTitle: 'Ignored Moments',
          timelineAuthorName: 'Mariam',
          timelineAuthorId: 'u_1',
        ),
        'Mariam',
      );
      expect(
        momentPageTitleLabel(
          isArabic: false,
          isFriendTimeline: true,
          miniProgramMomentsTitle: '',
          timelineAuthorName: ' ',
          timelineAuthorId: 'u_1',
        ),
        'u_1',
      );
    });

    test('localizes default title', () {
      expect(
        momentPageTitleLabel(
          isArabic: true,
          isFriendTimeline: false,
          miniProgramMomentsTitle: '',
          timelineAuthorName: '',
          timelineAuthorId: '',
        ),
        'اللحظات',
      );
    });
  });

  group('momentPageAppBarActionMeta', () {
    test('shows composer action only on main Moments timelines', () {
      final main = momentPageAppBarActionMeta(
        showComposer: true,
        isFriendTimeline: false,
        isArabic: false,
      );
      final friend = momentPageAppBarActionMeta(
        showComposer: true,
        isFriendTimeline: true,
        isArabic: false,
      );

      expect(main.showComposerAction, isTrue);
      expect(main.icon, Icons.photo_camera_outlined);
      expect(main.tooltip, 'New moment');
      expect(main.openSheetPerfKey, 'moments_appbar_new_sheet_open');
      expect(main.quickOpenPerfKey, 'moments_appbar_quick_composer_open');
      expect(friend.showComposerAction, isFalse);
    });

    test('localizes composer action tooltip', () {
      final meta = momentPageAppBarActionMeta(
        showComposer: true,
        isFriendTimeline: false,
        isArabic: true,
      );

      expect(meta.tooltip, 'إضافة لحظة');
    });
  });

  group('momentCoverHeaderMeta', () {
    test('builds WeChat-style light cover header chrome', () {
      final meta = momentCoverHeaderMeta(isDark: false);

      expect(meta.height, 280);
      expect(meta.gradientColors, const <Color>[
        Color(0xFF64748B),
        Color(0xFF334155),
      ]);
      expect(meta.assetPath, 'assets/shamell_steering.png');
      expect(meta.assetOpacity, .16);
      expect(meta.horizontalInset, 16);
      expect(meta.bottomInset, 16);
      expect(meta.tapRadius, 10);
      expect(meta.nameColor, Colors.white);
      expect(meta.nameFontSize, 16);
      expect(meta.nameFontWeight, FontWeight.w600);
      expect(meta.nameShadowBlurRadius, 10);
      expect(meta.nameShadowColor, Colors.black45);
      expect(meta.nameAvatarGap, 10);
      expect(meta.avatarSize, 64);
      expect(meta.avatarRadius, 8);
      expect(meta.avatarFillColor, Colors.white);
      expect(meta.avatarFillAlpha, .92);
      expect(meta.avatarBorderColor, Colors.white);
      expect(meta.avatarBorderAlpha, .95);
      expect(meta.avatarBorderWidth, 1);
      expect(meta.avatarShadowColor, Colors.black26);
      expect(meta.avatarShadowBlurRadius, 8);
      expect(meta.avatarShadowOffset, const Offset(0, 4));
      expect(meta.initialFontSize, 28);
      expect(meta.initialFontWeight, FontWeight.w800);
    });

    test('uses darker cover chrome in dark mode', () {
      final meta = momentCoverHeaderMeta(isDark: true);

      expect(meta.gradientColors, const <Color>[
        Color(0xFF0B1220),
        Color(0xFF111827),
      ]);
      expect(meta.assetOpacity, .12);
    });
  });
}
