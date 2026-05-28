import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../account_privilege_store.dart';
import '../l10n.dart';
import '../role_signup_api.dart';
import '../role_signup_gate.dart';
import '../session_cookie_store.dart';

/// Phase 2.5 Carrier Console.
///
/// On launch the page loads the caller's organizations via
/// `GET /v1/freight/orgs`:
///   - Loading: spinner.
///   - Empty: setup wizard (name + country + optional tax_id + contact).
///     Submit posts to `POST /v1/freight/orgs`; on success we slip the
///     new org into the dashboard view in-place (no second fetch).
///   - Non-empty: dashboard listing each org with role + status badge.
///     A floating-action button reopens the wizard for additional orgs.
///
/// Auth: every request carries the standard Shamell session headers
/// from [shamellSessionHeadersForBaseUrl]. The BFF's `freight_proxy`
/// resolves the session → `X-Shamell-Account-Id` injected upstream;
/// this page only knows the public surface.
///
/// Phase 3 will add Fleet (Vehicles/Trailers/CoolingUnits) + Drivers
/// + Certificates as tabs in this same shell.
const String _fallbackBaseUrl = 'https://api.shamell.online';

class CarrierConsolePage extends StatefulWidget {
  final String? baseUrl;

  const CarrierConsolePage({super.key, this.baseUrl});

  @override
  State<CarrierConsolePage> createState() => _CarrierConsolePageState();
}

class _CarrierConsolePageState extends State<CarrierConsolePage> {
  late final String _baseUrl;
  bool _loading = true;
  String? _loadError;
  List<_OrgEntry> _orgs = const [];
  bool _showWizard = false;
  // Snapshot of the caller's platform roles/permissions. Drives the
  // self-service signup gate: when the user lacks freight.carrier_admin
  // (and isn't a platform superadmin), the gate replaces the org
  // dashboard with a request form. Approval is fronted by the operator
  // console's Signups workspace and lands here via privilege refresh.
  AccountPrivilegeSnapshot _privileges = AccountPrivilegeSnapshot.empty;

