import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'mini_app_registry.dart';
import 'mini_program_models.dart';
import 'moments_page.dart';
import 'wechat_ui.dart';
import 'wechat_webview_page.dart';
import '../mini_apps/payments/payments_shell.dart';

Future<Map<String, String>> _hdrMiniProgram({bool json = false}) async {
  final headers = <String, String>{};
  if (json) {
    headers['content-type'] = 'application/json';
  }
  try {
    final sp = await SharedPreferences.getInstance();
    final cookie = sp.getString('sa_cookie') ?? '';
    if (cookie.isNotEmpty) {
      headers['sa_cookie'] = cookie;
    }
  } catch (_) {}
  return headers;
}

/// Simple shell widget that renders a Mini‑Program manifest.
///
/// Lädt Titel/Beschreibung/Aktionen primär per API aus
/// `/mini_programs/<id>` und nutzt die lokale Library nur noch als
/// Fallback für eingebaute Demo‑Programme.
class MiniProgramPage extends StatefulWidget {
  final String id;
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final void Function(String modId)? onOpenMod;

  const MiniProgramPage({
    super.key,
    required this.id,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    this.onOpenMod,
  });

  @override
  State<MiniProgramPage> createState() => _MiniProgramPageState();
}

class _MiniProgramPageState extends State<MiniProgramPage> {
  MiniProgramManifest? _localManifest;
  String? _remoteTitleEn;
  String? _remoteTitleAr;
  String? _remoteDescEn;
  String? _remoteDescAr;
  double? _remoteRating;
  int _remoteRatingCount = 0;
  List<MiniProgramAction>? _remoteActions;
  bool _loading = false;
  bool _remoteLoaded = false;
  String? _ownerName;
  String? _status;
  String? _reviewStatus;
  bool _isMine = false;
  List<String> _scopes = const <String>[];
  int _momentsSharesTotal = 0;
  int _momentsShares30d = 0;
  int _momentsUniqueSharersTotal = 0;
  int _momentsUniqueSharers30d = 0;
  String? _ownerContact;
  bool _pinned = false;
  bool _wechatMiniProgramUi = true;

  bool get _hasPaymentsScope {
    final scopesLower = _scopes.map((s) => s.toLowerCase()).toList();
    return scopesLower.contains('payments') ||
        scopesLower.contains('pay') ||
        scopesLower.contains('wallet');
  }

  bool get _canExecuteActions {
    if (_isMine) return true;
    final status = (_status ?? '').trim().toLowerCase();
    final review = (_reviewStatus ?? '').trim().toLowerCase();
    if (status.isNotEmpty && status != 'active') return false;
    if (review.isNotEmpty && review != 'approved') return false;
    return true;
  }

  bool _requiresPaymentsScopeForMod(String modId) {
    final id = modId.trim().toLowerCase();
    return id == 'payments' || id == 'merchant' || id == 'alias';
  }

  @override
  void initState() {
    super.initState();
    _localManifest = MiniAppRegistry.localManifestById(widget.id);
    _loadRemoteMeta();
    _loadMomentsStats();
    _loadPinnedFlag();
    _trackOpen();
  }

