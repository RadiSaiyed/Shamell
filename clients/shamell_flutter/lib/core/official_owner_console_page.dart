import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shamell_flutter/core/account_privilege_store.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'http_error.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart' as qr;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart' show LoginPage;

import 'access_platform_contracts.dart';
import 'design_tokens.dart';
import 'base_url.dart';
import 'device_binding_reauth.dart';
import 'format.dart' show fmtCents;
import 'l10n.dart';
import 'official_account_models.dart'
    show
        OfficialAccountHandle,
        normalizeOfficialQrPayload,
        normalizeOfficialRemoteImageUrl,
        normalizeOfficialRemoteImageUrlForAutoload,
        normalizeOfficialRemoteWebsiteUrl;
import 'official_moments_comments_page.dart';
import 'official_owners_access_page.dart';
import 'official_service_inbox_page.dart';
import 'payments/payments_idempotency.dart';
import 'cards_offers_page.dart';
import 'app_shell_widgets.dart' show AppBG;
import 'safe_clipboard.dart';
import 'safe_set_state.dart';
import 'shamell_loading_shimmer.dart';
import 'shamell_pinned_remote_image.dart';

class OfficialOwnerConsolePage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final http.Client? httpClient;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;

  const OfficialOwnerConsolePage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    this.httpClient,
    this.privilegeSnapshotOverride,
  });

  @override
  State<OfficialOwnerConsolePage> createState() =>
      _OfficialOwnerConsolePageState();
}

