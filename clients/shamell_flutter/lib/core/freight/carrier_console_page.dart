import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
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

  @override
  void initState() {
    super.initState();
    final trimmed =
        (widget.baseUrl ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    _baseUrl = trimmed.isEmpty ? _fallbackBaseUrl : trimmed;
    unawaited(_loadOrgs());
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
    // Role-gate moved to RoleSignupGuard in shamellBuildSignedInHome
    // (main_shell.dart). When the user reaches this page they already
    // hold freight.carrier_admin (or admin/superadmin); first-load
    // failures here are real connectivity / org problems, surfaced via
    // _ErrorPanel below.
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
            tooltip: l.isArabic ? 'السوق' : 'Marketplace',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  _MarketplacePage(baseUrl: widget.baseUrl, org: widget.org),
            )),
            icon: const Icon(Icons.storefront_outlined),
          ),
          IconButton(
            tooltip: l.isArabic ? 'السائقون' : 'Drivers',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  _OrgDriversPage(baseUrl: widget.baseUrl, org: widget.org),
            )),
            icon: const Icon(Icons.people_alt_outlined),
          ),
          IconButton(
            tooltip: l.isArabic ? 'سجل النشاط' : 'Activity log',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  _OrgActivityPage(baseUrl: widget.baseUrl, org: widget.org),
            )),
            icon: const Icon(Icons.history_outlined),
          ),
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

// ──────────────────────── Audit / Activity log ───────────────────

class _AuditEvent {
  final String id;
  final String actorKind; // 'user' | 'system' | 'api'
  final String? actorId;
  final String eventKind; // e.g. 'org_created', 'vehicle_added'
  final String targetKind;
  final String targetId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  _AuditEvent({
    required this.id,
    required this.actorKind,
    required this.actorId,
    required this.eventKind,
    required this.targetKind,
    required this.targetId,
    required this.payload,
    required this.createdAt,
  });

