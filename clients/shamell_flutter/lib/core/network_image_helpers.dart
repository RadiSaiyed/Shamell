import 'package:flutter/material.dart';

/// Drop-in replacement for [Image.network] that bounds the in-memory
/// decoded bitmap size to what the device will actually display.
///
/// Without `cacheWidth`/`cacheHeight`, Flutter decodes a remote image at
/// its full source resolution and then downsamples on every paint. A
/// 4096×4096 photo rendered at 64×64 dp on a 3x device burns ~64 MB of
/// RAM per image; multiplied across a Moments feed or sticker grid this
/// is the single largest source of memory pressure on the V1 client.
///
/// This helper computes a sensible cache size from the current
/// [MediaQuery] device pixel ratio:
/// - If [logicalWidth] is provided, the cache is sized to
///   `logicalWidth * dpr` rounded up.
/// - Otherwise it falls back to `MediaQuery.size.width * dpr`, which
///   is the largest the image can ever paint anyway.
///
/// Pass [logicalHeight] separately for non-square crops; otherwise the
/// helper uses the same logical size for both axes.
///
/// All other parameters are forwarded to [Image.network] unchanged so
/// existing call sites can be migrated mechanically.
Image shamellCachedNetworkImage(
  String url, {
  required BuildContext context,
  double? logicalWidth,
  double? logicalHeight,
  BoxFit? fit,
  double? width,
  double? height,
  Map<String, String>? headers,
  ImageLoadingBuilder? loadingBuilder,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  final mq = MediaQuery.of(context);
  final dpr = mq.devicePixelRatio;
  final logicalW = logicalWidth ?? width ?? mq.size.width;
  final logicalH = logicalHeight ?? height ?? logicalW;
  final cacheW = (logicalW * dpr).ceil();
  final cacheH = (logicalH * dpr).ceil();
  return Image.network(
    url,
    fit: fit,
    width: width,
    height: height,
    headers: headers,
    loadingBuilder: loadingBuilder,
    errorBuilder: errorBuilder,
    cacheWidth: cacheW > 0 ? cacheW : null,
    cacheHeight: cacheH > 0 ? cacheH : null,
  );
}