  @override
  void initState() {
    super.initState();
    final trimmed =
        (widget.baseUrl ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    _baseUrl = trimmed.isEmpty ? _fallbackBaseUrl : trimmed;
    unawaited(_bootstrap());
  }

  bool get _carrierAccessAllowed =>
      _privileges.isSuperadmin ||
      _privileges.isAdmin ||
      _privileges.roles.contains(RoleSignupRoleIds.carrier);

  Future<void> _bootstrap() async {
    // Load privilege snapshot first so we can decide signup-gate vs.
    // dashboard before the (potentially failing) GET /v1/freight/orgs.
    // The org fetch is gated on _carrierAccessAllowed to avoid lighting
    // up a confusing "Session expired" panel when the real cause is
    // "you don't have the role yet."
    try {
      final snap = await loadAccountPrivilegeSnapshotForBaseUrl(_baseUrl);
      if (!mounted) return;
      setState(() => _privileges = snap);
    } catch (_) {
      // Soft-fail: stale snapshot is fine, the gate will fall back
      // to its "no role" branch which is the safer default.
    }
    if (_carrierAccessAllowed) {
      await _loadOrgs();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshPrivilegesAndReload() async {
    try {
      final snap = await loadAccountPrivilegeSnapshotForBaseUrl(_baseUrl);
      if (!mounted) return;
      setState(() => _privileges = snap);
    } catch (_) {}
    if (_carrierAccessAllowed) {
      await _loadOrgs();
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final base = await shamellSessionHeadersForBaseUrl(_baseUrl);
    return {
      ...base,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _loadOrgs() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final headers = await _authHeaders();
      final resp = await http
          .get(Uri.parse('$_baseUrl/v1/freight/orgs'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 401) {
        setState(() {
          _loading = false;
          _loadError =
              'Sitzung abgelaufen — bitte erneut anmelden.\n(Session expired — please sign in again.)';
        });
        return;
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        setState(() {
          _loading = false;
          _loadError = 'HTTP ${resp.statusCode}\n${resp.body}';
        });
        return;
      }
      final parsed = json.decode(resp.body) as List<dynamic>;
      final orgs = parsed
          .whereType<Map<String, dynamic>>()
          .map(_OrgEntry.fromJson)
          .toList(growable: false);
      setState(() {
        _loading = false;
        _orgs = orgs;
        // First-launch UX: if the caller has no orgs yet, drop them
        // straight into the wizard. They came here to register a
        // company, not to look at an empty list.
        _showWizard = orgs.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<_OrgEntry?> _submitWizard(_OrgDraft draft) async {
    try {
      final headers = await _authHeaders();
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/v1/freight/orgs'),
            headers: headers,
            body: json.encode(draft.toJson()),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return null;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        // Surface backend's `{error,message}` shape verbatim so the
        // user sees the exact reason (e.g. duplicate tax_id).
        String detail;
        try {
          final parsed = json.decode(resp.body) as Map<String, dynamic>;
          detail = (parsed['message'] as String?) ?? resp.body;
        } catch (_) {
          detail = resp.body;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('HTTP ${resp.statusCode} — $detail'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ));
        return null;
      }
      final parsed = json.decode(resp.body) as Map<String, dynamic>;
      return _OrgEntry.fromJson(parsed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'سرتشات شحن (Carrier)' : 'SyrChat Carrier'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : _loadOrgs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(l)),
      floatingActionButton: (!_loading && _orgs.isNotEmpty && !_showWizard)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0F766E),
              onPressed: () => setState(() => _showWizard = true),
              icon: const Icon(Icons.add),
              label:
                  Text(l.isArabic ? 'إضافة شركة' : 'Add organization'),
            )
          : null,
    );
  }

  Widget _buildBody(L10n l) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Self-service signup gate. If the caller doesn't hold the
    // freight.carrier_admin platform role yet, the page is replaced
    // with a request form. The gate polls for status; an admin
    // approval flips _carrierAccessAllowed on the next privilege
    // refresh and the dashboard takes over.
    if (!_carrierAccessAllowed) {
      return RoleSignupGate(
        roleId: RoleSignupRoleIds.carrier,
        roleLabel: 'carrier',
        roleLabelArabic: 'ناقل',
        fields: RoleSignupFormFields.carrier,
        api: RoleSignupApi(baseUrl: _baseUrl),
        isArabic: l.isArabic,
        onSubmitted: () =>
            unawaited(_refreshPrivilegesAndReload()),
      );
    }
    if (_loadError != null) {
      return _ErrorPanel(message: _loadError!, onRetry: _loadOrgs);
    }
    if (_showWizard) {
      return _SetupWizard(
        firstTime: _orgs.isEmpty,
        onSubmit: (draft) async {
          final entry = await _submitWizard(draft);
          if (entry != null) {
            setState(() {
              _orgs = [entry, ..._orgs];
              _showWizard = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(l.isArabic
                  ? 'تم إنشاء "${entry.name}"'
                  : 'Created "${entry.name}"'),
              backgroundColor: const Color(0xFF0F766E),
            ));
          }
        },
        onCancel: _orgs.isEmpty ? null : () => setState(() => _showWizard = false),
      );
    }
    return _Dashboard(orgs: _orgs, baseUrl: _baseUrl);
  }
}

// ──────────────────────── data model ─────────────────────────────

class _OrgEntry {
  final String id;
  final String name;
  final String orgKind;
  final String? taxId;
  final String countryIso2;
  final String? city;
  final String status;
  final String role;

  _OrgEntry({
    required this.id,
    required this.name,
    required this.orgKind,
    required this.taxId,
    required this.countryIso2,
    required this.city,
    required this.status,
    required this.role,
  });

  static _OrgEntry fromJson(Map<String, dynamic> json) => _OrgEntry(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        orgKind: (json['org_kind'] ?? 'carrier').toString(),
        taxId: json['tax_id'] as String?,
        countryIso2: (json['country_iso2'] ?? '').toString(),
        city: json['city'] as String?,
        status: (json['status'] ?? 'draft').toString(),
        role: (json['role'] ?? 'owner').toString(),
      );
}

class _OrgDraft {
  final String name;
  final String countryIso2;
  final String? taxId;
  final String? city;
  final String? phone;
  final String? email;
  final String? legalForm;
  final String orgKind;

  _OrgDraft({
    required this.name,
    required this.countryIso2,
    this.taxId,
    this.city,
    this.phone,
    this.email,
    this.legalForm,
    this.orgKind = 'carrier',
  });

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'name': name,
      'country_iso2': countryIso2,
      'org_kind': orgKind,
    };
    if (taxId != null && taxId!.isNotEmpty) out['tax_id'] = taxId;
    if (city != null && city!.isNotEmpty) out['city'] = city;
    if (phone != null && phone!.isNotEmpty) out['phone'] = phone;
    if (email != null && email!.isNotEmpty) out['email'] = email;
    if (legalForm != null && legalForm!.isNotEmpty) {
      out['legal_form'] = legalForm;
    }
    return out;
  }
}

// ──────────────────────── views ──────────────────────────────────

class _ErrorPanel extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              l.isArabic ? 'تعذّر التحميل' : 'Could not load',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              message,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: Text(l.isArabic ? 'إعادة المحاولة' : 'Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final List<_OrgEntry> orgs;
  final String baseUrl;

  const _Dashboard({required this.orgs, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: orgs.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l.isArabic
                  ? '${orgs.length} شركة مرتبطة بحسابك'
                  : '${orgs.length} organization${orgs.length == 1 ? '' : 's'} linked to your account',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
              ),
            ),
          );
        }
        final entry = orgs[i - 1];
        return _OrgCard(
          entry: entry,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                _OrgVehiclesPage(baseUrl: baseUrl, org: entry),
          )),
        );
      },
    );
  }
}

