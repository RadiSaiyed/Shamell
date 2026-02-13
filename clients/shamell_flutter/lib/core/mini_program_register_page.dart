import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'http_error.dart';
import 'l10n.dart';

class MiniProgramRegisterPage extends StatefulWidget {
  final String baseUrl;

  const MiniProgramRegisterPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<MiniProgramRegisterPage> createState() =>
      _MiniProgramRegisterPageState();
}

class _MiniProgramRegisterPageState extends State<MiniProgramRegisterPage> {
  final _appIdCtrl = TextEditingController();
  final _titleEnCtrl = TextEditingController();
  final _titleArCtrl = TextEditingController();
  final _descEnCtrl = TextEditingController();
  final _descArCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _ownerContactCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;
  final Set<String> _scopes = <String>{};

  @override
  void initState() {
    super.initState();
    _prefillOwnerContact();
  }

  @override
  void dispose() {
    _appIdCtrl.dispose();
    _titleEnCtrl.dispose();
    _titleArCtrl.dispose();
    _descEnCtrl.dispose();
    _descArCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerContactCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillOwnerContact() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final phone = sp.getString('phone') ?? '';
      if (!mounted || phone.trim().isEmpty) return;
      setState(() {
        _ownerContactCtrl.text = phone.trim();
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

  void _toggleScope(String key) {
    setState(() {
      if (_scopes.contains(key)) {
        _scopes.remove(key);
      } else {
        _scopes.add(key);
      }
    });
  }

  Future<void> _submit() async {
    final l = L10n.of(context);
    final appId = _appIdCtrl.text.trim();
    final titleEn = _titleEnCtrl.text.trim();
    if (appId.isEmpty || titleEn.isEmpty) {
      setState(() {
        _error = l.isArabic
            ? 'App-ID وعنوان EN مطلوبان.'
            : 'App‑ID and English title are required.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/mini_programs/self_register');
      final payload = <String, Object?>{
        'app_id': appId,
        'title_en': titleEn,
        'title_ar':
            _titleArCtrl.text.trim().isEmpty ? null : _titleArCtrl.text.trim(),
        'description_en':
            _descEnCtrl.text.trim().isEmpty ? null : _descEnCtrl.text.trim(),
        'description_ar':
            _descArCtrl.text.trim().isEmpty ? null : _descArCtrl.text.trim(),
        'owner_name': _ownerNameCtrl.text.trim().isEmpty
            ? null
            : _ownerNameCtrl.text.trim(),
        'owner_contact': _ownerContactCtrl.text.trim().isEmpty
            ? null
            : _ownerContactCtrl.text.trim(),
      };
      if (_scopes.isNotEmpty) {
        payload['scopes'] = _scopes.toList();
      }
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تم تسجيل البرنامج المصغر كمسودة قيد المراجعة.'
                : 'Mini‑program registered as draft for review.',
          ),
        ),
      );
      Navigator.of(context).maybePop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l.isArabic ? 'تعذّر إرسال الطلب.' : 'Could not submit request.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'تسجيل برنامج مصغر' : 'Register mini‑program',
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
                    ? 'سجّل برنامجك المصغر على نمط Shamell. يبدأ الإدخال كـ "مسودة" ويمكن لفريق Shamell مراجعته وتفعيله لاحقاً.'
                    : 'Register your Shamell‑style mini‑program. It starts as a draft and can be reviewed and activated by the Shamell team.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .80),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _appIdCtrl,
                decoration: InputDecoration(
                  labelText: isArabic ? 'App-ID' : 'App‑ID',
                  helperText: isArabic
                      ? 'أحرف صغيرة، أرقام، "_" و "-". مثال: bus_demo'
                      : 'Lowercase letters, digits, "_" and "-". Example: bus_demo',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleEnCtrl,
                decoration: InputDecoration(
                  labelText: isArabic ? 'العنوان (إنجليزي)' : 'Title (English)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleArCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'العنوان (عربي، اختياري)'
                      : 'Title (Arabic, optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descEnCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'الوصف (إنجليزي، اختياري)'
                      : 'Description (English, optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descArCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'الوصف (عربي، اختياري)'
                      : 'Description (Arabic, optional)',
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
                controller: _ownerContactCtrl,
                decoration: InputDecoration(
                  labelText: isArabic
                      ? 'جهة الاتصال (هاتف أو بريد إلكتروني)'
                      : 'Owner contact (phone or email)',
                  helperText: isArabic
                      ? 'يستخدم لتأكيد ملكية البرنامج المصغر وإشعارات المطور.'
                      : 'Used to confirm ownership and send developer notifications.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isArabic
                    ? 'ما الذي يحتاجه هذا البرنامج المصغر؟'
                    : 'What does this mini‑program need?',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildScopeChip('location', isArabic ? 'الموقع' : 'Location'),
                  _buildScopeChip(
                    'payments',
                    isArabic ? 'المحفظة والمدفوعات' : 'Wallet & payments',
                  ),
                  _buildScopeChip(
                    'transport',
                    isArabic ? 'التنقل والنقل' : 'Transport',
                  ),
                  _buildScopeChip(
                    'notifications',
                    isArabic ? 'الإشعارات' : 'Notifications',
                  ),
                  _buildScopeChip(
                    'moments',
                    isArabic ? 'اللحظات' : 'Moments',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isArabic
                    ? 'يمكن لفريق Shamell استخدام هذه المعلومات في المراجعة ومنح الصلاحيات.'
                    : 'Shamell can use these scopes during review and for permissions.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
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
                    isArabic ? 'إرسال للتسجيل' : 'Submit for registration',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeChip(String key, String label) {
    final selected = _scopes.contains(key);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _toggleScope(key),
    );
  }
}
