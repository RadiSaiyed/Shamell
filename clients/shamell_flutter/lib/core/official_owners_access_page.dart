import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shamell_flutter/core/session_cookie_store.dart';
import '../main.dart' show LoginPage;

import 'access_platform_contracts.dart';
import 'account_privilege_store.dart';
import 'app_shell_widgets.dart' show AppBG;
import 'base_url.dart';
import 'device_binding_reauth.dart';
import 'http_error.dart';
import 'l10n.dart';
import 'official_owner_input_validation.dart';
import 'payments/payments_idempotency.dart';
import 'safe_set_state.dart';
import 'shamell_loading_shimmer.dart';

String _officialOwnerQueueLabel(String queue, bool isArabic) {
  switch (queue) {
    case 'phone_linked':
      return isArabic ? 'مرتبط بالهاتف' : 'Phone linked';
    case 'account_linked':
      return isArabic ? 'مرتبط بالحساب' : 'Account linked';
    case 'dual_identity':
      return isArabic ? 'هاتف + حساب' : 'Dual identity';
    default:
      return isArabic ? 'الكل' : 'All';
  }
}

class OfficialOwnersAccessPage extends StatefulWidget {
  final String baseUrl;
  final String accountId;
  final String accountName;
  final http.Client? httpClient;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;

  const OfficialOwnersAccessPage({
    super.key,
    required this.baseUrl,
    required this.accountId,
    required this.accountName,
    this.httpClient,
    this.privilegeSnapshotOverride,
  });

  @override
  State<OfficialOwnersAccessPage> createState() =>
      _OfficialOwnersAccessPageState();
}

