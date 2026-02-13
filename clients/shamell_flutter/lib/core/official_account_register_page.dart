import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'http_error.dart';
import 'l10n.dart';

class OfficialAccountRegisterPage extends StatefulWidget {
  final String baseUrl;

  const OfficialAccountRegisterPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<OfficialAccountRegisterPage> createState() =>
      _OfficialAccountRegisterPageState();
}

class _OfficialAccountRegisterPageState
    extends State<OfficialAccountRegisterPage> {
  final _accountIdCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _nameArCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _openingHoursCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _miniAppIdCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  String _kind = 'service';
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _requests = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _prefillContact();
    _loadRequests();
  }

  @override
  void dispose() {
    _accountIdCtrl.dispose();
    _nameEnCtrl.dispose();
    _nameArCtrl.dispose();
    _cityCtrl.dispose();
    _categoryCtrl.dispose();
    _addressCtrl.dispose();
    _openingHoursCtrl.dispose();
    _websiteCtrl.dispose();
    _miniAppIdCtrl.dispose();
    _ownerNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _contactEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillContact() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final phone = sp.getString('phone') ?? '';
      if (!mounted || phone.trim().isEmpty) return;
      setState(() {
        _contactPhoneCtrl.text = phone.trim();
      });
    } catch (_) {}
  }

  Future<Map<String, String>> _hdr() async {
    final headers = <String, String>{'content-type': 'application/json'};
    try {
      final cookie = await getSessionCookie() ?? '';
      if (cookie.isNotEmpty) {
        headers['sa_cookie'] = cookie;
      }
    } catch (_) {}
    return headers;
  }

  Future<void> _loadRequests() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/official_account_requests');
      final resp = await http.get(uri, headers: await _hdr());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(resp.body);
      if (!mounted) return;
      if (decoded is Map && decoded['requests'] is List) {
        final list = <Map<String, dynamic>>[];
        for (final item in (decoded['requests'] as List)) {
          if (item is Map<String, dynamic>) {
            list.add(item);
          }
        }
        setState(() {
          _requests = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    final l = L10n.of(context);
    final accountId = _accountIdCtrl.text.trim();
    final nameEn = _nameEnCtrl.text.trim();
    if (accountId.isEmpty || nameEn.isEmpty) {
      setState(() {
        _error = l.isArabic
            ? 'معرّف الحساب والاسم (EN) مطلوبان.'
            : 'Account ID and English name are required.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/official_accounts/self_register');
      final payload = <String, Object?>{
        'account_id': accountId,
        'kind': _kind,
        'name': nameEn,
        'name_ar':
            _nameArCtrl.text.trim().isEmpty ? null : _nameArCtrl.text.trim(),
        'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'category': _categoryCtrl.text.trim().isEmpty
            ? null
            : _categoryCtrl.text.trim(),
        'address':
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'opening_hours': _openingHoursCtrl.text.trim().isEmpty
            ? null
            : _openingHoursCtrl.text.trim(),
        'website_url':
            _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
        'mini_app_id': _miniAppIdCtrl.text.trim().isEmpty
            ? null
            : _miniAppIdCtrl.text.trim(),
        'owner_name': _ownerNameCtrl.text.trim().isEmpty
            ? null
            : _ownerNameCtrl.text.trim(),
        'contact_phone': _contactPhoneCtrl.text.trim().isEmpty
            ? null
            : _contactPhoneCtrl.text.trim(),
        'contact_email': _contactEmailCtrl.text.trim().isEmpty
            ? null
            : _contactEmailCtrl.text.trim(),
      };
      final resp = await http.post(
        uri,
        headers: await _hdr(),
        body: jsonEncode(payload),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final msg = sanitizeHttpError(
          statusCode: resp.statusCode,
          rawBody: resp.body,
          isArabic: l.isArabic,
        );
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = msg;
        });
        return;
      }
      await _loadRequests();
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تم إرسال طلب الحساب الرسمي للمراجعة.'
                : 'Official account request submitted for review.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l.isArabic ? 'تعذّر إرسال الطلب.' : 'Could not submit request.';
      });
    }
  }

  Future<void> _setDefaultOfficial(String id, String name) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('official.default_account_id', id);
      await sp.setString('official.default_account_name', name);
      if (!mounted) return;
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تم ربط هذا الحساب كمركز الحساب الرسمي في قسم "أنا".'
                : 'Linked this account as your default Official account in the Me tab.',
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'تسجيل حساب رسمي' : 'Register official account',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic
                    ? 'أنشئ حساباً رسمياً لخدمتك أو متجرك على نمط Shamell. يبدأ الطلب كمعلومة قيد المراجعة من فريق Shamell.'
                    : 'Create a Shamell‑style Official account for your service or shop. The request starts under review by the Shamell team.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .80),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accountIdCtrl,
                decoration: InputDecoration(
                  labelText: isArabic ? 'معرّف الحساب' : 'Account ID',
                  helperText: isArabic
                      ? 'أحرف صغيرة، أرقام، "_" و "-". مثال: bus_official'
                      : 'Lowercase letters, digits, "_" and "-". Example: bus_official',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameEnCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'اسم الحساب (إنجليزي)'
                      : 'Account name (English)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameArCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'اسم الحساب (عربي، اختياري)'
                      : 'Account name (Arabic, optional)',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isArabic ? 'نوع الحساب' : 'Account kind',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(isArabic ? 'خدمة' : 'Service account'),
                    selected: _kind == 'service',
                    onSelected: (_) {
                      setState(() {
                        _kind = 'service';
                      });
                    },
                  ),
                  ChoiceChip(
                    label: Text(isArabic ? 'اشتراك' : 'Subscription account'),
                    selected: _kind == 'subscription',
                    onSelected: (_) {
                      setState(() {
                        _kind = 'subscription';
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cityCtrl,
                decoration: InputDecoration(
                  labelText: isArabic ? 'المدينة (اختياري)' : 'City (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _categoryCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'الفئة (مثال: النقل، المدفوعات)'
                      : 'Category (e.g. transport, payments)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                  labelText:
                      isArabic ? 'العنوان (اختياري)' : 'Address (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _openingHoursCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'ساعات العمل (اختياري)'
                      : 'Opening hours (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _websiteCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'موقع الويب (اختياري)'
                      : 'Website URL (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _miniAppIdCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'معرّف التطبيق المصغر المرتبط (اختياري)'
                      : 'Linked mini‑app ID (optional)',
                  helperText: isArabic
                      ? 'مثال: bus، payments'
                      : 'Example: bus, payments',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ownerNameCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'اسم المالك/الشركة (اختياري)'
                      : 'Owner / company name (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contactPhoneCtrl,
                decoration: InputDecoration(
                  labelText: isArabic ? 'هاتف الاتصال' : 'Contact phone',
                  helperText: isArabic
                      ? 'يُستخدم للتواصل والتحقق من الحساب الرسمي.'
                      : 'Used to contact you and verify the Official account.',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contactEmailCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'بريد إلكتروني (اختياري)'
                      : 'Contact email (optional)',
                ),
              ),
              if (_error != null && _error!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
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
                    isArabic
                        ? 'إرسال طلب الحساب الرسمي'
                        : 'Submit Official account request',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_requests.isNotEmpty) ...[
                Text(
                  isArabic
                      ? 'طلباتي الحالية للحسابات الرسمية'
                      : 'My Official account requests',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                ..._requests.map((r) {
                  final id = (r['account_id'] ?? '').toString();
                  final name = (r['name'] ?? '').toString();
                  final kind = (r['kind'] ?? '').toString();
                  final status = (r['status'] ?? '').toString();
                  final createdAt = (r['created_at'] ?? '').toString();
                  final title = name.isNotEmpty ? '$id · $name' : id;
                  final isApproved = status.toLowerCase() == 'approved';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      title,
                      style: theme.textTheme.bodySmall,
                    ),
                    subtitle: Text(
                      createdAt.isNotEmpty ? '$kind · $createdAt' : kind,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          child: Text(
                            status,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (isApproved) ...[
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => _setDefaultOfficial(
                                id, name.isNotEmpty ? name : id),
                            child: Text(
                              isArabic
                                  ? 'استخدامه في مركز الحساب'
                                  : 'Use in owner console',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