  static _AuditEvent fromJson(Map<String, dynamic> json) => _AuditEvent(
        id: (json['id'] ?? '').toString(),
        actorKind: (json['actor_kind'] ?? '').toString(),
        actorId: json['actor_id']?.toString(),
        eventKind: (json['event_kind'] ?? '').toString(),
        targetKind: (json['target_kind'] ?? '').toString(),
        targetId: (json['target_id'] ?? '').toString(),
        payload: (json['payload'] is Map<String, dynamic>)
            ? (json['payload'] as Map<String, dynamic>)
            : <String, dynamic>{},
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString())
                ?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class _OrgActivityPage extends StatefulWidget {
  final String baseUrl;
  final _OrgEntry org;

  const _OrgActivityPage({required this.baseUrl, required this.org});

  @override
  State<_OrgActivityPage> createState() => _OrgActivityPageState();
}

class _OrgActivityPageState extends State<_OrgActivityPage> {
  bool _loading = true;
  String? _loadError;
  List<_AuditEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<Map<String, String>> _authHeaders() async {
    final base = await shamellSessionHeadersForBaseUrl(widget.baseUrl);
    return {...base, 'Accept': 'application/json'};
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
                '${widget.baseUrl}/v1/freight/orgs/${widget.org.id}/audit'),
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
        _events = parsed
            .whereType<Map<String, dynamic>>()
            .map(_AuditEvent.fromJson)
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

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic
              ? 'سجل النشاط · ${widget.org.name}'
              : 'Activity · ${widget.org.name}',
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
    );
  }

  Widget _buildBody(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return _ErrorPanel(message: _loadError!, onRetry: _load);
    }
    if (_events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_outlined,
                  size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                l.isArabic ? 'لا توجد أحداث بعد' : 'No activity yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l.isArabic
                    ? 'كل تغيير في الشركة يظهر هنا (تعديل المركبات، السائقين، الوثائق، إلخ).'
                    : 'Every mutation on this org lands here (vehicles, drivers, documents, etc.).',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _events.length,
      itemBuilder: (_, i) => _ActivityRow(event: _events[i]),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final _AuditEvent event;

  const _ActivityRow({required this.event});

  String _humanEvent(L10n l) {
    final ar = l.isArabic;
    switch (event.eventKind) {
      case 'org_created':
        return ar ? 'تم إنشاء الشركة' : 'Organization created';
      case 'vehicle_added':
        final plate = event.payload['plate_number'] ?? '';
        return ar
            ? 'أضيفت مركبة ${plate.toString().isEmpty ? '' : '($plate)'}'
            : 'Vehicle added ${plate.toString().isEmpty ? '' : '($plate)'}';
      default:
        return event.eventKind;
    }
  }

  IconData _iconFor() {
    switch (event.targetKind) {
      case 'vehicle':
        return Icons.local_shipping_outlined;
      case 'organization':
        return Icons.business_outlined;
      case 'driver':
        return Icons.person_outline;
      case 'document':
        return Icons.description_outlined;
      default:
        return Icons.bolt_outlined;
    }
  }

  String _timeAgo(L10n l) {
    final delta = DateTime.now().difference(event.createdAt);
    final ar = l.isArabic;
    if (delta.inMinutes < 1) return ar ? 'الآن' : 'just now';
    if (delta.inHours < 1) {
      return ar ? 'منذ ${delta.inMinutes} د' : '${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return ar ? 'منذ ${delta.inHours} س' : '${delta.inHours}h ago';
    }
    if (delta.inDays < 30) {
      return ar ? 'منذ ${delta.inDays} ي' : '${delta.inDays}d ago';
    }
    return '${event.createdAt.year}-${event.createdAt.month.toString().padLeft(2, '0')}-${event.createdAt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final actorLabel = event.actorKind == 'system'
        ? (l.isArabic ? 'النظام' : 'system')
        : (event.actorId != null && event.actorId!.isNotEmpty
            ? event.actorId!.substring(0, event.actorId!.length.clamp(0, 12))
            : event.actorKind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(), color: const Color(0xFF0F766E), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _humanEvent(l),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '$actorLabel · ${_timeAgo(l)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────── Drivers roster ─────────────────────────

class _Driver {
  final String id;
  final String firstName;
  final String lastName;
  final String? countryIso2;
  final String? phone;
  final String? shamellAccountId;
  final List<String> languages;
  final String status;

  _Driver({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.countryIso2,
    required this.phone,
    required this.shamellAccountId,
    required this.languages,
    required this.status,
  });

  String get displayName => '$firstName $lastName'.trim();

  static _Driver fromJson(Map<String, dynamic> json) {
    final langsRaw = json['languages'];
    final langs = langsRaw is List
        ? langsRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return _Driver(
      id: (json['id'] ?? '').toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      countryIso2: json['country_iso2'] as String?,
      phone: json['phone'] as String?,
      shamellAccountId: json['shamell_account_id'] as String?,
      languages: langs,
      status: (json['status'] ?? 'active').toString(),
    );
  }
}

class _OrgDriversPage extends StatefulWidget {
  final String baseUrl;
  final _OrgEntry org;

  const _OrgDriversPage({required this.baseUrl, required this.org});

  @override
  State<_OrgDriversPage> createState() => _OrgDriversPageState();
}

class _OrgDriversPageState extends State<_OrgDriversPage> {
  bool _loading = true;
  String? _loadError;
  List<_Driver> _drivers = const [];

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
                '${widget.baseUrl}/v1/freight/orgs/${widget.org.id}/drivers'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 401) {
        setState(() {
          _loading = false;
          _loadError = 'Sitzung abgelaufen — bitte erneut anmelden.';
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
        _drivers = parsed
            .whereType<Map<String, dynamic>>()
            .map(_Driver.fromJson)
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
    final created = await showModalBottomSheet<_Driver>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _AddDriverSheet(
          baseUrl: widget.baseUrl,
          orgId: widget.org.id,
          authHeaders: _authHeaders,
        ),
      ),
    );
    if (created != null && mounted) {
      setState(() => _drivers = [created, ..._drivers]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic
              ? 'السائقون · ${widget.org.name}'
              : 'Drivers · ${widget.org.name}',
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
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(l.isArabic ? 'إضافة سائق' : 'Add driver'),
            )
          : null,
    );
  }

  Widget _buildBody(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return _ErrorPanel(message: _loadError!, onRetry: _load);
    }
    if (_drivers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_alt_outlined,
                  size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                l.isArabic ? 'لا يوجد سائقون بعد' : 'No drivers yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _canWrite
                    ? (l.isArabic
                        ? 'أضف سائقًا. يمكنه ربط حسابه في SyrChat لاحقًا.'
                        : 'Add a driver. They can link their SyrChat account later.')
                    : (l.isArabic
                        ? 'دورك لا يسمح بالإضافة.'
                        : 'Your role does not allow adding drivers.'),
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
      itemCount: _drivers.length,
      itemBuilder: (_, i) => _DriverCard(driver: _drivers[i]),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final _Driver driver;

  const _DriverCard({required this.driver});

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: Text(
                (driver.firstName.isNotEmpty
                        ? driver.firstName.substring(0, 1)
                        : '?') +
                    (driver.lastName.isNotEmpty
                        ? driver.lastName.substring(0, 1)
                        : ''),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF0F766E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (driver.countryIso2 != null) driver.countryIso2!,
                      if (driver.phone != null) driver.phone!,
                      if (driver.shamellAccountId != null)
                        l.isArabic ? 'مرتبط بـ SyrChat' : 'SyrChat-linked',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.66),
                    ),
                  ),
                ],
              ),
            ),
            _StatusBadge(status: driver.status),
          ],
        ),
      ),
    );
  }
}

class _AddDriverSheet extends StatefulWidget {
  final String baseUrl;
  final String orgId;
  final Future<Map<String, String>> Function() authHeaders;

  const _AddDriverSheet({
    required this.baseUrl,
    required this.orgId,
    required this.authHeaders,
  });

  @override
  State<_AddDriverSheet> createState() => _AddDriverSheetState();
}

