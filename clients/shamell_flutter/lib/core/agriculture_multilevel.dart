import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'glass.dart';
import 'l10n.dart';
import '../main.dart' show AppBG, ModuleHealthPage;

Future<Map<String, String>> _hdrAgriDash({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class AgricultureLivestockMultiLevelPage extends StatefulWidget {
  final String baseUrl;
  const AgricultureLivestockMultiLevelPage({super.key, required this.baseUrl});

  @override
  State<AgricultureLivestockMultiLevelPage> createState() => _AgricultureLivestockMultiLevelPageState();
}

class _AgricultureLivestockMultiLevelPageState extends State<AgricultureLivestockMultiLevelPage> {
  bool _loading = true;
  String _error = '';

  String _phone = '';
  bool _isAdmin = false;
  bool _isSuperadmin = false;
  List<String> _roles = const [];
  List<String> _operatorDomains = const [];

  final TextEditingController _targetPhoneCtrl = TextEditingController();
  bool _roleBusy = false;
  String _roleOut = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl.trim()}/me/home_snapshot');
      final r = await http.get(uri, headers: await _hdrAgriDash());
      if (r.statusCode != 200) {
        setState(() {
          _error = '${r.statusCode}: ${r.body}';
        });
      } else {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final roles = j['roles'];
        final ops = j['operator_domains'];
        setState(() {
          _phone = (j['phone'] ?? '').toString();
          _isAdmin = j['is_admin'] == true;
          _isSuperadmin = j['is_superadmin'] == true;
          _roles = roles is List ? roles.map((e) => e.toString()).toList() : const [];
          _operatorDomains = ops is List ? ops.map((e) => e.toString()).toList() : const [];
        });
      }
    } catch (e) {
      setState(() {
        _error = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool get _isAgriOperator {
    return _roles.contains('operator_agriculture') || _operatorDomains.contains('agriculture');
  }

  bool get _isLivestockOperator {
    return _roles.contains('operator_livestock') || _operatorDomains.contains('livestock');
  }

  String get _baseUrl => widget.baseUrl.trim();

  void _openAgriculture() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModuleHealthPage(widget.baseUrl, 'Agriculture', '/agriculture/health'),
      ),
    );
  }

  void _openLivestock() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModuleHealthPage(widget.baseUrl, 'Livestock', '/livestock/health'),
      ),
    );
  }

  Future<void> _mutateAgriRole({required String role, required bool grant}) async {
    final phone = _targetPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _roleOut = 'Enter phone number first';
      });
      return;
    }
    setState(() {
      _roleBusy = true;
      _roleOut = grant
          ? 'Granting $role role...'
          : 'Revoking $role role...';
    });
    try {
      final uri = Uri.parse('$_baseUrl/admin/roles');
      final headers = await _hdrAgriDash(json: true);
      final body = jsonEncode({'phone': phone, 'role': role});
      final r = grant
          ? await http.post(uri, headers: headers, body: body)
          : await http.delete(uri, headers: headers, body: body);
      if (!mounted) return;
      setState(() {
        _roleOut = '${r.statusCode}: ${r.body}';
      });
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _roleOut = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _roleBusy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _targetPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const bg = AppBG();

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.agriculture, color: Tokens.colorAgricultureLivestock),
            const SizedBox(width: 8),
            const Text(
              'Agriculture & Livestock – Enduser, Operator, Admin, Superadmin',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_phone.isNotEmpty)
          Text(
            'Phone: $_phone',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        // Enduser card
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.agriculture),
                  const SizedBox(width: 8),
                  Text(
                    l.isArabic ? 'المستخدم النهائي (الزراعة والثروة الحيوانية)' : 'Enduser (Agriculture & Livestock)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.isArabic
                    ? 'راقب حالة وحدات الزراعة والثروة الحيوانية، وتأكد من عمل الخدمات بشكل سليم.'
                    : 'Check health for agriculture and livestock modules and ensure services are running well.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _openAgriculture,
                    icon: const Icon(Icons.agriculture),
                    label: const Text('Agriculture'),
                  ),
                  FilledButton.icon(
                    onPressed: _openLivestock,
                    icon: const Icon(Icons.pets),
                    label: const Text('Livestock'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Operator card
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.support_agent_outlined),
                  const SizedBox(width: 8),
                  Text(
                    l.isArabic ? 'مشغل الزراعة والثروة الحيوانية' : 'Agriculture & Livestock operator',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.isArabic ? 'الأدوار' : 'Roles',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_isAgriOperator)
                    Chip(
                      label: const Text('operator_agriculture'),
                      backgroundColor: Tokens.colorAgricultureLivestock.withValues(alpha: .16),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color:
                              Tokens.colorAgricultureLivestock.withValues(alpha: .9),
                        ),
                      ),
                    ),
                  if (_isLivestockOperator)
                    Chip(
                      label: const Text('operator_livestock'),
                      backgroundColor: Tokens.colorAgricultureLivestock.withValues(alpha: .10),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color:
                              Tokens.colorAgricultureLivestock.withValues(alpha: .75),
                        ),
                      ),
                    ),
                  if (!_isAgriOperator && !_isLivestockOperator)
                    Text(
                      l.isArabic
                          ? 'لا توجد صلاحيات مشغل الزراعة أو الثروة الحيوانية لهذه الهاتف.'
                          : 'This phone has no agriculture or livestock operator rights.',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isAgriOperator || _isLivestockOperator)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_isAgriOperator)
                      FilledButton.icon(
                        onPressed: _openAgriculture,
                        icon: const Icon(Icons.agriculture),
                        label: const Text('Agriculture health'),
                      ),
                    if (_isLivestockOperator)
                      FilledButton.icon(
                        onPressed: _openLivestock,
                        icon: const Icon(Icons.pets),
                        label: const Text('Livestock health'),
                      ),
                  ],
                )
              else
                Text(
                  l.isArabic
                      ? 'يمكن للمشرف أو المدير إضافة الأدوار operator_agriculture / operator_livestock من أدوات Superadmin في لوحة الزراعة والثروة الحيوانية.'
                      : 'Admin or Superadmin can grant operator_agriculture / operator_livestock from the Agriculture & Livestock tools on this page.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Admin card
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings_outlined),
                  const SizedBox(width: 8),
                  Text(
                    l.isArabic ? 'المدير (الزراعة والثروة الحيوانية)' : 'Admin (Agriculture & Livestock)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isAdmin
                    ? (l.isArabic
                        ? 'هذا الهاتف لديه صلاحيات المدير؛ يمكنه الوصول إلى تقارير الزراعة والثروة الحيوانية.'
                        : 'This phone has admin rights; use admin/ops dashboards for agriculture & livestock reporting.')
                    : (l.isArabic
                        ? 'لا توجد صلاحيات المدير؛ المشرف يمكنه إضافة دور admin.'
                        : 'No admin rights for this phone; Superadmin can grant admin.'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Superadmin card
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.security_outlined),
                  const SizedBox(width: 8),
                  const Text(
                    'Superadmin (Agriculture & Livestock)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isSuperadmin
                    ? 'Superadmin can manage Agriculture & Livestock roles and see guardrails and stats.'
                    : 'This phone is not Superadmin; Superadmin sees all agriculture & livestock roles and guardrails.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
              const SizedBox(height: 8),
              Text('Roles: ${_roles.join(", ")}'),
              const SizedBox(height: 4),
              Text(
                'Operator domains: ${_operatorDomains.join(", ")}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
              if (_isSuperadmin || _isAdmin) ...[
                const SizedBox(height: 16),
                Text(
                  l.isArabic
                      ? 'إدارة أدوار الزراعة والثروة الحيوانية (Superadmin)'
                      : 'Agriculture & Livestock role management (Superadmin)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _targetPhoneCtrl,
                  decoration: InputDecoration(
                    labelText: l.isArabic
                        ? 'هاتف الهدف (+963...)'
                        : 'Target phone (+963...)',
                    hintText: '+963...',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _roleBusy
                          ? null
                          : () => _mutateAgriRole(
                                role: 'operator_agriculture',
                                grant: true,
                              ),
                      icon: const Icon(Icons.add),
                      label: const Text('Grant operator_agriculture'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _roleBusy
                          ? null
                          : () => _mutateAgriRole(
                                role: 'operator_agriculture',
                                grant: false,
                              ),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Revoke operator_agriculture'),
                    ),
                    FilledButton.icon(
                      onPressed: _roleBusy
                          ? null
                          : () => _mutateAgriRole(
                                role: 'operator_livestock',
                                grant: true,
                              ),
                      icon: const Icon(Icons.add),
                      label: const Text('Grant operator_livestock'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _roleBusy
                          ? null
                          : () => _mutateAgriRole(
                                role: 'operator_livestock',
                                grant: false,
                              ),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Revoke operator_livestock'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_roleOut.isNotEmpty)
                  Text(
                    _roleOut,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .80),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agriculture & Livestock – 4 levels'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(
            child: SafeArea(child: body),
          ),
        ],
      ),
    );
  }
}
