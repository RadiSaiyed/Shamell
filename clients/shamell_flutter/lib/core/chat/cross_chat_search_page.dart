import 'package:flutter/material.dart';

import '../l10n.dart';
import 'cross_chat_search.dart';

/// Dedicated page that lets the user search for messages across ALL of
/// their conversations (Cycle 3D). Receives a [CrossChatSearchIndex]
/// snapshot at construction time — the index is built from the chat
/// page's in-memory message caches the moment the user opens this page,
/// so there's no streaming-update story to manage here; if a new message
/// arrives during the search, the user can re-open to refresh.
///
/// **Why a separate widget instead of inlining into the chat page.** The
/// chat page is already 24k+ lines. Adding search-results UI inline
/// would mean threading new state, a new visibility flag, and a fourth
/// list-vs-search-vs-thread-vs-info mode through that giant build
/// method. Lifting it to its own widget keeps the chat page diff to one
/// entry button + one Navigator.push call, and the search UI stays
/// independently testable.
class CrossChatSearchPage extends StatefulWidget {
  /// The pre-built index of all messages across direct + group chats.
  final CrossChatSearchIndex index;

  /// Map from conversation id (peer device id OR group id) to the
  /// human-readable label to show as the result section header /
  /// per-result subtitle. For direct chats this is typically the
  /// peer's alias or device id; for groups it's the group name. If a
  /// conversation id is missing from this map the row falls back to
  /// showing the raw id.
  final Map<String, String> conversationLabels;

  /// Called when the user taps a search result. The chat page should
  /// pop this search page off the navigator and navigate the user to
  /// the (peer or group) conversation, scrolling the requested message
  /// into view if possible. The page itself does NOT auto-pop on tap —
  /// the host controls that so it can sequence the navigation cleanly.
  final void Function(
      {required String conversationId,
      required bool isGroup,
      required String messageId}) onOpenResult;

  const CrossChatSearchPage({
    super.key,
    required this.index,
    required this.conversationLabels,
    required this.onOpenResult,
  });

  @override
  State<CrossChatSearchPage> createState() => _CrossChatSearchPageState();
}

class _CrossChatSearchPageState extends State<CrossChatSearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<CrossChatSearchEntry> _results = const <CrossChatSearchEntry>[];
  String _lastQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _runSearch(String raw) {
    final trimmed = raw.trim();
    if (trimmed == _lastQuery) return;
    _lastQuery = trimmed;
    setState(() {
      _results = widget.index.matches(trimmed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final showEmpty = _searchCtrl.text.trim().isEmpty;
    final showNoResults = !showEmpty && _results.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'البحث في الكل' : 'Search all chats',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _runSearch,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _runSearch('');
                        },
                      )
                    : null,
                hintText: l.isArabic
                    ? 'ابحث عن رسالة أو اسم...'
                    : 'Search messages or names…',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: showEmpty
                ? _CrossChatSearchEmptyHint(l: l, theme: theme)
                : showNoResults
                    ? _CrossChatSearchNoResults(l: l, theme: theme)
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          final label = widget.conversationLabels[
                                  r.conversationId] ??
                              r.conversationId;
                          return ListTile(
                            leading: Icon(
                              r.isGroup ? Icons.group : Icons.person_outline,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .55),
                            ),
                            title: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: r.previewSnippet.isEmpty
                                ? null
                                : Text(
                                    r.previewSnippet,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => widget.onOpenResult(
                              conversationId: r.conversationId,
                              isGroup: r.isGroup,
                              messageId: r.messageId,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _CrossChatSearchEmptyHint extends StatelessWidget {
  final L10n l;
  final ThemeData theme;

  const _CrossChatSearchEmptyHint({required this.l, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          l.isArabic
              ? 'اكتب كلمة للبحث في جميع المحادثات.'
              : 'Type a word to search across all your conversations.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .55),
          ),
        ),
      ),
    );
  }
}

class _CrossChatSearchNoResults extends StatelessWidget {
  final L10n l;
  final ThemeData theme;

  const _CrossChatSearchNoResults({required this.l, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          l.isArabic ? 'لا توجد نتائج.' : 'No matches.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .55),
          ),
        ),
      ),
    );
  }
}