class _OfficialOwnerConsolePageState extends State<OfficialOwnerConsolePage>
    with SafeSetStateMixin<OfficialOwnerConsolePage> {
  static const String _pageStorageStateIdentifier =
      'official_owner_console_ui_state';
  static const Duration _officialOwnerRequestTimeout = Duration(seconds: 15);
  static const int _officialAutoRepliesPageSize = 200;
  static const String _officialOwnerWorkspaceAll = 'all';
  static const String _officialOwnerWorkspaceService = 'service';
  static const String _officialOwnerWorkspaceAccess = 'access';
  static const String _officialOwnerWorkspacePublishing = 'publishing';
  static const String _officialOwnerWorkspaceCommerce = 'commerce';
  static const String _officialOwnerWorkspaceAutomation = 'automation';
  static const String _officialOwnerWorkspaceProfile = 'profile';
  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loading = true;
  bool _loadingPrivileges = true;
  bool _readAccessAllowed = false;
  bool _writeAccessAllowed = false;
  String _error = '';
  OfficialAccountHandle? _account;
  Map<String, dynamic>? _momentsStats;
  Map<String, dynamic>? _campaignDashboard;
  List<Map<String, dynamic>> _greenPaketCampaigns =
      const <Map<String, dynamic>>[];
  Map<String, dynamic>? _cardsDashboard;
  List<Map<String, dynamic>> _cardOffers = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _autoReplies = const <Map<String, dynamic>>[];
  String _selectedWorkspace = _officialOwnerWorkspaceAll;
  final Set<String> _collapsedWorkspaces = <String>{};
  bool _autoRepliesLoadingMore = false;
  bool _autoRepliesHasMore = false;
  AccountPrivilegeSnapshot _privileges = AccountPrivilegeSnapshot.empty;
  bool _restoredStoredState = false;
  final GlobalKey _serviceWorkspaceSectionKey = GlobalKey(
    debugLabel: 'officialOwnerServiceDesk',
  );
  final GlobalKey _accessWorkspaceSectionKey = GlobalKey(
    debugLabel: 'officialOwnerAccessDesk',
  );
  final GlobalKey _publishingWorkspaceSectionKey = GlobalKey(
    debugLabel: 'officialOwnerPublishingDesk',
  );
  final GlobalKey _commerceWorkspaceSectionKey = GlobalKey(
    debugLabel: 'officialOwnerCommerceDesk',
  );
  final GlobalKey _automationWorkspaceSectionKey = GlobalKey(
    debugLabel: 'officialOwnerAutomationDesk',
  );
  final GlobalKey _profileWorkspaceSectionKey = GlobalKey(
    debugLabel: 'officialOwnerProfileDesk',
  );

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? shamellHttpClient();
    _loadPrivilegesAndData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredStoredState) {
      return;
    }
    _restoredStoredState = true;
    final stored = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _pageStorageStateIdentifier);
    if (stored is! Map) {
      return;
    }
    final selectedWorkspace = stored['selectedWorkspace'];
    const knownWorkspaces = <String>{
      _officialOwnerWorkspaceAll,
      _officialOwnerWorkspaceService,
      _officialOwnerWorkspaceAccess,
      _officialOwnerWorkspacePublishing,
      _officialOwnerWorkspaceCommerce,
      _officialOwnerWorkspaceAutomation,
      _officialOwnerWorkspaceProfile,
    };
    if (selectedWorkspace is String &&
        knownWorkspaces.contains(selectedWorkspace)) {
      _selectedWorkspace = selectedWorkspace;
    }
    final collapsedWorkspaces = stored['collapsedWorkspaces'];
    if (collapsedWorkspaces is List) {
      _collapsedWorkspaces
        ..clear()
        ..addAll(
          collapsedWorkspaces
              .map((entry) => entry.toString().trim())
              .where((entry) => knownWorkspaces.contains(entry))
              .where((entry) => entry != _officialOwnerWorkspaceAll),
        );
    }
    if (_selectedWorkspace != _officialOwnerWorkspaceAll) {
      _collapsedWorkspaces.remove(_selectedWorkspace);
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<void> _loadPrivilegesAndData() async {
    final snapshot = widget.privilegeSnapshotOverride ??
        await loadAccountPrivilegeSnapshotForBaseUrl(widget.baseUrl);
    if (!mounted) return;
    final readAccess = shamellHasOfficialDashboardReadSnapshotAccess(
      snapshot,
      widget.accountId,
    );
    final writeAccess = shamellHasOfficialDashboardWriteSnapshotAccess(
      snapshot,
      widget.accountId,
    );
    setState(() {
      _privileges = snapshot;
      _loadingPrivileges = false;
      _readAccessAllowed = readAccess;
      _writeAccessAllowed = writeAccess;
      _loading = readAccess;
    });
    if (!readAccess) {
      return;
    }
    await _load();
  }

  Future<Map<String, String>> _hdr({bool jsonBody = false}) async {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl, json: jsonBody);
  }

  Uri? _ownerAdminUri({
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: pathSegments,
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage({bool? isArabic}) {
    final arabic = isArabic ?? L10n.of(context).isArabic;
    return arabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
  }

  Uri? _autoRepliesUri({int? afterId}) {
    final queryParameters = <String, String>{
      'limit': '$_officialAutoRepliesPageSize',
    };
    if (afterId != null && afterId > 0) {
      queryParameters['after_id'] = '$afterId';
    }
    return _ownerAdminUri(
      pathSegments: <String>[
        'admin',
        'official_accounts',
        widget.accountId,
        'auto_replies',
      ],
      queryParameters: queryParameters,
    );
  }

  List<Map<String, dynamic>> _decodeAutoReplies(dynamic decoded) {
    final rules = <Map<String, dynamic>>[];
    if (decoded is Map && decoded['rules'] is List) {
      for (final e in decoded['rules'] as List) {
        if (e is Map) {
          rules.add(e.cast<String, dynamic>());
        }
      }
    }
    return rules;
  }

  List<Map<String, dynamic>> _decodeCardOffers(dynamic decoded) {
    final offers = <Map<String, dynamic>>[];
    if (decoded is Map && decoded['offers'] is List) {
      for (final e in decoded['offers'] as List) {
        if (e is Map) {
          offers.add(e.cast<String, dynamic>());
        }
      }
    }
    return offers;
  }

  List<Map<String, dynamic>> _decodeGreenPaketCampaigns(dynamic decoded) {
    final campaigns = <Map<String, dynamic>>[];
    if (decoded is Map && decoded['campaigns'] is List) {
      for (final e in decoded['campaigns'] as List) {
        if (e is Map) {
          campaigns.add(e.cast<String, dynamic>());
        }
      }
    }
    return campaigns;
  }

  List<Map<String, dynamic>> _mergeAutoReplies(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final merged = <Map<String, dynamic>>[...current];
    final seen = current.map(_autoReplyMergeKey).toSet();
    for (final rule in incoming) {
      if (seen.add(_autoReplyMergeKey(rule))) {
        merged.add(rule);
      }
    }
    return merged;
  }

  String _autoReplyMergeKey(Map<String, dynamic> rule) {
    final id = (rule['id'] as num?)?.toInt() ?? 0;
    if (id > 0) {
      return 'id:$id';
    }
    final kind = (rule['kind'] ?? '').toString().trim();
    final keyword = (rule['keyword'] ?? '').toString().trim();
    final text = (rule['text'] ?? '').toString().trim();
    return 'rule:$kind|$keyword|$text';
  }

  bool _isWorkspaceVisible(String workspaceId) {
    return _selectedWorkspace == _officialOwnerWorkspaceAll ||
        _selectedWorkspace == workspaceId;
  }

  List<String> _visibleWorkspaces({
    required List<String> availableWorkspaces,
    required String selectedWorkspace,
  }) {
    if (selectedWorkspace == _officialOwnerWorkspaceAll) {
      return availableWorkspaces;
    }
    return availableWorkspaces
        .where((workspace) => workspace == selectedWorkspace)
        .toList(growable: false);
  }

  GlobalKey _workspaceSectionKey(String workspaceId) {
    switch (workspaceId) {
      case _officialOwnerWorkspaceService:
        return _serviceWorkspaceSectionKey;
      case _officialOwnerWorkspaceAccess:
        return _accessWorkspaceSectionKey;
      case _officialOwnerWorkspacePublishing:
        return _publishingWorkspaceSectionKey;
      case _officialOwnerWorkspaceCommerce:
        return _commerceWorkspaceSectionKey;
      case _officialOwnerWorkspaceAutomation:
        return _automationWorkspaceSectionKey;
      case _officialOwnerWorkspaceProfile:
        return _profileWorkspaceSectionKey;
      default:
        return GlobalKey(debugLabel: 'officialOwnerFallbackDesk');
    }
  }

  void _persistConsoleUiState() {
    PageStorage.maybeOf(context)?.writeState(
      context,
      <String, Object?>{
        'selectedWorkspace': _selectedWorkspace,
        'collapsedWorkspaces': _collapsedWorkspaces.toList(growable: false),
      },
      identifier: _pageStorageStateIdentifier,
    );
  }

  void _setSelectedWorkspace(String workspaceId) {
    if (_selectedWorkspace == workspaceId) {
      return;
    }
    setState(() {
      _selectedWorkspace = workspaceId;
      if (workspaceId != _officialOwnerWorkspaceAll) {
        _collapsedWorkspaces.remove(workspaceId);
      }
    });
    _persistConsoleUiState();
  }

  void _toggleWorkspaceCollapsed(String workspaceId) {
    setState(() {
      if (_collapsedWorkspaces.contains(workspaceId)) {
        _collapsedWorkspaces.remove(workspaceId);
      } else {
        _collapsedWorkspaces.add(workspaceId);
      }
    });
    _persistConsoleUiState();
  }

  void _collapseVisibleWorkspaces({
    required List<String> availableWorkspaces,
    required String selectedWorkspace,
  }) {
    setState(() {
      _collapsedWorkspaces.addAll(
        _visibleWorkspaces(
          availableWorkspaces: availableWorkspaces,
          selectedWorkspace: selectedWorkspace,
        ),
      );
    });
    _persistConsoleUiState();
  }

  void _expandVisibleWorkspaces({
    required List<String> availableWorkspaces,
    required String selectedWorkspace,
  }) {
    setState(() {
      _collapsedWorkspaces.removeAll(
        _visibleWorkspaces(
          availableWorkspaces: availableWorkspaces,
          selectedWorkspace: selectedWorkspace,
        ),
      );
    });
    _persistConsoleUiState();
  }

  void _focusWorkspaceFromCommandDesk(String workspaceId) {
    _setSelectedWorkspace(workspaceId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sectionContext = _workspaceSectionKey(workspaceId).currentContext;
      if (sectionContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: .06,
      );
    });
  }

  Future<void> _copyOfficialQrPayload(String payload) async {
    final normalized = payload.trim();
    if (normalized.isEmpty) {
      return;
    }
    await shamellCopyToClipboard(normalized);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context).copiedLabel)),
    );
  }

  Future<void> _showOfficialQrShareSheet(String payload) async {
    final normalized = payload.trim();
    if (normalized.isEmpty || !mounted) {
      return;
    }
    final l = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _OfficialQrSharePanel(
        payload: normalized,
        title: l.isArabic ? 'مشاركة QR للحساب' : 'Official QR share',
        closeLabel: l.isArabic ? 'إغلاق' : 'Close',
      ),
    );
  }

  Future<void> _showOfficialQrPosterSheet(
    OfficialAccountHandle acc, {
    String? payloadOverride,
  }) async {
    final normalized = normalizeOfficialQrPayload(
      payloadOverride ?? acc.qrPayload,
    );
    if (normalized == null || !mounted) {
      return;
    }
    final l = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _OfficialQrPosterPanel(
        title: l.isArabic ? 'ملصق QR للحساب' : 'Official QR poster',
        subtitle: l.isArabic
            ? 'معاينة جاهزة للطباعة أو العرض على الكاونتر قبل نشر الحساب.'
            : 'A compact preview for print or counter display before distributing the account.',
        closeLabel: l.isArabic ? 'إغلاق' : 'Close',
        copyPathLabel: l.isArabic ? 'نسخ المسار' : 'Copy path',
        saveLabel: l.isArabic ? 'حفظ الملصق' : 'Save poster',
        shareLabel: l.isArabic ? 'مشاركة الملصق' : 'Share poster',
        accountName: acc.name,
        payload: normalized,
        category: acc.category,
        city: acc.city,
        address: acc.address,
        openingHours: acc.openingHours,
        websiteUrl: acc.websiteUrl,
        isArabic: l.isArabic,
        onCopyPosterPath: () => _copyOfficialQrPosterPath(acc),
        onSavePoster: () => _saveOfficialQrPoster(
          acc,
          payloadOverride: normalized,
        ),
        onSharePoster: () => _shareOfficialQrPoster(
          acc,
          payloadOverride: normalized,
        ),
      ),
    );
  }

  Future<void> _copyOfficialQrPosterPath(OfficialAccountHandle acc) async {
    if (kIsWeb) {
      if (!mounted) return;
      final l = L10n.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'مسار الملصق غير متاح على الويب.'
                  : 'Poster paths are not available on web.',
            ),
          ),
        );
      return;
    }
    try {
      final file = await _resolveOfficialQrPosterFile(acc.id);
      await shamellCopyToClipboard(file.path);
      if (!mounted) return;
      final l = L10n.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تم نسخ مسار الملصق.' : 'Poster path copied.',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      final l = L10n.of(context);
      final detail = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر نسخ المسار: $detail'
                  : 'Copy path failed: $detail',
            ),
          ),
        );
    }
  }

  Future<void> _saveOfficialQrPoster(
    OfficialAccountHandle acc, {
    String? payloadOverride,
  }) async {
    if (kIsWeb) {
      if (!mounted) return;
      final l = L10n.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'حفظ الملصق غير مدعوم على الويب.'
                  : 'Saving posters is not supported on web.',
            ),
          ),
        );
      return;
    }
    final normalized = normalizeOfficialQrPayload(
      payloadOverride ?? acc.qrPayload,
    );
    if (normalized == null || !mounted) {
      return;
    }
    final l = L10n.of(context);
    try {
      final bytes = _buildOfficialQrPosterSvg(
        accountName: acc.name,
        payload: normalized,
        category: acc.category,
        city: acc.city,
        address: acc.address,
        openingHours: acc.openingHours,
        isArabic: l.isArabic,
        colorScheme: Theme.of(context).colorScheme,
      );
      final file = await _resolveOfficialQrPosterFile(acc.id);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تم حفظ الملصق.' : 'Poster saved.',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      final detail = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تعذّر حفظ الملصق: $detail' : 'Save failed: $detail',
            ),
          ),
        );
    }
  }

  Future<File> _resolveOfficialQrPosterFile(String accountId) async {
    final baseDir = await _resolveOfficialQrPosterSaveBaseDirectory();
    return File(
      '${baseDir.path}/official_qr_posters/official_${accountId}_qr_poster.svg',
    );
  }

  Future<Directory> _resolveOfficialQrPosterSaveBaseDirectory() async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        return downloadsDir;
      }
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  Future<void> _shareOfficialQrPoster(
    OfficialAccountHandle acc, {
    String? payloadOverride,
  }) async {
    final normalized = normalizeOfficialQrPayload(
      payloadOverride ?? acc.qrPayload,
    );
    if (normalized == null || !mounted) {
      return;
    }
    final l = L10n.of(context);
    try {
      final bytes = _buildOfficialQrPosterSvg(
        accountName: acc.name,
        payload: normalized,
        category: acc.category,
        city: acc.city,
        address: acc.address,
        openingHours: acc.openingHours,
        isArabic: l.isArabic,
        colorScheme: Theme.of(context).colorScheme,
      );
      final fileName = 'official_${acc.id}_qr_poster.svg';
      final file = XFile.fromData(
        bytes,
        mimeType: 'image/svg+xml',
        name: fileName,
      );
      await Share.shareXFiles(
        [file],
        text:
            l.isArabic ? 'ملصق QR للحساب ${acc.name}' : '${acc.name} QR poster',
        fileNameOverrides: [fileName],
      );
    } catch (e) {
      if (!mounted) return;
      final detail = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'فشل مشاركة الملصق: $detail'
                  : 'Share failed: $detail',
            ),
          ),
        );
    }
  }

  Future<void> _loadMoreAutoReplies() async {
    if (_loading ||
        _autoRepliesLoadingMore ||
        !_autoRepliesHasMore ||
        _autoReplies.isEmpty) {
      return;
    }
    final l = L10n.of(context);
    final afterId = (_autoReplies.last['id'] as num?)?.toInt() ?? 0;
    if (afterId <= 0) {
      setState(() {
        _autoRepliesHasMore = false;
      });
      return;
    }
    setState(() {
      _autoRepliesLoadingMore = true;
    });
    try {
      final uri = _autoRepliesUri(afterId: afterId);
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _autoRepliesLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_invalidServerUrlMessage(isArabic: l.isArabic))),
        );
        return;
      }
      final r = await _http
          .get(uri, headers: await _hdr())
          .timeout(_officialOwnerRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _autoRepliesLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sanitizeHttpError(
                statusCode: r.statusCode,
                rawBody: r.body,
                isArabic: l.isArabic,
              ),
            ),
          ),
        );
        return;
      }
      final rules = _decodeAutoReplies(jsonDecode(r.body));
      if (!mounted) return;
      setState(() {
        _autoReplies = _mergeAutoReplies(_autoReplies, rules);
        _autoRepliesLoadingMore = false;
        _autoRepliesHasMore = rules.length >= _officialAutoRepliesPageSize;
      });
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _autoRepliesLoadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sanitizeExceptionForUi(error: e, isArabic: l.isArabic),
          ),
        ),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
      _autoRepliesLoadingMore = false;
      _autoRepliesHasMore = false;
    });
    try {
      OfficialAccountHandle? acc;
      try {
        final uri = _ownerAdminUri(
          pathSegments: const <String>['official_accounts'],
          queryParameters: <String, String>{
            'followed_only': 'false',
            'account_id': widget.accountId,
          },
        );
        if (uri == null) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = _invalidServerUrlMessage();
          });
          return;
        }
        final r = await _http
            .get(uri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          final list = <OfficialAccountHandle>[];
          if (decoded is Map && decoded['accounts'] is List) {
            for (final e in decoded['accounts'] as List) {
              if (e is Map) {
                list.add(
                  OfficialAccountHandle.fromJson(e.cast<String, dynamic>()),
                );
              }
            }
          } else if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) {
                list.add(
                  OfficialAccountHandle.fromJson(e.cast<String, dynamic>()),
                );
              }
            }
          }
          for (final a in list) {
            if (a.id == widget.accountId) {
              acc = a;
              break;
            }
          }
        }
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
      }
      Map<String, dynamic>? moments;
      Map<String, dynamic>? campaignDashboard;
      List<Map<String, dynamic>> greenPaketCampaigns =
          const <Map<String, dynamic>>[];
      Map<String, dynamic>? cardsDashboard;
      List<Map<String, dynamic>> cardOffers = const <Map<String, dynamic>>[];
      List<Map<String, dynamic>> autoReplies = const <Map<String, dynamic>>[];
      try {
        final uri = _ownerAdminUri(
          pathSegments: <String>[
            'admin',
            'official_accounts',
            widget.accountId,
            'moments_stats',
          ],
        );
        if (uri == null) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = _invalidServerUrlMessage();
          });
          return;
        }
        final r = await _http
            .get(uri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          if (decoded is Map) {
            moments = decoded.cast<String, dynamic>();
          }
        }
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
      }
      try {
        final dashboardUri = _ownerAdminUri(
          pathSegments: <String>[
            'admin',
            'official_accounts',
            widget.accountId,
            'campaigns',
            'dashboard',
          ],
        );
        final campaignsUri = _ownerAdminUri(
          pathSegments: <String>[
            'admin',
            'official_accounts',
            widget.accountId,
            'campaigns',
          ],
          queryParameters: const <String, String>{'limit': '12'},
        );
        if (dashboardUri == null || campaignsUri == null) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = _invalidServerUrlMessage();
          });
          return;
        }
        final dashboardResponse = await _http
            .get(dashboardUri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: dashboardResponse.statusCode,
          rawBody: dashboardResponse.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (dashboardResponse.statusCode >= 200 &&
            dashboardResponse.statusCode < 300) {
          final decoded = jsonDecode(dashboardResponse.body);
          if (decoded is Map) {
            campaignDashboard = decoded.cast<String, dynamic>();
          }
        }
        final campaignsResponse = await _http
            .get(campaignsUri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: campaignsResponse.statusCode,
          rawBody: campaignsResponse.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (campaignsResponse.statusCode >= 200 &&
            campaignsResponse.statusCode < 300) {
          greenPaketCampaigns =
              _decodeGreenPaketCampaigns(jsonDecode(campaignsResponse.body));
        }
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
      }
      try {
        final dashboardUri = _ownerAdminUri(
          pathSegments: <String>[
            'admin',
            'official_accounts',
            widget.accountId,
            'cards',
            'dashboard',
          ],
        );
        final offersUri = _ownerAdminUri(
          pathSegments: <String>[
            'admin',
            'official_accounts',
            widget.accountId,
            'cards',
            'offers',
          ],
          queryParameters: const <String, String>{'limit': '12'},
        );
        if (dashboardUri == null || offersUri == null) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = _invalidServerUrlMessage();
          });
          return;
        }
        final dashboardResponse = await _http
            .get(dashboardUri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: dashboardResponse.statusCode,
          rawBody: dashboardResponse.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (dashboardResponse.statusCode >= 200 &&
            dashboardResponse.statusCode < 300) {
          final decoded = jsonDecode(dashboardResponse.body);
          if (decoded is Map) {
            cardsDashboard = decoded.cast<String, dynamic>();
          }
        }
        final offersResponse = await _http
            .get(offersUri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: offersResponse.statusCode,
          rawBody: offersResponse.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (offersResponse.statusCode >= 200 &&
            offersResponse.statusCode < 300) {
          cardOffers = _decodeCardOffers(jsonDecode(offersResponse.body));
        }
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
      }
      // Load existing auto‑reply rules for this Official account via admin API.
      try {
        final uri = _autoRepliesUri();
        if (uri == null) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = _invalidServerUrlMessage();
          });
          return;
        }
        final r = await _http
            .get(uri, headers: await _hdr())
            .timeout(_officialOwnerRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (r.statusCode >= 200 && r.statusCode < 300) {
          autoReplies = _decodeAutoReplies(jsonDecode(r.body));
        }
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _account = acc;
        _momentsStats = moments;
        _campaignDashboard = campaignDashboard;
        _greenPaketCampaigns = greenPaketCampaigns;
        _cardsDashboard = cardsDashboard;
        _cardOffers = cardOffers;
        _autoReplies = autoReplies;
        _autoRepliesLoadingMore = false;
        _autoRepliesHasMore =
            autoReplies.length >= _officialAutoRepliesPageSize;
        _loading = false;
        if (acc == null) {
          _error = 'Official account not found';
        }
      });
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = sanitizeExceptionForUi(error: e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final acc = _account;
    final title =
        l.isArabic ? 'مركز الحساب الرسمي' : 'Official account console';

    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const ShamellSkeletonList(itemCount: 6),
      );
    }

    if (!_readAccessAllowed) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l.isArabic
                  ? 'هذا الحساب غير مخوّل للوصول إلى لوحة هذا الحساب الرسمي.'
                  : 'Your account is not allowed to access this official account console.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const ShamellSkeletonList(itemCount: 6),
      );
    }

    if (acc == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error.isNotEmpty
                  ? _error
                  : (l.isArabic
                      ? 'تعذّر العثور على هذا الحساب الرسمي.'
                      : 'Could not find this official account.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      );
    }

    final stats = _momentsStats ?? const <String, dynamic>{};
    final totalFeedItems = (stats['feed_items_total'] is num)
        ? (stats['feed_items_total'] as num).toInt()
        : (stats['total_shares'] is num)
            ? (stats['total_shares'] as num).toInt()
            : 0;
    final feedItems30 = (stats['feed_items_30d'] is num)
        ? (stats['feed_items_30d'] as num).toInt()
        : 0;
    final legacyFeedItems30 =
        (stats['shares_30d'] is num) ? (stats['shares_30d'] as num).toInt() : 0;
    final followers =
        (stats['followers'] is num) ? (stats['followers'] as num).toInt() : 0;
    final feedItemsPer1k = (stats['feed_items_per_1k_followers'] is num)
        ? (stats['feed_items_per_1k_followers'] as num).toDouble()
        : (stats['shares_per_1k_followers'] is num)
            ? (stats['shares_per_1k_followers'] as num).toDouble()
            : 0.0;
    final recentFeedItems = feedItems30 > 0 ? feedItems30 : legacyFeedItems30;
    final hasContentImpact =
        totalFeedItems > 0 || recentFeedItems > 0 || followers > 0;
    final campaignStats = _campaignDashboard ?? const <String, dynamic>{};
    int campaignStat(String key) {
      final value = campaignStats[key];
      return value is num ? value.toInt() : 0;
    }

    final campaignDashboardItems = <Map<String, dynamic>>[];
    final rawTopCampaigns = campaignStats['top_campaigns'];
    if (rawTopCampaigns is List) {
      for (final entry in rawTopCampaigns) {
        if (entry is Map) {
          campaignDashboardItems.add(entry.cast<String, dynamic>());
        }
      }
    }
    final greenPaketCampaigns = _greenPaketCampaigns.isNotEmpty
        ? _greenPaketCampaigns
        : campaignDashboardItems;
    final activeCampaigns = campaignStat('campaigns_active');
    final campaignPacketsIssued = campaignStat('packets_issued');
    final campaignPacketsClaimed = campaignStat('packets_claimed');
    final campaignClaimedAmountCents = campaignStat('claimed_amount_cents');
    final campaignMoments30 = campaignStat('moments_shares_30d');
    final cardsStats = _cardsDashboard ?? const <String, dynamic>{};
    int cardsStat(String key) {
      final value = cardsStats[key];
      return value is num ? value.toInt() : 0;
    }

    final cardsDashboardOffers = <Map<String, dynamic>>[];
    final rawTopOffers = cardsStats['top_offers'];
    if (rawTopOffers is List) {
      for (final entry in rawTopOffers) {
        if (entry is Map) {
          cardsDashboardOffers.add(entry.cast<String, dynamic>());
        }
      }
    }
    final cardOffers =
        _cardOffers.isNotEmpty ? _cardOffers : cardsDashboardOffers;
    final activeCardOffers = cardsStat('active_offers');
    final claimedCards = cardsStat('claimed_total');
    final redeemedCards = cardsStat('redeemed_total');
    final cardholders = cardsStat('cardholder_accounts');
    final commerceSignalCount = activeCardOffers + activeCampaigns;
    final autoLoadAvatarUrl = normalizeOfficialRemoteImageUrlForAutoload(
      acc.avatarUrl,
      baseUrl: widget.baseUrl,
    );
    Map<String, dynamic>? welcomeRule;
    final keywordRules = <Map<String, dynamic>>[];
    for (final rule in _autoReplies) {
      final kind = (rule['kind'] ?? 'welcome').toString().toLowerCase();
      if (kind == 'welcome' && welcomeRule == null) {
        welcomeRule = rule;
      } else if (kind == 'keyword') {
        keywordRules.add(rule);
      }
    }
    final welcomeEnabled = (welcomeRule?['enabled'] as bool?) ?? false;
    final welcomeText = (welcomeRule?['text'] ?? '').toString().trim();
    final hasActiveWelcome = welcomeEnabled && welcomeText.isNotEmpty;
    final activeKeywordRules =
        keywordRules.where((rule) => (rule['enabled'] as bool?) ?? true).length;
    final hasQrCode = (acc.qrPayload ?? '').isNotEmpty;
    final profileReadiness = _buildOfficialQrReadinessData(
      isArabic: l.isArabic,
      payload: acc.qrPayload,
      address: acc.address,
      openingHours: acc.openingHours,
      websiteUrl: acc.websiteUrl,
    );

    void openServiceInbox() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OfficialServiceInboxPage(
            baseUrl: widget.baseUrl,
            accountId: widget.accountId,
            privilegeSnapshotOverride: _privileges,
          ),
        ),
      );
    }

    void openOwnersAccess() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OfficialOwnersAccessPage(
            baseUrl: widget.baseUrl,
            accountId: widget.accountId,
            accountName: acc.name.isNotEmpty ? acc.name : widget.accountId,
            privilegeSnapshotOverride: _privileges,
          ),
        ),
      );
    }

    void openFeedComments() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OfficialMomentsCommentsPage(
            baseUrl: widget.baseUrl,
            accountId: widget.accountId,
            privilegeSnapshotOverride: _privileges,
          ),
        ),
      );
    }

    void openCardsCustomerView() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CardsOffersPage(
            baseUrl: widget.baseUrl,
            officialAccountId: widget.accountId,
            miniProgramId: 'cards',
            title: l.isArabic ? 'عروض ${acc.name}' : '${acc.name} offers',
          ),
        ),
      );
    }

    void runCommandLaneNextAction(String laneId) {
      switch (laneId) {
        case _officialOwnerWorkspaceService:
          if (!hasActiveWelcome) {
            if (_writeAccessAllowed) {
              _openAutoReplyEditor(welcomeRule);
            } else {
              _focusWorkspaceFromCommandDesk(_officialOwnerWorkspaceAutomation);
            }
            return;
          }
          if (activeKeywordRules == 0) {
            if (_writeAccessAllowed) {
              _openKeywordAutoReplyEditor(null);
            } else {
              _focusWorkspaceFromCommandDesk(_officialOwnerWorkspaceAutomation);
            }
            return;
          }
          openServiceInbox();
          return;
        case _officialOwnerWorkspaceAccess:
          openOwnersAccess();
          return;
        case _officialOwnerWorkspacePublishing:
          if (recentFeedItems == 0) {
            if (_writeAccessAllowed) {
              _openFeedComposer(acc);
            } else {
              _focusWorkspaceFromCommandDesk(
                _officialOwnerWorkspacePublishing,
              );
            }
            return;
          }
          openFeedComments();
          return;
        case _officialOwnerWorkspaceCommerce:
          openCardsCustomerView();
          return;
        case _officialOwnerWorkspaceAutomation:
          if (!hasActiveWelcome) {
            if (_writeAccessAllowed) {
              _openAutoReplyEditor(welcomeRule);
            } else {
              _focusWorkspaceFromCommandDesk(
                _officialOwnerWorkspaceAutomation,
              );
            }
            return;
          }
          if (activeKeywordRules == 0) {
            if (_writeAccessAllowed) {
              _openKeywordAutoReplyEditor(null);
            } else {
              _focusWorkspaceFromCommandDesk(
                _officialOwnerWorkspaceAutomation,
              );
            }
            return;
          }
          _focusWorkspaceFromCommandDesk(_officialOwnerWorkspaceAutomation);
          if (_autoRepliesHasMore && !_autoRepliesLoadingMore) {
            _loadMoreAutoReplies();
          }
          return;
        case _officialOwnerWorkspaceProfile:
          if (_writeAccessAllowed) {
            _openProfileEditor(acc);
          } else {
            _focusWorkspaceFromCommandDesk(_officialOwnerWorkspaceProfile);
          }
          return;
      }
    }

    final attentionItems = <_OfficialAttentionItemData>[
      if (!hasActiveWelcome)
        _OfficialAttentionItemData(
          id: 'welcome',
          icon: Icons.waving_hand_outlined,
          title: l.isArabic ? 'فعّل رسالة الترحيب' : 'Enable welcome message',
          detail: l.isArabic
              ? 'ابدأ برسالة ترحيب تلقائية حتى لا تدخل المحادثات الجديدة بلا توجيه.'
              : 'Start with an automatic welcome message so new chats do not open without guidance.',
          onTap: _writeAccessAllowed
              ? () => _openAutoReplyEditor(welcomeRule)
              : () => _focusWorkspaceFromCommandDesk(
                    _officialOwnerWorkspaceAutomation,
                  ),
        ),
      if (keywordRules.isEmpty)
        _OfficialAttentionItemData(
          id: 'keywords',
          icon: Icons.alternate_email_outlined,
          title: l.isArabic ? 'أضف قواعد كلمات مفتاحية' : 'Add keyword rules',
          detail: l.isArabic
              ? 'أنشئ ردوداً تلقائية للكلمات المتكررة مثل الأسعار أو المواعيد.'
              : 'Create auto-replies for repeated asks like pricing or opening hours.',
          onTap: _writeAccessAllowed
              ? () => _openKeywordAutoReplyEditor(null)
              : () => _focusWorkspaceFromCommandDesk(
                    _officialOwnerWorkspaceAutomation,
                  ),
        ),
      if (recentFeedItems == 0)
        _OfficialAttentionItemData(
          id: 'publishing',
          icon: Icons.campaign_outlined,
          title: l.isArabic ? 'النشر متوقف' : 'Publishing is idle',
          detail: l.isArabic
              ? 'لا توجد منشورات حديثة خلال آخر 30 يوماً.'
              : 'There have been no recent posts in the last 30 days.',
          onTap: _writeAccessAllowed
              ? () => _openFeedComposer(acc)
              : () => _focusWorkspaceFromCommandDesk(
                    _officialOwnerWorkspacePublishing,
                  ),
        ),
      if (profileReadiness.statusTone != _OfficialCommandLaneStatusTone.healthy)
        _OfficialAttentionItemData(
          id: 'profile',
          icon: Icons.qr_code_2_outlined,
          title: profileReadiness.statusTone ==
                  _OfficialCommandLaneStatusTone.alert
              ? (l.isArabic ? 'الملف غير جاهز' : 'Profile is not ready')
              : (l.isArabic ? 'الملف يحتاج تحديثاً' : 'Profile needs update'),
          detail: profileReadiness.detail,
          onTap: _writeAccessAllowed
              ? () => _openProfileEditor(acc)
              : () => _focusWorkspaceFromCommandDesk(
                    _officialOwnerWorkspaceProfile,
                  ),
        ),
      if (!_writeAccessAllowed)
        _OfficialAttentionItemData(
          id: 'access',
          icon: Icons.visibility_outlined,
          title: l.isArabic ? 'وضع القراءة فقط' : 'Read-only session',
          detail: l.isArabic
              ? 'يمكنك المراجعة فقط. اطلب صلاحيات كتابة لإدارة هذا الحساب.'
              : 'You can review only. Ask for write access to manage this account.',
          onTap: openOwnersAccess,
        ),
    ];

    final hasMerchantProfile =
        (acc.address ?? '').isNotEmpty || (acc.websiteUrl ?? '').isNotEmpty;
    final readyProfileSignals =
        profileReadiness.checks.where((check) => check.passed).length;
    final serviceSignals = <bool>[
      hasActiveWelcome,
      activeKeywordRules > 0,
      _writeAccessAllowed,
    ].where((signal) => signal).length;
    final accessSignals = <bool>[
      true,
      _writeAccessAllowed,
    ].where((signal) => signal).length;
    final automationSignals = activeKeywordRules + (hasActiveWelcome ? 1 : 0);
    final serviceStatusTone = !hasActiveWelcome
        ? _OfficialCommandLaneStatusTone.alert
        : activeKeywordRules == 0
            ? _OfficialCommandLaneStatusTone.watch
            : _OfficialCommandLaneStatusTone.healthy;
    final serviceStatusLabel = !hasActiveWelcome
        ? (l.isArabic ? 'تنبيه' : 'Alert')
        : activeKeywordRules == 0
            ? (l.isArabic ? 'مراقبة' : 'Watch')
            : (l.isArabic ? 'سليم' : 'Healthy');
    final accessStatusTone = _writeAccessAllowed
        ? _OfficialCommandLaneStatusTone.healthy
        : _OfficialCommandLaneStatusTone.watch;
    final accessStatusLabel = _writeAccessAllowed
        ? (l.isArabic ? 'سليم' : 'Healthy')
        : (l.isArabic ? 'مراقبة' : 'Watch');
    final publishingStatusTone = recentFeedItems == 0
        ? _OfficialCommandLaneStatusTone.alert
        : recentFeedItems < 3
            ? _OfficialCommandLaneStatusTone.watch
            : _OfficialCommandLaneStatusTone.healthy;
    final publishingStatusLabel = recentFeedItems == 0
        ? (l.isArabic ? 'تنبيه' : 'Alert')
        : recentFeedItems < 3
            ? (l.isArabic ? 'مراقبة' : 'Watch')
            : (l.isArabic ? 'سليم' : 'Healthy');
    final commerceStatusTone = commerceSignalCount == 0
        ? _OfficialCommandLaneStatusTone.watch
        : _OfficialCommandLaneStatusTone.healthy;
    final commerceStatusLabel = commerceSignalCount == 0
        ? (l.isArabic ? 'مراقبة' : 'Watch')
        : (l.isArabic ? 'سليم' : 'Healthy');
    final automationStatusTone = !hasActiveWelcome || activeKeywordRules == 0
        ? _OfficialCommandLaneStatusTone.alert
        : _autoRepliesHasMore
            ? _OfficialCommandLaneStatusTone.watch
            : _OfficialCommandLaneStatusTone.healthy;
    final automationStatusLabel = !hasActiveWelcome || activeKeywordRules == 0
        ? (l.isArabic ? 'تنبيه' : 'Alert')
        : _autoRepliesHasMore
            ? (l.isArabic ? 'مراقبة' : 'Watch')
            : (l.isArabic ? 'سليم' : 'Healthy');
    final profileStatusTone = profileReadiness.statusTone;
    final allStatusTone = <_OfficialCommandLaneStatusTone>[
      serviceStatusTone,
      accessStatusTone,
      publishingStatusTone,
      commerceStatusTone,
      automationStatusTone,
      profileStatusTone,
    ].contains(_OfficialCommandLaneStatusTone.alert)
        ? _OfficialCommandLaneStatusTone.alert
        : <_OfficialCommandLaneStatusTone>[
            serviceStatusTone,
            accessStatusTone,
            publishingStatusTone,
            commerceStatusTone,
            automationStatusTone,
            profileStatusTone,
          ].contains(_OfficialCommandLaneStatusTone.watch)
            ? _OfficialCommandLaneStatusTone.watch
            : _OfficialCommandLaneStatusTone.healthy;
    final workspaceFocuses = <_OfficialWorkspaceFocusData>[
      _OfficialWorkspaceFocusData(
        id: _officialOwnerWorkspaceAll,
        label: l.isArabic ? 'الكل' : 'All',
        signalCount: 6,
        statusTone: allStatusTone,
      ),
      _OfficialWorkspaceFocusData(
        id: _officialOwnerWorkspaceService,
        label: l.isArabic ? 'الخدمة' : 'Service',
        signalCount: serviceSignals,
        statusTone: serviceStatusTone,
      ),
      _OfficialWorkspaceFocusData(
        id: _officialOwnerWorkspaceAccess,
        label: l.isArabic ? 'الوصول' : 'Access',
        signalCount: accessSignals,
        statusTone: accessStatusTone,
      ),
      _OfficialWorkspaceFocusData(
        id: _officialOwnerWorkspacePublishing,
        label: l.isArabic ? 'النشر' : 'Publishing',
        signalCount: recentFeedItems,
        statusTone: publishingStatusTone,
      ),
      _OfficialWorkspaceFocusData(
        id: _officialOwnerWorkspaceCommerce,
        label: l.isArabic ? 'العروض' : 'Offers',
        signalCount: commerceSignalCount,
        statusTone: commerceStatusTone,
      ),
      _OfficialWorkspaceFocusData(
        id: _officialOwnerWorkspaceAutomation,
        label: l.isArabic ? 'الأتمتة' : 'Automation',
        signalCount: automationSignals,
        statusTone: automationStatusTone,
      ),
      _OfficialWorkspaceFocusData(
        id: _officialOwnerWorkspaceProfile,
        label: l.isArabic ? 'الملف' : 'Profile',
        signalCount: readyProfileSignals,
        statusTone: profileStatusTone,
      ),
    ];
    final availableWorkspaces = workspaceFocuses
        .where((focus) => focus.id != _officialOwnerWorkspaceAll)
        .map((focus) => focus.id)
        .toList(growable: false);
    final visibleWorkspaces = _visibleWorkspaces(
      availableWorkspaces: availableWorkspaces,
      selectedWorkspace: _selectedWorkspace,
    );
    final visibleWorkspaceFocuses = workspaceFocuses
        .where((focus) => visibleWorkspaces.contains(focus.id))
        .toList(growable: false);
    final totalWorkspaceCount = workspaceFocuses.length - 1;
    final visibleWorkspaceCount = visibleWorkspaces.length;
    final collapsedVisibleCount = visibleWorkspaces
        .where((workspace) => _collapsedWorkspaces.contains(workspace))
        .length;
    final visibleAlertCount = visibleWorkspaceFocuses
        .where(
            (focus) => focus.statusTone == _OfficialCommandLaneStatusTone.alert)
        .length;
    final visibleWatchCount = visibleWorkspaceFocuses
        .where(
            (focus) => focus.statusTone == _OfficialCommandLaneStatusTone.watch)
        .length;
    final visibleHealthyCount = visibleWorkspaceFocuses
        .where((focus) =>
            focus.statusTone == _OfficialCommandLaneStatusTone.healthy)
        .length;
    final workspaceSectionWidgets = <Widget>[];
    final commandLanes = <_OfficialCommandLaneData>[
      _OfficialCommandLaneData(
        id: _officialOwnerWorkspaceService,
        icon: Icons.support_agent_outlined,
        label: l.isArabic ? 'الخدمة' : 'Service',
        value: l.isArabic ? 'صندوق مباشر' : 'Inbox live',
        detail: hasActiveWelcome
            ? (l.isArabic ? 'الترحيب مفعّل' : 'Welcome active')
            : (l.isArabic ? 'الترحيب مفقود' : 'Welcome missing'),
        statusTone: serviceStatusTone,
        statusLabel: serviceStatusLabel,
        nextAction: !hasActiveWelcome
            ? (l.isArabic ? 'اضبط رسالة الترحيب' : 'Set welcome message')
            : activeKeywordRules == 0
                ? (l.isArabic ? 'أضف قاعدة كلمة مفتاحية' : 'Add keyword rule')
                : (l.isArabic ? 'راجع صندوق الخدمة' : 'Review inbox'),
      ),
      _OfficialCommandLaneData(
        id: _officialOwnerWorkspaceAccess,
        icon: Icons.manage_accounts_outlined,
        label: l.isArabic ? 'الوصول' : 'Access',
        value: _writeAccessAllowed
            ? (l.isArabic ? 'كتابة' : 'Write')
            : (l.isArabic ? 'قراءة فقط' : 'Read only'),
        detail: acc.verified
            ? (l.isArabic ? 'الحساب موثّق' : 'Verified account')
            : (l.isArabic ? 'الحساب قياسي' : 'Standard account'),
        statusTone: accessStatusTone,
        statusLabel: accessStatusLabel,
        nextAction: _writeAccessAllowed
            ? (l.isArabic ? 'راجع المالكين' : 'Manage owners')
            : (l.isArabic ? 'راجع الوصول' : 'Review access'),
      ),
      _OfficialCommandLaneData(
        id: _officialOwnerWorkspacePublishing,
        icon: Icons.campaign_outlined,
        label: l.isArabic ? 'النشر' : 'Publishing',
        value:
            l.isArabic ? '$recentFeedItems منشورات' : '$recentFeedItems posts',
        detail: followers > 0
            ? (l.isArabic ? '$followers متابع' : '$followers followers')
            : (l.isArabic ? 'لا متابعين بعد' : 'No followers yet'),
        statusTone: publishingStatusTone,
        statusLabel: publishingStatusLabel,
        nextAction: recentFeedItems == 0
            ? (l.isArabic ? 'أنشئ منشوراً' : 'Create post')
            : (l.isArabic ? 'راجع التعليقات' : 'Review comments'),
      ),
      _OfficialCommandLaneData(
        id: _officialOwnerWorkspaceCommerce,
        icon: Icons.local_offer_outlined,
        label: l.isArabic ? 'العروض' : 'Offers',
        value: l.isArabic
            ? '$activeCardOffers عروض · $activeCampaigns حملات'
            : '$activeCardOffers offers · $activeCampaigns campaigns',
        detail: campaignPacketsClaimed > 0
            ? (l.isArabic
                ? '$campaignPacketsClaimed مطالبة بالحزمة الخضراء'
                : '$campaignPacketsClaimed Green Paket claims')
            : cardholders > 0
                ? (l.isArabic ? '$cardholders حاملاً' : '$cardholders holders')
                : (l.isArabic
                    ? 'لا بطاقات أو حملات نشطة بعد'
                    : 'No saved cards or active campaigns yet'),
        statusTone: commerceStatusTone,
        statusLabel: commerceStatusLabel,
        nextAction: l.isArabic ? 'راجع العروض' : 'Review offers',
      ),
      _OfficialCommandLaneData(
        id: _officialOwnerWorkspaceAutomation,
        icon: Icons.rule_folder_outlined,
        label: l.isArabic ? 'الأتمتة' : 'Automation',
        value: l.isArabic
            ? '$activeKeywordRules قواعد'
            : '$activeKeywordRules rules',
        detail: hasActiveWelcome
            ? (l.isArabic ? 'ترحيب تلقائي مفعّل' : 'Welcome active')
            : (l.isArabic ? 'الترحيب يحتاج إعداداً' : 'Welcome needs setup'),
        statusTone: automationStatusTone,
        statusLabel: automationStatusLabel,
        nextAction: !hasActiveWelcome
            ? (l.isArabic ? 'عدّل رسالة الترحيب' : 'Edit welcome')
            : activeKeywordRules == 0
                ? (l.isArabic ? 'أضف قاعدة كلمة مفتاحية' : 'Add keyword rule')
                : _autoRepliesHasMore
                    ? (l.isArabic
                        ? 'حمّل المزيد من القواعد'
                        : 'Load more rules')
                    : (l.isArabic ? 'راجع القواعد' : 'Review rules'),
      ),
      _OfficialCommandLaneData(
        id: _officialOwnerWorkspaceProfile,
        icon: Icons.qr_code_2_outlined,
        label: l.isArabic ? 'الملف' : 'Profile',
        value: profileReadiness.summaryLabel,
        detail: profileReadiness.detail,
        statusTone: profileStatusTone,
        statusLabel: profileReadiness.statusLabel,
        nextAction: !hasQrCode
            ? (l.isArabic ? 'راجع إعداد QR' : 'Review QR setup')
            : profileReadiness.statusTone ==
                    _OfficialCommandLaneStatusTone.healthy
                ? (l.isArabic ? 'راجع الملف' : 'Review profile')
                : (l.isArabic ? 'أكمل الملف' : 'Complete profile'),
      ),
    ];

    void addWorkspaceDesk({
      required String workspaceId,
      required String title,
      required String summary,
      required List<_OfficialWorkspaceSignalData> signals,
      required Widget child,
    }) {
      if (!_isWorkspaceVisible(workspaceId)) {
        return;
      }
      if (workspaceSectionWidgets.isNotEmpty) {
        workspaceSectionWidgets.add(const SizedBox(height: 12));
      }
      workspaceSectionWidgets.add(
        KeyedSubtree(
          key: _workspaceSectionKey(workspaceId),
          child: _OfficialWorkspaceDesk(
            workspaceId: workspaceId,
            title: title,
            summary: summary,
            signals: signals,
            collapsed: _collapsedWorkspaces.contains(workspaceId),
            isArabic: l.isArabic,
            onToggleCollapsed: () => _toggleWorkspaceCollapsed(workspaceId),
            child: child,
          ),
        ),
      );
    }

    addWorkspaceDesk(
      workspaceId: _officialOwnerWorkspaceService,
      title: l.isArabic ? 'مكتب الخدمة' : 'Service desk',
      summary: l.isArabic
          ? 'انتقل مباشرة إلى محادثات خدمة العملاء والرسائل التشغيلية لهذا الحساب.'
          : 'Jump straight into customer-service chats and operator handoff for this account.',
      signals: <_OfficialWorkspaceSignalData>[
        _OfficialWorkspaceSignalData(
          id: 'welcome',
          label: l.isArabic ? 'الترحيب' : 'Welcome',
          value: hasActiveWelcome
              ? (l.isArabic ? 'مفعّل' : 'Active')
              : (l.isArabic ? 'مفقود' : 'Missing'),
        ),
        _OfficialWorkspaceSignalData(
          id: 'keywords',
          label: l.isArabic ? 'القواعد' : 'Rules',
          value: '$activeKeywordRules',
        ),
        _OfficialWorkspaceSignalData(
          id: 'session',
          label: l.isArabic ? 'الجلسة' : 'Session',
          value: _writeAccessAllowed
              ? (l.isArabic ? 'كتابة' : 'Write')
              : (l.isArabic ? 'قراءة' : 'Read'),
        ),
      ],
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.support_agent_outlined),
        title: Text(
          l.isArabic ? 'صندوق خدمة العملاء' : 'Customer service inbox',
        ),
        subtitle: Text(
          l.isArabic
              ? 'عرض جلسات خدمة العملاء المفتوحة والرد عبر SyrChat.'
              : 'View open customer-service sessions and reply via SyrChat chats.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: openServiceInbox,
      ),
    );

    addWorkspaceDesk(
      workspaceId: _officialOwnerWorkspaceAccess,
      title: l.isArabic ? 'مكتب الوصول' : 'Access desk',
      summary: l.isArabic
          ? 'راجع وضع الصلاحيات ثم افتح إدارة المالكين والوصول من نفس المكتب.'
          : 'Review the current permission state, then open owner and access management from one place.',
      signals: <_OfficialWorkspaceSignalData>[
        _OfficialWorkspaceSignalData(
          id: 'mode',
          label: l.isArabic ? 'الوضع' : 'Mode',
          value: _writeAccessAllowed
              ? (l.isArabic ? 'إدارة' : 'Manage')
              : (l.isArabic ? 'مراجعة' : 'Review'),
        ),
        _OfficialWorkspaceSignalData(
          id: 'account',
          label: l.isArabic ? 'الحساب' : 'Account',
          value: acc.verified
              ? (l.isArabic ? 'موثّق' : 'Verified')
              : (l.isArabic ? 'قياسي' : 'Standard'),
        ),
        _OfficialWorkspaceSignalData(
          id: 'scope',
          label: l.isArabic ? 'الوصول' : 'Access',
          value: _writeAccessAllowed
              ? (l.isArabic ? 'كتابة' : 'Write')
              : (l.isArabic ? 'قراءة فقط' : 'Read only'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.isArabic
                ? 'إدارة مالكي الحساب الرسمي وصلاحيات الوصول.'
                : 'Manage official account owners and access permissions.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: Text(
              l.isArabic ? 'إدارة الوصول' : 'Manage access',
            ),
            subtitle: Text(
              l.isArabic
                  ? 'عرض المالكين وإضافة أو إزالة الوصول.'
                  : 'View owners and add or remove access.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: openOwnersAccess,
          ),
        ],
      ),
    );

    addWorkspaceDesk(
      workspaceId: _officialOwnerWorkspacePublishing,
      title: l.isArabic ? 'مكتب النشر' : 'Publishing desk',
      summary: l.isArabic
          ? 'راقب أثر المحتوى، ثم انطلق إلى النشر أو مراجعة التعليقات من نفس المسار.'
          : 'Track content impact, then jump into publishing or moderation from the same lane.',
      signals: <_OfficialWorkspaceSignalData>[
        _OfficialWorkspaceSignalData(
          id: 'posts30',
          label: l.isArabic ? '٣٠ يوماً' : '30d',
          value: '$recentFeedItems',
        ),
        _OfficialWorkspaceSignalData(
          id: 'followers',
          label: l.isArabic ? 'المتابعون' : 'Followers',
          value: followers > 0
              ? '$followers'
              : (l.isArabic ? 'لا بيانات' : 'No data'),
        ),
        _OfficialWorkspaceSignalData(
          id: 'reach',
          label: l.isArabic ? 'لكل ١٠٠٠' : 'Per 1K',
          value: feedItemsPer1k > 0
              ? feedItemsPer1k.toStringAsFixed(1)
              : (l.isArabic ? 'لا بيانات' : 'No data'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.isArabic
                ? 'استخدم هذا المكتب لمتابعة أثر المحتوى وفتح النشر أو التعليقات بسرعة.'
                : 'Use this desk to review content impact and jump quickly into posting or comments.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 10),
          if (hasContentImpact)
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _OfficialInsightChip(
                  icon: Icons.share_outlined,
                  label: l.isArabic ? 'إجمالي المنشورات' : 'Total posts',
                  value: totalFeedItems > 0
                      ? totalFeedItems.toString()
                      : (l.isArabic ? 'لا بيانات' : 'No data'),
                ),
                _OfficialInsightChip(
                  icon: Icons.timeline_outlined,
                  label: l.isArabic ? 'منشورات (٣٠ يوماً)' : 'Posts (30d)',
                  value: recentFeedItems > 0
                      ? recentFeedItems.toString()
                      : (l.isArabic ? 'لا بيانات' : 'No data'),
                ),
                _OfficialInsightChip(
                  icon: Icons.people_outline,
                  label: l.isArabic ? 'المتابعون' : 'Followers',
                  value: followers > 0
                      ? followers.toString()
                      : (l.isArabic ? 'لا بيانات' : 'No data'),
                ),
                _OfficialInsightChip(
                  icon: Icons.insights_outlined,
                  label: l.isArabic
                      ? 'منشورات لكل ١٠٠٠ متابع'
                      : 'Posts / 1K followers',
                  value: feedItemsPer1k > 0
                      ? feedItemsPer1k.toStringAsFixed(1)
                      : (l.isArabic ? 'لا بيانات' : 'No data'),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .45,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                l.isArabic
                    ? 'لا توجد إشارات أثر واضحة بعد. ابدأ بمنشور جديد أو راجع التعليقات الإدارية.'
                    : 'No clear content signals yet. Start with a new post or review admin comments.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed:
                    _writeAccessAllowed ? () => _openFeedComposer(acc) : null,
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: Text(
                  l.isArabic ? 'منشور جديد في الخلاصة' : 'New feed item',
                ),
              ),
              TextButton.icon(
                onPressed: openFeedComments,
                icon: const Icon(Icons.comment_outlined, size: 18),
                label: Text(
                  l.isArabic
                      ? 'تعليقات المنشورات (إدارة)'
                      : 'Feed comments (admin)',
                ),
              ),
            ],
          ),
        ],
      ),
    );

    addWorkspaceDesk(
      workspaceId: _officialOwnerWorkspaceCommerce,
      title: l.isArabic ? 'مكتب العروض' : 'Offers desk',
      summary: l.isArabic
          ? 'راجع بطاقات العضوية والقسائم المرتبطة بهذا الحساب الرسمي.'
          : 'Review member cards and coupons tied to this Official account.',
      signals: <_OfficialWorkspaceSignalData>[
        _OfficialWorkspaceSignalData(
          id: 'active',
          label: l.isArabic ? 'نشطة' : 'Active',
          value: '$activeCardOffers',
        ),
        _OfficialWorkspaceSignalData(
          id: 'campaigns',
          label: l.isArabic ? 'حملات' : 'Campaigns',
          value: '$activeCampaigns',
        ),
        _OfficialWorkspaceSignalData(
          id: 'claimed',
          label: l.isArabic ? 'محفوظة' : 'Saved',
          value: '$claimedCards',
        ),
        _OfficialWorkspaceSignalData(
          id: 'redeemed',
          label: l.isArabic ? 'مستخدمة' : 'Redeemed',
          value: '$redeemedCards',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _OfficialInsightChip(
                icon: Icons.local_offer_outlined,
                label: l.isArabic ? 'عروض نشطة' : 'Active offers',
                value: '$activeCardOffers',
              ),
              _OfficialInsightChip(
                icon: Icons.wallet_membership_outlined,
                label: l.isArabic ? 'محفوظة' : 'Saved',
                value: '$claimedCards',
              ),
              _OfficialInsightChip(
                icon: Icons.task_alt_outlined,
                label: l.isArabic ? 'استخدام' : 'Redeemed',
                value: '$redeemedCards',
              ),
              _OfficialInsightChip(
                icon: Icons.people_outline,
                label: l.isArabic ? 'حاملو البطاقات' : 'Cardholders',
                value: '$cardholders',
              ),
              _OfficialInsightChip(
                icon: Icons.campaign_outlined,
                label: l.isArabic ? 'حملات نشطة' : 'Active campaigns',
                value: '$activeCampaigns',
              ),
              _OfficialInsightChip(
                icon: Icons.payments_outlined,
                label: l.isArabic ? 'مطالبات الحزمة' : 'Paket claims',
                value: '$campaignPacketsClaimed / $campaignPacketsIssued',
              ),
              _OfficialInsightChip(
                icon: Icons.account_balance_wallet_outlined,
                label: l.isArabic ? 'قيمة المطالبات' : 'Claimed value',
                value: fmtCents(campaignClaimedAmountCents),
              ),
              _OfficialInsightChip(
                icon: Icons.public_outlined,
                label: l.isArabic ? 'مشاركات الحملة' : 'Campaign shares',
                value: '$campaignMoments30',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (cardOffers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .45,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                l.isArabic
                    ? 'لا توجد عروض مرتبطة بهذا الحساب بعد.'
                    : 'No offers are linked to this account yet.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            Column(
              children: [
                for (final offer in cardOffers.take(4)) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.local_offer_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      (offer['title_en'] ?? offer['id'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        (offer['kind'] ?? '').toString().replaceAll('_', ' '),
                        if ((offer['discount_text'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          (offer['discount_text'] ?? '').toString(),
                        '${(offer['claimed_count'] as num?)?.toInt() ?? 0} ${l.isArabic ? 'محفوظة' : 'saved'}',
                      ].where((value) => value.trim().isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ((offer['active'] as bool?) ?? false)
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.pause_circle_outline),
                    onTap: _writeAccessAllowed
                        ? () => _openCardOfferEditor(offer)
                        : openCardsCustomerView,
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _writeAccessAllowed
                      ? () => _openCardOfferEditor(null)
                      : null,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: Text(l.isArabic ? 'عرض جديد' : 'New offer'),
                ),
                TextButton.icon(
                  onPressed: openCardsCustomerView,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(
                    l.isArabic ? 'عرض تجربة العميل' : 'View customer side',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l.isArabic ? 'حملات الحزمة الخضراء' : 'Green Paket campaigns',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (greenPaketCampaigns.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .45,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                l.isArabic
                    ? 'لا توجد حملات حزمة خضراء مرتبطة بهذا الحساب بعد.'
                    : 'No Green Paket campaigns are linked to this account yet.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            Column(
              children: [
                for (final campaign in greenPaketCampaigns.take(4)) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.campaign_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      (campaign['title'] ?? campaign['campaign_id'] ?? '')
                          .toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        '${(campaign['packets_issued'] as num?)?.toInt() ?? 0} ${l.isArabic ? 'مرسلة' : 'issued'}',
                        '${(campaign['packets_claimed'] as num?)?.toInt() ?? 0} ${l.isArabic ? 'مطالبة' : 'claimed'}',
                        if (campaign['default_amount_cents'] is num)
                          '${l.isArabic ? 'افتراضي' : 'default'} ${fmtCents((campaign['default_amount_cents'] as num).toInt())}',
                      ].where((value) => value.trim().isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ((campaign['active'] as bool?) ?? false)
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.pause_circle_outline),
                    onTap: _writeAccessAllowed
                        ? () => _openGreenPaketCampaignEditor(campaign)
                        : null,
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _writeAccessAllowed
                  ? () => _openGreenPaketCampaignEditor(null)
                  : null,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: Text(l.isArabic ? 'حملة جديدة' : 'New campaign'),
            ),
          ),
        ],
      ),
    );

    addWorkspaceDesk(
      workspaceId: _officialOwnerWorkspaceAutomation,
      title: l.isArabic ? 'مكتب الأتمتة' : 'Automation desk',
      summary: l.isArabic
          ? 'تابع رسالة الترحيب، قواعد الكلمات المفتاحية، وصفحة القواعد من نفس المكتب.'
          : 'Review the welcome message, keyword rules, and rule queue from one operator desk.',
      signals: <_OfficialWorkspaceSignalData>[
        _OfficialWorkspaceSignalData(
          id: 'welcome',
          label: l.isArabic ? 'الترحيب' : 'Welcome',
          value: hasActiveWelcome
              ? (l.isArabic ? 'مفعّل' : 'Active')
              : (l.isArabic ? 'مفقود' : 'Missing'),
        ),
        _OfficialWorkspaceSignalData(
          id: 'keywords',
          label: l.isArabic ? 'القواعد' : 'Rules',
          value: '$activeKeywordRules',
        ),
        _OfficialWorkspaceSignalData(
          id: 'queue',
          label: l.isArabic ? 'الصفحة' : 'Queue',
          value: _autoRepliesHasMore
              ? (l.isArabic ? 'مزيد' : 'More')
              : (l.isArabic ? 'محلي' : 'Local'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.isArabic
                ? 'يمكنك إعداد رسالة ترحيب يتم عرضها تلقائياً عند فتح الدردشة مع الحساب الرسمي (أسلوب شبيه بـ SyrChat).'
                : 'Configure a welcome message that is shown automatically when a chat with this Official account is opened (SyrChat‑style).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (ctx) {
              Map<String, dynamic>? welcome;
              for (final r in _autoReplies) {
                final kind = (r['kind'] ?? 'welcome').toString().toLowerCase();
                if (kind == 'welcome') {
                  welcome = r;
                  break;
                }
              }
              final enabled = (welcome?['enabled'] as bool?) ?? false;
              final text = (welcome?['text'] ?? '').toString().trim();
              final hasText = text.isNotEmpty && enabled;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasText
                        ? (l.isArabic
                            ? 'رسالة ترحيب مفعّلة:'
                            : 'Active welcome message:')
                        : (l.isArabic
                            ? 'لا توجد رسالة ترحيب مفعّلة بعد.'
                            : 'No active welcome message yet.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hasText) ...[
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _openAutoReplyEditor(welcome),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        l.isArabic
                            ? 'تعديل رسالة الترحيب'
                            : 'Edit welcome message',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (ctx) {
              final keywordRules = _autoReplies
                  .where(
                    (r) =>
                        (r['kind'] ?? 'keyword').toString().toLowerCase() ==
                        'keyword',
                  )
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.isArabic
                        ? 'قواعد الكلمات المفتاحية'
                        : 'Keyword auto‑replies',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (keywordRules.isEmpty)
                    Text(
                      l.isArabic
                          ? 'يمكنك إضافة ردود تلقائية بناءً على كلمات معينة يرسلها المستخدم.'
                          : 'You can add automatic replies that trigger when users send specific keywords.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in keywordRules.take(3))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '"${(r['keyword'] ?? '').toString()}"',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  ((r['enabled'] as bool?) ?? true)
                                      ? Icons.toggle_on
                                      : Icons.toggle_off,
                                  size: 18,
                                  color: ((r['enabled'] as bool?) ?? true)
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: .40,
                                        ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  onPressed: () =>
                                      _openKeywordAutoReplyEditor(r),
                                ),
                              ],
                            ),
                          ),
                        if (keywordRules.length > 3)
                          Text(
                            l.isArabic
                                ? '+ ${keywordRules.length - 3} قواعد أخرى'
                                : '+ ${keywordRules.length - 3} more rules',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: .70,
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _openKeywordAutoReplyEditor(null),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: Text(
                        l.isArabic
                            ? 'إضافة قاعدة كلمة مفتاحية'
                            : 'Add keyword rule',
                      ),
                    ),
                  ),
                  if (_autoRepliesLoadingMore) ...[
                    const SizedBox(height: 8),
                    const Center(child: CircularProgressIndicator()),
                  ] else if (_autoRepliesHasMore) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loadMoreAutoReplies,
                        child: Text(
                          l.isArabic ? 'تحميل المزيد' : 'Load more',
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );

    addWorkspaceDesk(
      workspaceId: _officialOwnerWorkspaceProfile,
      title: l.isArabic ? 'مكتب الملف' : 'Profile desk',
      summary: l.isArabic
          ? 'راجع رمز QR وبيانات المتجر من نفس المكتب قبل مشاركة الحساب.'
          : 'Review the QR code and merchant details from one desk before sharing the account outward.',
      signals: <_OfficialWorkspaceSignalData>[
        _OfficialWorkspaceSignalData(
          id: 'qr',
          label: l.isArabic ? 'الرمز' : 'QR',
          value: hasQrCode
              ? (l.isArabic ? 'جاهز' : 'Ready')
              : (l.isArabic ? 'مفقود' : 'Missing'),
        ),
        _OfficialWorkspaceSignalData(
          id: 'address',
          label: l.isArabic ? 'العنوان' : 'Address',
          value: (acc.address ?? '').isNotEmpty
              ? (l.isArabic ? 'جاهز' : 'Ready')
              : (l.isArabic ? 'مفقود' : 'Missing'),
        ),
        _OfficialWorkspaceSignalData(
          id: 'website',
          label: l.isArabic ? 'الموقع' : 'Website',
          value: (acc.websiteUrl ?? '').isNotEmpty
              ? (l.isArabic ? 'جاهز' : 'Ready')
              : (l.isArabic ? 'مفقود' : 'Missing'),
        ),
        _OfficialWorkspaceSignalData(
          id: 'hours',
          label: l.isArabic ? 'الساعات' : 'Hours',
          value: (acc.openingHours ?? '').isNotEmpty
              ? (l.isArabic ? 'جاهز' : 'Ready')
              : (l.isArabic ? 'مفقود' : 'Missing'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OfficialQrReadinessPanel(
            key: const Key('officialOwnerProfileReadinessPanel'),
            title: l.isArabic ? 'جاهزية الملصق' : 'Poster readiness',
            subtitle: l.isArabic
                ? 'نفس الفحوص المستخدمة قبل الطباعة أو مشاركة QR مع العملاء.'
                : 'The same checks used before printing or sharing the QR outward.',
            statusKey: const Key('officialOwnerProfileReadinessStatus'),
            readiness: profileReadiness,
            checkKeyPrefix: 'officialOwnerProfileReadinessCheck',
          ),
          const SizedBox(height: 12),
          if (hasQrCode) ...[
            Text(
              l.isArabic ? 'رمز QR للحساب' : 'Official QR code',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: QrImageView(
                data: acc.qrPayload!,
                size: 160,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.isArabic
                  ? 'يمكن للعملاء مسح هذا الرمز لمتابعة الحساب وفتح الدردشة أو الخدمات، مثل SyrChat Official Accounts.'
                  : 'Customers can scan this code to follow, chat and open services, similar to SyrChat Official Accounts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            _OfficialQrActionRow(
              keyPrefix: 'officialOwnerProfile',
              isArabic: l.isArabic,
              onCopy: () => _copyOfficialQrPayload(acc.qrPayload!),
              onShare: () => _showOfficialQrShareSheet(acc.qrPayload!),
              onPoster: () => _showOfficialQrPosterSheet(acc),
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .45,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                l.isArabic
                    ? 'رمز QR غير متاح حالياً. أضفه قبل مشاركة هذا الحساب مع العملاء.'
                    : 'No QR code is available yet. Add one before distributing this account to customers.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'بيانات المتجر' : 'Merchant profile',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (hasMerchantProfile) ...[
            if ((acc.address ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  acc.address!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if ((acc.websiteUrl ?? '').isNotEmpty)
              Text(
                acc.websiteUrl!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ] else
            Text(
              l.isArabic
                  ? 'لم تتم إضافة عنوان أو موقع بعد.'
                  : 'No address or website has been added yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
          if (_writeAccessAllowed) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('officialOwnerProfileEditButton'),
                onPressed: () => _openProfileEditor(acc),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  hasMerchantProfile || hasQrCode
                      ? (l.isArabic
                          ? 'تعديل بيانات الملف'
                          : 'Edit profile details')
                      : (l.isArabic
                          ? 'إكمال إعداد الملف'
                          : 'Complete profile setup'),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: ClipOval(
                    child: SizedBox.expand(
                      child: autoLoadAvatarUrl == null
                          ? Center(
                              child: Text(
                                acc.name.isNotEmpty
                                    ? acc.name.characters.first.toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            )
                          : ShamellPinnedRemoteImage(
                              imageUrl: autoLoadAvatarUrl,
                              fallback: Center(
                                child: Text(
                                  acc.name.isNotEmpty
                                      ? acc.name.characters.first.toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              acc.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (acc.verified)
                            Padding(
                              padding: EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.verified,
                                size: 18,
                                color: Tokens.colorPayments,
                              ),
                            ),
                        ],
                      ),
                      if ((acc.category ?? '').isNotEmpty ||
                          (acc.city ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [
                              if ((acc.category ?? '').isNotEmpty)
                                acc.category!,
                              if ((acc.city ?? '').isNotEmpty) acc.city!,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                        ),
                      if (acc.openingHours != null &&
                          acc.openingHours!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            acc.openingHours!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'مكتب التشغيل' : 'Command desk',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.isArabic
                      ? 'ابدأ بما يحتاج متابعة الآن: المحادثات، الوصول، النشر، والردود التلقائية.'
                      : 'Start with what needs action now: chats, access, publishing, and auto-replies.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _OfficialCommandMetricCard(
                      icon: Icons.waving_hand_outlined,
                      label: l.isArabic ? 'الترحيب' : 'Welcome',
                      value: hasActiveWelcome
                          ? (l.isArabic ? 'مفعّلة' : 'Active')
                          : (l.isArabic ? 'غير مفعّلة' : 'Missing'),
                    ),
                    _OfficialCommandMetricCard(
                      icon: Icons.alternate_email_outlined,
                      label: l.isArabic ? 'قواعد الكلمات' : 'Keyword rules',
                      value: '$activeKeywordRules',
                    ),
                    _OfficialCommandMetricCard(
                      icon: Icons.campaign_outlined,
                      label: l.isArabic ? 'منشورات 30 يوماً' : 'Posts (30d)',
                      value: '$recentFeedItems',
                    ),
                    _OfficialCommandMetricCard(
                      icon: Icons.qr_code_2_outlined,
                      label: l.isArabic ? 'رمز QR' : 'QR ready',
                      value: hasQrCode
                          ? (l.isArabic ? 'جاهز' : 'Yes')
                          : (l.isArabic ? 'مفقود' : 'No'),
                    ),
                    _OfficialCommandMetricCard(
                      icon: Icons.admin_panel_settings_outlined,
                      label: l.isArabic ? 'الوصول' : 'Access',
                      value: _writeAccessAllowed
                          ? (l.isArabic ? 'كتابة' : 'Write')
                          : (l.isArabic ? 'قراءة' : 'Read only'),
                    ),
                  ],
                ),
                if (attentionItems.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    l.isArabic ? 'يحتاج متابعة' : 'Needs attention',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      for (final item in attentionItems) ...[
                        _OfficialAttentionItem(item: item),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  l.isArabic ? 'مسارات الأولوية' : 'Priority lanes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final lane in commandLanes)
                      _OfficialCommandLaneCard(
                        key: Key('officialOwnerCommandLane_${lane.id}'),
                        lane: lane,
                        selected: _selectedWorkspace == lane.id,
                        onTap: () => _focusWorkspaceFromCommandDesk(lane.id),
                        onNextTap: () => runCommandLaneNextAction(lane.id),
                        nextLabel: l.isArabic ? 'التالي' : 'Next',
                        nextActionPrompt: l.isArabic ? 'افتح الآن' : 'Open now',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: openServiceInbox,
                      icon: const Icon(Icons.support_agent_outlined),
                      label: Text(
                        l.isArabic ? 'صندوق الخدمة' : 'Service inbox',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: openOwnersAccess,
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: Text(
                        l.isArabic ? 'إدارة الوصول' : 'Manage access',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: openFeedComments,
                      icon: const Icon(Icons.comment_outlined),
                      label: Text(
                        l.isArabic ? 'تعليقات الخلاصة' : 'Feed comments',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _writeAccessAllowed
                          ? () => _openAutoReplyEditor(welcomeRule)
                          : null,
                      icon: const Icon(Icons.message_outlined),
                      label: Text(
                        l.isArabic ? 'رسالة الترحيب' : 'Welcome message',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _writeAccessAllowed
                          ? () => _openFeedComposer(acc)
                          : null,
                      icon: const Icon(Icons.add_box_outlined),
                      label: Text(
                        l.isArabic ? 'منشور جديد' : 'New post',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'تركيز المكتب' : 'Workspace focus',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.isArabic
                      ? 'اعرض كل المكاتب أو اضغط على مسار واحد فقط لإبقاء الشاشة تشغيلية ومركّزة.'
                      : 'Show every desk or pin the screen to one operator lane at a time.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final focus in workspaceFocuses)
                      Builder(
                        builder: (context) {
                          final toneStyle = _officialCommandLaneStatusStyle(
                            Theme.of(context),
                            focus.statusTone,
                          );
                          return ChoiceChip(
                            key: Key('officialOwnerWorkspaceFocus_${focus.id}'),
                            showCheckmark: false,
                            avatar: Container(
                              key: Key(
                                'officialOwnerWorkspaceFocusTone_${focus.id}_${focus.statusTone.name}',
                              ),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: toneStyle.foreground.withValues(
                                  alpha: .92,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            backgroundColor:
                                toneStyle.background.withValues(alpha: .78),
                            selectedColor: toneStyle.background.withValues(
                              alpha: .96,
                            ),
                            side: BorderSide(
                              color:
                                  toneStyle.foreground.withValues(alpha: .26),
                            ),
                            labelStyle: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _selectedWorkspace == focus.id
                                  ? toneStyle.foreground
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: .82),
                            ),
                            label:
                                Text('${focus.label} (${focus.signalCount})'),
                            selected: _selectedWorkspace == focus.id,
                            onSelected: (_) => _setSelectedWorkspace(focus.id),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('officialOwnerCollapseVisible'),
                      onPressed: visibleWorkspaces.isEmpty
                          ? null
                          : () => _collapseVisibleWorkspaces(
                                availableWorkspaces: availableWorkspaces,
                                selectedWorkspace: _selectedWorkspace,
                              ),
                      icon: const Icon(Icons.unfold_less_rounded),
                      label: Text(
                        l.isArabic ? 'طي المعروض' : 'Collapse visible',
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('officialOwnerExpandVisible'),
                      onPressed: visibleWorkspaces.isEmpty
                          ? null
                          : () => _expandVisibleWorkspaces(
                                availableWorkspaces: availableWorkspaces,
                                selectedWorkspace: _selectedWorkspace,
                              ),
                      icon: const Icon(Icons.unfold_more_rounded),
                      label: Text(
                        l.isArabic ? 'توسيع المعروض' : 'Expand visible',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l.isArabic
                      ? 'عرض $visibleWorkspaceCount من أصل $totalWorkspaceCount مكاتب'
                      : 'Showing $visibleWorkspaceCount of $totalWorkspaceCount desks',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.isArabic
                      ? 'مطوي $collapsedVisibleCount من $visibleWorkspaceCount مكاتب'
                      : 'Collapsed $collapsedVisibleCount of $visibleWorkspaceCount desks',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _OfficialStatusCountChip(
                      key:
                          const Key('officialOwnerWorkspaceFocusSummary_alert'),
                      label: l.isArabic ? 'تنبيه' : 'Alert',
                      count: visibleAlertCount,
                      tone: _OfficialCommandLaneStatusTone.alert,
                    ),
                    _OfficialStatusCountChip(
                      key:
                          const Key('officialOwnerWorkspaceFocusSummary_watch'),
                      label: l.isArabic ? 'مراقبة' : 'Watch',
                      count: visibleWatchCount,
                      tone: _OfficialCommandLaneStatusTone.watch,
                    ),
                    _OfficialStatusCountChip(
                      key: const Key(
                          'officialOwnerWorkspaceFocusSummary_healthy'),
                      label: l.isArabic ? 'سليم' : 'Healthy',
                      count: visibleHealthyCount,
                      tone: _OfficialCommandLaneStatusTone.healthy,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (workspaceSectionWidgets.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...workspaceSectionWidgets,
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'مركز الحساب الرسمي' : 'Official account console',
        ),
      ),
      body: AppBG(
        child: body,
      ),
    );
  }

  Future<void> _openProfileEditor(OfficialAccountHandle acc) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final addressCtrl = TextEditingController(text: acc.address ?? '');
    final openingHoursCtrl =
        TextEditingController(text: acc.openingHours ?? '');
    final websiteCtrl = TextEditingController(text: acc.websiteUrl ?? '');
    final qrCtrl = TextEditingController(text: acc.qrPayload ?? '');
    bool submitting = false;
    String? error;
    String? mutationIdempotencyKey;
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                            Icons.storefront_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .90),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'بيانات الملف الرسمي'
                                  : 'Official profile details',
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
                      Text(
                        l.isArabic
                            ? 'حدّث عنوان المتجر وساعات العمل ورابط الموقع وحمولة QR من نفس لوحة المشغّل.'
                            : 'Update the shop address, opening hours, website URL, and QR payload from one operator panel.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: addressCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: l.isArabic ? 'العنوان' : 'Address',
                          helperText: l.isArabic
                              ? 'اتركه فارغاً إذا لم يكن متاحاً بعد.'
                              : 'Leave empty if this is not available yet.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: openingHoursCtrl,
                        decoration: InputDecoration(
                          labelText:
                              l.isArabic ? 'ساعات العمل' : 'Opening hours',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: websiteCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic ? 'رابط الموقع' : 'Website URL',
                          helperText: l.isArabic
                              ? 'استخدم https، أو http محلياً أثناء التطوير فقط.'
                              : 'Use https, or local-network http during development only.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: qrCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.isArabic ? 'حمولة QR' : 'QR payload',
                          helperText: l.isArabic
                              ? 'تُستخدم لتوليد رمز المتابعة/الدردشة لهذا الحساب.'
                              : 'Used to generate the follow/chat QR for this account.',
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: qrCtrl,
                        builder: (context, value, _) {
                          final qrPayload =
                              normalizeOfficialQrPayload(value.text.trim());
                          if (qrPayload == null) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.isArabic ? 'إجراءات QR' : 'QR actions',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _OfficialQrActionRow(
                                  keyPrefix: 'officialOwnerProfileEditor',
                                  isArabic: l.isArabic,
                                  onCopy: () =>
                                      _copyOfficialQrPayload(qrPayload),
                                  onShare: () =>
                                      _showOfficialQrShareSheet(qrPayload),
                                  onPoster: () => _showOfficialQrPosterSheet(
                                    acc,
                                    payloadOverride: qrPayload,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
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
                                    final address = addressCtrl.text.trim();
                                    final openingHours =
                                        openingHoursCtrl.text.trim();
                                    final rawWebsite = websiteCtrl.text.trim();
                                    final rawQrPayload = qrCtrl.text.trim();
                                    if (address.length > 512) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'العنوان طويل جداً.'
                                            : 'Address is too long.';
                                      });
                                      return;
                                    }
                                    if (openingHours.length > 128) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'ساعات العمل طويلة جداً.'
                                            : 'Opening hours are too long.';
                                      });
                                      return;
                                    }
                                    final websiteUrl = rawWebsite.isEmpty
                                        ? null
                                        : normalizeOfficialRemoteWebsiteUrl(
                                            rawWebsite,
                                          );
                                    if (rawWebsite.isNotEmpty &&
                                        websiteUrl == null) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'استخدم رابط موقع صالحًا عبر https، أو http محلي للتطوير فقط.'
                                            : 'Use a valid https website URL, or local-network http for development only.';
                                      });
                                      return;
                                    }
                                    final qrPayload = rawQrPayload.isEmpty
                                        ? null
                                        : normalizeOfficialQrPayload(
                                            rawQrPayload,
                                          );
                                    if (rawQrPayload.isNotEmpty &&
                                        qrPayload == null) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'استخدم حمولة QR صالحة بدون محارف تحكم وبحد أقصى 1024 حرفاً.'
                                            : 'Use a valid QR payload without control characters and within 1024 characters.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final headers =
                                          await _hdr(jsonBody: true);
                                      mutationIdempotencyKey ??=
                                          newPaymentsIdempotencyKey(
                                        'official-account-profile-patch',
                                      );
                                      headers['Idempotency-Key'] =
                                          mutationIdempotencyKey!;
                                      final uri = _ownerAdminUri(
                                        pathSegments: <String>[
                                          'admin',
                                          'official_accounts',
                                          widget.accountId,
                                        ],
                                      );
                                      if (uri == null) {
                                        setModalState(() {
                                          submitting = false;
                                          error = _invalidServerUrlMessage(
                                            isArabic: l.isArabic,
                                          );
                                        });
                                        return;
                                      }
                                      final r = await _http
                                          .patch(
                                            uri,
                                            headers: headers,
                                            body: jsonEncode({
                                              'address': address.isEmpty
                                                  ? null
                                                  : address,
                                              'opening_hours':
                                                  openingHours.isEmpty
                                                      ? null
                                                      : openingHours,
                                              'website_url': websiteUrl,
                                              'qr_payload': qrPayload,
                                            }),
                                          )
                                          .timeout(
                                              _officialOwnerRequestTimeout);
                                      if (r.statusCode < 200 ||
                                          r.statusCode >= 300) {
                                        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
                                          context,
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          loginPageBuilder: (_) =>
                                              const LoginPage(),
                                        )) {
                                          return;
                                        }
                                        final msg = sanitizeHttpError(
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          isArabic: l.isArabic,
                                        );
                                        if (!mounted) return;
                                        setModalState(() {
                                          submitting = false;
                                          error = msg;
                                        });
                                        return;
                                      }
                                      if (!mounted) return;
                                      Navigator.of(ctx).pop();
                                      await _load();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l.isArabic
                                                ? 'تم تحديث بيانات الملف.'
                                                : 'Profile details updated.',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
                                        context,
                                        error: e,
                                        loginPageBuilder: (_) =>
                                            const LoginPage(),
                                      )) {
                                        return;
                                      }
                                      if (!mounted) return;
                                      setModalState(() {
                                        submitting = false;
                                        error = sanitizeExceptionForUi(
                                          error: e,
                                          isArabic: l.isArabic,
                                        );
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
                              l.isArabic ? 'حفظ' : 'Save',
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
    } finally {
      addressCtrl.dispose();
      openingHoursCtrl.dispose();
      websiteCtrl.dispose();
      qrCtrl.dispose();
    }
  }

  Future<void> _openFeedComposer(OfficialAccountHandle acc) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final idCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final snippetCtrl = TextEditingController();
    final thumbCtrl = TextEditingController();
    String? error;
    bool submitting = false;
    String? mutationIdempotencyKey;
    try {
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
                            Icons.article_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .90),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'منشور جديد في الحساب الرسمي'
                                  : 'Create new official feed item',
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
                        controller: idCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'معرّف فريد (مثل campaign_2025)'
                              : 'Unique ID (e.g. campaign_2025)',
                          helperText: l.isArabic
                              ? 'يُستخدم كمفتاح داخلي ويمكن تضمينه في روابط أو الحملات.'
                              : 'Used as internal key; can be referenced from campaigns or links.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText:
                              l.isArabic ? 'العنوان' : 'Title (headline)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: snippetCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'نص مختصر / وصف'
                              : 'Short text / snippet',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: thumbCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'رابط صورة (اختياري)'
                              : 'Thumbnail URL (optional)',
                          helperText: l.isArabic
                              ? 'استخدم رابط صورة موجودة لعرض بطاقة غنية في الخلاصة.'
                              : 'Use an existing image URL for a rich feed card.',
                        ),
                      ),
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
                                    final slug = idCtrl.text.trim();
                                    final title = titleCtrl.text.trim();
                                    final snippet = snippetCtrl.text.trim();
                                    if (slug.isEmpty || snippet.isEmpty) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'المعرّف والنص مطلوبان.'
                                            : 'ID and snippet are required.';
                                      });
                                      return;
                                    }
                                    final rawThumbUrl = thumbCtrl.text.trim();
                                    final thumbUrl =
                                        normalizeOfficialRemoteImageUrl(
                                      rawThumbUrl,
                                    );
                                    if (rawThumbUrl.isNotEmpty &&
                                        thumbUrl == null) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'استخدم رابط صورة صالحًا عبر https، أو http محلي للتطوير فقط.'
                                            : 'Use a valid https image URL, or localhost http for development only.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final uri = _ownerAdminUri(
                                        pathSegments: const <String>[
                                          'admin',
                                          'official_feeds',
                                        ],
                                      );
                                      if (uri == null) {
                                        setModalState(() {
                                          submitting = false;
                                          error = _invalidServerUrlMessage(
                                            isArabic: l.isArabic,
                                          );
                                        });
                                        return;
                                      }
                                      final payload = <String, Object?>{
                                        'account_id': widget.accountId,
                                        'id': slug,
                                        'type': 'promo',
                                        'title':
                                            title.isNotEmpty ? title : null,
                                        'snippet':
                                            snippet.isNotEmpty ? snippet : null,
                                        'thumb_url': thumbUrl,
                                      };
                                      final headers =
                                          await _hdr(jsonBody: true);
                                      mutationIdempotencyKey ??=
                                          newPaymentsIdempotencyKey(
                                        'official-feed-create',
                                      );
                                      headers['Idempotency-Key'] =
                                          mutationIdempotencyKey!;
                                      final r = await _http
                                          .post(
                                            uri,
                                            headers: headers,
                                            body: jsonEncode(payload),
                                          )
                                          .timeout(
                                              _officialOwnerRequestTimeout);
                                      if (r.statusCode < 200 ||
                                          r.statusCode >= 300) {
                                        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
                                          context,
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          loginPageBuilder: (_) =>
                                              const LoginPage(),
                                        )) {
                                          return;
                                        }
                                        final msg = sanitizeHttpError(
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          isArabic: l.isArabic,
                                        );
                                        if (!mounted) return;
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
                                                ? 'تم نشر منشور الخلاصة.'
                                                : 'Feed item created.',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
                                        context,
                                        error: e,
                                        loginPageBuilder: (_) =>
                                            const LoginPage(),
                                      )) {
                                        return;
                                      }
                                      if (!mounted) return;
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
    } finally {
      idCtrl.dispose();
      titleCtrl.dispose();
      snippetCtrl.dispose();
      thumbCtrl.dispose();
    }
  }

  Future<void> _openGreenPaketCampaignEditor(
    Map<String, dynamic>? existing,
  ) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isEditing = existing != null;
    final campaignId =
        (existing?['campaign_id'] ?? existing?['id'] ?? '').toString().trim();
    final idCtrl = TextEditingController(text: campaignId);
    final titleCtrl =
        TextEditingController(text: (existing?['title'] ?? '').toString());
    final descriptionCtrl = TextEditingController(
      text: (existing?['description'] ?? '').toString(),
    );
    final amountCtrl = TextEditingController(
      text: existing?['default_amount_cents'] == null
          ? ''
          : existing!['default_amount_cents'].toString(),
    );
    final countCtrl = TextEditingController(
      text: existing?['default_count'] == null
          ? ''
          : existing!['default_count'].toString(),
    );
    final startsAtCtrl = TextEditingController(
      text: (existing?['starts_at'] ?? '').toString(),
    );
    final endsAtCtrl = TextEditingController(
      text: (existing?['ends_at'] ?? '').toString(),
    );
    final allControllers = <TextEditingController>[
      idCtrl,
      titleCtrl,
      descriptionCtrl,
      amountCtrl,
      countCtrl,
      startsAtCtrl,
      endsAtCtrl,
    ];
    var active = (existing?['active'] as bool?) ?? true;
    bool submitting = false;
    bool deleting = false;
    String? error;
    String? mutationIdempotencyKey;

    Future<void> submit(
      BuildContext modalContext,
      StateSetter setModalState,
    ) async {
      final id = idCtrl.text.trim().toLowerCase();
      final title = titleCtrl.text.trim();
      final description = descriptionCtrl.text.trim();
      final amountRaw = amountCtrl.text.trim();
      final countRaw = countCtrl.text.trim();
      final startsAt = startsAtCtrl.text.trim();
      final endsAt = endsAtCtrl.text.trim();
      final amount = amountRaw.isEmpty ? null : int.tryParse(amountRaw);
      final count = countRaw.isEmpty ? null : int.tryParse(countRaw);
      if (!isEditing && id.isEmpty) {
        setModalState(() {
          error =
              l.isArabic ? 'معرّف الحملة مطلوب.' : 'Campaign ID is required.';
        });
        return;
      }
      if (title.isEmpty) {
        setModalState(() {
          error = l.isArabic ? 'العنوان مطلوب.' : 'Title is required.';
        });
        return;
      }
      if (amountRaw.isNotEmpty && (amount == null || amount < 0)) {
        setModalState(() {
          error = l.isArabic
              ? 'المبلغ الافتراضي يجب أن يكون رقماً موجباً.'
              : 'Default amount must be a positive number.';
        });
        return;
      }
      if (countRaw.isNotEmpty && (count == null || count < 1 || count > 100)) {
        setModalState(() {
          error = l.isArabic
              ? 'العدد الافتراضي يجب أن يكون بين 1 و100.'
              : 'Default count must be between 1 and 100.';
        });
        return;
      }
      setModalState(() {
        submitting = true;
        error = null;
      });
      try {
        final path = isEditing
            ? <String>[
                'admin',
                'official_accounts',
                widget.accountId,
                'campaigns',
                campaignId,
              ]
            : <String>[
                'admin',
                'official_accounts',
                widget.accountId,
                'campaigns',
              ];
        final uri = _ownerAdminUri(pathSegments: path);
        if (uri == null) {
          setModalState(() {
            submitting = false;
            error = _invalidServerUrlMessage(isArabic: l.isArabic);
          });
          return;
        }
        final payload = <String, Object?>{
          if (!isEditing) 'campaign_id': id,
          'title': title,
          'description': description.isEmpty ? null : description,
          'default_amount_cents': amount,
          'default_count': count,
          'active': active,
          if (startsAt.isNotEmpty) 'starts_at': startsAt,
          if (endsAt.isNotEmpty) 'ends_at': endsAt,
        };
        final headers = await _hdr(jsonBody: true);
        mutationIdempotencyKey ??= newPaymentsIdempotencyKey(
          isEditing
              ? 'official-green-paket-campaign-patch'
              : 'official-green-paket-campaign-create',
        );
        headers['Idempotency-Key'] = mutationIdempotencyKey!;
        final response = isEditing
            ? await _http
                .patch(uri, headers: headers, body: jsonEncode(payload))
                .timeout(_officialOwnerRequestTimeout)
            : await _http
                .post(uri, headers: headers, body: jsonEncode(payload))
                .timeout(_officialOwnerRequestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
            context,
            statusCode: response.statusCode,
            rawBody: response.body,
            loginPageBuilder: (_) => const LoginPage(),
          )) {
            return;
          }
          final msg = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
          if (!mounted) return;
          setModalState(() {
            submitting = false;
            error = msg;
          });
          return;
        }
        if (!mounted) return;
        Navigator.of(modalContext).pop();
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? (l.isArabic ? 'تم تحديث الحملة.' : 'Campaign updated.')
                  : (l.isArabic ? 'تم إنشاء الحملة.' : 'Campaign created.'),
            ),
          ),
        );
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (!mounted) return;
        setModalState(() {
          submitting = false;
          error = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
        });
      }
    }

    Future<void> deactivate(
      BuildContext modalContext,
      StateSetter setModalState,
    ) async {
      if (!isEditing || campaignId.isEmpty) {
        return;
      }
      setModalState(() {
        deleting = true;
        error = null;
      });
      try {
        final uri = _ownerAdminUri(
          pathSegments: <String>[
            'admin',
            'official_accounts',
            widget.accountId,
            'campaigns',
            campaignId,
          ],
        );
        if (uri == null) {
          setModalState(() {
            deleting = false;
            error = _invalidServerUrlMessage(isArabic: l.isArabic);
          });
          return;
        }
        final headers = await _hdr(jsonBody: true);
        headers['Idempotency-Key'] = newPaymentsIdempotencyKey(
          'official-green-paket-campaign-delete',
        );
        final response = await _http
            .delete(uri, headers: headers)
            .timeout(_officialOwnerRequestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
            context,
            statusCode: response.statusCode,
            rawBody: response.body,
            loginPageBuilder: (_) => const LoginPage(),
          )) {
            return;
          }
          final msg = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
          if (!mounted) return;
          setModalState(() {
            deleting = false;
            error = msg;
          });
          return;
        }
        if (!mounted) return;
        Navigator.of(modalContext).pop();
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تم إيقاف الحملة.' : 'Campaign deactivated.',
            ),
          ),
        );
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (!mounted) return;
        setModalState(() {
          deleting = false;
          error = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
        });
      }
    }

    try {
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
                final busy = submitting || deleting;
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx2).size.height * .88,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.campaign_outlined,
                              size: 20,
                              color: theme.colorScheme.primary
                                  .withValues(alpha: .90),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isEditing
                                    ? (l.isArabic
                                        ? 'تعديل حملة الحزمة الخضراء'
                                        : 'Edit Green Paket campaign')
                                    : (l.isArabic
                                        ? 'حملة حزمة خضراء جديدة'
                                        : 'Create Green Paket campaign'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed:
                                  busy ? null : () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: idCtrl,
                          enabled: !isEditing && !busy,
                          decoration: InputDecoration(
                            labelText:
                                l.isArabic ? 'معرّف الحملة' : 'Campaign ID',
                            helperText: isEditing
                                ? (l.isArabic
                                    ? 'لا يمكن تغيير المعرّف بعد الإنشاء.'
                                    : 'The ID cannot be changed after creation.')
                                : (l.isArabic
                                    ? 'مثال: spring_green_paket'
                                    : 'Example: spring_green_paket'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: titleCtrl,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText: l.isArabic ? 'العنوان' : 'Title',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: descriptionCtrl,
                          enabled: !busy,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: l.isArabic ? 'الوصف' : 'Description',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: amountCtrl,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l.isArabic
                                ? 'المبلغ الافتراضي بالسنت'
                                : 'Default amount (cents)',
                            helperText: l.isArabic
                                ? 'اتركه فارغاً لاستخدام الإعداد الافتراضي.'
                                : 'Leave empty to use the server default.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: countCtrl,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l.isArabic
                                ? 'العدد الافتراضي'
                                : 'Default packet count',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: startsAtCtrl,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText:
                                l.isArabic ? 'يبدأ في' : 'Starts at (optional)',
                            helperText: l.isArabic
                                ? 'استخدم صيغة ISO مثل 2026-05-05T09:00:00Z.'
                                : 'Use ISO format, e.g. 2026-05-05T09:00:00Z.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: endsAtCtrl,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText:
                                l.isArabic ? 'ينتهي في' : 'Ends at (optional)',
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: active,
                          onChanged: busy
                              ? null
                              : (value) => setModalState(() => active = value),
                          title: Text(l.isArabic ? 'نشطة' : 'Active'),
                        ),
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
                            if (isEditing) ...[
                              TextButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => deactivate(ctx, setModalState),
                                icon: deleting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.pause_circle_outline),
                                label: Text(
                                  l.isArabic ? 'إيقاف' : 'Deactivate',
                                ),
                              ),
                              const Spacer(),
                            ],
                            TextButton(
                              onPressed:
                                  busy ? null : () => Navigator.of(ctx).pop(),
                              child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => submit(ctx, setModalState),
                              icon: submitting
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
                                  : const Icon(Icons.check),
                              label: Text(l.isArabic ? 'حفظ' : 'Save'),
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
        );
      },
      );
    } finally {
      for (final ctrl in allControllers) {
        ctrl.dispose();
      }
    }
  }

  Future<void> _openCardOfferEditor(Map<String, dynamic>? existing) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isEditing = existing != null;
    final offerId =
        (existing?['id'] ?? existing?['offer_id'] ?? '').toString().trim();
    final idCtrl = TextEditingController(text: offerId);
    final titleCtrl =
        TextEditingController(text: (existing?['title_en'] ?? '').toString());
    final titleArCtrl =
        TextEditingController(text: (existing?['title_ar'] ?? '').toString());
    final descriptionCtrl = TextEditingController(
      text: (existing?['description_en'] ?? '').toString(),
    );
    final discountCtrl = TextEditingController(
      text: (existing?['discount_text'] ?? '').toString(),
    );
    final inventoryCtrl = TextEditingController(
      text: existing?['inventory_total'] == null
          ? ''
          : existing!['inventory_total'].toString(),
    );
    final validUntilCtrl = TextEditingController(
      text: (existing?['valid_until'] ?? '').toString(),
    );
    final allControllers = <TextEditingController>[
      idCtrl,
      titleCtrl,
      titleArCtrl,
      descriptionCtrl,
      discountCtrl,
      inventoryCtrl,
      validUntilCtrl,
    ];
    const kinds = <String>[
      'coupon',
      'member_card',
      'event_pass',
      'gift',
      'service_pass',
    ];
    var kind = (existing?['kind'] ?? 'coupon').toString().trim();
    if (!kinds.contains(kind)) {
      kind = 'coupon';
    }
    var active = (existing?['active'] as bool?) ?? true;
    var featured = (existing?['featured'] as bool?) ?? false;
    bool submitting = false;
    bool deleting = false;
    String? error;
    String? mutationIdempotencyKey;

    Future<void> submit(
      BuildContext modalContext,
      StateSetter setModalState,
    ) async {
      final id = idCtrl.text.trim().toLowerCase();
      final title = titleCtrl.text.trim();
      final titleAr = titleArCtrl.text.trim();
      final description = descriptionCtrl.text.trim();
      final discount = discountCtrl.text.trim();
      final inventoryRaw = inventoryCtrl.text.trim();
      final validUntil = validUntilCtrl.text.trim();
      final inventory =
          inventoryRaw.isEmpty ? null : int.tryParse(inventoryRaw);
      if (!isEditing && id.isEmpty) {
        setModalState(() {
          error = l.isArabic ? 'المعرّف مطلوب.' : 'Offer ID is required.';
        });
        return;
      }
      if (title.isEmpty) {
        setModalState(() {
          error = l.isArabic ? 'العنوان مطلوب.' : 'Title is required.';
        });
        return;
      }
      if (inventoryRaw.isNotEmpty && (inventory == null || inventory < 0)) {
        setModalState(() {
          error = l.isArabic
              ? 'المخزون يجب أن يكون رقماً موجباً.'
              : 'Inventory must be a positive number.';
        });
        return;
      }
      setModalState(() {
        submitting = true;
        error = null;
      });
      try {
        final path = isEditing
            ? <String>[
                'admin',
                'official_accounts',
                widget.accountId,
                'cards',
                'offers',
                offerId,
              ]
            : <String>[
                'admin',
                'official_accounts',
                widget.accountId,
                'cards',
                'offers',
              ];
        final uri = _ownerAdminUri(pathSegments: path);
        if (uri == null) {
          setModalState(() {
            submitting = false;
            error = _invalidServerUrlMessage(isArabic: l.isArabic);
          });
          return;
        }
        final payload = <String, Object?>{
          if (!isEditing) 'offer_id': id,
          'title_en': title,
          'title_ar': titleAr.isEmpty ? null : titleAr,
          'description_en': description.isEmpty ? null : description,
          'kind': kind,
          'discount_text': discount.isEmpty ? null : discount,
          'active': active,
          'featured': featured,
          'inventory_total': inventory,
          if (validUntil.isNotEmpty) 'valid_until': validUntil,
          'metadata': <String, Object?>{
            'surface': 'official_owner_console',
            'official_account_id': widget.accountId,
          },
        };
        final headers = await _hdr(jsonBody: true);
        mutationIdempotencyKey ??= newPaymentsIdempotencyKey(
          isEditing
              ? 'official-card-offer-patch'
              : 'official-card-offer-create',
        );
        headers['Idempotency-Key'] = mutationIdempotencyKey!;
        final response = isEditing
            ? await _http
                .patch(uri, headers: headers, body: jsonEncode(payload))
                .timeout(_officialOwnerRequestTimeout)
            : await _http
                .post(uri, headers: headers, body: jsonEncode(payload))
                .timeout(_officialOwnerRequestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
            context,
            statusCode: response.statusCode,
            rawBody: response.body,
            loginPageBuilder: (_) => const LoginPage(),
          )) {
            return;
          }
          final msg = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
          if (!mounted) return;
          setModalState(() {
            submitting = false;
            error = msg;
          });
          return;
        }
        if (!mounted) return;
        Navigator.of(modalContext).pop();
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? (l.isArabic ? 'تم تحديث العرض.' : 'Offer updated.')
                  : (l.isArabic ? 'تم إنشاء العرض.' : 'Offer created.'),
            ),
          ),
        );
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (!mounted) return;
        setModalState(() {
          submitting = false;
          error = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
        });
      }
    }

    Future<void> deactivate(
      BuildContext modalContext,
      StateSetter setModalState,
    ) async {
      if (!isEditing || offerId.isEmpty) {
        return;
      }
      setModalState(() {
        deleting = true;
        error = null;
      });
      try {
        final uri = _ownerAdminUri(
          pathSegments: <String>[
            'admin',
            'official_accounts',
            widget.accountId,
            'cards',
            'offers',
            offerId,
          ],
        );
        if (uri == null) {
          setModalState(() {
            deleting = false;
            error = _invalidServerUrlMessage(isArabic: l.isArabic);
          });
          return;
        }
        final headers = await _hdr(jsonBody: true);
        headers['Idempotency-Key'] =
            newPaymentsIdempotencyKey('official-card-offer-delete');
        final response = await _http
            .delete(uri, headers: headers)
            .timeout(_officialOwnerRequestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
            context,
            statusCode: response.statusCode,
            rawBody: response.body,
            loginPageBuilder: (_) => const LoginPage(),
          )) {
            return;
          }
          final msg = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
          if (!mounted) return;
          setModalState(() {
            deleting = false;
            error = msg;
          });
          return;
        }
        if (!mounted) return;
        Navigator.of(modalContext).pop();
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تم إيقاف العرض.' : 'Offer deactivated.',
            ),
          ),
        );
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (!mounted) return;
        setModalState(() {
          deleting = false;
          error = sanitizeExceptionForUi(error: e, isArabic: l.isArabic);
        });
      }
    }

    try {
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
                final busy = submitting || deleting;
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx2).size.height * .88,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.local_offer_outlined,
                              size: 20,
                              color: theme.colorScheme.primary
                                  .withValues(alpha: .90),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isEditing
                                    ? (l.isArabic
                                        ? 'تعديل العرض'
                                        : 'Edit offer')
                                    : (l.isArabic
                                        ? 'عرض جديد'
                                        : 'Create offer'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed:
                                  busy ? null : () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: idCtrl,
                          enabled: !isEditing && !busy,
                          decoration: InputDecoration(
                            labelText: l.isArabic ? 'معرّف العرض' : 'Offer ID',
                            helperText: isEditing
                                ? (l.isArabic
                                    ? 'لا يمكن تغيير المعرّف بعد الإنشاء.'
                                    : 'The ID cannot be changed after creation.')
                                : (l.isArabic
                                    ? 'مثال: spring_coupon'
                                    : 'Example: spring_coupon'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: titleCtrl,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText:
                                l.isArabic ? 'العنوان' : 'Title (English)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: titleArCtrl,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText:
                                l.isArabic ? 'العنوان العربي' : 'Arabic title',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: descriptionCtrl,
                          enabled: !busy,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: l.isArabic ? 'الوصف' : 'Description',
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: kind,
                          decoration: InputDecoration(
                            labelText: l.isArabic ? 'النوع' : 'Kind',
                          ),
                          items: [
                            for (final value in kinds)
                              DropdownMenuItem<String>(
                                value: value,
                                child: Text(value.replaceAll('_', ' ')),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setModalState(() => kind = value);
                                },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: discountCtrl,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText: l.isArabic
                                ? 'نص الخصم / الميزة'
                                : 'Discount / benefit text',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: inventoryCtrl,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l.isArabic ? 'المخزون' : 'Inventory',
                            helperText: l.isArabic
                                ? 'اتركه فارغاً للعروض غير المحدودة.'
                                : 'Leave empty for unlimited offers.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: validUntilCtrl,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText: l.isArabic
                                ? 'صالح حتى'
                                : 'Valid until (optional)',
                            helperText: l.isArabic
                                ? 'استخدم صيغة ISO مثل 2026-12-31T23:59:00Z.'
                                : 'Use ISO format, e.g. 2026-12-31T23:59:00Z.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: active,
                          onChanged: busy
                              ? null
                              : (value) => setModalState(() => active = value),
                          title: Text(l.isArabic ? 'نشط' : 'Active'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: featured,
                          onChanged: busy
                              ? null
                              : (value) =>
                                  setModalState(() => featured = value),
                          title: Text(l.isArabic ? 'مميّز' : 'Featured'),
                        ),
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
                            if (isEditing) ...[
                              TextButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => deactivate(ctx, setModalState),
                                icon: deleting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.pause_circle_outline),
                                label: Text(
                                  l.isArabic ? 'إيقاف' : 'Deactivate',
                                ),
                              ),
                              const Spacer(),
                            ],
                            TextButton(
                              onPressed:
                                  busy ? null : () => Navigator.of(ctx).pop(),
                              child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => submit(ctx, setModalState),
                              icon: submitting
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
                                  : const Icon(Icons.check),
                              label: Text(l.isArabic ? 'حفظ' : 'Save'),
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
        );
      },
      );
    } finally {
      for (final ctrl in allControllers) {
        ctrl.dispose();
      }
    }
  }

  Future<void> _openAutoReplyEditor(Map<String, dynamic>? existing) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final initialText = (existing?['text'] ?? '').toString();
    final textCtrl = TextEditingController(text: initialText);
    bool enabled = (existing?['enabled'] as bool?) ?? true;
    bool submitting = false;
    String? error;
    String? mutationIdempotencyKey;
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                            Icons.message_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .90),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'رسالة ترحيب تلقائية'
                                  : 'Automatic welcome message',
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
                      Text(
                        l.isArabic
                            ? 'سيتم عرض هذه الرسالة تلقائياً في الدردشة عندما يفتح المستخدم محادثة مع الحساب الرسمي.'
                            : 'This message will be shown automatically in chat when a user opens a conversation with your Official account.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: textCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'نص رسالة الترحيب'
                              : 'Welcome message text',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'تفعيل هذه الرسالة'
                                  : 'Enable this welcome message',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Switch(
                            value: enabled,
                            onChanged: (v) {
                              setModalState(() {
                                enabled = v;
                              });
                            },
                          ),
                        ],
                      ),
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
                                      final headers =
                                          await _hdr(jsonBody: true);
                                      mutationIdempotencyKey ??=
                                          newPaymentsIdempotencyKey(
                                        existing != null &&
                                                (existing['id'] != null)
                                            ? 'official-auto-reply-patch'
                                            : 'official-auto-reply-create',
                                      );
                                      headers['Idempotency-Key'] =
                                          mutationIdempotencyKey!;
                                      http.Response r;
                                      if (existing != null &&
                                          (existing['id'] != null)) {
                                        final id = existing['id'].toString();
                                        final uri = _ownerAdminUri(
                                          pathSegments: <String>[
                                            'admin',
                                            'official_auto_replies',
                                            id,
                                          ],
                                        );
                                        if (uri == null) {
                                          setModalState(() {
                                            submitting = false;
                                            error = _invalidServerUrlMessage(
                                              isArabic: l.isArabic,
                                            );
                                          });
                                          return;
                                        }
                                        r = await _http
                                            .patch(
                                              uri,
                                              headers: headers,
                                              body: jsonEncode({
                                                'text': text,
                                                'enabled': enabled,
                                              }),
                                            )
                                            .timeout(
                                                _officialOwnerRequestTimeout);
                                      } else {
                                        final uri = _ownerAdminUri(
                                          pathSegments: <String>[
                                            'admin',
                                            'official_accounts',
                                            widget.accountId,
                                            'auto_replies',
                                          ],
                                        );
                                        if (uri == null) {
                                          setModalState(() {
                                            submitting = false;
                                            error = _invalidServerUrlMessage(
                                              isArabic: l.isArabic,
                                            );
                                          });
                                          return;
                                        }
                                        r = await _http
                                            .post(
                                              uri,
                                              headers: headers,
                                              body: jsonEncode({
                                                'kind': 'welcome',
                                                'text': text,
                                                'enabled': enabled,
                                              }),
                                            )
                                            .timeout(
                                                _officialOwnerRequestTimeout);
                                      }
                                      if (r.statusCode < 200 ||
                                          r.statusCode >= 300) {
                                        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
                                          context,
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          loginPageBuilder: (_) =>
                                              const LoginPage(),
                                        )) {
                                          return;
                                        }
                                        final msg = sanitizeHttpError(
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          isArabic: l.isArabic,
                                        );
                                        if (!mounted) return;
                                        setModalState(() {
                                          submitting = false;
                                          error = msg;
                                        });
                                        return;
                                      }
                                      if (!mounted) return;
                                      Navigator.of(ctx).pop();
                                      await _load();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l.isArabic
                                                ? 'تم حفظ رسالة الترحيب.'
                                                : 'Welcome message saved.',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
                                        context,
                                        error: e,
                                        loginPageBuilder: (_) =>
                                            const LoginPage(),
                                      )) {
                                        return;
                                      }
                                      if (!mounted) return;
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
                              l.isArabic ? 'حفظ' : 'Save',
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
    } finally {
      textCtrl.dispose();
    }
  }

  Future<void> _openKeywordAutoReplyEditor(
      Map<String, dynamic>? existing) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final initialKeyword = (existing?['keyword'] ?? '').toString();
    final initialText = (existing?['text'] ?? '').toString();
    final kwCtrl = TextEditingController(text: initialKeyword);
    final textCtrl = TextEditingController(text: initialText);
    bool enabled = (existing?['enabled'] as bool?) ?? true;
    bool submitting = false;
    String? error;
    String? mutationIdempotencyKey;
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                            Icons.rule_folder_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .90),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'قاعدة رد تلقائي لكلمة مفتاحية'
                                  : 'Keyword auto‑reply rule',
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
                        controller: kwCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'الكلمة أو العبارة'
                              : 'Keyword or phrase',
                          helperText: l.isArabic
                              ? 'سيتم مطابقة الكلمة داخل النص (مطابقة جزئية، بدون حساسية لحالة الأحرف).'
                              : 'Matched anywhere in the message text (case‑insensitive substring).',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: textCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'نص الرد التلقائي'
                              : 'Auto‑reply text',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              l.isArabic
                                  ? 'تفعيل هذه القاعدة'
                                  : 'Enable this rule',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Switch(
                            value: enabled,
                            onChanged: (v) {
                              setModalState(() {
                                enabled = v;
                              });
                            },
                          ),
                        ],
                      ),
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
                                    final kw = kwCtrl.text.trim();
                                    final txt = textCtrl.text.trim();
                                    if (kw.isEmpty || txt.isEmpty) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'الكلمة والنص مطلوبان.'
                                            : 'Keyword and text are required.';
                                      });
                                      return;
                                    }
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final headers =
                                          await _hdr(jsonBody: true);
                                      mutationIdempotencyKey ??=
                                          newPaymentsIdempotencyKey(
                                        existing != null &&
                                                (existing['id'] != null)
                                            ? 'official-auto-reply-patch'
                                            : 'official-auto-reply-create',
                                      );
                                      headers['Idempotency-Key'] =
                                          mutationIdempotencyKey!;
                                      http.Response r;
                                      if (existing != null &&
                                          (existing['id'] != null)) {
                                        final id = existing['id'].toString();
                                        final uri = _ownerAdminUri(
                                          pathSegments: <String>[
                                            'admin',
                                            'official_auto_replies',
                                            id,
                                          ],
                                        );
                                        if (uri == null) {
                                          setModalState(() {
                                            submitting = false;
                                            error = _invalidServerUrlMessage(
                                              isArabic: l.isArabic,
                                            );
                                          });
                                          return;
                                        }
                                        r = await _http
                                            .patch(
                                              uri,
                                              headers: headers,
                                              body: jsonEncode({
                                                'kind': 'keyword',
                                                'keyword': kw,
                                                'text': txt,
                                                'enabled': enabled,
                                              }),
                                            )
                                            .timeout(
                                                _officialOwnerRequestTimeout);
                                      } else {
                                        final uri = _ownerAdminUri(
                                          pathSegments: <String>[
                                            'admin',
                                            'official_accounts',
                                            widget.accountId,
                                            'auto_replies',
                                          ],
                                        );
                                        if (uri == null) {
                                          setModalState(() {
                                            submitting = false;
                                            error = _invalidServerUrlMessage(
                                              isArabic: l.isArabic,
                                            );
                                          });
                                          return;
                                        }
                                        r = await _http
                                            .post(
                                              uri,
                                              headers: headers,
                                              body: jsonEncode({
                                                'kind': 'keyword',
                                                'keyword': kw,
                                                'text': txt,
                                                'enabled': enabled,
                                              }),
                                            )
                                            .timeout(
                                                _officialOwnerRequestTimeout);
                                      }
                                      if (r.statusCode < 200 ||
                                          r.statusCode >= 300) {
                                        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
                                          context,
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          loginPageBuilder: (_) =>
                                              const LoginPage(),
                                        )) {
                                          return;
                                        }
                                        final msg = sanitizeHttpError(
                                          statusCode: r.statusCode,
                                          rawBody: r.body,
                                          isArabic: l.isArabic,
                                        );
                                        if (!mounted) return;
                                        setModalState(() {
                                          submitting = false;
                                          error = msg;
                                        });
                                        return;
                                      }
                                      if (!mounted) return;
                                      Navigator.of(ctx).pop();
                                      await _load();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l.isArabic
                                                ? 'تم حفظ قاعدة الكلمة المفتاحية.'
                                                : 'Keyword rule saved.',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
                                        context,
                                        error: e,
                                        loginPageBuilder: (_) =>
                                            const LoginPage(),
                                      )) {
                                        return;
                                      }
                                      if (!mounted) return;
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
                              l.isArabic ? 'حفظ' : 'Save',
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
    } finally {
      kwCtrl.dispose();
      textCtrl.dispose();
    }
  }
}