class _AddDriverSheetState extends State<_AddDriverSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _country = TextEditingController(text: 'SY');
  final _phone = TextEditingController(text: '+963 ');
  bool _busy = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _country.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final headers = await widget.authHeaders();
      final body = <String, dynamic>{
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        if (_country.text.trim().isNotEmpty)
          'country_iso2': _country.text.trim().toUpperCase(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      };
      final resp = await http
          .post(
            Uri.parse(
                '${widget.baseUrl}/v1/freight/orgs/${widget.orgId}/drivers'),
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
        ));
        return;
      }
      final parsed = json.decode(resp.body) as Map<String, dynamic>;
      Navigator.of(context).pop(_Driver.fromJson(parsed));
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
              l.isArabic ? 'إضافة سائق' : 'Add driver',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _firstName,
                    label: l.isArabic ? 'الاسم الأول' : 'First name',
                    required: true,
                    maxLength: 64,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty || s.length > 64) {
                        return l.isArabic ? '1–64 حرف' : '1–64 characters';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TextField(
                    controller: _lastName,
                    label: l.isArabic ? 'الكنية' : 'Last name',
                    required: true,
                    maxLength: 64,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty || s.length > 64) {
                        return l.isArabic ? '1–64 حرف' : '1–64 characters';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _country,
                    label: l.isArabic ? 'البلد (ISO2)' : 'Country (ISO2)',
                    hint: 'SY',
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _TextField(
                    controller: _phone,
                    label: l.isArabic ? 'الهاتف' : 'Phone',
                    keyboardType: TextInputType.phone,
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

// ──────────────────────── Marketplace (Phase 3) ──────────────────

class _LoadOffer {
  final String id;
  final String orgId;
  final String postedKind;
  final String pickupCountry;
  final String? pickupCity;
  final String deliveryCountry;
  final String? deliveryCity;
  final DateTime? earliestPickupAt;
  final String cargoKind;
  final String? cargoDescription;
  final int? weightKg;
  final bool requiresTemperatureControl;
  final double? temperatureMinC;
  final double? temperatureMaxC;
  final bool requiresAtpCertificate;
  final bool requiresGdpCompliance;
  final bool requiresHaccpCompliance;
  final bool pharmaComplianceMode;
  final String pricingKind;
  final int? priceMinorUnits;
  final String currency;
  final String status;
  final String? notes;
  final String? publicReference;

  _LoadOffer({
    required this.id,
    required this.orgId,
    required this.postedKind,
    required this.pickupCountry,
    required this.pickupCity,
    required this.deliveryCountry,
    required this.deliveryCity,
    required this.earliestPickupAt,
    required this.cargoKind,
    required this.cargoDescription,
    required this.weightKg,
    required this.requiresTemperatureControl,
    required this.temperatureMinC,
    required this.temperatureMaxC,
    required this.requiresAtpCertificate,
    required this.requiresGdpCompliance,
    required this.requiresHaccpCompliance,
    required this.pharmaComplianceMode,
    required this.pricingKind,
    required this.priceMinorUnits,
    required this.currency,
    required this.status,
    required this.notes,
    required this.publicReference,
  });

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static _LoadOffer fromJson(Map<String, dynamic> json) => _LoadOffer(
        id: (json['id'] ?? '').toString(),
        orgId: (json['org_id'] ?? '').toString(),
        postedKind: (json['posted_kind'] ?? 'load_request').toString(),
        pickupCountry: (json['pickup_country_iso2'] ?? '').toString(),
        pickupCity: json['pickup_city'] as String?,
        deliveryCountry: (json['delivery_country_iso2'] ?? '').toString(),
        deliveryCity: json['delivery_city'] as String?,
        earliestPickupAt:
            DateTime.tryParse((json['earliest_pickup_at'] ?? '').toString())
                ?.toLocal(),
        cargoKind: (json['cargo_kind'] ?? 'general').toString(),
        cargoDescription: json['cargo_description'] as String?,
        weightKg: (json['weight_kg'] as num?)?.toInt(),
        requiresTemperatureControl:
            json['requires_temperature_control'] == true,
        temperatureMinC: _asDouble(json['temperature_min_c']),
        temperatureMaxC: _asDouble(json['temperature_max_c']),
        requiresAtpCertificate: json['requires_atp_certificate'] == true,
        requiresGdpCompliance: json['requires_gdp_compliance'] == true,
        requiresHaccpCompliance: json['requires_haccp_compliance'] == true,
        pharmaComplianceMode: json['pharma_compliance_mode'] == true,
        pricingKind: (json['pricing_kind'] ?? 'fixed').toString(),
        priceMinorUnits: (json['price_minor_units'] as num?)?.toInt(),
        currency: (json['currency'] ?? 'SYP').toString(),
        status: (json['status'] ?? 'open').toString(),
        notes: json['notes'] as String?,
        publicReference: json['public_reference'] as String?,
      );
}

class _MarketplacePage extends StatefulWidget {
  final String baseUrl;
  final _OrgEntry org;

  const _MarketplacePage({required this.baseUrl, required this.org});

  @override
  State<_MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<_MarketplacePage> {
  bool _loading = true;
  String? _loadError;
  List<_LoadOffer> _offers = const [];

  String? _pickupFilter;
  String? _deliveryFilter;
  bool _coldOnly = false;
  bool _pharmaOnly = false;

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
      final query = <String, String>{
        if ((_pickupFilter ?? '').isNotEmpty) 'pickup_country': _pickupFilter!,
        if ((_deliveryFilter ?? '').isNotEmpty)
          'delivery_country': _deliveryFilter!,
        if (_coldOnly) 'cold_chain_only': 'true',
        if (_pharmaOnly) 'pharma_only': 'true',
      };
      final uri = Uri.parse('${widget.baseUrl}/v1/freight/load-offers/search')
          .replace(queryParameters: query.isEmpty ? null : query);
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
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
        _offers = parsed
            .whereType<Map<String, dynamic>>()
            .map(_LoadOffer.fromJson)
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

  Future<void> _openPostSheet() async {
    final created = await showModalBottomSheet<_LoadOffer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _PostLoadOfferSheet(
          baseUrl: widget.baseUrl,
          orgId: widget.org.id,
          authHeaders: _authHeaders,
        ),
      ),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10n.of(context).isArabic
            ? 'تم نشر الحمولة (${created.publicReference ?? ''})'
            : 'Load posted (${created.publicReference ?? ''})'),
        backgroundColor: const Color(0xFF0F766E),
      ));
      unawaited(_load());
    }
  }

  /// Public tracking link for a freshly-issued tracking_token. Opens a
  /// dialog with the URL, a QR code (consignees scan from a printed
  /// CMR), and a "Copy" button so the dispatcher can paste it into
  /// chat / WhatsApp. The link itself is the credential — anyone with
  /// it can read the stripped public view at shamell.online/track/.
  Future<void> _showTrackingShareDialog(String token) async {
    final l = L10n.of(context);
    final url = 'https://shamell.online/track/?t=$token';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic
            ? 'مشاركة رابط التتبع'
            : 'Share tracking link'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFF0F766E)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: url,
                  size: 220,
                  backgroundColor: Colors.white,
                  // Medium error correction is the right trade-off for
                  // a screen-scanned URL: the link is short, so a
                  // bigger error-correction overhead would only blow
                  // up the module count without buying real resilience.
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                url,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                l.isArabic
                    ? 'الرابط نفسه هو بيانات الاعتماد — أي شخص يحصل عليه يمكنه رؤية الحالة.'
                    : 'The link itself is the credential — anyone with it can see the status.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(l.isArabic ? 'تم النسخ ✓' : 'Copied ✓'),
                  backgroundColor: const Color(0xFF0F766E),
                  duration: const Duration(seconds: 2),
                ));
              }
            },
            icon: const Icon(Icons.copy),
            label: Text(l.isArabic ? 'نسخ الرابط' : 'Copy link'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(l.isArabic ? 'افتح' : 'Open'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bookOffer(_LoadOffer offer) async {
    final l = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isArabic ? 'تأكيد الحجز' : 'Confirm booking'),
        content: Text(
          l.isArabic
              ? 'سيتم تخصيص هذه الحمولة لشركتك "${widget.org.name}".'
              : 'This load will be assigned to "${widget.org.name}" as carrier.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
            ),
            child: Text(l.isArabic ? 'احجز' : 'Book'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final headers = await _authHeaders();
      final resp = await http
          .post(
            Uri.parse(
                '${widget.baseUrl}/v1/freight/load-offers/${offer.id}/book'),
            headers: headers,
            body: json.encode({'carrier_org_id': widget.org.id}),
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
        ));
        return;
      }
      final parsed = json.decode(resp.body) as Map<String, dynamic>;
      final token = (parsed['tracking_token'] ?? '').toString();
      // After-booking UX: snackbar with "Share" → tracking-link QR
      // dialog (Tier-1 shareable-tracking-link). "Navigate" stays
      // reachable from the offer card; here we lead with Share since
      // the consignee usually needs the link before the carrier needs
      // the route.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic
            ? 'تم الحجز ✓ رمز التتبع: $token'
            : 'Booked ✓ Tracking: $token'),
        backgroundColor: const Color(0xFF0F766E),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          textColor: Colors.white,
          label: l.isArabic ? 'مشاركة' : 'Share',
          onPressed: () => _showTrackingShareDialog(token),
        ),
      ));
      unawaited(_load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'سوق الشحن' : 'Freight marketplace'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l.isArabic ? 'حجوزاتي' : 'My bookings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _OrgBookingsPage(
                baseUrl: widget.baseUrl,
                org: widget.org,
                onShare: _showTrackingShareDialog,
              ),
            )),
            icon: const Icon(Icons.assignment_turned_in_outlined),
          ),
          IconButton(
            tooltip: l.isArabic ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterBar(l),
            const Divider(height: 1),
            Expanded(child: _buildBody(l)),
          ],
        ),
      ),
      floatingActionButton: (_canWrite)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0F766E),
              onPressed: _openPostSheet,
              icon: const Icon(Icons.add),
              label: Text(l.isArabic ? 'نشر حمولة' : 'Post load'),
            )
          : null,
    );
  }

  Widget _buildFilterBar(L10n l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _CountryFilterField(
                  label: l.isArabic ? 'من' : 'From',
                  value: _pickupFilter,
                  onChanged: (v) => setState(() => _pickupFilter = v),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, color: Colors.grey, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: _CountryFilterField(
                  label: l.isArabic ? 'إلى' : 'To',
                  value: _deliveryFilter,
                  onChanged: (v) => setState(() => _deliveryFilter = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                label: Text(l.isArabic ? 'تبريد فقط' : 'Cold chain'),
                avatar: const Icon(Icons.ac_unit, size: 16),
                selected: _coldOnly,
                onSelected: (v) => setState(() => _coldOnly = v),
              ),
              FilterChip(
                label: Text(l.isArabic ? 'دواء فقط' : 'Pharma only'),
                avatar: const Icon(Icons.medication_outlined, size: 16),
                selected: _pharmaOnly,
                onSelected: (v) => setState(() => _pharmaOnly = v),
              ),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.search, size: 16),
                label: Text(l.isArabic ? 'بحث' : 'Search'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return _ErrorPanel(message: _loadError!, onRetry: _load);
    }
    if (_offers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_outlined,
                  size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                l.isArabic ? 'لا توجد حمولات مفتوحة' : 'No open loads',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l.isArabic
                    ? 'جرّب تصفية أخرى أو انشر حمولتك بنفسك بالزر أدناه.'
                    : 'Try a different filter, or post your own load with the button below.',
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
      itemCount: _offers.length,
      itemBuilder: (_, i) {
        final offer = _offers[i];
        final isOwn = offer.orgId == widget.org.id;
        return _OfferCard(
          offer: offer,
          onBook: (isOwn || !_canWrite) ? null : () => _bookOffer(offer),
          ownOrg: isOwn,
        );
      },
    );
  }
}

