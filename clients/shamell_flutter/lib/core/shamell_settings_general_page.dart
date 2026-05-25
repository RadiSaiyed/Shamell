import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_sounds.dart';
import 'chat/chat_service.dart';
import 'favorites_store.dart';
import 'l10n.dart';
import 'shamell_loading_shimmer.dart';
import 'ui_prefs.dart';
import 'shamell_ui.dart';

Widget _settingsReveal({
  required BuildContext context,
  required int order,
  required Widget child,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  if (reduceMotion) return child;
  final start = (order * 0.12).clamp(0.0, 0.72).toDouble();
  return TweenAnimationBuilder<double>(
    key: ValueKey<String>('settings-general-reveal-$order'),
    duration: const Duration(milliseconds: 460),
    curve: Interval(start, 1, curve: Curves.easeOutCubic),
    tween: Tween<double>(begin: 0, end: 1),
    child: child,
    builder: (context, value, child) {
      final y = (1 - value) * 14;
      return Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, y), child: child),
      );
    },
  );
}

class ShamellSettingsGeneralPage extends StatelessWidget {
  final String baseUrl;

  const ShamellSettingsGeneralPage({
    super.key,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .52),
        );

    Widget valueChevron(String value) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: shamellSettingsValueStyle(context),
          ),
          const SizedBox(width: 6),
          chevron(),
        ],
      );
    }

    String languageLabel(Locale? locale) {
      final code = locale?.languageCode.toLowerCase() ?? 'system';
      switch (code) {
        case 'ar':
          return l.isArabic ? 'العربية' : 'Arabic';
        case 'en':
          return 'English';
        case 'system':
        default:
          return l.isArabic ? 'لغة النظام' : 'System';
      }
    }

    String fontSizeLabel(double scale) {
      if (scale <= 1.05) {
        return l.isArabic ? 'افتراضي' : 'Standard';
      }
      if (scale <= 1.22) {
        return l.isArabic ? 'كبير' : 'Large';
      }
      return l.isArabic ? 'كبير جداً' : 'Extra Large';
    }

    String darkModeLabel(ThemeMode mode) {
      switch (mode) {
        case ThemeMode.system:
          return l.isArabic ? 'اتّباع النظام' : 'Follow System';
        case ThemeMode.dark:
          return l.isArabic ? 'تشغيل' : 'On';
        case ThemeMode.light:
        default:
          return l.isArabic ? 'إيقاف' : 'Off';
      }
    }

    Future<void> clearAllChatHistory() async {
      final sp = await SharedPreferences.getInstance();
      await shamellClearLocalChatHistory(
        sp: sp,
        baseUrlOverride: baseUrl,
      );
    }

    Future<void> confirmClearHistory() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(l.isArabic ? 'مسح سجل الدردشة' : 'Clear chat history'),
            content: Text(
              l.isArabic
                  ? 'سيتم حذف سجل الرسائل المخزّن على هذا الجهاز. لا يمكن التراجع عن ذلك.'
                  : 'This will delete chat history stored on this device. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.shamellDialogCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.isArabic ? 'مسح' : 'Clear'),
              ),
            ],
          );
        },
      );
      if (ok != true) return;
      await clearAllChatHistory();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تم مسح السجل.' : 'History cleared.',
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'عام' : 'General',
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        child: ListView(
          children: [
            _settingsReveal(
              context: context,
              order: 0,
              child: ShamellListSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  ListTile(
                    dense: true,
                    title: Text(l.isArabic ? 'اللغة' : 'Language'),
                    trailing: ValueListenableBuilder<Locale?>(
                      valueListenable: uiLocale,
                      builder: (context, locale, _) {
                        return valueChevron(languageLabel(locale));
                      },
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ShamellSettingsLanguagePage(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    title: Text(l.isArabic ? 'حجم الخط' : 'Font Size'),
                    trailing: ValueListenableBuilder<double>(
                      valueListenable: uiTextScale,
                      builder: (context, scale, _) {
                        return valueChevron(fontSizeLabel(scale));
                      },
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ShamellSettingsFontSizePage(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    title: Text(l.isArabic ? 'الوضع الداكن' : 'Dark Mode'),
                    trailing: ValueListenableBuilder<ThemeMode>(
                      valueListenable: uiThemeMode,
                      builder: (context, mode, _) {
                        return valueChevron(darkModeLabel(mode));
                      },
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ShamellSettingsDarkModePage(),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: ShamellSoundEffects.enabled,
                    builder: (context, enabled, _) {
                      return ListTile(
                        dense: true,
                        title: Text(
                          l.isArabic ? 'المؤثرات الصوتية' : 'Sound effects',
                        ),
                        trailing: ShamellCompactSwitch(
                          value: enabled,
                          onChanged: (value) {
                            unawaited(ShamellSoundEffects.setEnabled(value));
                            if (value) {
                              unawaited(
                                ShamellSoundEffects.play(
                                  ShamellSoundEffect.success,
                                ),
                              );
                            }
                          },
                        ),
                        onTap: () {
                          final value = !enabled;
                          unawaited(ShamellSoundEffects.setEnabled(value));
                          if (value) {
                            unawaited(
                              ShamellSoundEffects.play(
                                ShamellSoundEffect.success,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            _settingsReveal(
              context: context,
              order: 1,
              child: ShamellListSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  ListTile(
                    dense: true,
                    title: Text(l.shamellSettingsStorage),
                    trailing: chevron(),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShamellSettingsStorageManagementPage(
                            baseUrl: baseUrl,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            _settingsReveal(
              context: context,
              order: 2,
              child: ShamellListSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  ListTile(
                    dense: true,
                    title: Text(l.shamellClearChatHistory),
                    titleTextStyle: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                    onTap: confirmClearHistory,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShamellSettingsLanguagePage extends StatelessWidget {
  const ShamellSettingsLanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    TextStyle? subtitleStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .68),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'اللغة' : 'Language',
        backgroundColor: bgColor,
      ),
      body: ValueListenableBuilder<Locale?>(
        valueListenable: uiLocale,
        builder: (context, locale, _) {
          final selected = locale?.languageCode.toLowerCase() ?? 'system';

          Widget tile({
            required String code,
            required String title,
            String? subtitle,
          }) {
            final isSelected = selected == code;
            return ListTile(
              dense: true,
              title: Text(title),
              subtitle: subtitle == null
                  ? null
                  : Text(subtitle, style: subtitleStyle()),
              trailing: isSelected
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () => setUiLocaleCode(code),
            );
          }

          return shamellSettingsListTheme(
            context,
            child: ListView(
              children: [
                _settingsReveal(
                  context: context,
                  order: 0,
                  child: ShamellListSection(
                    dividerIndent: 16,
                    dividerEndIndent: 16,
                    children: [
                      tile(
                        code: 'system',
                        title: l.isArabic ? 'لغة النظام' : 'Follow System',
                        subtitle: l.isArabic
                            ? 'استخدم لغة الجهاز.'
                            : 'Use device language.',
                      ),
                      tile(
                        code: 'en',
                        title: 'English',
                        subtitle: l.isArabic ? 'الإنجليزية' : null,
                      ),
                      tile(
                        code: 'ar',
                        title: 'العربية',
                        subtitle: l.isArabic ? null : 'Arabic',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ShamellSettingsStorageManagementPage extends StatefulWidget {
  final String baseUrl;

  const ShamellSettingsStorageManagementPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<ShamellSettingsStorageManagementPage> createState() =>
      _ShamellSettingsStorageManagementPageState();
}

class _ShamellSettingsStorageManagementPageState
    extends State<ShamellSettingsStorageManagementPage> {
  bool _loading = true;
  int _chatBytes = 0;
  int _groupBytes = 0;
  int _pinnedBytes = 0;
  int _favoritesBytes = 0;
  int _chatThreads = 0;
  int _groupThreads = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final fixed = value >= 10 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fixed)} ${units[unit]}';
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final snapshot = await shamellLoadLocalChatHistoryStorageSnapshot(
        baseUrl: widget.baseUrl,
        sp: sp,
      );
      final favoritesBytes = await favoriteItemsStorageBytes(
        baseUrlOverride: widget.baseUrl,
      );

      if (!mounted) return;
      setState(() {
        _chatBytes = snapshot.chatBytes;
        _groupBytes = snapshot.groupBytes;
        _pinnedBytes = snapshot.pinnedBytes;
        _favoritesBytes = favoritesBytes;
        _chatThreads = snapshot.chatThreads;
        _groupThreads = snapshot.groupThreads;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _clearAllChatHistory() async {
    final sp = await SharedPreferences.getInstance();
    await shamellClearLocalChatHistory(
      sp: sp,
      baseUrlOverride: widget.baseUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    TextStyle? trailingStyle() => theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: .68),
        );

    final chatHistoryBytes = _chatBytes + _groupBytes + _pinnedBytes;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.shamellSettingsStorage,
        backgroundColor: bgColor,
      ),
      body: _loading
          ? const ShamellSkeletonList(itemCount: 6)
          : shamellSettingsListTheme(
              context,
              child: ListView(
                children: [
                  _settingsReveal(
                    context: context,
                    order: 0,
                    child: ShamellListSection(
                      dividerIndent: 16,
                      dividerEndIndent: 16,
                      children: [
                        ListTile(
                          dense: true,
                          title:
                              Text(l.isArabic ? 'سجل الدردشة' : 'Chat history'),
                          subtitle: Text(
                            l.isArabic
                                ? 'دردشات: $_chatThreads · مجموعات: $_groupThreads'
                                : 'Chats: $_chatThreads · Groups: $_groupThreads',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .68),
                            ),
                          ),
                          trailing: Text(
                            _formatBytes(chatHistoryBytes),
                            style: trailingStyle(),
                          ),
                          onTap: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) {
                                return AlertDialog(
                                  title: Text(l.shamellClearChatHistory),
                                  content: Text(
                                    l.isArabic
                                        ? 'سيتم حذف جميع رسائل الدردشة من هذا الجهاز.'
                                        : 'This will delete all chat messages from this device.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: Text(l.shamellDialogCancel),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: Text(l.shamellDialogOk),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (ok != true) return;
                            await _clearAllChatHistory();
                            if (!context.mounted) return;
                            setState(() => _loading = true);
                            await _load();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(l.isArabic ? 'تم.' : 'Done.'),
                                ),
                              );
                          },
                        ),
                        ListTile(
                          dense: true,
                          title: Text(l.isArabic ? 'الذاكرة المؤقتة' : 'Cache'),
                          trailing: Text('0 B', style: trailingStyle()),
                          onTap: () async {
                            try {
                              await HapticFeedback.selectionClick();
                            } catch (_) {}
                            try {
                              PaintingBinding.instance.imageCache.clear();
                              PaintingBinding.instance.imageCache
                                  .clearLiveImages();
                            } catch (_) {}
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l.isArabic
                                        ? 'تم مسح الذاكرة المؤقتة.'
                                        : 'Cache cleared.',
                                  ),
                                ),
                              );
                          },
                        ),
                      ],
                    ),
                  ),
                  _settingsReveal(
                    context: context,
                    order: 1,
                    child: ShamellListSection(
                      dividerIndent: 16,
                      dividerEndIndent: 16,
                      children: [
                        ListTile(
                          dense: true,
                          title: Text(l.isArabic ? 'المفضلة' : 'Favorites'),
                          subtitle: Text(
                            l.isArabic
                                ? 'تخزين محلي للعناصر المحفوظة.'
                                : 'Local storage used by saved favorite items.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .68),
                            ),
                          ),
                          trailing: Text(
                            _formatBytes(_favoritesBytes),
                            style: trailingStyle(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class ShamellSettingsFontSizePage extends StatelessWidget {
  const ShamellSettingsFontSizePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'حجم الخط' : 'Font Size',
        backgroundColor: bgColor,
      ),
      body: ValueListenableBuilder<double>(
        valueListenable: uiTextScale,
        builder: (context, scale, _) {
          bool isSelected(double v) => (scale - v).abs() < 0.02;

          Widget tile({
            required double value,
            required String title,
            String? subtitle,
          }) {
            return ListTile(
              dense: true,
              title: Text(title),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .68),
                      ),
                    ),
              trailing: isSelected(value)
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () => setUiTextScale(value),
            );
          }

          return shamellSettingsListTheme(
            context,
            child: ListView(
              children: [
                _settingsReveal(
                  context: context,
                  order: 0,
                  child: ShamellListSection(
                    dividerIndent: 16,
                    dividerEndIndent: 16,
                    children: [
                      tile(
                        value: 1.0,
                        title: l.isArabic ? 'افتراضي' : 'Standard',
                        subtitle: l.isArabic ? 'الموصى به.' : 'Recommended.',
                      ),
                      tile(
                        value: 1.15,
                        title: l.isArabic ? 'كبير' : 'Large',
                      ),
                      tile(
                        value: 1.3,
                        title: l.isArabic ? 'كبير جداً' : 'Extra Large',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ShamellSettingsDarkModePage extends StatelessWidget {
  const ShamellSettingsDarkModePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'الوضع الداكن' : 'Dark Mode',
        backgroundColor: bgColor,
      ),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: uiThemeMode,
        builder: (context, mode, _) {
          Widget tile({
            required ThemeMode value,
            required String title,
            String? subtitle,
          }) {
            final isSelected = mode == value;
            return ListTile(
              dense: true,
              title: Text(title),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .68),
                      ),
                    ),
              trailing: isSelected
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () => setUiThemeMode(value),
            );
          }

          return shamellSettingsListTheme(
            context,
            child: ListView(
              children: [
                _settingsReveal(
                  context: context,
                  order: 0,
                  child: ShamellListSection(
                    dividerIndent: 16,
                    dividerEndIndent: 16,
                    children: [
                      tile(
                        value: ThemeMode.system,
                        title: l.isArabic ? 'اتّباع النظام' : 'Follow System',
                        subtitle: l.isArabic
                            ? 'استخدم إعدادات المظهر في الجهاز.'
                            : 'Use device appearance settings.',
                      ),
                      tile(
                        value: ThemeMode.light,
                        title: l.isArabic ? 'إيقاف' : 'Off',
                      ),
                      tile(
                        value: ThemeMode.dark,
                        title: l.isArabic ? 'تشغيل' : 'On',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
