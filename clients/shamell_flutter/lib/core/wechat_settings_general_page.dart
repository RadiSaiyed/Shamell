import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'ui_prefs.dart';
import 'wechat_ui.dart';

class WeChatSettingsGeneralPage extends StatelessWidget {
  const WeChatSettingsGeneralPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    Widget valueChevron(String value) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: .55),
            ),
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
      final keys = sp.getKeys();
      final toRemove = <String>{
        ...keys.where(
          (k) =>
              k.startsWith('chat.msgs.') ||
              k.startsWith('chat.grp.msgs.') ||
              k.startsWith('chat.voice.played.') ||
              k.startsWith('chat.grp.voice.played.'),
        ),
        'chat.unread',
        'chat.active',
        'chat.grp.seen',
        'chat.pinned_messages',
        'chat.drafts.v1',
      };
      for (final k in toRemove) {
        await sp.remove(k);
      }
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
                child: Text(l.mirsaalDialogCancel),
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
      appBar: AppBar(
        title: Text(l.isArabic ? 'عام' : 'General'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          WeChatSection(
            margin: const EdgeInsets.only(top: 8),
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
                      builder: (_) => const WeChatSettingsLanguagePage(),
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
                      builder: (_) => const WeChatSettingsFontSizePage(),
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
                      builder: (_) => const WeChatSettingsDarkModePage(),
                    ),
                  );
                },
              ),
            ],
          ),
          WeChatSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.mirsaalSettingsStorage),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const WeChatSettingsStorageManagementPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          WeChatSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.mirsaalClearChatHistory),
                titleTextStyle: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
                onTap: confirmClearHistory,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WeChatSettingsLanguagePage extends StatelessWidget {
  const WeChatSettingsLanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

    TextStyle? subtitleStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'اللغة' : 'Language'),
        backgroundColor: bgColor,
        elevation: 0.5,
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

          return ListView(
            children: [
              WeChatSection(
                margin: const EdgeInsets.only(top: 8),
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
            ],
          );
        },
      ),
    );
  }
}

class WeChatSettingsStorageManagementPage extends StatefulWidget {
  const WeChatSettingsStorageManagementPage({super.key});

  @override
  State<WeChatSettingsStorageManagementPage> createState() =>
      _WeChatSettingsStorageManagementPageState();
}

class _WeChatSettingsStorageManagementPageState
    extends State<WeChatSettingsStorageManagementPage> {
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

  int _bytesForString(String? s) {
    if (s == null || s.isEmpty) return 0;
    return utf8.encode(s).length;
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
      final keys = sp.getKeys();
      var chatBytes = 0;
      var groupBytes = 0;
      var pinnedBytes = 0;
      var favoritesBytes = 0;
      var chatThreads = 0;
      var groupThreads = 0;

      for (final k in keys) {
        if (k.startsWith('chat.msgs.')) {
          chatThreads++;
          chatBytes += _bytesForString(sp.getString(k));
          continue;
        }
        if (k.startsWith('chat.grp.msgs.')) {
          groupThreads++;
          groupBytes += _bytesForString(sp.getString(k));
          continue;
        }
        if (k == 'chat.pinned_messages') {
          pinnedBytes = _bytesForString(sp.getString(k));
          continue;
        }
        if (k == 'favorites_items') {
          favoritesBytes = _bytesForString(sp.getString(k));
          continue;
        }
      }

      if (!mounted) return;
      setState(() {
        _chatBytes = chatBytes;
        _groupBytes = groupBytes;
        _pinnedBytes = pinnedBytes;
        _favoritesBytes = favoritesBytes;
        _chatThreads = chatThreads;
        _groupThreads = groupThreads;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _clearAllChatHistory() async {
    final sp = await SharedPreferences.getInstance();
    final keys = sp.getKeys();
    final toRemove = <String>{
      ...keys.where(
        (k) =>
            k.startsWith('chat.msgs.') ||
            k.startsWith('chat.grp.msgs.') ||
            k.startsWith('chat.voice.played.') ||
            k.startsWith('chat.grp.voice.played.'),
      ),
      'chat.unread',
      'chat.active',
      'chat.grp.seen',
      'chat.pinned_messages',
      'chat.drafts.v1',
    };
    for (final k in toRemove) {
      await sp.remove(k);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

    TextStyle? trailingStyle() => theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );

    final chatHistoryBytes = _chatBytes + _groupBytes + _pinnedBytes;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.mirsaalSettingsStorage),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                WeChatSection(
                  margin: const EdgeInsets.only(top: 8),
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'سجل الدردشة' : 'Chat history'),
                      subtitle: Text(
                        l.isArabic
                            ? 'دردشات: $_chatThreads · مجموعات: $_groupThreads'
                            : 'Chats: $_chatThreads · Groups: $_groupThreads',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
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
                              title: Text(l.mirsaalClearChatHistory),
                              content: Text(
                                l.isArabic
                                    ? 'سيتم حذف جميع رسائل الدردشة من هذا الجهاز.'
                                    : 'This will delete all chat messages from this device.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(l.mirsaalDialogCancel),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(l.mirsaalDialogOk),
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
                          PaintingBinding.instance.imageCache.clearLiveImages();
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
                WeChatSection(
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'المفضلة' : 'Favorites'),
                      trailing: Text(
                        _formatBytes(_favoritesBytes),
                        style: trailingStyle(),
                      ),
                      onTap: () {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                l.isArabic
                                    ? 'تُدار المفضلة من تبويب \"أنا\".'
                                    : 'Favorites are managed from the Me tab.',
                              ),
                            ),
                          );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class WeChatSettingsFontSizePage extends StatelessWidget {
  const WeChatSettingsFontSizePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'حجم الخط' : 'Font Size'),
        backgroundColor: bgColor,
        elevation: 0.5,
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
                            theme.colorScheme.onSurface.withValues(alpha: .55),
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

          return ListView(
            children: [
              WeChatSection(
                margin: const EdgeInsets.only(top: 8),
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
            ],
          );
        },
      ),
    );
  }
}

class WeChatSettingsDarkModePage extends StatelessWidget {
  const WeChatSettingsDarkModePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الوضع الداكن' : 'Dark Mode'),
        backgroundColor: bgColor,
        elevation: 0.5,
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
                            theme.colorScheme.onSurface.withValues(alpha: .55),
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

          return ListView(
            children: [
              WeChatSection(
                margin: const EdgeInsets.only(top: 8),
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
            ],
          );
        },
      ),
    );
  }
}
