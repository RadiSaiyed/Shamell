import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat/shamell_chat_page.dart';
import 'l10n.dart';
import 'shamell_ui.dart';

Future<void> addFavoriteItemQuick(
  String text, {
  String? chatId,
  String? msgId,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('favorites_items') ?? '[]';
    List list;
    try {
      final decoded = jsonDecode(raw);
      list = decoded is List ? decoded : <Object?>[];
    } catch (_) {
      list = <Object?>[];
    }
    final items =
        list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
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
    items.insert(0, entry);
    await sp.setString('favorites_items', jsonEncode(items));
  } catch (_) {}
}

Future<void> addFavoriteLocationQuick(
  double lat,
  double lon, {
  String? label,
  String? chatId,
  String? msgId,
}) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('favorites_items') ?? '[]';
    List list;
    try {
      final decoded = jsonDecode(raw);
      list = decoded is List ? decoded : <Object?>[];
    } catch (_) {
      list = <Object?>[];
    }
    final items =
        list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
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
    items.insert(0, entry);
    await sp.setString('favorites_items', jsonEncode(items));
  } catch (_) {}
}

enum FavoritesFilter { all, messages, locations, notes }

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
      final sp = await SharedPreferences.getInstance();
      final rawFav = sp.getString('favorites_items') ?? '[]';
      final decodedFav = jsonDecode(rawFav);
      if (decodedFav is List) {
        _items
          ..clear()
          ..addAll(decodedFav
              .whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList());
      }

      final rawAliases = sp.getString('friends.aliases') ?? '{}';
      final decodedAliases = jsonDecode(rawAliases);
      if (decodedAliases is Map) {
        final map = <String, String>{};
        decodedAliases.forEach((k, v) {
          final key = (k ?? '').toString();
          final val = (v ?? '').toString();
          if (key.isNotEmpty && val.isNotEmpty) {
            map[key] = val;
          }
        });
        _aliases = map;
      }

      final rawTags = sp.getString('friends.tags') ?? '{}';
      final decodedTags = jsonDecode(rawTags);
      if (decodedTags is Map) {
        final map = <String, String>{};
        decodedTags.forEach((k, v) {
          final key = (k ?? '').toString();
          final val = (v ?? '').toString();
          if (key.isNotEmpty && val.isNotEmpty) {
            map[key] = val;
          }
        });
        _tags = map;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('favorites_items', jsonEncode(_items));
    } catch (_) {}
  }

  bool _isLocation(Map<String, dynamic> p) {
    final kind = (p['kind'] ?? '').toString();
    if (kind == 'location') return true;
    final lat = p['lat'];
    final lon = p['lon'];
    return lat is num && lon is num;
  }

  bool _isStarredMessage(Map<String, dynamic> p) {
    final chatId = (p['chatId'] ?? '').toString();
    final msgId = (p['msgId'] ?? '').toString();
    return chatId.isNotEmpty && msgId.isNotEmpty;
  }

  bool _isNote(Map<String, dynamic> p) {
    return !_isStarredMessage(p) && !_isLocation(p);
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
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
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
    setState(() => _items.removeAt(idx));
    await _save();
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
              setState(() => _items.insert(idx, item));
              await _save();
            },
          ),
        ),
      );
  }

  Future<void> _addNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _items.insert(0, <String, Object?>{
        'text': trimmed,
        'ts': DateTime.now().toIso8601String(),
        'kind': 'note',
      });
    });
    await _save();
  }

  Future<void> _showCreateNoteSheet() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final ctrl = TextEditingController();
    final focus = FocusNode();

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

    ctrl.dispose();
    focus.dispose();
  }

  Future<void> _showActions(Map<String, dynamic> p) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    final text = (p['text'] ?? '').toString();
    final rawTs = (p['ts'] ?? '').toString();
    final chatId = (p['chatId'] ?? '').toString();
    final msgId = (p['msgId'] ?? '').toString();
    final isLocation = _isLocation(p);
    final lat = _asDouble(p['lat']);
    final lon = _asDouble(p['lon']);

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

  Widget _shortcutIcon({
    required ThemeData theme,
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required int count,
    required VoidCallback onTap,
  }) {
    final badgeText = count > 99 ? '99+' : count.toString();
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? ShamellPalette.green : color,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: (isDark ? Colors.black : Colors.black)
                                  .withValues(alpha: .10),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(icon, size: 22, color: Colors.white),
                ),
                if (count > 0)
                  Positioned(
                    top: -8,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .75),
              ),
            ),
          ],
        ),
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
        case FavoritesFilter.locations:
          return _isLocation(p);
        case FavoritesFilter.notes:
          return _isNote(p);
      }
    }

    bool matchesSearch(Map<String, dynamic> p) {
      if (q.isEmpty) return true;
      final text = (p['text'] ?? '').toString().toLowerCase();
      final chatId = (p['chatId'] ?? '').toString();
      final chatLabel = chatId.isNotEmpty ? _chatLabelFor(chatId) : '';
      final tagsText = chatId.isNotEmpty ? _tagsFor(chatId) : '';
      final haystack = [
        text,
        chatId.toLowerCase(),
        chatLabel.toLowerCase(),
        tagsText.toLowerCase(),
      ].join(' ');
      return haystack.contains(q);
    }

    final filteredItems =
        baseItems.where(matchesFilter).where(matchesSearch).toList();

    final allCount = baseItems.length;
    final messagesCount = baseItems.where(_isStarredMessage).length;
    final locationsCount = baseItems.where(_isLocation).length;
    final notesCount = baseItems.where(_isNote).length;

    Widget listRow(Map<String, dynamic> p) {
      final text = (p['text'] ?? '').toString();
      final rawTs = (p['ts'] ?? '').toString();
      final chatId = (p['chatId'] ?? '').toString();
      final msgId = (p['msgId'] ?? '').toString();
      final dt = _parseTs(rawTs);
      final timeLabel = _formatTime(dt);

      final isLocation = _isLocation(p);
      final lat = _asDouble(p['lat']);
      final lon = _asDouble(p['lon']);

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
          : ListView(
              children: [
                const SizedBox(height: 8),
                ShamellSearchBar(
                  hintText: l.isArabic ? 'بحث' : 'Search',
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                ),
                if (!inChatView && q.isEmpty)
                  ShamellSection(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          children: [
                            _shortcutIcon(
                              theme: theme,
                              label: l.isArabic ? 'الكل' : 'All',
                              icon: Icons.star_outline,
                              color: const Color(0xFFF59E0B),
                              selected: _filter == FavoritesFilter.all,
                              count: allCount,
                              onTap: () =>
                                  setState(() => _filter = FavoritesFilter.all),
                            ),
                            _shortcutIcon(
                              theme: theme,
                              label: l.isArabic ? 'الرسائل' : 'Chats',
                              icon: Icons.chat_bubble_outline,
                              color: const Color(0xFF3B82F6),
                              selected: _filter == FavoritesFilter.messages,
                              count: messagesCount,
                              onTap: () => setState(
                                  () => _filter = FavoritesFilter.messages),
                            ),
                            _shortcutIcon(
                              theme: theme,
                              label: l.isArabic ? 'المواقع' : 'Locations',
                              icon: Icons.place_outlined,
                              color: const Color(0xFFE11D48),
                              selected: _filter == FavoritesFilter.locations,
                              count: locationsCount,
                              onTap: () => setState(
                                  () => _filter = FavoritesFilter.locations),
                            ),
                            _shortcutIcon(
                              theme: theme,
                              label: l.isArabic ? 'الملاحظات' : 'Notes',
                              icon: Icons.note_outlined,
                              color: const Color(0xFF10B981),
                              selected: _filter == FavoritesFilter.notes,
                              count: notesCount,
                              onTap: () => setState(
                                  () => _filter = FavoritesFilter.notes),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (filteredItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        q.isNotEmpty
                            ? (l.isArabic
                                ? 'لا توجد نتائج.'
                                : 'No results found.')
                            : l.shamellFavoritesEmpty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .65),
                        ),
                      ),
                    ),
                  )
                else
                  ShamellSection(
                    margin: const EdgeInsets.only(top: 12),
                    children: [for (final p in filteredItems) listRow(p)],
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
