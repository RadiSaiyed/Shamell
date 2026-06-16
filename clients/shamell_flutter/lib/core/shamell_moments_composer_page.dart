import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_error.dart';
import 'l10n.dart';
import 'shamell_ui.dart';
import 'safe_set_state.dart';

class ShamellMomentDraft {
  final String text;
  final List<Uint8List> imageBytes;
  final List<String> imageMimes;
  final String? locationLabel;
  final String visibilityScope;
  final List<String> remindIds;
  final List<String> remindNames;

  const ShamellMomentDraft({
    required this.text,
    required this.visibilityScope,
    this.imageBytes = const <Uint8List>[],
    this.imageMimes = const <String>[],
    this.locationLabel,
    this.remindIds = const <String>[],
    this.remindNames = const <String>[],
  });
}

class ShamellMomentsComposerPage extends StatefulWidget {
  final String baseUrl;
  final String initialText;
  final Uint8List? initialImageBytes;
  final String? initialImageMime;
  final String initialVisibilityScope;

  const ShamellMomentsComposerPage({
    super.key,
    required this.baseUrl,
    this.initialText = '',
    this.initialImageBytes,
    this.initialImageMime,
    this.initialVisibilityScope = 'public',
  });

  @override
  State<ShamellMomentsComposerPage> createState() =>
      _ShamellMomentsComposerPageState();
}

class _ShamellComposerImage {
  final Uint8List bytes;
  final String mime;
  const _ShamellComposerImage({required this.bytes, required this.mime});
}

