import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'people_nearby_page.dart';
import 'wechat_ui.dart';

Future<Map<String, String>> _hdrFriends({bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  try {
    final sp = await SharedPreferences.getInstance();
    final cookie = sp.getString('sa_cookie');
    if (cookie != null && cookie.isNotEmpty) {
      h['sa_cookie'] = cookie;
    }
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
  bool _contactsLoading = false;
  List<Map<String, String>> _contactSuggestions = <Map<String, String>>[];
  Map<String, String> _tags = <String, String>{};
  int _contactMatches = 0;

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
        await _loadContactSuggestions();
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
      final r = await http.get(uri, headers: await _hdrFriends());
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
      final r = await http.get(uri, headers: await _hdrFriends());
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

    // Best-effort sync to backend for each friend/tag set so Moments can use
    // labels as audience filters, and persist a mapping so chat can show
    // WeChat-style contact details.
    try {
      final sp = await SharedPreferences.getInstance();
      final chatIdToPhone = <String, String>{};
      final closeMap = <String, bool>{};
      for (final f in _friends) {
        final chatId = _friendChatId(f);
        if (chatId.isEmpty) continue;
        final phone = (f['phone'] ?? f['id'] ?? '').toString().trim();
        if (phone.isEmpty) continue;
        chatIdToPhone[chatId] = phone;
        final isClose = (f['close'] as bool?) ?? false;
        if (isClose) {
          closeMap[chatId] = true;
        }
      }
      await sp.setString('friends.chat_to_phone', jsonEncode(chatIdToPhone));
      await sp.setString('friends.close', jsonEncode(closeMap));
      for (final entry in _tags.entries) {
        final chatId = entry.key;
        final tagsText = entry.value.trim();
        if (tagsText.isEmpty) continue;
        final phone = (chatIdToPhone[chatId] ?? '').trim();
        if (phone.isEmpty) continue;
        final tags = tagsText
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (tags.isEmpty) continue;
        try {
          final uri = Uri.parse('${widget.baseUrl}/me/friends/$phone/tags');
          await http.post(
            uri,
            headers: await _hdrFriends(json: true),
            body: jsonEncode({'tags': tags}),
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _loadContactSuggestions() async {
    setState(() {
      _contactsLoading = true;
    });
    try {
      if (!await FlutterContacts.requestPermission()) {
        if (!mounted) return;
        setState(() {
          _contactsLoading = false;
          _contactSuggestions = const <Map<String, String>>[];
        });
        return;
      }
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final existing = <String>{};
      for (final f in _friends) {
        final p = (f['phone'] ?? f['id'] ?? '').toString().replaceAll(' ', '');
        if (p.isNotEmpty) existing.add(p);
      }
      final sugg = <Map<String, String>>[];
      final phones = <String>[];
      for (final c in contacts) {
        if (c.phones.isEmpty) continue;
        final phone = c.phones.first.number.replaceAll(' ', '');
        if (phone.isEmpty) continue;
        if (existing.contains(phone)) continue;
        sugg.add({'name': c.displayName, 'phone': phone});
        phones.add(phone);
        if (sugg.length >= 16) break;
      }

      // Ask backend which of these contacts are active Shamell users.
      final matchedPhones = <String>{};
      if (phones.isNotEmpty) {
        try {
          final uri = Uri.parse('${widget.baseUrl}/me/contacts/sync');
          final resp = await http.post(
            uri,
            headers: await _hdrFriends(json: true),
            body: jsonEncode({'phones': phones}),
          );
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final decoded = jsonDecode(resp.body);
            List<dynamic>? arr;
            if (decoded is Map && decoded['matches'] is List) {
              arr = decoded['matches'] as List;
            } else if (decoded is List) {
              arr = decoded;
            }
            if (arr != null) {
              for (final e in arr) {
                if (e is! Map) continue;
                final m = e.cast<String, dynamic>();
                final p = (m['phone'] ?? '').toString().replaceAll(' ', '');
                if (p.isEmpty) continue;
                matchedPhones.add(p);
              }
            }
          }
        } catch (_) {}
      }

      // Prefer showing only contacts that are known Shamell users; if none
      // match, fall back to local suggestions.
      List<Map<String, String>> finalSugg = sugg;
      if (matchedPhones.isNotEmpty) {
        finalSugg = sugg
            .where((c) => matchedPhones.contains((c['phone'] ?? '').toString()))
            .toList();
      }
      if (finalSugg.length > 8) {
        finalSugg = finalSugg.sublist(0, 8);
      }
      if (!mounted) return;
      setState(() {
        _contactSuggestions = finalSugg;
        _contactMatches =
            matchedPhones.isNotEmpty ? matchedPhones.length : finalSugg.length;
        _contactsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contactsLoading = false;
        _contactSuggestions = const <Map<String, String>>[];
        _contactMatches = 0;
      });
    }
  }

  Future<void> _sendRequest() async {
    final target = _addCtrl.text.trim();
    if (target.isEmpty) return;
    setState(() {
      _busy = true;
      _requestOut = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/friends/request');
      final r = await http.post(
        uri,
        headers: await _hdrFriends(json: true),
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
          _requestOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _requestOut = 'error: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendRequestToPhone(String phone) async {
    final target = phone.trim();
    if (target.isEmpty) return;
    setState(() {
      _busy = true;
      _requestOut = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/friends/request');
      final r = await http.post(
        uri,
        headers: await _hdrFriends(json: true),
        body: jsonEncode({'target_id': target}),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _loadFriends();
        await _loadRequests();
        if (mounted) {
          setState(() {
            _contactSuggestions = _contactSuggestions
                .where((c) => (c['phone'] ?? '') != target)
                .toList();
          });
        }
      } else {
        setState(() {
          _requestOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _requestOut = 'error: $e';
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
        headers: await _hdrFriends(json: true),
        body: jsonEncode({'request_id': requestId}),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _loadFriends();
        await _loadRequests();
      } else {
        setState(() {
          _requestOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _requestOut = 'error: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setCloseFriend(
      Map<String, dynamic> friend, bool isClose) async {
    final phone = (friend['phone'] ?? friend['id'] ?? '').toString().trim();
    if (phone.isEmpty) return;
    setState(() {
      friend['close'] = isClose;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/close_friends/$phone');
      final headers = await _hdrFriends();
      final r = isClose
          ? await http.post(uri, headers: headers)
          : await http.delete(uri, headers: headers);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          friend['close'] = !isClose;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        friend['close'] = !isClose;
      });
    }
  }

  String _friendChatId(Map<String, dynamic> f) {
    try {
      final deviceId = (f['device_id'] ?? '').toString();
      if (deviceId.isNotEmpty) return deviceId;
    } catch (_) {}
    try {
      final shamellId = (f['shamell_id'] ?? '').toString();
      if (shamellId.isNotEmpty) return shamellId;
    } catch (_) {}
    try {
      final id = (f['id'] ?? '').toString();
      if (id.isNotEmpty) return id;
    } catch (_) {}
    try {
      final phone = (f['phone'] ?? '').toString();
      if (phone.isNotEmpty) return phone;
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
                    l.mirsaalFriendAliasTitle,
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
                      labelText: l.mirsaalFriendAliasLabel,
                      hintText: l.mirsaalFriendAliasHint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tagsCtrl,
                    decoration: InputDecoration(
                      labelText: l.mirsaalFriendTagsLabel,
                      hintText: l.mirsaalFriendTagsHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(l.mirsaalDialogCancel),
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
        isDark ? theme.colorScheme.surface : WeChatPalette.background;
    final dividerColor = isDark ? theme.dividerColor : WeChatPalette.divider;

    String title;
    switch (widget.mode) {
      case FriendsPageMode.newFriends:
        title = l.mirsaalContactsNewFriends;
        break;
      case FriendsPageMode.manage:
        title = l.mirsaalFriendsListTitle;
        break;
      case FriendsPageMode.picker:
        title = l.mirsaalTabContacts;
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
                        l.mirsaalFriendsCloseLabel,
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
                        '${l.mirsaalFriendTagsPrefix} $tagsText',
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
                        ? WeChatPalette.green
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
        leading: WeChatLeadingIcon(
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
                  foregroundColor: WeChatPalette.green,
                  side: const BorderSide(color: WeChatPalette.green),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: Text(l.mirsaalFriendsAccept),
              )
            : null,
      );
    }

    Widget peopleNearbyTile() {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: const WeChatLeadingIcon(
          icon: Icons.location_on_outlined,
          background: Color(0xFFF59E0B),
        ),
        title: Text(l.mirsaalFriendsPeopleNearbyTitle),
        subtitle: Text(
          l.mirsaalFriendsPeopleNearbySubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .65),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PeopleNearbyPage(
                baseUrl: widget.baseUrl,
                recommendedOfficials: const [],
                recommendedCityLabel: null,
              ),
            ),
          );
        },
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
        WeChatSearchBar(
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
              l.mirsaalFriendsEmpty,
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
                l.mirsaalFriendsCloseLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
                ),
              ),
            ),
          );
          tiles.add(
            WeChatSection(
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
          isDark ? WeChatPalette.searchFillDark : WeChatPalette.searchFill;

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
                        hintText: l.mirsaalFriendsSearchHint,
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
                            canSend ? WeChatPalette.green : Colors.transparent,
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
          header(l.mirsaalFriendsSuggestionsTitle),
          WeChatSection(
            margin: EdgeInsets.zero,
            backgroundColor: isDark ? theme.colorScheme.surface : Colors.white,
            children: [
              ListTile(
                dense: true,
                leading: const WeChatLeadingIcon(
                  icon: Icons.sync,
                  background: Color(0xFF94A3B8),
                ),
                title: Text(l.mirsaalFriendsSyncContacts),
                trailing: _contactsLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (_contactMatches > 0
                        ? Text(
                            '$_contactMatches',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .60),
                            ),
                          )
                        : const Icon(Icons.chevron_right)),
                onTap: _contactsLoading ? null : _loadContactSuggestions,
              ),
              if (!_contactsLoading && _contactSuggestions.isEmpty)
                ListTile(
                  dense: true,
                  title: Text(
                    l.mirsaalFriendsSuggestionsEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ),
              for (final c in _contactSuggestions) ...[
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const WeChatLeadingIcon(
                    icon: Icons.person_add_outlined,
                    background: Color(0xFF60A5FA),
                  ),
                  title: Text(
                    ((c['name'] ?? '').toString().trim().isNotEmpty)
                        ? (c['name'] ?? '').toString()
                        : (c['phone'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    (c['phone'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: .60),
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () =>
                            _sendRequestToPhone((c['phone'] ?? '').toString()),
                    style: TextButton.styleFrom(
                      foregroundColor: WeChatPalette.green,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: Text(l.isArabic ? 'إضافة' : 'Add'),
                  ),
                  onTap: _busy
                      ? null
                      : () =>
                          _sendRequestToPhone((c['phone'] ?? '').toString()),
                ),
              ],
            ],
          ),
          if (_incoming.isNotEmpty || _outgoing.isNotEmpty) ...[
            header(l.mirsaalFriendsRequestsTitle),
            WeChatSection(
              margin: EdgeInsets.zero,
              backgroundColor:
                  isDark ? theme.colorScheme.surface : Colors.white,
              children: [
                for (final r in _incoming) requestRow(r, incoming: true),
                for (final r in _outgoing) requestRow(r, incoming: false),
              ],
            ),
          ],
          header(l.mirsaalFriendsPeopleNearbyTitle),
          WeChatSection(
            margin: EdgeInsets.zero,
            backgroundColor: isDark ? theme.colorScheme.surface : Colors.white,
            children: [peopleNearbyTile()],
          ),
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
