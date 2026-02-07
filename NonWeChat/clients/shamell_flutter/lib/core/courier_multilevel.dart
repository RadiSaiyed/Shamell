import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import 'app_shell_widgets.dart' show AppBG;
import '../main.dart' show FreightPage;

Future<Map<String, String>> _hdrCourierDash({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class CourierMultiLevelPage extends StatefulWidget {
  final String baseUrl;
  const CourierMultiLevelPage({super.key, required this.baseUrl});

  @override
  State<CourierMultiLevelPage> createState() => _CourierMultiLevelPageState();
}

class _CourierMultiLevelPageState extends State<CourierMultiLevelPage> {
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
      final r = await http.get(uri, headers: await _hdrCourierDash());
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
          _roles = roles is List
              ? roles.map((e) => e.toString()).toList()
              : const [];
          _operatorDomains =
              ops is List ? ops.map((e) => e.toString()).toList() : const [];
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

  bool get _isCourierOperator {
    return _roles.contains('operator_freight') ||
        _operatorDomains.contains('freight');
  }

  String get _baseUrl => widget.baseUrl.trim();

  void _openCourier() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FreightPage(widget.baseUrl)),
    );
  }

  Future<void> _mutateCourierRole({required bool grant}) async {
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
          ? 'Granting operator_freight role...'
          : 'Revoking operator_freight role...';
    });
    try {
      final uri = Uri.parse('$_baseUrl/admin/roles');
      final headers = await _hdrCourierDash(json: true);
      final body = jsonEncode({'phone': phone, 'role': 'operator_freight'});
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
            Icon(Icons.local_shipping_outlined,
                color: Tokens.colorCourierTransport),
            const SizedBox(width: 8),
            const Text(
              'Courier – Enduser, Operator, Admin, Superadmin',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_phone.isNotEmpty)
          Text(
            'Phone: $_phone',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .70),
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
          title:
              l.isArabic ? 'المستخدم النهائي (Courier)' : 'Enduser (Courier)',
          subtitle: l.isArabic
              ? 'إرسال الشحنات والحجز والدفع من المحفظة'
              : 'Send shipments, get quotes and pay from your wallet',
          children: [
            Text(
              l.isArabic
                  ? 'أرسل شحنات، احصل على تسعير فوري، واحجز وادفع من محفظتك.'
                  : 'Send shipments, get instant quotes, and book & pay from your wallet.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openCourier,
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(l.freightTitle),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Operator section
        FormSection(
          title: l.isArabic ? 'مشغل Courier' : 'Courier operator',
          subtitle: l.isArabic
              ? 'صلاحيات مشغل التوصيل ولوحة الشحنات'
              : 'Courier operator rights and shipments console',
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
                if (_isCourierOperator)
                  Chip(
                    label: const Text('operator_freight'),
                    backgroundColor:
                        Tokens.colorCourierTransport.withValues(alpha: .16),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color:
                            Tokens.colorCourierTransport.withValues(alpha: .9),
                      ),
                    ),
                  ),
                if (!_isCourierOperator)
                  Text(
                    l.isArabic
                        ? 'لا توجد صلاحيات مشغل Courier/Transport لهذه الهاتف.'
                        : 'This phone has no Courier/transport operator rights.',
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
            if (_isCourierOperator)
              FilledButton.icon(
                onPressed: _openCourier,
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: Text(
                  l.isArabic ? 'فتح مشغل Courier' : 'Open Courier operator',
                ),
              )
            else
              Text(
                l.isArabic
                    ? 'يمكن للمشرف أو المدير إضافة الدور operator_freight من أدوات Superadmin في لوحة Courier.'
                    : 'Admin or Superadmin can grant operator_freight from the Courier tools on this page.',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .70),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Admin section
        FormSection(
          title: l.isArabic ? 'المدير (Courier)' : 'Admin (Courier)',
          subtitle: l.isArabic
              ? 'صلاحيات الإدارة وتقارير التوصيل'
              : 'Admin rights and courier reports',
          children: [
            Text(
              _isAdmin
                  ? (l.isArabic
                      ? 'هذا الهاتف لديه صلاحيات المدير؛ يمكنه الوصول إلى تقارير وخدمات التوصيل.'
                      : 'This phone has admin rights; use admin/ops dashboards for courier reporting.')
                  : (l.isArabic
                      ? 'لا توجد صلاحيات المدير؛ المشرف يمكنه إضافة دور admin.'
                      : 'No admin rights for this phone; Superadmin can grant admin.'),
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Superadmin section
        FormSection(
          title: 'Superadmin (Courier)',
          subtitle: l.isArabic
              ? 'إدارة أدوار Courier والحواجز'
              : 'Manage courier roles and guardrails',
          children: [
            Text(
              _isSuperadmin
                  ? 'Superadmin can manage courier roles and see guardrails and stats.'
                  : 'This phone is not Superadmin; Superadmin sees all courier roles and guardrails.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 8),
            Text('Roles: ${_roles.join(", ")}'),
            const SizedBox(height: 4),
            Text(
              'Operator domains: ${_operatorDomains.join(", ")}',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
            if (_isSuperadmin || _isAdmin) ...[
              const SizedBox(height: 16),
              Text(
                l.isArabic
                    ? 'إدارة أدوار Courier (Superadmin)'
                    : 'Courier role management (Superadmin)',
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
                          : () => _mutateCourierRole(grant: true),
                      icon: const Icon(Icons.add),
                      label: Text(
                        l.isArabic
                            ? 'إضافة operator_freight'
                            : 'Grant operator_freight',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _roleBusy
                          ? null
                          : () => _mutateCourierRole(grant: false),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(
                        l.isArabic
                            ? 'إزالة operator_freight'
                            : 'Revoke operator_freight',
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
      title: 'Courier',
      child: body,
      scrollable: false,
    );
  }
}
