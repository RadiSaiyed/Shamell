import 'package:flutter/material.dart';

class Tokens {
  // Core palette
  // Dark theme
  // Deep navy surface with subtle blue tint for a cinematic dark backdrop.
  static const Color surface =
      Color(0xFF050B1F); // soft navy instead of near-black
  static const Color onSurface = Color(0xFFFFFFFF); // pure white text
  // Vibrant blue primary, tuned for focus rings and primary actions.
  static const Color primary = Color(0xFF2563EB); // blue-600
  static const Color onPrimary = Color(0xFFFFFFFF); // white text
  static const Color accent = Color(0xFF38BDF8); // sky/cyan-400
  static const Color border = Color(0xFF111827); // subtle outline
  static const Color focus = Color(0xFF60A5FA); // blue-400 (focus ring)
  static const Color surfaceAlt = Color(0xFF02081C); // slightly lighter panel
  static const Color error = Color(0xFFEF4444); // red-500
  static const Color warning = Color(0xFFF59E0B); // amber-500

  // Light theme – calmer, brighter surface
  static const Color lightSurface = Color(0xFFE5F0FF); // soft blue-tinted paper
  static const Color lightSurfaceAlt = Color(0xFFFFFFFF); // white cards
  static const Color lightOnSurface = Color(0xFFFFFFFF); // white text
  static const Color lightOnSurfaceSecondary = Color(0xFFFFFFFF); // white text
  static const Color lightBorder = Color(0xFFD0E2FF); // subtle card border
  static const Color lightFocus = Color(0xFF2563EB); // primary blue

  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionBase = Duration(milliseconds: 180);
  static const Duration motionSlow = Duration(milliseconds: 240);

  static const BorderRadius radiusXs = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(16));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(24));

  static const List<double> typeScale = [12, 14, 16, 20, 24, 32];
  static const List<double> space = [4, 8, 12, 16, 24, 32];

  // Domain accent colours (used for icons / chips)
  static const Color colorPayments = Color(0xFF07C160); // WeChat-inspired green
  static const Color colorTaxi = Color(0xFFFACC15); // yellow
  static const Color colorBus = Color(0xFF3B82F6); // blue
  static const Color colorFood = Color(0xFFF97316); // orange
  static const Color colorHotelsStays = Color(0xFF6366F1); // indigo
  static const Color colorBuildingMaterials = Color(0xFFA16207); // amber/brown
  static const Color colorCourierTransport = Color(0xFF0EA5E9); // light blue
  static const Color colorAgricultureLivestock =
      Color(0xFF16A34A); // dark green
  static const Color colorCars =
      Color(0xFF0891B2); // cyan (Carrental & Carmarket)
}