class _ShamellMomentsComposerPageState extends State<ShamellMomentsComposerPage>
    with SafeSetStateMixin<ShamellMomentsComposerPage> {
  static const int _kMaxImages = 9;
  static const Duration _momentsComposerRequestTimeout = Duration(seconds: 15);
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialText);
  final List<_ShamellComposerImage> _images = <_ShamellComposerImage>[];
  late String _visibilityScope = widget.initialVisibilityScope;
  String? _locationLabel;
  List<String> _remindIds = <String>[];
  List<String> _remindNames = <String>[];
  String _lastText = '';
  bool _mentionPickerOpen = false;
  bool _suppressAtTrigger = false;
  String _profileName = '';
  String _profilePhone = '';

  void _onComposerChanged() {
    if (!mounted) return;
    final nextText = _ctrl.text;
    final nextSelection = _ctrl.selection;

    if (_suppressAtTrigger) {
      _suppressAtTrigger = false;
      _lastText = nextText;
      setState(() {});
      return;
    }

    int? atIndex;
    if (!_mentionPickerOpen &&
        nextSelection.isValid &&
        nextSelection.isCollapsed &&
        nextText.length == _lastText.length + 1) {
      final cursor = nextSelection.baseOffset;
      if (cursor > 0 && cursor <= nextText.length) {
        final idx = cursor - 1;
        if (idx >= 0 && idx < nextText.length && nextText[idx] == '@') {
          final candidate =
              '${nextText.substring(0, idx)}${nextText.substring(cursor)}';
          if (candidate == _lastText) {
            atIndex = idx;
          }
        }
      }
    }

    _lastText = nextText;
    setState(() {});

    if (atIndex != null) {
      Future<void>(() async {
        await _openMentionPicker(atIndex!);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialImageBytes;
    if (initial != null && initial.isNotEmpty) {
      _images.add(
        _ShamellComposerImage(
          bytes: initial,
          mime: (widget.initialImageMime ?? 'image/jpeg').trim().isNotEmpty
              ? widget.initialImageMime!.trim()
              : 'image/jpeg',
        ),
      );
    }
    _lastText = _ctrl.text;
    _ctrl.addListener(_onComposerChanged);
    unawaited(_loadProfileSummary());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onComposerChanged);
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canPost {
    final hasText = _ctrl.text.trim().isNotEmpty;
    final hasImage = _images.isNotEmpty;
    return hasText || hasImage;
  }

  Future<void> _loadProfileSummary() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final name = (sp.getString('last_login_name') ?? '').trim();
      final phone = (sp.getString('last_login_phone') ?? '').trim();
      if (!mounted) return;
      setState(() {
        _profileName = name;
        _profilePhone = phone;
      });
    } catch (_) {}
  }

  Future<void> _openImagePreview(int index) async {
    if (!mounted) return;
    if (index < 0 || index >= _images.length) return;
    final bytes = _images[index].bytes;
    if (bytes.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .92),
      builder: (ctx) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }

  String _cleanupComposerText(String text) {
    var t = text;
    t = t.replaceAll(RegExp(r'[ ]{2,}'), ' ');
    t = t.replaceAll(RegExp(r'[ ]+\n'), '\n');
    t = t.replaceAll(RegExp(r'\n[ ]+'), '\n');
    return t;
  }

  RegExp _mentionRegexFor(String name) {
    final cleaned = name.trim();
    final escaped = RegExp.escape(cleaned);
    return RegExp(
      '(^|\\s)@$escaped(?=\\s|\\\$|[\\]\\[\\}\\)\\(,，。.!؟?!;:])',
      multiLine: true,
    );
  }

  bool _containsMention(String text, String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return false;
    return _mentionRegexFor(cleaned).hasMatch(text);
  }

  String _removeMentionToken(String text, String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return text;
    final re = _mentionRegexFor(cleaned);
    return text.replaceAllMapped(re, (m) => m.group(1) ?? '');
  }

  String _buildMentionsInsertion({
    required String text,
    required int at,
    required List<String> names,
  }) {
    final unique = <String>[];
    final seen = <String>{};
    for (final raw in names) {
      final n = raw.trim();
      if (n.isEmpty) continue;
      if (seen.add(n)) unique.add(n);
    }
    if (unique.isEmpty) return '';

    final pieces = <String>[];
    for (final name in unique) {
      if (_containsMention(text, name)) continue;
      pieces.add('@$name');
    }
    if (pieces.isEmpty) return '';

    var insertion = '${pieces.join(' ')} ';
    if (at > 0 && at <= text.length) {
      final prev = text[at - 1];
      if (!RegExp(r'\s').hasMatch(prev)) {
        insertion = ' $insertion';
      }
    }
    return insertion;
  }

  void _mergeRemindSelection({
    required List<String> ids,
    required List<String> names,
  }) {
    final order = <String>[];
    final nameById = <String, String>{};

    void add(String id, String name) {
      final cleanId = id.trim();
      if (cleanId.isEmpty) return;
      if (!nameById.containsKey(cleanId)) {
        order.add(cleanId);
        nameById[cleanId] = name.trim();
        return;
      }
      final existing = (nameById[cleanId] ?? '').trim();
      if (existing.isEmpty && name.trim().isNotEmpty) {
        nameById[cleanId] = name.trim();
      }
    }

    for (var i = 0; i < _remindIds.length; i++) {
      final id = _remindIds[i];
      final name = i < _remindNames.length ? _remindNames[i] : '';
      add(id, name);
    }
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final name = i < names.length ? names[i] : '';
      add(id, name);
    }

    setState(() {
      _remindIds = order;
      _remindNames = order.map((id) {
        final n = (nameById[id] ?? '').trim();
        return n.isNotEmpty ? n : id;
      }).toList();
    });
  }

  Future<void> _openMentionPicker(int atIndex) async {
    if (_mentionPickerOpen) return;
    _mentionPickerOpen = true;
    final picked = await Navigator.of(context).push<_ShamellRemindPickResult>(
      MaterialPageRoute(
        builder: (_) => _ShamellRemindPickerPage(
          baseUrl: widget.baseUrl,
          singlePick: true,
          initialSelectedIds: _remindIds,
          initialSelectedNames: _remindNames,
        ),
      ),
    );
    _mentionPickerOpen = false;
    if (picked == null || !mounted) return;

    _mergeRemindSelection(ids: picked.ids, names: picked.names);

    final names = picked.names.map((e) => e.trim()).where((e) => e.isNotEmpty);
    final mentionPieces = <String>[
      for (final name in names) '@$name',
    ];
    if (mentionPieces.isEmpty) return;
    final mentionText = '${mentionPieces.join(' ')} ';

    final currentText = _ctrl.text;
    int idx = atIndex;
    if (idx < 0 || idx > currentText.length) {
      idx = currentText.length;
    }
    if (idx < currentText.length && currentText[idx] != '@') {
      final cursor = _ctrl.selection.isValid ? _ctrl.selection.baseOffset : -1;
      final anchor = cursor >= 0 && cursor <= currentText.length
          ? cursor
          : currentText.length;
      final found = currentText.lastIndexOf('@', anchor - 1);
      if (found >= 0) {
        idx = found;
      } else {
        idx = currentText.length;
      }
    }

    final before =
        idx <= currentText.length ? currentText.substring(0, idx) : currentText;
    final after = (idx < currentText.length && currentText[idx] == '@')
        ? currentText.substring(idx + 1)
        : currentText.substring(idx);
    final nextText = '$before$mentionText$after';
    final caret =
        (before.length + mentionText.length).clamp(0, nextText.length);

    _suppressAtTrigger = true;
    _ctrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caret),
    );
    _lastText = nextText;
  }

  String _remindSummary(L10n l) {
    if (_remindNames.isEmpty) {
      return l.isArabic ? 'لا أحد' : 'None';
    }
    final sep = l.isArabic ? '، ' : ', ';
    if (_remindNames.length <= 2) {
      return _remindNames.join(sep);
    }
    return '${_remindNames.take(2).join(sep)}…';
  }

  String _mimeFromFilename(String filename) {
    final parts = filename.split('.');
    final ext = parts.isNotEmpty ? parts.last.toLowerCase() : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      if (_images.length >= _kMaxImages) return;
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) return;
      setState(() {
        if (_images.length >= _kMaxImages) return;
        _images.add(_ShamellComposerImage(
            bytes: bytes, mime: _mimeFromFilename(x.name)));
      });
    } catch (_) {}
  }

  Future<void> _pickFromAlbum() async {
    try {
      if (_images.length >= _kMaxImages) return;
      final picker = ImagePicker();
      final xs = await picker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (xs.isEmpty) return;
      final remaining =
          (_kMaxImages - _images.length).clamp(0, _kMaxImages).toInt();
      final loaded = <_ShamellComposerImage>[];
      for (final x in xs.take(remaining)) {
        try {
          final bytes = await x.readAsBytes();
          if (bytes.isEmpty) continue;
          loaded.add(_ShamellComposerImage(
              bytes: bytes, mime: _mimeFromFilename(x.name)));
        } catch (_) {}
      }
      if (!mounted) return;
      if (loaded.isEmpty) return;
      setState(() {
        _images.addAll(loaded);
      });
    } catch (_) {}
  }

  Future<void> _showImagePickerSheet() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetBg = isDark ? theme.colorScheme.surface : Colors.white;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        final l2 = L10n.of(ctx);
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(l2.isArabic ? 'التقاط صورة' : 'Take Photo'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(
                  l2.isArabic ? 'اختيار من الألبوم' : 'Choose from Album',
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickFromAlbum();
                },
              ),
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
  }

  String _visibilityLabel(L10n l) {
    switch (_visibilityScope) {
      case 'only_me':
        return l.isArabic ? 'أنا فقط' : 'Only me';
      case 'friends':
        return l.isArabic ? 'الأصدقاء فقط' : 'Friends';
      case 'public':
      default:
        return l.isArabic ? 'عام' : 'Public';
    }
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _ShamellLocationPickerPage(
          initialLabel: _locationLabel,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final next = picked.trim();
    setState(() => _locationLabel = next.isEmpty ? null : next);
  }

  Future<void> _pickRemind() async {
    final beforeIds = List<String>.from(_remindIds);
    final beforeNames = List<String>.from(_remindNames);
    final picked = await Navigator.of(context).push<_ShamellRemindPickResult>(
      MaterialPageRoute(
        builder: (_) => _ShamellRemindPickerPage(
          baseUrl: widget.baseUrl,
          singlePick: false,
          initialSelectedIds: _remindIds,
          initialSelectedNames: _remindNames,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final oldNameById = <String, String>{};
    for (var i = 0; i < beforeIds.length; i++) {
      final id = beforeIds[i].trim();
      if (id.isEmpty) continue;
      final name = i < beforeNames.length ? beforeNames[i].trim() : '';
      oldNameById[id] = name.isNotEmpty ? name : id;
    }

    final newIds = <String>[];
    final newNames = <String>[];
    final seen = <String>{};
    for (var i = 0; i < picked.ids.length; i++) {
      final id = picked.ids[i].trim();
      if (id.isEmpty) continue;
      if (!seen.add(id)) continue;
      final name = i < picked.names.length ? picked.names[i].trim() : '';
      newIds.add(id);
      newNames.add(name.isNotEmpty ? name : id);
    }

    final oldSet =
        beforeIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final newSet = newIds.toSet();

    final removed = <String>[];
    for (final id in oldSet.difference(newSet)) {
      removed.add(oldNameById[id] ?? id);
    }

    final added = <String>[];
    for (var i = 0; i < newIds.length; i++) {
      final id = newIds[i];
      if (!oldSet.contains(id)) {
        added.add(newNames[i]);
      }
    }

    var nextText = _ctrl.text;
    var caret = _ctrl.selection.isValid && _ctrl.selection.isCollapsed
        ? _ctrl.selection.baseOffset
        : nextText.length;
    caret = caret.clamp(0, nextText.length);

    for (final name in removed) {
      nextText = _removeMentionToken(nextText, name);
    }
    nextText = _cleanupComposerText(nextText);
    caret = caret.clamp(0, nextText.length);

    final insertion = _buildMentionsInsertion(
      text: nextText,
      at: caret,
      names: added,
    );
    if (insertion.isNotEmpty) {
      nextText =
          '${nextText.substring(0, caret)}$insertion${nextText.substring(caret)}';
      nextText = _cleanupComposerText(nextText);
      caret = (caret + insertion.length).clamp(0, nextText.length);
    }

    _suppressAtTrigger = true;
    _ctrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caret),
    );
    _lastText = nextText;

    setState(() {
      _remindIds = newIds;
      _remindNames = newNames;
    });
  }

  Future<void> _pickVisibility() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetBg = isDark ? theme.colorScheme.surface : Colors.white;

    String selected = _visibilityScope;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        final l2 = L10n.of(ctx);
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              Widget radioRow(String value, String label) {
                return RadioListTile<String>(
                  value: value,
                  dense: true,
                  title: Text(label),
                );
              }

              return RadioGroup<String>(
                groupValue: selected,
                onChanged: (v) {
                  if (v == null) return;
                  setModalState(() => selected = v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .20),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            l2.isArabic ? 'من يمكنه رؤيتها' : 'Who can see',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(l2.isArabic ? 'تم' : 'Done'),
                          ),
                        ],
                      ),
                    ),
                    radioRow('public', l2.isArabic ? 'عام' : 'Public'),
                    radioRow('friends', l2.isArabic ? 'الأصدقاء' : 'Friends'),
                    radioRow('only_me', l2.isArabic ? 'أنا فقط' : 'Only me'),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() => _visibilityScope = selected);
  }

  void _submit() {
    final draft = ShamellMomentDraft(
      text: _ctrl.text,
      imageBytes: _images.map((e) => e.bytes).toList(),
      imageMimes: _images.map((e) => e.mime).toList(),
      locationLabel: _locationLabel,
      visibilityScope: _visibilityScope,
      remindIds: List<String>.from(_remindIds),
      remindNames: List<String>.from(_remindNames),
    );
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final dividerColor = isDark ? theme.dividerColor : ShamellPalette.divider;

    final canPost = _canPost;

    String avatarInitial() {
      final name = _profileName.trim();
      if (name.isNotEmpty) return name.substring(0, 1).toUpperCase();
      final phone = _profilePhone.trim();
      if (phone.isNotEmpty) return phone.substring(phone.length - 1);
      return '?';
    }

    Widget avatarBox() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 46,
          height: 46,
          color:
              theme.colorScheme.onSurface.withValues(alpha: isDark ? .14 : .08),
          alignment: Alignment.center,
          child: Text(
            avatarInitial(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface.withValues(alpha: .85),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0.5,
        leadingWidth: 92,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
        ),
        title: Text(l.isArabic ? 'اللحظات' : 'Moments'),
        actions: [
          TextButton(
            onPressed: canPost ? _submit : null,
            child: Text(
              l.isArabic ? 'نشر' : 'Post',
              style: TextStyle(
                color: canPost
                    ? ShamellPalette.green
                    : theme.colorScheme.onSurface.withValues(alpha: .35),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatarBox(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _ctrl,
                          autofocus: true,
                          maxLines: 8,
                          minLines: 4,
                          decoration: InputDecoration(
                            hintText:
                                l.isArabic ? 'مشاركة شيء…' : 'Say something…',
                            border: InputBorder.none,
                          ),
                        ),
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (ctx, constraints) {
                            final maxWidth = constraints.maxWidth;
                            const spacing = 10.0;
                            final columns = maxWidth >= 520 ? 4 : 3;
                            final showAdd = _images.length < _kMaxImages;
                            final itemCount =
                                _images.length + (showAdd ? 1 : 0);

                            Widget removeBadge(int index) {
                              return Positioned(
                                right: 4,
                                top: 4,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () {
                                    setState(() {
                                      if (index >= 0 &&
                                          index < _images.length) {
                                        _images.removeAt(index);
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: .55),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            }

                            Widget imageTile(int index) {
                              final img = _images[index];
                              return InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () =>
                                    unawaited(_openImagePreview(index)),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.memory(
                                        img.bytes,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    removeBadge(index),
                                  ],
                                ),
                              );
                            }

                            Widget addTile() {
                              return InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: _showImagePickerSheet,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          dividerColor.withValues(alpha: .85),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.add,
                                    size: 28,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .55),
                                  ),
                                ),
                              );
                            }

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                                childAspectRatio: 1,
                              ),
                              itemCount: itemCount,
                              itemBuilder: (ctx, i) {
                                if (i >= _images.length) {
                                  return addTile();
                                }
                                return imageTile(i);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ShamellSection(
              dividerIndent: 16,
              children: [
                ListTile(
                  dense: true,
                  title: Text(l.isArabic ? 'الموقع' : 'Location'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (_locationLabel ?? '').trim().isNotEmpty
                            ? _locationLabel!
                            : (l.isArabic ? 'عدم العرض' : 'Not shown'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .60),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                        size: 18,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .40),
                      ),
                    ],
                  ),
                  onTap: _pickLocation,
                ),
                ListTile(
                  dense: true,
                  title: Text(l.isArabic ? 'تذكير' : 'Remind'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _remindSummary(l),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .60),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                        size: 18,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .40),
                      ),
                    ],
                  ),
                  onTap: _pickRemind,
                ),
                ListTile(
                  dense: true,
                  title: Text(l.isArabic ? 'من يمكنه رؤيتها' : 'Who can see'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _visibilityLabel(l),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .60),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                        size: 18,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .40),
                      ),
                    ],
                  ),
                  onTap: _pickVisibility,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShamellLocationEntry {
  final String label;
  final String? subtitle;
  const _ShamellLocationEntry({required this.label, this.subtitle});
}

