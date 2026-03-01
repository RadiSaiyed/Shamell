import 'dart:async';
import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'glass.dart';
import 'l10n.dart';
import 'official_accounts_page.dart' show OfficialFeedItemDeepLinkPage;
import 'moments_page.dart' show MomentsPage;
import 'mini_apps_config.dart';
import 'call_signaling.dart';
import '../mini_apps/payments/payments_shell.dart';
import 'mini_programs_my_page_insights.dart' show MiniProgramInsightChip;
import 'shamell_ui.dart';
import 'mini_program_runtime.dart';
import 'http_error.dart';
import 'safe_set_state.dart';

Future<Map<String, String>> _hdrChannels({
  required String baseUrl,
  bool json = false,
}) async {
  final headers = <String, String>{};
  if (json) {
    headers['content-type'] = 'application/json';
  }
  try {
    final cookie = await getSessionCookieHeader(baseUrl) ?? '';
    if (cookie.isNotEmpty) {
      headers['cookie'] = cookie;
    }
  } catch (_) {}
  return headers;
}

class ChannelsPage extends StatefulWidget {
  final String baseUrl;
  final String? officialAccountId;
  final String? officialName;
  final bool initialHotOnly;
  // When true, this page is used from the
  // OfficialOwnerConsole and may show extra
  // creator/owner controls such as "End live".
  final bool forOwnerConsole;
  // Optional: when used from the owner console,
  // open the live composer immediately on first
  // frame to mimic a "Go live" action.
  final bool openLiveComposerOnStart;
  // Optional: start with the "Live only"
  // filter enabled, Shamell-style live tab.
  final bool initialLiveOnly;

  const ChannelsPage({
    super.key,
    required this.baseUrl,
    this.officialAccountId,
    this.officialName,
    this.initialHotOnly = false,
    this.forOwnerConsole = false,
    this.openLiveComposerOnStart = false,
    this.initialLiveOnly = false,
  });

  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage>
    with SafeSetStateMixin<ChannelsPage> {
  static const Duration _channelsRequestTimeout = Duration(seconds: 15);
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  bool _hotOnly = false;
  bool _campaignOnly = false;
  bool _followingOnly = false;
  bool _liveOnly = false;
  String? _cityFilter;
  String? _categoryFilter;
  int _timeWindowDays = 0; // 0 = all time, 7/30 = last N days

  @override
  void initState() {
    super.initState();
    _hotOnly = widget.initialHotOnly;
    _liveOnly = widget.initialLiveOnly;
    _load();
    if (widget.openLiveComposerOnStart &&
        (widget.officialAccountId ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openUploadComposer(initialLive: true);
      });
    }
  }

  Future<Map<String, String>> _hdrUpload({bool json = false}) async {
    final headers = <String, String>{};
    if (json) {
      headers['content-type'] = 'application/json';
    }
    try {
      final cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      if (cookie.isNotEmpty) {
        headers['cookie'] = cookie;
      }
    } catch (_) {}
    return headers;
  }

