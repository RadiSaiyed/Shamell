import 'package:flutter/material.dart';

class MomentMediaLayoutMeta {
  final int imageCount;
  final int visibleCount;
  final int hiddenCount;
  final int columns;
  final double spacing;
  final double childAspectRatio;
  final double preferredWidth;
  final double tileLogicalSize;

  const MomentMediaLayoutMeta({
    required this.imageCount,
    required this.visibleCount,
    required this.hiddenCount,
    required this.columns,
    required this.spacing,
    required this.childAspectRatio,
    required this.preferredWidth,
    required this.tileLogicalSize,
  });

  bool get hasMedia => visibleCount > 0;

  double widthFor(double availableWidth) {
    if (availableWidth <= 0) return preferredWidth;
    return availableWidth < preferredWidth ? availableWidth : preferredWidth;
  }
}

class MomentMediaChromeMeta {
  final double frameRadius;
  final double placeholderDarkAlpha;
  final double placeholderLightAlpha;
  final double hiddenOverlayAlpha;
  final Color hiddenCountTextColor;
  final double hiddenCountFontSize;
  final FontWeight hiddenCountFontWeight;

  const MomentMediaChromeMeta({
    required this.frameRadius,
    required this.placeholderDarkAlpha,
    required this.placeholderLightAlpha,
    required this.hiddenOverlayAlpha,
    required this.hiddenCountTextColor,
    required this.hiddenCountFontSize,
    required this.hiddenCountFontWeight,
  });
}

MomentMediaLayoutMeta momentMediaLayoutMeta({required int imageCount}) {
  final cleanCount = imageCount < 0 ? 0 : imageCount;
  final visibleCount = cleanCount > 9 ? 9 : cleanCount;
  final columns = _momentMediaColumns(visibleCount);
  const spacing = 4.0;
  final tile = visibleCount == 1 ? 216.0 : 86.0;
  final preferredWidth =
      visibleCount <= 0 ? 0.0 : (columns * tile) + ((columns - 1) * spacing);

  return MomentMediaLayoutMeta(
    imageCount: cleanCount,
    visibleCount: visibleCount,
    hiddenCount: cleanCount - visibleCount,
    columns: columns,
    spacing: spacing,
    childAspectRatio: 1,
    preferredWidth: preferredWidth,
    tileLogicalSize: tile,
  );
}

MomentMediaChromeMeta momentMediaChromeMeta() {
  return const MomentMediaChromeMeta(
    frameRadius: 8,
    placeholderDarkAlpha: .30,
    placeholderLightAlpha: .55,
    hiddenOverlayAlpha: .42,
    hiddenCountTextColor: Colors.white,
    hiddenCountFontSize: 18,
    hiddenCountFontWeight: FontWeight.w700,
  );
}

int _momentMediaColumns(int count) {
  if (count <= 1) return 1;
  if (count == 2 || count == 4) return 2;
  return 3;
}
