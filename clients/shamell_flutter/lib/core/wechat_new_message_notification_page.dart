import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat/chat_service.dart';
import 'l10n.dart';
import 'wechat_ui.dart';

class WeChatNewMessageNotificationPage extends StatefulWidget {
  final String baseUrl;

  const WeChatNewMessageNotificationPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<WeChatNewMessageNotificationPage> createState() =>
      _WeChatNewMessageNotificationPageState();
}

class _WeChatNewMessageNotificationPageState
    extends State<WeChatNewMessageNotificationPage> {
  final ChatLocalStore _store = ChatLocalStore();
  bool _loading = true;
  String? _error;

  bool _enabled = true;
  bool _preview = false;
  bool _sound = true;
  bool _vibrate = true;
  bool _dnd = false;
  int _dndStart = 22 * 60;
  int _dndEnd = 8 * 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfg = await _store.loadNotifyConfig();
      if (!mounted) return;
      setState(() {
        _enabled = cfg.enabled;
        _preview = cfg.preview;
        _sound = cfg.sound;
        _vibrate = cfg.vibrate;
        _dnd = cfg.dnd;
        _dndStart = cfg.dndStart;
        _dndEnd = cfg.dndEnd;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtTime(int minutes) {
    final m = minutes.clamp(0, 24 * 60 - 1);
    final hh = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _pickTime({required bool start}) async {
    final initialMinutes = start ? _dndStart : _dndEnd;
    final initialTime = TimeOfDay(
      hour: (initialMinutes ~/ 60).clamp(0, 23),
      minute: (initialMinutes % 60).clamp(0, 59),
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked == null || !mounted) return;
    final mins = (picked.hour * 60 + picked.minute).clamp(0, 24 * 60 - 1);
    final nextStart = start ? mins : _dndStart;
    final nextEnd = start ? _dndEnd : mins;
    setState(() {
      _dndStart = nextStart;
      _dndEnd = nextEnd;
    });
    try {
      await _store.setNotifyDndSchedule(
        startMinutes: nextStart,
        endMinutes: nextEnd,
      );
    } catch (_) {}
  }

  Widget _chevron(L10n l, ThemeData theme) => Icon(
        l.isArabic ? Icons.chevron_left : Icons.chevron_right,
        size: 18,
        color: theme.colorScheme.onSurface.withValues(alpha: .40),
      );

  Widget _switchRow({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
              ),
            ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: onChanged == null ? null : () => onChanged(!value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : WeChatPalette.background;

    final subtitleColor = theme.colorScheme.onSurface.withValues(alpha: .65);
    final sectionTitleStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface.withValues(alpha: .70),
    );

    final bool controlsEnabled = !_loading && _enabled;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'إشعارات الرسائل الجديدة' : 'New message notification',
        ),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          WeChatSection(
            margin: const EdgeInsets.only(top: 12),
            children: [
              _switchRow(
                title: l.isArabic
                    ? 'تلقي إشعارات الرسائل الجديدة'
                    : 'Receive new message notifications',
                subtitle: l.isArabic
                    ? 'إظهار إشعار عند وصول رسالة جديدة'
                    : 'Show a notification when a new message arrives',
                value: _enabled,
                onChanged: _loading
                    ? null
                    : (v) async {
                        try {
                          await HapticFeedback.selectionClick();
                        } catch (_) {}
                        setState(() => _enabled = v);
                        try {
                          await _store.setNotifyEnabled(v);
                        } catch (_) {}
                      },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              l.isArabic ? 'أسلوب الإشعار' : 'Notification style',
              style: sectionTitleStyle,
            ),
          ),
          WeChatSection(
            margin: EdgeInsets.zero,
            children: [
              _switchRow(
                title: l.isArabic ? 'معاينة الرسالة' : 'Message preview',
                subtitle: l.isArabic
                    ? 'إظهار محتوى الرسالة في الإشعار'
                    : 'Show message content in notifications',
                value: _preview,
                onChanged: controlsEnabled
                    ? (v) async {
                        try {
                          await HapticFeedback.selectionClick();
                        } catch (_) {}
                        setState(() => _preview = v);
                        try {
                          await _store.setNotifyPreview(v);
                        } catch (_) {}
                      }
                    : null,
              ),
              _switchRow(
                title: l.isArabic ? 'الصوت' : 'Sound',
                subtitle: l.isArabic
                    ? 'تشغيل صوت الإشعار'
                    : 'Play notification sound',
                value: _sound,
                onChanged: controlsEnabled
                    ? (v) async {
                        try {
                          await HapticFeedback.selectionClick();
                        } catch (_) {}
                        setState(() => _sound = v);
                        try {
                          await _store.setNotifySound(v);
                        } catch (_) {}
                      }
                    : null,
              ),
              _switchRow(
                title: l.isArabic ? 'الاهتزاز' : 'Vibrate',
                subtitle: l.isArabic
                    ? 'اهتزاز عند وصول إشعار'
                    : 'Vibrate when a notification arrives',
                value: _vibrate,
                onChanged: controlsEnabled
                    ? (v) async {
                        try {
                          await HapticFeedback.selectionClick();
                        } catch (_) {}
                        setState(() => _vibrate = v);
                        try {
                          await _store.setNotifyVibrate(v);
                        } catch (_) {}
                      }
                    : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              l.isArabic ? 'عدم الإزعاج' : 'Do not disturb',
              style: sectionTitleStyle,
            ),
          ),
          WeChatSection(
            margin: EdgeInsets.zero,
            children: [
              _switchRow(
                title:
                    l.isArabic ? 'تمكين عدم الإزعاج' : 'Enable do not disturb',
                subtitle: l.isArabic
                    ? 'إيقاف الإشعارات خلال فترة محددة'
                    : 'Mute notifications during a scheduled time window',
                value: _dnd,
                onChanged: controlsEnabled
                    ? (v) async {
                        try {
                          await HapticFeedback.selectionClick();
                        } catch (_) {}
                        setState(() => _dnd = v);
                        try {
                          await _store.setNotifyDndEnabled(v);
                        } catch (_) {}
                      }
                    : null,
              ),
              ListTile(
                dense: true,
                enabled: controlsEnabled && _dnd,
                title: Text(l.isArabic ? 'من' : 'From'),
                subtitle: Text(
                  _fmtTime(_dndStart),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: controlsEnabled && _dnd
                        ? subtitleColor
                        : subtitleColor.withValues(alpha: .55),
                  ),
                ),
                trailing: _chevron(l, theme),
                onTap: controlsEnabled && _dnd
                    ? () => _pickTime(start: true)
                    : null,
              ),
              ListTile(
                dense: true,
                enabled: controlsEnabled && _dnd,
                title: Text(l.isArabic ? 'إلى' : 'To'),
                subtitle: Text(
                  _fmtTime(_dndEnd),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: controlsEnabled && _dnd
                        ? subtitleColor
                        : subtitleColor.withValues(alpha: .55),
                  ),
                ),
                trailing: _chevron(l, theme),
                onTap: controlsEnabled && _dnd
                    ? () => _pickTime(start: false)
                    : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Text(
              l.isArabic
                  ? 'ملاحظة: إذا كان وقت البدء يساوي وقت الانتهاء، سيتم كتم الإشعارات طوال اليوم.'
                  : 'Note: If start time equals end time, notifications are muted all day.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