class _OfficialInsightChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OfficialInsightChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text('$label: $value', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _OfficialWorkspaceFocusData {
  final String id;
  final String label;
  final int signalCount;
  final _OfficialCommandLaneStatusTone statusTone;

  const _OfficialWorkspaceFocusData({
    required this.id,
    required this.label,
    required this.signalCount,
    required this.statusTone,
  });
}

class _OfficialWorkspaceSignalData {
  final String id;
  final String label;
  final String value;

  const _OfficialWorkspaceSignalData({
    required this.id,
    required this.label,
    required this.value,
  });
}

class _OfficialCommandLaneData {
  final String id;
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final _OfficialCommandLaneStatusTone statusTone;
  final String statusLabel;
  final String nextAction;

  const _OfficialCommandLaneData({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.statusTone,
    required this.statusLabel,
    required this.nextAction,
  });
}

enum _OfficialCommandLaneStatusTone {
  alert,
  watch,
  healthy,
}

class _OfficialCommandLaneToneStyle {
  final Color background;
  final Color foreground;

  const _OfficialCommandLaneToneStyle({
    required this.background,
    required this.foreground,
  });
}

_OfficialCommandLaneToneStyle _officialCommandLaneStatusStyle(
  ThemeData theme,
  _OfficialCommandLaneStatusTone tone,
) {
  return switch (tone) {
    _OfficialCommandLaneStatusTone.alert => _OfficialCommandLaneToneStyle(
        background: theme.colorScheme.errorContainer.withValues(alpha: .78),
        foreground: theme.colorScheme.onErrorContainer,
      ),
    _OfficialCommandLaneStatusTone.watch => _OfficialCommandLaneToneStyle(
        background: theme.colorScheme.tertiaryContainer.withValues(alpha: .70),
        foreground: theme.colorScheme.onTertiaryContainer,
      ),
    _OfficialCommandLaneStatusTone.healthy => _OfficialCommandLaneToneStyle(
        background: theme.colorScheme.secondaryContainer.withValues(alpha: .72),
        foreground: theme.colorScheme.onSecondaryContainer,
      ),
  };
}

class _OfficialStatusCountChip extends StatelessWidget {
  final String label;
  final int count;
  final _OfficialCommandLaneStatusTone tone;

  const _OfficialStatusCountChip({
    super.key,
    required this.label,
    required this.count,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toneStyle = _officialCommandLaneStatusStyle(theme, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: toneStyle.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $count',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: toneStyle.foreground,
        ),
      ),
    );
  }
}