class _OrgCard extends StatelessWidget {
  final _OrgEntry entry;
  final VoidCallback? onTap;

  const _OrgCard({required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.business_outlined,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${entry.countryIso2}${entry.city != null ? ' · ${entry.city}' : ''} · ${entry.orgKind}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.66),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: entry.status),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    icon: Icons.shield_outlined,
                    label: l.isArabic
                        ? 'الدور: ${entry.role}'
                        : 'Role: ${entry.role}',
                  ),
                  if ((entry.taxId ?? '').isNotEmpty)
                    _Chip(
                      icon: Icons.receipt_long_outlined,
                      label: 'Tax: ${entry.taxId}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'verified' => const Color(0xFF07C160),
      'submitted' || 'in_review' => const Color(0xFFEAB308),
      'rejected' || 'suspended' => const Color(0xFFEF4444),
      _ => const Color(0xFF6B7280),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ──────────────────────── setup wizard ───────────────────────────

class _SetupWizard extends StatefulWidget {
  final bool firstTime;
  final Future<void> Function(_OrgDraft) onSubmit;
  final VoidCallback? onCancel;

  const _SetupWizard({
    required this.firstTime,
    required this.onSubmit,
    this.onCancel,
  });

  @override
  State<_SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<_SetupWizard> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _country = TextEditingController(text: 'SY');
  final _taxId = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _legalForm = TextEditingController();
  String _orgKind = 'carrier';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    _taxId.dispose();
    _city.dispose();
    _phone.dispose();
    _email.dispose();
    _legalForm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_OrgDraft(
        name: _name.text.trim(),
        countryIso2: _country.text.trim().toUpperCase(),
        taxId: _taxId.text.trim().isEmpty ? null : _taxId.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        legalForm:
            _legalForm.text.trim().isEmpty ? null : _legalForm.text.trim(),
        orgKind: _orgKind,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.firstTime) ...[
              Text(
                l.isArabic
                    ? 'مرحباً بك في وحدة الشاحن'
                    : 'Welcome to the Carrier Console',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l.isArabic
                    ? 'لنبدأ بتسجيل شركتك. سيراجع فريق سرتشات الطلب وستتلقى تحديثاً قريباً.'
                    : 'Let\'s register your company. The SyrChat team reviews the submission and notifies you within a business day.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.isArabic ? 'إضافة شركة جديدة' : 'Add a new organization',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.onCancel != null)
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _TextField(
              controller: _name,
              label: l.isArabic ? 'اسم الشركة' : 'Company name',
              required: true,
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.length < 2 || s.length > 200) {
                  return l.isArabic
                      ? 'بين حرفين و200 حرف'
                      : '2–200 characters';
                }
                return null;
              },
            ),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _country,
                    label: l.isArabic ? 'البلد (ISO2)' : 'Country (ISO2)',
                    hint: 'SY',
                    required: true,
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.length != 2) {
                        return l.isArabic
                            ? 'رمز بلد من حرفين'
                            : '2-letter code';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TextField(
                    controller: _city,
                    label: l.isArabic ? 'المدينة' : 'City',
                  ),
                ),
              ],
            ),
            _TextField(
              controller: _taxId,
              label: l.isArabic ? 'الرقم الضريبي (اختياري)' : 'Tax ID (optional)',
            ),
            _TextField(
              controller: _legalForm,
              label:
                  l.isArabic ? 'الشكل القانوني (اختياري)' : 'Legal form (optional)',
              hint: 'GmbH, LLC, ش.ذ.م.م',
            ),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _phone,
                    label: l.isArabic ? 'الهاتف' : 'Phone',
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TextField(
                    controller: _email,
                    label: l.isArabic ? 'البريد' : 'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.isArabic ? 'نوع الشركة' : 'Org kind',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'carrier',
                  label: Text(l.isArabic ? 'شاحن' : 'Carrier'),
                  icon: const Icon(Icons.local_shipping_outlined),
                ),
                ButtonSegment(
                  value: 'shipper',
                  label: Text(l.isArabic ? 'مرسل' : 'Shipper'),
                  icon: const Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment(
                  value: 'both',
                  label: Text(l.isArabic ? 'كلاهما' : 'Both'),
                  icon: const Icon(Icons.compare_arrows),
                ),
              ],
              selected: {_orgKind},
              onSelectionChanged: (s) =>
                  setState(() => _orgKind = s.first),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(
                widget.firstTime
                    ? (l.isArabic
                        ? 'تسجيل الشركة'
                        : 'Register company')
                    : (l.isArabic ? 'إضافة' : 'Add'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool required;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _TextField({
    required this.controller,
    required this.label,
    this.hint,
    this.required = false,
    this.maxLength,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          counterText: '',
        ),
        maxLength: maxLength,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        validator: validator,
      ),
    );
  }
}