  Future<void> _openUploadComposer({bool initialLive = false}) async {
    if ((widget.officialAccountId ?? '').trim().isEmpty) {
      return;
    }
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final titleCtrl = TextEditingController();
    final snippetCtrl = TextEditingController();
    final thumbCtrl = TextEditingController();
    final liveUrlCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    bool isLive = initialLive;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 12,
            bottom: bottom + 12,
          ),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: StatefulBuilder(
              builder: (ctx2, setModalState) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.live_tv_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .85),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'إنشاء مقطع قناة جديد'
                                  : 'Create new Channels clip',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'العنوان (اختياري)'
                              : 'Title (optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: snippetCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'الوصف / النص'
                              : 'Description / caption',
                        ),
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: isLive,
                        onChanged: (val) {
                          setModalState(() {
                            isLive = val;
                          });
                        },
                        title: Text(
                          l.isArabic ? 'بث مباشر' : 'Live session',
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          l.isArabic
                              ? 'اجعل هذا المقطع بثًا مباشرًا في القنوات، بأسلوب Shamell Channels.'
                              : 'Mark this as a live session in Channels, Shamell‑Channels style.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: thumbCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'رابط صورة مصغرة (اختياري)'
                              : 'Thumbnail URL (optional)',
                          helperText: l.isArabic
                              ? 'استخدم رابط صورة موجودة أو اتركه فارغاً.'
                              : 'Use an existing image URL or leave empty.',
                        ),
                      ),
                      if (isLive) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: liveUrlCtrl,
                          decoration: InputDecoration(
                            labelText: l.isArabic
                                ? 'رابط البث (اختياري)'
                                : 'Live URL (optional)',
                            helperText: l.isArabic
                                ? 'مثال: رابط HLS أو صفحة لاعب خارجي.'
                                : 'Example: HLS URL or external player page.',
                          ),
                        ),
                      ],
                      if (error != null && error!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(ctx).pop(),
                            child: Text(
                              l.isArabic ? 'إلغاء' : 'Cancel',
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: submitting
                                ? null
                                : () async {
                                    final title = titleCtrl.text.trim().isEmpty
                                        ? null
                                        : titleCtrl.text.trim();
                                    final snippet =
                                        snippetCtrl.text.trim().isEmpty
                                            ? null
                                            : snippetCtrl.text.trim();
                                    if (snippet == null || snippet.isEmpty) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'النص مطلوب.'
                                            : 'Caption is required.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final uri = Uri.parse(
                                        '${widget.baseUrl}/channels/upload',
                                      );
                                      final payload = <String, Object?>{
                                        'official_account_id':
                                            widget.officialAccountId!.trim(),
                                        'title': title,
                                        'snippet': snippet,
                                        'thumb_url':
                                            thumbCtrl.text.trim().isEmpty
                                                ? null
                                                : thumbCtrl.text.trim(),
                                        'is_live': isLive,
                                      };
                                      final liveUrl = liveUrlCtrl.text.trim();
                                      if (isLive && liveUrl.isNotEmpty) {
                                        payload['deeplink'] = <String, Object?>{
                                          'live_url': liveUrl,
                                        };
                                      }
                                      final resp = await http
                                          .post(
                                            uri,
                                            headers:
                                                await _hdrUpload(json: true),
                                            body: jsonEncode(payload),
                                          )
                                          .timeout(_channelsRequestTimeout);
                                      if (resp.statusCode < 200 ||
                                          resp.statusCode >= 300) {
                                        final msg = sanitizeHttpError(
                                          statusCode: resp.statusCode,
                                          rawBody: resp.body,
                                          isArabic: l.isArabic,
                                        );
                                        setModalState(() {
                                          submitting = false;
                                          error = msg;
                                        });
                                        return;
                                      }
                                      if (!mounted) return;
                                      Navigator.of(ctx).pop();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l.isArabic
                                                ? 'تم إنشاء مقطع القناة.'
                                                : 'Channels clip created.',
                                          ),
                                        ),
                                      );
                                      // Refresh feed to include new clip.
                                      // ignore: discarded_futures
                                      _load();
                                    } catch (e) {
                                      setModalState(() {
                                        submitting = false;
                                        error =
                                            sanitizeExceptionForUi(error: e);
                                      });
                                    }
                                  },
                            icon: submitting
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.check),
                            label: Text(
                              l.isArabic ? 'نشر' : 'Publish',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final qp = <String, String>{'limit': '50'};
      final accId = (widget.officialAccountId ?? '').trim();
      if (accId.isNotEmpty) {
        qp['official_account_id'] = accId;
      }
      final uri = Uri.parse('${widget.baseUrl}/channels/feed')
          .replace(queryParameters: qp);
      final r = await http
          .get(uri, headers: await _hdrChannels(baseUrl: widget.baseUrl))
          .timeout(_channelsRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
          _loading = false;
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['items'] is List) {
        raw = decoded['items'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final items = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        items.add(e.cast<String, dynamic>());
      }
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _recordView(String itemId) async {
    if (itemId.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/channels/${Uri.encodeComponent(itemId)}/view',
      );
      await http
          .post(uri, headers: await _hdrChannels(baseUrl: widget.baseUrl))
          .timeout(_channelsRequestTimeout);
    } catch (_) {}
  }

  Future<void> _toggleLike(String itemId, {required int index}) async {
    if (itemId.isEmpty || index < 0 || index >= _items.length) return;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/channels/${Uri.encodeComponent(itemId)}/like',
      );
      final r = await http
          .post(
            uri,
            headers: await _hdrChannels(baseUrl: widget.baseUrl, json: true),
            body: jsonEncode(<String, dynamic>{}),
          )
          .timeout(_channelsRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return;
      final likesRaw = decoded['likes'];
      final likedRaw = decoded['liked'];
      if (!mounted) return;
      setState(() {
        final current = Map<String, dynamic>.from(_items[index]);
        if (likesRaw is num) {
          current['likes'] = likesRaw.toInt();
        }
        if (likedRaw is bool) {
          current['liked_by_me'] = likedRaw;
        }
        _items[index] = current;
      });
    } catch (_) {}
  }

  Future<void> _endLive(String itemId, {required int index}) async {
    if (itemId.isEmpty || index < 0 || index >= _items.length) return;
    final l = L10n.of(context);
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/channels/live/${Uri.encodeComponent(itemId)}/stop',
      );
      final r = await http
          .post(
            uri,
            headers: await _hdrChannels(baseUrl: widget.baseUrl, json: true),
            body: jsonEncode(<String, dynamic>{}),
          )
          .timeout(_channelsRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر إيقاف البث المباشر.'
                  : 'Failed to end live session.',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        final current = Map<String, dynamic>.from(_items[index]);
        current['item_type'] = 'clip';
        current['type'] = 'clip';
        _items[index] = current;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تم إنهاء البث.' : 'Live session ended.',
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _toggleFollowChannel(String accountId) async {
    if (accountId.isEmpty) return;
    final l = L10n.of(context);
    // Determine current state from first matching item.
    bool followed = false;
    for (final raw in _items) {
      final accId = (raw['official_account_id'] ?? '').toString().trim();
      if (accId == accountId) {
        followed = (raw['channel_followed_by_me'] as bool?) ?? false;
        break;
      }
    }
    final path = followed ? 'unfollow' : 'follow';
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/channels/accounts/${Uri.encodeComponent(accountId)}/$path',
      );
      final r = await http
          .post(uri,
              headers: await _hdrChannels(baseUrl: widget.baseUrl, json: true))
          .timeout(_channelsRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      // Optimistically update local state for all clips of this account.
      if (!mounted) return;
      setState(() {
        final list = <Map<String, dynamic>>[];
        for (final raw in _items) {
          final accId = (raw['official_account_id'] ?? '').toString().trim();
          if (accId != accountId) {
            list.add(raw);
            continue;
          }
          final m = Map<String, dynamic>.from(raw);
          final wasFollowed = (m['channel_followed_by_me'] as bool?) ?? false;
          final followersRaw = m['channel_followers'];
          int followers = followersRaw is num ? followersRaw.toInt() : 0;
          if (wasFollowed && followers > 0) {
            followers -= 1;
          } else if (!wasFollowed) {
            followers += 1;
          }
          m['channel_followed_by_me'] = !wasFollowed;
          m['channel_followers'] = followers;
          list.add(m);
        }
        _items = list;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            followed
                ? (l.isArabic
                    ? 'تم إلغاء متابعة القناة.'
                    : 'Unfollowed channel.')
                : (l.isArabic ? 'تمت متابعة القناة.' : 'Followed channel.'),
          ),
        ),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _fetchComments(String itemId) async {
    final uri = Uri.parse(
      '${widget.baseUrl}/channels/${Uri.encodeComponent(itemId)}/comments',
    ).replace(queryParameters: const {'limit': '50'});
    final r = await http
        .get(uri, headers: await _hdrChannels(baseUrl: widget.baseUrl))
        .timeout(_channelsRequestTimeout);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      return const <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(r.body);
    List<dynamic> raw = const [];
    if (decoded is Map && decoded['items'] is List) {
      raw = decoded['items'] as List;
    } else if (decoded is List) {
      raw = decoded;
    }
    final items = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is! Map) continue;
      items.add(e.cast<String, dynamic>());
    }
    return items;
  }

  Future<void> _showComments(String itemId, {required int index}) async {
    if (itemId.isEmpty) return;
    final l = L10n.of(context);
    List<Map<String, dynamic>> comments = const <Map<String, dynamic>>[];
    try {
      comments = await _fetchComments(itemId);
    } catch (_) {}
    if (!mounted) return;
    final TextEditingController textCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 12,
            bottom: bottom + 12,
          ),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: StatefulBuilder(
              builder: (ctx2, setModalState) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.mode_comment_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .85),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'تعليقات القناة'
                                  : 'Channel comments',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (comments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            l.isArabic
                                ? 'لا توجد تعليقات بعد. كن أول من يعلّق.'
                                : 'No comments yet. Be the first to comment.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: comments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final c = comments[i];
                              final text = (c['text'] ?? '').toString().trim();
                              final createdRaw =
                                  (c['created_at'] ?? '').toString().trim();
                              final authorKind =
                                  (c['author_kind'] ?? 'user').toString();
                              final isOfficial =
                                  authorKind.toLowerCase() == 'official';
                              final theme2 = Theme.of(ctx2);
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  isOfficial
                                      ? Icons.verified_outlined
                                      : Icons.person_outline,
                                  size: 20,
                                  color: isOfficial
                                      ? theme2.colorScheme.primary
                                      : theme2.colorScheme.onSurface
                                          .withValues(alpha: .70),
                                ),
                                title: Text(
                                  text.isEmpty
                                      ? (l.isArabic
                                          ? 'تعليق بدون نص'
                                          : 'Comment without text')
                                      : text,
                                ),
                                subtitle: createdRaw.isEmpty
                                    ? null
                                    : Text(
                                        createdRaw,
                                        style: theme2.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme2.colorScheme.onSurface
                                              .withValues(alpha: .60),
                                        ),
                                      ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (error != null && error!.isNotEmpty) ...[
                        Text(
                          error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: textCtrl,
                              enabled: !submitting,
                              decoration: InputDecoration(
                                hintText: l.isArabic
                                    ? 'أضف تعليقًا...'
                                    : 'Add a comment…',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              minLines: 1,
                              maxLines: 3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: submitting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        theme.colorScheme.primary,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.send_outlined),
                            onPressed: submitting
                                ? null
                                : () async {
                                    final text = textCtrl.text.trim();
                                    if (text.isEmpty) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'النص مطلوب.'
                                            : 'Text is required.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final uri = Uri.parse(
                                        '${widget.baseUrl}/channels/${Uri.encodeComponent(itemId)}/comments',
                                      );
                                      final r = await http
                                          .post(
                                            uri,
                                            headers: await _hdrChannels(
                                                baseUrl: widget.baseUrl,
                                                json: true),
                                            body: jsonEncode(
                                              <String, dynamic>{'text': text},
                                            ),
                                          )
                                          .timeout(_channelsRequestTimeout);
                                      if (r.statusCode < 200 ||
                                          r.statusCode >= 300) {
                                        setModalState(() {
                                          submitting = false;
                                          error = l.isArabic
                                              ? 'تعذّر إرسال التعليق.'
                                              : 'Failed to submit comment.';
                                        });
                                        return;
                                      }
                                      try {
                                        comments = await _fetchComments(itemId);
                                      } catch (_) {}
                                      if (!ctx2.mounted) return;
                                      setModalState(() {
                                        submitting = false;
                                        textCtrl.clear();
                                      });
                                    } catch (_) {
                                      setModalState(() {
                                        submitting = false;
                                        error = l.isArabic
                                            ? 'تعذّر إرسال التعليق.'
                                            : 'Failed to submit comment.';
                                      });
                                    }
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error.withValues(alpha: .85),
            ),
          ),
        ),
      );
    } else {
      String? cityLabel;
      final Set<String> categories = <String>{};
      for (final raw in _items) {
        final c = (raw['official_city'] ?? '').toString().trim();
        if (c.isNotEmpty) {
          cityLabel = c;
        }
        final cat = (raw['official_category'] ?? '').toString().trim();
        if (cat.isNotEmpty) {
          categories.add(cat);
        }
      }
      final indices = <int>[];
      final now = DateTime.now().toUtc();
      for (var i = 0; i < _items.length; i++) {
        final raw = _items[i];
        final isHot = (raw['official_is_hot'] as bool?) ?? false;
        final itemType =
            (raw['item_type'] ?? '').toString().trim().toLowerCase();
        final isLive = itemType == 'live';
        final isCampaign = itemType == 'campaign' || itemType == 'promo';
        final city = (raw['official_city'] ?? '').toString().trim();
        final category = (raw['official_category'] ?? '').toString().trim();
        final tsRaw = (raw['ts'] ?? '').toString().trim();
        DateTime? ts;
        if (tsRaw.isNotEmpty) {
          try {
            ts = DateTime.parse(tsRaw).toUtc();
          } catch (_) {
            ts = null;
          }
        }
        if (_hotOnly && !isHot) continue;
        if (_campaignOnly && !isCampaign) continue;
        if (_cityFilter != null &&
            _cityFilter!.isNotEmpty &&
            city.isNotEmpty &&
            city != _cityFilter) {
          continue;
        }
        if (_categoryFilter != null &&
            _categoryFilter!.isNotEmpty &&
            category.isNotEmpty &&
            category != _categoryFilter) {
          continue;
        }
        if (_timeWindowDays > 0 && ts != null) {
          final diff = now.difference(ts);
          if (diff.inDays > _timeWindowDays) {
            continue;
          }
        }
        if (_followingOnly) {
          final isFollowed = (raw['channel_followed_by_me'] as bool?) ?? false;
          if (!isFollowed) {
            continue;
          }
        }
        if (_liveOnly && !isLive) {
          continue;
        }
        indices.add(i);
      }
      // Lightweight Shamell-like "Channel insights" for the current view –
      // summarises clips, views, and how many services are hot in Moments.
      int clipCount = indices.length;
      int totalViews = 0;
      int totalLikes = 0;
      int totalComments = 0;
      final Set<String> services = <String>{};
      final Set<String> hotServices = <String>{};
      int hotClips = 0;
      for (final idx in indices) {
        final raw = _items[idx];
        final viewsRaw = raw['views'];
        final likesRaw = raw['likes'];
        final commentsRaw = raw['comments'];
        final views = viewsRaw is num ? viewsRaw.toInt() : 0;
        final likes = likesRaw is num ? likesRaw.toInt() : 0;
        final comments = commentsRaw is num ? commentsRaw.toInt() : 0;
        totalViews += views;
        totalLikes += likes;
        totalComments += comments;
        final accId = (raw['official_account_id'] ?? '').toString().trim();
        if (accId.isNotEmpty) {
          services.add(accId);
        }
        final isHot = (raw['official_is_hot'] as bool?) ?? false;
        if (isHot && accId.isNotEmpty) {
          hotServices.add(accId);
          hotClips += 1;
        }
      }
      // Prepare a simple "Top clips" list for the current view using the
      // backend-provided score and creation timestamp.
      final topClips = <Map<String, dynamic>>[];
      for (final idx in indices) {
        final raw = _items[idx];
        final withIdx = Map<String, dynamic>.from(raw)..['__index'] = idx;
        topClips.add(withIdx);
      }
      topClips.sort((a, b) {
        final sa = (a['score'] is num) ? (a['score'] as num).toDouble() : 0.0;
        final sb = (b['score'] is num) ? (b['score'] as num).toDouble() : 0.0;
        return sb.compareTo(sa);
      });
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((widget.officialAccountId ?? '').trim().isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                l.isArabic
                    ? 'اكتشف مقاطع قصيرة من الخدمات الرسمية، مرتبة حسب التفاعل والرواج في اللحظات.'
                    : 'Discover short clips from official services, ranked by engagement and how hot they are in Moments.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .75),
                ),
              ),
            ),
          if (widget.forOwnerConsole &&
              (widget.officialAccountId ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.insights_outlined,
                    size: 18,
                    color: theme.colorScheme.primary.withValues(alpha: .85),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.isArabic
                          ? 'لوحة منشئ القنوات لهذا الحساب'
                          : 'Channels creator tools for this account',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .75),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openUploadComposer,
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: Text(
                      l.isArabic ? 'مقطع جديد' : 'New clip',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: Text(
                    l.isArabic ? 'الكل' : 'All clips',
                  ),
                  selected: !_hotOnly &&
                      !_campaignOnly &&
                      !_followingOnly &&
                      !_liveOnly &&
                      (_cityFilter == null || _cityFilter!.isEmpty) &&
                      (_categoryFilter == null || _categoryFilter!.isEmpty),
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _hotOnly = false;
                      _campaignOnly = false;
                      _followingOnly = false;
                      _liveOnly = false;
                      _cityFilter = null;
                      _categoryFilter = null;
                    });
                  },
                ),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite_outline,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l.isArabic ? 'المتابَعة' : 'Following',
                      ),
                    ],
                  ),
                  selected: _followingOnly,
                  onSelected: (sel) {
                    setState(() {
                      _followingOnly = sel;
                    });
                  },
                ),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department_outlined,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l.isArabic ? 'الرائجة' : 'Hot only',
                      ),
                    ],
                  ),
                  selected: _hotOnly,
                  onSelected: (sel) {
                    setState(() {
                      _hotOnly = sel;
                    });
                  },
                ),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.live_tv_outlined,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l.isArabic ? 'البث المباشر' : 'Live only',
                      ),
                    ],
                  ),
                  selected: _liveOnly,
                  onSelected: (sel) {
                    setState(() {
                      _liveOnly = sel;
                    });
                  },
                ),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.campaign_outlined,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l.isArabic ? 'الحملات' : 'Campaigns only',
                      ),
                    ],
                  ),
                  selected: _campaignOnly,
                  onSelected: (sel) {
                    setState(() {
                      _campaignOnly = sel;
                    });
                  },
                ),
                if (cityLabel != null && cityLabel.isNotEmpty)
                  ChoiceChip(
                    label: Text(
                      l.isArabic
                          ? 'خدمات في $cityLabel'
                          : 'Services in $cityLabel',
                    ),
                    selected: _cityFilter == cityLabel,
                    onSelected: (sel) {
                      setState(() {
                        _cityFilter = sel ? cityLabel : null;
                      });
                    },
                  ),
                for (final cat in categories.take(4))
                  ChoiceChip(
                    label: Text(
                      _labelForCategory(cat, l),
                    ),
                    selected: _categoryFilter == cat,
                    onSelected: (sel) {
                      setState(() {
                        _categoryFilter = sel ? cat : null;
                      });
                    },
                  ),
              ],
            ),
          ),
          if ((widget.officialAccountId ?? '').trim().isNotEmpty &&
              topClips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Builder(
                builder: (ctx) {
                  final isAr = l.isArabic;
                  final now = DateTime.now().toUtc();
                  final display = topClips.length > 3
                      ? topClips.sublist(0, 3)
                      : List<Map<String, dynamic>>.from(topClips);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isAr
                            ? 'أفضل المقاطع لهذا الحساب'
                            : 'Top clips for this account',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .80),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: display.map((raw) {
                            final title =
                                (raw['title'] ?? '').toString().trim();
                            final snippet =
                                (raw['snippet'] ?? '').toString().trim();
                            final viewsRaw = raw['views'];
                            final views =
                                viewsRaw is num ? viewsRaw.toInt() : 0;
                            final likesRaw = raw['likes'];
                            final likes =
                                likesRaw is num ? likesRaw.toInt() : 0;
                            final commentsRaw = raw['comments'];
                            final comments =
                                commentsRaw is num ? commentsRaw.toInt() : 0;
                            final tsRaw = (raw['ts'] ?? '').toString().trim();
                            DateTime? ts;
                            bool isNew = false;
                            if (tsRaw.isNotEmpty) {
                              try {
                                ts = DateTime.parse(tsRaw).toUtc();
                                final diff = now.difference(ts);
                                isNew = diff.inDays < 7;
                              } catch (_) {
                                ts = null;
                              }
                            }
                            final idx = (raw['__index'] as int?) ?? 0;
                            final labelBuf = StringBuffer();
                            if (title.isNotEmpty) {
                              labelBuf.write(title);
                            } else if (snippet.isNotEmpty) {
                              labelBuf.write(snippet);
                            } else {
                              labelBuf.write(isAr ? 'مقطع' : 'Clip');
                            }
                            if (views > 0 || likes > 0 || comments > 0) {
                              labelBuf.write(' · ');
                              if (views > 0) {
                                labelBuf.write(
                                    isAr ? 'مشاهدات $views' : 'Views $views');
                              }
                              if (likes > 0) {
                                if (views > 0) labelBuf.write(' · ');
                                labelBuf.write(
                                    isAr ? 'إعجابات $likes' : 'Likes $likes');
                              }
                              if (comments > 0) {
                                if (views > 0 || likes > 0) {
                                  labelBuf.write(' · ');
                                }
                                labelBuf.write(isAr
                                    ? 'تعليقات $comments'
                                    : 'Comments $comments');
                              }
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: Icon(
                                  isNew
                                      ? Icons.fiber_new_outlined
                                      : Icons.play_circle_outline,
                                  size: 16,
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: .85),
                                ),
                                label: Text(
                                  labelBuf.toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onPressed: () {
                                  if (idx < 0 || idx >= _items.length) {
                                    return;
                                  }
                                  final item = _items[idx];
                                  final itemId =
                                      (item['id'] ?? '').toString().trim();
                                  if (itemId.isEmpty) return;
                                  _recordView(itemId);
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          OfficialFeedItemDeepLinkPage(
                                        baseUrl: widget.baseUrl,
                                        accountId:
                                            (item['official_account_id'] ?? '')
                                                .toString(),
                                        itemId: itemId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: Text(
                    l.isArabic ? 'كل الوقت' : 'All time',
                  ),
                  selected: _timeWindowDays == 0,
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _timeWindowDays = 0;
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    l.isArabic ? 'آخر ٧ أيام' : 'Last 7 days',
                  ),
                  selected: _timeWindowDays == 7,
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _timeWindowDays = 7;
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    l.isArabic ? 'آخر ٣٠ يومًا' : 'Last 30 days',
                  ),
                  selected: _timeWindowDays == 30,
                  onSelected: (sel) {
                    if (!sel) return;
                    setState(() {
                      _timeWindowDays = 30;
                    });
                  },
                ),
              ],
            ),
          ),
          if ((widget.officialAccountId ?? '').trim().isEmpty &&
              cityLabel != null &&
              cityLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.isArabic
                          ? 'لحظات من خدمات في $cityLabel'
                          : 'Moments from services in $cityLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MomentsPage(
                            baseUrl: widget.baseUrl,
                            officialCity: cityLabel,
                            initialHotOfficialsOnly: true,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      l.isArabic ? 'عرض اللحظات' : 'Open Moments',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (indices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: _buildInsightsBanner(
                l,
                theme,
                clipCount: clipCount,
                totalViews: totalViews,
                totalLikes: totalLikes,
                totalComments: totalComments,
                servicesCount: services.length,
                hotServicesCount: hotServices.length,
                hotClipsCount: hotClips,
              ),
            ),
          Expanded(
            child: indices.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.isArabic
                            ? 'لا توجد مقاطع مطابقة.'
                            : 'No matching clips.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .65),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: indices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final i = indices[idx];
                      final raw = _items[i];
                      final title = (raw['title'] ?? '').toString();
                      final snippet = (raw['snippet'] ?? '').toString();
                      final thumb = (raw['thumb_url'] ?? '').toString();
                      final accName =
                          (raw['official_name'] ?? '').toString().trim();
                      final accAvatar =
                          (raw['official_avatar_url'] ?? '').toString().trim();
                      final accCity =
                          (raw['official_city'] ?? '').toString().trim();
                      final accId =
                          (raw['official_account_id'] ?? '').toString().trim();
                      final itemId = (raw['id'] ?? '').toString().trim();
                      final isHot = (raw['official_is_hot'] as bool?) ?? false;
                      final itemType = (raw['item_type'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();
                      final isLive = itemType == 'live';
                      final isCampaign =
                          itemType == 'campaign' || itemType == 'promo';
                      final commentsRaw = raw['comments'];
                      final comments =
                          commentsRaw is num ? commentsRaw.toInt() : 0;
                      final likesRaw = raw['likes'];
                      final likes = likesRaw is num ? likesRaw.toInt() : 0;
                      final likedByMe = (raw['liked_by_me'] as bool?) ?? false;
                      final viewsRaw = raw['views'];
                      final views = viewsRaw is num ? viewsRaw.toInt() : 0;
                      final tsRaw = (raw['ts'] ?? '').toString().trim();
                      DateTime? ts;
                      if (tsRaw.isNotEmpty) {
                        try {
                          ts = DateTime.parse(tsRaw).toUtc();
                        } catch (_) {
                          ts = null;
                        }
                      }
                      String? miniAppId;
                      Map<String, dynamic>? deeplinkPayload;
                      final dl = raw['deeplink'];
                      if (dl is Map) {
                        final midRaw =
                            (dl['mini_app_id'] ?? '').toString().trim();
                        if (midRaw.isNotEmpty) {
                          miniAppId = midRaw;
                        }
                        final rawPayload = dl['payload'];
                        if (rawPayload is Map) {
                          deeplinkPayload = rawPayload.cast<String, dynamic>();
                        }
                      }
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (itemId.isEmpty) return;
                          _recordView(itemId);
                          // Primary deeplink: open full feed item page when possible.
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OfficialFeedItemDeepLinkPage(
                                baseUrl: widget.baseUrl,
                                accountId: accId.isNotEmpty ? accId : '',
                                itemId: itemId,
                              ),
                            ),
                          );
                        },
                        child: GlassPanel(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (thumb.isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        thumb,
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else if (accAvatar.isNotEmpty)
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundImage: NetworkImage(accAvatar),
                                    )
                                  else
                                    CircleAvatar(
                                      radius: 24,
                                      child: Text(
                                        accName.isNotEmpty
                                            ? accName.characters.first
                                                .toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (title.isNotEmpty)
                                          Text(
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        if (snippet.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              snippet,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withValues(alpha: .75),
                                              ),
                                            ),
                                          ),
                                        if (miniAppId != null &&
                                            miniAppId!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: _buildMiniAppRow(
                                              context,
                                              miniAppId!,
                                              deeplinkPayload,
                                            ),
                                          ),
                                        if (accName.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    accCity.isNotEmpty &&
                                                            accName.isNotEmpty
                                                        ? '$accName · $accCity'
                                                        : accName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      color: theme
                                                          .colorScheme.onSurface
                                                          .withValues(
                                                              alpha: .70),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Builder(
                                                  builder: (ctx2) {
                                                    final followersRaw = raw[
                                                        'channel_followers'];
                                                    final followers =
                                                        followersRaw is num
                                                            ? followersRaw
                                                                .toInt()
                                                            : 0;
                                                    final followed =
                                                        (raw['channel_followed_by_me']
                                                                as bool?) ??
                                                            false;
                                                    final label = followed
                                                        ? (l.isArabic
                                                            ? 'متابَعة'
                                                            : 'Following')
                                                        : (l.isArabic
                                                            ? 'متابعة'
                                                            : 'Follow');
                                                    return InkWell(
                                                      onTap: () {
                                                        if (accId.isEmpty) {
                                                          return;
                                                        }
                                                        _toggleFollowChannel(
                                                            accId);
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        999,
                                                      ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: followed
                                                              ? theme
                                                                  .colorScheme
                                                                  .primary
                                                                  .withValues(
                                                                      alpha:
                                                                          .10)
                                                              : theme
                                                                  .colorScheme
                                                                  .surface
                                                                  .withValues(
                                                                      alpha:
                                                                          .90),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            999,
                                                          ),
                                                          border: Border.all(
                                                            color: theme
                                                                .colorScheme
                                                                .primary
                                                                .withValues(
                                                                    alpha: .40),
                                                            width: 0.7,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              followed
                                                                  ? Icons.check
                                                                  : Icons.add,
                                                              size: 12,
                                                              color: theme
                                                                  .colorScheme
                                                                  .primary
                                                                  .withValues(
                                                                      alpha:
                                                                          .90),
                                                            ),
                                                            const SizedBox(
                                                                width: 4),
                                                            Text(
                                                              label,
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: theme
                                                                    .colorScheme
                                                                    .primary
                                                                    .withValues(
                                                                        alpha:
                                                                            .90),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            if (followers > 0)
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                  left: 4,
                                                                ),
                                                                child: Text(
                                                                  followers
                                                                      .toString(),
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize: 9,
                                                                    color: theme
                                                                        .colorScheme
                                                                        .onSurface
                                                                        .withValues(
                                                                            alpha:
                                                                                .60),
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                                if (isLive) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red
                                                          .withValues(
                                                              alpha: .12),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        999,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .live_tv_outlined,
                                                          size: 12,
                                                          color: Colors.red
                                                              .withValues(
                                                                  alpha: .95),
                                                        ),
                                                        const SizedBox(
                                                            width: 2),
                                                        Text(
                                                          l.isArabic
                                                              ? 'مباشر'
                                                              : 'LIVE',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ] else if (isHot) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: theme
                                                          .colorScheme.primary
                                                          .withValues(
                                                              alpha: .10),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        999,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .local_fire_department_outlined,
                                                          size: 12,
                                                          color: theme
                                                              .colorScheme
                                                              .primary,
                                                        ),
                                                        const SizedBox(
                                                            width: 2),
                                                        Text(
                                                          l.isArabic
                                                              ? 'رائج في اللحظات'
                                                              : 'Hot in Moments',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ] else if (isCampaign) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: theme
                                                          .colorScheme.secondary
                                                          .withValues(
                                                              alpha: .10),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        999,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .campaign_outlined,
                                                          size: 12,
                                                        ),
                                                        const SizedBox(
                                                            width: 2),
                                                        Text(
                                                          l.isArabic
                                                              ? 'حملة'
                                                              : 'Campaign',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        iconSize: 20,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: Icon(
                                          likedByMe
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: likedByMe
                                              ? theme.colorScheme.secondary
                                              : theme.colorScheme.onSurface
                                                  .withValues(alpha: .50),
                                        ),
                                        onPressed: () {
                                          if (itemId.isEmpty) return;
                                          _toggleLike(
                                            itemId,
                                            index: i,
                                          );
                                        },
                                      ),
                                      if (likes > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          child: Text(
                                            '$likes',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              fontSize: 11,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: .70),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        iconSize: 18,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(
                                          Icons.mode_comment_outlined,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          if (itemId.isEmpty) return;
                                          _showComments(
                                            itemId,
                                            index: i,
                                          );
                                        },
                                      ),
                                      if (comments > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          child: Text(
                                            '$comments',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              fontSize: 11,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: .70),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        iconSize: 18,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(
                                          Icons.insights_outlined,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          _showClipInsights(
                                            context,
                                            raw,
                                            ts: ts,
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(
                                        Icons.remove_red_eye_outlined,
                                        size: 16,
                                      ),
                                      if (views > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          child: Text(
                                            '$views',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              fontSize: 11,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: .70),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.forOwnerConsole &&
                                          isLive &&
                                          (widget.officialAccountId ?? '')
                                              .trim()
                                              .isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(right: 8),
                                          child: TextButton.icon(
                                            icon: const Icon(
                                              Icons.stop_circle_outlined,
                                              size: 18,
                                            ),
                                            label: Text(
                                              l.isArabic
                                                  ? 'إنهاء البث'
                                                  : 'End live',
                                            ),
                                            onPressed: () {
                                              if (itemId.isEmpty) return;
                                              _endLive(
                                                itemId,
                                                index: i,
                                              );
                                            },
                                          ),
                                        ),
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.share_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          l.isArabic
                                              ? 'مشاركة في اللحظات'
                                              : 'Share to Moments',
                                        ),
                                        onPressed: () async {
                                          final buf = StringBuffer();
                                          if (title.isNotEmpty) {
                                            buf.writeln(title);
                                          }
                                          if (snippet.isNotEmpty) {
                                            buf.writeln(snippet);
                                          }
                                          if (accName.isNotEmpty) {
                                            buf.writeln();
                                            buf.writeln(
                                              l.isArabic
                                                  ? 'من $accName'
                                                  : 'From $accName',
                                            );
                                          }
                                          if (accId.isNotEmpty) {
                                            final deepLink =
                                                'shamell://official/$accId${itemId.isNotEmpty ? '/$itemId' : ''}';
                                            buf.writeln(deepLink);
                                          }
                                          var text = buf.toString().trim();
                                          if (text.isEmpty) return;
                                          if (!text.contains('#')) {
                                            final tag = _hashTagForMiniApp(
                                              miniAppId,
                                              l.isArabic,
                                            );
                                            if (tag != null && tag.isNotEmpty) {
                                              text += ' $tag';
                                            } else {
                                              text += l.isArabic
                                                  ? ' #شامل_حساب_رسمي'
                                                  : ' #ShamellOfficial';
                                            }
                                          }
                                          if (itemId.isNotEmpty) {
                                            final clipTag =
                                                '#ch_${itemId.toLowerCase()}';
                                            if (!text.contains(clipTag)) {
                                              text += ' $clipTag';
                                            }
                                          }
                                          try {
                                            final sp = await SharedPreferences
                                                .getInstance();
                                            await sp.setString(
                                              'moments_preset_text',
                                              text,
                                            );
                                          } catch (_) {}
                                          if (!mounted) return;
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => MomentsPage(
                                                baseUrl: widget.baseUrl,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }

    final title = () {
      final accId = (widget.officialAccountId ?? '').trim();
      final accName = (widget.officialName ?? '').trim();
      if (accId.isNotEmpty) {
        if (accName.isNotEmpty) {
          return l.isArabic
              ? 'مقاطع من $accName'
              : 'Channels clips from $accName';
        }
        return l.isArabic ? 'مقاطع هذا الحساب' : 'Account clips';
      }
      if (_liveOnly) {
        return l.isArabic ? 'بث مباشر في القنوات' : 'Live in Channels';
      }
      if (_hotOnly) {
        return l.isArabic ? 'مقاطع رائجة' : 'Hot clips';
      }
      return l.isArabic ? 'اكتشاف القنوات' : 'Channels discover';
    }();
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: body,
    );
  }

  Widget _buildMiniAppRow(
    BuildContext context,
    String miniAppId,
    Map<String, dynamic>? payload,
  ) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final app = miniAppById(miniAppId);
    final serviceTitle = app?.title(isArabic: isAr) ?? miniAppId;
    final poweredText =
        isAr ? 'مدعوم بخدمة $serviceTitle' : 'Powered by $serviceTitle';
    IconData icon;
    String buttonLabel;
    switch (miniAppId) {
      case 'payments':
      case 'alias':
      case 'merchant':
        icon = Icons.account_balance_wallet_outlined;
        buttonLabel = isAr ? 'فتح المحفظة' : 'Open wallet';
        break;
      case 'bus':
        icon = Icons.directions_bus_filled_outlined;
        buttonLabel = isAr ? 'فتح الباص' : 'Open bus';
        break;
      default:
        icon = Icons.apps_outlined;
        buttonLabel = isAr ? 'فتح الخدمة' : 'Open service';
        break;
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            poweredText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .65),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: Icon(icon, size: 16),
          label: Text(
            buttonLabel,
            style: const TextStyle(fontSize: 11),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            foregroundColor: theme.colorScheme.primary,
          ),
          onPressed: () {
            _openMiniAppFromClip(miniAppId, payload: payload);
          },
        ),
      ],
    );
  }

  String? _hashTagForMiniApp(String? mid, bool isArabic) {
    if (mid == null || mid.isEmpty) return null;
    switch (mid) {
      case 'payments':
      case 'alias':
      case 'merchant':
        return '#ShamellWallet';
      case 'bus':
        return '#ShamellBus';
      default:
        return '#ShamellMiniApp';
    }
  }

  Future<void> _openMiniAppFromClip(
    String miniAppId, {
    Map<String, dynamic>? payload,
  }) async {
    final baseUrl = widget.baseUrl;
    final id = miniAppId.trim().toLowerCase();
    if (id.isEmpty) return;
    switch (id) {
      case 'payments':
      case 'alias':
      case 'merchant':
        try {
          final sp = await SharedPreferences.getInstance();
          final walletId = sp.getString('wallet_id') ?? '';
          final devId = await CallSignalingClient.loadDeviceId();
          String? contextLabel;
          final p = payload;
          if (p != null) {
            final rawLabel = p['label'];
            if (rawLabel is String && rawLabel.trim().isNotEmpty) {
              contextLabel = rawLabel.trim();
            }
          }
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentsPage(
                baseUrl,
                walletId,
                devId ?? 'device',
                initialSection: _initialSectionFromPayload(payload),
                contextLabel: contextLabel,
              ),
            ),
          );
        } catch (_) {}
        return;
      default:
        String walletId = '';
        String deviceId = '';
        try {
          final sp = await SharedPreferences.getInstance();
          walletId = sp.getString('wallet_id') ?? '';
          deviceId = await CallSignalingClient.loadDeviceId() ?? '';
        } catch (_) {}
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MiniProgramPage(
              id: id,
              baseUrl: baseUrl,
              walletId: walletId,
              deviceId: deviceId,
              onOpenMod: (next) => unawaited(_openMiniAppFromClip(next)),
            ),
          ),
        );
        return;
    }
  }

  Widget _buildInsightsBanner(
    L10n l,
    ThemeData theme, {
    required int clipCount,
    required int totalViews,
    required int totalLikes,
    required int totalComments,
    required int servicesCount,
    required int hotServicesCount,
    required int hotClipsCount,
  }) {
    final isArabic = l.isArabic;
    final hasOfficial = (widget.officialAccountId ?? '').trim().isNotEmpty;
    final titleText = () {
      if (hasOfficial) {
        return isArabic
            ? 'تحليلات القناة لهذا الحساب'
            : 'Channel insights for this account';
      }
      return isArabic ? 'نظرة عامة على القنوات' : 'Channels overview';
    }();

    Widget pill(String label, IconData icon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: theme.colorScheme.primary.withValues(alpha: .85)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .8),
              ),
            ),
          ],
        ),
      );
    }

    final pills = <Widget>[
      pill(
        isArabic ? 'المقاطع: $clipCount' : 'Clips: $clipCount',
        Icons.play_circle_outline,
      ),
    ];
    pills.add(
      pill(
        isArabic ? 'المشاهدات: $totalViews' : 'Views: $totalViews',
        Icons.remove_red_eye_outlined,
      ),
    );
    if (clipCount > 0 && totalViews > 0) {
      final avgViews = (totalViews / clipCount).toStringAsFixed(1);
      pills.add(
        pill(
          isArabic
              ? 'متوسط المشاهدات/مقطع: $avgViews'
              : 'Avg views/clip: $avgViews',
          Icons.trending_up_outlined,
        ),
      );
    }
    if (totalLikes > 0 || totalComments > 0) {
      final label = isArabic
          ? 'الإعجابات: $totalLikes · التعليقات: $totalComments'
          : 'Likes: $totalLikes · Comments: $totalComments';
      pills.add(
        pill(
          label,
          Icons.favorite_border,
        ),
      );
    }
    if (!hasOfficial && servicesCount > 0) {
      pills.add(
        pill(
          isArabic ? 'الحسابات: $servicesCount' : 'Accounts: $servicesCount',
          Icons.verified_user_outlined,
        ),
      );
    }
    if (hotServicesCount > 0 || hotClipsCount > 0) {
      if (!hasOfficial && hotServicesCount > 0) {
        pills.add(
          pill(
            isArabic
                ? 'خدمات رائجة في اللحظات: $hotServicesCount'
                : 'Hot in Moments: $hotServicesCount services',
            Icons.local_fire_department_outlined,
          ),
        );
      } else if (hasOfficial && hotClipsCount > 0) {
        pills.add(
          pill(
            isArabic
                ? 'مقاطع رائجة في اللحظات: $hotClipsCount'
                : 'Hot in Moments: $hotClipsCount clips',
            Icons.local_fire_department_outlined,
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: .04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insights_outlined,
                size: 18,
                color: theme.colorScheme.primary.withValues(alpha: .9),
              ),
              const SizedBox(width: 6),
              Text(
                titleText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: pills,
          ),
        ],
      ),
    );
  }

  String? _initialSectionFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final rawSection = (payload['section'] ?? '').toString().trim();
    if (rawSection.isEmpty) return null;
    return rawSection;
  }

  String _labelForCategory(String raw, L10n l) {
    final key = raw.toLowerCase();
    if (key.isEmpty) return raw;
    if (l.isArabic) {
      switch (key) {
        case 'transport':
          return 'التنقل والنقل';
        case 'payments':
          return 'المحفظة والمدفوعات';
        default:
          return raw;
      }
    } else {
      switch (key) {
        case 'transport':
          return 'Transport';
        case 'payments':
          return 'Wallet & payments';
        default:
          return raw;
      }
    }
  }

  Future<void> _showClipInsights(
    BuildContext context,
    Map<String, dynamic> raw, {
    DateTime? ts,
  }) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isAr = l.isArabic;
    final itemId = (raw['id'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString();
    final snippet = (raw['snippet'] ?? '').toString();
    final likesRaw = raw['likes'];
    final viewsRaw = raw['views'];
    final commentsRaw = raw['comments'];
    final likes = likesRaw is num ? likesRaw.toInt() : 0;
    final views = viewsRaw is num ? viewsRaw.toInt() : 0;
    final comments = commentsRaw is num ? commentsRaw.toInt() : 0;
    final typeRaw =
        (raw['item_type'] ?? raw['type'] ?? '').toString().toLowerCase();
    final isLiveClip = typeRaw == 'live';
    final isHot = (raw['official_is_hot'] as bool?) ?? false;
    int sharesTotal = 0;
    int shares30d = 0;
    int uniqTotal = 0;
    int uniq30d = 0;
    int activeDays = 0;
    int peakShares = 0;
    try {
      if (itemId.isNotEmpty) {
        final uri = Uri.parse(
          '${widget.baseUrl}/channels/${Uri.encodeComponent(itemId)}/moments_stats',
        );
        final r = await http
            .get(uri, headers: await _hdrChannels(baseUrl: widget.baseUrl))
            .timeout(_channelsRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          if (decoded is Map) {
            final m = decoded.cast<String, dynamic>();
            final st = m['shares_total'];
            final s30 = m['shares_30d'];
            final ut = m['unique_sharers_total'];
            final u30 = m['unique_sharers_30d'];
            if (st is num) sharesTotal = st.toInt();
            if (s30 is num) shares30d = s30.toInt();
            if (ut is num) uniqTotal = ut.toInt();
            if (u30 is num) uniq30d = u30.toInt();
            final series = m['series_30d'];
            if (series is List) {
              for (final e in series) {
                if (e is! Map) continue;
                final mm = e.cast<String, dynamic>();
                final valRaw = mm['shares'];
                final val = valRaw is num ? valRaw.toInt() : 0;
                if (val > 0) {
                  activeDays += 1;
                  if (val > peakShares) peakShares = val;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    final createdLabel = () {
      if (ts == null) return isAr ? 'غير معروف' : 'Unknown';
      final now = DateTime.now().toUtc();
      final diff = now.difference(ts);
      if (diff.inDays < 1) {
        return isAr ? 'اليوم' : 'Today';
      }
      if (diff.inDays < 7) {
        return isAr ? 'آخر ٧ أيام' : 'Last 7 days';
      }
      if (diff.inDays < 30) {
        return isAr ? 'آخر ٣٠ يوماً' : 'Last 30 days';
      }
      return ts.toIso8601String();
    }();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.insights_outlined,
                        size: 20,
                        color: theme.colorScheme.primary.withValues(alpha: .9),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'تحليلات مقطع القناة'
                              : 'Channel clip insights',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isLiveClip)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          MiniProgramInsightChip(
                            icon: Icons.live_tv_outlined,
                            label: isAr ? 'حالة البث' : 'Live status',
                            value: isAr
                                ? 'بث مباشر (قنوات)'
                                : 'Live clip (Channels)',
                          ),
                          MiniProgramInsightChip(
                            icon: Icons.remove_red_eye_outlined,
                            label: isAr
                                ? 'مشاهدات أثناء البث'
                                : 'Views (live period)',
                            value: views > 0
                                ? views.toString()
                                : (isAr ? 'لا بيانات' : 'No data'),
                          ),
                        ],
                      ),
                    ),
                  if (title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (snippet.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        snippet,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .75),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      MiniProgramInsightChip(
                        icon: Icons.remove_red_eye_outlined,
                        label: isAr ? 'المشاهدات' : 'Views',
                        value: views > 0
                            ? views.toString()
                            : (isAr ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.favorite_border,
                        label: isAr ? 'الإعجابات' : 'Likes',
                        value: likes > 0
                            ? likes.toString()
                            : (isAr ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.mode_comment_outlined,
                        label: isAr ? 'التعليقات' : 'Comments',
                        value: comments > 0
                            ? comments.toString()
                            : (isAr ? 'لا بيانات' : 'No data'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      MiniProgramInsightChip(
                        icon: Icons.share_outlined,
                        label: isAr ? 'مشاركات في اللحظات' : 'Moments shares',
                        value: sharesTotal > 0
                            ? (isAr
                                ? '$sharesTotal (٣٠ي: $shares30d)'
                                : '$sharesTotal (30d: $shares30d)')
                            : (isAr ? 'لا بيانات' : 'No data'),
                      ),
                      MiniProgramInsightChip(
                        icon: Icons.group_outlined,
                        label: isAr ? 'مستخدمون فريدون' : 'Unique sharers',
                        value: uniqTotal > 0
                            ? (isAr
                                ? '$uniqTotal (٣٠ي: $uniq30d)'
                                : '$uniqTotal (30d: $uniq30d)')
                            : (isAr ? 'لا بيانات' : 'No data'),
                      ),
                      if (activeDays > 0)
                        MiniProgramInsightChip(
                          icon: Icons.calendar_today_outlined,
                          label: isAr
                              ? 'أيام نشطة (٣٠ يوماً)'
                              : 'Active days (30d)',
                          value: activeDays.toString(),
                        ),
                      if (peakShares > 0)
                        MiniProgramInsightChip(
                          icon: Icons.trending_up_outlined,
                          label:
                              isAr ? 'أعلى مشاركات في يوم' : 'Peak shares/day',
                          value: peakShares.toString(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      MiniProgramInsightChip(
                        icon: Icons.schedule_outlined,
                        label: isAr ? 'الفترة' : 'Time window',
                        value: createdLabel,
                      ),
                      if (isHot)
                        MiniProgramInsightChip(
                          icon: Icons.local_fire_department_outlined,
                          label: isAr ? 'رائج في اللحظات' : 'Hot in Moments',
                          value: isAr ? 'نعم' : 'Yes',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAr
                        ? 'هذه الأرقام تقريبية وتعكس تطور هذا المقطع في القنوات واللحظات، على غرار لوحة منشئي المحتوى في Shamell Channels.'
                        : 'Numbers are approximate and reflect how this clip performs in Channels and Moments, similar to creator analytics in Shamell Channels.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (itemId.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: Text(
                          isAr
                              ? 'عرض اللحظات لهذا المقطع'
                              : 'View Moments for this clip',
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          final tag = '#ch_${itemId.toLowerCase()}';
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MomentsPage(
                                baseUrl: widget.baseUrl,
                                topicTag: tag,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
