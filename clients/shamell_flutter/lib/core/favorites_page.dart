import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import 'external_launch_guard.dart';
import 'chat/shamell_chat_page.dart';
import 'favorites_store.dart';
import 'friend_annotations_store.dart';
import 'l10n.dart';
import 'mini_program_runtime.dart';
import 'safe_clipboard.dart';
import 'shamell_empty_state.dart';
import 'shamell_ui.dart';

Future<void> addFavoriteItemQuick(
  String text, {
  String? baseUrlOverride,
  String? chatId,
  String? msgId,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;
  try {
    final entry = <String, Object?>{
      'text': trimmed,
      'ts': DateTime.now().toIso8601String(),
    };
    if (chatId != null && chatId.isNotEmpty) {
      entry['chatId'] = chatId;
    }
    if (msgId != null && msgId.isNotEmpty) {
      entry['msgId'] = msgId;
    }
    await appendFavoriteItem(
      entry,
      baseUrlOverride: baseUrlOverride,
    );
  } catch (_) {}
}

Future<void> addFavoriteLocationQuick(
  double lat,
  double lon, {
  String? baseUrlOverride,
  String? label,
  String? chatId,
  String? msgId,
}) async {
  try {
    final effectiveLabel = (label ?? '').trim();
    final text = effectiveLabel.isNotEmpty
        ? effectiveLabel
        : '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
    final entry = <String, Object?>{
      'text': text,
      'ts': DateTime.now().toIso8601String(),
      'kind': 'location',
      'lat': lat,
      'lon': lon,
    };
    if (chatId != null && chatId.isNotEmpty) {
      entry['chatId'] = chatId;
    }
    if (msgId != null && msgId.isNotEmpty) {
      entry['msgId'] = msgId;
    }
    await appendFavoriteItem(
      entry,
      baseUrlOverride: baseUrlOverride,
    );
  } catch (_) {}
}

enum FavoritesFilter { all, messages, links, locations, miniPrograms, notes }

class FavoritesPage extends StatefulWidget {
  final String baseUrl;
  final String? chatIdFilter;
  const FavoritesPage({
    super.key,
    required this.baseUrl,
    this.chatIdFilter,
  });

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final List<Map<String, dynamic>> _items = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  Map<String, String> _aliases = <String, String>{};
  Map<String, String> _tags = <String, String>{};
  FavoritesFilter _filter = FavoritesFilter.all;

  @override
  void initState() {
    super.initState();
    final chatIdFilter = widget.chatIdFilter?.trim();
    if (chatIdFilter != null && chatIdFilter.isNotEmpty) {
      _filter = FavoritesFilter.messages;
    }
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _items
        ..clear()
        ..addAll(await loadFavoriteItems(baseUrlOverride: widget.baseUrl));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    unawaited(_loadAnnotations());
  }

  Future<void> _loadAnnotations() async {
    try {
      final annotations =
          await loadFriendAnnotations(baseUrlOverride: widget.baseUrl);
      if (!mounted) return;
      setState(() {
        _aliases = annotations.aliases;
        _tags = annotations.tags;
      });
    } catch (_) {}
  }

  bool _isLocation(Map<String, dynamic> p) {
    final kind = (p['kind'] ?? '').toString();
    if (kind == 'location') return true;
    final lat = p['lat'];
    final lon = p['lon'];
    return lat is num && lon is num;
  }

  Uri? _firstWebUri(String text) {
    final match = RegExp(
      r'(https?:\/\/[^\s]+|www\.[^\s]+)',
      caseSensitive: false,
    ).firstMatch(text);
    var candidate = match?.group(0)?.trim() ?? '';
    while (candidate.isNotEmpty &&
        const <String>{'.', ',', ')', ']', '}', '>'}
            .contains(candidate[candidate.length - 1])) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    if (candidate.isEmpty) return null;
    if (candidate.toLowerCase().startsWith('www.')) {
      candidate = 'https://$candidate';
    }
    try {
      final uri = Uri.parse(candidate);
      final scheme = uri.scheme.toLowerCase();
      if ((scheme == 'http' || scheme == 'https') &&
          uri.host.trim().isNotEmpty) {
        return uri;
      }
    } catch (_) {}
    return null;
  }

  bool _isStarredMessage(Map<String, dynamic> p) {
    final chatId = (p['chatId'] ?? '').toString();
    final msgId = (p['msgId'] ?? '').toString();
    return chatId.isNotEmpty && msgId.isNotEmpty;
  }

  bool _isLink(Map<String, dynamic> p) {
    if (_isStarredMessage(p) || _isLocation(p) || _isMiniProgram(p)) {
      return false;
    }
    return _firstWebUri((p['text'] ?? '').toString()) != null;
  }

  bool _isNote(Map<String, dynamic> p) {
    return !_isStarredMessage(p) &&
        !_isLocation(p) &&
        !_isMiniProgram(p) &&
        !_isLink(p);
  }

  bool _isMiniProgram(Map<String, dynamic> p) {
    final kind = (p['kind'] ?? '').toString().trim().toLowerCase();
    return kind == 'mini_program' || _miniProgramId(p).isNotEmpty;
  }

  String _miniProgramId(Map<String, dynamic> p) {
    for (final key in const <String>[
      'miniProgramId',
      'mini_program_id',
      'miniAppId',
      'mini_app_id',
      'appId',
      'app_id',
    ]) {
      final value = (p[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    final sourceModule = (p['sourceModule'] ?? p['source_module'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final sourceId = (p['sourceId'] ?? p['source_id'] ?? '').toString().trim();
    if ((sourceModule == 'mini_app' ||
            sourceModule == 'mini_apps' ||
            sourceModule == 'mini_program' ||
            sourceModule == 'mini_programs') &&
        sourceId.isNotEmpty) {
      return sourceId;
    }
    return '';
  }

  String _displayText(Map<String, dynamic> p) {
    for (final key in const <String>['text', 'title', 'label', 'name']) {
      final value = (p[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    final miniProgramId = _miniProgramId(p);
    if (miniProgramId.isNotEmpty) return miniProgramId;
    return '';
  }

  Future<void> _openMiniProgram(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiniProgramPage(
          id: trimmed,
          baseUrl: widget.baseUrl,
          walletId: '',
          deviceId: 'favorites',
        ),
      ),
    );
  }

  double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return null;
  }

  String _chatLabelFor(String chatId) {
    final alias = _aliases[chatId]?.trim();
    return (alias != null && alias.isNotEmpty) ? alias : chatId;
  }

  String _tagsFor(String chatId) => (_tags[chatId] ?? '').trim();

  DateTime? _parseTs(String rawTs) {
    try {
      return DateTime.parse(rawTs).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final sameDay =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    if (sameDay) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  void _openChat(String chatId, {String? msgId}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShamellChatPage(
          baseUrl: widget.baseUrl,
          initialPeerId: chatId,
          initialMessageId: (msgId != null && msgId.isNotEmpty) ? msgId : null,
        ),
      ),
    );
  }

  Future<void> _openMap(double lat, double lon) async {
    final uri = normalizeExternalMapUri(latitude: lat, longitude: lon);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openWebUri(Uri uri) async {
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: shamellExternalLaunchMode(uri));
  }

  Future<void> _copyText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await shamellCopyToClipboard(t, sensitive: true);
    if (!mounted) return;
    final l = L10n.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.copiedLabel)));
  }

  Future<void> _deleteWithUndo(Map<String, dynamic> item) async {
    final l = L10n.of(context);
    final idx = _items.indexOf(item);
    if (idx < 0) return;
    final entry = Map<String, dynamic>.from(item);
    setState(() => _items.removeAt(idx));
    try {
      await removeFavoriteItemEntry(
        entry,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l.isArabic ? 'تم الحذف' : 'Removed'),
          action: SnackBarAction(
            label: l.isArabic ? 'تراجع' : 'Undo',
            onPressed: () async {
              if (!mounted) return;
              setState(() => _items.insert(idx, entry));
              try {
                await insertFavoriteItemAt(
                  idx,
                  entry,
                  baseUrlOverride: widget.baseUrl,
                );
              } catch (_) {}
            },
          ),
        ),
      );
  }

  Future<void> _addNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final entry = <String, Object?>{
      'text': trimmed,
      'ts': DateTime.now().toIso8601String(),
      'kind': 'note',
    };
    setState(() {
      _items.insert(0, entry);
    });
    try {
      await appendFavoriteItem(
        entry,
        baseUrlOverride: widget.baseUrl,
      );
    } catch (_) {}
  }

  Future<void> _showCreateNoteSheet() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final ctrl = TextEditingController();
    final focus = FocusNode();

    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: viewInsets.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                l.isArabic ? 'ملاحظة جديدة' : 'New note',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                focusNode: focus,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: l.shamellFavoritesHint,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(l.shamellDialogCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final text = ctrl.text.trim();
                        if (text.isEmpty) return;
                        Navigator.of(ctx).pop();
                        await _addNote(text);
                      },
                      child: Text(
                        l.settingsSave,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    } finally {
      ctrl.dispose();
      focus.dispose();
    }
  }

  Future<void> _showActions(Map<String, dynamic> p) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    final text = _displayText(p);
    final rawTs = (p['ts'] ?? '').toString();
    final chatId = (p['chatId'] ?? '').toString();
    final msgId = (p['msgId'] ?? '').toString();
    final isLocation = _isLocation(p);
    final miniProgramId = _miniProgramId(p);
    final lat = _asDouble(p['lat']);
    final lon = _asDouble(p['lon']);
    final webUri = _firstWebUri(text);

    final chatLabel = chatId.isNotEmpty ? _chatLabelFor(chatId) : '';
    final dt = _parseTs(rawTs);
    final tsLabel = _formatTime(dt);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final titleStyle = theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ) ??
            const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

        final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: .70),
        );

        Widget actionTile({
          required IconData icon,
          required String title,
          Color? color,
          required VoidCallback onTap,
        }) {
          return ListTile(
            dense: true,
            leading: Icon(icon, color: color ?? theme.colorScheme.onSurface),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color ?? theme.colorScheme.onSurface,
              ),
            ),
            onTap: onTap,
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: .75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    if (chatId.isNotEmpty || tsLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          [
                            if (chatId.isNotEmpty)
                              (l.isArabic
                                  ? 'من دردشة: $chatLabel'
                                  : 'From chat: $chatLabel'),
                            if (tsLabel.isNotEmpty) tsLabel,
                          ].join(' · '),
                          style: subtitleStyle,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 16),
              if (webUri != null)
                actionTile(
                  icon: Icons.open_in_browser_outlined,
                  title: l.isArabic ? 'فتح الرابط' : 'Open link',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _openWebUri(webUri);
                  },
                ),
              if (miniProgramId.isNotEmpty)
                actionTile(
                  icon: Icons.apps_outlined,
                  title: l.isArabic ? 'فتح البرنامج' : 'Open Mini Program',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _openMiniProgram(miniProgramId);
                  },
                ),
              actionTile(
                icon: Icons.copy_outlined,
                title: l.shamellCopyMessage,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _copyText(text);
                },
              ),
              if (chatId.isNotEmpty)
                actionTile(
                  icon: Icons.chat_bubble_outline,
                  title: l.shamellFavoritesOpenChatTooltip,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openChat(chatId, msgId: msgId);
                  },
                ),
              if (isLocation && lat != null && lon != null)
                actionTile(
                  icon: Icons.map_outlined,
                  title: l.shamellLocationOpenInMap,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _openMap(lat, lon);
                  },
                ),
              actionTile(
                icon: Icons.delete_outline,
                title: l.shamellFavoritesRemoveTooltip,
                color: theme.colorScheme.error.withValues(alpha: .95),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _deleteWithUndo(p);
                },
              ),
              const SizedBox(height: 10),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  dense: true,
                  title: Center(
                    child: Text(
                      l.shamellDialogCancel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  String _filterLabel(L10n l, FavoritesFilter filter) {
    switch (filter) {
      case FavoritesFilter.all:
        return l.isArabic ? 'الكل' : 'All';
      case FavoritesFilter.messages:
        return l.isArabic ? 'الدردشات' : 'Chats';
      case FavoritesFilter.links:
        return l.isArabic ? 'الروابط' : 'Links';
      case FavoritesFilter.locations:
        return l.isArabic ? 'المواقع' : 'Places';
      case FavoritesFilter.miniPrograms:
        return l.isArabic ? 'البرامج' : 'Mini Programs';
      case FavoritesFilter.notes:
        return l.isArabic ? 'الملاحظات' : 'Notes';
    }
  }

  IconData _filterIcon(FavoritesFilter filter) {
    switch (filter) {
      case FavoritesFilter.all:
        return Icons.star_outline;
      case FavoritesFilter.messages:
        return Icons.chat_bubble_outline;
      case FavoritesFilter.links:
        return Icons.link_outlined;
      case FavoritesFilter.locations:
        return Icons.place_outlined;
      case FavoritesFilter.miniPrograms:
        return Icons.apps_outlined;
      case FavoritesFilter.notes:
        return Icons.note_outlined;
    }
  }

  Color _filterColor(FavoritesFilter filter) {
    switch (filter) {
      case FavoritesFilter.all:
        return const Color(0xFFF59E0B);
      case FavoritesFilter.messages:
        return const Color(0xFF3B82F6);
      case FavoritesFilter.links:
        return const Color(0xFF7C3AED);
      case FavoritesFilter.locations:
        return const Color(0xFFE11D48);
      case FavoritesFilter.miniPrograms:
        return const Color(0xFF059669);
      case FavoritesFilter.notes:
        return const Color(0xFF10B981);
    }
  }

  String _typeLabel(L10n l, Map<String, dynamic> item) {
    if (_isLocation(item)) return l.isArabic ? 'موقع' : 'Place';
    if (_isStarredMessage(item)) return l.isArabic ? 'رسالة' : 'Chat';
    if (_isMiniProgram(item))
      return l.isArabic ? 'برنامج مصغر' : 'Mini Program';
    if (_isLink(item)) return l.isArabic ? 'رابط' : 'Link';
    return l.isArabic ? 'ملاحظة' : 'Note';
  }

  Widget _filterPill({
    required ThemeData theme,
    required L10n l,
    required FavoritesFilter filter,
    required bool selected,
    required int count,
    required VoidCallback onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final color = _filterColor(filter);
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    final bg = selected
        ? ShamellPalette.green
        : (isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .32)
            : Colors.white);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? ShamellPalette.green
                : theme.dividerColor.withValues(alpha: isDark ? .45 : .80),
            width: .7,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _filterIcon(filter),
              size: 16,
              color: selected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              _filterLabel(l, filter),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              count > 99 ? '99+' : '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: selected
                    ? Colors.white.withValues(alpha: .86)
                    : theme.colorScheme.onSurface.withValues(alpha: .54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryPanel({
    required ThemeData theme,
    required L10n l,
    required int allCount,
    required int messagesCount,
    required int linksCount,
    required int locationsCount,
    required int miniProgramsCount,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final savedLabel = l.isArabic ? 'العناصر المحفوظة' : 'Saved items';
    final countLabel = l.isArabic ? '$allCount عنصر' : '$allCount items';
    final detailParts = <String>[
      l.isArabic ? '$messagesCount دردشات' : '$messagesCount chats',
      l.isArabic ? '$linksCount روابط' : '$linksCount links',
      l.isArabic ? '$locationsCount مواقع' : '$locationsCount places',
      if (miniProgramsCount > 0)
        l.isArabic
            ? '$miniProgramsCount برامج'
            : '$miniProgramsCount mini programs',
    ];
    final detail = detailParts.join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .46 : .82),
          width: .7,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: ShamellPalette.green.withValues(alpha: isDark ? .20 : .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bookmark_added_outlined,
              color: ShamellPalette.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  savedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            countLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: ShamellPalette.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required ThemeData theme,
    required L10n l,
    required bool hasQuery,
    required bool inChatView,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final showCreate = !inChatView && !hasQuery;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .46 : .82),
          width: .7,
        ),
      ),
      // Card chrome stays page-specific (matches the surrounding favorites
      // tiles); the shared widget supplies the inner empty-state semantics.
      child: hasQuery
          ? ShamellEmptyState.noResults(
              title: l.isArabic ? 'لا توجد نتائج.' : 'No results found.',
            )
          : ShamellEmptyState.empty(
              icon: Icons.bookmark_outline,
              title: l.shamellFavoritesEmpty,
              actionLabel:
                  showCreate ? (l.isArabic ? 'ملاحظة جديدة' : 'New note') : null,
              onAction: showCreate
                  ? () {
                      // ignore: discarded_futures
                      _showCreateNoteSheet();
                    }
                  : null,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    final String? chatIdFilter = widget.chatIdFilter?.trim().isNotEmpty == true
        ? widget.chatIdFilter!.trim()
        : null;
    final inChatView = chatIdFilter != null;

    final baseItems = inChatView
        ? _items
            .where((p) =>
                (p['chatId'] ?? '').toString() == chatIdFilter &&
                (p['msgId'] ?? '').toString().isNotEmpty)
            .toList()
        : List<Map<String, dynamic>>.from(_items);

    final effectiveFilter = inChatView ? FavoritesFilter.messages : _filter;
    final q = _searchCtrl.text.trim().toLowerCase();

    bool matchesFilter(Map<String, dynamic> p) {
      switch (effectiveFilter) {
        case FavoritesFilter.all:
          return true;
        case FavoritesFilter.messages:
          return _isStarredMessage(p);
        case FavoritesFilter.links:
          return _isLink(p);
        case FavoritesFilter.locations:
          return _isLocation(p);
        case FavoritesFilter.miniPrograms:
          return _isMiniProgram(p);
        case FavoritesFilter.notes:
          return _isNote(p);
      }
    }

    bool matchesSearch(Map<String, dynamic> p) {
      if (q.isEmpty) return true;
      final text = _displayText(p).toLowerCase();
      final chatId = (p['chatId'] ?? '').toString();
      final chatLabel = chatId.isNotEmpty ? _chatLabelFor(chatId) : '';
      final tagsText = chatId.isNotEmpty ? _tagsFor(chatId) : '';
      final miniProgramId = _miniProgramId(p);
      final haystack = [
        text,
        chatId.toLowerCase(),
        chatLabel.toLowerCase(),
        tagsText.toLowerCase(),
        miniProgramId.toLowerCase(),
      ].join(' ');
      return haystack.contains(q);
    }

    final filteredItems =
        baseItems.where(matchesFilter).where(matchesSearch).toList();

    final allCount = baseItems.length;
    final messagesCount = baseItems.where(_isStarredMessage).length;
    final linksCount = baseItems.where(_isLink).length;
    final locationsCount = baseItems.where(_isLocation).length;
    final miniProgramsCount = baseItems.where(_isMiniProgram).length;
    final notesCount = baseItems.where(_isNote).length;

    Widget listRow(Map<String, dynamic> p) {
      final text = _displayText(p);
      final rawTs = (p['ts'] ?? '').toString();
      final chatId = (p['chatId'] ?? '').toString();
      final msgId = (p['msgId'] ?? '').toString();
      final dt = _parseTs(rawTs);
      final timeLabel = _formatTime(dt);

      final isLocation = _isLocation(p);
      final miniProgramId = _miniProgramId(p);
      final lat = _asDouble(p['lat']);
      final lon = _asDouble(p['lon']);
      final webUri = _firstWebUri(text);

      final chatLabel = chatId.isNotEmpty ? _chatLabelFor(chatId) : '';
      final tagsText = chatId.isNotEmpty ? _tagsFor(chatId) : '';

      final Color leadColor;
      final IconData leadIcon;
      if (isLocation) {
        leadColor = const Color(0xFFE11D48);
        leadIcon = Icons.place_outlined;
      } else if (_isStarredMessage(p)) {
        leadColor = const Color(0xFF3B82F6);
        leadIcon = Icons.chat_bubble_outline;
      } else if (miniProgramId.isNotEmpty) {
        leadColor = const Color(0xFF059669);
        leadIcon = Icons.apps_outlined;
      } else if (webUri != null) {
        leadColor = const Color(0xFF7C3AED);
        leadIcon = Icons.link_outlined;
      } else {
        leadColor = const Color(0xFF10B981);
        leadIcon = Icons.note_outlined;
      }

      final subtitleLines = <Widget>[];
      if (chatId.isNotEmpty) {
        subtitleLines.add(
          Text(
            l.isArabic ? 'من دردشة: $chatLabel' : 'From chat: $chatLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
      if (chatId.isNotEmpty && tagsText.isNotEmpty) {
        subtitleLines.add(
          Text(
            '${l.shamellFavoritesTagsPrefix} $tagsText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
      if (chatId.isEmpty) {
        subtitleLines.add(
          Text(
            miniProgramId.isEmpty
                ? _typeLabel(l, p)
                : '${_typeLabel(l, p)} · $miniProgramId',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }

      return Dismissible(
        key: ObjectKey(p),
        direction: DismissDirection.endToStart,
        background: const SizedBox.shrink(),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          color: theme.colorScheme.error.withValues(alpha: .95),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Icon(
            Icons.delete_outline,
            color: theme.colorScheme.onError,
          ),
        ),
        onDismissed: (_) {
          // ignore: discarded_futures
          _deleteWithUndo(p);
        },
        child: ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: ShamellLeadingIcon(
            icon: leadIcon,
            background: leadColor,
          ),
          title: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ) ??
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: subtitleLines.isEmpty
              ? null
              : DefaultTextStyle(
                  style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .65),
                      ) ??
                      const TextStyle(fontSize: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: subtitleLines,
                  ),
                ),
          trailing: timeLabel.isEmpty
              ? null
              : Text(
                  timeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
          onTap: () {
            if (chatId.isNotEmpty) {
              _openChat(chatId, msgId: msgId);
              return;
            }
            if (isLocation && lat != null && lon != null) {
              // ignore: discarded_futures
              _openMap(lat, lon);
              return;
            }
            if (webUri != null) {
              // ignore: discarded_futures
              _openWebUri(webUri);
              return;
            }
            if (miniProgramId.isNotEmpty) {
              // ignore: discarded_futures
              _openMiniProgram(miniProgramId);
              return;
            }
            // ignore: discarded_futures
            _showActions(p);
          },
          onLongPress: () {
            // ignore: discarded_futures
            _showActions(p);
          },
        ),
      );
    }

    final title =
        inChatView ? l.shamellFavoritesFilterMessages : l.shamellFavoritesTitle;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          if (!inChatView)
            IconButton(
              tooltip: l.isArabic ? 'ملاحظة جديدة' : 'New note',
              onPressed: () {
                // ignore: discarded_futures
                _showCreateNoteSheet();
              },
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  const SizedBox(height: 10),
                  ShamellSearchBar(
                    hintText:
                        l.isArabic ? 'بحث في المفضلة' : 'Search favorites',
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (!inChatView && q.isEmpty)
                    _summaryPanel(
                      theme: theme,
                      l: l,
                      allCount: allCount,
                      messagesCount: messagesCount,
                      linksCount: linksCount,
                      locationsCount: locationsCount,
                      miniProgramsCount: miniProgramsCount,
                    ),
                  if (!inChatView) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (_, i) {
                          final filters = <FavoritesFilter>[
                            FavoritesFilter.all,
                            FavoritesFilter.messages,
                            FavoritesFilter.links,
                            FavoritesFilter.locations,
                            FavoritesFilter.miniPrograms,
                            FavoritesFilter.notes,
                          ];
                          final counts = <int>[
                            allCount,
                            messagesCount,
                            linksCount,
                            locationsCount,
                            miniProgramsCount,
                            notesCount,
                          ];
                          final filter = filters[i];
                          return _filterPill(
                            theme: theme,
                            l: l,
                            filter: filter,
                            selected: _filter == filter,
                            count: counts[i],
                            onTap: () => setState(() => _filter = filter),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemCount: 6,
                      ),
                    ),
                  ],
                  if (filteredItems.isEmpty)
                    _emptyState(
                      theme: theme,
                      l: l,
                      hasQuery: q.isNotEmpty,
                      inChatView: inChatView,
                    )
                  else
                    ShamellSection(
                      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      children: [for (final p in filteredItems) listRow(p)],
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
