import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'chat/chat_models.dart';
import 'chat/chat_service.dart';
import 'chat/threema_chat_page.dart';
import 'l10n.dart';

class GlobalMediaPage extends StatefulWidget {
  final String baseUrl;

  const GlobalMediaPage({super.key, required this.baseUrl});

  @override
  State<GlobalMediaPage> createState() => _GlobalMediaPageState();
}

class _GlobalMediaPageState extends State<GlobalMediaPage> {
  bool _loading = true;
  String? _error;
  String _filter = 'media'; // media, files, links
  List<_MediaEntry> _items = const <_MediaEntry>[];
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

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
    setState(() {
      _loading = true;
      _error = null;
      _items = const <_MediaEntry>[];
    });
    try {
      final store = ChatLocalStore();
      final contacts = await store.loadContacts();
      final List<_MediaEntry> collected = [];
      for (final c in contacts) {
        final peerId = c.id;
        if (peerId.isEmpty) continue;
        final msgs = await store.loadMessages(peerId);
        for (final m in msgs) {
          try {
            final decoded = _decode(m);
            final att = decoded.attachment;
            final mime = decoded.mime ?? '';
            final text = decoded.text;
            final isVoice = (decoded.kind ?? '') == 'voice';
            final hasLink = _hasLink(text);
            if (att != null && att.isNotEmpty) {
              if (!isVoice && _isImageOrVideo(mime)) {
                collected.add(_MediaEntry(
                  kind: 'media',
                  message: m,
                  peerId: peerId,
                  text: text,
                ));
              } else if (!isVoice) {
                collected.add(_MediaEntry(
                  kind: 'file',
                  message: m,
                  peerId: peerId,
                  text: text,
                ));
              }
            }
            if (hasLink) {
              collected.add(_MediaEntry(
                kind: 'link',
                message: m,
                peerId: peerId,
                text: text,
              ));
            }
          } catch (_) {}
        }
      }
      if (!mounted) return;
      setState(() {
        _items = collected;
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

  bool _hasLink(String text) {
    final t = text.toLowerCase();
    return t.contains('http://') ||
        t.contains('https://') ||
        t.contains('www.');
  }

  bool _isImageOrVideo(String mime) {
    final low = mime.toLowerCase();
    return low.startsWith('image/') || low.startsWith('video/');
  }

  _Decoded _decode(ChatMessage m) {
    try {
      final raw = m.boxB64;
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        final text = (map['text'] ?? '').toString();
        Uint8List? att;
        String? mime;
        if (map['attachment_b64'] is String &&
            (map['attachment_b64'] as String).isNotEmpty) {
          try {
            att = base64Decode(map['attachment_b64'] as String);
            mime = (map['attachment_mime'] ?? 'application/octet-stream')
                .toString();
          } catch (_) {}
        }
        final kind = (map['kind'] ?? '').toString();
        return _Decoded(text: text, attachment: att, mime: mime, kind: kind);
      }
    } catch (_) {}
    return _Decoded(text: '', attachment: null, mime: null, kind: null);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _items.where((e) {
      if (_filter == 'media' && e.kind != 'media') return false;
      if (_filter == 'files' && e.kind != 'file') return false;
      if (_filter == 'links' && e.kind != 'link') return false;
      if (q.isNotEmpty) {
        final text = e.text.toLowerCase();
        final peer = e.peerId.toLowerCase();
        if (!text.contains(q) && !peer.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final ta = a.message.createdAt ?? a.message.deliveredAt;
        final tb = b.message.createdAt ?? b.message.deliveredAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      );
    } else if (filtered.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 40,
                color: theme.colorScheme.onSurface.withValues(alpha: .35),
              ),
              const SizedBox(height: 8),
              Text(
                l.mirsaalGlobalMediaEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      body = ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (ctx, i) {
          final e = filtered[i];
          final m = e.message;
          final ts = m.createdAt ?? m.deliveredAt;
          String tsLabel = '';
          if (ts != null) {
            final dt = ts.toLocal();
            tsLabel =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }
          final title = e.text.isNotEmpty
              ? e.text
              : (e.kind == 'media'
                  ? l.mirsaalPreviewImage
                  : l.mirsaalPreviewUnknown);
          final subtitle =
              tsLabel.isEmpty ? e.peerId : '$tsLabel · ${e.peerId}';
          return ListTile(
            dense: true,
            leading: Icon(
              e.kind == 'media'
                  ? Icons.photo_library_outlined
                  : (e.kind == 'file'
                      ? Icons.insert_drive_file_outlined
                      : Icons.link_outlined),
            ),
            title: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ThreemaChatPage(
                    baseUrl: widget.baseUrl,
                    initialPeerId: e.peerId,
                    initialMessageId: m.id,
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.mirsaalGlobalMediaTitle),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.mirsaalGlobalMediaSearchHint,
              ),
              textInputAction: TextInputAction.search,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l.mirsaalSearchFilterMedia),
                  selected: _filter == 'media',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() => _filter = 'media');
                  },
                ),
                ChoiceChip(
                  label: Text(l.mirsaalSearchFilterFiles),
                  selected: _filter == 'files',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() => _filter = 'files');
                  },
                ),
                ChoiceChip(
                  label: Text(l.mirsaalSearchFilterLinks),
                  selected: _filter == 'links',
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() => _filter = 'links');
                  },
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _MediaEntry {
  final String kind; // media / file / link
  final ChatMessage message;
  final String peerId;
  final String text;

  _MediaEntry({
    required this.kind,
    required this.message,
    required this.peerId,
    required this.text,
  });
}

class _Decoded {
  final String text;
  final Uint8List? attachment;
  final String? mime;
  final String? kind;

  _Decoded({
    required this.text,
    required this.attachment,
    required this.mime,
    required this.kind,
  });
}