class _ShamellLocationPickerPage extends StatefulWidget {
  final String? initialLabel;

  const _ShamellLocationPickerPage({this.initialLabel});

  @override
  State<_ShamellLocationPickerPage> createState() =>
      _ShamellLocationPickerPageState();
}

class _ShamellLocationPickerPageState
    extends State<_ShamellLocationPickerPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  String? _selectedLabel;

  bool _loadingCurrent = false;
  String? _currentError;
  _ShamellLocationEntry? _current;

  bool _loadingSearch = false;
  String? _searchError;
  List<_ShamellLocationEntry> _results = const <_ShamellLocationEntry>[];

  @override
  void initState() {
    super.initState();
    _selectedLabel = widget.initialLabel?.trim().isNotEmpty == true
        ? widget.initialLabel!.trim()
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCurrent();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _select(String? label) {
    Navigator.of(context).pop(label ?? '');
  }

  Map<String, String> _nominatimHeaders(L10n l) {
    return <String, String>{
      'accept': 'application/json',
      'user-agent': 'ShamellFlutter',
      'accept-language': l.isArabic ? 'ar' : 'en',
    };
  }

  _ShamellLocationEntry? _entryFromDisplay(String displayName) {
    final raw = displayName.trim();
    if (raw.isEmpty) return null;
    final parts = raw.split(',');
    final title = parts.isNotEmpty ? parts.first.trim() : raw;
    final subtitle = parts.length > 1
        ? parts
            .skip(1)
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .join(', ')
        : null;
    return _ShamellLocationEntry(
      label: title.isNotEmpty ? title : raw,
      subtitle: (subtitle ?? '').trim().isNotEmpty ? subtitle : null,
    );
  }

  Future<_ShamellLocationEntry?> _reverseGeocode({
    required double lat,
    required double lon,
    required L10n l,
  }) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      <String, String>{
        'lat': '$lat',
        'lon': '$lon',
        'format': 'jsonv2',
        'zoom': '18',
        'addressdetails': '1',
      },
    );
    final resp = await http.get(uri, headers: _nominatimHeaders(l)).timeout(
        _ShamellMomentsComposerPageState._momentsComposerRequestTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    final name = (decoded['name'] ?? '').toString().trim();
    if (name.isNotEmpty) {
      final display = (decoded['display_name'] ?? '').toString().trim();
      if (display.isNotEmpty) {
        final entry = _entryFromDisplay(display);
        if (entry != null && entry.label.trim().isNotEmpty) return entry;
      }
      return _ShamellLocationEntry(label: name);
    }
    final display = (decoded['display_name'] ?? '').toString().trim();
    return _entryFromDisplay(display);
  }

  Future<void> _loadCurrent() async {
    final l = L10n.of(context);
    setState(() {
      _loadingCurrent = true;
      _currentError = null;
      _current = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        setState(() {
          _loadingCurrent = false;
          _currentError =
              l.isArabic ? 'خدمات الموقع متوقفة' : 'Location services are off';
        });
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _loadingCurrent = false;
          _currentError =
              l.isArabic ? 'تم رفض إذن الموقع' : 'Location permission denied';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      final entry = await _reverseGeocode(
        lat: pos.latitude,
        lon: pos.longitude,
        l: l,
      );
      if (!mounted) return;
      setState(() {
        _loadingCurrent = false;
        _current = entry;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCurrent = false;
        _currentError = sanitizeExceptionForUi(
          error: e,
          isArabic: l.isArabic,
        );
      });
    }
  }

  Future<void> _search(String query) async {
    final l = L10n.of(context);
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _loadingSearch = false;
        _searchError = null;
        _results = const <_ShamellLocationEntry>[];
      });
      return;
    }

    setState(() {
      _loadingSearch = true;
      _searchError = null;
    });
    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        <String, String>{
          'q': q,
          'format': 'jsonv2',
          'addressdetails': '1',
          'limit': '20',
        },
      );
      final resp = await http.get(uri, headers: _nominatimHeaders(l)).timeout(
          _ShamellMomentsComposerPageState._momentsComposerRequestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _loadingSearch = false;
          _searchError = sanitizeHttpError(
            statusCode: resp.statusCode,
            rawBody: resp.body,
            isArabic: l.isArabic,
          );
          _results = const <_ShamellLocationEntry>[];
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) {
        if (!mounted) return;
        setState(() {
          _loadingSearch = false;
          _results = const <_ShamellLocationEntry>[];
        });
        return;
      }
      final entries = <_ShamellLocationEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final display = (e['display_name'] ?? '').toString().trim();
        final entry = _entryFromDisplay(display);
        if (entry == null) continue;
        final label = entry.label.trim();
        if (label.isEmpty) continue;
        entries.add(entry);
        if (entries.length >= 20) break;
      }
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
        _results = entries;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
        _searchError =
            l.isArabic ? 'تعذّر تنفيذ البحث.' : 'Could not run search.';
        _results = const <_ShamellLocationEntry>[];
      });
    }
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    final q = v;
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _search(q);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    final query = _searchCtrl.text.trim();
    final isSearching = query.isNotEmpty;

    final bodyChildren = <Widget>[];

    bodyChildren.add(const SizedBox(height: 8));
    bodyChildren.add(
      ShamellSearchBar(
        hintText: l.isArabic ? 'بحث' : 'Search',
        controller: _searchCtrl,
        readOnly: false,
        onChanged: _onQueryChanged,
      ),
    );
    bodyChildren.add(const SizedBox(height: 10));

    if (!isSearching) {
      bodyChildren.add(
        ShamellSection(
          margin: const EdgeInsets.only(top: 0),
          dividerIndent: 16,
          dividerEndIndent: 16,
          children: [
            ListTile(
              dense: true,
              title: Text(
                  l.isArabic ? 'عدم إظهار الموقع' : 'Do not show location'),
              trailing: _selectedLabel == null
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
              onTap: () => _select(null),
            ),
            if (_loadingCurrent)
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'جارٍ تحديد الموقع…' : 'Locating…'),
                trailing: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_current != null)
              ListTile(
                dense: true,
                title: Text(
                  _current!.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: (_current!.subtitle ?? '').trim().isNotEmpty
                    ? Text(
                        _current!.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
                        ),
                      )
                    : null,
                trailing: _selectedLabel == _current!.label
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () => _select(_current!.label),
              )
            else if ((_currentError ?? '').trim().isNotEmpty)
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'تعذّر تحديد الموقع' : 'Unable to get location',
                ),
                subtitle: Text(
                  _currentError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                trailing: TextButton(
                  onPressed: _loadCurrent,
                  child: Text(l.isArabic ? 'إعادة المحاولة' : 'Retry'),
                ),
              )
            else
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'تحديد الموقع' : 'Get location'),
                trailing: TextButton(
                  onPressed: _loadCurrent,
                  child: Text(l.isArabic ? 'تشغيل' : 'Enable'),
                ),
              ),
          ],
        ),
      );
      bodyChildren.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            l.isArabic
                ? 'استخدم البحث لاختيار مكان.'
                : 'Search to choose a place.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: .55),
            ),
          ),
        ),
      );
    } else {
      if (_loadingSearch) {
        bodyChildren.add(
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      } else if ((_searchError ?? '').trim().isNotEmpty) {
        bodyChildren.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Text(
              _searchError!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.error,
              ),
            ),
          ),
        );
      } else if (_results.isEmpty) {
        bodyChildren.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Text(
              l.isArabic ? 'لا توجد نتائج.' : 'No results.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: .55),
              ),
            ),
          ),
        );
      } else {
        bodyChildren.add(
          ShamellSection(
            margin: const EdgeInsets.only(top: 0),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              for (final e in _results)
                ListTile(
                  dense: true,
                  title: Text(
                    e.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: (e.subtitle ?? '').trim().isNotEmpty
                      ? Text(
                          e.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .55),
                          ),
                        )
                      : null,
                  trailing: _selectedLabel == e.label
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => _select(e.label),
                ),
            ],
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الموقع' : 'Location'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: bodyChildren,
      ),
    );
  }
}

