import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'glass.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import '../main.dart' show AppBG, FoodPage;
import 'food_orders.dart';
import 'pos_glass.dart';

Future<Map<String, String>> _hdrFoodDash({bool json = false}) async {
  final sp = await SharedPreferences.getInstance();
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final cookie = sp.getString('sa_cookie');
  if (cookie != null && cookie.isNotEmpty) {
    h['sa_cookie'] = cookie;
  }
  return h;
}

class FoodMultiLevelPage extends StatefulWidget {
  final String baseUrl;
  const FoodMultiLevelPage({super.key, required this.baseUrl});

  @override
  State<FoodMultiLevelPage> createState() => _FoodMultiLevelPageState();
}

class _FoodMultiLevelPageState extends State<FoodMultiLevelPage> {
  bool _loading = true;
  String _error = '';

  // Optional toggle to show only a subset of modules per role (keeps UX snappy)
  bool _compact = false;
  bool _darkGlass = false;

  static const Map<String, dynamic> _gn = {
    "SupplyCycle": {
      "subtitle": "Inventory, cost control and purchasing",
      "modules": {
        "InventoryManagement": {
          "description": [
            "Inventory management with real-time stock control",
            "Article and ingredient management",
            "Mobile inventory and breakage lists"
          ]
        },
        "Calculation": {
          "description": [
            "Calculation of contribution margin, cost of goods sold and gross profit",
            "Recipe and ingredient management",
            "Management of additives and allergens"
          ]
        },
        "ProcurementSystem": {
          "description": [
            "Supplier management",
            "Digital ordering",
            "Automated goods receipt"
          ]
        }
      }
    },
    "Management": {
      "subtitle": "Keep KPIs in view and scale",
      "modules": {
        "MultiLocation": {
          "description": [
            "Central management of multiple locations",
            "Cross-location data maintenance",
            "Central evaluation of all sites"
          ]
        },
        "TimeTracking": {
          "description": [
            "Digital recording of working and break times",
            "Recording via PIN, QR code or card",
            "Documentation of staff self-consumption"
          ]
        }
      }
    },
    "Marketing": {
      "subtitle": "Reach and new guests",
      "modules": {
        "Website": {
          "description": [
            "Modern, responsive templates",
            "Search-engine optimized",
            "Automatically generated pages for menus, news and more"
          ]
        },
        "Newsletter": {
          "description": [
            "Modern newsletter templates",
            "Automated content creation and sending",
            "Intelligent recipient grouping"
          ]
        },
        "DigitalSignage": {
          "description": [
            "Digital advertising boards for TV screens and website",
            "Modern, clear design",
            "Centralized control"
          ]
        }
      }
    },
    "GuestService": {
      "subtitle": "Boost revenue and loyalty",
      "modules": {
        "TableReservation": {
          "description": [
            "Real-time table plan",
            "Online reservation calendar",
            "Automated guest communication"
          ]
        },
        "OrderingSystem": {
          "description": [
            "Take-away and delivery service",
            "Self-ordering via QR code",
            "Digital menus and contactless payment"
          ]
        },
        "CustomerLoyalty": {
          "description": [
            "Customer database and loyalty cards",
            "Discounts and vouchers",
            "Cards for employees"
          ]
        }
      }
    },
    "Payment": {
      "subtitle": "Cashless payment",
      "modules": {
        "GastronoviPay": {
          "description": [
            "Supports all common cashless payment methods",
            "Transparent fees and fair conditions",
            "Tip suggestions and digital receipts"
          ]
        }
      }
    },
    "PointOfSale": {
      "subtitle": "POS + production",
      "modules": {
        "POSSystem": {
          "description": [
            "Fully integrated POS software",
            "Cloud-based and flexible",
            "Integration of service and kitchen"
          ]
        },
        "KitchenMonitor": {
          "description": [
            "Included within the POS system",
            "Real-time display of production progress",
            "Station and course management"
          ]
        },
        "CashBook": {
          "description": [
            "Complete bookkeeping with booking templates",
            "Recording of own and third-party receipts",
            "Daily cash counting and variance analysis"
          ]
        }
      }
    }
  };

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
      final r = await http.get(uri, headers: await _hdrFoodDash());
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

  bool get _isFoodOperator {
    return _roles.contains('operator_food') || _operatorDomains.contains('food');
  }

  String get _baseUrl => widget.baseUrl.trim();

