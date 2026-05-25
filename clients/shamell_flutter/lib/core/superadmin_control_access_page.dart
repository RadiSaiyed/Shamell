import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show LoginPage;

import 'access_platform_contracts.dart';
import 'account_privilege_store.dart';
import 'app_shell_widgets.dart' show AppBG;
import 'base_url.dart';
import 'device_binding_reauth.dart';
import 'http_error.dart';
import 'l10n.dart';
import 'payments/payments_idempotency.dart';
import 'safe_set_state.dart';
import 'session_cookie_store.dart';
import 'shamell_loading_shimmer.dart';

const List<String> shamellControlGrantableRoleIds = <String>[
  'platform.ops_manager',
  'platform.admin',
  'owner.daily_admin',
];

bool isValidShamellControlAdminAccountId(String raw) {
  final value = raw.trim();
  return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
}

bool isValidShamellControlAdminPhoneE164(String raw) {
  final value = raw.trim();
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value);
}

String normalizeShamellControlAdminAccountId(String raw) =>
    raw.trim().toLowerCase();

String normalizeShamellControlAdminPhone(String raw) => raw.trim();

@visibleForTesting
bool shamellControlSensitiveRevealStillValid(
  DateTime? unlockedUntil, {
  DateTime? now,
}) {
  if (unlockedUntil == null) {
    return false;
  }
  final reference = (now ?? DateTime.now()).toUtc();
  return unlockedUntil.isAfter(reference);
}

@visibleForTesting
bool shamellControlPlatformRequiresSensitiveLocalAuth({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  if (isWeb) {
    return false;
  }
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return false;
  }
}

class SuperadminControlAccessPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? httpClient;
  final Future<bool> Function()? sensitiveRevealOverride;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;

  const SuperadminControlAccessPage({
    super.key,
    required this.baseUrl,
    this.httpClient,
    this.sensitiveRevealOverride,
    this.privilegeSnapshotOverride,
  });

  @override
  State<SuperadminControlAccessPage> createState() =>
      _SuperadminControlAccessPageState();
}