class _CountryFilterField extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _CountryFilterField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      onChanged: (v) {
        final trimmed = v.trim().toUpperCase();
        onChanged(trimmed.isEmpty ? null : trimmed);
      },
      maxLength: 2,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'SY',
        border: const OutlineInputBorder(),
        isDense: true,
        counterText: '',
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final _LoadOffer offer;
  final VoidCallback? onBook;
  final bool ownOrg;

  const _OfferCard({
    required this.offer,
    required this.onBook,
    required this.ownOrg,
  });

  String _price(L10n l) {
    final cents = offer.priceMinorUnits;
    if (cents == null) return l.isArabic ? 'قابل للتفاوض' : 'Negotiable';
    final units = (cents / 100).toStringAsFixed(0);
    return '$units ${offer.currency}';
  }

  IconData _cargoIcon() {
    switch (offer.cargoKind) {
      case 'pharma':
        return Icons.medication_outlined;
      case 'perishable':
        return Icons.ac_unit;
      case 'dangerous':
        return Icons.warning_amber_rounded;
      case 'liquid':
        return Icons.water_drop_outlined;
      case 'bulk':
        return Icons.inventory_2_outlined;
      default:
        return Icons.inventory_outlined;
    }
  }

  /// Open the offer's pickup → delivery route in Google Maps.
  /// Falls back to a query-only search when the city is missing, so a
  /// country-only lane still produces a useful map. Web: opens a tab.
  /// Mobile: Maps app if installed, otherwise browser.
  Future<void> _openRoute(BuildContext context, _LoadOffer offer) async {
    String fmt(String? city, String country) {
      final c = (city ?? '').trim();
      return c.isEmpty
          ? country
          : '${Uri.encodeComponent(c)},${Uri.encodeComponent(country)}';
    }
    final origin = fmt(offer.pickupCity, offer.pickupCountry);
    final destination = fmt(offer.deliveryCity, offer.deliveryCountry);
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$origin'
      '&destination=$destination'
      '&travelmode=driving',
    );
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10n.of(context).isArabic
            ? 'تعذّر فتح خرائط جوجل'
            : 'Could not open Google Maps'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_cargoIcon(), color: const Color(0xFF0F766E), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${offer.pickupCountry} → ${offer.deliveryCountry}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _price(l),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (offer.pickupCity != null) offer.pickupCity!,
                if (offer.deliveryCity != null) '→ ${offer.deliveryCity!}',
              ].join(' '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _SmallTag(label: offer.cargoKind.toUpperCase()),
                if (offer.weightKg != null)
                  _SmallTag(label: '${offer.weightKg} kg'),
                if (offer.requiresTemperatureControl)
                  _SmallTag(
                    icon: Icons.ac_unit,
                    label: (offer.temperatureMinC != null &&
                            offer.temperatureMaxC != null)
                        ? '${offer.temperatureMinC!.toStringAsFixed(0)}…${offer.temperatureMaxC!.toStringAsFixed(0)}°C'
                        : 'Cold chain',
                    accent: Colors.blue,
                  ),
                if (offer.requiresAtpCertificate)
                  const _SmallTag(label: 'ATP', accent: Colors.indigo),
                if (offer.requiresGdpCompliance)
                  const _SmallTag(label: 'GDP', accent: Colors.indigo),
                if (offer.requiresHaccpCompliance)
                  const _SmallTag(label: 'HACCP', accent: Colors.indigo),
                if (offer.pricingKind == 'instant')
                  const _SmallTag(label: 'INSTANT', accent: Colors.orange),
                if (offer.publicReference != null)
                  _SmallTag(label: '#${offer.publicReference!}'),
              ],
            ),
            if (offer.cargoDescription != null) ...[
              const SizedBox(height: 10),
              Text(
                offer.cargoDescription!,
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // "Navigate" is available on every offer regardless of
                // ownership / role — a viewer or a competitor org can
                // still want to inspect the route before deciding to
                // book. Tap opens Google Maps with origin + dest
                // pre-filled; Maps picks driving mode by default.
                TextButton.icon(
                  onPressed: () => _openRoute(context, offer),
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: Text(l.isArabic ? 'المسار' : 'Route'),
                ),
                const SizedBox(width: 4),
                if (ownOrg)
                  Chip(
                    label: Text(l.isArabic ? 'حمولتك' : 'Your post'),
                    backgroundColor:
                        const Color(0xFF0F766E).withValues(alpha: 0.1),
                  )
                else if (onBook != null)
                  FilledButton.icon(
                    onPressed: onBook,
                    icon: const Icon(Icons.check),
                    label: Text(l.isArabic ? 'احجز الآن' : 'Book now'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? accent;
  const _SmallTag({required this.label, this.icon, this.accent});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? const Color(0xFF0F766E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostLoadOfferSheet extends StatefulWidget {
  final String baseUrl;
  final String orgId;
  final Future<Map<String, String>> Function() authHeaders;

  const _PostLoadOfferSheet({
    required this.baseUrl,
    required this.orgId,
    required this.authHeaders,
  });

  @override
  State<_PostLoadOfferSheet> createState() => _PostLoadOfferSheetState();
}

class _PostLoadOfferSheetState extends State<_PostLoadOfferSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pickupCountry = TextEditingController(text: 'SY');
  final _pickupCity = TextEditingController();
  final _deliveryCountry = TextEditingController();
  final _deliveryCity = TextEditingController();
  final _weight = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  final _tempMin = TextEditingController();
  final _tempMax = TextEditingController();
  String _cargoKind = 'general';
  String _pricingKind = 'fixed';
  bool _atp = false;
  bool _gdp = false;
  bool _haccp = false;
  bool _pharmaMode = false;
  bool _busy = false;

  bool get _showColdFields =>
      _cargoKind == 'perishable' || _cargoKind == 'pharma';

  @override
  void dispose() {
    _pickupCountry.dispose();
    _pickupCity.dispose();
    _deliveryCountry.dispose();
    _deliveryCity.dispose();
    _weight.dispose();
    _price.dispose();
    _notes.dispose();
    _tempMin.dispose();
    _tempMax.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final headers = await widget.authHeaders();
      final body = <String, dynamic>{
        'pickup_country_iso2':
            _pickupCountry.text.trim().toUpperCase(),
        if (_pickupCity.text.trim().isNotEmpty)
          'pickup_city': _pickupCity.text.trim(),
        'delivery_country_iso2':
            _deliveryCountry.text.trim().toUpperCase(),
        if (_deliveryCity.text.trim().isNotEmpty)
          'delivery_city': _deliveryCity.text.trim(),
        'cargo_kind': _cargoKind,
        if (_weight.text.trim().isNotEmpty)
          'weight_kg': int.tryParse(_weight.text.trim()),
        'pricing_kind': _pricingKind,
        if (_price.text.trim().isNotEmpty)
          'price_minor_units':
              ((double.tryParse(_price.text.trim()) ?? 0) * 100).round(),
        'currency': 'SYP',
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      };
      if (_showColdFields || _tempMin.text.isNotEmpty) {
        body['requires_temperature_control'] = true;
        if (_tempMin.text.trim().isNotEmpty) {
          body['temperature_min_c'] = double.tryParse(_tempMin.text.trim());
        }
        if (_tempMax.text.trim().isNotEmpty) {
          body['temperature_max_c'] = double.tryParse(_tempMax.text.trim());
        }
      }
      if (_atp) body['requires_atp_certificate'] = true;
      if (_gdp) body['requires_gdp_compliance'] = true;
      if (_haccp) body['requires_haccp_compliance'] = true;
      if (_pharmaMode) body['pharma_compliance_mode'] = true;

      final resp = await http
          .post(
            Uri.parse(
                '${widget.baseUrl}/v1/freight/orgs/${widget.orgId}/load-offers'),
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
        ));
        return;
      }
      final parsed = json.decode(resp.body) as Map<String, dynamic>;
      Navigator.of(context).pop(_LoadOffer.fromJson(parsed));
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
              l.isArabic ? 'نشر حمولة' : 'Post load',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _pickupCountry,
                    label: l.isArabic ? 'من (ISO2)' : 'From (ISO2)',
                    required: true,
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) =>
                        (v ?? '').trim().length == 2 ? null : '2 letters',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _TextField(
                    controller: _pickupCity,
                    label: l.isArabic ? 'مدينة' : 'City',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _deliveryCountry,
                    label: l.isArabic ? 'إلى (ISO2)' : 'To (ISO2)',
                    required: true,
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) =>
                        (v ?? '').trim().length == 2 ? null : '2 letters',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _TextField(
                    controller: _deliveryCity,
                    label: l.isArabic ? 'مدينة' : 'City',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l.isArabic ? 'نوع الحمولة' : 'Cargo kind',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final kind in [
                  'general',
                  'perishable',
                  'pharma',
                  'dangerous',
                  'liquid',
                  'bulk',
                ])
                  ChoiceChip(
                    label: Text(kind),
                    selected: _cargoKind == kind,
                    onSelected: (sel) {
                      if (sel) setState(() => _cargoKind = kind);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TextField(
                    controller: _weight,
                    label: l.isArabic ? 'الوزن (كغ)' : 'Weight (kg)',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TextField(
                    controller: _price,
                    label: l.isArabic ? 'السعر (ل.س)' : 'Price (SYP)',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            if (_showColdFields) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 4, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.ac_unit,
                            color: Colors.blue, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          l.isArabic
                              ? 'متطلبات سلسلة التبريد'
                              : 'Cold-chain requirements',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _TextField(
                            controller: _tempMin,
                            label: l.isArabic ? 'حد أدنى °م' : 'Min °C',
                            keyboardType: const TextInputType.numberWithOptions(
                                signed: true, decimal: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TextField(
                            controller: _tempMax,
                            label: l.isArabic ? 'حد أعلى °م' : 'Max °C',
                            keyboardType: const TextInputType.numberWithOptions(
                                signed: true, decimal: true),
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        FilterChip(
                          label: const Text('ATP'),
                          selected: _atp,
                          onSelected: (v) => setState(() => _atp = v),
                        ),
                        FilterChip(
                          label: const Text('GDP'),
                          selected: _gdp,
                          onSelected: (v) => setState(() => _gdp = v),
                        ),
                        FilterChip(
                          label: const Text('HACCP'),
                          selected: _haccp,
                          onSelected: (v) => setState(() => _haccp = v),
                        ),
                        if (_cargoKind == 'pharma')
                          FilterChip(
                            label: Text(l.isArabic
                                ? 'وضع صيدلاني صارم'
                                : 'Pharma-strict mode'),
                            selected: _pharmaMode,
                            onSelected: (v) =>
                                setState(() => _pharmaMode = v),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(l.isArabic ? 'نوع التسعير' : 'Pricing',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final kind in ['fixed', 'instant', 'negotiable', 'auction'])
                  ChoiceChip(
                    label: Text(kind),
                    selected: _pricingKind == kind,
                    onSelected: (sel) {
                      if (sel) setState(() => _pricingKind = kind);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _TextField(
              controller: _notes,
              label: l.isArabic ? 'ملاحظات' : 'Notes',
              maxLength: 240,
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
                  : const Icon(Icons.publish),
              label: Text(l.isArabic ? 'نشر' : 'Publish'),
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

// ──────────────────────── My Bookings ────────────────────────────

class _Booking {
  final String id;
  final String loadOfferId;
  final String status;
  final int? priceMinorUnits;
  final String currency;
  final String? trackingToken;
  final DateTime createdAt;
  final DateTime? pickupProofAt;
  final DateTime? deliveryProofAt;

  _Booking({
    required this.id,
    required this.loadOfferId,
    required this.status,
    required this.priceMinorUnits,
    required this.currency,
    required this.trackingToken,
    required this.createdAt,
    required this.pickupProofAt,
    required this.deliveryProofAt,
  });

  static _Booking fromJson(Map<String, dynamic> json) => _Booking(
        id: (json['id'] ?? '').toString(),
        loadOfferId: (json['load_offer_id'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        priceMinorUnits: (json['price_minor_units'] as num?)?.toInt(),
        currency: (json['currency'] ?? 'SYP').toString(),
        trackingToken: json['tracking_token'] as String?,
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString())
                ?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        pickupProofAt:
            DateTime.tryParse((json['pickup_proof_at'] ?? '').toString())
                ?.toLocal(),
        deliveryProofAt:
            DateTime.tryParse((json['delivery_proof_at'] ?? '').toString())
                ?.toLocal(),
      );
}

class _OrgBookingsPage extends StatefulWidget {
  final String baseUrl;
  final _OrgEntry org;
  final Future<void> Function(String token) onShare;

  const _OrgBookingsPage({
    required this.baseUrl,
    required this.org,
    required this.onShare,
  });

  @override
  State<_OrgBookingsPage> createState() => _OrgBookingsPageState();
}

class _OrgBookingsPageState extends State<_OrgBookingsPage> {
  bool _loading = true;
  String? _loadError;
  List<_Booking> _bookings = const [];

  bool get _canWrite =>
      widget.org.role == 'owner' ||
      widget.org.role == 'manager' ||
      widget.org.role == 'dispatcher';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<Map<String, String>> _authHeaders({bool jsonBody = false}) async {
    final base = await shamellSessionHeadersForBaseUrl(widget.baseUrl);
    return {
      ...base,
      'Accept': 'application/json',
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }

  /// Walk a booking forward by one state ('confirmed'→'in_transit',
  /// 'in_transit'→'delivered'). Optionally attaches a proof URI the
  /// dispatcher pasted into the prompt (Foto-POD anchor for the PDF's
  /// Tier-1 row); a blank URI is accepted — the timestamp alone is
  /// enough to advance the booking. Refreshes the list on success.
  Future<void> _transition(_Booking booking, String action) async {
    final l = L10n.of(context);
    final proofUri = await _promptProofUri(action, booking, l);
    if (proofUri == null) return; // user cancelled
    try {
      final headers = await _authHeaders(jsonBody: true);
      final resp = await http
          .post(
            Uri.parse(
                '${widget.baseUrl}/v1/freight/bookings/${booking.id}/$action'),
            headers: headers,
            body: json.encode({
              if (proofUri.isNotEmpty) 'proof_uri': proofUri,
            }),
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
        ));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(action == 'pickup'
            ? (l.isArabic ? 'تم تسجيل الاستلام ✓' : 'Pickup recorded ✓')
            : (l.isArabic ? 'تم تسجيل التسليم ✓' : 'Delivery recorded ✓')),
        backgroundColor: const Color(0xFF047857),
      ));
      unawaited(_load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  Future<String?> _promptProofUri(
    String action,
    _Booking booking,
    L10n l,
  ) async {
    final ctl = TextEditingController();
    final isPickup = action == 'pickup';
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isPickup
              ? (l.isArabic ? 'تأكيد الاستلام' : 'Confirm pickup')
              : (l.isArabic ? 'تأكيد التسليم' : 'Confirm delivery'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPickup
                  ? (l.isArabic
                      ? 'سيتم تحديث حالة الحجز إلى "في الطريق" وستظهر طابع الزمن على رابط التتبع العام.'
                      : 'Booking flips to "in transit" and the timestamp appears on the public tracking page.')
                  : (l.isArabic
                      ? 'سيتم تحديث حالة الحجز إلى "تم التسليم" وستظهر طابع الزمن على رابط التتبع العام.'
                      : 'Booking flips to "delivered" and the timestamp appears on the public tracking page.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctl,
              decoration: InputDecoration(
                labelText: isPickup
                    ? (l.isArabic
                        ? 'رابط صورة الاستلام (اختياري)'
                        : 'Pickup photo URL (optional)')
                    : (l.isArabic
                        ? 'رابط صورة التسليم (اختياري)'
                        : 'Delivery photo URL (optional)'),
                hintText: 'https://…',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLength: 1024,
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            icon: Icon(isPickup
                ? Icons.local_shipping_outlined
                : Icons.check_circle_outline),
            label: Text(isPickup
                ? (l.isArabic ? 'تسجيل الاستلام' : 'Mark picked up')
                : (l.isArabic ? 'تسجيل التسليم' : 'Mark delivered')),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
    return result;
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
                '${widget.baseUrl}/v1/freight/orgs/${widget.org.id}/bookings'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
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
        _bookings = parsed
            .whereType<Map<String, dynamic>>()
            .map(_Booking.fromJson)
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

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic
              ? 'حجوزاتي · ${widget.org.name}'
              : 'My bookings · ${widget.org.name}',
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
    );
  }

  Widget _buildBody(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return _ErrorPanel(message: _loadError!, onRetry: _load);
    }
    if (_bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.assignment_turned_in_outlined,
                  size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                l.isArabic ? 'لا توجد حجوزات بعد' : 'No bookings yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l.isArabic
                    ? 'احجز حمولة من السوق وستظهر هنا.'
                    : 'Book a load from the marketplace and it lands here.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _bookings.length,
      itemBuilder: (_, i) => _BookingCard(
        booking: _bookings[i],
        onShare: widget.onShare,
        onMarkPickedUp: _canWrite ? () => _transition(_bookings[i], 'pickup') : null,
        onMarkDelivered:
            _canWrite ? () => _transition(_bookings[i], 'delivery') : null,
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final _Booking booking;
  final Future<void> Function(String token) onShare;
  final VoidCallback? onMarkPickedUp;
  final VoidCallback? onMarkDelivered;

  const _BookingCard({
    required this.booking,
    required this.onShare,
    required this.onMarkPickedUp,
    required this.onMarkDelivered,
  });

  String _statusLabel(L10n l) {
    final ar = l.isArabic;
    switch (booking.status) {
      case 'pending':     return ar ? 'قيد الانتظار' : 'PENDING';
      case 'confirmed':   return ar ? 'مؤكد'        : 'CONFIRMED';
      case 'in_transit':  return ar ? 'في الطريق'   : 'IN TRANSIT';
      case 'delivered':   return ar ? 'تم التسليم'  : 'DELIVERED';
      case 'cancelled':   return ar ? 'ملغى'        : 'CANCELLED';
      default:            return booking.status.toUpperCase();
    }
  }

  Color _statusColor() {
    switch (booking.status) {
      case 'pending':     return const Color(0xFFEAB308);
      case 'confirmed':   return const Color(0xFF2563EB);
      case 'in_transit':  return const Color(0xFFEA580C);
      case 'delivered':   return const Color(0xFF047857);
      case 'cancelled':   return const Color(0xFFB91C1C);
      default:            return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final color = _statusColor();
    final priceText = booking.priceMinorUnits == null
        ? '—'
        : '${(booking.priceMinorUnits! / 100).toStringAsFixed(0)} ${booking.currency}';
    final hasToken = (booking.trackingToken ?? '').isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: color.withValues(alpha: 0.35),
                      width: 0.7,
                    ),
                  ),
                  child: Text(
                    _statusLabel(l),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  priceText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (hasToken)
              Text(
                '#${booking.trackingToken}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: const Color(0xFF0F766E),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              l.isArabic
                  ? 'تم الحجز ${_relative(l, booking.createdAt)}'
                  : 'Booked ${_relative(l, booking.createdAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (booking.pickupProofAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '✓ ' +
                      (l.isArabic
                          ? 'تم الاستلام ${_relative(l, booking.pickupProofAt!)}'
                          : 'Picked up ${_relative(l, booking.pickupProofAt!)}'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFF047857)),
                ),
              ),
            if (booking.deliveryProofAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '✓ ' +
                      (l.isArabic
                          ? 'تم التسليم ${_relative(l, booking.deliveryProofAt!)}'
                          : 'Delivered ${_relative(l, booking.deliveryProofAt!)}'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFF047857)),
                ),
              ),
            const SizedBox(height: 12),
            // Action row — share tracking + step the booking forward.
            // Status-aware: only the *next* allowed transition is shown.
            //  confirmed   → "Mark picked up"
            //  in_transit  → "Mark delivered"
            //  delivered / cancelled → no transition button
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (hasToken)
                  OutlinedButton.icon(
                    onPressed: () => onShare(booking.trackingToken!),
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: Text(l.isArabic
                        ? 'مشاركة رمز التتبع'
                        : 'Share tracking'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F766E),
                      side: const BorderSide(color: Color(0xFF0F766E)),
                    ),
                  ),
                if (booking.status == 'confirmed' && onMarkPickedUp != null)
                  FilledButton.icon(
                    onPressed: onMarkPickedUp,
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: Text(
                        l.isArabic ? 'تسجيل الاستلام' : 'Mark picked up'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                    ),
                  ),
                if (booking.status == 'in_transit' && onMarkDelivered != null)
                  FilledButton.icon(
                    onPressed: onMarkDelivered,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                        l.isArabic ? 'تسجيل التسليم' : 'Mark delivered'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _relative(L10n l, DateTime when) {
    final delta = DateTime.now().difference(when);
    final ar = l.isArabic;
    if (delta.inMinutes < 1) return ar ? 'الآن' : 'just now';
    if (delta.inHours < 1) {
      return ar ? 'منذ ${delta.inMinutes} د' : '${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return ar ? 'منذ ${delta.inHours} س' : '${delta.inHours}h ago';
    }
    if (delta.inDays < 30) {
      return ar ? 'منذ ${delta.inDays} ي' : '${delta.inDays}d ago';
    }
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}
