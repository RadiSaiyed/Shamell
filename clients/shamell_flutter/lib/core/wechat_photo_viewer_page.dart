import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat/chat_service.dart';
import 'chat/threema_chat_page.dart';
import 'l10n.dart';

class WeChatPhotoViewerPage extends StatefulWidget {
  final String? baseUrl;
  final List<String> sources;
  final List<String>? heroTags;
  final int initialIndex;

  const WeChatPhotoViewerPage({
    super.key,
    this.baseUrl,
    required this.sources,
    this.heroTags,
    this.initialIndex = 0,
  });

  @override
  State<WeChatPhotoViewerPage> createState() => _WeChatPhotoViewerPageState();
}

class _WeChatPhotoItem {
  final String source;
  final String? heroTag;

  const _WeChatPhotoItem({required this.source, required this.heroTag});
}

enum _WeChatPhotoAction {
  sendToChat,
  save,
  share,
}

class _WeChatPhotoViewerPageState extends State<WeChatPhotoViewerPage> {
  late final List<_WeChatPhotoItem> _items = (() {
    final cleaned = <_WeChatPhotoItem>[];
    final tags = widget.heroTags ?? const <String>[];
    for (var i = 0; i < widget.sources.length; i++) {
      final src = widget.sources[i].trim();
      if (src.isEmpty) continue;
      final tag = i < tags.length ? tags[i].trim() : '';
      cleaned.add(
        _WeChatPhotoItem(
          source: src,
          heroTag: tag.isNotEmpty ? tag : null,
        ),
      );
    }
    return cleaned;
  })();
  late final int _initial =
      widget.initialIndex.clamp(0, (_items.length - 1).clamp(0, 999999));
  late final PageController _pageCtrl = PageController(initialPage: _initial);

  final Map<int, Uint8List> _bytesCache = <int, Uint8List>{};
  final Map<int, String> _mimeCache = <int, String>{};
  final Map<int, TransformationController> _zoomCtrls =
      <int, TransformationController>{};

  int _index = 0;
  bool _chromeVisible = true;
  bool _working = false;
  Offset _lastDoubleTapPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _index = _initial;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in _zoomCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  String _stripDataUriPrefix(String s) {
    final idx = s.indexOf('base64,');
    if (idx < 0) return s;
    return s.substring(idx + 'base64,'.length);
  }

  String? _mimeFromDataUri(String s) {
    final raw = s.trim();
    if (!raw.startsWith('data:')) return null;
    final comma = raw.indexOf(',');
    if (comma < 0) return null;
    final header = raw.substring(5, comma);
    final semi = header.indexOf(';');
    final mime = (semi >= 0 ? header.substring(0, semi) : header).trim();
    return mime.isNotEmpty ? mime : null;
  }

