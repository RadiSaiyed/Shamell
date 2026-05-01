import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'people_nearby_page.dart';
import 'wechat_ui.dart';

class WeChatShakePage extends StatefulWidget {
  final String baseUrl;

  const WeChatShakePage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<WeChatShakePage> createState() => _WeChatShakePageState();
}

class _WeChatShakePageState extends State<WeChatShakePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _splitPx;
  bool _searching = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _splitPx = Tween<double>(begin: 0, end: 44).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openNearby() async {
    if (_navigating) return;
    setState(() {
      _navigating = true;
    });
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PeopleNearbyPage(baseUrl: widget.baseUrl),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _navigating = false;
        });
      }
    }
  }

  Future<void> _triggerShake() async {
    if (_searching || _navigating) return;
    setState(() {
      _searching = true;
    });
    try {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}

      await _controller.forward(from: 0);
      await _controller.reverse();
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      setState(() {
        _searching = false;
      });
      await _openNearby();
    } finally {
      if (mounted && _searching) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : WeChatPalette.background;
    final iconColor = isDark
        ? theme.colorScheme.onSurface.withValues(alpha: .85)
        : WeChatPalette.textPrimary.withValues(alpha: .80);
    final hintColor = isDark
        ? theme.colorScheme.onSurface.withValues(alpha: .65)
        : WeChatPalette.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'هزّ' : 'Shake'),
        backgroundColor: bgColor,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _triggerShake,
          child: LayoutBuilder(
            builder: (ctx, _) {
              final shortest =
                  MediaQuery.of(context).size.shortestSide.clamp(320.0, 520.0);
              final iconSize = (shortest * 0.62).clamp(210.0, 290.0);
              final halfShift = iconSize / 4;

              final icon = Icon(
                Icons.vibration_outlined,
                size: iconSize,
                color: iconColor,
              );

              Widget halfIcon({
                required bool top,
                required double split,
              }) {
                return Transform.translate(
                  offset: Offset(0, (top ? -halfShift : halfShift) + split),
                  child: ClipRect(
                    child: Align(
                      alignment:
                          top ? Alignment.topCenter : Alignment.bottomCenter,
                      heightFactor: 0.5,
                      child: icon,
                    ),
                  ),
                );
              }

              return Stack(
                children: [
                  AnimatedBuilder(
                    animation: _splitPx,
                    builder: (ctx2, _) {
                      final split = _splitPx.value;
                      return Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            halfIcon(top: true, split: -split),
                            halfIcon(top: false, split: split),
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: WeChatPalette.green,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: bgColor.withValues(alpha: .9),
                                  width: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.center,
                        child: Container(
                          height: 0.8,
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          color: theme.dividerColor
                              .withValues(alpha: isDark ? .28 : .55),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 26,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l.isArabic
                                ? 'هز هاتفك لاكتشاف أشخاص قريبين.'
                                : 'Shake your phone to discover nearby people.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: isDark ? .92 : 1),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l.isArabic
                                ? 'يمكنك أيضاً النقر للبدء.'
                                : 'You can also tap to start.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_searching,
                      child: AnimatedOpacity(
                        opacity: _searching ? 1 : 0,
                        duration: const Duration(milliseconds: 140),
                        child: Container(
                          color: bgColor.withValues(alpha: isDark ? .68 : .55),
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: theme.dividerColor
                                    .withValues(alpha: isDark ? .22 : .35),
                                width: 0.6,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      WeChatPalette.green,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  l.isArabic ? 'جارٍ البحث…' : 'Searching…',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
