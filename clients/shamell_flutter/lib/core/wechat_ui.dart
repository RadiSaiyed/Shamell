import 'package:flutter/material.dart';

class WeChatPalette {
  static const Color green = Color(0xFF07C160);
  static const Color background = Color(0xFFF7F7F7);
  static const Color divider = Color(0xFFE5E5E5);
  static const Color searchFill = Color(0xFFF1F1F1);
  static const Color searchFillDark = Color(0xFF2C2C2E);
  static const Color textPrimary = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF777777);
  static const Color linkBlue = Color(0xFF576B95);
}

class WeChatSection extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  final Color? backgroundColor;
  final double dividerIndent;
  final double dividerEndIndent;
  final BorderRadius? borderRadius;

  const WeChatSection({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(top: 12),
    this.backgroundColor,
    this.dividerIndent = 72,
    this.dividerEndIndent = 0,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.surface;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 0.5,
              indent: dividerIndent,
              endIndent: dividerEndIndent,
              color: theme.dividerColor,
            ),
          children[i],
        ],
      ],
    );

    final box = Container(color: bg, child: content);
    final radius = borderRadius;
    return Container(
      margin: margin,
      child: radius == null ? box : ClipRRect(borderRadius: radius, child: box),
    );
  }
}

class WeChatLeadingIcon extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final double iconSize;
  final BorderRadius borderRadius;

  const WeChatLeadingIcon({
    super.key,
    required this.icon,
    required this.background,
    this.foreground = Colors.white,
    this.size = 34,
    this.iconSize = 20,
    this.borderRadius = const BorderRadius.all(Radius.circular(7)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius,
      ),
      child: Icon(icon, size: iconSize, color: foreground),
    );
  }
}

class WeChatSearchBar extends StatelessWidget {
  final String hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final EdgeInsets margin;
  final TextInputAction? textInputAction;

  const WeChatSearchBar({
    super.key,
    required this.hintText,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill =
        isDark ? WeChatPalette.searchFillDark : WeChatPalette.searchFill;
    final hintColor = isDark
        ? theme.colorScheme.onSurface.withValues(alpha: .55)
        : WeChatPalette.textSecondary;
    return Container(
      margin: margin,
      height: 36,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        readOnly: readOnly,
        showCursor: !readOnly,
        enableInteractiveSelection: !readOnly,
        onTap: onTap,
        onChanged: onChanged,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          prefixIcon: Icon(Icons.search, size: 18, color: hintColor),
        ).copyWith(
          hintText: hintText,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            color: hintColor,
          ),
        ),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
