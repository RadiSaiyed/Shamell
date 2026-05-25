import 'package:flutter/material.dart';

import 'design_tokens.dart';

class ShamellPalette {
  static const Color green = Tokens.primary;
  static const Color background = Tokens.lightScaffold;
  static const Color divider = Tokens.lightBorder;
  static const Color searchFill = Tokens.lightSurfaceAlt;
  static const Color searchFillDark = Tokens.darkSurfaceAlt;
  static const Color textPrimary = Tokens.lightOnSurface;
  static const Color textSecondary = Tokens.lightOnSurfaceSecondary;
  static const Color linkBlue = Tokens.primary;
}

class ShamellSection extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  final Color? backgroundColor;
  final double dividerIndent;
  final double dividerEndIndent;
  final BorderRadius? borderRadius;

  const ShamellSection({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 0),
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

    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(10);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .50 : .85),
          width: .7,
        ),
      ),
      child: content,
    );
    return Container(margin: margin, child: box);
  }
}

class ShamellListSection extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  final Color? backgroundColor;
  final double dividerIndent;
  final double dividerEndIndent;
  final BorderSide? borderSide;

  const ShamellListSection({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(top: 8),
    this.backgroundColor,
    this.dividerIndent = 72,
    this.dividerEndIndent = 0,
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final side = borderSide ??
        BorderSide(
          color: theme.dividerColor.withValues(alpha: isDark ? .42 : .72),
          width: .7,
        );
    final bg = backgroundColor ??
        theme.colorScheme.surface.withValues(alpha: isDark ? .84 : .96);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: side, bottom: side),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: .5,
                indent: dividerIndent,
                endIndent: dividerEndIndent,
                color: theme.dividerColor.withValues(alpha: isDark ? .54 : 1),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

AppBar shamellSettingsAppBar(
  BuildContext context, {
  required String title,
  Color? backgroundColor,
  List<Widget>? actions,
}) {
  final theme = Theme.of(context);
  return AppBar(
    toolbarHeight: 52,
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    ),
    backgroundColor: backgroundColor,
    elevation: 0.5,
    actions: actions,
  );
}

Widget shamellSettingsListTheme(
  BuildContext context, {
  required Widget child,
  double minLeadingWidth = 0,
  EdgeInsetsGeometry contentPadding =
      const EdgeInsets.symmetric(horizontal: 14),
}) {
  final theme = Theme.of(context);
  return ListTileTheme.merge(
    dense: true,
    visualDensity: VisualDensity.compact,
    minLeadingWidth: minLeadingWidth,
    minVerticalPadding: 4,
    contentPadding: contentPadding,
    titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
    subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: .58),
      fontSize: 12.5,
      height: 1.24,
    ),
    child: child,
  );
}

TextStyle? shamellSettingsValueStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    fontSize: 13,
    color: theme.colorScheme.onSurface.withValues(alpha: .68),
  );
}

InputDecoration shamellSettingsInputDecoration(
  BuildContext context, {
  required String label,
}) {
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    labelStyle: theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: theme.colorScheme.onSurface.withValues(alpha: .58),
    ),
    floatingLabelStyle: theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    ),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    filled: false,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 12),
  );
}

class ShamellLeadingIcon extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final double iconSize;
  final BorderRadius borderRadius;

  const ShamellLeadingIcon({
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
      decoration: BoxDecoration(color: background, borderRadius: borderRadius),
      child: Icon(icon, size: iconSize, color: foreground),
    );
  }
}

class ShamellCompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const ShamellCompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inactiveTrack = theme.colorScheme.onSurface.withValues(
      alpha: isDark ? .22 : .14,
    );
    final inactiveOutline = theme.colorScheme.onSurface.withValues(
      alpha: onChanged == null ? .10 : .24,
    );

    return Transform.scale(
      scale: .84,
      child: Switch(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: ShamellPalette.green,
        inactiveThumbColor: theme.colorScheme.surface,
        inactiveTrackColor: inactiveTrack,
        trackOutlineColor: MaterialStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(MaterialState.selected)) {
              return Colors.transparent;
            }
            return inactiveOutline;
          },
        ),
      ),
    );
  }
}

class ShamellSearchBar extends StatelessWidget {
  final String hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final EdgeInsets margin;
  final TextInputAction? textInputAction;

  const ShamellSearchBar({
    super.key,
    required this.hintText,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hintColor = isDark
        ? theme.colorScheme.onSurface.withValues(alpha: .55)
        : ShamellPalette.textSecondary;
    final fillColor = isDark
        ? ShamellPalette.searchFillDark.withValues(alpha: .82)
        : const Color(0xFFF1F1F1);
    return Container(
      margin: margin,
      height: 34,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .20 : .28),
          width: .5,
        ),
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
        onSubmitted: onSubmitted,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 0,
            vertical: 7,
          ),
          prefixIcon: Icon(Icons.search, size: 18, color: hintColor),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 34,
          ),
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
