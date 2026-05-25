import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_flags.dart' show kEnduserOnly;
import 'design_tokens.dart';
import 'l10n.dart';
import 'mini_app_registry.dart';
import 'mini_apps_config.dart';
import 'moments_preset_store.dart';
import 'mini_program_shelf_prefs.dart';
import 'mini_program_runtime.dart';
import 'mini_programs_my_page.dart';
import 'session_cookie_store.dart';
import 'wechat_ui.dart';

class _IconSpec {
  final IconData icon;
  final Color bg;
  final Color fg;
  const _IconSpec(this.icon, this.bg, this.fg);
}

class MiniProgramsDiscoverPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final void Function(String modId) onOpenMod;
  final http.Client? httpClient;
  final bool openPinnedManageOnStart;
  final bool autofocusSearchOnStart;

  const MiniProgramsDiscoverPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.onOpenMod,
    this.httpClient,
    this.openPinnedManageOnStart = false,
    this.autofocusSearchOnStart = false,
  });

  @override
  State<MiniProgramsDiscoverPage> createState() =>
      _MiniProgramsDiscoverPageState();
}

class _MiniProgramsDiscoverPageState extends State<MiniProgramsDiscoverPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _searchFocus = FocusNode();
  final GlobalKey _allDirectoryKey = GlobalKey();
  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _programs = const <Map<String, dynamic>>[];
  String _query = '';
  String? _categoryFilter;
  bool _trendingOnly = false;
  bool _mineOnly = false;
  bool _showAllDirectory = false;
  Set<String> _pinned = <String>{};
  List<String> _pinnedOrder = const <String>[];
  List<String> _recentIds = const <String>[];
  String? _myOwnerContact;
  List<Map<String, dynamic>> _topPrograms = const <Map<String, dynamic>>[];
  String _topProgramsSig = '';
  bool _hasNewTopPrograms = false;
  Map<String, dynamic>? _devSummary;
  Map<String, String> _seenReleaseVersions = <String, String>{};
  Set<String> _updateBadgeIds = <String>{};
  bool _autoOpenedPinnedManage = false;
  bool _autoFocusedSearch = false;
  bool _shelfSyncing = false;

  static const Duration _shelfSyncTimeout = Duration(seconds: 4);
  static const String _prefsSeenReleaseKey =
      'mini_programs.seen_release_versions.v1';
  static const String _prefsLatestReleaseKey =
      'mini_programs.latest_released_versions.v1';

  bool _miniProgramStatusIsPublished(Object? raw) {
    final status = (raw ?? '').toString().trim().toLowerCase();
    return status == 'active' || status == 'published';
  }

  List<String> _cleanIdList(Iterable<String> items) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in items) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key)) return false;
      if ((b[e.key] ?? '') != e.value) return false;
    }
    return true;
  }

  String _textField(Map<String, dynamic> p, String key) {
    return (p[key] ?? '').toString().trim();
  }

  int _intField(Map<String, dynamic> p, String key) {
    final raw = p[key];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  double _doubleField(Map<String, dynamic> p, String key) {
    final raw = p[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  bool _boolField(Map<String, dynamic> p, String key, {bool fallback = false}) {
    final raw = p[key];
    if (raw is bool) return raw;
    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value == 'true') return true;
    if (value == 'false') return false;
    return fallback;
  }

  String _manifestAuthorityForRecord(
    Map<String, dynamic> p, {
    required bool remote,
  }) {
    if (!remote) return 'local_fallback';
    final existing = _textField(p, 'manifest_authority');
    if (existing.isNotEmpty) return existing;

    final enabled = _boolField(p, 'enabled', fallback: true);
    final status = _textField(p, 'status').toLowerCase();
    final reviewStatus = _textField(p, 'review_status').toLowerCase();
    final releasedBundleUrl = _textField(p, 'released_bundle_url');
    if (!enabled || status == 'suspended' || status == 'archived') {
      return 'server_restricted';
    }
    if ((status == 'published' || status == 'active') &&
        reviewStatus == 'approved') {
      return releasedBundleUrl.isNotEmpty
          ? 'server_released_bundle'
          : 'server_native_manifest';
    }
    if (reviewStatus == 'pending' || reviewStatus == 'submitted') {
      return 'server_review_pending';
    }
    if (reviewStatus == 'changes_requested') {
      return 'server_changes_requested';
    }
    if (reviewStatus == 'rejected') return 'server_rejected';
    return 'server_draft';
  }

  MiniAppDescriptor? _localDescriptorForProgram(String appId) {
    final id = appId.trim().toLowerCase();
    if (id.isEmpty) return null;
    for (final descriptor in MiniAppRegistry.descriptors) {
      final descriptorId = descriptor.id.trim().toLowerCase();
      final runtimeId = (descriptor.runtimeAppId ?? '').trim().toLowerCase();
      if (descriptorId == id || runtimeId == id) return descriptor;
    }
    return null;
  }

  Map<String, dynamic> _normalizeMiniProgramRecord(
    Map<String, dynamic> raw, {
    bool remote = false,
  }) {
    final p = Map<String, dynamic>.from(raw);
    final appId = _textField(p, 'app_id').isNotEmpty
        ? _textField(p, 'app_id')
        : _textField(p, 'id');
    if (appId.isEmpty) return p;
    p['app_id'] = appId;
    final descriptor = _localDescriptorForProgram(appId);
    final titleEn = _textField(p, 'title_en');
    final titleAr = _textField(p, 'title_ar');
    final categoryEn = _textField(p, 'category_en');
    final categoryAr = _textField(p, 'category_ar');
    final descriptionEn = _textField(p, 'description_en');
    final descriptionAr = _textField(p, 'description_ar');
    final runtimeId = _textField(p, 'runtime_app_id');
    if (descriptor != null) {
      if (titleEn.isEmpty) p['title_en'] = descriptor.titleEn;
      if (titleAr.isEmpty) p['title_ar'] = descriptor.titleAr;
      if (categoryEn.isEmpty) p['category_en'] = descriptor.categoryEn;
      if (categoryAr.isEmpty) p['category_ar'] = descriptor.categoryAr;
      if (descriptionEn.isEmpty) p['description_en'] = descriptor.categoryEn;
      if (descriptionAr.isEmpty) p['description_ar'] = descriptor.categoryAr;
      if (runtimeId.isEmpty && (descriptor.runtimeAppId ?? '').isNotEmpty) {
        p['runtime_app_id'] = descriptor.runtimeAppId;
      }
      if (!p.containsKey('official')) p['official'] = descriptor.official;
      if (!p.containsKey('beta')) p['beta'] = descriptor.beta;
      if (!p.containsKey('enabled')) p['enabled'] = descriptor.enabled;
      if (_doubleField(p, 'rating') <= 0 && descriptor.rating > 0) {
        p['rating'] = descriptor.rating;
      }
      if (_intField(p, 'rating_count') <= 0 && descriptor.ratingCount > 0) {
        p['rating_count'] = descriptor.ratingCount;
      }
      if (_intField(p, 'usage_score') <= 0 && descriptor.usageScore > 0) {
        p['usage_score'] = descriptor.usageScore;
      }
      if (_intField(p, 'moments_shares_30d') <= 0 &&
          descriptor.momentsShares > 0) {
        p['moments_shares_30d'] = descriptor.momentsShares;
      }
    }
    p['status'] = _textField(p, 'status').isNotEmpty
        ? _textField(p, 'status')
        : 'published';
    p['review_status'] = _textField(p, 'review_status').isNotEmpty
        ? _textField(p, 'review_status')
        : 'approved';
    p['enabled'] = _boolField(p, 'enabled', fallback: true);
    p['__registry_source'] = remote ? 'server' : 'local';
    p['manifest_authority'] = _manifestAuthorityForRecord(p, remote: remote);
    return p;
  }

  String _programSearchHaystack(Map<String, dynamic> p) {
    final parts = <String>[
      _textField(p, 'app_id'),
      _textField(p, 'runtime_app_id'),
      _textField(p, 'title_en'),
      _textField(p, 'title_ar'),
      _textField(p, 'description_en'),
      _textField(p, 'description_ar'),
      _textField(p, 'category_en'),
      _textField(p, 'category_ar'),
    ];
    return parts.join(' ').toLowerCase().trim();
  }

  bool _matchesCategoryFilter(Map<String, dynamic> p, String? filter) {
    if (filter == null) return true;
    final hay = _programSearchHaystack(p);
    switch (filter) {
      case 'transport':
        return hay.contains('bus') ||
            hay.contains('ride') ||
            hay.contains('transport') ||
            hay.contains('mobility') ||
            hay.contains('تنقل');
      case 'wallet':
        return hay.contains('wallet') ||
            hay.contains('pay') ||
            hay.contains('payment') ||
            hay.contains('payments') ||
            hay.contains('محفظ');
      case 'social':
        return hay.contains('moments') ||
            hay.contains('social') ||
            hay.contains('people_nearby') ||
            hay.contains('nearby') ||
            hay.contains('sticker') ||
            hay.contains('ملصق') ||
            hay.contains('اجتماعي');
      case 'media':
        return hay.contains('channels') ||
            hay.contains('media') ||
            hay.contains('video') ||
            hay.contains('قناة');
      case 'services':
        return hay.contains('official') ||
            hay.contains('service') ||
            hay.contains('account') ||
            hay.contains('verified') ||
            hay.contains('رسمي') ||
            hay.contains('خدمات');
      case 'tools':
        return hay.contains('favorite') ||
            hay.contains('bookmark') ||
            hay.contains('personal') ||
            hay.contains('saved') ||
            hay.contains('مفض');
      default:
        return true;
    }
  }

  String _localizedProgramField(
    Map<String, dynamic> p,
    String enKey,
    String arKey, {
    required bool isArabic,
  }) {
    final en = _textField(p, enKey);
    final ar = _textField(p, arKey);
    if (isArabic && ar.isNotEmpty) return ar;
    return en.isNotEmpty ? en : ar;
  }

  String _programSubtitle(Map<String, dynamic> p, {required bool isArabic}) {
    final description = _localizedProgramField(
      p,
      'description_en',
      'description_ar',
      isArabic: isArabic,
    );
    if (description.isNotEmpty) return description;
    return _localizedProgramField(
      p,
      'category_en',
      'category_ar',
      isArabic: isArabic,
    );
  }

  Map<String, String> _releasedVersionsById() {
    final out = <String, String>{};
    for (final p in _programs) {
      final appId = (p['app_id'] ?? '').toString().trim();
      if (appId.isEmpty) continue;
      final rel =
          (p['released_version'] ?? p['last_version'] ?? '').toString().trim();
      if (rel.isNotEmpty) out[appId] = rel;
    }
    return out;
  }

  Future<void> _persistLatestReleasedVersions() async {
    final latest = _releasedVersionsById();
    try {
      final sp = await SharedPreferences.getInstance();
      if (latest.isEmpty) {
        await sp.remove(_prefsLatestReleaseKey);
        return;
      }
      await sp.setString(_prefsLatestReleaseKey, jsonEncode(latest));
    } catch (_) {}
  }

  Future<void> _loadSeenReleaseVersions() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsSeenReleaseKey) ?? '{}';
      final decoded = jsonDecode(raw);
      final map = <String, String>{};
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final id = (k ?? '').toString().trim();
          final ver = (v ?? '').toString().trim();
          if (id.isNotEmpty && ver.isNotEmpty) map[id] = ver;
        });
      }
      if (!mounted) return;
      setState(() {
        _seenReleaseVersions = map;
      });
    } catch (_) {}
    unawaited(_refreshReleaseBadges());
  }

  Future<void> _persistSeenReleaseVersions(Map<String, String> versions) async {
    final cleaned = <String, String>{};
    versions.forEach((k, v) {
      final id = k.trim();
      final ver = v.trim();
      if (id.isNotEmpty && ver.isNotEmpty) cleaned[id] = ver;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      if (cleaned.isEmpty) {
        await sp.remove(_prefsSeenReleaseKey);
        return;
      }
      await sp.setString(_prefsSeenReleaseKey, jsonEncode(cleaned));
    } catch (_) {}
  }

  Future<void> _refreshReleaseBadges() async {
    final releases = _releasedVersionsById();
    unawaited(_persistLatestReleasedVersions());
    final interested = <String>{
      ..._pinned,
      ..._recentIds,
    };
    final nextSeen = Map<String, String>.from(_seenReleaseVersions);
    var seenChanged = false;
    final newlySeenVersions = <String, String>{};
    for (final id in interested) {
      final rel = (releases[id] ?? '').trim();
      if (rel.isEmpty) continue;
      final cur = (nextSeen[id] ?? '').trim();
      if (cur.isEmpty) {
        nextSeen[id] = rel;
        newlySeenVersions[id] = rel;
        seenChanged = true;
      }
    }

    final badges = <String>{};
    for (final id in interested) {
      final rel = (releases[id] ?? '').trim();
      if (rel.isEmpty) continue;
      final seen = (nextSeen[id] ?? '').trim();
      if (seen.isEmpty) continue;
      if (seen != rel) badges.add(id);
    }

    final nextBadges = badges;
    final badgesChanged = !_setEquals(nextBadges, _updateBadgeIds);
    final seenMapChanged = !_mapEquals(nextSeen, _seenReleaseVersions);
    if (!badgesChanged && !seenMapChanged) return;
    if (!mounted) return;
    setState(() {
      _updateBadgeIds = nextBadges;
      _seenReleaseVersions = nextSeen;
    });
    if (seenChanged) {
      unawaited(_persistSeenReleaseVersions(nextSeen));
      for (final entry in newlySeenVersions.entries) {
        unawaited(_syncMiniProgramSeenRelease(entry.key, entry.value));
      }
    }
  }

  Future<void> _markReleaseSeen(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final releases = _releasedVersionsById();
    final rel = (releases[id] ?? '').trim();
    if (rel.isEmpty) return;
    final nextSeen = Map<String, String>.from(_seenReleaseVersions);
    if ((nextSeen[id] ?? '').trim() == rel && !_updateBadgeIds.contains(id)) {
      return;
    }
    nextSeen[id] = rel;
    final nextBadges = <String>{..._updateBadgeIds}..remove(id);
    if (!mounted) return;
    setState(() {
      _seenReleaseVersions = nextSeen;
      _updateBadgeIds = nextBadges;
    });
    await _persistSeenReleaseVersions(nextSeen);
    unawaited(_syncMiniProgramSeenRelease(id, rel));
  }

  Future<void> _togglePinned(String id) async {
    final clean = id.trim();
    if (clean.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final curPinned = loadMiniProgramPinnedIdsSync(sp);
      final pinnedSet = curPinned.toSet();
      final isPinned = pinnedSet.contains(clean);
      if (isPinned) {
        curPinned.removeWhere((e) => e == clean);
      } else {
        curPinned.insert(0, clean);
      }
      await saveMiniProgramPinnedIds(sp, curPinned);

      final curOrder = loadMiniProgramPinnedOrderSync(sp);
      curOrder.removeWhere((e) => e == clean);
      if (!isPinned) {
        curOrder.insert(0, clean);
      }
      final nextOrder = miniProgramPinnedOrderFromLists(
        pinnedIds: curPinned,
        orderedIds: curOrder,
      );
      await saveMiniProgramPinnedOrder(
        sp,
        nextOrder,
        pinnedIds: curPinned,
      );
      if (!mounted) return;
      setState(() {
        _pinned = curPinned.toSet();
        _pinnedOrder = nextOrder;
      });
      unawaited(_syncMiniProgramPinnedState(clean, !isPinned));
      unawaited(_syncMiniProgramPinnedOrder(nextOrder));
      unawaited(_refreshReleaseBadges());
    } catch (_) {}
  }

  Future<void> _savePinnedOrder(List<String> orderedIds) async {
    final cleaned = _cleanIdList(orderedIds).where(_pinned.contains).toList();
    try {
      final sp = await SharedPreferences.getInstance();
      await saveMiniProgramPinnedOrder(sp, cleaned, pinnedIds: _pinned);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pinnedOrder = cleaned;
    });
    unawaited(_syncMiniProgramPinnedOrder(cleaned));
  }

  Future<void> _removeFromRecents(String id) async {
    final clean = id.trim();
    if (clean.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final cur = loadMiniProgramRecentIdsSync(sp);
      cur.removeWhere((e) => e == clean);
      await saveMiniProgramRecentIds(sp, cur);
      if (!mounted) return;
      setState(() {
        _recentIds = cur;
      });
      unawaited(_removeMiniProgramRecentOnServer(clean));
      unawaited(_refreshReleaseBadges());
    } catch (_) {}
  }

  Future<void> _clearRecents() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await clearMiniProgramRecentIds(sp);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recentIds = const <String>[];
    });
    unawaited(_clearMiniProgramRecentsOnServer());
    unawaited(_refreshReleaseBadges());
  }

  Future<void> _trackMiniProgramOpen(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    await _trackRecentLocally(id);
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/mini_programs/${Uri.encodeComponent(id)}/track_open',
      );
      await _http
          .post(uri, headers: await _authHeaders())
          .timeout(_shelfSyncTimeout);
    } catch (_) {}
  }

  Future<void> _trackRecentLocally(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final cur = loadMiniProgramRecentIdsSync(sp);
      cur.removeWhere((e) => e == id);
      cur.insert(0, id);
      if (cur.length > 10) {
        cur.removeRange(10, cur.length);
      }
      await saveMiniProgramRecentIds(sp, cur);
      if (!mounted) return;
      setState(() {
        _recentIds = cur;
      });
      unawaited(_refreshReleaseBadges());
    } catch (_) {}
  }

  Future<void> _openMiniProgram(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    unawaited(_markReleaseSeen(id));
    final nativeRuntimeId = _nativeRuntimeTargetForAppId(id);
    if (nativeRuntimeId != null) {
      unawaited(_trackMiniProgramOpen(id));
      widget.onOpenMod(nativeRuntimeId);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiniProgramPage(
          id: id,
          baseUrl: widget.baseUrl,
          walletId: widget.walletId,
          deviceId: widget.deviceId,
          onOpenMod: widget.onOpenMod,
        ),
      ),
    );
    // Refresh badges/pins/recents after returning from the runtime.
    // ignore: discarded_futures
    _loadPinned();
    // ignore: discarded_futures
    _loadRecents();
  }

  Map<String, dynamic>? _programById(String appId) {
    final id = appId.trim();
    if (id.isEmpty) return null;
    for (final p in _programs) {
      final candidate = (p['app_id'] ?? '').toString().trim();
      final runtimeId = (p['runtime_app_id'] ?? '').toString().trim();
      if (candidate == id || runtimeId == id) return p;
    }
    return null;
  }

  String? _nativeRuntimeTargetForAppId(String appId) {
    final id = appId.trim();
    if (id.isEmpty) return null;
    final p = _programById(id);
    final runtimeId = p == null ? '' : _textField(p, 'runtime_app_id');
    if (runtimeId.isNotEmpty && MiniAppRegistry.byId(runtimeId) != null) {
      return runtimeId;
    }
    if (MiniAppRegistry.byId(id) != null) return id;
    return null;
  }

  String _miniProgramTitle(String appId, {required bool isArabic}) {
    final id = appId.trim();
    final p = _programById(id);
    if (p != null) {
      final titleEn = (p['title_en'] ?? '').toString().trim();
      final titleAr = (p['title_ar'] ?? '').toString().trim();
      if (isArabic && titleAr.isNotEmpty) return titleAr;
      if (titleEn.isNotEmpty) return titleEn;
      if (titleAr.isNotEmpty) return titleAr;
    }
    for (final descriptor in MiniAppRegistry.descriptors) {
      if (descriptor.id == id || descriptor.runtimeAppId == id) {
        return descriptor.title(isArabic: isArabic);
      }
    }
    return id;
  }

  String _miniProgramCategory(String appId, {required bool isArabic}) {
    final id = appId.trim();
    final p = _programById(id);
    if (p != null) {
      final category = _localizedProgramField(
        p,
        'category_en',
        'category_ar',
        isArabic: isArabic,
      );
      if (category.isNotEmpty) return category;
      final subtitle = _programSubtitle(p, isArabic: isArabic);
      if (subtitle.isNotEmpty) return subtitle;
    }
    for (final descriptor in MiniAppRegistry.descriptors) {
      if (descriptor.id == id || descriptor.runtimeAppId == id) {
        return descriptor.category(isArabic: isArabic);
      }
    }
    return '';
  }

  String _miniProgramQrPayload(String appId) =>
      'MINIPROGRAM|id=${Uri.encodeComponent(appId.trim())}';

  String _miniProgramDeepLink(String appId) =>
      'shamell://mini_program/${Uri.encodeComponent(appId.trim())}';

  String _miniProgramShareText(String appId, L10n l) {
    final title = _miniProgramTitle(appId, isArabic: l.isArabic);
    final text = l.isArabic
        ? 'اكتشف $title في تطبيق SyrChat. #سرتشات_الخدمات #MiniApp'
        : 'Check out $title in the SyrChat super app. #ShamellMiniApp #Services';
    final id = appId.trim().toLowerCase();
    final topic = switch (id) {
      'payments' => ' #WalletMiniApp',
      'green_paket' => ' #GreenPaket',
      'moments' => ' #Moments',
      'bus' || 'coach' => ' #CoachBus',
      _ => '',
    };
    return '$text$topic\n${_miniProgramDeepLink(appId)}';
  }

  Future<void> _copyMiniProgramLink(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final l = L10n.of(context);
    await Clipboard.setData(ClipboardData(text: _miniProgramDeepLink(id)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l.isArabic
              ? 'تم نسخ رابط البرنامج المصغّر.'
              : 'Mini program link copied.',
        ),
      ),
    );
  }

  Future<void> _shareMiniProgramToMoments(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final l = L10n.of(context);
    try {
      await saveMiniProgramMomentsPreset(
        text: _miniProgramShareText(id, l),
        miniProgramId: id,
      );
    } catch (_) {}
    if (!mounted) return;
    widget.onOpenMod('moments');
  }

  Future<void> _showMiniProgramQr(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    final theme = Theme.of(context);
    final title = _miniProgramTitle(id, isArabic: isArabic);
    final category = _miniProgramCategory(id, isArabic: isArabic);
    final payload = _miniProgramQrPayload(id);
    final spec = _iconSpecFor(id);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        WeChatLeadingIcon(
                          icon: spec.icon,
                          background: spec.bg,
                          foreground: spec.fg,
                          size: 42,
                          iconSize: 20,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(11)),
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
                              if (category.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .62),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: .85),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: payload,
                            version: QrVersions.auto,
                            size: 210,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      payload,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .62),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              unawaited(_copyMiniProgramLink(id));
                            },
                            icon: const Icon(Icons.link, size: 18),
                            label: Text(isArabic ? 'نسخ الرابط' : 'Copy link'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              unawaited(_shareMiniProgramToMoments(id));
                            },
                            icon: const Icon(Icons.ios_share, size: 18),
                            label: Text(
                              isArabic ? 'مشاركة' : 'Share',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMiniProgramActionsSheet({
    required String appId,
    required bool isPinned,
    required bool isRecent,
  }) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    final theme = Theme.of(context);
    final pinLabel = isPinned
        ? (isArabic ? 'إلغاء التثبيت' : 'Unpin')
        : (isArabic ? 'تثبيت' : 'Pin');
    final shareLabel = isArabic ? 'مشاركة في اللحظات' : 'Share to Moments';
    final qrLabel = isArabic ? 'رمز QR' : 'Mini program QR';
    final copyLabel = isArabic ? 'نسخ الرابط' : 'Copy link';
    final removeRecentLabel =
        isArabic ? 'إزالة من الأخيرة' : 'Remove from recents';
    final cancelLabel = isArabic ? 'إلغاء' : 'Cancel';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget card(List<Widget> children) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: .98),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          );
        }

        Widget actionRow({
          required String label,
          required VoidCallback onTap,
          Color? color,
        }) {
          return ListTile(
            dense: true,
            title: Center(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color ?? theme.colorScheme.onSurface,
                ),
              ),
            ),
            onTap: onTap,
          );
        }

        final actions = <Widget>[
          actionRow(
            label: pinLabel,
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_togglePinned(id));
            },
          ),
          const Divider(height: 1),
          actionRow(
            label: shareLabel,
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_shareMiniProgramToMoments(id));
            },
          ),
          const Divider(height: 1),
          actionRow(
            label: qrLabel,
            onTap: () {
              Navigator.of(ctx).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                unawaited(_showMiniProgramQr(id));
              });
            },
          ),
          const Divider(height: 1),
          actionRow(
            label: copyLabel,
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_copyMiniProgramLink(id));
            },
          ),
          if (isRecent) ...[
            const Divider(height: 1),
            actionRow(
              label: removeRecentLabel,
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_removeFromRecents(id));
              },
            ),
          ],
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                card(actions),
                const SizedBox(height: 8),
                card([
                  actionRow(
                    label: cancelLabel,
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMiniProgramActionsPopover({
    required String appId,
    required bool isPinned,
    required bool isRecent,
    required Offset globalPosition,
  }) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    final l = L10n.of(context);
    final isArabic = l.isArabic;
    final theme = Theme.of(context);

    final pinLabel = isPinned
        ? (isArabic ? 'إلغاء التثبيت' : 'Unpin')
        : (isArabic ? 'تثبيت' : 'Pin');
    final shareLabel = isArabic ? 'مشاركة في اللحظات' : 'Share to Moments';
    final qrLabel = isArabic ? 'رمز QR' : 'Mini program QR';
    final copyLabel = isArabic ? 'نسخ الرابط' : 'Copy link';
    final removeRecentLabel =
        isArabic ? 'إزالة من الأخيرة' : 'Remove from recents';
    final cancelLabel = isArabic ? 'إلغاء' : 'Cancel';

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    final overlaySize = overlayBox.size;
    final anchor =
        overlayBox.globalToLocal(globalPosition) - const Offset(0, 8);

    final actionsCount = isRecent ? 5 : 4;
    final dividerCount = actionsCount - 1;
    const rowH = 44.0;
    const menuW = 218.0;
    final menuH = (rowH * actionsCount) + dividerCount;
    const arrowW = 14.0;
    const arrowH = 10.0;
    const margin = 8.0;
    const gap = 10.0;

    final canShowAbove = anchor.dy - gap - arrowH - menuH >= margin;
    final canShowBelow =
        anchor.dy + gap + arrowH + menuH <= overlaySize.height - margin;
    final showAbove = canShowAbove || !canShowBelow;

    var left = anchor.dx - (menuW / 2);
    left = left.clamp(margin, overlaySize.width - menuW - margin);

    double top;
    if (showAbove) {
      top = anchor.dy - gap - arrowH - menuH;
    } else {
      top = anchor.dy + gap + arrowH;
    }
    top = top.clamp(margin, overlaySize.height - menuH - margin);

    var arrowLeft = anchor.dx - (arrowW / 2);
    arrowLeft = arrowLeft.clamp(left + 10, left + menuW - arrowW - 10);
    final arrowTop = showAbove ? (top + menuH) : (top - arrowH);

    const bg = Color(0xFF2C2C2C);

    Widget actionRow({
      required String label,
      required VoidCallback onTap,
      Color color = Colors.white,
    }) {
      return InkWell(
        onTap: onTap,
        child: SizedBox(
          height: rowH,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget menuDivider() {
      return Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: .14),
      );
    }

    final menu = Material(
      color: Colors.transparent,
      child: Container(
        width: menuW,
        height: menuH,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            actionRow(
              label: pinLabel,
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_togglePinned(id));
              },
            ),
            menuDivider(),
            actionRow(
              label: shareLabel,
              onTap: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(_shareMiniProgramToMoments(id));
                });
              },
            ),
            menuDivider(),
            actionRow(
              label: qrLabel,
              onTap: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(_showMiniProgramQr(id));
                });
              },
            ),
            menuDivider(),
            actionRow(
              label: copyLabel,
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_copyMiniProgramLink(id));
              },
            ),
            if (isRecent) ...[
              menuDivider(),
              actionRow(
                label: removeRecentLabel,
                color: const Color(0xFFFA5151),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_removeFromRecents(id));
                },
              ),
            ],
          ],
        ),
      ),
    );

    final arrow = ClipPath(
      clipper: showAbove
          ? _WeChatPopoverDownArrowClipper()
          : _WeChatPopoverUpArrowClipper(),
      child: const ColoredBox(
        color: bg,
        child: SizedBox(width: arrowW, height: arrowH),
      ),
    );

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: cancelLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, a1, _) {
        final curved = CurvedAnimation(
          parent: a1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),
              AnimatedBuilder(
                animation: curved,
                builder: (context, _) {
                  final t = curved.value;
                  final dx = 14 * (1 - t);
                  return Stack(
                    children: [
                      Positioned(
                        left: left,
                        top: top,
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(dx, 0),
                            child: menu,
                          ),
                        ),
                      ),
                      Positioned(
                        left: arrowLeft,
                        top: arrowTop,
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(dx, 0),
                            child: arrow,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) => child,
    );
  }

  Future<void> _onMiniProgramLongPress({
    required String appId,
    required bool isPinned,
    required bool isRecent,
    Offset? globalPosition,
  }) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    final globalPos = globalPosition;
    if (globalPos != null) {
      await _showMiniProgramActionsPopover(
        appId: id,
        isPinned: isPinned,
        isRecent: isRecent,
        globalPosition: globalPos,
      );
      return;
    }
    await _showMiniProgramActionsSheet(
      appId: id,
      isPinned: isPinned,
      isRecent: isRecent,
    );
  }

  Future<void> _openRecentsManage() async {
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    final byId = <String, Map<String, dynamic>>{};
    for (final p in _programs) {
      final appId = (p['app_id'] ?? '').toString();
      if (appId.isEmpty) continue;
      byId[appId] = p;
    }

    final ids = <String>[];
    final seen = <String>{};
    for (final raw in _recentIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (!seen.add(id)) continue;
      if (!byId.containsKey(id)) continue;
      ids.add(id);
    }

    final titleById = <String, String>{};
    for (final id in ids) {
      final p = byId[id];
      if (p == null) continue;
      final titleEn = (p['title_en'] ?? '').toString().trim();
      final titleAr = (p['title_ar'] ?? '').toString().trim();
      final title = isArabic && titleAr.isNotEmpty
          ? titleAr
          : (titleEn.isNotEmpty ? titleEn : id);
      titleById[id] = title;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MiniProgramsRecentsManagePage(
          recentIds: ids,
          titleById: titleById,
          iconSpecFor: _iconSpecFor,
          onRemove: (id) => _removeFromRecents(id),
          onClear: _clearRecents,
        ),
      ),
    );
    await _loadRecents();
  }

  Future<void> _openPinnedManage() async {
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    final byId = <String, Map<String, dynamic>>{};
    for (final p in _programs) {
      final appId = (p['app_id'] ?? '').toString();
      if (appId.isEmpty) continue;
      byId[appId] = p;
    }

    var pinnedSet = <String>{..._pinned};
    var pinnedOrder = List<String>.from(_pinnedOrder);
    try {
      final sp = await SharedPreferences.getInstance();
      final pinned = loadMiniProgramPinnedIdsSync(sp);
      final nextPinned = pinned.toSet();
      final baseOrder = loadMiniProgramPinnedOrderSync(sp)
          .where(nextPinned.contains)
          .toList();
      final missing = pinned
          .where((id) => nextPinned.contains(id) && !baseOrder.contains(id))
          .toList();
      pinnedSet = nextPinned;
      pinnedOrder = <String>[...missing, ...baseOrder];
    } catch (_) {}

    final ids = <String>[];
    final seen = <String>{};
    void add(String raw) {
      final id = raw.trim();
      if (id.isEmpty) return;
      if (!seen.add(id)) return;
      if (!pinnedSet.contains(id)) return;
      if (!byId.containsKey(id)) return;
      ids.add(id);
    }

    for (final id in pinnedOrder) {
      add(id);
    }
    for (final id in pinnedSet) {
      add(id);
    }

    final titleById = <String, String>{};
    for (final entry in byId.entries) {
      final p = entry.value;
      final appId = entry.key;
      final titleEn = (p['title_en'] ?? '').toString();
      final titleAr = (p['title_ar'] ?? '').toString();
      final title = isArabic && titleAr.trim().isNotEmpty
          ? titleAr.trim()
          : (titleEn.trim().isNotEmpty ? titleEn.trim() : appId);
      titleById[appId] = title;
    }

    double usageScore(Map<String, dynamic> p) {
      final raw = p['usage_score'];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '') ?? 0;
    }

    final allPrograms = byId.values.toList()
      ..sort((a, b) => usageScore(b).compareTo(usageScore(a)));
    final suggestedIds = <String>[];
    final suggestedSeen = <String>{};
    void addSuggested(String raw) {
      final id = raw.trim();
      if (id.isEmpty) return;
      if (!suggestedSeen.add(id)) return;
      if (!byId.containsKey(id)) return;
      suggestedIds.add(id);
    }

    for (final id in _recentIds) {
      addSuggested(id);
    }
    for (final p in _topPrograms) {
      addSuggested((p['app_id'] ?? '').toString());
    }
    for (final p in allPrograms) {
      addSuggested((p['app_id'] ?? '').toString());
    }

    final next = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => _MiniProgramsPinnedManagePage(
          pinnedIds: ids,
          suggestedIds: suggestedIds,
          titleById: titleById,
          iconSpecFor: _iconSpecFor,
          onTogglePinned: (id) => _togglePinned(id),
          onSaveOrder: _savePinnedOrder,
        ),
      ),
    );
    if (next != null) {
      await _savePinnedOrder(next);
    }
    await _loadPinned();
  }

  List<Map<String, dynamic>> _localMiniPrograms() {
    final out = <Map<String, dynamic>>[];
    for (final m in visibleMiniApps()) {
      final id = m.id.trim();
      if (id.isEmpty) continue;
      final scopes = <String>[];
      final idLower = id.toLowerCase();
      if (idLower.contains('pay') ||
          idLower.contains('wallet') ||
          idLower.contains('payment')) {
        scopes.add('payments');
      }
      out.add(<String, dynamic>{
        'app_id': id,
        'runtime_app_id': m.runtimeAppId ?? id,
        'title_en': m.titleEn,
        'title_ar': m.titleAr,
        'category_en': m.categoryEn,
        'category_ar': m.categoryAr,
        'description_en': m.categoryEn,
        'description_ar': m.categoryAr,
        'status': 'published',
        'review_status': 'approved',
        'enabled': m.enabled,
        'manifest_authority': 'local_fallback',
        '__registry_source': 'local',
        'usage_score': m.usageScore,
        'rating': m.rating,
        'rating_count': m.ratingCount,
        'moments_shares_30d': m.momentsShares,
        'moments_shares_total': m.momentsShares,
        'owner_contact': '',
        'scopes': scopes,
        'official': m.official,
        'beta': m.beta,
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _mergeWithLocal(
      List<Map<String, dynamic>> remote) {
    final merged = <Map<String, dynamic>>[
      for (final p in remote)
        _normalizeMiniProgramRecord(Map<String, dynamic>.from(p), remote: true),
    ];
    final existing = <String>{};
    for (final p in merged) {
      final id = (p['app_id'] ?? '').toString().trim().toLowerCase();
      if (id.isNotEmpty) existing.add(id);
      final runtimeId =
          (p['runtime_app_id'] ?? '').toString().trim().toLowerCase();
      if (runtimeId.isNotEmpty) existing.add(runtimeId);
    }
    for (final p in _localMiniPrograms()) {
      final id = (p['app_id'] ?? '').toString().trim().toLowerCase();
      if (id.isEmpty || existing.contains(id)) {
        continue;
      }
      merged.add(_normalizeMiniProgramRecord(p));
    }
    return merged;
  }

  Color _accentForMiniProgram(String appId) {
    switch (appId.trim().toLowerCase()) {
      case 'payments':
        return Tokens.colorPayments;
      case 'green_paket':
        return const Color(0xFF16A34A);
      case 'moments':
        return const Color(0xFF2563EB);
      case 'favorites':
        return const Color(0xFFF59E0B);
      case 'official_accounts':
        return const Color(0xFF0EA5E9);
      case 'channels':
        return const Color(0xFFEF4444);
      case 'people_nearby':
        return const Color(0xFF14B8A6);
      case 'stickers':
        return const Color(0xFFF97316);
      case 'bus':
      case 'coach':
        return Tokens.colorBus;
      default:
        return const Color(0xFF64748B);
    }
  }

  _IconSpec _iconSpecFor(String appId) {
    final id = appId.trim().toLowerCase();
    final p = _programById(appId);
    final programRuntimeId =
        p == null ? '' : _textField(p, 'runtime_app_id').toLowerCase();
    for (final descriptor in MiniAppRegistry.descriptors) {
      final descriptorId = descriptor.id.trim().toLowerCase();
      final runtimeId = (descriptor.runtimeAppId ?? '').trim().toLowerCase();
      if (descriptorId == id ||
          runtimeId == id ||
          descriptorId == programRuntimeId ||
          runtimeId == programRuntimeId) {
        return _IconSpec(
          descriptor.icon,
          _accentForMiniProgram(descriptorId),
          Colors.white,
        );
      }
    }
    if (id.contains('pay') || id.contains('wallet') || id.contains('payment')) {
      return const _IconSpec(
        Icons.account_balance_wallet_outlined,
        Tokens.colorPayments,
        Colors.white,
      );
    }
    if (id.contains('bus') || id.contains('ride') || id.contains('mobility')) {
      return const _IconSpec(
        Icons.directions_bus_filled_outlined,
        Tokens.colorBus,
        Colors.white,
      );
    }
    return const _IconSpec(
      Icons.widgets_outlined,
      Color(0xFF64748B),
      Colors.white,
    );
  }

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? http.Client();
    _searchFocus.addListener(_onSearchFocusChanged);
    _autoFocusedSearch =
        widget.autofocusSearchOnStart && !widget.openPinnedManageOnStart;
    if (_autoFocusedSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchFocus.requestFocus();
        setState(() {
          _autoFocusedSearch = false;
        });
      });
    }
    _loadSeenReleaseVersions();
    _load();
    _loadPinned();
    _loadRecents();
    unawaited(_syncMiniProgramShelfFromServer());
    _loadMyOwnerContact();
    _loadDeveloperSummary();
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<void> _loadPinned() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final pinned = loadMiniProgramPinnedIdsSync(sp);
      final order = loadMiniProgramPinnedOrderSync(sp);
      final pinnedSet = pinned.toSet();
      final baseOrder = order.where(pinnedSet.contains).toList();
      final missing = pinned
          .where((id) => pinnedSet.contains(id) && !baseOrder.contains(id))
          .toList();
      final nextOrder = <String>[
        ...missing,
        ...baseOrder,
      ];
      if (nextOrder.length != order.length ||
          !order.every((id) => nextOrder.contains(id))) {
        // Keep the order list consistent (filter out unpinned IDs + de-dupe).
        // ignore: discarded_futures
        saveMiniProgramPinnedOrder(sp, nextOrder, pinnedIds: pinnedSet);
      }
      if (!mounted) return;
      setState(() {
        _pinned = pinnedSet;
        _pinnedOrder = nextOrder;
      });
      unawaited(_refreshReleaseBadges());
      unawaited(_maybeAutoOpenPinnedManage());
    } catch (_) {}
  }

  Future<void> _loadRecents() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ids = loadMiniProgramRecentIdsSync(sp);
      if (!mounted) return;
      setState(() {
        _recentIds = ids;
      });
      unawaited(_refreshReleaseBadges());
    } catch (_) {}
  }

  Future<void> _loadMyOwnerContact() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final phone = sp.getString('phone') ?? '';
      if (!mounted) return;
      setState(() {
        _myOwnerContact = phone.trim().isEmpty ? null : phone.trim();
      });
    } catch (_) {}
  }

  Future<Map<String, String>> _authHeaders() {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl);
  }

  Future<Map<String, String>> _jsonAuthHeaders() {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: true);
  }

  String _shelfItemId(Map<String, dynamic> item) {
    return (item['app_id'] ?? item['id'] ?? '').toString().trim();
  }

  Future<List<Map<String, dynamic>>> _fetchMiniProgramShelf() async {
    final uri = Uri.parse('${widget.baseUrl}/me/mini_programs/shelf?limit=100');
    final resp = await _http
        .get(uri, headers: await _authHeaders())
        .timeout(_shelfSyncTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return const <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(resp.body);
    final raw = decoded is Map
        ? (decoded['items'] is List
            ? decoded['items'] as List
            : decoded['programs'] is List
                ? decoded['programs'] as List
                : const <dynamic>[])
        : decoded is List
            ? decoded
            : const <dynamic>[];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) out.add(item.cast<String, dynamic>());
    }
    return out;
  }

  Future<void> _syncMiniProgramShelfFromServer() async {
    if (_shelfSyncing) return;
    _shelfSyncing = true;
    try {
      final shelf = await _fetchMiniProgramShelf();

      final serverPinned = <String>[];
      final serverRecents = <String>[];
      final serverSeenVersions = <String, String>{};
      for (final item in shelf) {
        final id = _shelfItemId(item);
        if (id.isEmpty) continue;
        final pinned = item['pinned'] == true;
        final lastOpened = (item['last_opened_at'] ?? '').toString().trim();
        final openCount = item['open_count'];
        final seenVersion = (item['seen_version'] ?? '').toString().trim();
        if (pinned) serverPinned.add(id);
        if (lastOpened.isNotEmpty || (openCount is num && openCount > 0)) {
          serverRecents.add(id);
        }
        if (seenVersion.isNotEmpty) {
          serverSeenVersions[id] = seenVersion;
        }
      }

      final sp = await SharedPreferences.getInstance();
      final localPinned = loadMiniProgramPinnedIdsSync(sp);
      final localOrder = loadMiniProgramPinnedOrderSync(sp);
      final localRecents = loadMiniProgramRecentIdsSync(sp);
      final localSeenVersions = <String, String>{};
      try {
        final rawSeen = sp.getString(_prefsSeenReleaseKey) ?? '{}';
        final decodedSeen = jsonDecode(rawSeen);
        if (decodedSeen is Map) {
          decodedSeen.forEach((k, v) {
            final id = (k ?? '').toString().trim();
            final version = (v ?? '').toString().trim();
            if (id.isNotEmpty && version.isNotEmpty) {
              localSeenVersions[id] = version;
            }
          });
        }
      } catch (_) {}

      final nextPinnedList = _cleanIdList(<String>[
        ...serverPinned,
        ...localPinned,
      ]);
      final nextPinnedSet = nextPinnedList.toSet();
      final nextOrder = _cleanIdList(<String>[
        ...serverPinned,
        ...localOrder,
        ...localPinned,
      ]).where(nextPinnedSet.contains).toList();
      final nextRecents = _cleanIdList(<String>[
        ...serverRecents,
        ...localRecents,
      ]).take(10).toList();
      final releasedVersions = _releasedVersionsById();
      final nextSeenVersions = <String, String>{...serverSeenVersions};
      for (final entry in localSeenVersions.entries) {
        final currentRelease = (releasedVersions[entry.key] ?? '').trim();
        if (!serverSeenVersions.containsKey(entry.key) ||
            currentRelease == entry.value) {
          nextSeenVersions[entry.key] = entry.value;
        }
      }

      await saveMiniProgramShelfPrefs(
        sp,
        pinnedIds: nextPinnedList,
        pinnedOrder: nextOrder,
        recentIds: nextRecents,
      );
      await _persistSeenReleaseVersions(nextSeenVersions);

      final serverPinnedSet = serverPinned.toSet();
      for (final id in localPinned) {
        if (!serverPinnedSet.contains(id)) {
          unawaited(_syncMiniProgramPinnedState(id, true));
        }
      }
      for (final entry in localSeenVersions.entries) {
        final currentRelease = (releasedVersions[entry.key] ?? '').trim();
        if (!serverSeenVersions.containsKey(entry.key) ||
            (currentRelease == entry.value &&
                serverSeenVersions[entry.key] != entry.value)) {
          unawaited(_syncMiniProgramSeenRelease(entry.key, entry.value));
        }
      }
      unawaited(_syncMiniProgramPinnedOrder(nextOrder));

      if (!mounted) return;
      setState(() {
        _pinned = nextPinnedSet;
        _pinnedOrder = nextOrder;
        _recentIds = nextRecents;
        _seenReleaseVersions = nextSeenVersions;
      });
      unawaited(_refreshReleaseBadges());
      unawaited(_maybeAutoOpenPinnedManage());
    } catch (_) {
      // Offline and unauthenticated sessions keep the local shelf.
    } finally {
      _shelfSyncing = false;
    }
  }

  Future<void> _syncMiniProgramPinnedState(
    String appId,
    bool pinned,
  ) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/me/mini_programs/shelf/${Uri.encodeComponent(id)}',
      );
      await _http
          .patch(
            uri,
            headers: await _jsonAuthHeaders(),
            body: jsonEncode({'pinned': pinned}),
          )
          .timeout(_shelfSyncTimeout);
    } catch (_) {}
  }

  Future<void> _syncMiniProgramPinnedOrder(List<String> orderedIds) async {
    final ids = _cleanIdList(orderedIds);
    if (ids.isEmpty) return;
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/mini_programs/shelf/order');
      await _http
          .post(
            uri,
            headers: await _jsonAuthHeaders(),
            body: jsonEncode({'app_ids': ids}),
          )
          .timeout(_shelfSyncTimeout);
    } catch (_) {}
  }

  Future<void> _syncMiniProgramSeenRelease(
    String appId,
    String version,
  ) async {
    final id = appId.trim();
    final cleanVersion = version.trim();
    if (id.isEmpty || cleanVersion.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/me/mini_programs/shelf/${Uri.encodeComponent(id)}/seen_release',
      );
      await _http
          .post(
            uri,
            headers: await _jsonAuthHeaders(),
            body: jsonEncode({'version': cleanVersion}),
          )
          .timeout(_shelfSyncTimeout);
    } catch (_) {}
  }

  Future<void> _removeMiniProgramRecentOnServer(String appId) async {
    final id = appId.trim();
    if (id.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/me/mini_programs/shelf/${Uri.encodeComponent(id)}',
      );
      await _http
          .delete(uri, headers: await _authHeaders())
          .timeout(_shelfSyncTimeout);
    } catch (_) {}
  }

  Future<void> _clearMiniProgramRecentsOnServer() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/mini_programs/shelf');
      await _http
          .delete(uri, headers: await _authHeaders())
          .timeout(_shelfSyncTimeout);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Keep something useful on screen even if the server is unavailable.
    if (_programs.isEmpty) {
      final local = _localMiniPrograms();
      if (local.isNotEmpty) {
        setState(() {
          _programs = local;
          _topPrograms = _computeTopPrograms(local);
        });
        unawaited(_refreshReleaseBadges());
        unawaited(_maybeAutoOpenPinnedManage());
      }
    }

    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs');
      final resp = await _http.get(uri, headers: await _authHeaders());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (!mounted) return;
        final merged = _mergeWithLocal(_programs);
        final top = _computeTopPrograms(merged);
        // ignore: discarded_futures
        _updateTopProgramsBadge(top);
        setState(() {
          _error = resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}';
          _loading = false;
          _programs = merged;
          _topPrograms = top;
        });
        unawaited(_refreshReleaseBadges());
        unawaited(_maybeAutoOpenPinnedManage());
        return;
      }
      final decoded = jsonDecode(resp.body);
      final list = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['programs'] is List) {
        for (final e in decoded['programs'] as List) {
          if (e is Map) {
            list.add(e.cast<String, dynamic>());
          }
        }
      } else if (decoded is List) {
        for (final e in decoded) {
          if (e is Map) {
            list.add(e.cast<String, dynamic>());
          }
        }
      }
      if (!mounted) return;
      final merged = _mergeWithLocal(list);
      final top = _computeTopPrograms(merged);
      // ignore: discarded_futures
      _updateTopProgramsBadge(top);
      setState(() {
        _programs = merged;
        _topPrograms = top;
        _loading = false;
      });
      unawaited(_refreshReleaseBadges());
      unawaited(_maybeAutoOpenPinnedManage());
    } catch (e) {
      if (!mounted) return;
      final merged = _mergeWithLocal(_programs);
      final top = _computeTopPrograms(merged);
      // ignore: discarded_futures
      _updateTopProgramsBadge(top);
      setState(() {
        _error = e.toString();
        _loading = false;
        _programs = merged;
        _topPrograms = top;
      });
      unawaited(_refreshReleaseBadges());
      unawaited(_maybeAutoOpenPinnedManage());
    }
  }

  Future<void> _maybeAutoOpenPinnedManage() async {
    if (_autoOpenedPinnedManage) return;
    if (!widget.openPinnedManageOnStart) return;
    if (!mounted) return;
    if (_programs.isEmpty) return;

    var pinnedIds = _pinned;
    try {
      final sp = await SharedPreferences.getInstance();
      pinnedIds = loadMiniProgramPinnedIdsSync(sp).toSet();
    } catch (_) {}

    if (pinnedIds.isNotEmpty) {
      final available = <String>{};
      for (final p in _programs) {
        final id = (p['app_id'] ?? '').toString().trim();
        if (id.isNotEmpty) available.add(id);
      }
      final hasAnyPinnedInList = pinnedIds.any(available.contains);
      if (!hasAnyPinnedInList && _loading) return;
    }

    _autoOpenedPinnedManage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openPinnedManage());
    });
  }

  Future<void> _updateTopProgramsBadge(List<Map<String, dynamic>> top) async {
    final sig = top
        .map((p) => (p['app_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .join('|');
    String seen = '';
    try {
      final sp = await SharedPreferences.getInstance();
      seen = sp.getString('mini_programs.trending_seen_sig') ?? '';
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _topProgramsSig = sig;
      _hasNewTopPrograms = sig.isNotEmpty && sig != seen;
    });
  }

  Future<void> _markTopProgramsSeen() async {
    final sig = _topProgramsSig.trim();
    if (sig.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('mini_programs.trending_seen_sig', sig);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _hasNewTopPrograms = false;
    });
  }

  void _openAllMiniProgramsDirectory() {
    if (!mounted) return;
    if (!_showAllDirectory) {
      setState(() {
        _showAllDirectory = true;
      });
    }
    unawaited(_markTopProgramsSeen());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _allDirectoryKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0,
      );
    });
  }

  Future<void> _loadDeveloperSummary() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs/developer_json');
      final resp = await _http.get(uri, headers: await _authHeaders());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(resp.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['programs'] is List) {
        raw = decoded['programs'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      int totalApps = 0;
      int activeApps = 0;
      int totalUsage = 0;
      int totalMomentsShares = 0;
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        totalApps += 1;
        final status = (m['status'] ?? 'draft').toString().toLowerCase();
        if (_miniProgramStatusIsPublished(status)) {
          activeApps += 1;
        }
        final usage = m['usage_score'];
        if (usage is num && usage > 0) {
          totalUsage += usage.toInt();
        }
        final ms = m['moments_shares'];
        if (ms is num && ms > 0) {
          totalMomentsShares += ms.toInt();
        }
      }
      if (!mounted || totalApps <= 0) return;
      setState(() {
        _devSummary = <String, dynamic>{
          'total_apps': totalApps,
          'active_apps': activeApps,
          'total_usage': totalUsage,
          'total_moments_shares': totalMomentsShares,
        };
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : WeChatPalette.background;

    final filtered = _filteredPrograms();
    final isArabic = l.isArabic;
    final showHubSections = _query.trim().isEmpty &&
        !_trendingOnly &&
        !_mineOnly &&
        _categoryFilter == null;
    final showDirectory = !showHubSections || _showAllDirectory;

    Widget chevron() => Icon(
          isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    Widget errorBanner(String msg) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: theme.colorScheme.error.withValues(alpha: .08),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 18,
              color: theme.colorScheme.error.withValues(alpha: .90),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error.withValues(alpha: .90),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(isArabic ? 'البرامج المصغّرة' : 'Mini Programs'),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          PopupMenuButton<String>(
            tooltip: isArabic ? 'المزيد' : 'More',
            onSelected: (value) {
              if (value == 'refresh') {
                _load();
                return;
              }
              if (value == 'dev') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MyMiniProgramsPage(
                      baseUrl: widget.baseUrl,
                      walletId: widget.walletId,
                      deviceId: widget.deviceId,
                      onOpenMod: widget.onOpenMod,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (ctx) {
              final items = <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'refresh',
                  child: Text(isArabic ? 'تحديث' : 'Refresh'),
                ),
              ];
              if (!kEnduserOnly) {
                items.add(const PopupMenuDivider(height: 1));
                items.add(
                  PopupMenuItem<String>(
                    value: 'dev',
                    child: Text(
                      isArabic ? 'لوحة المطوّر' : 'Developer center',
                    ),
                  ),
                );
              }
              return items;
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            if (_loading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_error != null)
              SliverToBoxAdapter(
                child: errorBanner(_error!),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Builder(
                  builder: (ctx) {
                    final showCancel = _searchFocus.hasFocus ||
                        _query.trim().isNotEmpty ||
                        _searchCtrl.text.trim().isNotEmpty;
                    return Row(
                      children: [
                        Expanded(
                          child: WeChatSearchBar(
                            controller: _searchCtrl,
                            focusNode: _searchFocus,
                            autofocus: _autoFocusedSearch,
                            textInputAction: TextInputAction.search,
                            hintText: isArabic
                                ? 'ابحث في البرامج المصغّرة'
                                : 'Search mini programs',
                            margin: EdgeInsets.zero,
                            onChanged: (v) {
                              setState(() {
                                _query = v;
                              });
                            },
                          ),
                        ),
                        if (showCancel) ...[
                          const SizedBox(width: 10),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: WeChatPalette.green,
                            ),
                            onPressed: () {
                              _searchCtrl.clear();
                              _searchFocus.unfocus();
                              setState(() {
                                _query = '';
                              });
                            },
                            child: Text(
                              isArabic ? 'إلغاء' : 'Cancel',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: WeChatPalette.green,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            if (showHubSections && !_showAllDirectory)
              SliverToBoxAdapter(
                child: WeChatSection(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: _buildPinnedRow(l, theme),
                    ),
                  ],
                ),
              ),
            if (showHubSections && !_showAllDirectory)
              SliverToBoxAdapter(
                child: WeChatSection(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: _buildRecentRow(l, theme),
                    ),
                  ],
                ),
              ),
            if (showHubSections &&
                !_showAllDirectory &&
                _topPrograms.isNotEmpty)
              SliverToBoxAdapter(
                child: WeChatSection(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: _buildRecommendedRow(l, theme),
                    ),
                  ],
                ),
              ),
            if (!kEnduserOnly && showHubSections && _devSummary != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _buildDeveloperSummaryBanner(l, theme),
                ),
              ),
            if (showHubSections && !_showAllDirectory)
              SliverToBoxAdapter(
                child: WeChatSection(
                  children: [
                    ListTile(
                      dense: true,
                      leading: const WeChatLeadingIcon(
                        icon: Icons.apps_outlined,
                        background: WeChatPalette.green,
                      ),
                      title:
                          Text(isArabic ? 'كل البرامج' : 'All mini programs'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_hasNewTopPrograms) ...[
                            _buildRedDotBadge(theme),
                            const SizedBox(width: 8),
                          ],
                          chevron(),
                        ],
                      ),
                      onTap: _openAllMiniProgramsDirectory,
                    ),
                  ],
                ),
              ),
            if (showDirectory && _showAllDirectory && _topPrograms.isNotEmpty)
              SliverToBoxAdapter(
                child: WeChatSection(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: _buildTopProgramsRow(l, theme),
                    ),
                  ],
                ),
              ),
            if (showDirectory && _programs.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildCategoryChips(l),
                  ),
                ),
              ),
            if (showDirectory)
              SliverToBoxAdapter(
                child: Padding(
                  key: _allDirectoryKey,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isArabic ? 'كل البرامج' : 'All mini programs',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .75),
                        ),
                      ),
                      if (showHubSections && _showAllDirectory)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _showAllDirectory = false;
                            });
                            if (_scrollCtrl.hasClients) {
                              _scrollCtrl.animateTo(
                                0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          child: Text(isArabic ? 'إخفاء' : 'Hide'),
                        ),
                    ],
                  ),
                ),
              ),
            if (showDirectory && filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isArabic
                          ? 'لا توجد برامج مصغّرة مطابقة.'
                          : 'No matching mini‑programs.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: .65,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (showDirectory)
              SliverToBoxAdapter(
                child: Container(
                  color: theme.colorScheme.surface,
                  child: const SizedBox(height: 0),
                ),
              ),
            if (showDirectory && filtered.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final p = filtered[i];
                    final appId = (p['app_id'] ?? '').toString();
                    final titleEn = (p['title_en'] ?? '').toString();
                    final titleAr = (p['title_ar'] ?? '').toString();
                    final title = isArabic && titleAr.isNotEmpty
                        ? titleAr
                        : (titleEn.isNotEmpty ? titleEn : appId);
                    final desc = _programSubtitle(p, isArabic: isArabic);
                    final usage = (p['usage_score'] is num)
                        ? (p['usage_score'] as num).toInt()
                        : 0;
                    final rating = (p['rating'] is num)
                        ? (p['rating'] as num).toDouble()
                        : 0.0;
                    final moments30 = (p['moments_shares_30d'] is num)
                        ? (p['moments_shares_30d'] as num).toInt()
                        : 0;
                    final ownerContact =
                        (p['owner_contact'] ?? '').toString().trim();
                    final isMine = (_myOwnerContact ?? '').isNotEmpty &&
                        ownerContact.isNotEmpty &&
                        ownerContact == _myOwnerContact;
                    final isPinned = _pinned.contains(appId);
                    final isTrending =
                        usage >= 50 || rating >= 4.5 || moments30 >= 5;
                    final scopesRaw = p['scopes'];
                    final scopes = <String>[];
                    if (scopesRaw is List) {
                      for (final s in scopesRaw) {
                        final v = (s ?? '').toString().trim().toLowerCase();
                        if (v.isNotEmpty) scopes.add(v);
                      }
                    }
                    final hasPaymentsScope =
                        scopes.contains('payments') || scopes.contains('pay');

                    final spec = _iconSpecFor(appId);
                    final isLast = i == filtered.length - 1;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: theme.colorScheme.surface,
                          child: ListTile(
                            onTap: () => unawaited(_openMiniProgram(appId)),
                            onLongPress: appId.isEmpty
                                ? null
                                : () => _togglePinned(appId),
                            leading: WeChatLeadingIcon(
                              icon: spec.icon,
                              background: spec.bg,
                              foreground: spec.fg,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (isPinned) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.star_rounded,
                                    size: 16,
                                    color:
                                        theme.colorScheme.onSurface.withValues(
                                      alpha: .45,
                                    ),
                                  ),
                                ],
                                if (isTrending) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.local_fire_department_outlined,
                                    size: 16,
                                    color:
                                        Colors.redAccent.withValues(alpha: .85),
                                  ),
                                ],
                                if (hasPaymentsScope) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 16,
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: .85,
                                    ),
                                  ),
                                ],
                                if (isMine) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.onSurface
                                          .withValues(
                                        alpha: .06,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      isArabic ? 'لي' : 'Mine',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface
                                            .withValues(
                                          alpha: .70,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: desc.isNotEmpty
                                ? Text(
                                    desc,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(
                                        alpha: .65,
                                      ),
                                    ),
                                  )
                                : null,
                            trailing: chevron(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                          ),
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 72,
                            endIndent: 0,
                            color: theme.dividerColor,
                          ),
                      ],
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filteredPrograms() {
    final term = _query.trim().toLowerCase();
    final filtered = _programs.where((p) {
      final status = (p['status'] ?? '').toString().toLowerCase();
      if (!_miniProgramStatusIsPublished(status)) return false;
      if (term.isNotEmpty) {
        if (!_programSearchHaystack(p).contains(term)) {
          return false;
        }
      }
      if (_mineOnly) {
        final contact = (p['owner_contact'] ?? '').toString().trim();
        final mine = (_myOwnerContact ?? '').isNotEmpty &&
            contact.isNotEmpty &&
            contact == _myOwnerContact;
        if (!mine) return false;
      }
      final usageScore =
          (p['usage_score'] is num) ? (p['usage_score'] as num).toInt() : 0;
      final ratingVal =
          (p['rating'] is num) ? (p['rating'] as num).toDouble() : 0.0;
      final moments30 = (p['moments_shares_30d'] is num)
          ? (p['moments_shares_30d'] as num).toInt()
          : 0;
      if (_trendingOnly) {
        final isTrending =
            usageScore >= 50 || ratingVal >= 4.5 || moments30 >= 5;
        if (!isTrending) return false;
      }
      if (!_matchesCategoryFilter(p, _categoryFilter)) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final ua =
          (a['usage_score'] is num) ? (a['usage_score'] as num).toInt() : 0;
      final ub =
          (b['usage_score'] is num) ? (b['usage_score'] as num).toInt() : 0;
      final ra = (a['rating'] is num) ? (a['rating'] as num).toDouble() : 0.0;
      final rb = (b['rating'] is num) ? (b['rating'] as num).toDouble() : 0.0;
      final m30a = (a['moments_shares_30d'] is num)
          ? (a['moments_shares_30d'] as num).toInt()
          : 0;
      final m30b = (b['moments_shares_30d'] is num)
          ? (b['moments_shares_30d'] as num).toInt()
          : 0;
      final scoreA = ua + (ra * 8.0) + (m30a * 5);
      final scoreB = ub + (rb * 8.0) + (m30b * 5);
      return scoreB.compareTo(scoreA);
    });

    return filtered;
  }

  Widget _buildCategoryChips(L10n l) {
    final isArabic = l.isArabic;
    final cats = <String>{};
    for (final p in _programs) {
      final haystack = _programSearchHaystack(p);
      if (haystack.isEmpty) continue;
      if (haystack.contains('bus') ||
          haystack.contains('ride') ||
          haystack.contains('transport') ||
          haystack.contains('mobility')) {
        cats.add('transport');
      } else if (haystack.contains('wallet') ||
          haystack.contains('pay') ||
          haystack.contains('payment') ||
          haystack.contains('payments')) {
        cats.add('wallet');
      } else if (haystack.contains('moments') ||
          haystack.contains('social') ||
          haystack.contains('people_nearby') ||
          haystack.contains('nearby') ||
          haystack.contains('sticker')) {
        cats.add('social');
      } else if (haystack.contains('channels') ||
          haystack.contains('media') ||
          haystack.contains('video')) {
        cats.add('media');
      } else if (haystack.contains('official') ||
          haystack.contains('service') ||
          haystack.contains('account') ||
          haystack.contains('verified')) {
        cats.add('services');
      } else if (haystack.contains('favorite') ||
          haystack.contains('bookmark') ||
          haystack.contains('personal') ||
          haystack.contains('saved')) {
        cats.add('tools');
      }
    }
    if (cats.isEmpty) {
      return const SizedBox.shrink();
    }
    String labelFor(String key) {
      switch (key) {
        case 'transport':
          return isArabic ? 'التنقل والنقل' : 'Transport';
        case 'wallet':
          return isArabic ? 'المحفظة والمدفوعات' : 'Wallet & payments';
        case 'social':
          return isArabic ? 'اجتماعي' : 'Social';
        case 'media':
          return isArabic ? 'الإعلام' : 'Media';
        case 'services':
          return isArabic ? 'الخدمات' : 'Services';
        case 'tools':
          return isArabic ? 'أدوات شخصية' : 'Personal tools';
        default:
          return key;
      }
    }

    final keys = cats.toList()..sort();
    return Wrap(
      spacing: 8,
      children: keys.map((key) {
        final selected = _categoryFilter == key;
        return ChoiceChip(
          label: Text(labelFor(key)),
          selected: selected,
          onSelected: (sel) {
            setState(() {
              _categoryFilter = sel ? key : null;
            });
          },
        );
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _computeTopPrograms(
    List<Map<String, dynamic>> list,
  ) {
    final items = <Map<String, dynamic>>[];
    for (final p in list) {
      final status = (p['status'] ?? '').toString().toLowerCase();
      if (!_miniProgramStatusIsPublished(status)) continue;
      final usage =
          (p['usage_score'] is num) ? (p['usage_score'] as num).toInt() : 0;
      final rating =
          (p['rating'] is num) ? (p['rating'] as num).toDouble() : 0.0;
      final m30 = (p['moments_shares_30d'] is num)
          ? (p['moments_shares_30d'] as num).toInt()
          : 0;
      final score = usage + (rating * 8.0) + (m30 * 5);
      final copy = Map<String, dynamic>.from(
        p.cast<String, dynamic>(),
      )..['__score'] = score;
      items.add(copy);
    }
    items.sort((a, b) {
      final sa = (a['__score'] is num) ? (a['__score'] as num).toDouble() : 0.0;
      final sb = (b['__score'] is num) ? (b['__score'] as num).toDouble() : 0.0;
      return sb.compareTo(sa);
    });
    final limit = items.length > 6 ? 6 : items.length;
    return items.sublist(0, limit);
  }

  // ignore: unused_element
  Widget _buildList(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    final term = _query.trim().toLowerCase();
    final filtered = _programs.where((p) {
      final status = (p['status'] ?? '').toString().toLowerCase();
      if (!_miniProgramStatusIsPublished(status)) return false;
      if (term.isNotEmpty) {
        if (!_programSearchHaystack(p).contains(term)) {
          return false;
        }
      }
      if (_mineOnly) {
        final contact = (p['owner_contact'] ?? '').toString().trim();
        final mine = (_myOwnerContact ?? '').isNotEmpty &&
            contact.isNotEmpty &&
            contact == _myOwnerContact;
        if (!mine) return false;
      }
      final usageScore =
          (p['usage_score'] is num) ? (p['usage_score'] as num).toInt() : 0;
      final ratingVal =
          (p['rating'] is num) ? (p['rating'] as num).toDouble() : 0.0;
      final moments30 = (p['moments_shares_30d'] is num)
          ? (p['moments_shares_30d'] as num).toInt()
          : 0;
      if (_trendingOnly) {
        final isTrending =
            usageScore >= 50 || ratingVal >= 4.5 || moments30 >= 5;
        if (!isTrending) return false;
      }
      if (!_matchesCategoryFilter(p, _categoryFilter)) {
        return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l.isArabic
                ? 'لا توجد برامج مصغّرة مطابقة.'
                : 'No matching mini‑programs.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .65),
            ),
          ),
        ),
      );
    }

    filtered.sort((a, b) {
      final ua =
          (a['usage_score'] is num) ? (a['usage_score'] as num).toInt() : 0;
      final ub =
          (b['usage_score'] is num) ? (b['usage_score'] as num).toInt() : 0;
      final ra = (a['rating'] is num) ? (a['rating'] as num).toDouble() : 0.0;
      final rb = (b['rating'] is num) ? (b['rating'] as num).toDouble() : 0.0;
      final m30a = (a['moments_shares_30d'] is num)
          ? (a['moments_shares_30d'] as num).toInt()
          : 0;
      final m30b = (b['moments_shares_30d'] is num)
          ? (b['moments_shares_30d'] as num).toInt()
          : 0;
      final scoreA = ua + (ra * 8.0) + (m30a * 5);
      final scoreB = ub + (rb * 8.0) + (m30b * 5);
      return scoreB.compareTo(scoreA);
    });

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final p = filtered[i];
        final appId = (p['app_id'] ?? '').toString();
        final titleEn = (p['title_en'] ?? '').toString();
        final titleAr = (p['title_ar'] ?? '').toString();
        final usage =
            (p['usage_score'] is num) ? (p['usage_score'] as num).toInt() : 0;
        final rating =
            (p['rating'] is num) ? (p['rating'] as num).toDouble() : 0.0;
        final moments30 = (p['moments_shares_30d'] is num)
            ? (p['moments_shares_30d'] as num).toInt()
            : 0;
        final title = isArabic && titleAr.isNotEmpty
            ? titleAr
            : (titleEn.isNotEmpty ? titleEn : appId);
        final desc = _programSubtitle(p, isArabic: isArabic);
        final ownerContact = (p['owner_contact'] ?? '').toString().trim();
        final isMine = (_myOwnerContact ?? '').isNotEmpty &&
            ownerContact.isNotEmpty &&
            ownerContact == _myOwnerContact;
        final scopesRaw = p['scopes'];
        final scopes = <String>[];
        if (scopesRaw is List) {
          for (final s in scopesRaw) {
            final v = (s ?? '').toString().trim().toLowerCase();
            if (v.isNotEmpty) scopes.add(v);
          }
        }
        final hasPaymentsScope =
            scopes.contains('payments') || scopes.contains('pay');
        final isPinned = _pinned.contains(appId);
        final isTrending = usage >= 50 || rating >= 4.5 || moments30 >= 5;

        final subtitleParts = <String>[];
        if (desc.isNotEmpty) {
          subtitleParts.add(desc);
        }
        if (rating > 0) {
          final ratingText = rating.toStringAsFixed(1);
          subtitleParts.add('⭐ $ratingText');
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Material(
            color: theme.colorScheme.surface.withValues(alpha: .98),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => unawaited(_openMiniProgram(appId)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.widgets_outlined,
                        size: 20,
                        color: theme.colorScheme.primary.withValues(alpha: .90),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isPinned) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.star,
                                  size: 14,
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: .85),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (isMine) ...[
                                _buildMiniBadge(
                                  theme: theme,
                                  label: isArabic ? 'برنامجي' : 'My app',
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (isTrending) ...[
                                _buildMiniBadge(
                                  theme: theme,
                                  label: isArabic ? 'شائع' : 'Trending',
                                  icon: Icons.local_fire_department_outlined,
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (hasPaymentsScope)
                                _buildMiniBadge(
                                  theme: theme,
                                  label:
                                      isArabic ? 'يدعم الدفع' : 'Pay‑enabled',
                                  icon: Icons.account_balance_wallet_outlined,
                                ),
                            ],
                          ),
                          if (subtitleParts.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitleParts.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .75),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniBadge({
    required ThemeData theme,
    required String label,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: .75),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.onSurface.withValues(alpha: .75),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedDotBadge(ThemeData theme, {double size = 8}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.redAccent,
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.colorScheme.surface,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildMiniProgramGridTile({
    required ThemeData theme,
    required double width,
    required String appId,
    required String title,
    required _IconSpec spec,
    required bool isPinned,
    required bool isRecent,
    required bool showPinnedBadge,
    required bool showUpdateBadge,
    VoidCallback? onTap,
  }) {
    Offset? downPos;
    final handleTap = onTap ?? () => unawaited(_openMiniProgram(appId));
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTapDown: (d) => downPos = d.globalPosition,
        onTap: handleTap,
        onLongPress: () => unawaited(
          _onMiniProgramLongPress(
            appId: appId,
            isPinned: isPinned,
            isRecent: isRecent,
            globalPosition: downPos,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                WeChatLeadingIcon(
                  icon: spec.icon,
                  background: spec.bg,
                  foreground: spec.fg,
                  size: 44,
                  iconSize: 20,
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                if (showPinnedBadge)
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .55),
                      ),
                    ),
                  ),
                if (showUpdateBadge)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: _buildRedDotBadge(theme),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedRow(L10n l, ThemeData theme) {
    final isArabic = l.isArabic;
    final byId = <String, Map<String, dynamic>>{};
    for (final p in _programs) {
      final appId = (p['app_id'] ?? '').toString();
      if (appId.isEmpty) continue;
      byId[appId] = p;
    }
    final pinnedIds = <String>[];
    final seen = <String>{};
    void addPinned(String raw) {
      final id = raw.trim();
      if (id.isEmpty) return;
      if (!seen.add(id)) return;
      if (!_pinned.contains(id)) return;
      if (!byId.containsKey(id)) return;
      pinnedIds.add(id);
    }

    for (final id in _pinnedOrder) {
      addPinned(id);
    }
    for (final id in _pinned) {
      addPinned(id);
    }

    final pinned = <Map<String, dynamic>>[
      for (final id in pinnedIds) byId[id]!,
    ];
    final hasBadge = pinnedIds.any(_updateBadgeIds.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              isArabic ? 'البرامج المصغّرة الخاصة بي' : 'My Mini Programs',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            if (hasBadge) ...[
              const SizedBox(width: 6),
              _buildRedDotBadge(theme),
            ],
            const Spacer(),
            TextButton(
              onPressed: () => unawaited(_openPinnedManage()),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                isArabic ? 'تعديل' : 'Edit',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (pinned.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              isArabic
                  ? 'اضغط مطولاً على أي برنامج مصغّر لتثبيته هنا.'
                  : 'Long‑press any mini‑program to pin it here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
              ),
            ),
          ),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final maxWidth = constraints.maxWidth;
            const spacing = 12.0;
            final columns = maxWidth >= 520 ? 5 : 4;
            final tileWidth = (maxWidth - spacing * (columns - 1)) / columns;
            final maxVisible = columns * 2;
            final visible = pinned.take(maxVisible - 1).toList();
            final hidden = pinned.skip(maxVisible - 1).toList();
            final showMoreUpdateBadge = hidden.any((p) {
              final id = (p['app_id'] ?? '').toString().trim();
              return id.isNotEmpty && _updateBadgeIds.contains(id);
            });
            return Wrap(
              spacing: spacing,
              runSpacing: 12,
              children: [
                for (final p in visible) ...[
                  Builder(
                    builder: (ctx) {
                      final appId = (p['app_id'] ?? '').toString();
                      final titleEn = (p['title_en'] ?? '').toString();
                      final titleAr = (p['title_ar'] ?? '').toString();
                      final title = isArabic && titleAr.isNotEmpty
                          ? titleAr
                          : (titleEn.isNotEmpty ? titleEn : appId);
                      final showUpdateBadge = _updateBadgeIds.contains(appId);
                      final spec = _iconSpecFor(appId);
                      final isRecent = _recentIds.contains(appId);
                      return _buildMiniProgramGridTile(
                        theme: theme,
                        width: tileWidth,
                        appId: appId,
                        title: title,
                        spec: spec,
                        isPinned: true,
                        isRecent: isRecent,
                        showPinnedBadge: false,
                        showUpdateBadge: showUpdateBadge,
                      );
                    },
                  ),
                ],
                SizedBox(
                  width: tileWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _openAllMiniProgramsDirectory,
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
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.more_horiz,
                                size: 22,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .55),
                              ),
                            ),
                            if (showMoreUpdateBadge)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: _buildRedDotBadge(theme),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isArabic ? 'المزيد' : 'More',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTopProgramsRow(L10n l, ThemeData theme) {
    final isArabic = l.isArabic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              isArabic
                  ? 'أفضل البرامج المصغّرة هذا الأسبوع'
                  : 'Top mini‑programs this week',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            if (_hasNewTopPrograms) ...[
              const SizedBox(width: 6),
              _buildRedDotBadge(theme),
            ],
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final maxWidth = constraints.maxWidth;
            const spacing = 12.0;
            final columns = maxWidth >= 520 ? 5 : 4;
            final tileWidth = (maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: 12,
              children: _topPrograms.map((p) {
                final appId = (p['app_id'] ?? '').toString();
                final titleEn = (p['title_en'] ?? '').toString();
                final titleAr = (p['title_ar'] ?? '').toString();
                final ownerContact =
                    (p['owner_contact'] ?? '').toString().trim();
                final isMine = (_myOwnerContact ?? '').isNotEmpty &&
                    ownerContact.isNotEmpty &&
                    ownerContact == _myOwnerContact;
                final title = isArabic && titleAr.isNotEmpty
                    ? titleAr
                    : (titleEn.isNotEmpty ? titleEn : appId);
                final label = isMine ? (isArabic ? 'برنامجي' : 'My') : title;
                final isPinned = _pinned.contains(appId);
                final isRecent = _recentIds.contains(appId);
                final showUpdateBadge = _updateBadgeIds.contains(appId);
                final spec = _iconSpecFor(appId);
                return _buildMiniProgramGridTile(
                  theme: theme,
                  width: tileWidth,
                  appId: appId,
                  title: label,
                  spec: spec,
                  isPinned: isPinned,
                  isRecent: isRecent,
                  showPinnedBadge: isPinned,
                  showUpdateBadge: showUpdateBadge,
                  onTap: () {
                    unawaited(_markTopProgramsSeen());
                    unawaited(_openMiniProgram(appId));
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecommendedRow(L10n l, ThemeData theme) {
    final isArabic = l.isArabic;
    final recommended = <Map<String, dynamic>>[];
    final seen = <String>{};
    void addProgram(Map<String, dynamic> p) {
      final id = (p['app_id'] ?? '').toString().trim();
      if (id.isEmpty) return;
      if (!seen.add(id)) return;
      recommended.add(p);
    }

    for (final p in _topPrograms) {
      final id = (p['app_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      if (_pinned.contains(id) || _recentIds.contains(id)) continue;
      addProgram(p);
    }
    if (recommended.length < 4) {
      for (final p in _topPrograms) {
        addProgram(p);
        if (recommended.length >= 6) break;
      }
    }
    if (recommended.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              isArabic ? 'اقتراحات لك' : 'Recommended for you',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            if (_hasNewTopPrograms) ...[
              const SizedBox(width: 6),
              _buildRedDotBadge(theme),
            ],
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final maxWidth = constraints.maxWidth;
            const spacing = 12.0;
            final columns = maxWidth >= 520 ? 5 : 4;
            final tileWidth = (maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: 12,
              children: recommended.take(columns * 2).map((p) {
                final appId = (p['app_id'] ?? '').toString();
                final titleEn = (p['title_en'] ?? '').toString();
                final titleAr = (p['title_ar'] ?? '').toString();
                final title = isArabic && titleAr.isNotEmpty
                    ? titleAr
                    : (titleEn.isNotEmpty ? titleEn : appId);
                final isPinned = _pinned.contains(appId);
                final isRecent = _recentIds.contains(appId);
                final showUpdateBadge = _updateBadgeIds.contains(appId);
                final spec = _iconSpecFor(appId);
                return _buildMiniProgramGridTile(
                  theme: theme,
                  width: tileWidth,
                  appId: appId,
                  title: title,
                  spec: spec,
                  isPinned: isPinned,
                  isRecent: isRecent,
                  showPinnedBadge: isPinned,
                  showUpdateBadge: showUpdateBadge,
                  onTap: () {
                    unawaited(_markTopProgramsSeen());
                    unawaited(_openMiniProgram(appId));
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecentRow(L10n l, ThemeData theme) {
    final isArabic = l.isArabic;
    final byId = <String, Map<String, dynamic>>{};
    for (final p in _programs) {
      final appId = (p['app_id'] ?? '').toString();
      if (appId.isEmpty) continue;
      byId[appId] = p;
    }
    final recent = <Map<String, dynamic>>[];
    for (final id in _recentIds) {
      final p = byId[id];
      if (p != null) {
        recent.add(p);
      }
    }
    final hasBadge = recent.any((p) {
      final appId = (p['app_id'] ?? '').toString().trim();
      return appId.isNotEmpty && _updateBadgeIds.contains(appId);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l.isArabic ? 'المستخدمة مؤخراً' : 'Recent mini programs',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            if (hasBadge) ...[
              const SizedBox(width: 6),
              _buildRedDotBadge(theme),
            ],
            const Spacer(),
          ],
        ),
        const SizedBox(height: 6),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              isArabic
                  ? 'ستظهر البرامج المصغّرة التي فتحتها مؤخراً هنا.'
                  : 'Mini‑programs you open will show up here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
              ),
            ),
          ),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final maxWidth = constraints.maxWidth;
            const spacing = 12.0;
            final columns = maxWidth >= 520 ? 5 : 4;
            final tileWidth = (maxWidth - spacing * (columns - 1)) / columns;
            final maxVisible = columns * 2;
            final visible = recent.take(maxVisible - 1).toList();
            final hidden = recent.skip(maxVisible - 1).toList();
            final showMoreUpdateBadge = hidden.any((p) {
              final id = (p['app_id'] ?? '').toString().trim();
              return id.isNotEmpty && _updateBadgeIds.contains(id);
            });
            return Wrap(
              spacing: spacing,
              runSpacing: 12,
              children: [
                for (final p in visible) ...[
                  Builder(
                    builder: (ctx) {
                      final appId = (p['app_id'] ?? '').toString();
                      final titleEn = (p['title_en'] ?? '').toString();
                      final titleAr = (p['title_ar'] ?? '').toString();
                      final title = isArabic && titleAr.isNotEmpty
                          ? titleAr
                          : (titleEn.isNotEmpty ? titleEn : appId);
                      final isPinned = _pinned.contains(appId);
                      final showUpdateBadge = _updateBadgeIds.contains(appId);
                      final spec = _iconSpecFor(appId);
                      return _buildMiniProgramGridTile(
                        theme: theme,
                        width: tileWidth,
                        appId: appId,
                        title: title,
                        spec: spec,
                        isPinned: isPinned,
                        isRecent: true,
                        showPinnedBadge: isPinned,
                        showUpdateBadge: showUpdateBadge,
                      );
                    },
                  ),
                ],
                SizedBox(
                  width: tileWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => unawaited(_openRecentsManage()),
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
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.more_horiz,
                                size: 22,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .55),
                              ),
                            ),
                            if (showMoreUpdateBadge)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: _buildRedDotBadge(theme),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isArabic ? 'المزيد' : 'More',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildDeveloperSummaryBanner(L10n l, ThemeData theme) {
    final summary = _devSummary ?? const <String, dynamic>{};
    final totalApps = (summary['total_apps'] as int?) ?? 0;
    final activeApps = (summary['active_apps'] as int?) ?? 0;
    final totalUsage = (summary['total_usage'] as int?) ?? 0;
    final totalMoments = (summary['total_moments_shares'] as int?) ?? 0;
    final hasPaymentsScope = (summary['has_payments_scope'] as bool?) ?? false;
    if (totalApps <= 0) {
      return const SizedBox.shrink();
    }
    final isArabic = l.isArabic;
    final headline = isArabic
        ? 'لوحة مطوّر البرامج المصغّرة'
        : 'Mini‑programs developer overview';
    final line1 = isArabic
        ? 'التطبيقات: $totalApps، النشطة: $activeApps'
        : 'Apps: $totalApps, active: $activeApps';
    final line2 = isArabic
        ? 'الفتحات الإجمالية: $totalUsage · مشاركات اللحظات: $totalMoments'
        : 'Total opens: $totalUsage · Moments shares: $totalMoments';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .98),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: .04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.insights_outlined,
            size: 20,
            color: theme.colorScheme.primary.withValues(alpha: .90),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  ),
                ),
                Text(
                  line2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MyMiniProgramsPage(
                    baseUrl: widget.baseUrl,
                    walletId: widget.walletId,
                    deviceId: widget.deviceId,
                    onOpenMod: widget.onOpenMod,
                  ),
                ),
              );
            },
            child: Text(
              isArabic ? 'فتح اللوحة' : 'Open dashboard',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (hasPaymentsScope) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 12,
                    color: theme.colorScheme.secondary.withValues(alpha: .85),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    isArabic ? 'يدعم الدفع' : 'Pay‑enabled',
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.secondary.withValues(alpha: .85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniProgramsPinnedManagePage extends StatefulWidget {
  final List<String> pinnedIds;
  final List<String> suggestedIds;
  final Map<String, String> titleById;
  final _IconSpec Function(String appId) iconSpecFor;
  final Future<void> Function(String appId) onTogglePinned;
  final Future<void> Function(List<String> orderedIds) onSaveOrder;

  const _MiniProgramsPinnedManagePage({
    required this.pinnedIds,
    required this.suggestedIds,
    required this.titleById,
    required this.iconSpecFor,
    required this.onTogglePinned,
    required this.onSaveOrder,
  });

  @override
  State<_MiniProgramsPinnedManagePage> createState() =>
      _MiniProgramsPinnedManagePageState();
}

class _MiniProgramsPinnedManagePageState
    extends State<_MiniProgramsPinnedManagePage> {
  late List<String> _ids;

  @override
  void initState() {
    super.initState();
    _ids = List<String>.from(widget.pinnedIds);
  }

  Future<void> _persist() async {
    await widget.onSaveOrder(_ids);
  }

  Future<void> _removeId(String id) async {
    await widget.onTogglePinned(id);
    if (!mounted) return;
    setState(() {
      _ids.removeWhere((e) => e == id);
    });
    unawaited(_persist());
  }

  Future<void> _addId(String id) async {
    final clean = id.trim();
    if (clean.isEmpty) return;
    if (_ids.contains(clean)) return;
    await widget.onTogglePinned(clean);
    if (!mounted) return;
    setState(() {
      _ids.insert(0, clean);
    });
    unawaited(_persist());
  }

  Future<void> _moveId(String draggedId, int newIndex) async {
    final oldIndex = _ids.indexOf(draggedId);
    if (oldIndex < 0) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= _ids.length) return;
    if (target == oldIndex) return;
    setState(() {
      final item = _ids.removeAt(oldIndex);
      _ids.insert(target, item);
    });
    unawaited(_persist());
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : WeChatPalette.background;

    final pinnedSet = _ids.toSet();
    final addableIds = <String>[];
    final addableSeen = <String>{};
    for (final raw in widget.suggestedIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (!addableSeen.add(id)) continue;
      if (pinnedSet.contains(id)) continue;
      addableIds.add(id);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          isArabic ? 'البرامج المصغّرة الخاصة بي' : 'My Mini Programs',
        ),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: () async {
              await _persist();
              if (!mounted) return;
              Navigator.pop(context, _ids);
            },
            child: Text(
              isArabic ? 'تم' : 'Done',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final maxWidth = constraints.maxWidth;
          const spacing = 12.0;
          final columns = maxWidth >= 520 ? 5 : 4;
          final tileWidth = (maxWidth - 32 - spacing * (columns - 1)) / columns;

          Widget iconTile({
            required String id,
            required String title,
            required _IconSpec spec,
            required bool highlight,
            required bool dimmed,
            Widget? cornerBadge,
          }) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: highlight
                    ? theme.colorScheme.primary.withValues(alpha: .06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Opacity(
                opacity: dimmed ? 0.35 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        WeChatLeadingIcon(
                          icon: spec.icon,
                          background: spec.bg,
                          foreground: spec.fg,
                          size: 46,
                          iconSize: 20,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
                        ),
                        if (cornerBadge != null) cornerBadge,
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          Widget removeBadge(String id) {
            return Positioned(
              left: -6,
              top: -6,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => unawaited(_removeId(id)),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFA5151),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.remove,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          }

          Widget addBadge(String id) {
            return Positioned(
              left: -6,
              top: -6,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => unawaited(_addId(id)),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Tokens.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          }

          Widget pinnedGrid() {
            if (_ids.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Text(
                  isArabic
                      ? 'لا توجد برامج مصغّرة مثبّتة بعد.'
                      : 'No pinned mini‑programs yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: 0.9,
              ),
              itemCount: _ids.length,
              itemBuilder: (ctx, i) {
                final id = _ids[i];
                final title = widget.titleById[id] ?? id;
                final spec = widget.iconSpecFor(id);

                return DragTarget<String>(
                  onWillAcceptWithDetails: (details) => details.data != id,
                  onAcceptWithDetails: (details) =>
                      unawaited(_moveId(details.data, i)),
                  builder: (ctx, candidate, _) {
                    final highlight = candidate.isNotEmpty;
                    final child = iconTile(
                      id: id,
                      title: title,
                      spec: spec,
                      highlight: highlight,
                      dimmed: false,
                      cornerBadge: removeBadge(id),
                    );
                    return LongPressDraggable<String>(
                      data: id,
                      feedback: Material(
                        color: Colors.transparent,
                        child: SizedBox(
                          width: tileWidth,
                          child: iconTile(
                            id: id,
                            title: title,
                            spec: spec,
                            highlight: false,
                            dimmed: false,
                            cornerBadge: removeBadge(id),
                          ),
                        ),
                      ),
                      childWhenDragging: iconTile(
                        id: id,
                        title: title,
                        spec: spec,
                        highlight: false,
                        dimmed: true,
                        cornerBadge: removeBadge(id),
                      ),
                      child: child,
                    );
                  },
                );
              },
            );
          }

          Widget addableGrid() {
            if (addableIds.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Text(
                  isArabic
                      ? 'لا توجد اقتراحات حالياً.'
                      : 'No suggestions right now.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: 0.9,
              ),
              itemCount: addableIds.length,
              itemBuilder: (ctx, i) {
                final id = addableIds[i];
                final title = widget.titleById[id] ?? id;
                final spec = widget.iconSpecFor(id);
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => unawaited(_addId(id)),
                  child: iconTile(
                    id: id,
                    title: title,
                    spec: spec,
                    highlight: false,
                    dimmed: false,
                    cornerBadge: addBadge(id),
                  ),
                );
              },
            );
          }

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  isArabic
                      ? 'اسحب لإعادة الترتيب، اضغط − للإزالة، واضغط + للإضافة.'
                      : 'Drag to reorder, tap − to remove, tap + to add.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  isArabic ? 'مثبتة' : 'Pinned',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  ),
                ),
              ),
              pinnedGrid(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  isArabic ? 'إضافة المزيد' : 'Add more',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  ),
                ),
              ),
              addableGrid(),
            ],
          );
        },
      ),
    );
  }
}

class _MiniProgramsRecentsManagePage extends StatefulWidget {
  final List<String> recentIds;
  final Map<String, String> titleById;
  final _IconSpec Function(String appId) iconSpecFor;
  final Future<void> Function(String appId) onRemove;
  final Future<void> Function() onClear;

  const _MiniProgramsRecentsManagePage({
    required this.recentIds,
    required this.titleById,
    required this.iconSpecFor,
    required this.onRemove,
    required this.onClear,
  });

  @override
  State<_MiniProgramsRecentsManagePage> createState() =>
      _MiniProgramsRecentsManagePageState();
}

class _MiniProgramsRecentsManagePageState
    extends State<_MiniProgramsRecentsManagePage> {
  late List<String> _ids;

  @override
  void initState() {
    super.initState();
    _ids = List<String>.from(widget.recentIds);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : WeChatPalette.background;

    Future<void> confirmClear() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(isArabic ? 'مسح الأخيرة' : 'Clear recents'),
            content: Text(
              isArabic
                  ? 'سيؤدي ذلك إلى إزالة كل البرامج المصغّرة المستخدمة مؤخراً.'
                  : 'This will remove all recently used mini‑programs.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(isArabic ? 'إلغاء' : 'Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  isArabic ? 'مسح' : 'Clear',
                  style: const TextStyle(color: Color(0xFFFA5151)),
                ),
              ),
            ],
          );
        },
      );
      if (ok != true || !mounted) return;
      await widget.onClear();
      if (!mounted) return;
      setState(() => _ids = const <String>[]);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'المستخدمة مؤخراً' : 'Recent mini programs'),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: _ids.isEmpty ? null : confirmClear,
            child: Text(
              isArabic ? 'مسح' : 'Clear',
              style: TextStyle(
                color: _ids.isEmpty
                    ? theme.colorScheme.onSurface.withValues(alpha: .35)
                    : const Color(0xFFFA5151),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _ids.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  isArabic
                      ? 'ستظهر البرامج المصغّرة التي فتحتها مؤخراً هنا.'
                      : 'Mini‑programs you open will show up here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ),
            )
          : ListView.builder(
              itemCount: _ids.length,
              padding: const EdgeInsets.only(bottom: 24),
              itemBuilder: (ctx, i) {
                final id = _ids[i];
                final title = widget.titleById[id] ?? id;
                final spec = widget.iconSpecFor(id);
                final isLast = i == _ids.length - 1;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: theme.colorScheme.surface,
                      child: ListTile(
                        dense: true,
                        leading: WeChatLeadingIcon(
                          icon: spec.icon,
                          background: spec.bg,
                          foreground: spec.fg,
                          size: 36,
                          iconSize: 18,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(10)),
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: IconButton(
                          tooltip: isArabic ? 'إزالة' : 'Remove',
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color:
                                theme.colorScheme.error.withValues(alpha: .9),
                          ),
                          onPressed: () async {
                            await widget.onRemove(id);
                            if (!mounted) return;
                            setState(() {
                              _ids.removeAt(i);
                            });
                          },
                        ),
                      ),
                    ),
                    if (!isLast)
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
    );
  }
}

class _WeChatPopoverDownArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WeChatPopoverDownArrowClipper oldClipper) => false;
}

class _WeChatPopoverUpArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WeChatPopoverUpArrowClipper oldClipper) => false;
}
