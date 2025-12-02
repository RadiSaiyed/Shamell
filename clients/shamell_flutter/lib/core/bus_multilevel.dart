import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import '../main.dart' show AppBG, BusBookPage, BusOperatorPage;

Future<Map<String, String>> _hdrBusDash({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class BusMultiLevelPage extends StatefulWidget {
  final String baseUrl;
  const BusMultiLevelPage({super.key, required this.baseUrl});

  @override
  State<BusMultiLevelPage> createState() => _BusMultiLevelPageState();
}

class _BusMultiLevelPageState extends State<BusMultiLevelPage> {
  bool _loading = true;
  String _error = '';

  String _phone = '';
  bool _isAdmin = false;
  bool _isSuperadmin = false;
  List<String> _roles = const [];
  List<String> _operatorDomains = const [];

  final TextEditingController _targetPhoneCtrl = TextEditingController();
  final TextEditingController _operatorCompanyCtrl = TextEditingController();
  bool _roleBusy = false;
  String _roleOut = '';
  Map<String, dynamic>? _idsForPhone;

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
      final r = await http.get(uri, headers: await _hdrBusDash());
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

  bool get _isBusOperator {
    return _roles.contains('operator_bus') || _operatorDomains.contains('bus');
  }

  String get _baseUrl => widget.baseUrl.trim();

  void _openEnduser() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BusBookPage(widget.baseUrl)),
    );
  }

  void _openOperator() {
    if (!_isBusOperator) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BusOperatorPage(widget.baseUrl)),
    );
  }

  Future<void> _createBusOperatorForPhone() async {
    final phone = _targetPhoneCtrl.text.trim();
    final company = _operatorCompanyCtrl.text.trim();
    if (phone.isEmpty || company.isEmpty) {
      setState(() {
        _roleOut = 'Phone and company name are required';
      });
      return;
    }
    setState(() {
      _roleBusy = true;
      _roleOut = 'Creating bus operator...';
    });
    try {
      final uri = Uri.parse('$_baseUrl/admin/bus/operator');
      final headers = await _hdrBusDash(json: true);
      final body = jsonEncode({'phone': phone, 'company_name': company});
      final r = await http.post(uri, headers: headers, body: body);
      if (!mounted) return;
      setState(() {
        _roleOut = '${r.statusCode}: ${r.body}';
      });
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _loadIdsForPhone(phone);
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

  Future<void> _revokeBusOperatorRole() async {
    final phone = _targetPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _roleOut = 'Enter phone number first';
      });
      return;
    }
    setState(() {
      _roleBusy = true;
      _roleOut = 'Revoking operator_bus role...';
    });
    try {
      final uri = Uri.parse('$_baseUrl/admin/roles');
      final headers = await _hdrBusDash(json: true);
      final body = jsonEncode({'phone': phone, 'role': 'operator_bus'});
      final r = await http.delete(uri, headers: headers, body: body);
      if (!mounted) return;
      setState(() {
        _roleOut = '${r.statusCode}: ${r.body}';
      });
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await _loadIdsForPhone(phone);
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

  Future<void> _loadIdsForPhone(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) return;
    try {
      final qp = {
        'phone': p,
      };
      final uri = Uri.parse('$_baseUrl/admin/ids_for_phone')
          .replace(queryParameters: qp);
      final r = await http.get(uri, headers: await _hdrBusDash());
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map<String, dynamic>) {
          setState(() {
            _idsForPhone = body;
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _idsForPhone = null;
      });
    }
  }

  @override
  void dispose() {
    _targetPhoneCtrl.dispose();
    _operatorCompanyCtrl.dispose();
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
            Icon(Icons.directions_bus_filled_outlined,
                color: Tokens.colorBus),
            const SizedBox(width: 8),
            const Text(
              'Bus – Enduser, Operator, Admin, Superadmin',
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
          title: l.isArabic ? 'المستخدم النهائي (الباص)' : 'Enduser (Bus)',
          subtitle: l.isArabic
              ? 'حجوزات ومسارات الباص للركاب'
              : 'Intercity bus search, bookings and tickets',
          children: [
            Text(
              l.isArabic
                  ? 'احجز تذاكر الباص بين المدن، شاهد تفاصيل الحجز وتذاكر QR.'
                  : 'Search and book intercity bus trips, see your bookings and QR tickets.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openEnduser,
              icon: const Icon(Icons.search),
              label: const Text('Bus booking'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Operator section
        FormSection(
          title: l.isArabic ? 'مشغل الباص' : 'Bus operator',
          subtitle: l.isArabic
              ? 'أدوار المشغل ولوحة التحكم'
              : 'Operator roles and console',
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
                if (_isBusOperator)
                  Chip(
                    label: const Text('operator_bus'),
                    backgroundColor: Tokens.colorBus.withValues(alpha: .16),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Tokens.colorBus.withValues(alpha: .9),
                      ),
                    ),
                  ),
                if (!_isBusOperator)
                  Text(
                    l.isArabic
                        ? 'لا توجد صلاحيات مشغل Bus لهذه الهاتف.'
                        : 'This phone has no bus operator rights.',
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
            if (_isBusOperator)
              FilledButton.icon(
                onPressed: _openOperator,
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: const Text('Bus operator'),
              )
            else
              Text(
                l.isArabic
                    ? 'يمكن للمشرف أو المدير إضافة الدور operator_bus من لوحة الباص لهذه الخدمة.'
                    : 'Admin or Superadmin can grant operator_bus from the Bus tools on this page.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Admin section
        FormSection(
          title: l.isArabic ? 'المدير (الباص)' : 'Admin (Bus)',
          subtitle: l.isArabic
              ? 'صلاحيات الإدارة وتقارير الحافلات'
              : 'Admin rights and bus reports',
          children: [
            Text(
              _isAdmin
                  ? (l.isArabic
                      ? 'هذا الهاتف لديه صلاحيات المدير؛ يمكنه الوصول إلى تقارير الباص ومراقبة الجودة.'
                      : 'This phone has admin rights; use Admin/Ops dashboards for bus reporting.')
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
	          title: 'Superadmin (Bus)',
	          subtitle: l.isArabic
	              ? 'إدارة الأدوار والحواجز لمجال التنقل'
	              : 'Manage bus roles and mobility guardrails',
	          children: [
	            Text(
	              _isSuperadmin
	                  ? 'Superadmin can manage bus roles and see global mobility stats and guardrails.'
	                  : 'This phone is not Superadmin; Superadmin sees all bus guardrails and roles.',
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
	                    ? 'إدارة مشغلي الباص (Superadmin)'
	                    : 'Bus operator provisioning (Superadmin)',
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
	              TextField(
	                controller: _operatorCompanyCtrl,
	                decoration: InputDecoration(
	                  labelText: l.isArabic
	                      ? 'اسم الشركة / المشغل'
	                      : 'Company / Operator name',
	                  hintText: l.isArabic ? 'مثل: شركة Shamell' : 'e.g. Al-Ameer الأمير',
	                ),
	              ),
	              const SizedBox(height: 8),
	              Row(
	                children: [
	                  Expanded(
	                    child: FilledButton.icon(
	                      onPressed: _roleBusy ? null : _createBusOperatorForPhone,
	                      icon: const Icon(Icons.directions_bus_filled_outlined),
	                      label: Text(
	                        l.isArabic
	                            ? 'إنشاء مشغل باص'
	                            : 'Create Bus operator',
	                      ),
	                    ),
	                  ),
	                  const SizedBox(width: 8),
	                  Expanded(
	                    child: Column(
	                      crossAxisAlignment: CrossAxisAlignment.stretch,
	                      children: [
	                        OutlinedButton(
	                          onPressed: _roleBusy
	                              ? null
	                              : () => _revokeBusOperatorRole(),
	                          child: Text(
	                            l.isArabic
	                                ? 'إزالة operator_bus'
	                                : 'Revoke operator_bus',
	                          ),
	                        ),
	                        const SizedBox(height: 4),
	                        OutlinedButton(
	                          onPressed: _roleBusy
	                              ? null
	                              : () => _loadIdsForPhone(_targetPhoneCtrl.text),
	                          child: Text(
	                            l.isArabic
	                                ? 'عرض المعرفات لهذا الهاتف'
	                                : 'Show IDs for this phone',
	                          ),
	                        ),
	                      ],
	                    ),
	                  )
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
	              if (_idsForPhone != null) ...[
	                const SizedBox(height: 8),
	                Builder(
	                  builder: (ctx) {
	                    final ids = _idsForPhone!;
	                    String field(String key) {
	                      final v = (ids[key] ?? '').toString().trim();
	                      return v.isEmpty ? '-' : v;
	                    }

	                    final userId = field('user_id');
	                    final walletId = field('wallet_id');
	                    final busOps = (ids['bus_operator_ids'] is List)
	                        ? (ids['bus_operator_ids'] as List)
	                            .map((e) => e.toString())
	                            .join(', ')
	                        : '';

	                    String label(String en, String ar) =>
	                        L10n.of(ctx).isArabic ? ar : en;

	                    return Column(
	                      crossAxisAlignment: CrossAxisAlignment.start,
	                      children: [
	                        Text(
	                          "${label('User ID', 'معرّف المستخدم')}: $userId",
	                          style: Theme.of(ctx).textTheme.bodySmall,
	                        ),
	                        Text(
	                          "${label('Wallet ID', 'معرّف المحفظة')}: $walletId",
	                          style: Theme.of(ctx).textTheme.bodySmall,
	                        ),
	                        Text(
	                          "${label('Bus operator ID(s)', 'معرّف مشغل الحافلات')}: ${busOps.isEmpty ? '-' : busOps}",
	                          style: Theme.of(ctx).textTheme.bodySmall,
	                        ),
	                      ],
	                    );
	                  },
	                ),
	              ],
	            ],
	          ],
	        ),
	      ],
	    );

	    return DomainPageScaffold(
	      background: bg,
	      title: 'Bus',
	      child: body,
	      scrollable: false,
	    );
	  }
	}