class _OfficialOwnersAccessPageState extends State<OfficialOwnersAccessPage>
    with SafeSetStateMixin<OfficialOwnersAccessPage> {
  static const Duration _officialOwnersRequestTimeout = Duration(seconds: 15);
  static const int _officialOwnersPageSize = 200;
  late final http.Client _http;
  late final bool _ownsHttpClient;

  bool _loading = true;
  bool _loadingPrivileges = true;
  bool _readAccessAllowed = false;
  bool _writeAccessAllowed = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String _error = '';
  List<Map<String, dynamic>> _owners = const <Map<String, dynamic>>[];
  final TextEditingController _searchController = TextEditingController();
  String _selectedQueue = 'all';

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? shamellHttpClient();
    _loadPrivilegesAndOwners();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<void> _loadPrivilegesAndOwners() async {
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

  Uri? _ownersUri({Map<String, String>? queryParameters}) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>[
        'admin',
        'official_accounts',
        widget.accountId,
        'owners',
      ],
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage({bool? isArabic}) {
    final arabic = isArabic ?? L10n.of(context).isArabic;
    return arabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
  }

  Future<void> _load() => _loadPage(reset: true);

  Future<void> _loadMore() => _loadPage(reset: false);

  Future<void> _loadPage({required bool reset}) async {
    if (!reset) {
      if (_loading || _loadingMore || !_hasMore || _owners.isEmpty) {
        return;
      }
      setState(() {
        _loadingMore = true;
      });
    } else {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _hasMore = false;
        _error = '';
      });
    }
    try {
      final queryParameters = <String, String>{
        'limit': '$_officialOwnersPageSize',
      };
      if (!reset && _owners.isNotEmpty) {
        final last = _owners.last;
        final beforeCreatedAt = (last['created_at'] ?? '').toString().trim();
        final beforeId = (last['cursor_id'] as num?)?.toInt() ?? 0;
        if (beforeCreatedAt.isNotEmpty && beforeId > 0) {
          queryParameters['before_created_at'] = beforeCreatedAt;
          queryParameters['before_id'] = '$beforeId';
        } else {
          setState(() {
            _loadingMore = false;
            _hasMore = false;
          });
          return;
        }
      }
      final uri = _ownersUri(queryParameters: queryParameters);
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _owners = const <Map<String, dynamic>>[];
          _loading = false;
          _loadingMore = false;
          _error = _invalidServerUrlMessage();
        });
        return;
      }
      final r = await _http
          .get(uri, headers: await _hdr())
          .timeout(_officialOwnersRequestTimeout);
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
          _owners = const <Map<String, dynamic>>[];
          _loading = false;
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      final owners = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['owners'] is List) {
        for (final e in decoded['owners'] as List) {
          if (e is Map) {
            owners.add(e.cast<String, dynamic>());
          }
        }
      }
      if (!mounted) return;
      final merged = reset ? owners : _mergeOwners(_owners, owners);
      setState(() {
        _owners = merged;
        _loading = false;
        _loadingMore = false;
        _hasMore = owners.length >= _officialOwnersPageSize;
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
      final detail = sanitizeExceptionForUi(error: e);
      if (reset) {
        setState(() {
          _owners = const <Map<String, dynamic>>[];
          _loading = false;
          _loadingMore = false;
          _error = detail;
        });
      } else {
        setState(() {
          _loadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(detail)),
        );
      }
    }
  }

  List<Map<String, dynamic>> _mergeOwners(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final merged = <Map<String, dynamic>>[...current];
    final seen = current.map(_ownerMergeKey).toSet();
    for (final owner in incoming) {
      if (seen.add(_ownerMergeKey(owner))) {
        merged.add(owner);
      }
    }
    return merged;
  }

  String _ownerMergeKey(Map<String, dynamic> owner) {
    final cursorId = (owner['cursor_id'] ?? '').toString().trim();
    if (cursorId.isNotEmpty) {
      return 'id:$cursorId';
    }
    final accountId = (owner['account_id'] ?? '').toString().trim();
    final phone = (owner['phone'] ?? '').toString().trim();
    final createdAt = (owner['created_at'] ?? '').toString().trim();
    return 'owner:$accountId|$phone|$createdAt';
  }

  bool _matchesQueue(Map<String, dynamic> owner, String queue) {
    final hasAccountId =
        (owner['account_id'] ?? '').toString().trim().isNotEmpty;
    final hasPhone = (owner['phone'] ?? '').toString().trim().isNotEmpty;
    switch (queue) {
      case 'phone_linked':
        return hasPhone;
      case 'account_linked':
        return hasAccountId;
      case 'dual_identity':
        return hasAccountId && hasPhone;
      default:
        return true;
    }
  }

  bool _matchesSearch(Map<String, dynamic> owner, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return (owner['account_id'] ?? '')
            .toString()
            .toLowerCase()
            .contains(normalized) ||
        (owner['phone'] ?? '').toString().toLowerCase().contains(normalized) ||
        (owner['created_at'] ?? '')
            .toString()
            .toLowerCase()
            .contains(normalized);
  }

  int _queueCount(String queue) {
    return _owners.where((owner) => _matchesQueue(owner, queue)).length;
  }

  Future<void> _removeOwner(Map<String, dynamic> owner) async {
    if (!_writeAccessAllowed) return;
    final l = L10n.of(context);
    final accountId = (owner['account_id'] ?? '').toString().trim();
    final phone = (owner['phone'] ?? '').toString().trim();
    if (accountId.isEmpty && phone.isEmpty) return;
    final label = phone.isNotEmpty ? phone : accountId;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic ? 'إزالة المالك' : 'Remove owner'),
        content: Text(
          l.isArabic
              ? 'هل تريد إزالة صلاحية المالك عن: $label؟'
              : 'Remove owner access for: $label?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.isArabic ? 'إزالة' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final uri = _ownersUri();
      if (uri == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_invalidServerUrlMessage(isArabic: l.isArabic))),
        );
        return;
      }
      final payload = <String, Object?>{
        'account_id': accountId.isNotEmpty ? accountId : null,
        'phone': phone.isNotEmpty ? phone : null,
      };
      final reqHeaders = await _hdr(jsonBody: true);
      reqHeaders['Idempotency-Key'] =
          newPaymentsIdempotencyKey('official-owner-remove');
      final r = await _http
          .delete(
            uri,
            headers: reqHeaders,
            body: jsonEncode(payload),
          )
          .timeout(_officialOwnersRequestTimeout);
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
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تمت إزالة المالك.' : 'Owner removed.',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sanitizeExceptionForUi(error: e, isArabic: l.isArabic)),
        ),
      );
    }
  }

  Future<void> _openOwnerEditor() async {
    if (!_writeAccessAllowed) return;
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final accountIdCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? idempotencyKey;
    bool submitting = false;
    String? error;
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
                            Icons.person_add_alt_1_outlined,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: .90),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.isArabic ? 'إضافة مالك' : 'Add owner',
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
                            ? 'أضف مالكاً عبر معرّف الحساب (64 حرف Hex) أو الهاتف (E.164 مثل +963...).'
                            : 'Add an owner by account ID (64-char hex) or phone (E.164, e.g. +963...).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: accountIdCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'معرّف الحساب (اختياري)'
                              : 'Account ID (optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: phoneCtrl,
                        decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'الهاتف E.164 (اختياري)'
                              : 'Phone E.164 (optional)',
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
                                    final accountIdInput =
                                        accountIdCtrl.text.trim();
                                    final phoneInput = phoneCtrl.text.trim();
                                    if (accountIdInput.isEmpty &&
                                        phoneInput.isEmpty) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'أدخل معرّف الحساب أو الهاتف.'
                                            : 'Enter account ID or phone.';
                                      });
                                      return;
                                    }
                                    if (accountIdInput.isNotEmpty &&
                                        !isValidOfficialOwnerAccountId(
                                          accountIdInput,
                                        )) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'معرّف الحساب يجب أن يكون 64 حرف Hex.'
                                            : 'Account ID must be 64 hex characters.';
                                      });
                                      return;
                                    }
                                    if (phoneInput.isNotEmpty &&
                                        !isValidOfficialOwnerPhoneE164(
                                          phoneInput,
                                        )) {
                                      setModalState(() {
                                        error = l.isArabic
                                            ? 'صيغة الهاتف غير صالحة. استخدم E.164 مثل +963...'
                                            : 'Invalid phone format. Use E.164 like +963...';
                                      });
                                      return;
                                    }
                                    final accountId =
                                        normalizeOfficialOwnerAccountId(
                                      accountIdInput,
                                    );
                                    final phone = phoneInput;
                                    setModalState(() {
                                      submitting = true;
                                      error = null;
                                    });
                                    try {
                                      final uri = _ownersUri();
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
                                        'account_id': accountId.isNotEmpty
                                            ? accountId
                                            : null,
                                        'phone':
                                            phone.isNotEmpty ? phone : null,
                                      };
                                      idempotencyKey ??=
                                          newPaymentsIdempotencyKey(
                                        'official-owner-add',
                                      );
                                      final reqHeaders =
                                          await _hdr(jsonBody: true);
                                      reqHeaders['Idempotency-Key'] =
                                          idempotencyKey!;
                                      final r = await _http
                                          .post(
                                            uri,
                                            headers: reqHeaders,
                                            body: jsonEncode(payload),
                                          )
                                          .timeout(
                                              _officialOwnersRequestTimeout);
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
                                        if (!mounted) return;
                                        setModalState(() {
                                          submitting = false;
                                          error = sanitizeHttpError(
                                            statusCode: r.statusCode,
                                            rawBody: r.body,
                                            isArabic: l.isArabic,
                                          );
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
                                                ? 'تمت إضافة المالك.'
                                                : 'Owner added.',
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
                              l.isArabic ? 'إضافة' : 'Add',
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
      accountIdCtrl.dispose();
      phoneCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final visibleOwners = _owners
        .where((owner) => _matchesQueue(owner, _selectedQueue))
        .where((owner) => _matchesSearch(owner, _searchController.text))
        .toList(growable: false);
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'مالكو الحساب الرسمي' : 'Official owners',
          ),
        ),
        body: const ShamellSkeletonList(itemCount: 6),
      );
    }
    if (!_readAccessAllowed) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'مالكو الحساب الرسمي' : 'Official owners',
          ),
        ),
        body: AppBG(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l.isArabic
                    ? 'هذا الحساب غير مخوّل لإدارة ملاك هذا الحساب الرسمي.'
                    : 'Your account is not allowed to access this official owners page.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'مالكو الحساب الرسمي' : 'Official owners',
        ),
      ),
      body: AppBG(
        child: _loading
            ? const ShamellSkeletonList(itemCount: 6)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.accountName.isNotEmpty
                                ? widget.accountName
                                : widget.accountId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.accountId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
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
                            l.isArabic
                                ? 'المالكون والصلاحيات'
                                : 'Owners & access',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _error,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: l.isArabic
                                  ? 'ابحث في المالكين'
                                  : 'Search owners',
                              hintText: l.isArabic
                                  ? 'الحساب أو الهاتف أو وقت الإضافة'
                                  : 'Account, phone, or added time',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              suffixIcon: _searchController.text.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {});
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                label: Text(
                                  '${l.isArabic ? 'المحمّل' : 'Loaded'} ${_owners.length}',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  '${l.isArabic ? 'مرتبط بالهاتف' : 'Phone linked'} ${_queueCount('phone_linked')}',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  '${l.isArabic ? 'مرتبط بالحساب' : 'Account linked'} ${_queueCount('account_linked')}',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  '${l.isArabic ? 'هاتف + حساب' : 'Dual identity'} ${_queueCount('dual_identity')}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.isArabic ? 'الطابور' : 'Queue',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final queue in const <String>[
                                'all',
                                'phone_linked',
                                'account_linked',
                                'dual_identity',
                              ])
                                ChoiceChip(
                                  label: Text(
                                    '${_officialOwnerQueueLabel(queue, l.isArabic)} (${queue == 'all' ? _owners.length : _queueCount(queue)})',
                                  ),
                                  selected: _selectedQueue == queue,
                                  onSelected: (selected) {
                                    if (!selected) return;
                                    setState(() {
                                      _selectedQueue = queue;
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.isArabic
                                ? 'عرض ${visibleOwners.length} من ${_owners.length} مالك'
                                : 'Showing ${visibleOwners.length} of ${_owners.length} owners',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_owners.isEmpty)
                            Text(
                              l.isArabic
                                  ? 'لا يوجد مالكون إضافيون حتى الآن.'
                                  : 'No additional owners yet.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            )
                          else if (visibleOwners.isEmpty)
                            Text(
                              l.isArabic
                                  ? 'لا يوجد مالكون يطابقون البحث أو الطابور الحالي.'
                                  : 'No owners match the current search or queue.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .70),
                              ),
                            )
                          else
                            Column(
                              children: [
                                for (final o in visibleOwners)
                                  Builder(
                                    builder: (ctx) {
                                      final ownerAccountId =
                                          (o['account_id'] ?? '')
                                              .toString()
                                              .trim();
                                      final ownerPhone =
                                          (o['phone'] ?? '').toString().trim();
                                      final createdAt = (o['created_at'] ?? '')
                                          .toString()
                                          .trim();
                                      final ownerLabel = ownerPhone.isNotEmpty
                                          ? ownerPhone
                                          : (ownerAccountId.isNotEmpty
                                              ? ownerAccountId
                                              : (l.isArabic
                                                  ? 'مالك غير معروف'
                                                  : 'Unknown owner'));
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: const Icon(
                                          Icons.admin_panel_settings_outlined,
                                        ),
                                        title: Text(
                                          ownerLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: createdAt.isEmpty
                                            ? null
                                            : Text(
                                                l.isArabic
                                                    ? 'أضيف: $createdAt'
                                                    : 'Added: $createdAt',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withValues(alpha: .70),
                                                ),
                                              ),
                                        trailing: IconButton(
                                          tooltip: l.isArabic
                                              ? 'إزالة المالك'
                                              : 'Remove owner',
                                          icon: const Icon(
                                            Icons.person_remove_outlined,
                                          ),
                                          onPressed: _writeAccessAllowed
                                              ? () => _removeOwner(o)
                                              : null,
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          if (_loadingMore || _hasMore)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Center(
                                child: _loadingMore
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: _loadMore,
                                        child: Text(
                                          l.isArabic
                                              ? 'تحميل المزيد'
                                              : 'Load more',
                                        ),
                                      ),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: Text(
                                    l.isArabic ? 'تحديث' : 'Refresh',
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _writeAccessAllowed
                                      ? _openOwnerEditor
                                      : null,
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    l.isArabic ? 'إضافة مالك' : 'Add owner',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
