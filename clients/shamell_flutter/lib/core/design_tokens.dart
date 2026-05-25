import 'package:flutter/material.dart';

class Tokens {
  // Unified SyrChat brand palette, tuned toward a restrained WeChat-like shell.
  static const Color primary = Color(0xFF07C160);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF10B981);
  static const Color focus = accent;
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  // Light theme
  static const Color lightScaffold = Color(0xFFEDEDED);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF7F7F7);
  static const Color lightOnSurface = Color(0xFF111111);
  static const Color lightOnSurfaceSecondary = Color(0xFF6B7280);
  static const Color lightBorder = Color(0xFFDADDE2);
  static const Color lightInputBorder = Color(0xFFD1D5DB);
  static const Color lightFocus = primary;
  static const Color lightSnackSurface = Color(0xFF202124);

  // Dark theme
  static const Color darkScaffold = Color(0xFF101010);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceAlt = Color(0xFF2A2A2D);
  static const Color darkOnSurface = Color(0xFFF4F4F5);
  static const Color darkOnSurfaceSecondary = Color(0xFFA1A1AA);
  static const Color darkBorder = Color(0xFF343437);
  static const Color darkInputBorder = Color(0xFF3F3F46);
  static const Color darkSnackSurface = Color(0xFF242426);

  // Backwards-compatible aliases used across the app.
  static const Color surface = darkSurface;
  static const Color onSurface = darkOnSurface;
  static const Color border = darkBorder;
  static const Color surfaceAlt = darkSurfaceAlt;

  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionBase = Duration(milliseconds: 180);
  static const Duration motionSlow = Duration(milliseconds: 240);

  static const BorderRadius radiusXs = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(16));

  static const List<double> typeScale = [12, 14, 16, 20, 24, 32];
  static const List<double> space = [4, 8, 12, 16, 24, 32];

  // Domain accent colours (used for icons / chips)
  static const Color colorPayments = accent;
  static const Color colorBus = primary;
}
