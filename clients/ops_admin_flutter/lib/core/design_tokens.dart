import 'package:flutter/material.dart';

class Tokens {
  // Black/White only palette
  static const Color primary = Color(0xFFFFFFFF);
  static const Color onPrimary = Color(0xFF000000);
  static const Color surface = Color(0xFF000000);
  static const Color onSurface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFF000000);
  static const Color border = Color(0xFFFFFFFF);
  static const Color focus = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFFFFFFF);

  // Light theme
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF000000);
  static const Color lightBorder = Color(0xFF000000);
  static const Color lightFocus = Color(0xFF000000);

  // Motion
  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionBase = Duration(milliseconds: 180);
}