  String? _sniffMime(Uint8List bytes) {
    if (bytes.length >= 12) {
      // PNG: 89 50 4E 47 0D 0A 1A 0A
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      // JPEG: FF D8
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'image/jpeg';
      }
      // GIF: GIF87a / GIF89a
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38) {
        return 'image/gif';
      }
      // WEBP: RIFF....WEBP
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }
    }
    return null;
  }

  String _extFromMime(String mime) {
    final m = mime.toLowerCase().trim();
    if (m == 'image/png') return 'png';
    if (m == 'image/gif') return 'gif';
    if (m == 'image/webp') return 'webp';
    return 'jpg';
  }

  Future<Uint8List?> _bytesFor(int index) async {
    if (_bytesCache.containsKey(index)) {
      return _bytesCache[index];
    }
    if (index < 0 || index >= _items.length) return null;
    final src = _items[index].source;
    try {
      Uint8List bytes;
      if (_isUrl(src)) {
        final resp = await http.get(Uri.parse(src));
        if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
        bytes = resp.bodyBytes;
      } else {
        final mime = _mimeFromDataUri(src);
        if (mime != null) _mimeCache[index] = mime;
        final b64 = _stripDataUriPrefix(src).trim();
        bytes = base64Decode(b64);
      }
      if (bytes.isEmpty) return null;
      _bytesCache[index] = bytes;
      _mimeCache[index] ??= _sniffMime(bytes) ?? 'image/jpeg';
      return bytes;
    } catch (_) {
      return null;
    }
  }

  String _mimeForIndex(int index) {
    final cached = _mimeCache[index];
    if (cached != null && cached.trim().isNotEmpty) return cached.trim();
    final src = index >= 0 && index < _items.length ? _items[index].source : '';
    final fromData = _mimeFromDataUri(src);
    if (fromData != null) return fromData;
    if (_isUrl(src)) {
      final lower = src.toLowerCase();
      if (lower.contains('.png')) return 'image/png';
      if (lower.contains('.webp')) return 'image/webp';
      if (lower.contains('.gif')) return 'image/gif';
    }
    return 'image/jpeg';
  }

  void _resetZoom(int index) {
    final c = _zoomCtrls[index];
    if (c == null) return;
    c.value = Matrix4.identity();
  }

  void _handleDoubleTap(int index) {
    final c = _zoomCtrls[index];
    if (c == null) return;
    final currentScale = c.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      c.value = Matrix4.identity();
      return;
    }
    const targetScale = 2.5;
    final p = _lastDoubleTapPos;
    c.value = Matrix4.identity()
      ..translateByDouble(
        -p.dx * (targetScale - 1),
        -p.dy * (targetScale - 1),
        0.0,
        1.0,
      )
      ..scaleByDouble(targetScale, targetScale, targetScale, 1.0);
  }

  void _toggleChrome() {
    setState(() {
      _chromeVisible = !_chromeVisible;
    });
  }

  Future<void> _openActions() async {
    if (_working) return;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? theme.colorScheme.surface : Colors.white;
    final l = L10n.of(context);

    final action = await showModalBottomSheet<_WeChatPhotoAction>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        final l2 = L10n.of(ctx);
        Widget tile({
          required IconData icon,
          required String title,
          required _WeChatPhotoAction value,
        }) {
          return ListTile(
            leading: Icon(icon),
            title: Text(title),
            onTap: () => Navigator.of(ctx).pop(value),
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((widget.baseUrl ?? '').trim().isNotEmpty)
                tile(
                  icon: Icons.chat_bubble_outline,
                  title: l2.isArabic ? 'إرسال إلى دردشة' : 'Send to chat',
                  value: _WeChatPhotoAction.sendToChat,
                ),
              tile(
                icon: Icons.download_outlined,
                title: l2.isArabic ? 'حفظ الصورة' : 'Save image',
                value: _WeChatPhotoAction.save,
              ),
              tile(
                icon: Icons.share_outlined,
                title: l2.isArabic ? 'مشاركة' : 'Share',
                value: _WeChatPhotoAction.share,
              ),
              const Divider(height: 1),
              ListTile(
                title: Center(
                  child: Text(
                    l2.isArabic ? 'إلغاء' : 'Cancel',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    switch (action) {
      case _WeChatPhotoAction.sendToChat:
        await _sendToChat(l);
        break;
      case _WeChatPhotoAction.save:
        await _saveCurrent(l);
        break;
      case _WeChatPhotoAction.share:
        await _shareCurrent(l);
        break;
    }
  }

  Future<_WeChatSendToChatTarget?> _pickSendTarget({
    required L10n l,
    required String baseUrl,
  }) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? theme.colorScheme.surface : Colors.white;
    return showModalBottomSheet<_WeChatSendToChatTarget>(
      context: context,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => _WeChatSendToChatSheet(
        baseUrl: baseUrl,
        isArabic: l.isArabic,
      ),
    );
  }

  Future<void> _sendToChat(L10n l) async {
    final baseUrl = (widget.baseUrl ?? '').trim();
    if (baseUrl.isEmpty) return;

    if (_working) return;
    setState(() => _working = true);
    Uint8List? bytes;
    try {
      bytes = await _bytesFor(_index);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تعذّر تحميل الصورة' : 'Failed to load image',
            ),
          ),
        );
      return;
    }

    final target = await _pickSendTarget(l: l, baseUrl: baseUrl);
    if (!mounted || target == null) return;
    final mime = _mimeForIndex(_index);
    final ext = _extFromMime(mime);
    final name = 'moment_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ThreemaChatPage(
          baseUrl: baseUrl,
          initialPeerId: target.id,
          showBottomNav: false,
          presetAttachmentBytes: bytes,
          presetAttachmentMime: mime,
          presetAttachmentName: name,
        ),
      ),
    );
  }

  Future<void> _saveCurrent(L10n l) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (kIsWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic
                    ? 'الحفظ غير مدعوم على الويب.'
                    : 'Saving is not supported on web.',
              ),
            ),
          );
        return;
      }
      final bytes = await _bytesFor(_index);
      if (bytes == null || bytes.isEmpty || !mounted) return;
      final name = 'moments_${DateTime.now().millisecondsSinceEpoch}';
      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        quality: 95,
        name: name,
      );
      final success = (result['isSuccess'] == true) ||
          (result['isSuccess'] == 1) ||
          (result['success'] == true) ||
          (result['success'] == 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? (l.isArabic ? 'تم حفظ الصورة.' : 'Image saved.')
                  : (l.isArabic ? 'تعذّر حفظ الصورة.' : 'Save failed.'),
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تعذّر حفظ الصورة: $e' : 'Save failed: $e',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _shareCurrent(L10n l) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final bytes = await _bytesFor(_index);
      if (bytes == null || bytes.isEmpty) return;
      final mime = _mimeForIndex(_index);
      final ext = _extFromMime(mime);
      final file = XFile.fromData(
        bytes,
        mimeType: mime,
        name: 'moment_${_index + 1}.$ext',
      );
      await Share.shareXFiles([file]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'فشل المشاركة: $e' : 'Share failed: $e',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _buildPhotoPage(BuildContext context, int index) {
    final src = _items[index].source;
    Widget content;

    if (_isUrl(src)) {
      content = Image.network(
        src,
        fit: BoxFit.contain,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (ctx, err, st) {
          return Center(
            child: Text(
              L10n.of(ctx).isArabic
                  ? 'تعذّر تحميل الصورة'
                  : 'Failed to load image',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        },
      );
    } else {
      final cached = _bytesCache[index];
      Uint8List? bytes;
      if (cached != null && cached.isNotEmpty) {
        bytes = cached;
      } else {
        try {
          final mime = _mimeFromDataUri(src);
          if (mime != null) _mimeCache[index] = mime;
          final b64 = _stripDataUriPrefix(src).trim();
          bytes = base64Decode(b64);
          if (bytes.isNotEmpty) {
            _bytesCache[index] = bytes;
            _mimeCache[index] ??= _sniffMime(bytes) ?? 'image/jpeg';
          }
        } catch (_) {
          bytes = null;
        }
      }
      if (bytes == null || bytes.isEmpty) {
        content = Center(
          child: Text(
            L10n.of(context).isArabic
                ? 'تعذّر تحميل الصورة'
                : 'Failed to load image',
            style: const TextStyle(color: Colors.white70),
          ),
        );
      } else {
        content = Image.memory(bytes, fit: BoxFit.contain);
      }
    }

    final tag = _items[index].heroTag;
    if (tag != null) {
      content = Hero(
        tag: tag,
        child: content,
      );
    }

    final zoomCtrl =
        _zoomCtrls.putIfAbsent(index, () => TransformationController());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleChrome,
      onDoubleTapDown: (d) => _lastDoubleTapPos = d.localPosition,
      onDoubleTap: () => _handleDoubleTap(index),
      onLongPress: _openActions,
      child: Center(
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          transformationController: zoomCtrl,
          child: content,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final top = SafeArea(
      bottom: false,
      child: SizedBox(
        height: kToolbarHeight,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              color: Colors.white,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${_index + 1}/${_items.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_horiz),
              color: Colors.white,
              onPressed: _openActions,
              tooltip: l.isArabic ? 'المزيد' : 'More',
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() {
              _resetZoom(_index);
              _index = i;
            }),
            itemBuilder: _buildPhotoPage,
          ),
          AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xB3000000),
                      Color(0x00000000),
                    ],
                  ),
                ),
                child: top,
              ),
            ),
          ),
          if (_working)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: .18),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeChatSendToChatTarget {
  final String id;
  final String displayName;
  final bool pinned;

  const _WeChatSendToChatTarget({
    required this.id,
    required this.displayName,
    required this.pinned,
  });
}

