import 'dart:async';

import 'package:flutter/material.dart';
import 'http_error.dart';

import 'chat/chat_models.dart';
import 'chat/chat_read_receipts_pref.dart';
import 'chat/chat_service.dart';
import 'l10n.dart';
import 'privacy_preference_store.dart';
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
    key: ValueKey<String>('settings-privacy-reveal-$order'),
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

class _ShamellSettingsPrivacyPageState
    extends State<ShamellSettingsPrivacyPage> {
  bool _friendVerification = true;
  int _blockedCount = 0;
  /// Local mirror of the global `ChatReadReceiptsPref.enabled` value.
  /// Defaults to the synchronous getter's current value so the switch
  /// renders the right state on first paint without waiting for the
  /// async hydrate.
  bool _readReceiptsEnabled = ChatReadReceiptsPref.enabled;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBlockedCount();
    // Hydrate the read-receipts pref from disk before the user can
    // interact with the toggle — without this an unhydrated cache
    // would briefly show the default (true) even if the user has
    // previously disabled receipts.
    unawaited(_loadReadReceiptsPref());
  }

  Future<void> _loadReadReceiptsPref() async {
    await ChatReadReceiptsPref.hydrate();
    if (!mounted) return;
    setState(() {
      _readReceiptsEnabled = ChatReadReceiptsPref.enabled;
    });
  }

  Future<void> _load() async {
    try {
      final v1 = await loadPrivacyPreferenceValue(
        kPrivacyFriendVerificationPrefKey,
        baseUrlOverride: widget.baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _friendVerification = v1;
      });
    } catch (_) {}
  }

  Future<void> _loadBlockedCount() async {
    try {
      final store = ChatLocalStore();
      final contacts =
          await store.loadContacts(baseUrlOverride: widget.baseUrl);
      if (!mounted) return;
      setState(() {
        _blockedCount = contacts.where((c) => c.blocked).length;
      });
    } catch (_) {}
  }

  Future<void> _setBool(String key, bool v) async {
    try {
      await savePrivacyPreferenceValue(
        key,
        v,
        baseUrlOverride: widget.baseUrl,
      );
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
          color: theme.colorScheme.onSurface.withValues(alpha: .52),
        );

    final blockedLabel = _blockedCount > 0
        ? (l.isArabic ? '($_blockedCount)' : '($_blockedCount)')
        : '';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'الخصوصية' : 'Privacy',
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
                    title: Text(
                      l.isArabic ? 'تأكيد الأصدقاء' : 'Friend verification',
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'يتطلب تأكيداً عند إضافة صديق.'
                          : 'Require confirmation when adding a friend.',
                    ),
                    trailing: ShamellCompactSwitch(
                      value: _friendVerification,
                      onChanged: (v) {
                        setState(() => _friendVerification = v);
                        _setBool(kPrivacyFriendVerificationPrefKey, v);
                      },
                    ),
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
                    title:
                        Text(l.isArabic ? 'طرق إضافة صديق' : 'Ways to add me'),
                    subtitle: Text(
                      l.isArabic
                          ? 'يتطلب إضافة جهة اتصال جديدة رمز دعوة أو QR. يُستخدم معرّف SyrChat للتحقق فقط.'
                          : 'New contacts require an invite token or QR. SyrChat ID is for verification only.',
                    ),
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
                    title: Text(l.isArabic ? 'قائمة الحظر' : 'Blocked list'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (blockedLabel.isNotEmpty)
                          Text(
                            blockedLabel,
                            style: shamellSettingsValueStyle(context),
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
            ),
            // Read-receipts toggle (audit P1-17). The switch maps
            // directly to the global `ChatReadReceiptsPref` flag
            // that gates `_startLiveDirectReadAck` in the chat page.
            // OFF means: incoming messages stay unread on the
            // sender's side (no `read_at`), at the cost of also
            // losing our own visibility into other people's read
            // state (WhatsApp / Signal use the same symmetric
            // trade-off).
            _settingsReveal(
              context: context,
              order: 3,
              child: ShamellListSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  ListTile(
                    title: Text(
                      l.isArabic
                          ? 'إيصالات القراءة'
                          : 'Read receipts',
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عند الإيقاف لا تُرسل ولا تستقبل علامات القراءة (المربعات الزرقاء).'
                          : 'When off you neither send nor receive read marks (the blue double-check).',
                    ),
                    trailing: ShamellCompactSwitch(
                      value: _readReceiptsEnabled,
                      onChanged: (v) {
                        setState(() => _readReceiptsEnabled = v);
                        unawaited(ChatReadReceiptsPref.setEnabled(v));
                      },
                    ),
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
  late final ChatLocalStore _store = ChatLocalStore();
  late final ChatService _service = ChatService(widget.baseUrl);

  bool _loading = true;
  String? _error;
  List<ChatContact> _blocked = const <ChatContact>[];
  final Set<String> _busyUnblockIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contacts = await _store.loadContacts(
        baseUrlOverride: widget.baseUrl,
      );
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
    if (_busyUnblockIds.contains(c.id)) return;
    setState(() => _busyUnblockIds.add(c.id));
    var remoteOk = true;
    try {
      await _service.setBlock(
        deviceId: widget.deviceId,
        peerId: c.id,
        blocked: false,
        hidden: c.hidden,
      );
    } catch (e) {
      remoteOk = false;
      if (mounted) {
        final l = L10n.of(context);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                sanitizeExceptionForUi(error: e, isArabic: l.isArabic),
              ),
            ),
          );
      }
    }

    if (remoteOk) {
      try {
        final contacts = await _store.loadContacts(
          baseUrlOverride: widget.baseUrl,
        );
        final next = <ChatContact>[];
        for (final item in contacts) {
          if (item.id == c.id) {
            next.add(item.copyWith(blocked: false));
          } else {
            next.add(item);
          }
        }
        await _store.saveContacts(next, baseUrlOverride: widget.baseUrl);
      } catch (_) {}
      if (mounted) {
        await _load();
        if (!mounted) return;
        final l = L10n.of(context);
        final shownName =
            (c.name ?? '').trim().isNotEmpty ? c.name!.trim() : c.id;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic
                    ? 'تم إلغاء حظر $shownName'
                    : '$shownName is unblocked',
              ),
            ),
          );
      }
    }
    if (mounted) {
      setState(() => _busyUnblockIds.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blockedCount = _blocked.length;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'قائمة الحظر' : 'Blocked list',
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        minLeadingWidth: 40,
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: .94),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: .55),
                    width: .9,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: .08),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: .14),
                        ),
                        child: Icon(
                          Icons.block_outlined,
                          size: 19,
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic ? 'إدارة الحظر' : 'Block management',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l.isArabic
                                  ? 'الأشخاص المحظورون: $blockedCount'
                                  : 'Blocked contacts: $blockedCount',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .72),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l.isArabic ? 'تحديث' : 'Refresh',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.errorContainer.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: .35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: Text(l.isArabic ? 'إعادة المحاولة' : 'Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _blocked.isEmpty && !_loading && _error == null
                  ? Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.surface.withValues(alpha: .92),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: .55),
                            width: .9,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l.isArabic
                                    ? 'لا توجد جهات اتصال محظورة'
                                    : 'No blocked contacts',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .78),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                      itemCount: _blocked.length,
                      itemBuilder: (ctx, i) {
                        final c = _blocked[i];
                        final isBusy = _busyUnblockIds.contains(c.id);
                        final name = (c.name ?? '').trim().isNotEmpty
                            ? c.name!.trim()
                            : c.id;
                        final initial =
                            name.isNotEmpty ? name[0].toUpperCase() : '?';
                        final subtitle =
                            (c.name ?? '').trim().isNotEmpty && c.id != name
                                ? c.id
                                : '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface
                                .withValues(alpha: .94),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: theme.dividerColor.withValues(alpha: .55),
                              width: .8,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Container(
                                width: 40,
                                height: 40,
                                color: theme.colorScheme.primary
                                    .withValues(alpha: .20),
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: subtitle.isEmpty
                                ? null
                                : Text(
                                    subtitle,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: .68),
                                    ),
                                  ),
                            trailing: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: isBusy
                                  ? SizedBox(
                                      key: const ValueKey('busy'),
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : TextButton(
                                      key: const ValueKey('ready'),
                                      onPressed: () => _unblock(c),
                                      child: Text(
                                        l.isArabic ? 'إلغاء الحظر' : 'Unblock',
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
