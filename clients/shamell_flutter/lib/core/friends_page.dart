import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'http_error.dart';
import 'l10n.dart';
import 'shamell_ui.dart';

Future<Map<String, String>> _hdrFriends({
  required String baseUrl,
  bool json = false,
}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  try {
    final cookie = await getSessionCookieHeader(baseUrl);
    if (cookie != null && cookie.isNotEmpty) h['cookie'] = cookie;
  } catch (_) {}
  return h;
}

enum FriendsPageMode {
  picker,
  manage,
  newFriends,
}

class FriendsPage extends StatefulWidget {
  final String baseUrl;
  final FriendsPageMode mode;
  final String? initialAddText;
  const FriendsPage(
    this.baseUrl, {
    super.key,
    this.mode = FriendsPageMode.picker,
    this.initialAddText,
  });

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _outgoing = [];

  final TextEditingController _filterCtrl = TextEditingController();
  final TextEditingController _addCtrl = TextEditingController();
  final ScrollController _friendsScrollCtrl = ScrollController();
  final Map<String, GlobalKey> _letterKeys = <String, GlobalKey>{};

  String _requestOut = '';
  bool _busy = false;
  Map<String, String> _aliases = <String, String>{};
  Map<String, String> _tags = <String, String>{};

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialAddText ?? '').trim();
    if (initial.isNotEmpty) {
      _addCtrl.text = initial;
    }
    _load();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _addCtrl.dispose();
    _friendsScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      await _loadFriends();
      await _loadAliases();
      await _loadTags();
      if (widget.mode == FriendsPageMode.newFriends) {
        await _loadRequests();
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _loadFriends() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/friends');
      final r = await http.get(
        uri,
        headers: await _hdrFriends(baseUrl: widget.baseUrl),
      );
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        final arr = (j is Map ? j['friends'] : j) as Object?;
        if (arr is List) {
          _friends = arr
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        }
      }
    } catch (_) {}
  }

  Future<void> _loadRequests() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/friend_requests');
      final r = await http.get(
        uri,
        headers: await _hdrFriends(baseUrl: widget.baseUrl),
      );
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        if (j is Map<String, dynamic>) {
          final inc = j['incoming'];
          final out = j['outgoing'];
          _incoming = (inc is List)
              ? inc
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList()
              : [];
          _outgoing = (out is List)
              ? out
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList()
              : [];
        }
      }
    } catch (_) {}
  }

  Future<void> _loadAliases() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('friends.aliases') ?? '{}';
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = <String, String>{};
        decoded.forEach((k, v) {
          final key = (k ?? '').toString();
          final val = (v ?? '').toString();
          if (key.isNotEmpty && val.isNotEmpty) {
            map[key] = val;
          }
        });
        if (!mounted) return;
        setState(() {
          _aliases = map;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveAliases() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('friends.aliases', jsonEncode(_aliases));
    } catch (_) {}
  }

  Future<void> _loadTags() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('friends.tags') ?? '{}';
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = <String, String>{};
        decoded.forEach((k, v) {
          final key = (k ?? '').toString();
          final val = (v ?? '').toString();
          if (key.isNotEmpty && val.isNotEmpty) {
            map[key] = val;
          }
        });
        if (!mounted) return;
        setState(() {
          _tags = map;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveTags() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('friends.tags', jsonEncode(_tags));
    } catch (_) {}
  }

  Future<void> _sendRequest() async {
    final target = _addCtrl.text.trim();
    if (target.isEmpty) return;
    if (_looksLikePhoneIdentifier(target)) {
      if (!mounted) return;
      setState(() {
        _requestOut = L10n.of(context).isArabic
            ? 'إضافة الأصدقاء عبر رقم الهاتف غير مدعومة. استخدم Shamell ID أو رمز QR.'
            : 'Adding friends by phone number is not supported. Use Shamell ID or QR.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _requestOut = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/friends/request');
      final r = await http.post(
        uri,
        headers: await _hdrFriends(baseUrl: widget.baseUrl, json: true),
        body: jsonEncode({'target_id': target}),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _addCtrl.clear();
        await _loadRequests();
        if (mounted) {
          setState(() {
            _requestOut = '';
          });
        }
      } else {
        setState(() {
          _requestOut = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } catch (e) {
      setState(() {
        _requestOut = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    setState(() {
      _busy = true;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/friends/accept');
      final r = await http.post(
        uri,
        headers: await _hdrFriends(baseUrl: widget.baseUrl, json: true),
        body: jsonEncode({'request_id': requestId}),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _loadFriends();
        await _loadRequests();
      } else {
        setState(() {
          _requestOut = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } catch (e) {
      setState(() {
        _requestOut = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setCloseFriend(
      Map<String, dynamic> friend, bool isClose) async {
    final chatId = _friendChatId(friend);
    if (chatId.isEmpty) return;
    setState(() {
      friend['close'] = isClose;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      final rawClose = sp.getString('friends.close') ?? '{}';
      Map<String, dynamic> decodedClose;
      try {
        decodedClose = jsonDecode(rawClose) as Map<String, dynamic>;
      } catch (_) {
        decodedClose = <String, dynamic>{};
      }
      if (isClose) {
        decodedClose[chatId] = true;
      } else {
        decodedClose.remove(chatId);
      }
      await sp.setString('friends.close', jsonEncode(decodedClose));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        friend['close'] = !isClose;
      });
    }
  }

  bool _looksLikePhoneIdentifier(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    if (RegExp(r'[A-Za-z]').hasMatch(s)) return false;
    final normalized = s.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) return false;
    return RegExp(r'^\+?[0-9]{7,20}$').hasMatch(normalized);
  }

  String _friendChatId(Map<String, dynamic> f) {
    try {
      final deviceId = (f['device_id'] ?? '').toString();
      if (deviceId.isNotEmpty) return deviceId;
    } catch (_) {}
    try {
      final id = (f['id'] ?? '').toString();
      if (id.isNotEmpty) return id;
    } catch (_) {}
    return '';
  }

  Future<void> _editAliasForFriend(Map<String, dynamic> f) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final chatId = _friendChatId(f);
    if (chatId.isEmpty) return;
    final name = (f['name'] ?? f['id'] ?? '').toString();
    final id = (f['id'] ?? '').toString();
    final currentAlias = _aliases[chatId] ?? '';
    final currentTags = _tags[chatId] ?? '';
    final ctrl = TextEditingController(text: currentAlias);
    final tagsCtrl = TextEditingController(text: currentTags);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        final isDark = theme.brightness == Brightness.dark;
        final sheetBg = isDark ? theme.colorScheme.surface : Colors.white;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 12,
            bottom: bottom + 12,
          ),
          child: Material(
            color: sheetBg,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.shamellFriendAliasTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name.isNotEmpty ? name : id,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      labelText: l.shamellFriendAliasLabel,
                      hintText: l.shamellFriendAliasHint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tagsCtrl,
                    decoration: InputDecoration(
                      labelText: l.shamellFriendTagsLabel,
                      hintText: l.shamellFriendTagsHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(l.shamellDialogCancel),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          final alias = ctrl.text.trim();
                          setState(() {
                            if (alias.isEmpty) {
                              _aliases.remove(chatId);
                            } else {
                              _aliases[chatId] = alias;
                            }
                          });
                          final tagsText = tagsCtrl.text.trim();
                          setState(() {
                            if (tagsText.isEmpty) {
                              _tags.remove(chatId);
                            } else {
                              _tags[chatId] = tagsText;
                            }
                          });
                          // ignore: discarded_futures
                          _saveAliases();
                          // ignore: discarded_futures
                          _saveTags();
                          if (mounted) Navigator.of(ctx).pop();
                        },
                        child: Text(
                          l.settingsSave,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    tagsCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final dividerColor = isDark ? theme.dividerColor : ShamellPalette.divider;

    String title;
    switch (widget.mode) {
      case FriendsPageMode.newFriends:
        title = l.shamellContactsNewFriends;
        break;
      case FriendsPageMode.manage:
        title = l.shamellFriendsListTitle;
        break;
      case FriendsPageMode.picker:
        title = l.shamellTabContacts;
        break;
    }

    Widget avatar(String display) {
      final initial =
          display.trim().isNotEmpty ? display.trim()[0].toUpperCase() : '?';
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

    String displayFor(Map<String, dynamic> f) {
      final chatIdKey = _friendChatId(f);
      final name = (f['name'] ?? f['id'] ?? '').toString();
      final id = (f['id'] ?? '').toString();
      final alias = _aliases[chatIdKey]?.trim();
      return (alias != null && alias.isNotEmpty)
          ? alias
          : (name.isEmpty ? id : name);
    }

    String letterForDisplay(String display) {
      if (display.trim().isEmpty) return '#';
      final first = display.trim()[0].toUpperCase();
      final code = first.codeUnitAt(0);
      if (code < 65 || code > 90) return '#';
      return first;
    }

    Widget friendRow(
      Map<String, dynamic> f, {
      required bool selectable,
      required bool showCloseToggle,
    }) {
      final chatId = _friendChatId(f);
      final display = displayFor(f);
      final chatIdKey = _friendChatId(f);
      final name = (f['name'] ?? f['id'] ?? '').toString();
      final id = (f['id'] ?? '').toString();
      final alias = _aliases[chatIdKey]?.trim();
      final tagsText = _tags[chatIdKey]?.trim();
      final isClose = (f['close'] as bool?) ?? false;

      final titleStyle = theme.textTheme.bodyMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ) ??
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w500);

      final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: .60),
          ) ??
          TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: .60),
          );

      return Container(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: avatar(display),
          title: Text(
            display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
          subtitle: (alias != null && alias.isNotEmpty) ||
                  (tagsText != null && tagsText.isNotEmpty) ||
                  isClose
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isClose)
                      Text(
                        l.shamellFriendsCloseLabel,
                        style: subtitleStyle,
                      ),
                    if (alias != null && alias.isNotEmpty)
                      Text(
                        l.isArabic
                            ? 'الاسم الأصلي: ${name.isEmpty ? id : name}'
                            : 'Original: ${name.isEmpty ? id : name}',
                        style: subtitleStyle.copyWith(fontSize: 11),
                      ),
                    if (tagsText != null && tagsText.isNotEmpty)
                      Text(
                        '${l.shamellFriendTagsPrefix} $tagsText',
                        style: subtitleStyle.copyWith(fontSize: 11),
                      ),
                  ],
                )
              : null,
          trailing: showCloseToggle
              ? IconButton(
                  tooltip: isClose
                      ? (l.isArabic
                          ? 'إزالة من الأصدقاء المقرّبين'
                          : 'Remove from close friends')
                      : (l.isArabic
                          ? 'إضافة إلى الأصدقاء المقرّبين'
                          : 'Add to close friends'),
                  icon: Icon(
                    isClose ? Icons.star : Icons.star_border,
                    size: 20,
                    color: isClose
                        ? ShamellPalette.green
                        : theme.colorScheme.onSurface.withValues(alpha: .35),
                  ),
                  onPressed: _busy ? null : () => _setCloseFriend(f, !isClose),
                )
              : null,
          onTap: selectable
              ? () {
                  if (chatId.isEmpty) return;
                  Navigator.of(context).pop(chatId);
                }
              : () {
                  // ignore: discarded_futures
                  _editAliasForFriend(f);
                },
          onLongPress: () {
            // ignore: discarded_futures
            _editAliasForFriend(f);
          },
        ),
      );
    }

    Widget requestRow(
      Map<String, dynamic> r, {
      required bool incoming,
    }) {
      final name = (r['name'] ?? r['from'] ?? r['to'] ?? '').toString();
      final id = (r['id'] ?? '').toString();
      final reqId = (r['request_id'] ?? id).toString();
      final display = name.isNotEmpty ? name : reqId;

      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: ShamellLeadingIcon(
          icon:
              incoming ? Icons.person_add_alt_1_outlined : Icons.outgoing_mail,
          background:
              incoming ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
        ),
        title: Text(
          display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: name.isNotEmpty && reqId.isNotEmpty
            ? Text(
                reqId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: .60),
                ),
              )
            : null,
        trailing: incoming
            ? OutlinedButton(
                onPressed: _busy ? null : () => _acceptRequest(reqId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ShamellPalette.green,
                  side: const BorderSide(color: ShamellPalette.green),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: Text(l.shamellFriendsAccept),
              )
            : null,
      );
    }

    Widget friendsListBody({
      required bool selectable,
      required bool showCloseToggle,
    }) {
      final query = _filterCtrl.text.trim().toLowerCase();
      final all = List<Map<String, dynamic>>.from(_friends);

      String keyFor(Map<String, dynamic> f) => displayFor(f).toLowerCase();

      all.sort((a, b) => keyFor(a).compareTo(keyFor(b)));

      final filtered = query.isEmpty
          ? all
          : all.where((f) {
              final display = displayFor(f).toLowerCase();
              final chatId = _friendChatId(f).toLowerCase();
              final tags = (_tags[_friendChatId(f)] ?? '').toLowerCase();
              return display.contains(query) ||
                  chatId.contains(query) ||
                  tags.contains(query);
            }).toList();

      final canIndex = query.isEmpty;
      _letterKeys.clear();

      final tiles = <Widget>[];
      tiles.add(const SizedBox(height: 10));
      tiles.add(
        ShamellSearchBar(
          hintText: l.labelSearch,
          controller: _filterCtrl,
          onChanged: (_) => setState(() {}),
        ),
      );
      tiles.add(const SizedBox(height: 10));

      if (filtered.isEmpty) {
        tiles.add(
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l.shamellFriendsEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
          ),
        );
      } else {
        final close = showCloseToggle
            ? filtered.where((f) => (f['close'] as bool?) ?? false).toList()
            : const <Map<String, dynamic>>[];
        final normal = showCloseToggle
            ? filtered.where((f) => !((f['close'] as bool?) ?? false)).toList()
            : filtered;

        if (close.isNotEmpty) {
          tiles.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                l.shamellFriendsCloseLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
                ),
              ),
            ),
          );
          tiles.add(
            ShamellSection(
              margin: EdgeInsets.zero,
              backgroundColor:
                  isDark ? theme.colorScheme.surface : Colors.white,
              children: [
                for (var i = 0; i < close.length; i++)
                  friendRow(
                    close[i],
                    selectable: selectable,
                    showCloseToggle: showCloseToggle,
                  ),
              ],
            ),
          );
          tiles.add(const SizedBox(height: 10));
        }

        if (normal.isNotEmpty) {
          String currentLetter = '';
          for (final f in normal) {
            final display = displayFor(f);
            final letter = letterForDisplay(display);
            if (canIndex && letter != currentLetter) {
              currentLetter = letter;
              final key = GlobalKey();
              _letterKeys[letter] = key;
              tiles.add(
                Container(
                  key: key,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  color: bgColor,
                  child: Text(
                    letter,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: .60),
                    ),
                  ),
                ),
              );
            }

            tiles.add(
              friendRow(
                f,
                selectable: selectable,
                showCloseToggle: showCloseToggle,
              ),
            );
            tiles.add(
              Divider(
                height: 1,
                thickness: 0.5,
                indent: 72,
                color: dividerColor,
              ),
            );
          }
        }
      }

      final list = ListView(
        controller: _friendsScrollCtrl,
        padding: EdgeInsets.zero,
        children: tiles,
      );

      if (!canIndex || _letterKeys.isEmpty) return list;

      const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#';
      return Stack(
        children: [
          list,
          Positioned(
            right: 2,
            top: 88,
            bottom: 40,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: letters.split('').map((letter) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final key = _letterKeys[letter];
                    if (key == null) return;
                    final ctx = key.currentContext;
                    if (ctx == null) return;
                    Scrollable.ensureVisible(
                      ctx,
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      letter,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .55),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    Widget newFriendsBody() {
      Widget header(String text) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .65),
            ),
          ),
        );
      }

      final addFill =
          isDark ? ShamellPalette.searchFillDark : ShamellPalette.searchFill;

      return ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: addFill,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextField(
                      controller: _addCtrl,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
                        ),
                        hintText: l.shamellFriendsSearchHint,
                      ),
                      onSubmitted: (_) {
                        if (_busy) return;
                        // ignore: discarded_futures
                        _sendRequest();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _addCtrl,
                  builder: (ctx, value, _) {
                    final canSend = value.text.trim().isNotEmpty && !_busy;
                    return TextButton(
                      onPressed: canSend ? _sendRequest : null,
                      style: TextButton.styleFrom(
                        backgroundColor:
                            canSend ? ShamellPalette.green : Colors.transparent,
                        foregroundColor: canSend
                            ? Colors.white
                            : theme.colorScheme.onSurface
                                .withValues(alpha: .45),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        l.isArabic ? 'إضافة' : 'Add',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_requestOut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _requestOut,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ),
          header(l.isArabic ? 'الخصوصية' : 'Privacy'),
          ShamellSection(
            margin: EdgeInsets.zero,
            backgroundColor: isDark ? theme.colorScheme.surface : Colors.white,
            children: [
              ListTile(
                dense: true,
                leading: const ShamellLeadingIcon(
                  icon: Icons.privacy_tip_outlined,
                  background: Color(0xFF94A3B8),
                ),
                title: Text(
                  l.isArabic
                      ? 'لا نستخدم رقم الهاتف لاكتشاف جهات الاتصال.'
                      : 'Phone numbers are not used for contact discovery.',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'أضف الأصدقاء عبر Shamell ID أو رمز QR.'
                      : 'Add friends via Shamell ID or QR.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
              ),
            ],
          ),
          if (_incoming.isNotEmpty || _outgoing.isNotEmpty) ...[
            header(l.shamellFriendsRequestsTitle),
            ShamellSection(
              margin: EdgeInsets.zero,
              backgroundColor:
                  isDark ? theme.colorScheme.surface : Colors.white,
              children: [
                for (final r in _incoming) requestRow(r, incoming: true),
                for (final r in _outgoing) requestRow(r, incoming: false),
              ],
            ),
          ],
          const SizedBox(height: 20),
        ],
      );
    }

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (widget.mode == FriendsPageMode.newFriends) {
      body = newFriendsBody();
    } else if (widget.mode == FriendsPageMode.manage) {
      body = friendsListBody(selectable: false, showCloseToggle: true);
    } else {
      body = friendsListBody(selectable: true, showCloseToggle: false);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          if (widget.mode == FriendsPageMode.manage)
            IconButton(
              tooltip: l.isArabic ? 'إضافة صديق' : 'Add friend',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendsPage(
                      widget.baseUrl,
                      mode: FriendsPageMode.newFriends,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: body,
    );
  }
}
