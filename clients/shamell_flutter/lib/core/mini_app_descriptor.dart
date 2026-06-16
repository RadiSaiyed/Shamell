import 'package:flutter/material.dart';

/// Descriptor for a Shamell mini-app (Shamell-style mini-program).
///
/// Used by:
///   - Discover strip on the home/services tab
///   - MiniAppsPage directory
///   - Recent-modules chips
class MiniAppDescriptor {
  final String id;
  final IconData icon;
  final String titleEn;
  final String titleAr;
  final String categoryEn;
  final String categoryAr;
  final String? runtimeAppId;
  final bool official; // true = first-party Shamell mini-app
  final bool enabled; // allow hiding apps per build/region
  final bool beta; // gated features, usually off in prod
  final double rating; // 0.0–5.0, simple client-side heuristic
  final int usageScore; // synthetic "trending" signal, higher = more prominent
  final int ratingCount; // number of user ratings (server-backed)
  final int momentsShares; // Moments posts referencing this mini-app

  const MiniAppDescriptor({
    required this.id,
    required this.icon,
    required this.titleEn,
    required this.titleAr,
    required this.categoryEn,
    required this.categoryAr,
    this.runtimeAppId,
    this.official = true,
    this.enabled = true,
    this.beta = false,
    this.rating = 0.0,
    this.usageScore = 0,
    this.ratingCount = 0,
    this.momentsShares = 0,
  });

  factory MiniAppDescriptor.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString().trim();
    final titleEn = (j['title_en'] ?? '').toString();
    final titleAr = (j['title_ar'] ?? '').toString();
    final categoryEn = (j['category_en'] ?? '').toString();
    final categoryAr = (j['category_ar'] ?? '').toString();
    final rating = j['rating'] is num ? (j['rating'] as num).toDouble() : 0.0;
    final usage =
        j['usage_score'] is num ? (j['usage_score'] as num).toInt() : 0;
    final ratingCount =
        j['rating_count'] is num ? (j['rating_count'] as num).toInt() : 0;
    final momentsShares =
        j['moments_shares'] is num ? (j['moments_shares'] as num).toInt() : 0;
    final runtimeAppId = (j['runtime_app_id'] ?? '').toString().trim();
    final official = j['official'] == true;
    final beta = j['beta'] == true;
    return MiniAppDescriptor(
      id: id,
      icon: Icons.apps_outlined,
      titleEn: titleEn.isNotEmpty ? titleEn : id,
      titleAr: titleAr.isNotEmpty ? titleAr : titleEn,
      categoryEn: categoryEn,
      categoryAr: categoryAr,
      runtimeAppId: runtimeAppId.isNotEmpty ? runtimeAppId : null,
      official: official,
      enabled: true,
      beta: beta,
      rating: rating,
      usageScore: usage,
      ratingCount: ratingCount,
      momentsShares: momentsShares,
    );
  }

  String title({required bool isArabic}) => isArabic ? titleAr : titleEn;

  String category({required bool isArabic}) =>
      isArabic ? categoryAr : categoryEn;
}
