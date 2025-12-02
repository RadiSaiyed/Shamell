import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import '../main.dart' show AppBG;
import 'building_cubotoo.dart';

Future<Map<String, String>> _hdrBuildingDash({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class BuildingMaterialsMultiLevelPage extends StatefulWidget {
  final String baseUrl;
  const BuildingMaterialsMultiLevelPage({super.key, required this.baseUrl});

  @override
  State<BuildingMaterialsMultiLevelPage> createState() => _BuildingMaterialsMultiLevelPageState();
}

class _BuildingMaterialsMultiLevelPageState extends State<BuildingMaterialsMultiLevelPage> {
  bool _loading = true;
  String _error = '';

  String _phone = '';
  bool _isAdmin = false;
  bool _isSuperadmin = false;
  List<String> _roles = const [];
  List<String> _operatorDomains = const [];
  String _walletId = '';

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
      final r = await http.get(uri, headers: await _hdrBuildingDash());
      if (r.statusCode != 200) {
        setState(() {
          _error = '${r.statusCode}: ${r.body}';
        });
      } else {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final roles = j['roles'];
        final ops = j['operator_domains'];
        final wallet = j['wallet'];
        setState(() {
          _phone = (j['phone'] ?? '').toString();
          _isAdmin = j['is_admin'] == true;
          _isSuperadmin = j['is_superadmin'] == true;
          _roles = roles is List ? roles.map((e) => e.toString()).toList() : const [];
          _operatorDomains = ops is List ? ops.map((e) => e.toString()).toList() : const [];
          if (wallet is Map<String, dynamic>) {
            final id = (wallet['wallet_id'] ?? wallet['id'] ?? '').toString();
            _walletId = id;
          }
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

  bool get _isBuildingOperator {
    return _roles.contains('operator_commerce') || _operatorDomains.contains('commerce');
  }

  String get _baseUrl => widget.baseUrl.trim();

  void _openEnduser() {
    if (_walletId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuildingCubotooPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  void _openOperator() {
    if (!_isBuildingOperator) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuildingCubotooPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  Future<void> _mutateCommerceRole({required bool grant}) async {
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
          ? 'Granting operator_commerce role...'
          : 'Revoking operator_commerce role...';
    });
    try {
      final uri = Uri.parse('$_baseUrl/admin/roles');
      final headers = await _hdrBuildingDash(json: true);
      final body = jsonEncode({'phone': phone, 'role': 'operator_commerce'});
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
            Icon(Icons.construction_outlined,
                color: Tokens.colorBuildingMaterials),
            const SizedBox(width: 8),
            const Text(
              'Building Materials – Enduser, Operator, Admin, Superadmin',
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
        // Enduser section
        FormSection(
          title: l.isArabic ? 'المستخدم النهائي (مواد البناء)' : 'Enduser (Building Materials)',
          subtitle: l.isArabic
              ? 'استخدام محفظتك لطلب مواد البناء مع الضمان'
              : 'Use your wallet to order building materials with escrow',
          children: [
            Text(
              l.isArabic
                  ? 'تصفح مواد البناء، ثم اطلبها مع حجز المبلغ في الضمان باستخدام محفظتك.'
                  : 'Browse building materials and place orders held in escrow using your wallet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _walletId.isEmpty
                  ? (l.isArabic
                      ? 'لا توجد محفظة حالياً؛ Superadmin أو Admin يمكنه إنشاء/ضبط المحفظة.'
                      : 'No wallet available; Superadmin/Admin can ensure or set a wallet.')
                  : (l.isArabic
                      ? 'محفظتك معدّة، يمكنك استخدام Building Materials كمستخدم نهائي.'
                      : 'Wallet is ready; you can use Building Materials as an enduser.'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _walletId.isEmpty ? null : _openEnduser,
              icon: const Icon(Icons.storefront_outlined),
              label: Text(l.homeBuildingMaterials),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Operator section
        FormSection(
          title: l.isArabic ? 'مشغل مواد البناء' : 'Building Materials operator',
          subtitle: l.isArabic
              ? 'صلاحيات المشغل ومشاهدة لوحة مواد البناء'
              : 'Operator rights and building materials console',
          children: [
            Text(
              l.isArabic ? 'الأدوار' : 'Roles',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_isBuildingOperator)
                    Chip(
                      label: const Text('operator_commerce'),
                      backgroundColor: Tokens.colorBuildingMaterials.withValues(alpha: .16),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: Tokens.colorBuildingMaterials.withValues(alpha: .9),
                        ),
                      ),
                    ),
                  if (!_isBuildingOperator)
                    Text(
                      l.isArabic
                          ? 'لا توجد صلاحيات مشغل Commerce/Building لهذا الهاتف.'
                          : 'This phone has no commerce/building operator rights.',
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
            if (_isBuildingOperator)
              FilledButton.icon(
                onPressed: _openOperator,
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: Text(
                  l.isArabic ? 'فتح مشغل مواد البناء' : 'Open Building Materials operator',
                ),
              )
            else
              Text(
                l.isArabic
                    ? 'يمكن للمشرف أو المدير إضافة الدور operator_commerce من أدوات Superadmin في لوحة مواد البناء / التجارة.'
                    : 'Admin or Superadmin can grant operator_commerce from the Building & Commerce tools on this page.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Admin section
        FormSection(
          title: l.isArabic ? 'المدير (مواد البناء)' : 'Admin (Building Materials)',
          subtitle: l.isArabic
              ? 'صلاحيات الإدارة وتقارير التجارة / مواد البناء'
              : 'Admin rights and commerce/building reports',
          children: [
            Text(
              _isAdmin
                  ? (l.isArabic
                      ? 'هذا الهاتف لديه صلاحيات المدير؛ يمكنه الوصول إلى تقارير Commerce/Building وعمليات التصدير.'
                      : 'This phone has admin rights; use admin/ops dashboards for commerce/building reporting.')
                  : (l.isArabic
                      ? 'لا توجد صلاحيات المدير؛ المشرف يمكنه إضافة دور admin.'
                      : 'No admin rights for this phone; Superadmin can grant admin.'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Superadmin section
        FormSection(
          title: 'Superadmin (Building Materials)',
          subtitle: l.isArabic
              ? 'إدارة أدوار التجارة / مواد البناء والحواجز'
              : 'Manage commerce/building roles and guardrails',
          children: [
            Text(
              _isSuperadmin
                  ? 'Superadmin can manage Building & Commerce roles and see guardrails and finance stats.'
                  : 'This phone is not Superadmin; Superadmin sees all commerce/building roles and guardrails.',
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
                    ? 'إدارة أدوار التجارة / مواد البناء (Superadmin)'
                    : 'Commerce / Building role management (Superadmin)',
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
                          : () => _mutateCommerceRole(grant: true),
                      icon: const Icon(Icons.add),
                      label: Text(
                        l.isArabic
                            ? 'إضافة operator_commerce'
                            : 'Grant operator_commerce',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _roleBusy
                          ? null
                          : () => _mutateCommerceRole(grant: false),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(
                        l.isArabic
                            ? 'إزالة operator_commerce'
                            : 'Revoke operator_commerce',
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
      ],
    );

    return DomainPageScaffold(
      background: bg,
      title: 'Building Materials',
      child: body,
      scrollable: false,
    );
  }
}