class _OfficialCommandLaneCard extends StatelessWidget {
  final _OfficialCommandLaneData lane;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onNextTap;
  final String nextLabel;
  final String nextActionPrompt;

  const _OfficialCommandLaneCard({
    super.key,
    required this.lane,
    required this.selected,
    required this.onTap,
    required this.onNextTap,
    required this.nextLabel,
    required this.nextActionPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusStyle = _officialCommandLaneStatusStyle(theme, lane.statusTone);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: .40)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: .35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: .45)
                : theme.colorScheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            lane.icon,
                            size: 18,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .92),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Container(
                                  key: Key(
                                      'officialOwnerCommandLaneStatus_${lane.id}'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusStyle.background,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    lane.statusLabel,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: statusStyle.foreground,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        lane.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: .76,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lane.value,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lane.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: .72,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: Key('officialOwnerCommandLaneNextAction_${lane.id}'),
                  onTap: onNextTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    key: Key('officialOwnerCommandLaneNext_${lane.id}'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: .4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              nextLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .68),
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.arrow_outward_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .62),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lane.nextAction,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          nextActionPrompt,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .92),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfficialQrActionRow extends StatelessWidget {
  final String keyPrefix;
  final bool isArabic;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onPoster;

  const _OfficialQrActionRow({
    required this.keyPrefix,
    required this.isArabic,
    required this.onCopy,
    required this.onShare,
    required this.onPoster,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: Key('${keyPrefix}CopyQr'),
          onPressed: onCopy,
          icon: const Icon(Icons.copy_all_outlined, size: 18),
          label: Text(isArabic ? 'نسخ الحمولة' : 'Copy payload'),
        ),
        OutlinedButton.icon(
          key: Key('${keyPrefix}ShareQr'),
          onPressed: onShare,
          icon: const Icon(Icons.qr_code_2_outlined, size: 18),
          label: Text(isArabic ? 'مشاركة QR' : 'Share QR'),
        ),
        OutlinedButton.icon(
          key: Key('${keyPrefix}PosterQr'),
          onPressed: onPoster,
          icon: const Icon(Icons.print_outlined, size: 18),
          label: Text(isArabic ? 'عرض الملصق' : 'Poster view'),
        ),
      ],
    );
  }
}