class _SuperadminControlAccessPageState
    extends State<SuperadminControlAccessPage>
    with SafeSetStateMixin<SuperadminControlAccessPage> {
  static const Duration _requestTimeout = Duration(seconds: 15);

  late final http.Client _http;
  late final bool _ownsHttpClient;
  final TextEditingController _identifierCtrl = TextEditingController();

  bool _usePhone = true;
  bool _loadingPrivileges = true;
  bool _loading = false;
  bool _mutating = false;
  bool _readAllowed = false;
  bool _writeAllowed = false;
  String _selectedRoleId = shamellControlGrantableRoleIds.first;
  String _status = '';
  List<Map<String, dynamic>> _assignments = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? shamellHttpClient();
    _loadPrivileges();
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Uri? _assignmentsUri({Map<String, String>? queryParameters}) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: const <String>['admin', 'access', 'assignments'],
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage({bool? isArabic}) {
    final arabic = isArabic ?? L10n.of(context).isArabic;
    return arabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
  }

  Future<void> _loadPrivileges() async {
    final snapshot = widget.privilegeSnapshotOverride ??
        await loadAccountPrivilegeSnapshotForBaseUrl(widget.baseUrl);
    if (!mounted) return;
    setState(() {
      _readAllowed = shamellHasControlAccessAssignmentReadSnapshotAccess(
        snapshot,
      );
      _writeAllowed = shamellHasControlAccessAssignmentWriteSnapshotAccess(
        snapshot,
      );
      _loadingPrivileges = false;
    });
  }

  Future<Map<String, String>> _headers({
    bool jsonBody = false,
    String? idempotencyPrefix,
  }) async {
    final extra = <String, String>{};
    if (idempotencyPrefix != null && idempotencyPrefix.trim().isNotEmpty) {
      extra['idempotency-key'] = newPaymentsIdempotencyKey(idempotencyPrefix);
    }
    return shamellSessionHeadersForBaseUrl(
      widget.baseUrl,
      json: jsonBody,
      extra: extra.isEmpty ? null : extra,
    );
  }

  Future<bool> _requireSensitiveReveal() async {
    return true;
  }

  String? _validatedIdentifier() {
    final raw = _identifierCtrl.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    if (_usePhone) {
      if (!isValidShamellControlAdminPhoneE164(raw)) {
        return null;
      }
      return normalizeShamellControlAdminPhone(raw);
    }
    if (!isValidShamellControlAdminAccountId(raw)) {
      return null;
    }
    return normalizeShamellControlAdminAccountId(raw);
  }

  String _identifierValidationMessage(L10n l) {
    if (_usePhone) {
      return l.isArabic
          ? 'أدخل رقم هاتف بصيغة E.164 مثل +963...'
          : 'Enter a phone number in E.164 format such as +963...';
    }
    return l.isArabic
        ? 'أدخل account_id مكوّنًا من 64 خانة hex.'
        : 'Enter a 64-character hex account_id.';
  }

  Map<String, String> _subjectQuery(String identifier) {
    return _usePhone
        ? <String, String>{'phone': identifier, 'limit': '200'}
        : <String, String>{'account_id': identifier, 'limit': '200'};
  }

  Map<String, dynamic> _subjectBody(String identifier) {
    return _usePhone
        ? <String, dynamic>{'phone': identifier, 'role_id': _selectedRoleId}
        : <String, dynamic>{
            'account_id': identifier,
            'role_id': _selectedRoleId,
          };
  }

  String? _normalizeControlRoleId(Map<String, dynamic> item) {
    final roleId = (item['role_id'] ?? '').toString().trim().toLowerCase();
    if (shamellControlGrantableRoleIds.contains(roleId)) {
      return roleId;
    }
    final legacyRole =
        (item['legacy_role'] ?? '').toString().trim().toLowerCase();
    switch (legacyRole) {
      case 'ops':
        return 'platform.ops_manager';
      case 'admin':
        return 'platform.admin';
      case 'superadmin':
        return 'owner.daily_admin';
      default:
        return null;
    }
  }

  List<String> _roleIds(List<Map<String, dynamic>> assignments) {
    final out = <String>[];
    for (final item in assignments) {
      final roleId = _normalizeControlRoleId(item);
      if (roleId == null || out.contains(roleId)) {
        continue;
      }
      out.add(roleId);
    }
    out.sort();
    return out;
  }

  String _roleLabel(BuildContext context, String roleId) {
    final arabic = L10n.of(context).isArabic;
    switch (roleId) {
      case 'platform.ops_manager':
        return arabic ? 'تشغيل Control' : 'Control ops';
      case 'platform.admin':
        return arabic ? 'إدارة Control' : 'Control admin';
      case 'owner.daily_admin':
        return arabic ? 'مالك يومي' : 'Daily owner';
      default:
        return roleId;
    }
  }

  String _roleDescription(BuildContext context, String roleId) {
    final arabic = L10n.of(context).isArabic;
    switch (roleId) {
      case 'platform.ops_manager':
        return arabic
            ? 'يدخل لوحة SyrChat Control التشغيلية.'
            : 'Access to the SyrChat Control operations board.';
      case 'platform.admin':
        return arabic
            ? 'يدخل لوحة الإدارة مع أدوات أوسع من دور ops.'
            : 'Access to the admin console with broader permissions than ops.';
      case 'owner.daily_admin':
        return arabic
            ? 'يمكنه منح وسحب أدوار admin و superadmin.'
            : 'Can grant and revoke admin and superadmin roles.';
      default:
        return roleId;
    }
  }

  Future<void> _loadAssignments() async {
    final l = L10n.of(context);
    final identifier = _validatedIdentifier();
    if (identifier == null) {
      setState(() {
        _status = _identifierValidationMessage(l);
        _assignments = const <Map<String, dynamic>>[];
      });
      return;
    }
    final uri = _assignmentsUri(queryParameters: _subjectQuery(identifier));
    if (uri == null) {
      setState(() {
        _status = _invalidServerUrlMessage(isArabic: l.isArabic);
        _assignments = const <Map<String, dynamic>>[];
      });
      return;
    }
    setState(() {
      _loading = true;
      _status = '';
    });
    try {
      final response = await _http
          .get(uri, headers: await _headers())
          .timeout(_requestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: response.statusCode,
        rawBody: response.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _assignments = const <Map<String, dynamic>>[];
          _status = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(response.body);
      final assignments = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['assignments'] is List) {
        for (final item in decoded['assignments'] as List) {
          if (item is Map) {
            assignments.add(item.cast<String, dynamic>());
          }
        }
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            assignments.add(item.cast<String, dynamic>());
          }
        }
      }
      if (!mounted) return;
      final roleNames = _roleIds(assignments);
      setState(() {
        _loading = false;
        _assignments = assignments;
        _status = roleNames.isEmpty
            ? (l.isArabic
                ? 'لا توجد أدوار حالية لهذه الهوية بعد.'
                : 'No current roles for this identity yet.')
            : (l.isArabic
                ? 'تم تحميل الأدوار الحالية.'
                : 'Loaded current roles.');
      });
    } catch (error) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: error,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = sanitizeExceptionForUi(error: error, isArabic: l.isArabic);
      });
    }
  }

  Future<void> _mutateRole({required bool add}) async {
    final l = L10n.of(context);
    final identifier = _validatedIdentifier();
    if (identifier == null) {
      setState(() {
        _status = _identifierValidationMessage(l);
      });
      return;
    }
    final approvedReveal = await _requireSensitiveReveal();
    if (!approvedReveal) {
      return;
    }
    final uri = _assignmentsUri();
    if (uri == null) {
      setState(() {
        _status = _invalidServerUrlMessage(isArabic: l.isArabic);
      });
      return;
    }
    setState(() {
      _mutating = true;
      _status = '';
    });
    try {
      final response = await (add
              ? _http.post(
                  uri,
                  headers: await _headers(
                    jsonBody: true,
                    idempotencyPrefix: 'control-role-add',
                  ),
                  body: jsonEncode(_subjectBody(identifier)),
                )
              : _http.delete(
                  uri,
                  headers: await _headers(
                    jsonBody: true,
                    idempotencyPrefix: 'control-role-remove',
                  ),
                  body: jsonEncode(_subjectBody(identifier)),
                ))
          .timeout(_requestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: response.statusCode,
        rawBody: response.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _mutating = false;
          _status = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _mutating = false;
        _status = add
            ? (l.isArabic ? 'تم منح الدور.' : 'Role granted.')
            : (l.isArabic ? 'تم سحب الدور.' : 'Role removed.');
      });
      await _loadAssignments();
    } catch (error) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: error,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _mutating = false;
        _status = sanitizeExceptionForUi(error: error, isArabic: l.isArabic);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final roleIds = _roleIds(_assignments);
    final hasSelectedRole = roleIds.contains(_selectedRoleId);
    final identifierHint = _usePhone
        ? (l.isArabic ? '+9639...' : '+9639...')
        : '64-char account_id';

    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'صلاحيات SyrChat Control' : 'SyrChat Control access',
          ),
        ),
        body: const ShamellSkeletonList(itemCount: 6),
      );
    }

    if (!_readAllowed) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'صلاحيات SyrChat Control' : 'SyrChat Control access',
          ),
        ),
        body: AppBG(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    l.isArabic
                        ? 'هذا الحساب غير مخوّل لإدارة وصول SyrChat Control.'
                        : 'Your account is not allowed to manage SyrChat Control access.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
          l.isArabic ? 'صلاحيات SyrChat Control' : 'SyrChat Control access',
        ),
      ),
      body: AppBG(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic
                            ? 'أنشئ أو حدّث وصول Admin لتطبيق SyrChat Control'
                            : 'Create or update admin access for SyrChat Control',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.isArabic
                            ? 'يمكنك منح الدور عبر phone أو account_id. إذا لم يكن للحساب أدوار بعد، يمكنك منحها مسبقًا وسيظهر الوصول عند تسجيل الدخول.'
                            : 'Grant access by phone or account_id. If the target has no roles yet, you can pre-provision access and it will appear after sign-in.',
                        style: theme.textTheme.bodyMedium,
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
                        l.isArabic ? 'هوية الهدف' : 'Target identity',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: <ButtonSegment<bool>>[
                          ButtonSegment<bool>(
                            value: true,
                            label: Text(l.isArabic ? 'هاتف' : 'Phone'),
                            icon: const Icon(Icons.phone_outlined),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: const Text('account_id'),
                            icon: const Icon(Icons.fingerprint),
                          ),
                        ],
                        selected: <bool>{_usePhone},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _usePhone = selection.first;
                            _assignments = const <Map<String, dynamic>>[];
                            _status = '';
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _identifierCtrl,
                        autofillHints: _usePhone
                            ? const <String>[AutofillHints.telephoneNumber]
                            : null,
                        keyboardType: _usePhone
                            ? TextInputType.phone
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: _usePhone ? 'Phone (E.164)' : 'account_id',
                          hintText: identifierHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _loading || _mutating
                                  ? null
                                  : _loadAssignments,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.search),
                              label: Text(
                                l.isArabic
                                    ? 'تحميل الأدوار الحالية'
                                    : 'Load current roles',
                              ),
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
                        l.isArabic ? 'إدارة الدور' : 'Role mutation',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRoleId,
                        decoration: InputDecoration(
                          labelText: l.isArabic ? 'الدور' : 'Role',
                          border: const OutlineInputBorder(),
                        ),
                        items: shamellControlGrantableRoleIds
                            .map(
                              (roleId) => DropdownMenuItem<String>(
                                value: roleId,
                                child: Text(_roleLabel(context, roleId)),
                              ),
                            )
                            .toList(),
                        onChanged: _mutating
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedRoleId = value;
                                });
                              },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _roleDescription(context, _selectedRoleId),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .76),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _mutating || !_writeAllowed
                                ? null
                                : () => _mutateRole(add: true),
                            icon: _mutating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1),
                            label: Text(
                              l.isArabic ? 'منح الدور' : 'Grant role',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                _mutating || !_writeAllowed || !hasSelectedRole
                                    ? null
                                    : () => _mutateRole(add: false),
                            icon: const Icon(Icons.person_remove_outlined),
                            label: Text(
                              l.isArabic ? 'سحب الدور' : 'Remove role',
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
                        l.isArabic ? 'الأدوار الحالية' : 'Current roles',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (roleIds.isEmpty)
                        Text(
                          l.isArabic
                              ? 'لا توجد أدوار حالية لهذه الهوية.'
                              : 'No current roles for this identity.',
                          style: theme.textTheme.bodyMedium,
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: roleIds
                              .map(
                                (roleId) => Chip(
                                  label: Text(_roleLabel(context, roleId)),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ),
              if (_status.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_status),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
