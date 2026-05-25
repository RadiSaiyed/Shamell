import 'package:flutter/material.dart';

import '../l10n.dart';
import 'access_admin_api.dart';
import 'syrcom_theme.dart';
import 'workforce_snapshot.dart';

/// Self-service access administration for SyrCom.
///
/// Reachable only when the caller's workforce snapshot grants
/// `access.assignment.write` — the Workbench gates the tile on that
/// permission. The page itself defers all authorization to the server;
/// hiding the tile is defense-in-depth, not the primary gate.
///
/// Subject resolution uses the deterministic dev IdP derivation
/// (`deriveDevWorkforceAccountIdForEmail`), so this page is only useful
/// against a dev BFF where workforce accounts are provisioned via the
/// HMAC sign-in path. Once Cloudflare Access / ZITADEL land, a real
/// member-list endpoint replaces the email-to-id helper.
class SyrComAccessAdminPage extends StatefulWidget {
  const SyrComAccessAdminPage({
    super.key,
    required this.baseUrl,
    this.api,
    this.callerSnapshot,
  });

  final String baseUrl;
  final AccessAdminApi? api;
  final WorkforceAccessSnapshot? callerSnapshot;

  @override
  State<SyrComAccessAdminPage> createState() => _SyrComAccessAdminPageState();
}

class _SyrComAccessAdminPageState extends State<SyrComAccessAdminPage> {
  final TextEditingController _emailCtrl = TextEditingController();
  String _selectedRole = kSyrComAdminCanonicalRoles.first;
  bool _useOrgScope = false;
  bool _busy = false;
  String? _lastBanner;
  bool _lastBannerError = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  AccessAdminApi _api() {
    return widget.api ?? AccessAdminApi(baseUrl: widget.baseUrl);
  }

  String _primaryOrgId() {
    final snap = widget.callerSnapshot;
    if (snap == null) return 'org_shamell_internal';
    final primaries = snap.organizations
        .where((m) => m.isPrimary && m.status == 'active')
        .toList();
    if (primaries.isEmpty) return 'org_shamell_internal';
    return primaries.first.organizationId;
  }

  Future<void> _runMutation({required bool grant}) async {
    final isArabic = L10n.of(context).isArabic;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _lastBanner = isArabic
            ? 'بريد إلكتروني غير صالح'
            : 'Enter a valid email';
        _lastBannerError = true;
      });
      return;
    }
    final wfaId = deriveDevWorkforceAccountIdForEmail(email);
    setState(() {
      _busy = true;
      _lastBanner = null;
      _lastBannerError = false;
    });
    final api = _api();
    final result = grant
        ? await api.grantWorkforceRole(
            workforceAccountId: wfaId,
            roleId: _selectedRole,
            organizationId: _useOrgScope ? _primaryOrgId() : null,
          )
        : await api.revokeWorkforceRole(
            workforceAccountId: wfaId,
            roleId: _selectedRole,
            organizationId: _useOrgScope ? _primaryOrgId() : null,
          );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastBannerError = !result.ok;
      if (result.ok) {
        final verb = grant
            ? (isArabic ? 'مُنحت' : 'Granted')
            : (isArabic ? 'سُحبت' : 'Revoked');
        _lastBanner =
            '$verb $_selectedRole → ${email.trim().toLowerCase()}';
      } else {
        _lastBanner = result.error ??
            (isArabic
                ? 'فشل التحديث (HTTP ${result.statusCode})'
                : 'Mutation failed (HTTP ${result.statusCode})');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    final isDark = theme.brightness == Brightness.dark;
    final orgId = _primaryOrgId();

    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'إدارة الصلاحيات' : 'Access Admin'),
        backgroundColor: kSyrComPrimary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: isArabic ? 'الموضوع' : 'Subject',
              hint: isArabic
                  ? 'البريد الإلكتروني للمستخدم العامل المراد منحه/سحبه دوراً'
                  : 'Workforce email to grant or revoke a role for',
            ),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: isArabic ? 'البريد الإلكتروني' : 'Email',
                hintText: 'alice@shamell.test',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1A1F27)
                    : const Color(0xFFF7F8FA),
              ),
            ),
            const SizedBox(height: 18),
            _SectionHeader(
              title: isArabic ? 'الدور' : 'Role',
              hint: isArabic
                  ? 'مأخوذ من فهرس الأدوار المعتمد على الخادم'
                  : 'From the server-canonical role catalog',
            ),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1A1F27)
                    : const Color(0xFFF7F8FA),
              ),
              items: kSyrComAdminCanonicalRoles
                  .map((role) => DropdownMenuItem<String>(
                        value: role,
                        child: Text(role),
                      ))
                  .toList(growable: false),
              onChanged: (v) {
                if (v != null) setState(() => _selectedRole = v);
              },
            ),
            const SizedBox(height: 18),
            _SectionHeader(
              title: isArabic ? 'النطاق' : 'Scope',
              hint: isArabic
                  ? 'منصة (بدون قيد) أو منظمة (مقيّد بـ $orgId)'
                  : 'Platform (unscoped) or Organization (scoped to $orgId)',
            ),
            SwitchListTile(
              value: _useOrgScope,
              onChanged: (v) => setState(() => _useOrgScope = v),
              title: Text(
                _useOrgScope
                    ? (isArabic
                        ? 'نطاق المنظمة: $orgId'
                        : 'Organization scope: $orgId')
                    : (isArabic ? 'نطاق المنصة' : 'Platform scope'),
              ),
              activeThumbColor: kSyrComPrimary,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kSyrComPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _busy ? null : () => _runMutation(grant: true),
                    icon: const Icon(Icons.add),
                    label: Text(isArabic ? 'منح الدور' : 'Grant role'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kSyrComPrimary,
                      side: const BorderSide(color: kSyrComPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _busy ? null : () => _runMutation(grant: false),
                    icon: const Icon(Icons.remove),
                    label: Text(isArabic ? 'سحب الدور' : 'Revoke role'),
                  ),
                ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(kSyrComPrimary),
                    ),
                  ),
                ),
              ),
            if (_lastBanner != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_lastBannerError
                            ? theme.colorScheme.error
                            : kSyrComPrimary)
                        .withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_lastBannerError
                              ? theme.colorScheme.error
                              : kSyrComPrimary)
                          .withValues(alpha: .35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _lastBannerError
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: _lastBannerError
                            ? theme.colorScheme.error
                            : kSyrComPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lastBanner!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _lastBannerError
                                ? theme.colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              isArabic
                  ? 'ملاحظة: تستخدم هذه الواجهة الاشتقاق الحتمي لمعرّف المستخدم العامل من البريد الإلكتروني، وهو صالح فقط للمستخدمين المُسجّلين عبر تسجيل دخول المطوّر. الإصدارات الإنتاجية ستستبدل ذلك بنقطة نهاية أعضاء حقيقية.'
                  : 'Note: this UI derives workforce_account_id deterministically from the email, which only matches users provisioned via dev sign-in. Production builds will swap this for a real member-list endpoint.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .60),
            ),
          ),
        ],
      ),
    );
  }
}