class _ShamellRemindPickResult {
  final List<String> ids;
  final List<String> names;
  const _ShamellRemindPickResult({
    required this.ids,
    required this.names,
  });
}

class _ShamellRemindHeader {
  final String letter;
  const _ShamellRemindHeader(this.letter);
}

class _ShamellRemindEntry {
  final String id;
  final String displayName;
  final String? subtitle;
  final String letter;
  const _ShamellRemindEntry({
    required this.id,
    required this.displayName,
    required this.letter,
    this.subtitle,
  });
}

class _ShamellRemindPickerPage extends StatefulWidget {
  final String baseUrl;
  final bool singlePick;
  final List<String> initialSelectedIds;
  final List<String> initialSelectedNames;

  const _ShamellRemindPickerPage({
    required this.baseUrl,
    this.singlePick = false,
    this.initialSelectedIds = const <String>[],
    this.initialSelectedNames = const <String>[],
  });

  @override
  State<_ShamellRemindPickerPage> createState() =>
      _ShamellRemindPickerPageState();
}

class _ShamellRemindPickerPageState extends State<_ShamellRemindPickerPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _letterKeys = <String, GlobalKey>{};

  bool _loadingFriends = true;
  String? _friendsError;
  List<_ShamellRemindEntry> _friends = const <_ShamellRemindEntry>[];

  final List<String> _selectedOrder = <String>[];
  final Set<String> _selectedIds = <String>{};
  final Map<String, String> _nameById = <String, String>{};

  @override
  void initState() {
    super.initState();
    for (final id in widget.initialSelectedIds) {
      final clean = id.trim();
      if (clean.isEmpty) continue;
      if (_selectedIds.add(clean)) _selectedOrder.add(clean);
    }
    for (var i = 0; i < widget.initialSelectedIds.length; i++) {
      final id = widget.initialSelectedIds[i].trim();
      if (id.isEmpty) continue;
      if (i < widget.initialSelectedNames.length) {
        final name = widget.initialSelectedNames[i].trim();
        if (name.isNotEmpty) _nameById[id] = name;
      }
    }
    _loadFriends();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{};
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) {
        headers['cookie'] = cookie;
      }
    } catch (_) {}
    return headers;
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

  String _letterFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '#';
    final first = trimmed[0].toUpperCase();
    final code = first.codeUnitAt(0);
    if (code < 65 || code > 90) return '#';
    return first;
  }

  String _friendChatId(Map<String, dynamic> f) {
    final deviceId = (f['device_id'] ?? '').toString().trim();
    if (deviceId.isNotEmpty) return deviceId;
    final id = (f['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    return '';
  }

  Future<void> _loadFriends() async {
    final l = L10n.of(context);
    setState(() {
      _loadingFriends = true;
      _friendsError = null;
    });
    try {
      Map<String, String> aliases = const <String, String>{};
      try {
        final sp = await SharedPreferences.getInstance();
        aliases = _decodeStringMap(sp.getString('friends.aliases') ?? '{}');
      } catch (_) {}

      final uri = Uri.parse('${widget.baseUrl}/me/friends');
      final resp = await http.get(uri, headers: await _authHeaders()).timeout(
          _ShamellMomentsComposerPageState._momentsComposerRequestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _loadingFriends = false;
          _friendsError = sanitizeHttpError(
            statusCode: resp.statusCode,
            rawBody: resp.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
      final raw = (decoded is Map ? decoded['friends'] : decoded) as Object?;
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(e.cast<String, dynamic>());
        }
      }
      final entries = <_ShamellRemindEntry>[];
      for (final f in list) {
        final id = _friendChatId(f);
        if (id.isEmpty) continue;
        final nameRaw = (f['name'] ?? f['id'] ?? id).toString().trim();
        final alias = aliases[id]?.trim();
        final display = (alias != null && alias.isNotEmpty)
            ? alias
            : (nameRaw.isNotEmpty ? nameRaw : id);
        final subtitle = display != id ? id : null;
        final letter = _letterFor(display);
        entries.add(
          _ShamellRemindEntry(
            id: id,
            displayName: display,
            letter: letter,
            subtitle: subtitle,
          ),
        );
        _nameById[id] = display;
      }
      entries.sort((a, b) {
        if (a.letter != b.letter) {
          if (a.letter == '#') return 1;
          if (b.letter == '#') return -1;
          return a.letter.compareTo(b.letter);
        }
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _friends = entries;
        _loadingFriends = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _friendsError =
            l.isArabic ? 'تعذّر تحميل الأصدقاء.' : 'Could not load friends.';
        _loadingFriends = false;
      });
    }
  }

  void _toggleSelected(String id) {
    final clean = id.trim();
    if (clean.isEmpty) return;
    setState(() {
      if (_selectedIds.contains(clean)) {
        _selectedIds.remove(clean);
        _selectedOrder.removeWhere((e) => e == clean);
      } else {
        _selectedIds.add(clean);
        _selectedOrder.add(clean);
      }
    });
  }

  void _scrollToLetter(String letter) {
    final key = _letterKeys[letter];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    // ignore: discarded_futures
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final surface = theme.colorScheme.surface;

    final sourceEntries = _friends;
    final loading = _loadingFriends;
    final error = _friendsError;

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? sourceEntries
        : sourceEntries.where((e) {
            final hay =
                '${e.displayName.toLowerCase()} ${(e.subtitle ?? '').toLowerCase()}';
            return hay.contains(query);
          }).toList();

    final items = <Object>[];
    _letterKeys.clear();
    String? currentLetter;
    for (final e in filtered) {
      if (currentLetter != e.letter) {
        currentLetter = e.letter;
        items.add(_ShamellRemindHeader(currentLetter));
      }
      items.add(e);
    }

    final letters = <String>[];
    for (final item in items) {
      if (item is _ShamellRemindHeader) {
        letters.add(item.letter);
      }
    }

    final selectedCount = _selectedIds.length;
    final doneLabel = selectedCount > 0
        ? (isArabic ? 'تم ($selectedCount)' : 'Done ($selectedCount)')
        : (isArabic ? 'تم' : 'Done');

    Widget avatar(String name) {
      final trimmed = name.trim();
      final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
      return SizedBox(
        width: 40,
        height: 40,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            color:
                theme.colorScheme.primary.withValues(alpha: isDark ? .30 : .15),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    Widget content() {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        );
      }
      if (items.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              isArabic ? 'لا توجد نتائج.' : 'No matches.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
              ),
            ),
          ),
        );
      }

      return Stack(
        children: [
          ListView.builder(
            controller: _scrollCtrl,
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              if (item is _ShamellRemindHeader) {
                final key =
                    _letterKeys.putIfAbsent(item.letter, () => GlobalKey());
                return Container(
                  key: key,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  color: bgColor,
                  child: Text(
                    item.letter,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: .55),
                    ),
                  ),
                );
              }
              final e = item as _ShamellRemindEntry;
              final selected = _selectedIds.contains(e.id);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: surface,
                    child: ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading: avatar(e.displayName),
                      title: Text(
                        e.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: (e.subtitle ?? '').trim().isNotEmpty
                          ? Text(
                              e.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      trailing: widget.singlePick
                          ? null
                          : Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 22,
                              color: selected
                                  ? ShamellPalette.green
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: .25),
                            ),
                      onTap: () {
                        if (widget.singlePick) {
                          Navigator.of(context).pop(
                            _ShamellRemindPickResult(
                              ids: <String>[e.id],
                              names: <String>[e.displayName],
                            ),
                          );
                          return;
                        }
                        _toggleSelected(e.id);
                      },
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
          if (query.isEmpty && letters.length > 1)
            PositionedDirectional(
              end: 6,
              top: 8,
              bottom: 8,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final itemHeight = constraints.maxHeight / letters.length;
                  void jump(double dy) {
                    final idx =
                        (dy / itemHeight).floor().clamp(0, letters.length - 1);
                    _scrollToLetter(letters[idx]);
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => jump(d.localPosition.dy),
                    onVerticalDragUpdate: (d) => jump(d.localPosition.dy),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final letter in letters)
                          SizedBox(
                            height: itemHeight,
                            child: Center(
                              child: Text(
                                letter,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .45),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0.5,
        leadingWidth: 92,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isArabic ? 'إلغاء' : 'Cancel'),
        ),
        title: Text(isArabic ? 'تذكير' : 'Remind'),
        actions: widget.singlePick
            ? null
            : [
                TextButton(
                  onPressed: () {
                    final ids = List<String>.from(_selectedOrder);
                    final names = ids
                        .map((id) => (_nameById[id] ?? id).trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    Navigator.of(context).pop(
                      _ShamellRemindPickResult(ids: ids, names: names),
                    );
                  },
                  child: Text(
                    doneLabel,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            ShamellSearchBar(
              hintText: isArabic ? 'بحث' : 'Search',
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  isArabic ? 'الأصدقاء' : 'Friends',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ),
            ),
            if (!widget.singlePick && selectedCount > 0) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  reverse: isArabic,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _selectedOrder.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final id = _selectedOrder[i];
                    final name = (_nameById[id] ?? id).trim();
                    final initial =
                        name.isNotEmpty ? name[0].toUpperCase() : '?';
                    final chipBg = isDark
                        ? theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: .55,
                          )
                        : ShamellPalette.searchFill;
                    final fg =
                        theme.colorScheme.onSurface.withValues(alpha: .85);
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _toggleSelected(id),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: isDark ? .30 : .15,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.close,
                              size: 16,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .45),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(child: content()),
          ],
        ),
      ),
    );
  }
}
