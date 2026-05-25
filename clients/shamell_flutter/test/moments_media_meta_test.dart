import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_media_meta.dart';

void main() {
  group('momentMediaLayoutMeta', () {
    test('uses compact single image frame', () {
      final meta = momentMediaLayoutMeta(imageCount: 1);

      expect(meta.visibleCount, 1);
      expect(meta.hiddenCount, 0);
      expect(meta.columns, 1);
      expect(meta.preferredWidth, 216);
      expect(meta.tileLogicalSize, 216);
      expect(meta.widthFor(320), 216);
    });

    test('uses WeChat-style two and four image grids', () {
      final two = momentMediaLayoutMeta(imageCount: 2);
      final four = momentMediaLayoutMeta(imageCount: 4);

      expect(two.columns, 2);
      expect(two.preferredWidth, 176);
      expect(two.tileLogicalSize, 86);
      expect(four.columns, 2);
      expect(four.preferredWidth, 176);
    });

    test('uses three columns for dense grids and caps visible media at nine',
        () {
      final three = momentMediaLayoutMeta(imageCount: 3);
      final many = momentMediaLayoutMeta(imageCount: 12);

      expect(three.columns, 3);
      expect(three.preferredWidth, 266);
      expect(many.visibleCount, 9);
      expect(many.hiddenCount, 3);
      expect(many.columns, 3);
    });

    test('builds WeChat-style media chrome for overlays and placeholders', () {
      final chrome = momentMediaChromeMeta();

      expect(chrome.frameRadius, 8);
      expect(chrome.placeholderDarkAlpha, .30);
      expect(chrome.placeholderLightAlpha, .55);
      expect(chrome.hiddenOverlayAlpha, .42);
      expect(chrome.hiddenCountTextColor, Colors.white);
      expect(chrome.hiddenCountFontSize, 18);
      expect(chrome.hiddenCountFontWeight, FontWeight.w700);
    });

    test('never exceeds available width', () {
      final meta = momentMediaLayoutMeta(imageCount: 9);

      expect(meta.widthFor(180), 180);
      expect(meta.widthFor(0), meta.preferredWidth);
    });
  });
}
