import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'http_error.dart';

import 'chat/chat_models.dart';
import 'chat/chat_service.dart';
import 'l10n.dart';
import 'shamell_ui.dart';

const String _kPrivacyFriendVerification = 'shamell.privacy.friend_verification';
const String _kPrivacyLegacySearchById = 'shamell.privacy.search_by_id';

const String _kPrivacyAddById = 'shamell.privacy.add_me.by_id';
const String _kPrivacyAddByQr = 'shamell.privacy.add_me.by_qr';
const String _kPrivacyAddByGroup = 'shamell.privacy.add_me.by_group';
const String _kPrivacyAddByCard = 'shamell.privacy.add_me.by_card';

const String _kPrivacyMomentsAllowStrangersTenPosts =
    'shamell.privacy.moments.allow_strangers_ten_posts';
const String _kPrivacyMomentsUpdateReminders =
    'shamell.privacy.moments.update_reminders';
const String _kPrivacyStatusVisibleToOthers =
    'shamell.privacy.status.visible_to_others';

class ShamellSettingsPrivacyPage extends StatefulWidget {
  final String baseUrl;
  final String deviceId;

  const ShamellSettingsPrivacyPage({
    super.key,
    required this.baseUrl,
    required this.deviceId,
  });

  @override
  State<ShamellSettingsPrivacyPage> createState() =>
      _ShamellSettingsPrivacyPageState();
}

class _ShamellSettingsPrivacyPageState extends State<ShamellSettingsPrivacyPage> {
  bool _friendVerification = true;
  int _blockedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBlockedCount();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v1 = sp.getBool(_kPrivacyFriendVerification);
      if (!mounted) return;
      setState(() {
        _friendVerification = v1 ?? true;
      });
    } catch (_) {}
  }

  Future<void> _loadBlockedCount() async {
    try {
      final store = ChatLocalStore();
      final contacts = await store.loadContacts();
      if (!mounted) return;
      setState(() {
        _blockedCount = contacts.where((c) => c.blocked).length;
      });
    } catch (_) {}
  }

  Future<void> _setBool(String key, bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, v);
    } catch (_) {}
  }

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
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    final blockedLabel = _blockedCount > 0
        ? (l.isArabic ? '($_blockedCount)' : '($_blockedCount)')
        : '';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الخصوصية' : 'Privacy'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'تأكيد الأصدقاء' : 'Friend verification',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'يتطلب تأكيداً عند إضافة صديق.'
                      : 'Require confirmation when adding a friend.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                trailing: Switch(
                  value: _friendVerification,
                  onChanged: (v) {
                    setState(() => _friendVerification = v);
                    _setBool(_kPrivacyFriendVerification, v);
                  },
                ),
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'طرق إضافة صديق' : 'Ways to add me'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellSettingsPrivacyAddMePage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'اللحظات والحالة' : 'Moments & Status',
                ),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellSettingsPrivacyMomentsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'قائمة الحظر' : 'Blocked list'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (blockedLabel.isNotEmpty)
                      Text(
                        blockedLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
                        ),
                      ),
                    if (blockedLabel.isNotEmpty) const SizedBox(width: 6),
                    chevron(),
                  ],
                ),
                onTap: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ShamellSettingsBlockedListPage(
                        baseUrl: widget.baseUrl,
                        deviceId: widget.deviceId,
                      ),
                    ),
                  );
                  // ignore: discarded_futures
                  _loadBlockedCount();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellSettingsPrivacyAddMePage extends StatefulWidget {
  const ShamellSettingsPrivacyAddMePage({super.key});

  @override
  State<ShamellSettingsPrivacyAddMePage> createState() =>
      _ShamellSettingsPrivacyAddMePageState();
}

