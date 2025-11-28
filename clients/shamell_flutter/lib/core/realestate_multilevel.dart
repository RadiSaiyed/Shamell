import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'glass.dart';
import 'l10n.dart';
import '../main.dart' show AppBG, RealEstatePage;

Future<Map<String, String>> _hdrReDash({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class RealestateMultiLevelPage extends StatefulWidget {
  final String baseUrl;
  const RealestateMultiLevelPage({super.key, required this.baseUrl});

  @override
  State<RealestateMultiLevelPage> createState() => _RealestateMultiLevelPageState();
}

class _RealestateMultiLevelPageState extends State<RealestateMultiLevelPage> {
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
      final r = await http.get(uri, headers: await _hdrReDash());
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

  bool get _isReOperator {
    return _roles.contains('operator_realestate') || _operatorDomains.contains('realestate');
  }

  String get _baseUrl => widget.baseUrl.trim();

  void _openEnduser() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RealEstatePage(widget.baseUrl)),
    );
  }

  void _openOperator() {
    // RealEstatePage already exposes operator-style view (KPIs + controls),
    // so we reuse the same page for operator-level access.
    if (!_isReOperator) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RealEstatePage(widget.baseUrl)),
    );
  }

  Future<void> _mutateRealestateRole({required bool grant}) async {
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
          ? 'Granting operator_realestate role...'
          : 'Revoking operator_realestate role...';
    });
    try {
      final uri = Uri.parse('$_baseUrl/admin/roles');
      final headers = await _hdrReDash(json: true);
      final body = jsonEncode({'phone': phone, 'role': 'operator_realestate'});
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
            Icon(Icons.home_work_outlined,
                color: Tokens.colorHotelsStays),
            const SizedBox(width: 8),
            const Text(
              'Realestate – Enduser, Operator, Admin, Superadmin',
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
                  const Icon(Icons.home_outlined),
                  const SizedBox(width: 8),
                  Text(
                    l.isArabic ? 'المستخدم النهائي (Realestate)' : 'Enduser (Realestate)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.isArabic
                    ? 'تصفح العقارات، أرسل استفسارات، واطلب حجز مع وديعة سكن.'
                    : 'Browse properties, send inquiries and reserve with a deposit.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openEnduser,
                icon: const Icon(Icons.home),
                label: const Text('RealEstate'),
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
                    l.isArabic ? 'مشغل العقارات' : 'Realestate operator',
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
                  if (_isReOperator)
                    Chip(
                      label: const Text('operator_realestate'),
                      backgroundColor: Tokens.colorHotelsStays.withValues(alpha: .16),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: Tokens.colorHotelsStays.withValues(alpha: .9),
                        ),
                      ),
                    ),
                  if (!_isReOperator)
                    Text(
                      l.isArabic
                          ? 'لا توجد صلاحيات مشغل Realestate لهذه الهاتف.'
                          : 'This phone has no realestate operator rights.',
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
              if (_isReOperator)
                FilledButton.icon(
                  onPressed: _openOperator,
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text('Open operator view'),
                )
              else
                Text(
                  l.isArabic
                      ? 'يمكن للمشرف أو المدير إضافة الدور operator_realestate من أدوات Superadmin في لوحة العقارات.'
                      : 'Admin or Superadmin can grant operator_realestate from the Realestate tools on this page.',
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
                    l.isArabic ? 'المدير (Realestate)' : 'Admin (Realestate)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isAdmin
                    ? (l.isArabic
                        ? 'هذا الهاتف لديه صلاحيات المدير؛ يمكنه الوصول إلى تقارير العقارات.'
                        : 'This phone has admin rights; use Ops/Admin dashboards for realestate reporting.')
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
                    'Superadmin (Realestate)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isSuperadmin
                    ? 'Superadmin can manage Realestate roles and see global guardrails and stats.'
                    : 'This phone is not Superadmin; Superadmin sees all realestate roles and guardrails.',
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
                      ? 'إدارة أدوار Realestate (Superadmin)'
                      : 'Realestate role management (Superadmin)',
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
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _roleBusy
                            ? null
                            : () => _mutateRealestateRole(grant: true),
                        icon: const Icon(Icons.add),
                        label: Text(
                          l.isArabic
                              ? 'إضافة operator_realestate'
                              : 'Grant operator_realestate',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _roleBusy
                            ? null
                            : () => _mutateRealestateRole(grant: false),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: Text(
                          l.isArabic
                              ? 'إزالة operator_realestate'
                              : 'Revoke operator_realestate',
                        ),
                      ),
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
        title: const Text('Realestate – 4 levels'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(child: SafeArea(child: body)),
        ],
      ),
    );
  }
}