class _WeChatSendToChatSheet extends StatefulWidget {
  final String baseUrl;
  final bool isArabic;

  const _WeChatSendToChatSheet({
    required this.baseUrl,
    required this.isArabic,
  });

  @override
  State<_WeChatSendToChatSheet> createState() => _WeChatSendToChatSheetState();
}

class _WeChatSendToChatSheetState extends State<_WeChatSendToChatSheet> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<_WeChatSendToChatTarget> _targets = const <_WeChatSendToChatTarget>[];

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

  Map<String, String> _decodeStringMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, String>{};
        decoded.forEach((k, v) {
          final key = (k ?? '').toString().trim();
          final val = (v ?? '').toString().trim();
          if (key.isNotEmpty && val.isNotEmpty) out[key] = val;
        });
        return out;
      }
    } catch (_) {}
    return const <String, String>{};
  }

  String _friendChatId(Map<String, dynamic> f) {
    final deviceId = (f['device_id'] ?? '').toString().trim();
    if (deviceId.isNotEmpty) return deviceId;
    final shamellId = (f['shamell_id'] ?? '').toString().trim();
    if (shamellId.isNotEmpty) return shamellId;
    final id = (f['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    final phone = (f['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;
    return '';
  }

  Future<Map<String, String>> _authHeaders() async {
    final h = <String, String>{};
    try {
      final sp = await SharedPreferences.getInstance();
      final cookie = sp.getString('sa_cookie') ?? '';
      if (cookie.isNotEmpty) h['sa_cookie'] = cookie;
    } catch (_) {}
    return h;
  }

  Future<List<_WeChatSendToChatTarget>> _loadTargetsFromLocalChats() async {
    final contacts = await ChatLocalStore().loadContacts();
    final out = <_WeChatSendToChatTarget>[];
    final seen = <String>{};
    for (final c in contacts) {
      final id = c.id.trim();
      if (id.isEmpty) continue;
      if (id.startsWith('__')) continue;
      if (c.blocked) continue;
      if (!seen.add(id)) continue;
      final name = (c.name ?? '').toString().trim();
      out.add(
        _WeChatSendToChatTarget(
          id: id,
          displayName: name.isNotEmpty ? name : id,
          pinned: c.pinned,
        ),
      );
    }
    out.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return out;
  }

  Future<List<_WeChatSendToChatTarget>> _loadTargetsFromFriends() async {
    final sp = await SharedPreferences.getInstance();
    final aliases = _decodeStringMap(sp.getString('friends.aliases') ?? '{}');
    final uri = Uri.parse('${widget.baseUrl}/me/friends');
    final resp = await http.get(uri, headers: await _authHeaders());
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}',
      );
    }
    final decoded = jsonDecode(resp.body);
    final raw = (decoded is Map ? decoded['friends'] : decoded) as Object?;
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(e.cast<String, dynamic>());
      }
    }

    final out = <_WeChatSendToChatTarget>[];
    final seen = <String>{};
    for (final f in list) {
      final id = _friendChatId(f);
      if (id.isEmpty) continue;
      if (!seen.add(id)) continue;
      final nameRaw = (f['name'] ?? f['id'] ?? id).toString().trim();
      final alias = aliases[id]?.trim();
      final display = (alias != null && alias.isNotEmpty)
          ? alias
          : (nameRaw.isNotEmpty ? nameRaw : id);
      out.add(
        _WeChatSendToChatTarget(
          id: id,
          displayName: display,
          pinned: false,
        ),
      );
    }
    out.sort((a, b) {
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var targets = await _loadTargetsFromLocalChats();
      targets = targets.isNotEmpty ? targets : await _loadTargetsFromFriends();
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _targets
        : _targets
            .where((t) =>
                t.displayName.toLowerCase().contains(q) ||
                t.id.toLowerCase().contains(q))
            .toList();

    final maxHeight = MediaQuery.of(context).size.height * 0.86;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isArabic ? 'إرسال إلى دردشة' : 'Send to chat',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(widget.isArabic ? 'إلغاء' : 'Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.isArabic ? 'بحث' : 'Search',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(
                          alpha:
                              theme.brightness == Brightness.dark ? .30 : .60),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Builder(
                  builder: (ctx) {
                    if (_loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final err = (_error ?? '').trim();
                    if (err.isNotEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.isArabic
                                  ? 'تعذّر تحميل المحادثات'
                                  : 'Failed to load chats',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              err,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .60),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _load,
                              child: Text(
                                  widget.isArabic ? 'إعادة المحاولة' : 'Retry'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          widget.isArabic
                              ? 'لا توجد محادثات'
                              : 'No chats found',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final t = filtered[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(
                            t.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            t.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .60),
                            ),
                          ),
                          trailing: t.pinned
                              ? const Icon(Icons.push_pin, size: 18)
                              : null,
                          onTap: () => Navigator.of(context).pop(t),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