class _ShamellSettingsPrivacyAddMePageState
    extends State<ShamellSettingsPrivacyAddMePage> {
  bool _byId = true;
  bool _byQr = true;
  bool _byGroup = true;
  bool _byCard = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _byId = sp.getBool(_kPrivacyAddById) ??
            sp.getBool(_kPrivacyLegacySearchById) ??
            true;
        _byQr = sp.getBool(_kPrivacyAddByQr) ?? true;
        _byGroup = sp.getBool(_kPrivacyAddByGroup) ?? true;
        _byCard = sp.getBool(_kPrivacyAddByCard) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _set(String key, bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, v);
      if (key == _kPrivacyAddById) {
        await sp.setBool(_kPrivacyLegacySearchById, v);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    TextStyle? hintStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'طرق إضافة صديق' : 'Ways to add me'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'معرّف شامل' : 'Shamell ID'),
                subtitle: Text(
                  l.isArabic
                      ? 'السماح بالإضافة عبر المعرّف.'
                      : 'Allow adding me via ID.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _byId,
                  onChanged: (v) async {
                    setState(() => _byId = v);
                    await _set(_kPrivacyAddById, v);
                  },
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'رمز QR' : 'QR code'),
                subtitle: Text(
                  l.isArabic
                      ? 'السماح بالإضافة عبر رمز QR.'
                      : 'Allow adding me via QR.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _byQr,
                  onChanged: (v) async {
                    setState(() => _byQr = v);
                    await _set(_kPrivacyAddByQr, v);
                  },
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الدردشة الجماعية' : 'Group chats'),
                subtitle: Text(
                  l.isArabic
                      ? 'السماح بالإضافة عبر المجموعات.'
                      : 'Allow adding me via group chats.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _byGroup,
                  onChanged: (v) async {
                    setState(() => _byGroup = v);
                    await _set(_kPrivacyAddByGroup, v);
                  },
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'بطاقة الاسم' : 'Business card'),
                subtitle: Text(
                  l.isArabic
                      ? 'السماح بالإضافة عبر بطاقة الاسم.'
                      : 'Allow adding me via business card.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _byCard,
                  onChanged: (v) async {
                    setState(() => _byCard = v);
                    await _set(_kPrivacyAddByCard, v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellSettingsPrivacyMomentsPage extends StatefulWidget {
  const ShamellSettingsPrivacyMomentsPage({super.key});

  @override
  State<ShamellSettingsPrivacyMomentsPage> createState() =>
      _ShamellSettingsPrivacyMomentsPageState();
}

class _ShamellSettingsPrivacyMomentsPageState
    extends State<ShamellSettingsPrivacyMomentsPage> {
  bool _strangersTenPosts = true;
  bool _updateReminders = true;
  bool _statusVisible = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _strangersTenPosts =
            sp.getBool(_kPrivacyMomentsAllowStrangersTenPosts) ?? true;
        _updateReminders = sp.getBool(_kPrivacyMomentsUpdateReminders) ?? true;
        _statusVisible = sp.getBool(_kPrivacyStatusVisibleToOthers) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _setBool(String key, bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    TextStyle? hintStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'اللحظات والحالة' : 'Moments & Status'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic
                      ? 'السماح للغرباء بمشاهدة 10 منشورات'
                      : 'Allow strangers to view ten posts',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'يمكن لغير الأصدقاء رؤية آخر 10 منشورات في اللحظات.'
                      : 'Non-friends can view your last 10 Moments posts.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _strangersTenPosts,
                  onChanged: (v) async {
                    setState(() => _strangersTenPosts = v);
                    await _setBool(_kPrivacyMomentsAllowStrangersTenPosts, v);
                  },
                ),
              ),
              ListTile(
                dense: true,
                title:
                    Text(l.isArabic ? 'تذكير بالتحديثات' : 'Update reminders'),
                subtitle: Text(
                  l.isArabic
                      ? 'اعرض تذكيرات عند نشر الأصدقاء تحديثات في اللحظات.'
                      : 'Show reminders when friends post in Moments.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _updateReminders,
                  onChanged: (v) async {
                    setState(() => _updateReminders = v);
                    await _setBool(_kPrivacyMomentsUpdateReminders, v);
                  },
                ),
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic
                      ? 'عرض الحالة للآخرين'
                      : 'Show my Status to others',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'اسمح للآخرين بمشاهدة حالتك.'
                      : 'Allow others to view your Status.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _statusVisible,
                  onChanged: (v) async {
                    setState(() => _statusVisible = v);
                    await _setBool(_kPrivacyStatusVisibleToOthers, v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellSettingsBlockedListPage extends StatefulWidget {
  final String baseUrl;
  final String deviceId;

  const ShamellSettingsBlockedListPage({
    super.key,
    required this.baseUrl,
    required this.deviceId,
  });

  @override
  State<ShamellSettingsBlockedListPage> createState() =>
      _ShamellSettingsBlockedListPageState();
}

class _ShamellSettingsBlockedListPageState
    extends State<ShamellSettingsBlockedListPage> {
  final ChatLocalStore _store = ChatLocalStore();
  late final ChatService _service = ChatService(widget.baseUrl);

  bool _loading = true;
  String? _error;
  List<ChatContact> _blocked = const <ChatContact>[];

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
      final contacts = await _store.loadContacts();
      final blocked = contacts.where((c) => c.blocked).toList();
      blocked.sort((a, b) {
        final an = (a.name ?? a.id).toLowerCase();
        final bn = (b.name ?? b.id).toLowerCase();
        return an.compareTo(bn);
      });
      if (!mounted) return;
      setState(() {
        _blocked = blocked;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
        _loading = false;
      });
    }
  }

  Future<void> _unblock(ChatContact c) async {
    try {
      await _service.setBlock(
        deviceId: widget.deviceId,
        peerId: c.id,
        blocked: false,
        hidden: c.hidden,
      );
    } catch (_) {}

    try {
      final contacts = await _store.loadContacts();
      final next = <ChatContact>[];
      for (final item in contacts) {
        if (item.id == c.id) {
          next.add(item.copyWith(blocked: false));
        } else {
          next.add(item);
        }
      }
      await _store.saveContacts(next);
    } catch (_) {}

    // ignore: discarded_futures
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'قائمة الحظر' : 'Blocked list'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Expanded(
            child: _blocked.isEmpty && !_loading
                ? Center(
                    child: Text(
                      l.isArabic ? 'لا أحد.' : 'No one.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .6),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _blocked.length,
                    itemBuilder: (ctx, i) {
                      final c = _blocked[i];
                      final name = (c.name ?? '').trim().isNotEmpty
                          ? c.name!.trim()
                          : c.id;
                      final initial =
                          name.isNotEmpty ? name[0].toUpperCase() : '?';
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: theme.colorScheme.surface,
                            child: ListTile(
                              dense: true,
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: .15),
                                  alignment: Alignment.center,
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              trailing: TextButton(
                                onPressed: () => _unblock(c),
                                child: Text(
                                    l.isArabic ? 'إلغاء الحظر' : 'Unblock'),
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 72,
                            color: theme.dividerColor,
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