class _OfficialQrSharePanel extends StatelessWidget {
  final String payload;
  final String title;
  final String closeLabel;

  const _OfficialQrSharePanel({
    required this.payload,
    required this.title,
    required this.closeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            payload,
            key: const Key('officialOwnerQrSharePayload'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Center(
            child: QrImageView(data: payload, size: 220),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('officialOwnerQrShareClose'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(closeLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficialQrPosterPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String closeLabel;
  final String copyPathLabel;
  final String saveLabel;
  final String shareLabel;
  final String accountName;
  final String payload;
  final String? category;
  final String? city;
  final String? address;
  final String? openingHours;
  final String? websiteUrl;
  final bool isArabic;
  final VoidCallback onCopyPosterPath;
  final VoidCallback onSavePoster;
  final VoidCallback onSharePoster;

  const _OfficialQrPosterPanel({
    required this.title,
    required this.subtitle,
    required this.closeLabel,
    required this.copyPathLabel,
    required this.saveLabel,
    required this.shareLabel,
    required this.accountName,
    required this.payload,
    required this.category,
    required this.city,
    required this.address,
    required this.openingHours,
    required this.websiteUrl,
    required this.isArabic,
    required this.onCopyPosterPath,
    required this.onSavePoster,
    required this.onSharePoster,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setupGuideTitle =
        isArabic ? 'دليل الإعداد السريع' : 'Quick setup guide';
    final setupGuideSubtitle = isArabic
        ? 'أبقِ هذا الملصق قابلاً للمسح عند الطباعة أو العرض على الكاونتر.'
        : 'Keep the poster easy to scan when printing or placing it on the counter.';
    final printSetupTitle = isArabic ? 'إعداد الطباعة' : 'Print setup';
    final counterSetupTitle = isArabic ? 'إعداد الكاونتر' : 'Counter setup';
    final printSetupSteps = <String>[
      isArabic
          ? 'اطبع بحجم A5 أو أكبر مع هامش أبيض واضح حول رمز QR.'
          : 'Print at A5 or larger and keep a clear white margin around the QR.',
      isArabic
          ? 'استخدم ورقاً غير لامع أو تصفيحاً خفيفاً لتقليل الانعكاس.'
          : 'Use matte stock or light lamination to reduce glare.',
      isArabic
          ? 'استبدل النسخة المطبوعة فور تغيير الرابط أو بيانات الحساب.'
          : 'Replace the printout as soon as the payload or account details change.',
    ];
    final counterSetupSteps = <String>[
      isArabic
          ? 'ضع الملصق عند مستوى العين وبعيداً عن الزجاج والسطوح العاكسة.'
          : 'Place the poster near eye level and away from glass or reflective surfaces.',
      isArabic
          ? 'اترك مسافة مسح مريحة أمام العميل من 30 إلى 60 سم.'
          : 'Leave a comfortable 30-60 cm scan distance in front of the customer.',
      isArabic
          ? 'احتفظ بنسخة احتياطية قرب نقطة الخدمة إذا كان الكاونتر مزدحماً.'
          : 'Keep a spare copy near the service point for busy counter shifts.',
    ];
    final metadata = <String>[
      if ((category ?? '').isNotEmpty) category!,
      if ((city ?? '').isNotEmpty) city!,
      if ((openingHours ?? '').isNotEmpty) openingHours!,
    ];
    final readiness = _buildOfficialQrReadinessData(
      isArabic: isArabic,
      payload: payload,
      address: address,
      openingHours: openingHours,
      websiteUrl: websiteUrl,
    );
    final detailLine = (address ?? '').trim().isNotEmpty ? address!.trim() : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: .72,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('officialOwnerQrPosterClose'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: closeLabel,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('officialOwnerQrPosterPanel'),
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer.withValues(alpha: .92),
                    theme.colorScheme.surfaceContainerHighest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isArabic ? 'امسح للمتابعة' : 'Scan to follow',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    accountName,
                    key: const Key('officialOwnerQrPosterName'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: metadata
                          .map(
                            (entry) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface
                                    .withValues(alpha: .72),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                entry,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: QrImageView(
                      key: const Key('officialOwnerQrPosterCode'),
                      data: payload,
                      size: 220,
                    ),
                  ),
                  if (detailLine.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      detailLine,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SelectableText(
                    payload,
                    key: const Key('officialOwnerQrPosterPayload'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .78),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isArabic
                        ? 'استخدم هذه البطاقة للعرض على الطاولة أو للطباعة السريعة عند نقطة الخدمة.'
                        : 'Use this card for countertop display or a quick printed handout at the service point.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .72),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _OfficialQrReadinessPanel(
              key: const Key('officialOwnerQrPosterReadinessPanel'),
              statusKey: const Key('officialOwnerQrPosterReadinessStatus'),
              readiness: readiness,
              checkKeyPrefix: 'officialOwnerQrPosterCheck',
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('officialOwnerQrPosterSetupPanel'),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .55,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: .5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    setupGuideTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    setupGuideSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .72),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _OfficialQrPosterInstructionCard(
                        key: const Key('officialOwnerQrPosterSetup_print'),
                        icon: Icons.print_outlined,
                        title: printSetupTitle,
                        steps: printSetupSteps,
                        isArabic: isArabic,
                      ),
                      _OfficialQrPosterInstructionCard(
                        key: const Key('officialOwnerQrPosterSetup_counter'),
                        icon: Icons.point_of_sale_outlined,
                        title: counterSetupTitle,
                        steps: counterSetupSteps,
                        isArabic: isArabic,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('officialOwnerQrPosterCopyPath'),
                  onPressed: onCopyPosterPath,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: Text(copyPathLabel),
                ),
                OutlinedButton.icon(
                  key: const Key('officialOwnerQrPosterSave'),
                  onPressed: onSavePoster,
                  icon: const Icon(Icons.save_alt_outlined, size: 18),
                  label: Text(saveLabel),
                ),
                FilledButton.icon(
                  key: const Key('officialOwnerQrPosterShare'),
                  onPressed: onSharePoster,
                  icon: const Icon(Icons.ios_share_outlined, size: 18),
                  label: Text(shareLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfficialQrReadinessData {
  final _OfficialCommandLaneStatusTone statusTone;
  final String statusLabel;
  final String detail;
  final String summaryLabel;
  final List<_OfficialQrPosterReadinessCheckData> checks;

  const _OfficialQrReadinessData({
    required this.statusTone,
    required this.statusLabel,
    required this.detail,
    required this.summaryLabel,
    required this.checks,
  });
}

_OfficialQrReadinessData _buildOfficialQrReadinessData({
  required bool isArabic,
  required String? payload,
  required String? address,
  required String? openingHours,
  required String? websiteUrl,
}) {
  final normalizedPayload = normalizeOfficialQrPayload(payload);
  final checks = <_OfficialQrPosterReadinessCheckData>[
    _OfficialQrPosterReadinessCheckData(
      id: 'payload',
      label: isArabic ? 'رمز QR' : 'QR payload',
      passed: normalizedPayload != null,
    ),
    _OfficialQrPosterReadinessCheckData(
      id: 'address',
      label: isArabic ? 'العنوان' : 'Address',
      passed: (address ?? '').trim().isNotEmpty,
    ),
    _OfficialQrPosterReadinessCheckData(
      id: 'hours',
      label: isArabic ? 'الساعات' : 'Hours',
      passed: (openingHours ?? '').trim().isNotEmpty,
    ),
    _OfficialQrPosterReadinessCheckData(
      id: 'website',
      label: isArabic ? 'الموقع' : 'Website',
      passed: (websiteUrl ?? '').trim().isNotEmpty,
    ),
  ];
  final readyCount = checks.where((check) => check.passed).length;
  final missingLabels = checks
      .where((check) => !check.passed)
      .map((check) => check.label)
      .toList(growable: false);
  final statusTone = normalizedPayload == null
      ? _OfficialCommandLaneStatusTone.alert
      : missingLabels.isEmpty
          ? _OfficialCommandLaneStatusTone.healthy
          : _OfficialCommandLaneStatusTone.watch;
  final statusLabel = normalizedPayload == null
      ? (isArabic ? 'ينقص QR' : 'QR missing')
      : missingLabels.isEmpty
          ? (isArabic ? 'جاهز للطباعة' : 'Ready to print')
          : (isArabic ? 'يحتاج تحديثاً' : 'Needs update');
  final detail = missingLabels.isEmpty
      ? (isArabic
          ? 'بيانات الملف وQR مكتملة للعرض على الكاونتر أو للطباعة السريعة.'
          : 'Profile and QR details are complete for counter display or quick print.')
      : isArabic
          ? 'أكمل ${missingLabels.join('، ')} قبل توزيع هذا الملصق.'
          : 'Add ${missingLabels.join(', ')} before distributing this poster.';
  final summaryLabel = isArabic
      ? '$readyCount من ${checks.length} إشارات جاهزة'
      : '$readyCount of ${checks.length} checks ready';
  return _OfficialQrReadinessData(
    statusTone: statusTone,
    statusLabel: statusLabel,
    detail: detail,
    summaryLabel: summaryLabel,
    checks: checks,
  );
}

class _OfficialQrReadinessPanel extends StatelessWidget {
  final Key? statusKey;
  final _OfficialQrReadinessData readiness;
  final String checkKeyPrefix;
  final String? title;
  final String? subtitle;

  const _OfficialQrReadinessPanel({
    super.key,
    this.statusKey,
    required this.readiness,
    required this.checkKeyPrefix,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readinessStyle =
        _officialCommandLaneStatusStyle(theme, readiness.statusTone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: readinessStyle.background.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: readinessStyle.foreground.withValues(alpha: .20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .72),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                key: statusKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: readinessStyle.foreground.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  readiness.statusLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: readinessStyle.foreground,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  readiness.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: readinessStyle.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            readiness.summaryLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: readinessStyle.foreground.withValues(alpha: .88),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final check in readiness.checks)
                _OfficialQrPosterReadinessChip(
                  key: Key('${checkKeyPrefix}_${check.id}'),
                  check: check,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfficialQrPosterReadinessCheckData {
  final String id;
  final String label;
  final bool passed;

  const _OfficialQrPosterReadinessCheckData({
    required this.id,
    required this.label,
    required this.passed,
  });
}

class _OfficialQrPosterReadinessChip extends StatelessWidget {
  final _OfficialQrPosterReadinessCheckData check;

  const _OfficialQrPosterReadinessChip({
    super.key,
    required this.check,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = check.passed
        ? _OfficialCommandLaneStatusTone.healthy
        : _OfficialCommandLaneStatusTone.watch;
    final toneStyle = _officialCommandLaneStatusStyle(theme, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: toneStyle.background.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: toneStyle.foreground.withValues(alpha: .22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            check.passed ? Icons.check_circle_outline : Icons.schedule_outlined,
            size: 16,
            color: toneStyle.foreground,
          ),
          const SizedBox(width: 6),
          Text(
            check.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: toneStyle.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficialQrPosterInstructionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> steps;
  final bool isArabic;

  const _OfficialQrPosterInstructionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.steps,
    required this.isArabic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: .86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: theme.colorScheme.primary.withValues(alpha: .92),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < steps.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      isArabic ? '•' : '${i + 1}.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: .78,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (i != steps.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

Uint8List _buildOfficialQrPosterSvg({
  required String accountName,
  required String payload,
  required String? category,
  required String? city,
  required String? address,
  required String? openingHours,
  required bool isArabic,
  required ColorScheme colorScheme,
}) {
  const width = 1200.0;
  const height = 1680.0;
  const cardLeft = 92.0;
  const cardTop = 92.0;
  const cardWidth = width - (cardLeft * 2);
  const cardHeight = height - 176.0;
  const pillWidth = 220.0;
  const pillHeight = 50.0;
  const qrBoxSize = 720.0;
  const qrInnerSize = 560.0;
  final metadata = <String>[
    if ((category ?? '').trim().isNotEmpty) category!.trim(),
    if ((city ?? '').trim().isNotEmpty) city!.trim(),
    if ((openingHours ?? '').trim().isNotEmpty) openingHours!.trim(),
  ];
  final direction = isArabic ? 'rtl' : 'ltr';
  final titleLines = _wrapPosterSvgText(accountName, 18, maxLines: 2);
  final addressLines =
      _wrapPosterSvgText((address ?? '').trim(), 34, maxLines: 2);
  final payloadLines = _wrapPosterSvgText(payload, 42, maxLines: 3);
  final footerLines = _wrapPosterSvgText(
    isArabic
        ? 'استخدم هذه البطاقة للعرض على الطاولة أو للطباعة السريعة عند نقطة الخدمة.'
        : 'Use this card for countertop display or a quick printed handout at the service point.',
    48,
    maxLines: 3,
  );
  final pillY = cardTop + 48;
  final titleY = pillY + 92;
  final chipsY = titleY + (titleLines.length * 88);
  final qrBoxY = chipsY + (metadata.isEmpty ? 28 : 84);
  final qrBoxX = (width - qrBoxSize) / 2;
  final qrInnerX = (width - qrInnerSize) / 2;
  final qrInnerY = qrBoxY + ((qrBoxSize - qrInnerSize) / 2);
  final addressY = qrBoxY + qrBoxSize + 68;
  final payloadY =
      addressY + (addressLines.isEmpty ? 0 : (addressLines.length * 44) + 18);
  final footerY = payloadY + (payloadLines.length * 34) + 26;
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${width.toInt()}" height="${height.toInt()}" viewBox="0 0 ${width.toInt()} ${height.toInt()}">',
    )
    ..writeln(
      '<rect width="${width.toInt()}" height="${height.toInt()}" fill="${_svgColor(colorScheme.primaryContainer)}"/>',
    )
    ..writeln(
      '<rect x="${cardLeft.toStringAsFixed(1)}" y="${cardTop.toStringAsFixed(1)}" width="${cardWidth.toStringAsFixed(1)}" height="${cardHeight.toStringAsFixed(1)}" rx="44" fill="${_svgColor(colorScheme.surface)}"/>',
    )
    ..writeln(
      '<rect x="${((width - pillWidth) / 2).toStringAsFixed(1)}" y="${pillY.toStringAsFixed(1)}" width="${pillWidth.toStringAsFixed(1)}" height="${pillHeight.toStringAsFixed(1)}" rx="25" fill="${_svgColor(colorScheme.primary.withValues(alpha: .14))}"/>',
    )
    ..writeln(
      '<text x="${(width / 2).toStringAsFixed(1)}" y="${(pillY + 32).toStringAsFixed(1)}" text-anchor="middle" direction="$direction" font-family="sans-serif" font-size="24" font-weight="700" fill="${_svgColor(colorScheme.primary)}">${_escapeSvgText(isArabic ? 'امسح للمتابعة' : 'Scan to follow')}</text>',
    );

  for (var i = 0; i < titleLines.length; i++) {
    buffer.writeln(
      '<text x="${(width / 2).toStringAsFixed(1)}" y="${(titleY + (i * 80)).toStringAsFixed(1)}" text-anchor="middle" direction="$direction" font-family="sans-serif" font-size="74" font-weight="800" fill="${_svgColor(colorScheme.onSurface)}">${_escapeSvgText(titleLines[i])}</text>',
    );
  }

  if (metadata.isNotEmpty) {
    const chipHeight = 44.0;
    const chipSpacing = 14.0;
    final chipWidths =
        metadata.map((entry) => 36.0 + (entry.runes.length * 14.0)).toList();
    final totalWidth = chipWidths.fold<double>(0, (sum, width) => sum + width) +
        (chipSpacing * (metadata.length - 1));
    var chipX = (width - totalWidth) / 2;
    for (var i = 0; i < metadata.length; i++) {
      final chipWidth = chipWidths[i];
      buffer.writeln(
        '<rect x="${chipX.toStringAsFixed(1)}" y="${chipsY.toStringAsFixed(1)}" width="${chipWidth.toStringAsFixed(1)}" height="$chipHeight" rx="22" fill="${_svgColor(colorScheme.surfaceContainerHighest)}"/>',
      );
      buffer.writeln(
        '<text x="${(chipX + (chipWidth / 2)).toStringAsFixed(1)}" y="${(chipsY + 29).toStringAsFixed(1)}" text-anchor="middle" direction="$direction" font-family="sans-serif" font-size="24" font-weight="700" fill="${_svgColor(colorScheme.onSurface)}">${_escapeSvgText(metadata[i])}</text>',
      );
      chipX += chipWidth + chipSpacing;
    }
  }

  buffer
    ..writeln(
      '<rect x="${qrBoxX.toStringAsFixed(1)}" y="${qrBoxY.toStringAsFixed(1)}" width="${qrBoxSize.toStringAsFixed(1)}" height="${qrBoxSize.toStringAsFixed(1)}" rx="36" fill="#FFFFFF"/>',
    )
    ..writeln(
      '<rect x="${qrBoxX.toStringAsFixed(1)}" y="${qrBoxY.toStringAsFixed(1)}" width="${qrBoxSize.toStringAsFixed(1)}" height="${qrBoxSize.toStringAsFixed(1)}" rx="36" fill="none" stroke="${_svgColor(colorScheme.outlineVariant)}" stroke-width="3"/>',
    )
    ..write(
      _buildPosterSvgQrGroup(
        payload: payload,
        left: qrInnerX,
        top: qrInnerY,
        size: qrInnerSize,
      ),
    );

  for (var i = 0; i < addressLines.length; i++) {
    buffer.writeln(
      '<text x="${(width / 2).toStringAsFixed(1)}" y="${(addressY + (i * 40)).toStringAsFixed(1)}" text-anchor="middle" direction="$direction" font-family="sans-serif" font-size="34" font-weight="600" fill="${_svgColor(colorScheme.onSurface)}">${_escapeSvgText(addressLines[i])}</text>',
    );
  }

  for (var i = 0; i < payloadLines.length; i++) {
    buffer.writeln(
      '<text x="${(width / 2).toStringAsFixed(1)}" y="${(payloadY + (i * 32)).toStringAsFixed(1)}" text-anchor="middle" direction="$direction" font-family="monospace" font-size="26" fill="${_svgColor(colorScheme.onSurface.withValues(alpha: .78))}">${_escapeSvgText(payloadLines[i])}</text>',
    );
  }

  for (var i = 0; i < footerLines.length; i++) {
    buffer.writeln(
      '<text x="${(width / 2).toStringAsFixed(1)}" y="${(footerY + (i * 34)).toStringAsFixed(1)}" text-anchor="middle" direction="$direction" font-family="sans-serif" font-size="28" fill="${_svgColor(colorScheme.onSurface.withValues(alpha: .68))}">${_escapeSvgText(footerLines[i])}</text>',
    );
  }

  buffer.writeln('</svg>');
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

String _buildPosterSvgQrGroup({
  required String payload,
  required double left,
  required double top,
  required double size,
}) {
  final code = qr.QrCode.fromData(
    data: payload,
    errorCorrectLevel: qr.QrErrorCorrectLevel.M,
  );
  final image = qr.QrImage(code);
  final moduleSize = size / image.moduleCount;
  final buffer = StringBuffer();
  for (var row = 0; row < image.moduleCount; row++) {
    for (var col = 0; col < image.moduleCount; col++) {
      if (!image.isDark(row, col)) {
        continue;
      }
      buffer.writeln(
        '<rect x="${(left + (col * moduleSize)).toStringAsFixed(2)}" y="${(top + (row * moduleSize)).toStringAsFixed(2)}" width="${moduleSize.toStringAsFixed(2)}" height="${moduleSize.toStringAsFixed(2)}" fill="#101418"/>',
      );
    }
  }
  return buffer.toString();
}

List<String> _wrapPosterSvgText(
  String text,
  int targetChars, {
  required int maxLines,
}) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return const <String>[];
  }
  final words = normalized.split(RegExp(r'\s+'));
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    final candidate = current.isEmpty ? word : '$current $word';
    if (candidate.runes.length <= targetChars || current.isEmpty) {
      current = candidate;
      continue;
    }
    lines.add(current);
    current = word;
    if (lines.length == maxLines - 1) {
      break;
    }
  }
  if (lines.length < maxLines && current.isNotEmpty) {
    lines.add(current);
  }
  if (lines.length > maxLines) {
    return lines.take(maxLines).toList();
  }
  if (lines.length == maxLines &&
      words.join(' ').runes.length > lines.join(' ').runes.length) {
    final last = lines.removeLast();
    final trimmed = last.runes.length > targetChars - 1
        ? String.fromCharCodes(last.runes.take(targetChars - 1))
        : last;
    lines.add('${trimmed.trimRight()}…');
  }
  return lines;
}

String _svgColor(Color color) {
  final alpha = color.a;
  if (alpha >= 1) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return 'rgba($r,$g,$b,${alpha.toStringAsFixed(3)})';
}

String _escapeSvgText(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class _OfficialWorkspaceDesk extends StatelessWidget {
  final String workspaceId;
  final String title;
  final String summary;
  final List<_OfficialWorkspaceSignalData> signals;
  final bool collapsed;
  final bool isArabic;
  final VoidCallback onToggleCollapsed;
  final Widget child;

  const _OfficialWorkspaceDesk({
    required this.workspaceId,
    required this.title,
    required this.summary,
    required this.signals,
    required this.collapsed,
    required this.isArabic,
    required this.onToggleCollapsed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: Key('officialOwnerWorkspace_$workspaceId'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: Key('officialOwnerWorkspaceToggle_$workspaceId'),
                        onPressed: onToggleCollapsed,
                        icon: Icon(
                          collapsed
                              ? Icons.unfold_more_rounded
                              : Icons.unfold_less_rounded,
                        ),
                        label: Text(
                          isArabic
                              ? (collapsed ? 'توسيع' : 'طي')
                              : (collapsed ? 'Expand' : 'Collapse'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  if (signals.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final signal in signals)
                          _OfficialWorkspaceSignalChip(
                            key: Key(
                              'officialOwnerWorkspaceSignal_${workspaceId}_${signal.id}',
                            ),
                            label: signal.label,
                            value: signal.value,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: collapsed
                ? Card(
                    key: Key('officialOwnerWorkspaceCollapsed_$workspaceId'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        isArabic
                            ? 'المكتب مطوي. وسّعه لمراجعة التفاصيل.'
                            : 'Desk collapsed. Expand it to review details.',
                      ),
                    ),
                  )
                : Container(
                    key: Key('officialOwnerWorkspaceBody_$workspaceId'),
                    child: child,
                  ),
          ),
        ],
      ),
    );
  }
}

class _OfficialWorkspaceSignalChip extends StatelessWidget {
  final String label;
  final String value;

  const _OfficialWorkspaceSignalChip({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .50),
        ),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OfficialAttentionItemData {
  final String id;
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  const _OfficialAttentionItemData({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });
}

class _OfficialCommandMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OfficialCommandMetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: .45,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .50),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: theme.colorScheme.primary.withValues(alpha: .90),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .72),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfficialAttentionItem extends StatelessWidget {
  final _OfficialAttentionItemData item;

  const _OfficialAttentionItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 18,
            color: theme.colorScheme.primary.withValues(alpha: .95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .78),
                  ),
                ),
              ],
            ),
          ),
          if (item.onTap != null) ...[
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_outward_rounded,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: .58),
            ),
          ],
        ],
      ),
    );
    if (item.onTap == null) {
      return Container(
        key: Key('officialOwnerAttention_${item.id}'),
        child: card,
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('officialOwnerAttention_${item.id}'),
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}
