import 'package:flutter/material.dart';
import 'dart:async';

import 'chat/shamell_chat_page.dart';
import 'friend_annotations_store.dart';
import 'l10n.dart';
import 'shamell_empty_state.dart';
import 'shamell_ui.dart';

class FriendTagsPage extends StatefulWidget {
  final String baseUrl;
  const FriendTagsPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<FriendTagsPage> createState() => _FriendTagsPageState();
}

class _FriendTagsPageState extends State<FriendTagsPage> {
  bool _loading = true;
  Map<String, String> _tagsByChat = const <String, String>{};
  Map<String, List<String>> _tagToChatIds = const <String, List<String>>{};
  Map<String, String> _aliases = const <String, String>{};
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tagsByChat = await loadFriendTags(baseUrlOverride: widget.baseUrl);
      final ordered = _buildTagToChatIds(
        tagsByChat: tagsByChat,
        aliases: const <String, String>{},
      );

      if (!mounted) return;
      setState(() {
        _tagsByChat = tagsByChat;
        _tagToChatIds = ordered;
        _loading = false;
      });
      unawaited(_loadAliases());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadAliases() async {
    try {
      final aliases = await loadFriendAliases(baseUrlOverride: widget.baseUrl);
      if (!mounted) return;
      setState(() {
        _aliases = aliases;
        _tagToChatIds =
            _buildTagToChatIds(tagsByChat: _tagsByChat, aliases: aliases);
      });
    } catch (_) {}
  }

  Map<String, List<String>> _buildTagToChatIds({
    required Map<String, String> tagsByChat,
    required Map<String, String> aliases,
  }) {
    final tagToChat = <String, List<String>>{};
    for (final entry in tagsByChat.entries) {
      final chatId = entry.key.trim();
      final raw = entry.value.trim();
      if (chatId.isEmpty || raw.isEmpty) continue;
      final tags = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      for (final t in tags) {
        final list = tagToChat.putIfAbsent(t, () => <String>[]);
        if (!list.contains(chatId)) {
          list.add(chatId);
        }
      }
    }

    for (final list in tagToChat.values) {
      list.sort((a, b) {
        final da = (aliases[a] ?? a).toLowerCase();
        final db = (aliases[b] ?? b).toLowerCase();
        return da.compareTo(db);
      });
    }

    final sorted = tagToChat.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return <String, List<String>>{
      for (final e in sorted) e.key: e.value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final tags = _tagToChatIds;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    final filtered = () {
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return tags.entries.toList();
      return tags.entries
          .where((e) => e.key.toLowerCase().contains(q))
          .toList();
    }();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الوسوم' : 'Tags'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (tags.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l.isArabic
                          ? 'لا توجد وسوم بعد. أضِف وسمًا لجهة اتصال من شاشة معلومات جهة الاتصال.'
                          : 'No tags yet. Add a tag to a contact from Contact info.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    const SizedBox(height: 8),
                    ShamellSearchBar(
                      hintText: l.isArabic ? 'بحث' : 'Search',
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    if (filtered.isEmpty)
                      ShamellEmptyState.noResults(
                        title:
                            l.isArabic ? 'لا توجد نتائج.' : 'No matches found.',
                      )
                    else
                      ShamellSection(
                        children: [
                          for (final entry in filtered)
                            ListTile(
                              dense: true,
                              leading: const ShamellLeadingIcon(
                                icon: Icons.sell_outlined,
                                background: Color(0xFF3B82F6),
                              ),
                              title: Text(entry.key),
                              subtitle: Text(
                                l.isArabic
                                    ? '${entry.value.length} جهات اتصال'
                                    : '${entry.value.length} contacts',
                              ),
                              trailing: chevron(),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => _TagMembersPage(
                                      baseUrl: widget.baseUrl,
                                      tag: entry.key,
                                      chatIds: entry.value,
                                      aliases: _aliases,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                  ],
                )),
    );
  }
}

class _TagMembersPage extends StatefulWidget {
  final String baseUrl;
  final String tag;
  final List<String> chatIds;
  final Map<String, String> aliases;

  const _TagMembersPage({
    required this.baseUrl,
    required this.tag,
    required this.chatIds,
    required this.aliases,
  });

  @override
  State<_TagMembersPage> createState() => _TagMembersPageState();
}

class _TagMembersPageState extends State<_TagMembersPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

    final filtered = () {
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return widget.chatIds;
      return widget.chatIds.where((id) {
        final label = (widget.aliases[id] ?? '').trim();
        return id.toLowerCase().contains(q) || label.toLowerCase().contains(q);
      }).toList();
    }();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(widget.tag),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ShamellSearchBar(
            hintText: l.isArabic ? 'بحث' : 'Search',
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
          ),
          if (filtered.isEmpty)
            ShamellEmptyState.noResults(
              title: l.isArabic ? 'لا توجد نتائج.' : 'No matches found.',
            )
          else
            ShamellSection(
              children: [
                for (final id in filtered)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      child: Text(
                        ((widget.aliases[id] ?? '').trim().isNotEmpty
                                ? widget.aliases[id]!
                                : id)
                            .substring(0, 1)
                            .toUpperCase(),
                      ),
                    ),
                    title: Text(() {
                      final label = (widget.aliases[id] ?? '').trim();
                      return label.isNotEmpty ? label : id;
                    }()),
                    subtitle: (() {
                      final label = (widget.aliases[id] ?? '').trim();
                      if (label.isEmpty) return null;
                      return Text(id);
                    }()),
                    trailing: chevron(),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShamellChatPage(
                            baseUrl: widget.baseUrl,
                            initialPeerId: id,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