// ──────────────────────── Vehicles (Fleet tab) ───────────────────

class _Vehicle {
  final String id;
  final String plateNumber;
  final String vehicleType;
  final int? axleCount;
  final String? vin;
  final String? firstRegisteredAt;
  final String status;

  _Vehicle({
    required this.id,
    required this.plateNumber,
    required this.vehicleType,
    required this.axleCount,
    required this.vin,
    required this.firstRegisteredAt,
    required this.status,
  });

  static _Vehicle fromJson(Map<String, dynamic> json) => _Vehicle(
        id: (json['id'] ?? '').toString(),
        plateNumber: (json['plate_number'] ?? '').toString(),
        vehicleType: (json['vehicle_type'] ?? '').toString(),
        axleCount: (json['axle_count'] as num?)?.toInt(),
        vin: json['vin'] as String?,
        firstRegisteredAt: json['first_registered_at'] as String?,
        status: (json['status'] ?? 'active').toString(),
      );
}

class _OrgVehiclesPage extends StatefulWidget {
  final String baseUrl;
  final _OrgEntry org;

  const _OrgVehiclesPage({required this.baseUrl, required this.org});

  @override
  State<_OrgVehiclesPage> createState() => _OrgVehiclesPageState();
}

class _OrgVehiclesPageState extends State<_OrgVehiclesPage> {
  bool _loading = true;
  String? _loadError;
  List<_Vehicle> _vehicles = const [];

  bool get _canWrite =>
      widget.org.role == 'owner' ||
      widget.org.role == 'manager' ||
      widget.org.role == 'dispatcher';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<Map<String, String>> _authHeaders() async {
    final base = await shamellSessionHeadersForBaseUrl(widget.baseUrl);
    return {
      ...base,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final headers = await _authHeaders();
      final resp = await http
          .get(
            Uri.parse(
                '${widget.baseUrl}/v1/freight/orgs/${widget.org.id}/vehicles'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 401) {
        setState(() {
          _loading = false;
          _loadError =
              'Sitzung abgelaufen — bitte erneut anmelden.\n(Session expired — please sign in again.)';
        });
        return;
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        setState(() {
          _loading = false;
          _loadError = 'HTTP ${resp.statusCode}\n${resp.body}';
        });
        return;
      }
      final parsed = json.decode(resp.body) as List<dynamic>;
      setState(() {
        _loading = false;
        _vehicles = parsed
            .whereType<Map<String, dynamic>>()
            .map(_Vehicle.fromJson)
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _openAddSheet() async {
    final created = await showModalBottomSheet<_Vehicle>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        // SegmentedButton + form needs extra room above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _AddVehicleSheet(
          baseUrl: widget.baseUrl,
          orgId: widget.org.id,
          authHeaders: _authHeaders,
        ),
      ),
    );
    if (created != null && mounted) {
      setState(() => _vehicles = [..._vehicles, created]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic
              ? 'الأسطول · ${widget.org.name}'
              : 'Fleet · ${widget.org.name}',
        ),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(l)),
      floatingActionButton: (_canWrite && !_loading && _loadError == null)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0F766E),
              onPressed: _openAddSheet,
              icon: const Icon(Icons.add),
              label: Text(l.isArabic ? 'إضافة مركبة' : 'Add vehicle'),
            )
          : null,
    );
  }

  Widget _buildBody(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return _ErrorPanel(message: _loadError!, onRetry: _load);
    }
    if (_vehicles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_shipping_outlined,
                  size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                l.isArabic ? 'لا توجد مركبات بعد' : 'No vehicles yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _canWrite
                    ? (l.isArabic
                        ? 'أضف أول لوحة من زر الإضافة في الأسفل.'
                        : 'Add the first plate using the button below.')
                    : (l.isArabic
                        ? 'ليس لديك صلاحية الإضافة.'
                        : 'Your role does not allow adding vehicles.'),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _vehicles.length,
      itemBuilder: (_, i) => _VehicleCard(vehicle: _vehicles[i]),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final _Vehicle vehicle;

  const _VehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final typeLabel = switch (vehicle.vehicleType) {
      'truck_solo' => l.isArabic ? 'شاحنة منفردة' : 'Truck (solo)',
      'truck_trailer_tractor' =>
        l.isArabic ? 'جرّار مع مقطورة' : 'Tractor + trailer',
      'van' => l.isArabic ? 'فان' : 'Van',
      _ => vehicle.vehicleType,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_shipping_outlined,
                  color: Color(0xFF0F766E)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.plateNumber,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      typeLabel,
                      if (vehicle.axleCount != null)
                        '${vehicle.axleCount} ${l.isArabic ? 'محاور' : 'axles'}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.66),
                    ),
                  ),
                ],
              ),
            ),
            _StatusBadge(status: vehicle.status),
          ],
        ),
      ),
    );
  }
}

