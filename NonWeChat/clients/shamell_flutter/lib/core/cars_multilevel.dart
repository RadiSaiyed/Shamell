import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import 'app_shell_widgets.dart' show AppBG;
import '../main.dart' show CarmarketPage, CarrentalPage;

Future<Map<String, String>> _hdrCarsDash({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class CarrentalCarmarketMultiLevelPage extends StatefulWidget {
  final String baseUrl;
  const CarrentalCarmarketMultiLevelPage({super.key, required this.baseUrl});

  @override
  State<CarrentalCarmarketMultiLevelPage> createState() =>
      _CarrentalCarmarketMultiLevelPageState();
}

class _CarrentalCarmarketMultiLevelPageState
    extends State<CarrentalCarmarketMultiLevelPage> {
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
      final r = await http.get(uri, headers: await _hdrCarsDash());
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

  bool get _isCarsOperator {
    // Carrental is its own domain; Carmarket typically uses commerce roles.
    return _roles.contains('operator_carrental') ||
        _roles.contains('operator_commerce') ||
        _operatorDomains.contains('carrental');
  }

  String get _baseUrl => widget.baseUrl.trim();

  void _openCarmarket() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CarmarketPage(widget.baseUrl)),
    );
  }

  void _openCarrental() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CarrentalPage(widget.baseUrl)),
    );
  }

  Future<void> _mutateCarsRole(
      {required String role, required bool grant}) async {
    final phone = _targetPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _roleOut = 'Enter phone number first';
      });
      return;
    }
    setState(() {
      _roleBusy = true;
      _roleOut = grant ? 'Granting $role role...' : 'Revoking $role role...';
    });
    try {
      final uri = Uri.parse('$_baseUrl/admin/roles');
      final headers = await _hdrCarsDash(json: true);
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
            Icon(Icons.directions_car_filled_outlined, color: Tokens.colorCars),
            const SizedBox(width: 8),
            const Text(
              'Carrental & Carmarket – Enduser, Operator, Admin, Superadmin',
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
          title: l.isArabic
              ? 'المستخدم النهائي (تأجير وبيع السيارات)'
              : 'Enduser (Carrental & Carmarket)',
          subtitle: l.isArabic
              ? 'تصفح واعرض السيارات واحجز للإيجار من محفظتك'
              : 'Browse cars, send inquiries and book rentals from your wallet',
          children: [
            Text(
              l.isArabic
                  ? 'تصفح إعلانات السيارات، أرسل استفسارات، واحجز سيارات للإيجار مباشرة من محفظتك.'
                  : 'Browse car listings, send inquiries, and book rental cars directly from your wallet.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _openCarmarket,
                  icon: const Icon(Icons.directions_car_filled_outlined),
                  label: Text(l.carmarketTitle),
                ),
                FilledButton.icon(
                  onPressed: _openCarrental,
                  icon: const Icon(Icons.car_rental),
                  label: Text(l.carrentalTitle),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Operator section
        FormSection(
          title: l.isArabic
              ? 'مشغل تأجير وبيع السيارات'
              : 'Carrental & Carmarket operator',
          subtitle: l.isArabic
              ? 'صلاحيات مشغل السيارات ولوحات Carmarket/Carrental'
              : 'Operator roles and Carmarket/Carrental consoles',
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
                if (_roles.contains('operator_carrental'))
                  Chip(
                    label: const Text('operator_carrental'),
                    backgroundColor: Tokens.colorCars.withValues(alpha: .16),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Tokens.colorCars.withValues(alpha: .9),
                      ),
                    ),
                  ),
                if (_roles.contains('operator_commerce'))
                  Chip(
                    label: const Text('operator_commerce'),
                    backgroundColor: Tokens.colorCars.withValues(alpha: .10),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Tokens.colorCars.withValues(alpha: .75),
                      ),
                    ),
                  ),
                if (!_isCarsOperator)
                  Text(
                    l.isArabic
                        ? 'لا توجد صلاحيات مشغل Carrental/Carmarket لهذه الهاتف.'
                        : 'This phone has no carrental/carmarket operator rights.',
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
            if (_isCarsOperator)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _openCarmarket,
                    icon: const Icon(Icons.directions_car_filled_outlined),
                    label: const Text('Carmarket operator'),
                  ),
                  FilledButton.icon(
                    onPressed: _openCarrental,
                    icon: const Icon(Icons.car_rental),
                    label: const Text('Carrental operator'),
                  ),
                ],
              )
            else
              Text(
                l.isArabic
                    ? 'يمكن للمشرف أو المدير إضافة الأدوار operator_carrental / operator_commerce من أدوات Superadmin في لوحة السيارات.'
                    : 'Admin or Superadmin can grant operator_carrental / operator_commerce from the Cars tools on this page.',
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
          title: l.isArabic
              ? 'المدير (تأجير وبيع السيارات)'
              : 'Admin (Carrental & Carmarket)',
          subtitle: l.isArabic
              ? 'صلاحيات الإدارة وتقارير السيارات'
              : 'Admin rights and car reporting',
          children: [
            Text(
              _isAdmin
                  ? (l.isArabic
                      ? 'هذا الهاتف لديه صلاحيات المدير؛ يمكنه الوصول إلى تقارير Carrental/Carmarket وعمليات التصدير.'
                      : 'This phone has admin rights; use admin/ops dashboards for carrental & carmarket reporting.')
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
          title: 'Superadmin (Carrental & Carmarket)',
          subtitle: l.isArabic
              ? 'إدارة أدوار السيارات والحواجز'
              : 'Manage car roles and guardrails',
          children: [
            Text(
              _isSuperadmin
                  ? 'Superadmin can manage Carrental & Carmarket roles and see guardrails and stats.'
                  : 'This phone is not Superadmin; Superadmin sees all carrental & carmarket roles and guardrails.',
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
                    ? 'إدارة أدوار Carrental & Carmarket (Superadmin)'
                    : 'Carrental & Carmarket role management (Superadmin)',
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
                        : () => _mutateCarsRole(
                              role: 'operator_carrental',
                              grant: true,
                            ),
                    icon: const Icon(Icons.add),
                    label: const Text('Grant operator_carrental'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _roleBusy
                        ? null
                        : () => _mutateCarsRole(
                              role: 'operator_carrental',
                              grant: false,
                            ),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Revoke operator_carrental'),
                  ),
                  FilledButton.icon(
                    onPressed: _roleBusy
                        ? null
                        : () => _mutateCarsRole(
                              role: 'operator_commerce',
                              grant: true,
                            ),
                    icon: const Icon(Icons.add),
                    label: const Text('Grant operator_commerce'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _roleBusy
                        ? null
                        : () => _mutateCarsRole(
                              role: 'operator_commerce',
                              grant: false,
                            ),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Revoke operator_commerce'),
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
      title: 'Carrental & Carmarket',
      child: body,
      scrollable: false,
    );
  }
}
