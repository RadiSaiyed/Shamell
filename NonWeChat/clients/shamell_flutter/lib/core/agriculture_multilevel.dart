import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import 'app_shell_widgets.dart' show AppBG;
import 'agri_fullharvest.dart';
import 'livestock_sellmylivestock.dart';

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
  State<AgricultureLivestockMultiLevelPage> createState() =>
      _AgricultureLivestockMultiLevelPageState();
}

class _AgricultureLivestockMultiLevelPageState
    extends State<AgricultureLivestockMultiLevelPage> {
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

  bool get _isAgriOperator {
    return _roles.contains('operator_agriculture') ||
        _operatorDomains.contains('agriculture');
  }

  bool get _isLivestockOperator {
    return _roles.contains('operator_livestock') ||
        _operatorDomains.contains('livestock');
  }

  String get _baseUrl => widget.baseUrl.trim();

  void _openAgriculture() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgriMarketplacePage(baseUrl: widget.baseUrl),
      ),
    );
  }

  void _openLivestock() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivestockMarketplacePage(baseUrl: widget.baseUrl),
      ),
    );
  }

  Future<void> _mutateAgriRole(
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
            Icon(Icons.store_mall_directory_outlined,
                color: Tokens.colorAgricultureLivestock),
            const SizedBox(width: 8),
            const Text(
              'Agri Marketplace + Livestock',
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
              ? 'مستخدم سوق المنتجات الزراعية'
              : 'Enduser (Agri Marketplace)',
          subtitle: l.isArabic
              ? 'طلب المنتجات الزراعية وتتبع صحة السوق'
              : 'Request produce and track marketplace health',
          children: [
            Text(
              l.isArabic
                  ? 'تصفح واطلب المنتجات الزراعية والموردين، وتابع صحة خدمات السوق.'
                  : 'Browse and request produce supply, match with growers, and monitor marketplace health.',
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
                  onPressed: _openAgriculture,
                  icon: const Icon(Icons.store),
                  label: const Text('Agri Marketplace'),
                ),
                FilledButton.icon(
                  onPressed: _openLivestock,
                  icon: const Icon(Icons.pets),
                  label: const Text('Livestock marketplace'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Operator section
        FormSection(
          title: l.isArabic
              ? 'مشغل سوق المنتجات الزراعية'
              : 'Agri Marketplace operator',
          subtitle: l.isArabic
              ? 'صلاحيات مشغلي الزراعة والثروة الحيوانية'
              : 'Agriculture and livestock operator roles',
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
                if (_isAgriOperator)
                  Chip(
                    label: const Text('operator_agriculture'),
                    backgroundColor:
                        Tokens.colorAgricultureLivestock.withValues(alpha: .16),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Tokens.colorAgricultureLivestock
                            .withValues(alpha: .9),
                      ),
                    ),
                  ),
                if (_isLivestockOperator)
                  Chip(
                    label: const Text('operator_livestock'),
                    backgroundColor:
                        Tokens.colorAgricultureLivestock.withValues(alpha: .10),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Tokens.colorAgricultureLivestock
                            .withValues(alpha: .75),
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
                      label: const Text('Agri Marketplace health'),
                    ),
                  if (_isLivestockOperator)
                    FilledButton.icon(
                      onPressed: _openLivestock,
                      icon: const Icon(Icons.pets),
                      label: const Text('Livestock operator'),
                    ),
                ],
              )
            else
              Text(
                l.isArabic
                    ? 'يمكن للمشرف أو المدير إضافة الأدوار operator_agriculture / operator_livestock من أدوات Superadmin في لوحة سوق المنتجات الزراعية.'
                    : 'Admin or Superadmin can grant operator_agriculture / operator_livestock from the Agri Marketplace tools on this page.',
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
              ? 'المدير (سوق المنتجات الزراعية)'
              : 'Admin (Agri Marketplace)',
          subtitle: l.isArabic
              ? 'صلاحيات الإدارة وتقارير سوق المنتجات الزراعية'
              : 'Admin rights and Agri Marketplace reporting',
          children: [
            Text(
              _isAdmin
                  ? (l.isArabic
                      ? 'هذا الهاتف لديه صلاحيات المدير؛ يمكنه الوصول إلى تقارير سوق المنتجات الزراعية.'
                      : 'This phone has admin rights; use admin/ops dashboards for Agri Marketplace reporting.')
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
          title: 'Superadmin (Agri Marketplace)',
          subtitle: l.isArabic
              ? 'إدارة أدوار سوق المنتجات الزراعية والحواجز'
              : 'Manage Agri Marketplace roles and guardrails',
          children: [
            Text(
              _isSuperadmin
                  ? 'Superadmin can manage Agri Marketplace roles and see guardrails and stats.'
                  : 'This phone is not Superadmin; Superadmin sees all Agri Marketplace roles and guardrails.',
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
                    ? 'إدارة أدوار سوق المنتجات الزراعية (Superadmin)'
                    : 'Agri Marketplace role management (Superadmin)',
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
      ],
    );

    return DomainPageScaffold(
      background: bg,
      title: 'Agriculture & Livestock',
      child: body,
      scrollable: false,
    );
  }
}
