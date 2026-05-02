import 'package:flutter/material.dart';

class Tokens {
  // Core palette: restrained enterprise neutrals with separate domain accents.
  static const Color surface = Color(0xFF111827);
  static const Color surfaceAlt = Color(0xFF1F2937);
  static const Color onSurface = Color(0xFFF8FAFC);
  static const Color onSurfaceSecondary = Color(0xFFCBD5E1);
  static const Color primary = Color(0xFF0F766E);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF2563EB);
  static const Color border = Color(0xFF334155);
  static const Color focus = Color(0xFF14B8A6);
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);

  static const Color lightSurface = Color(0xFFF6F8FB);
  static const Color lightSurfaceAlt = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF111827);
  static const Color lightOnSurfaceSecondary = Color(0xFF475569);
  static const Color lightBorder = Color(0xFFD7DEE8);
  static const Color lightFocus = Color(0xFF0F766E);

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
  static const Color colorPayments = Color(0xFF059669);
  static const Color colorBus = Color(0xFF2563EB);
}
