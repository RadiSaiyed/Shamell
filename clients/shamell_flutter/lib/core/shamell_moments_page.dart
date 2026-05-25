import 'package:flutter/material.dart';

import 'moments_page.dart';

/// Compatibility entry point for older SyrChat routes.
///
/// The production Moments experience now lives in [MomentsPage], which carries
/// the WeChat-style cover, composer, comments, privacy, mini-program embeds and
/// official-account surfaces. Keeping this tiny wrapper lets existing deep
/// links and feature entry points converge on the same implementation instead
/// of maintaining two separate Moments worlds.
class ShamellMomentsPage extends StatelessWidget {
  final String baseUrl;
  final bool showOnlyMine;
  final String? topicTag;
  final String? miniProgramId;

  const ShamellMomentsPage({
    super.key,
    required this.baseUrl,
    this.showOnlyMine = false,
    this.topicTag,
    this.miniProgramId,
  });

  @override
  Widget build(BuildContext context) {
    return MomentsPage(
      baseUrl: baseUrl,
      showOnlyMine: showOnlyMine,
      topicTag: topicTag,
      miniProgramId: miniProgramId,
    );
  }
}