  void _openEnduser() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FoodPage(widget.baseUrl)),
    );
  }

  void _openOperator() {
    if (!_isFoodOperator) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FoodOrdersPage(widget.baseUrl)),
    );
  }

  Future<void> _mutateFoodRole({required bool grant}) async {
    final phone = _targetPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _roleOut = 'Enter phone number first';
      });
      return;
    }
    setState(() {
      _roleBusy = true;
      _roleOut =
          grant ? 'Granting operator_food role...' : 'Revoking operator_food role...';
    });
    try {
      final uri = Uri.parse('$_baseUrl/admin/roles');
      final headers = await _hdrFoodDash(json: true);
      final body = jsonEncode({'phone': phone, 'role': 'operator_food'});
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

  Widget _buildGastroGrid() {
    final theme = Theme.of(context);
    const domainIcons = {
      "PointOfSale": Icons.point_of_sale_outlined,
      "SupplyCycle": Icons.inventory_2_outlined,
      "Management": Icons.dashboard_customize_outlined,
      "Marketing": Icons.campaign_outlined,
      "GuestService": Icons.room_service_outlined,
      "Payment": Icons.payments_outlined,
    };
    const moduleIcons = {
      "POSSystem": Icons.table_bar_outlined,
      "KitchenMonitor": Icons.kitchen_outlined,
      "CashBook": Icons.book_outlined,
      "InventoryManagement": Icons.warehouse_outlined,
      "Calculation": Icons.calculate_outlined,
      "ProcurementSystem": Icons.shopping_bag_outlined,
      "MultiLocation": Icons.store_mall_directory_outlined,
      "TimeTracking": Icons.schedule_outlined,
      "Website": Icons.language_outlined,
      "Newsletter": Icons.mail_outline,
      "DigitalSignage": Icons.tv_outlined,
      "TableReservation": Icons.event_seat_outlined,
      "OrderingSystem": Icons.delivery_dining_outlined,
      "CustomerLoyalty": Icons.card_membership_outlined,
      "GastronoviPay": Icons.credit_card,
    };
    final cards = <Widget>[];
    _gn.forEach((domain, value) {
      final subtitle = (value['subtitle'] ?? '').toString();
      final modules = (value['modules'] as Map<String, dynamic>);
      cards.add(
        GlassPanel(
          padding: const EdgeInsets.all(14),
          radius: 18,
          blurSigma: _darkGlass ? 26 : 20,
          borderOpacityLight: _darkGlass ? 0.08 : 0.12,
          borderOpacityDark: _darkGlass ? 0.14 : 0.16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(domainIcons[domain] ?? Icons.apps, size: 18, color: Tokens.colorFood),
                  const SizedBox(width: 6),
                  Text(domain, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  if (subtitle.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.75))),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: modules.entries.where((e) {
                  if (!_compact) return true;
                  // compact: pick 2 modules per domain
                  final idx = modules.keys.toList().indexOf(e.key);
                  return idx < 2;
                }).map((e) {
                  final name = e.key;
                  final desc = (e.value['description'] as List<dynamic>?)?.cast<String>() ?? const [];
                  return SizedBox(
                    width: 240,
                    child: GlassPanel(
                      padding: const EdgeInsets.all(12),
                      radius: 16,
                      blurSigma: _darkGlass ? 24 : 20,
                      borderOpacityLight: _darkGlass ? 0.08 : 0.12,
                      borderOpacityDark: _darkGlass ? 0.14 : 0.16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.12)),
                              color: _darkGlass
                                  ? theme.colorScheme.inverseSurface.withValues(alpha: 0.38)
                                  : theme.colorScheme.surface.withValues(alpha: 0.30),
                            ),
                            child: Row(
                              children: [
                                Icon(moduleIcons[name] ?? Icons.bolt_outlined, size: 16, color: Tokens.colorFood),
                                const SizedBox(width: 6),
                                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...desc.map((d) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1.5),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(top: 5),
                                      decoration: BoxDecoration(
                                        color: (_darkGlass
                                                ? theme.colorScheme.onInverseSurface
                                                : theme.colorScheme.primary)
                                            .withValues(alpha: 0.85),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: (_darkGlass
                                                    ? theme.colorScheme.onInverseSurface
                                                    : theme.colorScheme.primary)
                                                .withValues(alpha: 0.45),
                                            blurRadius: 10,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(
                                      d,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.85)),
                                    )),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Food Suite Overview', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Open POS Suite'),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => PosGlassPage(widget.baseUrl)));
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.list_alt),
              label: const Text('Open Orders Console'),
              onPressed: _openOperator,
            ),
            FilterChip(
              label: const Text('Compact'),
              selected: _compact,
              onSelected: (v) => setState(() => _compact = v),
            ),
            FilterChip(
              label: const Text('Glass: Dark accent'),
              selected: _darkGlass,
              onSelected: (v) => setState(() => _darkGlass = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards.map((c) => SizedBox(width: _compact ? 460 : 520, child: c)).toList(),
          ),
      ],
    );
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
            Icon(Icons.restaurant_menu_outlined, color: Tokens.colorFood),
            const SizedBox(width: 8),
            const Text(
              'Food – Enduser, Operator, Admin, Superadmin',
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
        // Food suite overview section
        FormSection(
          title: 'Food Suite',
          subtitle: l.isArabic
              ? 'نظرة عامة على وحدات نقاط البيع، المخزون، الإدارة والتسويق'
              : 'High-level overview of POS, stock, management and marketing modules',
          children: [
            _buildGastroGrid(),
          ],
        ),
        const SizedBox(height: 16),
        // Enduser section
        FormSection(
          title: l.isArabic ? 'المستخدم النهائي (Food)' : 'Enduser (Food)',
          subtitle: l.isArabic
              ? 'طلب الطعام والدفع من المحفظة'
              : 'Order food and pay from your wallet',
          children: [
            Text(
              l.isArabic
                  ? 'يمكنك البحث عن المطاعم وطلب الطعام والدفع من محفظتك.'
                  : 'Search restaurants, place food orders and pay from your wallet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openEnduser,
              icon: const Icon(Icons.restaurant),
              label: Text(l.homeFood),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Operator section
        FormSection(
          title: l.isArabic ? 'مشغل Food' : 'Food operator',
          subtitle: l.isArabic
              ? 'صلاحيات المشغل ولوحة الطلبات'
              : 'Operator rights and orders console',
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
                if (_isFoodOperator)
                  Chip(
                    label: const Text('operator_food'),
                    backgroundColor: Tokens.colorFood.withValues(alpha: .16),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Tokens.colorFood.withValues(alpha: .9),
                      ),
                    ),
                  ),
                if (!_isFoodOperator)
                  Text(
                    l.isArabic
                        ? 'لا توجد صلاحيات مشغل Food لهذه الهاتف.'
                        : 'This phone has no food operator rights.',
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
            if (_isFoodOperator)
              FilledButton.icon(
                onPressed: _openOperator,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(l.isArabic ? 'طلبات الطعام' : 'Food orders'),
              )
            else
              Text(
                l.isArabic
                    ? 'يمكن للمشرف أو المدير إضافة الدور operator_food من لوحة Superadmin.'
                    : 'Admin or Superadmin can grant operator_food via the Superadmin dashboard.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Admin section
        FormSection(
          title: l.isArabic ? 'المدير (Food)' : 'Admin (Food)',
          subtitle: l.isArabic
              ? 'صلاحيات الإدارة وتقارير الطلبات'
              : 'Admin rights and food reporting',
          children: [
            Text(
              _isAdmin
                  ? (l.isArabic
                      ? 'هذا الهاتف لديه صلاحيات المدير؛ يمكنه الوصول إلى تقارير الطلبات Food.'
                      : 'This phone has admin rights; use Ops/Admin dashboards for food reporting.')
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
          title: 'Superadmin (Food)',
          subtitle: l.isArabic
              ? 'إدارة أدوار Food والحواجز'
              : 'Manage food roles and guardrails',
          children: [
            Text(
              _isSuperadmin
                  ? 'Superadmin can manage Food roles and see global guardrails and stats.'
                  : 'This phone is not Superadmin; Superadmin sees all food roles and guardrails.',
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
                    ? 'إدارة أدوار Food (Superadmin)'
                    : 'Food role management (Superadmin)',
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
                      onPressed:
                          _roleBusy ? null : () => _mutateFoodRole(grant: true),
                      icon: const Icon(Icons.add),
                      label: Text(
                        l.isArabic
                            ? 'إضافة operator_food'
                            : 'Grant operator_food',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _roleBusy ? null : () => _mutateFoodRole(grant: false),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(
                        l.isArabic
                            ? 'إزالة operator_food'
                            : 'Revoke operator_food',
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
      title: 'Food',
      child: body,
      scrollable: false,
    );
  }
}