  Future<void> _loadPinnedFlag() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ids = sp.getStringList('pinned_miniapps') ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _pinned = ids
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .contains(widget.id);
      });
    } catch (_) {}
  }

  Future<void> _togglePinned() async {
    try {
      final sp = await SharedPreferences.getInstance();
      const pinnedKey = 'pinned_miniapps';
      const orderKey = 'mini_programs.pinned_order';
      final curPinnedRaw = sp.getStringList(pinnedKey) ?? const <String>[];
      final pinnedList = <String>[];
      final pinnedSet = <String>{};
      for (final raw in curPinnedRaw) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        if (pinnedSet.add(id)) pinnedList.add(id);
      }
      final isPinned = pinnedSet.contains(widget.id);
      pinnedList.removeWhere((e) => e == widget.id);
      if (!isPinned) {
        pinnedList.insert(0, widget.id);
      }
      await sp.setStringList(pinnedKey, pinnedList);

      final curOrderRaw = sp.getStringList(orderKey) ?? const <String>[];
      final orderList = <String>[];
      final orderSet = <String>{};
      for (final raw in curOrderRaw) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        if (orderSet.add(id)) orderList.add(id);
      }
      orderList.removeWhere((e) => e == widget.id);
      if (!isPinned) {
        orderList.insert(0, widget.id);
      }
      final nextOrder = orderList.where(pinnedList.contains).toList();
      await sp.setStringList(orderKey, nextOrder);
      if (!mounted) return;
      setState(() {
        _pinned = !isPinned;
      });
    } catch (_) {}
  }

  Future<void> _trackOpen() async {
    // Track open both server-side (usage_score, analytics) and
    // client-side for a small "recently used" list in Discover.
    _trackRecentLocally();
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(widget.id)}/track_open');
      await http.post(uri);
    } catch (_) {
      // best-effort only
    }
  }

  Future<void> _trackRecentLocally() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final key = 'recent_mini_programs';
      final cur = sp.getStringList(key) ?? const <String>[];
      final list = List<String>.from(cur);
      list.removeWhere((e) => e == widget.id);
      list.insert(0, widget.id);
      if (list.length > 10) {
        list.removeRange(10, list.length);
      }
      await sp.setStringList(key, list);
    } catch (_) {}
  }

  Future<void> _loadRemoteMeta() async {
    setState(() {
      _loading = true;
      _remoteLoaded = false;
    });
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(widget.id)}');
      final resp = await http.get(uri);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          final titleEnRaw = (decoded['title_en'] ?? '').toString();
          final titleArRaw = (decoded['title_ar'] ?? '').toString();
          final descEnRaw = (decoded['description_en'] ?? '').toString();
          final descArRaw = (decoded['description_ar'] ?? '').toString();
          final ratingRaw = decoded['rating'];
          final ratingCountRaw = decoded['rating_count'];
          final ownerNameRaw = (decoded['owner_name'] ?? '').toString();
          final ownerContactRaw = (decoded['owner_contact'] ?? '').toString();
          final statusRaw = (decoded['status'] ?? '').toString().toLowerCase();
          final reviewStatusRaw =
              (decoded['review_status'] ?? '').toString().toLowerCase();
          final scopesRaw = decoded['scopes'];
          double? rating;
          int ratingCount = 0;
          if (ratingRaw is num) {
            rating = ratingRaw.toDouble();
          }
          if (ratingCountRaw is num) {
            ratingCount = ratingCountRaw.toInt();
          }

          List<MiniProgramAction>? actions;
          final rawActions = decoded['actions'];
          if (rawActions is List) {
            actions = <MiniProgramAction>[];
            for (final e in rawActions) {
              if (e is! Map) continue;
              final map = e.cast<String, dynamic>();
              final id = (map['id'] ?? '').toString().trim();
              final labelEn = (map['label_en'] ?? '').toString();
              final labelAr = (map['label_ar'] ?? '').toString();
              if (id.isEmpty || labelEn.isEmpty) continue;
              final kindStr = (map['kind'] ?? '').toString().toLowerCase();
              MiniProgramActionKind kind;
              switch (kindStr) {
                case 'close':
                  kind = MiniProgramActionKind.close;
                  break;
                case 'open_url':
                  kind = MiniProgramActionKind.openUrl;
                  break;
                case 'open_mod':
                default:
                  kind = MiniProgramActionKind.openMod;
                  break;
              }
              final modIdRaw = (map['mod_id'] ?? '').toString().trim();
              final urlRaw = (map['url'] ?? '').toString().trim();
              actions.add(
                MiniProgramAction(
                  id: id,
                  labelEn: labelEn,
                  labelAr: labelAr.isNotEmpty ? labelAr : labelEn,
                  kind: kind,
                  modId: modIdRaw.isNotEmpty ? modIdRaw : null,
                  url: urlRaw.isNotEmpty ? urlRaw : null,
                ),
              );
            }
            if (actions.isEmpty) {
              actions = null;
            }
          }

          final scopes = <String>[];
          if (scopesRaw is List) {
            for (final s in scopesRaw) {
              final v = (s ?? '').toString().trim();
              if (v.isEmpty) continue;
              scopes.add(v);
            }
          }

          String? myPhone;
          try {
            final sp = await SharedPreferences.getInstance();
            myPhone = sp.getString('phone');
          } catch (_) {}
          final ownerContactClean = ownerContactRaw.trim();
          final isMine = myPhone != null &&
              myPhone.trim().isNotEmpty &&
              ownerContactClean.isNotEmpty &&
              myPhone.trim() == ownerContactClean;

          if (!mounted) return;
          setState(() {
            _remoteTitleEn = titleEnRaw.trim().isNotEmpty ? titleEnRaw : null;
            _remoteTitleAr = titleArRaw.trim().isNotEmpty ? titleArRaw : null;
            _remoteDescEn = descEnRaw.trim().isNotEmpty ? descEnRaw : null;
            _remoteDescAr = descArRaw.trim().isNotEmpty ? descArRaw : null;
            _remoteRating = rating;
            _remoteRatingCount = ratingCount;
            _remoteActions = actions;
            _ownerName =
                ownerNameRaw.trim().isNotEmpty ? ownerNameRaw.trim() : null;
            _status = statusRaw.isNotEmpty ? statusRaw : null;
            _reviewStatus = reviewStatusRaw.isNotEmpty ? reviewStatusRaw : null;
            _isMine = isMine;
            _scopes = scopes;
            _ownerContact =
                ownerContactClean.isNotEmpty ? ownerContactClean : null;
            _remoteLoaded = true;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _remoteLoaded = true;
          });
        }
      } else if (resp.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _remoteLoaded = true;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _remoteLoaded = true;
        });
      }
    } catch (_) {
      // best-effort only
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMomentsStats() async {
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(widget.id)}/moments_stats');
      final resp = await http.get(uri, headers: await _hdrMiniProgram());
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return;
      if (!mounted) return;
      setState(() {
        final m = decoded.cast<String, dynamic>();
        final t = m['shares_total'];
        final s30 = m['shares_30d'];
        final u = m['unique_sharers_total'];
        final u30 = m['unique_sharers_30d'];
        if (t is num) _momentsSharesTotal = t.toInt();
        if (s30 is num) _momentsShares30d = s30.toInt();
        if (u is num) _momentsUniqueSharersTotal = u.toInt();
        if (u30 is num) _momentsUniqueSharers30d = u30.toInt();
      });
    } catch (_) {}
  }

  Future<void> _sendRating(BuildContext context, int value) async {
    final l = L10n.of(context);
    final val = value.clamp(1, 5);
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(widget.id)}/rate');
      final body = jsonEncode({'rating': val});
      final resp = await http.post(uri,
          headers: await _hdrMiniProgram(json: true), body: body);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تم تسجيل تقييمك لهذا البرنامج المصغر.'
                  : 'Your rating for this mini‑program has been recorded.',
            ),
          ),
        );
        // best-effort refresh of remote meta to update average.
        // ignore: discarded_futures
        _loadRemoteMeta();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final manifest = _localManifest;
    final theme = Theme.of(context);
    final hasRemoteMeta =
        (_remoteTitleEn != null && _remoteTitleEn!.trim().isNotEmpty) ||
            (_remoteTitleAr != null && _remoteTitleAr!.trim().isNotEmpty) ||
            (_remoteDescEn != null && _remoteDescEn!.trim().isNotEmpty) ||
            (_remoteDescAr != null && _remoteDescAr!.trim().isNotEmpty) ||
            (_remoteActions != null && _remoteActions!.isNotEmpty);

    if (manifest == null && !hasRemoteMeta) {
      if (_loading && !_remoteLoaded) {
        return Scaffold(
          appBar: AppBar(
            title: Text(l.isArabic ? 'برنامج مصغر' : 'Mini‑program'),
          ),
          body: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(l.isArabic ? 'برنامج مصغر' : 'Mini‑program'),
        ),
        body: Center(
          child: Text(
            l.isArabic
                ? 'تعذّر العثور على هذا البرنامج المصغر.'
                : 'Mini‑program not found.',
          ),
        ),
      );
    }

    final isArabic = l.isArabic;
    final title = () {
      final remoteTitle = isArabic ? _remoteTitleAr : _remoteTitleEn;
      if (remoteTitle != null && remoteTitle.trim().isNotEmpty) {
        return remoteTitle.trim();
      }
      if (manifest != null) {
        return manifest.title(isArabic: isArabic);
      }
      return widget.id;
    }();
    final description = () {
      final remoteDesc = isArabic ? _remoteDescAr : _remoteDescEn;
      if (remoteDesc != null && remoteDesc.trim().isNotEmpty) {
        return remoteDesc.trim();
      }
      if (manifest != null) {
        return manifest.description(isArabic: isArabic);
      }
      return '';
    }();
    final actions = () {
      if (_remoteActions != null && _remoteActions!.isNotEmpty) {
        return _remoteActions!;
      }
      if (manifest != null) {
        return manifest.actions;
      }
      return const <MiniProgramAction>[];
    }();
    String avatarInitial = '';
    final trimmedTitle = title.trim();
    if (trimmedTitle.isNotEmpty) {
      avatarInitial = trimmedTitle[0].toUpperCase();
    } else {
      final idTrim = widget.id.trim();
      if (idTrim.isNotEmpty) {
        avatarInitial = idTrim[0].toUpperCase();
      }
    }
    final bool hasPaymentsScope = _hasPaymentsScope;

    if (_wechatMiniProgramUi) {
      final isDark = theme.brightness == Brightness.dark;
      final Color bgColor =
          isDark ? theme.colorScheme.surface : WeChatPalette.background;

      Icon chevron() => Icon(
            isArabic ? Icons.chevron_left : Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: .40),
          );

      Widget pill(
        String text, {
        required Color background,
        required Color foreground,
        IconData? icon,
      }) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }

      final idLower = widget.id.trim().toLowerCase();
      IconData appIcon = Icons.widgets_outlined;
      Color appBg = theme.colorScheme.primary;
      Color appFg = Colors.white;
      if (idLower.contains('pay') ||
          idLower.contains('wallet') ||
          idLower.contains('payment')) {
        appIcon = Icons.account_balance_wallet_outlined;
        appBg = Tokens.colorPayments;
        appFg = Colors.white;
      } else if (idLower.contains('bus') ||
          idLower.contains('ride') ||
          idLower.contains('mobility') ||
          idLower.contains('transport')) {
        appIcon = Icons.directions_bus_filled_outlined;
        appBg = Tokens.colorBus;
        appFg = Colors.white;
      }

      Widget appAvatar() {
        final showLetter =
            appIcon == Icons.widgets_outlined && avatarInitial.isNotEmpty;
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: appBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: showLetter
                ? Text(
                    avatarInitial,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: appFg,
                    ),
                  )
                : Icon(appIcon, size: 24, color: appFg),
          ),
        );
      }

      String statusLabel(String s) {
        final clean = s.trim().toLowerCase();
        if (clean == 'active') return isArabic ? 'نشط' : 'Active';
        if (clean == 'draft') return isArabic ? 'مسودة' : 'Draft';
        return s;
      }

      String reviewLabel(String r) {
        final clean = r.trim().toLowerCase();
        if (clean == 'approved') return isArabic ? 'موافق عليه' : 'Approved';
        if (clean == 'submitted')
          return isArabic ? 'قيد المراجعة' : 'In review';
        if (clean == 'draft') return isArabic ? 'مسودة' : 'Draft';
        if (clean == 'rejected') return isArabic ? 'مرفوض' : 'Rejected';
        if (clean == 'suspended') return isArabic ? 'موقوف' : 'Suspended';
        return r;
      }

      final List<Widget> actionTiles = <Widget>[];
      final canPay = hasPaymentsScope &&
          _ownerContact != null &&
          _ownerContact!.trim().isNotEmpty;
      if (canPay) {
        actionTiles.add(
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.account_balance_wallet_outlined,
              background: Tokens.colorPayments,
            ),
            title: Text(isArabic ? 'الدفع' : 'Pay'),
            subtitle: Text(
              _ownerName != null && _ownerName!.trim().isNotEmpty
                  ? _ownerName!.trim()
                  : (isArabic
                      ? 'ادفع داخل هذا البرنامج المصغّر'
                      : 'Pay inside this mini‑program'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: chevron(),
            onTap: _canExecuteActions
                ? () => _openMiniProgramPaySheet(context)
                : null,
          ),
        );
      }

      for (final a in actions) {
        IconData icon;
        Color bg;
        switch (a.kind) {
          case MiniProgramActionKind.openUrl:
            icon = Icons.link_outlined;
            bg = const Color(0xFF3B82F6);
            break;
          case MiniProgramActionKind.close:
            icon = Icons.close;
            bg = const Color(0xFF94A3B8);
            break;
          case MiniProgramActionKind.openMod:
          default:
            icon = Icons.widgets_outlined;
            bg = WeChatPalette.green;
            break;
        }
        final allow =
            _canExecuteActions || a.kind == MiniProgramActionKind.close;
        actionTiles.add(
          ListTile(
            dense: true,
            leading: WeChatLeadingIcon(icon: icon, background: bg),
            title: Text(a.label(isArabic: isArabic)),
            trailing: chevron(),
            onTap: allow ? () => _handleAction(context, a) : null,
          ),
        );
      }

      final List<Widget> infoTiles = <Widget>[
        ListTile(
          dense: true,
          leading: const WeChatLeadingIcon(
            icon: Icons.star_outline,
            background: Color(0xFFF59E0B),
          ),
          title: Text(isArabic ? 'التقييم' : 'Rating'),
          subtitle: Text(
            (_remoteRating != null && (_remoteRating ?? 0) > 0)
                ? (_remoteRatingCount > 0
                    ? '${_remoteRating!.toStringAsFixed(1)} (${_remoteRatingCount})'
                    : _remoteRating!.toStringAsFixed(1))
                : (isArabic
                    ? 'قيّم هذا البرنامج المصغّر'
                    : 'Rate this mini‑program'),
          ),
          trailing: chevron(),
          onTap: () => _showRatingSheet(context),
        ),
      ];

      if (_scopes.isNotEmpty) {
        final scopesLabel =
            _scopes.map((s) => _scopeLabel(s, isArabic)).join(' · ');
        infoTiles.add(
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.verified_user_outlined,
              background: Color(0xFF64748B),
            ),
            title: Text(isArabic ? 'الأذونات' : 'Permissions'),
            subtitle: Text(
              scopesLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }

      if (_momentsSharesTotal > 0 || _momentsShares30d > 0) {
        final total = _momentsSharesTotal;
        final s30 = _momentsShares30d;
        final u = _momentsUniqueSharersTotal;
        final u30 = _momentsUniqueSharers30d;
        final impact = () {
          if (isArabic) {
            var base = 'الأثر في اللحظات: تمت مشاركة هذا البرنامج $total مرة';
            final parts = <String>[];
            if (s30 > 0) parts.add('في آخر ٣٠ يوماً: $s30 مشاركة');
            if (u > 0 || u30 > 0) {
              final inner = <String>[];
              if (u > 0) inner.add('$u مستخدمين فريدين');
              if (u30 > 0) inner.add('$u30 في آخر ٣٠ يوماً');
              parts.add(inner.join(' · '));
            }
            if (parts.isNotEmpty) base = '$base · ${parts.join(' · ')}';
            return base;
          }
          var base = 'Moments impact: shared $total times';
          final parts = <String>[];
          if (s30 > 0) parts.add('$s30 shares in the last 30 days');
          if (u > 0 || u30 > 0) {
            final inner = <String>[];
            if (u > 0) inner.add('$u unique sharers');
            if (u30 > 0) inner.add('$u30 in the last 30 days');
            parts.add(inner.join(' · '));
          }
          if (parts.isNotEmpty) base = '$base · ${parts.join(' · ')}';
          return base;
        }();
        infoTiles.add(
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.insights_outlined,
              background: Color(0xFF3B82F6),
            ),
            title: Text(isArabic ? 'أثر اللحظات' : 'Moments impact'),
            subtitle: Text(
              impact,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }

      final List<Widget> momentsTiles = <Widget>[
        ListTile(
          dense: true,
          leading: const WeChatLeadingIcon(
            icon: Icons.tag_outlined,
            background: Color(0xFFF97316),
          ),
          title: Text(isArabic ? 'لحظات هذا البرنامج' : 'Moments topic'),
          trailing: chevron(),
          onTap: () => _openMiniProgramTopic(context),
        ),
        ListTile(
          dense: true,
          leading: const WeChatLeadingIcon(
            icon: Icons.share_outlined,
            background: WeChatPalette.green,
          ),
          title: Text(isArabic ? 'مشاركة في اللحظات' : 'Share to Moments'),
          trailing: chevron(),
          onTap: () => _shareToMoments(context, title, description),
        ),
      ];

      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: Icon(_pinned ? Icons.star : Icons.star_border),
              tooltip: isArabic
                  ? (_pinned ? 'إزالة من المفضّلة' : 'تثبيت البرنامج المصغّر')
                  : (_pinned ? 'Unpin mini‑program' : 'Pin mini‑program'),
              onPressed: _togglePinned,
            ),
            PopupMenuButton<String>(
              tooltip: isArabic ? 'المزيد' : 'More',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) async {
                switch (value) {
                  case 'rate':
                    _showRatingSheet(context);
                    return;
                  case 'topic':
                    await _openMiniProgramTopic(context);
                    return;
                  case 'share':
                    await _shareToMoments(context, title, description);
                    return;
                  case 'refresh':
                    await _loadRemoteMeta();
                    await _loadMomentsStats();
                    await _loadPinnedFlag();
                    return;
                  case 'pay':
                    if (canPay && _canExecuteActions) {
                      await _openMiniProgramPaySheet(context);
                    }
                    return;
                }
              },
              itemBuilder: (ctx) {
                final items = <PopupMenuEntry<String>>[];
                if (canPay) {
                  items.add(
                    PopupMenuItem<String>(
                      value: 'pay',
                      child: Text(isArabic ? 'الدفع' : 'Pay'),
                    ),
                  );
                }
                items.addAll([
                  PopupMenuItem<String>(
                    value: 'share',
                    child: Text(
                        isArabic ? 'مشاركة في اللحظات' : 'Share to Moments'),
                  ),
                  PopupMenuItem<String>(
                    value: 'topic',
                    child:
                        Text(isArabic ? 'لحظات هذا البرنامج' : 'Moments topic'),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem<String>(
                    value: 'rate',
                    child: Text(isArabic ? 'تقييم' : 'Rate'),
                  ),
                  PopupMenuItem<String>(
                    value: 'refresh',
                    child: Text(isArabic ? 'تحديث' : 'Refresh'),
                  ),
                ]);
                return items;
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await _loadRemoteMeta();
            await _loadMomentsStats();
            await _loadPinnedFlag();
          },
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              WeChatSection(
                margin: const EdgeInsets.only(top: 0),
                dividerIndent: 16,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: appAvatar(),
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .80),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            pill(
                              isArabic ? 'برنامج مصغر' : 'Mini Program',
                              background: WeChatPalette.searchFill,
                              foreground: WeChatPalette.textSecondary,
                            ),
                            if (hasPaymentsScope)
                              pill(
                                isArabic ? 'يدعم الدفع' : 'Pay‑enabled',
                                background:
                                    Tokens.colorPayments.withValues(alpha: .12),
                                foreground: Tokens.colorPayments,
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                            if (_status != null && _status!.trim().isNotEmpty)
                              pill(
                                statusLabel(_status!),
                                background: theme.colorScheme.primary
                                    .withValues(alpha: .10),
                                foreground: theme.colorScheme.primary
                                    .withValues(alpha: .90),
                              ),
                            if (_reviewStatus != null &&
                                _reviewStatus!.trim().isNotEmpty)
                              pill(
                                reviewLabel(_reviewStatus!),
                                background: (_reviewStatus == 'approved')
                                    ? Colors.green.withValues(alpha: .10)
                                    : theme.colorScheme.error
                                        .withValues(alpha: .08),
                                foreground: (_reviewStatus == 'approved')
                                    ? Colors.green.withValues(alpha: .90)
                                    : theme.colorScheme.error
                                        .withValues(alpha: .90),
                              ),
                          ],
                        ),
                        if (_isMine ||
                            (_ownerName != null &&
                                _ownerName!.trim().isNotEmpty)) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                _isMine
                                    ? Icons.person_outline
                                    : Icons.storefront_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isMine
                                      ? (isArabic
                                          ? 'أنت (المالك)'
                                          : 'You (owner)')
                                      : (isArabic
                                          ? 'المالك: ${_ownerName!}'
                                          : 'Owner: ${_ownerName!}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .75),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (!_canExecuteActions && actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: .18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isArabic
                                ? 'هذا البرنامج غير متاح حالياً (يلزم Active + Approved).'
                                : 'This mini‑program is not available yet (requires Active + Approved).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (actionTiles.isNotEmpty) WeChatSection(children: actionTiles),
              if (infoTiles.isNotEmpty) WeChatSection(children: infoTiles),
              WeChatSection(children: momentsTiles),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              _pinned ? Icons.star : Icons.star_border,
            ),
            tooltip: isArabic
                ? (_pinned ? 'إزالة من المفضّلة' : 'تثبيت البرنامج المصغّر')
                : (_pinned ? 'Unpin mini‑program' : 'Pin mini‑program'),
            onPressed: _togglePinned,
          ),
          if (hasPaymentsScope &&
              _ownerContact != null &&
              _ownerContact!.trim().isNotEmpty)
            IconButton(
              icon: const Icon(Icons.payment_outlined),
              tooltip: isArabic
                  ? 'دفع داخل هذا البرنامج'
                  : 'Pay in this mini‑program',
              onPressed: _canExecuteActions
                  ? () => _openMiniProgramPaySheet(context)
                  : null,
            ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: isArabic ? 'مشاركة في اللحظات' : 'Share to Moments',
            onPressed: () => _shareToMoments(context, title, description),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: .25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: .03),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: avatarInitial.isNotEmpty
                                ? Text(
                                    avatarInitial,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: .95),
                                    ),
                                  )
                                : Icon(
                                    Icons.widgets_outlined,
                                    size: 24,
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: .90),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .80),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface
                                          .withValues(alpha: .06),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      isArabic ? 'برنامج مصغر' : 'Mini‑program',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        fontSize: 10,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .75),
                                      ),
                                    ),
                                  ),
                                  if (hasPaymentsScope) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: .06),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons
                                                .account_balance_wallet_outlined,
                                            size: 12,
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: .85),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isArabic
                                                ? 'يدعم الدفع'
                                                : 'Pay‑enabled',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontSize: 10,
                                              color: theme.colorScheme.primary
                                                  .withValues(alpha: .85),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if ((_remoteRating ?? 0.0) > 0) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.star,
                                      size: 14,
                                      color:
                                          Colors.amber.withValues(alpha: .95),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      (_remoteRating ?? 0.0).toStringAsFixed(1),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (_remoteRatingCount > 0) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '(${_remoteRatingCount})',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          fontSize: 10,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: .65),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_ownerName != null ||
                        _status != null ||
                        _reviewStatus != null ||
                        _isMine) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isMine) ...[
                            const Icon(Icons.person_outline, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              isArabic ? 'أنت (المالك)' : 'You (owner)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ] else if (_ownerName != null) ...[
                            const Icon(Icons.storefront_outlined, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              isArabic
                                  ? 'المالك: ${_ownerName!}'
                                  : 'Owner: ${_ownerName!}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (_status != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                () {
                                  final s = _status!;
                                  if (s == 'active') {
                                    return isArabic ? 'نشط' : 'Active';
                                  }
                                  if (s == 'draft') {
                                    return isArabic ? 'مسودة' : 'Draft';
                                  }
                                  return s;
                                }(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: .85),
                                ),
                              ),
                            ),
                          ],
                          if (_reviewStatus != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (_reviewStatus == 'approved')
                                    ? Colors.green.withValues(alpha: .10)
                                    : theme.colorScheme.error
                                        .withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                () {
                                  final r = _reviewStatus!;
                                  if (r == 'approved') {
                                    return isArabic ? 'موافق عليه' : 'Approved';
                                  }
                                  if (r == 'submitted') {
                                    return isArabic
                                        ? 'قيد المراجعة'
                                        : 'In review';
                                  }
                                  if (r == 'draft') {
                                    return isArabic ? 'مسودة' : 'Draft';
                                  }
                                  if (r == 'rejected') {
                                    return isArabic ? 'مرفوض' : 'Rejected';
                                  }
                                  if (r == 'suspended') {
                                    return isArabic ? 'موقوف' : 'Suspended';
                                  }
                                  return r;
                                }(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: (_reviewStatus == 'approved')
                                      ? Colors.green.withValues(alpha: .90)
                                      : theme.colorScheme.error
                                          .withValues(alpha: .90),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 12),
              if (_remoteRating != null && _remoteRating! > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        onPressed: () => _sendRating(context, i),
                        icon: Icon(
                          i <= _remoteRating!.round()
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber.withValues(alpha: .95),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _remoteRatingCount > 0
                          ? '${_remoteRating!.toStringAsFixed(1)} · $_remoteRatingCount'
                          : _remoteRating!.toStringAsFixed(1),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: () => _sendRating(context, 5),
                      icon: Icon(
                        Icons.star_border,
                        color: Colors.amber.withValues(alpha: .95),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isArabic
                          ? 'قيّم هذا البرنامج المصغر'
                          : 'Rate this mini‑program',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              if ((_remoteRating ?? 0.0) > 0) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      size: 16,
                      color: Colors.amber.withValues(alpha: .95),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      (_remoteRating ?? 0.0).toStringAsFixed(1),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (_remoteRatingCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${_remoteRatingCount})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .65),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => _showRatingSheet(context),
                      child: Text(
                        isArabic
                            ? 'قيّم هذا البرنامج'
                            : 'Rate this mini‑program',
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _showRatingSheet(context),
                  child: Text(
                    isArabic ? 'قيّم هذا البرنامج' : 'Rate this mini‑program',
                  ),
                ),
              ],
              if (_scopes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  isArabic
                      ? 'قد يستخدم هذا البرنامج المصغر:'
                      : 'This mini‑program may use:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _scopes.map((s) {
                    final label = _scopeLabel(s, isArabic);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              theme.colorScheme.primary.withValues(alpha: .85),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 24),
              if (_momentsSharesTotal > 0 || _momentsShares30d > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.insights_outlined,
                        size: 18,
                        color: theme.colorScheme.primary.withValues(alpha: .85),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          () {
                            final total = _momentsSharesTotal;
                            final s30 = _momentsShares30d;
                            final u = _momentsUniqueSharersTotal;
                            final u30 = _momentsUniqueSharers30d;
                            if (isArabic) {
                              var base =
                                  'الأثر في اللحظات: تمت مشاركة هذا البرنامج $total مرة';
                              final parts = <String>[];
                              if (s30 > 0) {
                                parts.add('في آخر ٣٠ يوماً: $s30 مشاركة');
                              }
                              if (u > 0 || u30 > 0) {
                                final inner = <String>[];
                                if (u > 0) {
                                  inner.add('$u مستخدمين فريدين');
                                }
                                if (u30 > 0) {
                                  inner.add('$u30 في آخر ٣٠ يوماً');
                                }
                                parts.add(inner.join(' · '));
                              }
                              if (parts.isNotEmpty) {
                                base = '$base · ${parts.join(' · ')}';
                              }
                              return base;
                            } else {
                              var base = 'Moments impact: shared $total times';
                              final parts = <String>[];
                              if (s30 > 0) {
                                parts.add('$s30 shares in the last 30 days');
                              }
                              if (u > 0 || u30 > 0) {
                                final inner = <String>[];
                                if (u > 0) {
                                  inner.add('$u unique sharers');
                                }
                                if (u30 > 0) {
                                  inner.add('$u30 in the last 30 days');
                                }
                                parts.add(inner.join(' · '));
                              }
                              if (parts.isNotEmpty) {
                                base = '$base · ${parts.join(' · ')}';
                              }
                              return base;
                            }
                          }(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .80),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_canExecuteActions && actions.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: .18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isArabic
                              ? 'هذا البرنامج غير متاح حالياً (يلزم Active + Approved).'
                              : 'This mini‑program is not available yet (requires Active + Approved).',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: actions.map((a) {
                  final allow = _canExecuteActions ||
                      a.kind == MiniProgramActionKind.close;
                  return FilledButton(
                    onPressed: allow ? () => _handleAction(context, a) : null,
                    child: Text(a.label(isArabic: isArabic)),
                  );
                }).toList(),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.tag_outlined, size: 18),
                label: Text(
                  isArabic
                      ? 'لحظات هذا البرنامج'
                      : 'Moments topic for this app',
                ),
                onPressed: () => _openMiniProgramTopic(context),
              ),
              const SizedBox(height: 2),
              TextButton.icon(
                icon: const Icon(Icons.share_outlined, size: 18),
                label: Text(
                  isArabic ? 'مشاركة في اللحظات' : 'Share to Moments',
                ),
                onPressed: () => _shareToMoments(context, title, description),
              ),
              const SizedBox(height: 4),
              Text(
                isArabic
                    ? 'معاينة لبرامج مصغّرة على نمط WeChat داخل Shamell.'
                    : 'Preview of WeChat‑style mini‑programs inside Shamell.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareToMoments(
    BuildContext context,
    String title,
    String description,
  ) async {
    final l = L10n.of(context);
    final buf = StringBuffer();
    if (title.trim().isNotEmpty) {
      buf.writeln(title.trim());
    }
    if (description.trim().isNotEmpty) {
      buf.writeln();
      buf.writeln(description.trim());
    }
    buf.writeln();
    buf.writeln('shamell://mini_program/${widget.id}');
    var text = buf.toString().trim();
    if (text.isEmpty) return;
    if (!text.contains('#')) {
      final isArabic = l.isArabic;
      final serviceTag = _serviceHashtag(isArabic: isArabic);
      final baseTag = '#ShamellMiniApp';
      final mpTag = _miniProgramTopicTag();
      text += ' $baseTag';
      if (mpTag.isNotEmpty) {
        text += ' $mpTag';
      }
      if (serviceTag.isNotEmpty) {
        text += ' $serviceTag';
      }
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('moments_preset_text', text);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MomentsPage(
          baseUrl: widget.baseUrl,
        ),
      ),
    );
  }

  Future<void> _openMiniProgramTopic(BuildContext context) async {
    final tag = _miniProgramTopicTag();
    if (tag.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MomentsPage(
          baseUrl: widget.baseUrl,
          topicTag: tag,
        ),
      ),
    );
  }

  String _miniProgramTopicTag() {
    var id = widget.id.toLowerCase().trim();
    if (id.isEmpty) return '';
    // Normalize to a simple hashtag-friendly slug.
    id = id.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (id.isEmpty) return '';
    return '#mp_$id';
  }

  String _scopeLabel(String key, bool isArabic) {
    final k = key.toLowerCase();
    if (isArabic) {
      switch (k) {
        case 'location':
          return 'الموقع';
        case 'wallet':
        case 'payments':
          return 'المحفظة والمدفوعات';
        case 'transport':
          return 'التنقل والنقل';
        case 'notifications':
          return 'الإشعارات';
        case 'moments':
          return 'اللحظات';
        default:
          return key;
      }
    } else {
      switch (k) {
        case 'location':
          return 'Location';
        case 'wallet':
        case 'payments':
          return 'Wallet & payments';
        case 'transport':
          return 'Transport';
        case 'notifications':
          return 'Notifications';
        case 'moments':
          return 'Moments';
        default:
          return key;
      }
    }
  }

  String _serviceHashtag({required bool isArabic}) {
    final id = widget.id.toLowerCase();
    // Heuristics based on Mini‑Program id and common service ids.
    if (id.contains('bus') ||
        id.contains('ride') ||
        id.contains('transport') ||
        id.contains('mobility')) {
      return isArabic ? '#النقل' : '#Transport';
    }
    if (id.contains('wallet') ||
        id.contains('pay') ||
        id.contains('payment') ||
        id.contains('payments')) {
      return isArabic ? '#المحفظة' : '#Wallet';
    }
    return '';
  }

  Future<void> _handleAction(
    BuildContext context,
    MiniProgramAction action,
  ) async {
    if (!_canExecuteActions && action.kind != MiniProgramActionKind.close) {
      final l = L10n.of(context);
      final isArabic = l.isArabic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'هذا البرنامج غير متاح حالياً.'
                : 'This mini‑program is not available yet.',
          ),
        ),
      );
      return;
    }
    switch (action.kind) {
      case MiniProgramActionKind.close:
        Navigator.of(context).maybePop();
        break;
      case MiniProgramActionKind.openMod:
        final target = action.modId;
        if (target != null && widget.onOpenMod != null) {
          if (_requiresPaymentsScopeForMod(target) && !_hasPaymentsScope) {
            final l = L10n.of(context);
            final isArabic = l.isArabic;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isArabic
                      ? 'هذا الإجراء يتطلب صلاحية الدفع (Payments scope).'
                      : 'This action requires Payments permission (scope).',
                ),
              ),
            );
            return;
          }
          Navigator.of(context).maybePop();
          widget.onOpenMod!(target);
        }
        break;
      case MiniProgramActionKind.openUrl:
        final url = action.url;
        if (url == null || url.isEmpty) return;
        try {
          final parsed = Uri.tryParse(url.trim());
          if (parsed == null) return;
          final baseUri = Uri.tryParse(widget.baseUrl.trim());
          final uri = (baseUri != null && parsed.scheme.isEmpty)
              ? baseUri.resolveUri(parsed)
              : parsed;
          final scheme = uri.scheme.toLowerCase();
          if (scheme == 'http' || scheme == 'https') {
            final l = L10n.of(context);
            final isArabic = l.isArabic;
            final title = (isArabic
                    ? (_remoteTitleAr ?? _localManifest?.titleAr)
                    : (_remoteTitleEn ?? _localManifest?.titleEn)) ??
                '';
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WeChatWebViewPage(
                  initialUri: uri,
                  baseUri: baseUri,
                  initialTitle: title.trim().isEmpty ? null : title.trim(),
                ),
              ),
            );
            return;
          }
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } catch (_) {}
        break;
    }
  }

  Future<void> _openMiniProgramPaySheet(BuildContext context) async {
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    if (!_hasPaymentsScope) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'هذا البرنامج لا يملك صلاحية الدفع (Payments scope).'
                : 'This mini‑program does not have Payments permission (scope).',
          ),
        ),
      );
      return;
    }
    String? recipient = _ownerContact;
    String ctxLabel = '';
    if (_ownerName != null && _ownerName!.trim().isNotEmpty) {
      ctxLabel = _ownerName!.trim();
    } else {
      // Fallback to a human‑readable mini‑program title.
      final titleEn = (_remoteTitleEn ?? _localManifest?.titleEn ?? '').trim();
      final titleAr = (_remoteTitleAr ?? _localManifest?.titleAr ?? '').trim();
      if (isArabic && titleAr.isNotEmpty) {
        ctxLabel = titleAr;
      } else if (titleEn.isNotEmpty) {
        ctxLabel = titleEn;
      } else if (titleAr.isNotEmpty) {
        ctxLabel = titleAr;
      }
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final walletId = sp.getString('wallet_id') ?? widget.walletId;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentsPage(
            widget.baseUrl,
            walletId,
            widget.deviceId,
            initialRecipient: recipient,
            initialSection: 'send',
            contextLabel: ctxLabel.isNotEmpty ? ctxLabel : null,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentsPage(
            widget.baseUrl,
            widget.walletId,
            widget.deviceId,
            initialSection: 'send',
            contextLabel: ctxLabel.isNotEmpty ? ctxLabel : null,
          ),
        ),
      );
    }
  }

  void _showRatingSheet(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    int selected = 5;
    bool submitting = false;
    String? error;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Material(
              borderRadius: BorderRadius.circular(12),
              color: theme.cardColor,
              child: StatefulBuilder(
                builder: (ctx2, setModalState) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.isArabic
                              ? 'تقييم البرنامج المصغر'
                              : 'Rate this mini‑program',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (i) {
                            final idx = i + 1;
                            final filled = idx <= selected;
                            return IconButton(
                              onPressed: submitting
                                  ? null
                                  : () {
                                      setModalState(() {
                                        selected = idx;
                                      });
                                    },
                              icon: Icon(
                                filled
                                    ? Icons.star
                                    : Icons.star_border_outlined,
                                color: Colors.amber
                                    .withValues(alpha: filled ? .95 : .55),
                              ),
                              iconSize: 28,
                              padding: EdgeInsets.zero,
                            );
                          }),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 4),
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
                            ElevatedButton(
                              onPressed: submitting
                                  ? null
                                  : () async {
                                      setModalState(() {
                                        submitting = true;
                                        error = null;
                                      });
                                      try {
                                        final uri = Uri.parse(
                                          '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(widget.id)}/rate',
                                        );
                                        final resp = await http.post(
                                          uri,
                                          headers:
                                              await _hdrMiniProgram(json: true),
                                          body: jsonEncode(
                                            <String, dynamic>{
                                              'rating': selected,
                                            },
                                          ),
                                        );
                                        if (resp.statusCode < 200 ||
                                            resp.statusCode >= 300) {
                                          setModalState(() {
                                            submitting = false;
                                            error = l.isArabic
                                                ? 'تعذّر إرسال التقييم.'
                                                : 'Failed to submit rating.';
                                          });
                                          return;
                                        }
                                        if (context.mounted) {
                                          Navigator.of(ctx).pop();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                l.isArabic
                                                    ? 'شكرًا لتقييم البرنامج.'
                                                    : 'Thanks for rating this mini‑program.',
                                              ),
                                            ),
                                          );
                                          // Refresh remote meta so rating is reflected.
                                          // ignore: discarded_futures
                                          _loadRemoteMeta();
                                        }
                                      } catch (_) {
                                        setModalState(() {
                                          submitting = false;
                                          error = l.isArabic
                                              ? 'تعذّر إرسال التقييم.'
                                              : 'Failed to submit rating.';
                                        });
                                      }
                                    },
                              child: submitting
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          theme.colorScheme.onPrimary,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      l.isArabic
                                          ? 'إرسال التقييم'
                                          : 'Submit rating',
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
          ),
        );
      },
    );
  }
}