class _AddVehicleSheet extends StatefulWidget {
  final String baseUrl;
  final String orgId;
  final Future<Map<String, String>> Function() authHeaders;

  const _AddVehicleSheet({
    required this.baseUrl,
    required this.orgId,
    required this.authHeaders,
  });

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _vin = TextEditingController();
  final _axles = TextEditingController();
  String _vehicleType = 'truck_solo';
  bool _busy = false;

  @override
  void dispose() {
    _plate.dispose();
    _vin.dispose();
    _axles.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final headers = await widget.authHeaders();
      final body = <String, dynamic>{
        'plate_number': _plate.text.trim(),
        'vehicle_type': _vehicleType,
      };
      final axlesText = _axles.text.trim();
      if (axlesText.isNotEmpty) {
        body['axle_count'] = int.tryParse(axlesText);
      }
      final vinText = _vin.text.trim();
      if (vinText.isNotEmpty) body['vin'] = vinText;
      final resp = await http
          .post(
            Uri.parse(
                '${widget.baseUrl}/v1/freight/orgs/${widget.orgId}/vehicles'),
            headers: headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String detail;
        try {
          final parsed = json.decode(resp.body) as Map<String, dynamic>;
          detail = (parsed['message'] as String?) ?? resp.body;
        } catch (_) {
          detail = resp.body;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('HTTP ${resp.statusCode} — $detail'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ));
        return;
      }
      final parsed = json.decode(resp.body) as Map<String, dynamic>;
      Navigator.of(context).pop(_Vehicle.fromJson(parsed));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l.isArabic ? 'إضافة مركبة' : 'Add vehicle',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _TextField(
              controller: _plate,
              label: l.isArabic ? 'رقم اللوحة' : 'Plate number',
              required: true,
              maxLength: 32,
              textCapitalization: TextCapitalization.characters,
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty || s.length > 32) {
                  return l.isArabic
                      ? '1–32 حرف'
                      : '1–32 characters';
                }
                return null;
              },
            ),
            Text(
              l.isArabic ? 'نوع المركبة' : 'Vehicle type',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'truck_solo',
                  label: Text(l.isArabic ? 'منفردة' : 'Solo'),
                  icon: const Icon(Icons.local_shipping_outlined),
                ),
                ButtonSegment(
                  value: 'truck_trailer_tractor',
                  label: Text(l.isArabic ? 'جرّار' : 'Tractor'),
                  icon: const Icon(Icons.rv_hookup_outlined),
                ),
                ButtonSegment(
                  value: 'van',
                  label: Text(l.isArabic ? 'فان' : 'Van'),
                  icon: const Icon(Icons.airport_shuttle_outlined),
                ),
              ],
              selected: {_vehicleType},
              onSelectionChanged: (s) =>
                  setState(() => _vehicleType = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _axles,
                    label: l.isArabic
                        ? 'عدد المحاور (اختياري)'
                        : 'Axles (optional)',
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return null;
                      final n = int.tryParse(s);
                      if (n == null || n < 2 || n > 8) {
                        return l.isArabic ? '2–8' : '2–8';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _TextField(
                    controller: _vin,
                    label: 'VIN ${l.isArabic ? '(اختياري)' : '(optional)'}',
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(l.isArabic ? 'حفظ' : 'Save'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
