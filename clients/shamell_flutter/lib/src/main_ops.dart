part of '../main.dart';

const Duration _opsRequestTimeout = Duration(seconds: 15);
const bool _opsTopupVoucherRedeemEnabled = false;
const bool _opsTopupKioskEnabled = false;
const bool _opsSystemStatusEnabled = false;
const bool _opsSuperadminGlobalStatsEnabled = false;

Uri? _opsApiChildUri({
  required String baseUrl,
  required List<String> pathSegments,
  Map<String, String>? queryParameters,
}) {
  return secureApiChildUri(
    baseUrl: baseUrl,
    pathSegments: pathSegments,
    queryParameters: queryParameters,
  );
}

List<String>? _controlDashboardRouteSegments(String dashboardRoute) {
  final raw = dashboardRoute.trim();
  if (raw.isEmpty) return null;
  final path = raw.split('?').first.split('#').first.trim();
  if (path.isEmpty) return null;
  final segments = path
      .split('/')
      .map((segment) => Uri.decodeComponent(segment.trim()))
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty || segments.first != 'admin') return null;
  return segments;
}

String _controlDashboardRouteKey(List<String> pathSegments) {
  return '/${pathSegments.map((segment) => segment.toLowerCase()).join('/')}';
}

void _recordControlDashboardOpen({
  required String baseUrl,
  required String openContext,
  required bool nativeSurface,
  String dashboardRoute = '',
  String dashboardTitle = '',
}) {
  final normalizedRoute = dashboardRoute.trim();
  final normalizedTitle = dashboardTitle.trim();
  unawaited(
    ShamellPlatformFeatureEvents.record(
      baseUrl: baseUrl,
      moduleId: 'control',
      action: 'open',
      featureKey: 'dashboard_open',
      roleContext: openContext,
      metadata: <String, Object?>{
        'dashboard_route': normalizedRoute,
        'dashboard_title': normalizedTitle,
        'native_surface': nativeSurface,
        'client_surface': 'flutter',
      },
    ),
  );
}

Future<Map<String, String>> _controlDashboardApiHeaders({
  required String baseUrl,
  required String openContext,
  bool nativeSurface = true,
}) {
  return shamellSessionHeadersForBaseUrl(
    baseUrl,
    extra: <String, String>{
      'x-shamell-control-surface': nativeSurface ? 'native' : 'web',
      'x-shamell-control-context': openContext,
    },
  );
}

String _controlDashboardRouteTitle(List<String> pathSegments) {
  if (pathSegments.isEmpty) return 'Control dashboard';
  final last = pathSegments.last.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (last.isEmpty) return 'Control dashboard';
  return last
      .split(RegExp(r'\s+'))
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

Map<String, dynamic>? _opsRunbookMap(Map<String, dynamic> item) {
  final raw = item['runbook'];
  if (raw is! Map) return null;
  return raw.cast<String, dynamic>();
}

String _opsRunbookField(Map<String, dynamic> item, String key) {
  final runbook = _opsRunbookMap(item);
  if (runbook == null) return '';
  return (runbook[key] ?? '').toString().trim();
}

String _opsRunbookSummaryLine(Map<String, dynamic> item) {
  final title = _opsRunbookField(item, 'title');
  final firstStep = _opsRunbookField(item, 'first_step');
  if (title.isEmpty) return firstStep;
  if (firstStep.isEmpty) return 'Runbook: $title';
  return 'Runbook: $title · $firstStep';
}

WidgetBuilder? _controlDashboardNativeBuilderForSegments({
  required String baseUrl,
  required List<String> pathSegments,
}) {
  switch (_controlDashboardRouteKey(pathSegments)) {
    case '/admin/dashboards/overview':
    case '/admin/dashboards/control':
    case '/admin/dashboards/control-home':
      return (_) => ShamellControlDashboardHubPage(baseUrl: baseUrl);
    case '/admin/dashboards/control-intelligence':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>[
              'admin',
              'dashboards',
              'control-intelligence'
            ],
            title: 'Control intelligence',
            subtitle:
                'Operational score, gates, action plan, owner SLAs, and runbook evidence.',
            icon: Icons.psychology_alt_outlined,
            accent: const Color(0xFF334155),
          );
    case '/admin/dashboards/control-inbox':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>[
              'admin',
              'dashboards',
              'control-inbox'
            ],
            title: 'Control inbox',
            subtitle:
                'Prioritized owner queue with SLA, permissions, runbooks, and next dashboard routes.',
            icon: Icons.inbox_outlined,
            accent: const Color(0xFF0F766E),
          );
    case '/admin/dashboards/daily-brief':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'daily-brief'],
            title: 'Daily brief',
            subtitle:
                "Today's Control posture, lead action, owner focus, gates, readiness, and native adoption.",
            icon: Icons.today_outlined,
            accent: const Color(0xFF334155),
          );
    case '/admin/dashboards/escalations':
    case '/admin/dashboards/control-escalations':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'escalations'],
            title: 'Escalations',
            subtitle:
                'High and medium Control signals with owner SLA, required permission, runbook, and target board.',
            icon: Icons.report_gmailerrorred_outlined,
            accent: const Color(0xFFDC2626),
          );
    case '/admin/dashboards/sla-board':
    case '/admin/dashboards/control-sla':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'sla-board'],
            title: 'SLA board',
            subtitle:
                'Control actions grouped by due now, today, this week, and later watch buckets.',
            icon: Icons.timer_outlined,
            accent: const Color(0xFFC2410C),
          );
    case '/admin/dashboards/evidence':
    case '/admin/dashboards/control-evidence':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'evidence'],
            title: 'Evidence board',
            subtitle:
                'Runbook evidence, done-when criteria, first steps, escalation paths, and owner proof.',
            icon: Icons.fact_check_outlined,
            accent: const Color(0xFF2563EB),
          );
    case '/admin/dashboards/sync':
    case '/admin/dashboards/control-sync':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'sync'],
            title: 'Sync board',
            subtitle:
                'Data freshness, source authority, native route coverage, and cross-surface sync health.',
            icon: Icons.sync_alt_outlined,
            accent: const Color(0xFF0F766E),
          );
    case '/admin/dashboards/quality':
    case '/admin/dashboards/control-quality':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'quality'],
            title: 'Quality board',
            subtitle:
                'Surface readiness, operating gates, sync health, owners, and production-quality score.',
            icon: Icons.verified_outlined,
            accent: const Color(0xFF334155),
          );
    case '/admin/dashboards/launch':
    case '/admin/dashboards/control-launch':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'launch'],
            title: 'Launch board',
            subtitle:
                'Rollout decisions for scale, limited rollout, pilots, and held WeChat surfaces.',
            icon: Icons.rocket_launch_outlined,
            accent: const Color(0xFF7C3AED),
          );
    case '/admin/dashboards/growth':
    case '/admin/dashboards/control-growth':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'growth'],
            title: 'Growth board',
            subtitle:
                'Growth loops, adoption signals, experiments, instrumentation, and blocked surface follow-up.',
            icon: Icons.trending_up_outlined,
            accent: const Color(0xFF16A34A),
          );
    case '/admin/dashboards/experiments':
    case '/admin/dashboards/control-experiments':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'experiments'],
            title: 'Experiment board',
            subtitle:
                'Experiment hypotheses, primary metrics, success criteria, owners, and blocked growth follow-up.',
            icon: Icons.science_outlined,
            accent: const Color(0xFF0891B2),
          );
    case '/admin/dashboards/retention':
    case '/admin/dashboards/control-retention':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'retention'],
            title: 'Retention board',
            subtitle:
                'Repeat-use loops, retention score, cohort proof, measurement gaps, owners, and next moves.',
            icon: Icons.repeat_outlined,
            accent: const Color(0xFF0F766E),
          );
    case '/admin/dashboards/executive':
    case '/admin/dashboards/control-executive':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'executive'],
            title: 'Executive board',
            subtitle:
                'Top-level Control posture, attention, quality, rollout, growth, experiments, retention, and owner execution.',
            icon: Icons.space_dashboard_outlined,
            accent: const Color(0xFF334155),
          );
    case '/admin/dashboards/risk':
    case '/admin/dashboards/control-risk':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'risk'],
            title: 'Risk board',
            subtitle:
                'Critical risks, mitigations, risk scores, owners, review cadence, and target control boards.',
            icon: Icons.shield_outlined,
            accent: const Color(0xFFDC2626),
          );
    case '/admin/dashboards/incidents':
    case '/admin/dashboards/control-incidents':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'incidents'],
            title: 'Incident board',
            subtitle:
                'Active incidents, commanders, containment, response SLAs, rollback gates, comms, and target boards.',
            icon: Icons.crisis_alert_outlined,
            accent: const Color(0xFFC2410C),
          );
    case '/admin/dashboards/runbooks':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'runbooks'],
            title: 'Control runbooks',
            subtitle:
                'Owner playbooks, evidence, done-when criteria, and escalation paths.',
            icon: Icons.rule_folder_outlined,
            accent: const Color(0xFF0F766E),
          );
    case '/admin/dashboards/owner-workload':
    case '/admin/dashboards/owners':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>[
              'admin',
              'dashboards',
              'owner-workload'
            ],
            title: 'Owner workload',
            subtitle:
                'Team ownership, action pressure, SLAs, permissions, and next owner boards.',
            icon: Icons.assignment_ind_outlined,
            accent: const Color(0xFF2563EB),
          );
    case '/admin/dashboards/command-worklist':
    case '/admin/dashboards/control-command-worklist':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>[
              'admin',
              'dashboards',
              'command-worklist'
            ],
            title: 'Command worklist',
            subtitle:
                'Executive command, owner response, dispatch steps, next response windows, and target boards.',
            icon: Icons.outbound_outlined,
            accent: const Color(0xFFDC2626),
          );
    case '/admin/dashboards/mini-programs':
    case '/admin/dashboards/manifest-review':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>[
              'admin',
              'dashboards',
              'mini-programs'
            ],
            title: 'Mini-program review',
            subtitle:
                'Mini Program registry, manifest authority, review queue, releases, shelf usage, and event quality.',
            icon: Icons.apps_outlined,
            accent: const Color(0xFF0F766E),
          );
    case '/admin/dashboards/moments':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'moments'],
            title: 'Moments control',
            subtitle:
                'Moments feed health, privacy scopes, reports, comments, likes, Mini Program embeds, and friend-tag sync.',
            icon: Icons.dynamic_feed_outlined,
            accent: const Color(0xFF16A34A),
          );
    case '/admin/dashboards/official-accounts':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>[
              'admin',
              'dashboards',
              'official-accounts'
            ],
            title: 'Official Accounts control',
            subtitle:
                'Official Account profile quality, follows, feed depth, template messages, notification modes, and Green Paket linkage.',
            icon: Icons.verified_outlined,
            accent: const Color(0xFF2563EB),
          );
    case '/admin/dashboards/channels':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'channels'],
            title: 'Channels control',
            subtitle:
                'Channels content, live depth, views, follows, engagement, creator quality, and discovery telemetry.',
            icon: Icons.play_circle_outline_rounded,
            accent: const Color(0xFFE11D48),
          );
    case '/admin/dashboards/discover':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'discover'],
            title: 'Discover control',
            subtitle:
                'Search, People Nearby, profile freshness, and discovery telemetry.',
            icon: Icons.explore_outlined,
            accent: const Color(0xFF2563EB),
          );
    case '/admin/dashboards/contacts':
    case '/admin/dashboards/social-graph':
    case '/admin/dashboards/friend-tags':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'contacts'],
            title: 'Contacts control',
            subtitle:
                'Contacts graph quality, invitations, active edges, revocations, friend tags, and Moments privacy sync.',
            icon: Icons.groups_outlined,
            accent: const Color(0xFF0F766E),
          );
    case '/admin/dashboards/cards':
    case '/admin/dashboards/cards-offers':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'cards'],
            title: 'Cards and offers control',
            subtitle:
                'Member cards, offer inventory, claims, redemptions, and commerce telemetry.',
            icon: Icons.style_outlined,
            accent: Tokens.colorPayments,
          );
    case '/admin/dashboards/stickers':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'stickers'],
            title: 'Sticker store control',
            subtitle:
                'Sticker inventory, official packs, chat usage, and Mini Program telemetry.',
            icon: Icons.emoji_emotions_outlined,
            accent: const Color(0xFF7C3AED),
          );
    case '/admin/dashboards/favorites':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'favorites'],
            title: 'Favorites control',
            subtitle:
                'Saved items, source modules, active accounts, and mutation telemetry.',
            icon: Icons.bookmark_border_rounded,
            accent: const Color(0xFF0F766E),
          );
    case '/admin/dashboards/chat':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'chat'],
            title: 'Chat preferences control',
            subtitle:
                'Pinned, muted, starred, group preferences, and chat telemetry.',
            icon: Icons.chat_bubble_outline_rounded,
            accent: const Color(0xFF334155),
          );
    case '/admin/dashboards/green-paket':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'green-paket'],
            title: 'Green Paket control',
            subtitle:
                'Campaigns, commerce surfaces, Moments sharing, and owner activity.',
            icon: Icons.redeem_outlined,
            accent: Tokens.colorPayments,
          );
    case '/admin/dashboards/payment':
    case '/admin/dashboards/payments':
    case '/admin/dashboards/payments-credit':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'payments'],
            title: 'Payments control',
            subtitle:
                'Wallet authority, send safety, attestation hygiene, active challenges, and trusted payment telemetry.',
            icon: Icons.account_balance_wallet_outlined,
            accent: Tokens.colorPayments,
          );
    case '/admin/dashboards/rides':
    case '/admin/dashboards/ride-operator':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'rides'],
            title: 'Ride control',
            subtitle:
                'Ride trips, driver supply, dispatch offers, support pressure, payment failures, and live tracking authority.',
            icon: Icons.local_taxi_outlined,
            accent: const Color(0xFF2563EB),
          );
    case '/admin/dashboards/coach':
    case '/admin/dashboards/coach-operator':
    case '/admin/dashboards/coach-admin':
    case '/admin/dashboards/coach-boarding':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'coach'],
            title: 'Coach control',
            subtitle:
                'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority in one control board.',
            icon: Icons.directions_bus_outlined,
            accent: const Color(0xFF0F766E),
          );
    case '/admin/platform/features/summary':
      return (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>[
              'admin',
              'platform',
              'features',
              'summary'
            ],
            title: 'Analytics authority',
            subtitle:
                'Trusted platform events, source authority, and feature telemetry.',
            icon: Icons.query_stats_outlined,
            accent: const Color(0xFF334155),
          );
  }
  return null;
}

Future<void> _openControlDashboardBackendRoute(
  BuildContext context, {
  required String baseUrl,
  required String dashboardRoute,
}) async {
  final l = L10n.of(context);
  final pathSegments = _controlDashboardRouteSegments(dashboardRoute);
  void showLaunchError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l.isArabic
              ? 'تعذّر فتح لوحة التحكم.'
              : 'Could not open the control dashboard.',
        ),
      ),
    );
  }

  if (pathSegments == null) {
    showLaunchError();
    return;
  }
  final nativeBuilder = _controlDashboardNativeBuilderForSegments(
    baseUrl: baseUrl,
    pathSegments: pathSegments,
  );
  if (nativeBuilder != null) {
    await Navigator.of(context).push(MaterialPageRoute(builder: nativeBuilder));
    return;
  }
  if (shamellOpsTrustedWebPathRequiresSensitiveReveal(pathSegments)) {
    final approved = await _opsRequireSensitiveReveal(context);
    if (!approved) return;
  }
  final uri = shamellTrustedWebChildUri(
    baseUrl: baseUrl,
    pathSegments: pathSegments,
  );
  if (uri == null) {
    showLaunchError();
    return;
  }
  _recordControlDashboardOpen(
    baseUrl: baseUrl,
    dashboardRoute: _controlDashboardRouteKey(pathSegments),
    dashboardTitle: _controlDashboardRouteTitle(pathSegments),
    nativeSurface: false,
    openContext: 'trusted_web_route',
  );
  await launchWithSession(uri);
}

class ShamellControlDomainDashboardPage extends StatefulWidget {
  final String baseUrl;
  final List<String> pathSegments;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const ShamellControlDomainDashboardPage({
    super.key,
    required this.baseUrl,
    required this.pathSegments,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  State<ShamellControlDomainDashboardPage> createState() =>
      _ShamellControlDomainDashboardPageState();
}

class _ShamellControlDomainDashboardPageState
    extends State<ShamellControlDomainDashboardPage>
    with SafeSetStateMixin<ShamellControlDomainDashboardPage> {
  bool _loading = true;
  String _status = '';
  Map<String, dynamic>? _data;
  String _incidentWorkflowFilter = 'all';
  String _commandWorklistFilter = 'all';
  String _ownerWorkloadFilter = 'all';
  String _controlInboxFilter = 'all';
  String _strategicBoardFilter = 'all';
  String _operationalBoardFilter = 'all';
  String _runbookFilter = 'all';
  String _surfaceControlFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: widget.pathSegments,
    );
    if (uri == null) {
      setState(() {
        _loading = false;
        _status = _opsInvalidServerUrlMessage(context);
        _data = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _status = '';
    });
    final client = shamellHttpClient();
    try {
      final response = await client
          .get(
            uri,
            headers: await _controlDashboardApiHeaders(
              baseUrl: widget.baseUrl,
              openContext: 'native_control_dashboard_page',
            ),
          )
          .timeout(_opsRequestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final isArabic = L10n.of(context).isArabic;
        if (!mounted) return;
        setState(() {
          _loading = false;
          _data = null;
          _status = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(response.body);
      final parsed = decoded is Map ? decoded.cast<String, dynamic>() : null;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = _scopedDashboardData(parsed);
        _status = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = null;
        _status = sanitizeExceptionForUi(
          error: error,
          isArabic: L10n.of(context).isArabic,
        );
      });
    } finally {
      client.close();
    }
  }

  Map<String, dynamic>? _scopedDashboardData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final title = widget.title.toLowerCase();
    final scopeKey = title == 'control inbox'
        ? 'control_inbox'
        : title == 'control intelligence'
            ? 'control_intelligence'
            : title == 'daily brief'
                ? 'control_daily_brief'
                : title == 'escalations'
                    ? 'control_escalations'
                    : title == 'sla board'
                        ? 'control_sla_board'
                        : title == 'evidence board'
                            ? 'control_evidence_board'
                            : title == 'sync board'
                                ? 'control_sync_board'
                                : title == 'quality board'
                                    ? 'control_quality_board'
                                    : title == 'launch board'
                                        ? 'control_launch_board'
                                        : title == 'growth board'
                                            ? 'control_growth_board'
                                            : title == 'experiment board'
                                                ? 'control_experiment_board'
                                                : title == 'retention board'
                                                    ? 'control_retention_board'
                                                    : title == 'executive board'
                                                        ? 'control_executive_board'
                                                        : title == 'risk board'
                                                            ? 'control_risk_board'
                                                            : title ==
                                                                    'incident board'
                                                                ? 'control_incident_board'
                                                                : title ==
                                                                        'command worklist'
                                                                    ? 'control_command_worklist'
                                                                    : title ==
                                                                            'owner workload'
                                                                        ? 'control_owner_workload'
                                                                        : '';
    if (scopeKey.isEmpty) return data;
    final scoped = data[scopeKey];
    return scoped is Map ? scoped.cast<String, dynamic>() : data;
  }

  String _labelForKey(String key) {
    final normalized = key
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return key;
    return normalized
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  bool _isMetricValue(Object? value) {
    return value is num || value is bool || value is String;
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  Map<String, dynamic> _summaryData(Map<String, dynamic> data) {
    final summary = data['summary'];
    return summary is Map
        ? summary.cast<String, dynamic>()
        : data.cast<String, dynamic>();
  }

  List<Map<String, dynamic>> _listItems(
    Map<String, dynamic> data,
    List<String> keys, {
    int limit = 8,
  }) {
    for (final key in keys) {
      final raw = data[key];
      if (raw is List) {
        final items = raw
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .take(limit)
            .toList(growable: false);
        if (items.isNotEmpty) return items;
      }
    }
    return const <Map<String, dynamic>>[];
  }

  List<MapEntry<String, Object?>> _metricEntries(Map<String, dynamic> data) {
    final entries = <MapEntry<String, Object?>>[];
    for (final entry in data.entries) {
      final key = entry.key.trim();
      final value = entry.value;
      if (key.isEmpty || !_isMetricValue(value)) continue;
      if (key.endsWith('_at') ||
          key.endsWith('_iso') ||
          key == 'status' ||
          key == 'title' ||
          key == 'id') {
        continue;
      }
      entries.add(MapEntry<String, Object?>(key, value));
    }
    entries.sort((a, b) {
      final aNum = a.value is num ? 0 : 1;
      final bNum = b.value is num ? 0 : 1;
      if (aNum != bNum) return aNum.compareTo(bNum);
      return a.key.compareTo(b.key);
    });
    return entries.take(12).toList(growable: false);
  }

  List<Map<String, dynamic>> _primaryItems(Map<String, dynamic> data) {
    return _listItems(data, const <String>[
      'items',
      'campaigns',
      'top_campaigns',
      'dashboard_items',
      'recent_events',
      'top_events',
      'events',
    ]);
  }

  List<Map<String, dynamic>> _commandQueueItems(Map<String, dynamic> data) {
    return _listItems(data, const <String>['command_queue'], limit: 5);
  }

  List<Map<String, dynamic>> _responseLaneItems(Map<String, dynamic> data) {
    return _listItems(data, const <String>['response_lanes'], limit: 4);
  }

  bool get _isDailyBriefSurface => widget.title.toLowerCase() == 'daily brief';

  bool get _isControlInboxSurface =>
      widget.title.toLowerCase() == 'control inbox';

  bool get _isControlIntelligenceSurface =>
      widget.title.toLowerCase() == 'control intelligence';

  bool get _isRunbookSurface =>
      widget.title.toLowerCase() == 'control runbooks';

  bool get _isCommandWorklistSurface =>
      widget.title.toLowerCase() == 'command worklist';

  bool get _isOwnerWorkloadSurface =>
      widget.title.toLowerCase() == 'owner workload';

  bool get _isStrategicBoardSurface {
    final title = widget.title.toLowerCase();
    return title == 'experiment board' ||
        title == 'retention board' ||
        title == 'executive board' ||
        title == 'risk board';
  }

  bool get _isOperationalBoardSurface {
    final title = widget.title.toLowerCase();
    return title == 'escalations' ||
        title == 'sla board' ||
        title == 'evidence board' ||
        title == 'sync board' ||
        title == 'quality board' ||
        title == 'launch board' ||
        title == 'growth board';
  }

  bool get _isSurfaceControlSurface {
    final title = widget.title.toLowerCase();
    return title == 'mini-program review' ||
        title == 'moments control' ||
        title == 'moments' ||
        title == 'official accounts control' ||
        title == 'official accounts' ||
        title == 'channels control' ||
        title == 'channels' ||
        title == 'contacts control' ||
        title == 'contacts' ||
        title == 'discover control' ||
        title == 'cards control' ||
        title == 'cards and offers control' ||
        title == 'sticker store control' ||
        title == 'favorites control' ||
        title == 'chat preferences control' ||
        title == 'green paket control' ||
        title == 'payments control' ||
        title == 'ride control' ||
        title == 'coach control' ||
        title == 'analytics authority';
  }

  Map<String, dynamic>? _dailyCommandFocusItem(Map<String, dynamic> data) {
    for (final item in _primaryItems(data)) {
      if ((item['id'] ?? '').toString().trim() == 'command_focus') {
        return item;
      }
    }
    final summary = _summaryData(data);
    final commandTotal = _intValue(summary['command_total']);
    if (commandTotal <= 0) return null;
    return <String, dynamic>{
      'id': 'command_focus',
      'title': summary['command_primary_title'] ?? 'Control command',
      'status': summary['command_state'] ?? 'watch',
      'owner': summary['command_primary_owner'] ?? 'Control Operations',
      'dashboard_route': summary['command_primary_route'] ??
          '/admin/dashboards/command-worklist',
      'signal_count': commandTotal,
      'dispatch_steps_total': summary['command_dispatch_steps_total'] ?? 0,
      'next_response_minutes': summary['command_next_response_minutes'] ?? 0,
      'detail': '$commandTotal command task(s) need response.',
      'cta_label': 'Open command',
    };
  }

  List<Map<String, dynamic>> _featureItems(Map<String, dynamic> data) {
    return _listItems(
        data,
        const <String>[
          'features_30d',
          'features',
          'owner_action_summary',
          'modules',
          'mini_programs',
        ],
        limit: 10);
  }

  bool _showsOwnerWorkload(Map<String, dynamic>? data) {
    final value = data?['owner_action_summary'];
    return value is List && value.isNotEmpty;
  }

  List<Map<String, dynamic>> _sourceAuthorityItems(Map<String, dynamic> data) {
    return _listItems(
        data,
        const <String>[
          'source_authorities_30d',
          'source_authorities',
        ],
        limit: 8);
  }

  List<Map<String, dynamic>> _actionPlanItems(Map<String, dynamic> data) {
    final direct = _listItems(
      data,
      const <String>['action_plan', 'dashboard_actions'],
      limit: 8,
    );
    if (direct.isNotEmpty) return direct;
    final intelligence = data['control_intelligence'];
    if (intelligence is Map) {
      return _listItems(
        intelligence.cast<String, dynamic>(),
        const <String>['action_plan', 'dashboard_actions', 'next_actions'],
        limit: 8,
      );
    }
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _trendItems(Map<String, dynamic> data) {
    return _listItems(data, const <String>['series_30d'], limit: 30);
  }

  String _itemTitle(Map<String, dynamic> item) {
    for (final key in const <String>[
      'title',
      'title_en',
      'name',
      'official_name',
      'label',
      'feature_key',
      'module_id',
      'mini_program_id',
      'app_id',
      'tag',
      'visibility_scope',
      'campaign_id',
      'id',
      'key',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return 'Control item';
  }

  String _itemDetail(Map<String, dynamic> item) {
    final parts = <String>[];
    for (final key in const <String>[
      'status',
      'state',
      'owner',
      'review_cadence',
      'required_permission',
      'active',
      'event_count',
      'count',
      'module_id',
      'feature_key',
      'action',
      'events_30d',
      'source_authority',
      'role_context',
      'rollout_decision',
      'rollout_scope',
      'launch_window',
      'growth_signal',
      'growth_goal',
      'experiment_status',
      'primary_metric',
      'success_criteria',
      'retention_status',
      'retention_loop',
      'retention_score',
      'next_retention_move',
      'executive_attention',
      'operational_score',
      'source_authority_percent',
      'risk_level',
      'risk_domain',
      'risk_score',
      'mitigation',
      'incident_status',
      'workflow_status',
      'last_action',
      'incident_commander',
      'incident_commander_account_id',
      'owner_account_id',
      'owner_team',
      'response_phase',
      'response_sla_minutes',
      'containment',
      'rollback_gate',
      'snoozed_until',
      'timeline_event_count',
      'timeline_events',
      'timeline_events_total',
      'last_event_at',
      'queue_rank',
      'command_health',
      'escalation_tier',
      'response_bucket',
      'recommended_action',
      'next_response_minutes',
      'escalation_required',
      'command_critical',
      'command_attention',
      'command_watch',
      'command_resolved',
      'open_workflows',
      'unclaimed',
      'sla_due_soon',
      'workflow_active',
      'workflow_acknowledged',
      'workflow_assigned',
      'workflow_snoozed',
      'workflow_resolved',
      'official_account_id',
      'dashboard_route',
      'first_step',
      'done_when',
      'synced_when',
      'updated_at',
      'created_at',
    ]) {
      final value = item[key];
      if (value == null) continue;
      final raw = value.toString().trim();
      if (raw.isEmpty) continue;
      parts.add('${_labelForKey(key)}: $raw');
      if (parts.length >= 3) break;
    }
    return parts.join(' · ');
  }

  bool _isIncidentBoardItem(Map<String, dynamic> item) {
    if (!_isIncidentBoardSurface) return false;
    final id = (item['id'] ?? '').toString().trim();
    return id.isNotEmpty;
  }

  bool get _isIncidentBoardSurface =>
      widget.title.toLowerCase() == 'incident board';

  String _incidentWorkflowStatusForItem(Map<String, dynamic> item) {
    final raw = (item['workflow_status'] ??
            item['incident_status'] ??
            item['status'] ??
            'active')
        .toString()
        .trim();
    return raw.isEmpty ? 'active' : raw;
  }

  bool _incidentItemClaimed(Map<String, dynamic> item) {
    for (final key in const <String>[
      'incident_commander_account_id',
      'owner_account_id',
      'owner_team',
    ]) {
      if ((item[key] ?? '').toString().trim().isNotEmpty) return true;
    }
    return _incidentWorkflowStatusForItem(item) == 'assigned';
  }

  bool _incidentMatchesFilter(Map<String, dynamic> item, String filter) {
    if (filter == 'all') return true;
    final workflow = _incidentWorkflowStatusForItem(item);
    final incidentStatus =
        (item['incident_status'] ?? item['status'] ?? '').toString().trim();
    final commandHealth = (item['command_health'] ?? '').toString().trim();
    switch (filter) {
      case 'critical':
        return commandHealth == 'critical';
      case 'attention':
        return commandHealth == 'attention';
      case 'watch':
        return commandHealth == 'watch';
      case 'active':
        return workflow == 'active' || incidentStatus == 'active';
      case 'assigned':
        return workflow == 'assigned';
      case 'acknowledged':
        return workflow == 'acknowledged';
      case 'snoozed':
        return workflow == 'snoozed' || incidentStatus == 'monitoring';
      case 'resolved':
        return workflow == 'resolved' || incidentStatus == 'resolved';
      case 'unclaimed':
        return workflow != 'resolved' &&
            incidentStatus != 'resolved' &&
            !_incidentItemClaimed(item);
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredIncidentItems(
    List<Map<String, dynamic>> items,
  ) {
    if (!_isIncidentBoardSurface || _incidentWorkflowFilter == 'all') {
      return items;
    }
    return items
        .where((item) => _incidentMatchesFilter(item, _incidentWorkflowFilter))
        .toList(growable: false);
  }

  int _incidentFilterCount(
    List<Map<String, dynamic>> items,
    String filter,
  ) {
    return items.where((item) => _incidentMatchesFilter(item, filter)).length;
  }

  bool _commandMatchesFilter(Map<String, dynamic> item, String filter) {
    if (filter == 'all') return true;
    final status = (item['status'] ?? '').toString().trim();
    final authority =
        (item['incident_authority_state'] ?? '').toString().trim();
    final health = (item['command_health'] ?? '').toString().trim();
    final bucket = (item['response_bucket'] ?? '').toString().trim();
    final workflow = (item['workflow_status'] ?? '').toString().trim();
    switch (filter) {
      case 'executive':
        return status == 'executive_command' ||
            authority == 'executive_command_required';
      case 'owner':
        return status == 'owner_command' ||
            authority == 'owner_command_required';
      case 'critical':
        return health == 'critical';
      case 'attention':
        return health == 'attention';
      case 'watch':
        return health == 'watch' || status == 'control_watch';
      case 'due':
        return bucket == 'page_now' || bucket == 'due_soon';
      case 'unclaimed':
        return workflow == 'active';
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredCommandItems(
    List<Map<String, dynamic>> items,
  ) {
    if (!_isCommandWorklistSurface || _commandWorklistFilter == 'all') {
      return items;
    }
    return items
        .where((item) => _commandMatchesFilter(item, _commandWorklistFilter))
        .toList(growable: false);
  }

  int _commandFilterCount(
    List<Map<String, dynamic>> items,
    String filter,
  ) {
    return items.where((item) => _commandMatchesFilter(item, filter)).length;
  }

  String _commandFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'due':
        return 'Due';
      default:
        return _labelForKey(filter);
    }
  }

  IconData _commandFilterIcon(String filter) {
    switch (filter) {
      case 'all':
        return Icons.all_inbox_outlined;
      case 'executive':
        return Icons.corporate_fare_outlined;
      case 'owner':
        return Icons.assignment_ind_outlined;
      case 'critical':
        return Icons.notification_important_outlined;
      case 'attention':
        return Icons.priority_high_rounded;
      case 'watch':
        return Icons.visibility_outlined;
      case 'due':
        return Icons.timer_outlined;
      case 'unclaimed':
        return Icons.person_off_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  bool _ownerMatchesFilter(Map<String, dynamic> item, String filter) {
    if (filter == 'all') return true;
    final status = (item['status'] ?? '').toString().trim();
    final executive = _intValue(item['executive_command_required']);
    final ownerRequired = _intValue(item['owner_command_required']);
    final critical = _intValue(item['critical']);
    final dueSoon = _intValue(item['due_soon']);
    final unclaimed = _intValue(item['unclaimed']);
    final watch = _intValue(item['watch']);
    switch (filter) {
      case 'executive':
        return executive > 0 || status == 'executive_command';
      case 'owner':
        return ownerRequired > 0 || status == 'owner_command';
      case 'critical':
        return critical > 0;
      case 'due':
        return dueSoon > 0;
      case 'unclaimed':
        return unclaimed > 0;
      case 'watch':
        return watch > 0 || status == 'watch';
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredOwnerWorkloadItems(
    List<Map<String, dynamic>> items,
  ) {
    if (!_isOwnerWorkloadSurface || _ownerWorkloadFilter == 'all') {
      return items;
    }
    return items
        .where((item) => _ownerMatchesFilter(item, _ownerWorkloadFilter))
        .toList(growable: false);
  }

  int _ownerFilterCount(List<Map<String, dynamic>> items, String filter) {
    return items.where((item) => _ownerMatchesFilter(item, filter)).length;
  }

  String _ownerFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'due':
        return 'Due';
      default:
        return _labelForKey(filter);
    }
  }

  IconData _ownerFilterIcon(String filter) {
    switch (filter) {
      case 'all':
        return Icons.groups_outlined;
      case 'executive':
        return Icons.corporate_fare_outlined;
      case 'owner':
        return Icons.assignment_ind_outlined;
      case 'critical':
        return Icons.notification_important_outlined;
      case 'due':
        return Icons.timer_outlined;
      case 'unclaimed':
        return Icons.person_off_outlined;
      case 'watch':
        return Icons.visibility_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  bool _controlInboxMatchesFilter(Map<String, dynamic> item, String filter) {
    if (filter == 'all') return true;
    final severity = (item['severity'] ?? 'low').toString().trim();
    final status = (item['status'] ?? '').toString().trim();
    final dueMinutes = _intValue(item['due_in_minutes']);
    final permission = (item['required_permission'] ?? '').toString().trim();
    switch (filter) {
      case 'high':
        return severity == 'high';
      case 'medium':
        return severity == 'medium';
      case 'low':
        return severity == 'low';
      case 'due':
        return dueMinutes > 0 && dueMinutes <= 1440;
      case 'attention':
        return status == 'attention' || severity == 'high';
      case 'permission':
        return permission.isNotEmpty;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredControlInboxItems(
    List<Map<String, dynamic>> items,
  ) {
    if (!_isControlInboxSurface || _controlInboxFilter == 'all') {
      return items;
    }
    return items
        .where((item) => _controlInboxMatchesFilter(item, _controlInboxFilter))
        .toList(growable: false);
  }

  int _controlInboxFilterCount(
    List<Map<String, dynamic>> items,
    String filter,
  ) {
    return items
        .where((item) => _controlInboxMatchesFilter(item, filter))
        .length;
  }

  String _controlInboxFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'due':
        return 'Due';
      case 'permission':
        return 'Permission';
      default:
        return _labelForKey(filter);
    }
  }

  IconData _controlInboxFilterIcon(String filter) {
    switch (filter) {
      case 'all':
        return Icons.all_inbox_outlined;
      case 'high':
        return Icons.notification_important_outlined;
      case 'medium':
        return Icons.timelapse_rounded;
      case 'low':
        return Icons.task_alt_rounded;
      case 'due':
        return Icons.timer_outlined;
      case 'attention':
        return Icons.priority_high_rounded;
      case 'permission':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  String _strategicStatusForItem(Map<String, dynamic> item) {
    final title = widget.title.toLowerCase();
    final keys = title == 'risk board'
        ? const <String>['risk_level', 'risk_acceptance_state', 'status']
        : title == 'executive board'
            ? const <String>['executive_decision_state', 'status']
            : title == 'retention board'
                ? const <String>['retention_status', 'status']
                : const <String>['experiment_status', 'status'];
    for (final key in keys) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return 'watch';
  }

  String _strategicAuthorityForItem(Map<String, dynamic> item) {
    for (final key in const <String>[
      'command_authority_level',
      'risk_owner_authority',
      'retention_authority_state',
      'experiment_authority_state',
      'rollout_approval_state',
      'growth_readiness_state',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  int _strategicScoreForItem(Map<String, dynamic> item) {
    for (final key in const <String>[
      'priority_score',
      'command_priority_score',
      'risk_score',
      'retention_score',
      'growth_signal',
      'signal_count',
      'quality_score',
    ]) {
      final value = _intValue(item[key]);
      if (value > 0) return value;
    }
    return 0;
  }

  String _strategicSeverityForItem(Map<String, dynamic> item) {
    final explicit = (item['severity'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    final status = _strategicStatusForItem(item);
    final risk = (item['risk_level'] ?? '').toString().trim();
    if (risk == 'critical' ||
        status == 'blocked' ||
        status == 'decision_required' ||
        status == 'not_accepted') {
      return 'high';
    }
    if (risk == 'elevated' ||
        status == 'attention' ||
        status == 'prove' ||
        status == 'measure' ||
        status == 'instrument' ||
        status == 'running') {
      return 'medium';
    }
    return 'low';
  }

  bool _strategicMatchesFilter(Map<String, dynamic> item, String filter) {
    if (filter == 'all') return true;
    final status = _strategicStatusForItem(item);
    final severity = _strategicSeverityForItem(item);
    final authority = _strategicAuthorityForItem(item);
    switch (filter) {
      case 'blocked':
        return status == 'blocked' ||
            status == 'not_accepted' ||
            authority == 'blocked';
      case 'attention':
        return severity == 'high' ||
            severity == 'medium' ||
            status == 'attention';
      case 'ready':
        return status == 'scale' ||
            status == 'retained' ||
            status == 'approved' ||
            status == 'accepted' ||
            authority.contains('authorized');
      case 'decision':
        return status == 'decision_required' ||
            status == 'not_accepted' ||
            authority.contains('required');
      case 'measure':
        return status == 'measure' ||
            status == 'instrument' ||
            status == 'running' ||
            status == 'prove';
      case 'high':
        return severity == 'high';
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredStrategicBoardItems(
    List<Map<String, dynamic>> items,
  ) {
    if (!_isStrategicBoardSurface || _strategicBoardFilter == 'all') {
      return items;
    }
    return items
        .where((item) => _strategicMatchesFilter(item, _strategicBoardFilter))
        .toList(growable: false);
  }

  int _strategicFilterCount(List<Map<String, dynamic>> items, String filter) {
    return items.where((item) => _strategicMatchesFilter(item, filter)).length;
  }

  String _strategicFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'ready':
        return 'Ready';
      case 'measure':
        return 'Measure';
      case 'high':
        return 'High';
      default:
        return _labelForKey(filter);
    }
  }

  IconData _strategicFilterIcon(String filter) {
    switch (filter) {
      case 'all':
        return Icons.space_dashboard_outlined;
      case 'blocked':
        return Icons.block_outlined;
      case 'attention':
        return Icons.priority_high_rounded;
      case 'ready':
        return Icons.task_alt_rounded;
      case 'decision':
        return Icons.gavel_outlined;
      case 'measure':
        return Icons.insights_outlined;
      case 'high':
        return Icons.notification_important_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  String _strategicBoardHeaderTitle() {
    switch (widget.title.toLowerCase()) {
      case 'experiment board':
        return 'Experiment control';
      case 'retention board':
        return 'Retention control';
      case 'executive board':
        return 'Executive command';
      case 'risk board':
        return 'Risk command';
      default:
        return 'Strategic control';
    }
  }

  IconData _strategicBoardIcon() {
    switch (widget.title.toLowerCase()) {
      case 'experiment board':
        return Icons.science_outlined;
      case 'retention board':
        return Icons.repeat_outlined;
      case 'executive board':
        return Icons.space_dashboard_outlined;
      case 'risk board':
        return Icons.shield_outlined;
      default:
        return Icons.account_tree_outlined;
    }
  }

  String _strategicPrimaryLine(Map<String, dynamic> item) {
    for (final key in const <String>[
      'hypothesis',
      'retention_loop',
      'risk_domain',
      'mitigation',
      'primary_metric',
      'next_retention_move',
      'success_criteria',
      'detail',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _strategicGateLine(Map<String, dynamic> item) {
    for (final key in const <String>[
      'command_gate',
      'risk_gate',
      'retention_gate',
      'experiment_guardrail',
      'growth_gate',
      'approval_gate',
      'certification_gate',
      'decision_gate',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _opsStepDisplayText(Object? step) {
    if (step is Map) {
      final typed = step.cast<String, dynamic>();
      final label = (typed['label'] ?? '').toString().trim();
      final detail = (typed['detail'] ?? '').toString().trim();
      final id = (typed['id'] ?? '').toString().trim();
      if (label.isNotEmpty && detail.isNotEmpty) return '$label · $detail';
      if (label.isNotEmpty) return label;
      if (detail.isNotEmpty) return detail;
      return id;
    }
    return (step ?? '').toString().trim();
  }

  List<String> _strategicSteps(Map<String, dynamic> item) {
    for (final key in const <String>[
      'command_steps',
      'risk_mitigation_steps',
      'retention_steps',
      'experiment_steps',
      'growth_steps',
      'approval_steps',
      'certification_steps',
      'repair_steps',
    ]) {
      final raw = item[key];
      if (raw is List) {
        final steps = raw
            .map(_opsStepDisplayText)
            .where((step) => step.isNotEmpty)
            .take(2)
            .toList(growable: false);
        if (steps.isNotEmpty) return steps;
      }
    }
    return const <String>[];
  }

  String _operationalStatusForItem(Map<String, dynamic> item) {
    final title = widget.title.toLowerCase();
    final keys = title == 'sla board'
        ? const <String>['bucket', 'status']
        : title == 'sync board'
            ? const <String>['sync_status', 'status']
            : title == 'quality board'
                ? const <String>[
                    'quality_status',
                    'certification_state',
                    'gate_state',
                    'status',
                  ]
                : title == 'launch board'
                    ? const <String>[
                        'rollout_decision',
                        'rollout_approval_state',
                        'status',
                      ]
                    : title == 'growth board'
                        ? const <String>['status', 'growth_status']
                        : const <String>['status', 'severity'];
    for (final key in keys) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return 'watch';
  }

  String _operationalSeverityForItem(Map<String, dynamic> item) {
    final explicit = (item['severity'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    final status = _operationalStatusForItem(item);
    if (const <String>{
      'blocked',
      'hold',
      'escalate',
      'required',
      'missing',
      'now',
    }.contains(status)) {
      return 'high';
    }
    if (const <String>{
      'watch',
      'review',
      'today',
      'week',
      'pilot',
      'limited',
      'instrument',
      'experiment',
      'needs_instrumentation',
    }.contains(status)) {
      return 'medium';
    }
    return 'low';
  }

  bool _operationalMatchesFilter(Map<String, dynamic> item, String filter) {
    if (filter == 'all') return true;
    final status = _operationalStatusForItem(item);
    final severity = _operationalSeverityForItem(item);
    final dueMinutes = _intValue(item['due_in_minutes']);
    final steps = _strategicSteps(item);
    switch (filter) {
      case 'high':
        return severity == 'high';
      case 'blocked':
        return severity == 'high' ||
            const <String>{'blocked', 'hold', 'missing', 'required'}
                .contains(status);
      case 'watch':
        return severity == 'medium' ||
            const <String>{'watch', 'review', 'today', 'week'}.contains(status);
      case 'ready':
        return const <String>{
          'scale',
          'accelerate',
          'open',
          'approved',
          'healthy',
          'calm',
          'later',
        }.contains(status);
      case 'due':
        return dueMinutes > 0 && dueMinutes <= 1440 ||
            status == 'now' ||
            status == 'today';
      case 'steps':
        return steps.isNotEmpty;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredOperationalBoardItems(
    List<Map<String, dynamic>> items,
  ) {
    if (!_isOperationalBoardSurface || _operationalBoardFilter == 'all') {
      return items;
    }
    return items
        .where(
          (item) => _operationalMatchesFilter(item, _operationalBoardFilter),
        )
        .toList(growable: false);
  }

  int _operationalFilterCount(List<Map<String, dynamic>> items, String filter) {
    return items
        .where((item) => _operationalMatchesFilter(item, filter))
        .length;
  }

  String _operationalFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'ready':
        return 'Ready';
      case 'due':
        return 'Due';
      case 'steps':
        return 'Steps';
      case 'high':
        return 'High';
      default:
        return _labelForKey(filter);
    }
  }

  IconData _operationalFilterIcon(String filter) {
    switch (filter) {
      case 'all':
        return Icons.dashboard_customize_outlined;
      case 'high':
        return Icons.notification_important_outlined;
      case 'blocked':
        return Icons.block_outlined;
      case 'watch':
        return Icons.visibility_outlined;
      case 'ready':
        return Icons.task_alt_rounded;
      case 'due':
        return Icons.timer_outlined;
      case 'steps':
        return Icons.playlist_add_check_circle_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  IconData _operationalBoardIcon() {
    switch (widget.title.toLowerCase()) {
      case 'escalations':
        return Icons.priority_high_rounded;
      case 'sla board':
        return Icons.timer_outlined;
      case 'evidence board':
        return Icons.fact_check_outlined;
      case 'sync board':
        return Icons.sync_outlined;
      case 'quality board':
        return Icons.verified_outlined;
      case 'launch board':
        return Icons.rocket_launch_outlined;
      case 'growth board':
        return Icons.trending_up_outlined;
      default:
        return Icons.dashboard_customize_outlined;
    }
  }

  String _operationalBoardHeaderTitle() {
    switch (widget.title.toLowerCase()) {
      case 'escalations':
        return 'Escalation control';
      case 'sla board':
        return 'SLA control';
      case 'evidence board':
        return 'Evidence control';
      case 'sync board':
        return 'Sync control';
      case 'quality board':
        return 'Quality control';
      case 'launch board':
        return 'Launch control';
      case 'growth board':
        return 'Growth control';
      default:
        return 'Operational control';
    }
  }

  String _operationalAuthorityForItem(Map<String, dynamic> item) {
    for (final key in const <String>[
      'rollout_approval_state',
      'certification_state',
      'growth_readiness_state',
      'sync_status',
      'source_authority',
      'required_permission',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  int _operationalScoreForItem(Map<String, dynamic> item) {
    for (final key in const <String>[
      'quality_score',
      'average_score',
      'growth_signal',
      'source_authority_percent',
      'signal_count',
      'count',
    ]) {
      final value = _intValue(item[key]);
      if (value > 0) return value;
    }
    return 0;
  }

  String _operationalPrimaryLine(Map<String, dynamic> item) {
    for (final key in const <String>[
      'detail',
      'growth_goal',
      'next_growth_move',
      'release_gate',
      'evidence_gap',
      'evidence_required',
      'synced_when',
      'first_step',
      'done_when',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return _opsRunbookSummaryLine(item);
  }

  String _operationalGateLine(Map<String, dynamic> item) {
    for (final key in const <String>[
      'certification_gate',
      'approval_gate',
      'growth_gate',
      'decision_gate',
      'rollback_gate',
      'repair_gate',
      'sync_gate',
      'gate_state',
      'sla_label',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Object? _operationalStepTotal(Map<String, dynamic> summary) {
    for (final key in const <String>[
      'repair_steps_total',
      'certification_steps_total',
      'approval_steps_total',
      'growth_steps_total',
      'evidence_steps_total',
      'steps_total',
    ]) {
      final value = summary[key];
      if (_intValue(value) > 0) return value;
    }
    return null;
  }

  Color _controlStateColor(String status) {
    switch (status) {
      case 'action':
      case 'risk':
      case 'blocked':
      case 'high':
        return const Color(0xFFDC2626);
      case 'watch':
      case 'gap':
      case 'medium':
        return const Color(0xFFC2410C);
      case 'healthy':
      case 'mature':
      case 'open':
      case 'active':
        return const Color(0xFF0F766E);
      default:
        return widget.accent;
    }
  }

  IconData _controlStateIcon(String status) {
    switch (status) {
      case 'action':
      case 'risk':
      case 'blocked':
      case 'high':
        return Icons.notification_important_outlined;
      case 'watch':
      case 'gap':
      case 'medium':
        return Icons.visibility_outlined;
      case 'healthy':
      case 'mature':
      case 'open':
      case 'active':
        return Icons.task_alt_rounded;
      default:
        return Icons.radar_outlined;
    }
  }

  List<Map<String, dynamic>> _controlIntelligenceItems(
    Map<String, dynamic> data,
    String key, {
    int limit = 8,
  }) {
    return _listItems(data, <String>[key], limit: limit);
  }

  bool _runbookMatchesFilter(Map<String, dynamic> item, String filter) {
    if (filter == 'all') return true;
    final severity = (item['severity'] ?? 'low').toString().trim();
    final owner = (item['owner'] ?? '').toString().toLowerCase();
    switch (filter) {
      case 'high':
      case 'medium':
      case 'low':
        return severity == filter;
      case 'owner':
        return owner.isNotEmpty;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredRunbookItems(
    List<Map<String, dynamic>> items,
  ) {
    if (!_isRunbookSurface || _runbookFilter == 'all') return items;
    return items
        .where((item) => _runbookMatchesFilter(item, _runbookFilter))
        .toList(growable: false);
  }

  int _runbookFilterCount(List<Map<String, dynamic>> items, String filter) {
    return items.where((item) => _runbookMatchesFilter(item, filter)).length;
  }

  String _runbookFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'owner':
        return 'Owner';
      default:
        return _labelForKey(filter);
    }
  }

  IconData _runbookFilterIcon(String filter) {
    switch (filter) {
      case 'all':
        return Icons.rule_folder_outlined;
      case 'high':
        return Icons.notification_important_outlined;
      case 'medium':
        return Icons.visibility_outlined;
      case 'low':
        return Icons.task_alt_rounded;
      case 'owner':
        return Icons.assignment_ind_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  List<Map<String, dynamic>> _surfaceControlSourceItems(
    Map<String, dynamic> data,
  ) {
    final items = <Map<String, dynamic>>[];
    const sources = <MapEntry<String, String>>[
      MapEntry('top_programs', 'Mini Programs'),
      MapEntry('manifest_authorities_30d', 'Manifest authority'),
      MapEntry('top_accounts', 'Accounts'),
      MapEntry('top_campaigns', 'Campaigns'),
      MapEntry('top_offers', 'Offers'),
      MapEntry('top_packs', 'Sticker packs'),
      MapEntry('visibility_breakdown', 'Privacy scopes'),
      MapEntry('mini_program_embeds', 'Mini Program embeds'),
      MapEntry('tags', 'Friend tags'),
      MapEntry('profile_segments', 'Profiles'),
      MapEntry('kinds', 'Kinds'),
      MapEntry('sources', 'Sources'),
      MapEntry('segments', 'Segments'),
      MapEntry('domain_control_quality', 'Domain quality'),
      MapEntry('operations', 'Operations'),
      MapEntry('trip_statuses', 'Trip statuses'),
      MapEntry('driver_statuses', 'Driver statuses'),
      MapEntry('support_segments', 'Support'),
      MapEntry('dispatch_segments', 'Dispatch'),
      MapEntry('booking_states', 'Booking states'),
      MapEntry('ticket_states', 'Ticket states'),
      MapEntry('boarding_states', 'Boarding states'),
      MapEntry('feed_health', 'Feed health'),
      MapEntry('modules', 'Modules'),
      MapEntry('features', 'Features'),
      MapEntry('mini_programs', 'Mini Programs'),
      MapEntry('features_30d', 'Feature events'),
      MapEntry('recent_events', 'Recent events'),
      MapEntry('dashboard_actions', 'Action plan'),
      MapEntry('action_plan', 'Action plan'),
    ];
    for (final source in sources) {
      final raw = data[source.key];
      if (raw is! List) continue;
      for (final value in raw) {
        if (value is! Map) continue;
        items.add(<String, dynamic>{
          ...value.cast<String, dynamic>(),
          '_surface_section': source.value,
        });
      }
    }
    if (items.isEmpty) {
      final summary = _summaryData(data);
      final eventCount = _surfaceEventCount(summary);
      final inventoryCount = _surfaceInventoryCount(summary);
      items.add(<String, dynamic>{
        'title': _surfaceControlTitle(),
        'status': eventCount > 0 || inventoryCount > 0 ? 'active' : 'watch',
        'event_count': eventCount,
        'count': inventoryCount,
        'detail':
            'No live surface rows yet; keep instrumentation, ownership, and source authority visible.',
        '_surface_section': 'Summary',
      });
    }
    return items.take(28).toList(growable: false);
  }

  bool _truthySurfaceValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value > 0;
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return normalized == 'true' ||
        normalized == 'active' ||
        normalized == 'enabled' ||
        normalized == 'featured' ||
        normalized == 'official' ||
        normalized == 'visible' ||
        normalized == 'server_authoritative' ||
        normalized == 'client_authenticated';
  }

  String _surfaceStatusForItem(Map<String, dynamic> item) {
    for (final key in const <String>[
      'status',
      'state',
      'review_status',
      'source_authority',
      'manifest_authority',
    ]) {
      final raw = (item[key] ?? '').toString().trim();
      if (raw.isNotEmpty) return raw;
    }
    if (item.containsKey('active')) {
      return _truthySurfaceValue(item['active']) ? 'active' : 'inactive';
    }
    if (item.containsKey('enabled')) {
      return _truthySurfaceValue(item['enabled']) ? 'enabled' : 'disabled';
    }
    if (item.containsKey('visible')) {
      return _truthySurfaceValue(item['visible']) ? 'visible' : 'hidden';
    }
    if (item.containsKey('featured') && _truthySurfaceValue(item['featured'])) {
      return 'featured';
    }
    if (item.containsKey('official') && _truthySurfaceValue(item['official'])) {
      return 'official';
    }
    final segment = (item['segment'] ?? item['visibility_scope'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (segment.contains('revoked') ||
        segment.contains('expired') ||
        segment.contains('reported')) {
      return segment;
    }
    if (segment.contains('active') ||
        segment.contains('public') ||
        segment.contains('protected') ||
        segment.contains('tagged')) {
      return segment;
    }
    if (_surfaceScoreForItem(item) > 0) return 'active';
    return 'watch';
  }

  String _surfaceSeverityForItem(Map<String, dynamic> item) {
    final explicit = (item['severity'] ?? '').toString().trim();
    if (explicit == 'high' || explicit == 'medium' || explicit == 'low') {
      return explicit;
    }
    final status = _surfaceStatusForItem(item).toLowerCase();
    final source = (item['source_authority'] ?? '').toString().toLowerCase();
    if (source == 'unknown' || source == 'legacy') return 'high';
    if (status.contains('unknown') ||
        status.contains('legacy') ||
        status.contains('blocked') ||
        status.contains('expired') ||
        status.contains('revoked') ||
        status.contains('reported') ||
        status.contains('failed') ||
        status.contains('error')) {
      return 'high';
    }
    if (status.contains('inactive') ||
        status.contains('disabled') ||
        status.contains('hidden') ||
        status.contains('pending') ||
        status.contains('review') ||
        status.contains('watch') ||
        status.contains('stale')) {
      return 'medium';
    }
    return 'low';
  }

  bool _surfaceMatchesFilter(Map<String, dynamic> item, String filter) {
    if (filter == 'all') return true;
    final severity = _surfaceSeverityForItem(item);
    final status = _surfaceStatusForItem(item).toLowerCase();
    final source = (item['source_authority'] ?? '').toString().toLowerCase();
    switch (filter) {
      case 'high':
      case 'medium':
      case 'low':
        return severity == filter;
      case 'watch':
        return severity != 'low' ||
            status.contains('watch') ||
            status.contains('pending') ||
            status.contains('review');
      case 'active':
        return _truthySurfaceValue(item['active']) ||
            _truthySurfaceValue(item['enabled']) ||
            _truthySurfaceValue(item['featured']) ||
            _truthySurfaceValue(item['official']) ||
            _truthySurfaceValue(item['visible']) ||
            status == 'active' ||
            status == 'enabled' ||
            status == 'featured' ||
            _surfaceScoreForItem(item) > 0;
      case 'authority':
        return source == 'server_authoritative' ||
            source == 'client_authenticated' ||
            (item['manifest_authority'] ?? '').toString().trim().isNotEmpty;
      case 'events':
        return item.entries.any((entry) {
          final key = entry.key.toLowerCase();
          return (key.endsWith('events') ||
                  key.endsWith('events_30d') ||
                  key == 'event_count') &&
              _intValue(entry.value) > 0;
        });
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredSurfaceControlItems(
    List<Map<String, dynamic>> items,
  ) {
    if (!_isSurfaceControlSurface || _surfaceControlFilter == 'all') {
      return items;
    }
    return items
        .where((item) => _surfaceMatchesFilter(item, _surfaceControlFilter))
        .toList(growable: false);
  }

  int _surfaceFilterCount(List<Map<String, dynamic>> items, String filter) {
    return items.where((item) => _surfaceMatchesFilter(item, filter)).length;
  }

  String _surfaceFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'events':
        return 'Events';
      default:
        return _labelForKey(filter);
    }
  }

  IconData _surfaceFilterIcon(String filter) {
    switch (filter) {
      case 'all':
        return Icons.dashboard_customize_outlined;
      case 'watch':
        return Icons.visibility_outlined;
      case 'high':
        return Icons.notification_important_outlined;
      case 'medium':
        return Icons.timelapse_rounded;
      case 'low':
        return Icons.task_alt_rounded;
      case 'active':
        return Icons.bolt_outlined;
      case 'authority':
        return Icons.verified_user_outlined;
      case 'events':
        return Icons.query_stats_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  IconData _surfaceControlIcon() {
    final title = widget.title.toLowerCase();
    if (title.contains('mini-program')) return Icons.apps_outlined;
    if (title.contains('moments')) return Icons.dynamic_feed_outlined;
    if (title.contains('official accounts')) return Icons.verified_outlined;
    if (title.contains('channels')) return Icons.play_circle_outline_rounded;
    if (title.contains('contacts')) return Icons.groups_outlined;
    if (title.contains('discover')) return Icons.explore_outlined;
    if (title.contains('card')) return Icons.style_outlined;
    if (title.contains('sticker')) return Icons.emoji_emotions_outlined;
    if (title.contains('favorites')) return Icons.bookmark_border_rounded;
    if (title.contains('chat')) return Icons.chat_bubble_outline_rounded;
    if (title.contains('green paket')) return Icons.redeem_outlined;
    if (title.contains('payments'))
      return Icons.account_balance_wallet_outlined;
    if (title.contains('ride')) return Icons.local_taxi_outlined;
    if (title.contains('coach')) return Icons.directions_bus_outlined;
    if (title.contains('analytics')) return Icons.query_stats_outlined;
    return widget.icon;
  }

  String _surfaceControlTitle() {
    final title = widget.title.toLowerCase();
    if (title.contains('mini-program')) return 'Mini Program review';
    if (title.contains('moments')) return 'Moments';
    if (title.contains('official accounts')) return 'Official Accounts';
    if (title.contains('channels')) return 'Channels';
    if (title.contains('contacts')) return 'Contacts graph';
    if (title.contains('discover')) return 'Discover surface';
    if (title.contains('card')) return 'Cards and offers';
    if (title.contains('sticker')) return 'Sticker store';
    if (title.contains('favorites')) return 'Favorites';
    if (title.contains('chat')) return 'Chat preferences';
    if (title.contains('green paket')) return 'Green Paket';
    if (title.contains('payments')) return 'Payments';
    if (title.contains('ride')) return 'Ride';
    if (title.contains('coach')) return 'Coach';
    if (title.contains('analytics')) return 'Analytics authority';
    return widget.title;
  }

  int _surfaceScoreForItem(Map<String, dynamic> item) {
    for (final key in const <String>[
      'event_count',
      'events_30d',
      'usage_score',
      'usage_count',
      'views',
      'views_total',
      'likes',
      'likes_total',
      'followers',
      'follows_total',
      'comments',
      'comments_total',
      'feed_items',
      'feed_items_total',
      'embeds_30d',
      'embeds_total',
      'shelf_opens',
      'shelf_users',
      'versions',
      'pending_versions',
      'pair_count',
      'install_count',
      'holder_count',
      'claimed_count',
      'redeemed_count',
      'claims_30d',
      'profile_count',
      'item_count',
      'offer_count',
      'active_users_30d',
      'install_users',
      'inventory_total',
      'attestation_count',
      'account_count',
      'trip_count',
      'driver_count',
      'ticket_count',
      'booking_count',
      'boarding_count',
      'feed_count',
      'records_ingested',
      'tracking_events',
      'tracking_events_30d',
      'payment_events_30d',
      'ride_events_30d',
      'coach_events_30d',
      'signal_count',
      'count',
    ]) {
      final value = _intValue(item[key]);
      if (value > 0) return value;
    }
    return 0;
  }

  int _summaryCountForKeys(
    Map<String, dynamic> summary,
    List<String> keys,
  ) {
    var total = 0;
    for (final key in keys) {
      total += _intValue(summary[key]);
    }
    return total;
  }

  int _surfaceInventoryCount(Map<String, dynamic> summary) {
    final direct = _summaryCountForKeys(summary, const <String>[
      'offers_total',
      'packs_total',
      'campaigns_total',
      'programs_total',
      'accounts_total',
      'posts_total',
      'items_total',
      'contact_edges_total',
      'invites_total',
      'friend_tags_total',
      'nearby_profiles_total',
      'favorites_total',
      'attestations_total',
      'trips_total',
      'drivers_total',
      'bookings_total',
      'tickets_total',
      'total_events',
    ]);
    if (direct > 0) return direct;
    return _summaryCountForKeys(summary, const <String>[
      'conversation_prefs_total',
      'group_prefs_total',
      'items_total',
    ]);
  }

  int _surfaceActiveCount(Map<String, dynamic> summary) {
    final direct = _summaryCountForKeys(summary, const <String>[
      'active_offers',
      'enabled_packs',
      'campaigns_active',
      'enabled_programs',
      'published_programs',
      'official_programs',
      'verified_accounts',
      'featured_accounts',
      'active_campaigns',
      'public_posts',
      'protected_posts',
      'active_authors_30d',
      'active_contact_edges',
      'active_contact_edges_30d',
      'active_invites',
      'nearby_visible_profiles',
      'active_saving_accounts_30d',
      'active_users',
      'active_challenges',
      'active_trips',
      'online_drivers',
      'active_bookings',
      'active_tickets',
      'server_authoritative_events',
      'client_authenticated_events',
    ]);
    if (direct > 0) return direct;
    return _summaryCountForKeys(summary, const <String>[
      'pinned_conversations',
      'pinned_groups',
      'starred_conversations',
    ]);
  }

  int _surfaceEventCount(Map<String, dynamic> summary) {
    return _summaryCountForKeys(summary, const <String>[
      'total_events',
      'platform_events_30d',
      'discover_events_30d',
      'card_events_30d',
      'store_events_30d',
      'open_events_30d',
      'review_events_30d',
      'shelf_events_30d',
      'release_seen_events_30d',
      'posts_30d',
      'mini_program_posts_30d',
      'friend_tags_sync_events_30d',
      'feed_items_30d',
      'accounts_30d',
      'items_30d',
      'contact_edges_30d',
      'invites_created_30d',
      'invites_redeemed_30d',
      'favorites_events_30d',
      'chat_pref_events_30d',
      'admin_events_30d',
      'mini_program_events_30d',
      'claim_events_30d',
      'redeem_events_30d',
      'save_events_30d',
      'delete_events_30d',
      'attestations_30d',
      'consumed_30d',
      'payment_events_30d',
      'trips_30d',
      'ride_events_30d',
      'tracking_events_30d',
      'bookings_30d',
      'boarding_events_30d',
      'boarding_exceptions_30d',
      'coach_events_30d',
    ]);
  }

  int _surfaceAuthorityPercent(
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> authorities,
  ) {
    final explicit = _intValue(summary['source_authority_percent']);
    if (explicit > 0) return explicit.clamp(0, 100).toInt();
    final totalEvents = _intValue(summary['total_events']);
    final trustedEvents = _summaryCountForKeys(summary, const <String>[
      'server_authoritative_events',
      'client_authenticated_events',
    ]);
    if (totalEvents > 0) {
      return ((trustedEvents * 100) / totalEvents)
          .round()
          .clamp(0, 100)
          .toInt();
    }
    final total = authorities.fold<int>(
      0,
      (sum, item) => sum + _intValue(item['event_count']),
    );
    final trusted = authorities.fold<int>(0, (sum, item) {
      final source = (item['source_authority'] ?? '').toString();
      if (source == 'server_authoritative' ||
          source == 'client_authenticated') {
        return sum + _intValue(item['event_count']);
      }
      return sum;
    });
    if (total <= 0) return 100;
    return ((trusted * 100) / total).round().clamp(0, 100).toInt();
  }

  String _surfacePrimaryLine(Map<String, dynamic> item) {
    final parts = <String>[];
    for (final key in const <String>[
      '_surface_section',
      'detail',
      'official_name',
      'title_en',
      'creator_display_name',
      'category_en',
      'category',
      'discount_text',
      'kind',
      'segment',
      'visibility_scope',
      'tag',
      'source_module',
      'module_id',
      'feature_key',
      'action',
      'mini_program_id',
      'app_id',
      'manifest_authority',
      'source_authority',
      'created_at',
    ]) {
      final raw = (item[key] ?? '').toString().trim();
      if (raw.isEmpty) continue;
      parts.add(key == '_surface_section' ? raw : '${_labelForKey(key)}: $raw');
      if (parts.length >= 3) break;
    }
    return parts.join(' · ');
  }

  Future<void> _postIncidentAction(
    Map<String, dynamic> item,
    String action, {
    String? note,
    String? incidentCommanderAccountId,
    String? ownerAccountId,
    String? ownerTeam,
    String? snoozedUntil,
  }) async {
    final incidentId = (item['id'] ?? '').toString().trim();
    if (incidentId.isEmpty) return;
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>[
        'admin',
        'dashboards',
        'incidents',
        incidentId,
        'action',
      ],
    );
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_opsInvalidServerUrlMessage(context))),
      );
      return;
    }
    final client = shamellHttpClient();
    try {
      final headers = await shamellSessionHeadersForBaseUrl(widget.baseUrl);
      headers['Content-Type'] = 'application/json';
      headers['Idempotency-Key'] =
          'control-incident-$incidentId-$action-${DateTime.now().microsecondsSinceEpoch}';
      final response = await client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(<String, Object?>{
              'action': action,
              if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
              if ((incidentCommanderAccountId ?? '').trim().isNotEmpty)
                'incident_commander_account_id':
                    incidentCommanderAccountId!.trim(),
              if ((ownerAccountId ?? '').trim().isNotEmpty)
                'owner_account_id': ownerAccountId!.trim(),
              if ((ownerTeam ?? '').trim().isNotEmpty)
                'owner_team': ownerTeam!.trim(),
              if ((snoozedUntil ?? '').trim().isNotEmpty)
                'snoozed_until': snoozedUntil!.trim(),
            }),
          )
          .timeout(_opsRequestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sanitizeHttpError(
                statusCode: response.statusCode,
                rawBody: response.body,
                isArabic: L10n.of(context).isArabic,
              ),
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Incident ${action.replaceAll('_', ' ')}')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sanitizeExceptionForUi(
              error: error,
              isArabic: L10n.of(context).isArabic,
            ),
          ),
        ),
      );
    } finally {
      client.close();
    }
  }

  Future<void> _showIncidentActionDialog(
    Map<String, dynamic> item,
    String action,
  ) async {
    final noteController = TextEditingController();
    final commanderController = TextEditingController(
      text: (item['incident_commander_account_id'] ?? '').toString(),
    );
    final ownerController = TextEditingController(
      text: (item['owner_account_id'] ?? '').toString(),
    );
    final teamController = TextEditingController(
      text: (item['owner_team'] ?? '').toString(),
    );
    final snoozedUntilController = TextEditingController(
      text: action == 'snooze'
          ? DateTime.now()
              .toUtc()
              .add(const Duration(hours: 4))
              .toIso8601String()
          : '',
    );
    try {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          final isAssign = action == 'assign';
          final isSnooze = action == 'snooze';
          return AlertDialog(
            title: Text('${_labelForKey(action)} incident'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _itemTitle(item),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isAssign) ...[
                    TextField(
                      controller: commanderController,
                      decoration: const InputDecoration(
                        labelText: 'Incident commander account',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: ownerController,
                      decoration: const InputDecoration(
                        labelText: 'Owner account',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: teamController,
                      decoration:
                          const InputDecoration(labelText: 'Owner team'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (isSnooze) ...[
                    TextField(
                      controller: snoozedUntilController,
                      decoration: const InputDecoration(
                        labelText: 'Snoozed until',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Note'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(<String, String>{
                  'note': noteController.text.trim(),
                  'incident_commander_account_id':
                      commanderController.text.trim(),
                  'owner_account_id': ownerController.text.trim(),
                  'owner_team': teamController.text.trim(),
                  'snoozed_until': snoozedUntilController.text.trim(),
                }),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (result == null) return;
      await _postIncidentAction(
        item,
        action,
        note: result['note'],
        incidentCommanderAccountId: result['incident_commander_account_id'],
        ownerAccountId: result['owner_account_id'],
        ownerTeam: result['owner_team'],
        snoozedUntil: result['snoozed_until'],
      );
    } finally {
      noteController.dispose();
      commanderController.dispose();
      ownerController.dispose();
      teamController.dispose();
      snoozedUntilController.dispose();
    }
  }

  Future<void> _showIncidentTimelineSheet(Map<String, dynamic> item) async {
    final incidentId = (item['id'] ?? '').toString().trim();
    if (incidentId.isEmpty) return;
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: const <String>[
        'admin',
        'dashboards',
        'incidents',
        'timeline',
      ],
      queryParameters: <String, String>{
        'incident_id': incidentId,
        'limit': '50',
      },
    );
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_opsInvalidServerUrlMessage(context))),
      );
      return;
    }
    final client = shamellHttpClient();
    try {
      final response = await client
          .get(
            uri,
            headers: await shamellSessionHeadersForBaseUrl(widget.baseUrl),
          )
          .timeout(_opsRequestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sanitizeHttpError(
                statusCode: response.statusCode,
                rawBody: response.body,
                isArabic: L10n.of(context).isArabic,
              ),
            ),
          ),
        );
        return;
      }
      final decoded = jsonDecode(response.body);
      final payload = decoded is Map
          ? decoded.cast<String, dynamic>()
          : const <String, dynamic>{};
      final events = (payload['events'] as List? ?? const [])
          .whereType<Map>()
          .map((event) => event.cast<String, dynamic>())
          .toList(growable: false);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _incidentTimelineSheet(context, item, events),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sanitizeExceptionForUi(
              error: error,
              isArabic: L10n.of(context).isArabic,
            ),
          ),
        ),
      );
    } finally {
      client.close();
    }
  }

  Widget _incidentTimelineSheet(
    BuildContext context,
    Map<String, dynamic> item,
    List<Map<String, dynamic>> events,
  ) {
    final theme = Theme.of(context);
    final status = (item['workflow_status'] ??
            item['incident_status'] ??
            item['status'] ??
            'active')
        .toString();
    final color = _incidentWorkflowColor(status);
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        minChildSize: .42,
        maxChildSize: .92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Icon(Icons.manage_history_rounded, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _itemTitle(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _incidentStatusPill(item),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${events.length} timeline event(s)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5A6F66),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (events.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: .12)),
                ),
                child: Text(
                  'No audit events yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5A6F66),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              ...events.map((event) {
                final action = (event['action'] ?? '').toString();
                final workflow = (event['workflow_status'] ?? '').toString();
                final eventColor = _incidentWorkflowColor(workflow);
                final note = (event['note'] ?? '').toString();
                final actor = (event['actor_account_id'] ?? '').toString();
                final createdAt = (event['created_at'] ?? '').toString();
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: eventColor.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: eventColor.withValues(alpha: .14),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_incidentWorkflowIcon(workflow), color: eventColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_labelForKey(action)} · ${_labelForKey(workflow)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (actor.isNotEmpty || createdAt.isNotEmpty)
                              Text(
                                [
                                  if (actor.isNotEmpty) actor,
                                  if (createdAt.isNotEmpty) createdAt,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: eventColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            if (note.isNotEmpty)
                              Text(
                                note,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6F66),
                                  height: 1.35,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Color _incidentWorkflowColor(String status) {
    switch (status) {
      case 'active':
      case 'critical':
        return const Color(0xFFDC2626);
      case 'triage':
      case 'assigned':
      case 'acknowledged':
        return const Color(0xFFC2410C);
      case 'monitoring':
      case 'snoozed':
        return const Color(0xFF2563EB);
      case 'resolved':
        return const Color(0xFF0F766E);
      default:
        return widget.accent;
    }
  }

  Color _incidentCommandHealthColor(String health) {
    switch (health) {
      case 'critical':
        return const Color(0xFFDC2626);
      case 'attention':
        return const Color(0xFFC2410C);
      case 'watch':
        return const Color(0xFF2563EB);
      case 'resolved':
        return const Color(0xFF0F766E);
      default:
        return widget.accent;
    }
  }

  IconData _incidentCommandHealthIcon(String health) {
    switch (health) {
      case 'critical':
        return Icons.notification_important_outlined;
      case 'attention':
        return Icons.priority_high_rounded;
      case 'watch':
        return Icons.visibility_outlined;
      case 'resolved':
        return Icons.task_alt_rounded;
      default:
        return Icons.health_and_safety_outlined;
    }
  }

  Color _commandStateColor(String state) {
    switch (state) {
      case 'executive_command_required':
      case 'executive_command':
        return const Color(0xFFDC2626);
      case 'owner_command_required':
      case 'owner_command':
        return const Color(0xFFC2410C);
      case 'control_watch':
      case 'watch':
        return const Color(0xFF2563EB);
      case 'closure_monitor':
      case 'clear':
      case 'resolved':
      case 'healthy':
        return const Color(0xFF0F766E);
      default:
        return widget.accent;
    }
  }

  IconData _commandStateIcon(String state) {
    switch (state) {
      case 'executive_command_required':
      case 'executive_command':
        return Icons.notification_important_outlined;
      case 'owner_command_required':
      case 'owner_command':
        return Icons.assignment_ind_outlined;
      case 'control_watch':
      case 'watch':
        return Icons.visibility_outlined;
      case 'closure_monitor':
        return Icons.manage_history_rounded;
      case 'clear':
      case 'resolved':
      case 'healthy':
        return Icons.task_alt_rounded;
      default:
        return Icons.outbound_outlined;
    }
  }

  String _incidentResponseBucketLabel(String bucket) {
    switch (bucket) {
      case 'page_now':
        return 'Page now';
      case 'due_soon':
        return 'Due soon';
      case 'watch_window':
        return 'Watch';
      case 'closed':
        return 'Closed';
      default:
        return _labelForKey(bucket);
    }
  }

  Color _incidentResponseBucketColor(String bucket) {
    switch (bucket) {
      case 'page_now':
        return const Color(0xFFDC2626);
      case 'due_soon':
        return const Color(0xFFC2410C);
      case 'watch_window':
        return const Color(0xFF2563EB);
      case 'closed':
        return const Color(0xFF0F766E);
      default:
        return widget.accent;
    }
  }

  IconData _incidentResponseBucketIcon(String bucket) {
    switch (bucket) {
      case 'page_now':
        return Icons.notification_important_outlined;
      case 'due_soon':
        return Icons.timer_outlined;
      case 'watch_window':
        return Icons.visibility_outlined;
      case 'closed':
        return Icons.task_alt_rounded;
      default:
        return Icons.speed_rounded;
    }
  }

  Widget _incidentResponseBucketPill(String bucket) {
    final normalized = bucket.trim().isEmpty ? 'due_soon' : bucket.trim();
    final color = _incidentResponseBucketColor(normalized);
    return Tooltip(
      message: _incidentResponseBucketLabel(normalized),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 112),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_incidentResponseBucketIcon(normalized),
                color: color, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _incidentResponseBucketLabel(normalized),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _incidentCommandHealthPill(Map<String, dynamic> item) {
    final health = (item['command_health'] ?? 'attention').toString();
    final action = (item['recommended_action'] ?? '').toString().trim();
    final color = _incidentCommandHealthColor(health);
    return Tooltip(
      message: action.isEmpty ? _labelForKey(health) : action,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 126),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_incidentCommandHealthIcon(health), color: color, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _labelForKey(health),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _incidentWorkflowIcon(String status) {
    switch (status) {
      case 'active':
      case 'critical':
        return Icons.crisis_alert_outlined;
      case 'triage':
      case 'assigned':
        return Icons.assignment_ind_outlined;
      case 'acknowledged':
        return Icons.done_all_rounded;
      case 'monitoring':
      case 'snoozed':
        return Icons.schedule_rounded;
      case 'resolved':
        return Icons.task_alt_rounded;
      default:
        return Icons.track_changes_outlined;
    }
  }

  Widget _incidentStatusPill(Map<String, dynamic> item) {
    final status = (item['workflow_status'] ??
            item['incident_status'] ??
            item['status'] ??
            'active')
        .toString();
    final color = _incidentWorkflowColor(status);
    final events = _intValue(item['timeline_event_count']);
    return Tooltip(
      message: events > 0 ? '$events timeline event(s)' : _labelForKey(status),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 116),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_incidentWorkflowIcon(status), color: color, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                events > 0
                    ? '${_labelForKey(status)} · $events'
                    : _labelForKey(status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _incidentFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'acknowledged':
        return 'Ack';
      default:
        return _labelForKey(filter);
    }
  }

  IconData _incidentFilterIcon(String filter) {
    switch (filter) {
      case 'all':
        return Icons.all_inbox_outlined;
      case 'critical':
        return Icons.notification_important_outlined;
      case 'attention':
        return Icons.priority_high_rounded;
      case 'watch':
        return Icons.visibility_outlined;
      case 'active':
        return Icons.crisis_alert_outlined;
      case 'assigned':
        return Icons.assignment_ind_outlined;
      case 'acknowledged':
        return Icons.done_all_rounded;
      case 'snoozed':
        return Icons.schedule_rounded;
      case 'resolved':
        return Icons.task_alt_rounded;
      case 'unclaimed':
        return Icons.person_off_outlined;
      default:
        return Icons.tune_rounded;
    }
  }

  Widget _incidentMetricChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Object? value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label · $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _incidentWorkflowControlPanel(
    BuildContext context,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> allItems,
  ) {
    final theme = Theme.of(context);
    const filters = <String>[
      'all',
      'critical',
      'attention',
      'watch',
      'active',
      'assigned',
      'acknowledged',
      'snoozed',
      'resolved',
      'unclaimed',
    ];
    final selected = filters.contains(_incidentWorkflowFilter)
        ? _incidentWorkflowFilter
        : 'all';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Incident command',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${_incidentFilterCount(allItems, selected)} shown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if ((summary['primary_recommended_action'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary['primary_recommended_action'].toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _incidentCommandHealthColor(
                  (summary['primary_command_health'] ?? 'attention').toString(),
                ),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: filters
                  .map(
                    (filter) => ButtonSegment<String>(
                      value: filter,
                      icon: Icon(_incidentFilterIcon(filter), size: 16),
                      label: Text(
                        '${_incidentFilterLabel(filter)} ${_incidentFilterCount(allItems, filter)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <String>{selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() {
                  _incidentWorkflowFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: _incidentResponseBucketIcon('page_now'),
                label: _incidentResponseBucketLabel('page_now'),
                value: summary['response_page_now'] ?? 0,
                color: _incidentResponseBucketColor('page_now'),
              ),
              _incidentMetricChip(
                context,
                icon: _incidentResponseBucketIcon('due_soon'),
                label: _incidentResponseBucketLabel('due_soon'),
                value: summary['response_due_soon'] ?? 0,
                color: _incidentResponseBucketColor('due_soon'),
              ),
              _incidentMetricChip(
                context,
                icon: _incidentResponseBucketIcon('watch_window'),
                label: _incidentResponseBucketLabel('watch_window'),
                value: summary['response_watch_window'] ?? 0,
                color: _incidentResponseBucketColor('watch_window'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: Icons.notification_important_outlined,
                label: 'Critical',
                value: summary['command_critical'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.outbound_outlined,
                label: 'Escalate',
                value: summary['escalation_required'] ?? 0,
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.pending_actions_outlined,
                label: 'Open',
                value: summary['open_workflows'] ?? allItems.length,
                color: widget.accent,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.person_off_outlined,
                label: 'Unclaimed',
                value: summary['unclaimed'] ??
                    _incidentFilterCount(allItems, 'unclaimed'),
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.timer_outlined,
                label: 'SLA',
                value: summary['sla_due_soon'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.manage_history_rounded,
                label: 'Timeline',
                value: summary['timeline_events_total'] ?? 0,
                color: const Color(0xFF2563EB),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.verified_user_outlined,
                label: 'Authority',
                value: summary['server_authoritative_actions'] ?? 0,
                color: const Color(0xFF047857),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _incidentCommandQueuePanel(
    BuildContext context,
    List<Map<String, dynamic>> queue,
  ) {
    final theme = Theme.of(context);
    if (queue.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.outbound_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Command queue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${queue.length} priority',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...queue.map((item) {
            final health = (item['command_health'] ?? 'attention').toString();
            final color = _incidentCommandHealthColor(health);
            final action = (item['recommended_action'] ?? '').toString().trim();
            final tier = (item['escalation_tier'] ?? '').toString().trim();
            final nextMinutes = _intValue(item['next_response_minutes']);
            final timelineEvents = _intValue(item['timeline_event_count']);
            final rank = _intValue(item['queue_rank']);
            final responseBucket =
                (item['response_bucket'] ?? 'due_soon').toString().trim();
            final meta = [
              if (tier.isNotEmpty) _labelForKey(tier),
              if (responseBucket.isNotEmpty)
                _incidentResponseBucketLabel(responseBucket),
              if (nextMinutes > 0) '${nextMinutes}m',
              if (timelineEvents > 0) '$timelineEvents event(s)',
            ].join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => unawaited(_showIncidentTimelineSheet(item)),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 7),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(13),
                            border:
                                Border.all(color: color.withValues(alpha: .16)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                rank > 0 ? '#$rank' : 'Q',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Icon(_incidentCommandHealthIcon(health),
                                  color: color, size: 18),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _itemTitle(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (action.isNotEmpty)
                                Text(
                                  action,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                    height: 1.3,
                                  ),
                                ),
                              if (meta.isNotEmpty)
                                Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF5A6F66),
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _incidentResponseBucketPill(responseBucket),
                        const SizedBox(width: 4),
                        _incidentActionMenu(item),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _controlIntelligencePosturePanel(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final theme = Theme.of(context);
    final status = (data['status'] ?? 'watch').toString().trim();
    final color = _controlStateColor(status);
    final posture =
        (data['operating_posture'] ?? 'Control posture').toString().trim();
    final detail = (data['posture_detail'] ?? '').toString().trim();
    final score = _intValue(data['operational_score']);
    final attention = _intValue(data['attention_total']);
    final authority = _intValue(data['source_authority_percent']);
    final sla = _intValue(data['attention_sla_minutes']);
    final laneSummary = data['lane_summary'];
    final actionLanes =
        laneSummary is Map ? _intValue(laneSummary['action']) : 0;
    final gateSummary = data['gate_summary'];
    final blockedGates =
        gateSummary is Map ? _intValue(gateSummary['blocked']) : 0;
    final readiness = data['ecosystem_readiness'];
    final readinessScore = readiness is Map ? _intValue(readiness['score']) : 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_controlStateIcon(status), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      posture.isEmpty ? 'Control posture' : posture,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF17362B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _labelForKey(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$score',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5A6F66),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: Icons.speed_rounded,
                label: 'Score',
                value: score,
                color: color,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.priority_high_rounded,
                label: 'Attention',
                value: attention,
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.verified_user_outlined,
                label: 'Authority',
                value: '$authority%',
                color: const Color(0xFF0F766E),
              ),
              if (sla > 0)
                _incidentMetricChip(
                  context,
                  icon: Icons.timer_outlined,
                  label: 'SLA',
                  value: '${sla}m',
                  color: color,
                ),
              _incidentMetricChip(
                context,
                icon: Icons.view_column_outlined,
                label: 'Action lanes',
                value: actionLanes,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.lock_outline_rounded,
                label: 'Blocked gates',
                value: blockedGates,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.eco_outlined,
                label: 'Readiness',
                value: readinessScore,
                color: widget.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _controlIntelligenceLine(Map<String, dynamic> item) {
    for (final key in const <String>[
      'detail',
      'objective',
      'decision',
      'unlock_criteria',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Widget _controlIntelligencePanel(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required String statusKey,
    String countKey = 'signal_count',
  }) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$title · ${items.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final status = (item[statusKey] ?? item['status'] ?? 'watch')
                .toString()
                .trim();
            final color = _controlStateColor(status);
            final route = (item['dashboard_route'] ?? '').toString().trim();
            final line = _controlIntelligenceLine(item);
            final count = _intValue(item[countKey]);
            final owner = (item['owner'] ?? '').toString().trim();
            final cadence = (item['review_cadence'] ?? '').toString().trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: route.isEmpty
                      ? null
                      : () => unawaited(
                            _openControlDashboardBackendRoute(
                              context,
                              baseUrl: widget.baseUrl,
                              dashboardRoute: route,
                            ),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(_controlStateIcon(status), color: color),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _itemTitle(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                [
                                  _labelForKey(status),
                                  if (owner.isNotEmpty) owner,
                                  if (cadence.isNotEmpty) cadence,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  height: 1.3,
                                ),
                              ),
                              if (line.isNotEmpty)
                                Text(
                                  line,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF5A6F66),
                                    height: 1.35,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$count',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _runbookControlPanel(
    BuildContext context,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> owners,
    List<Map<String, dynamic>> allItems,
  ) {
    final theme = Theme.of(context);
    const filters = <String>['all', 'high', 'medium', 'low', 'owner'];
    final selected = filters.contains(_runbookFilter) ? _runbookFilter : 'all';
    final high = _intValue(summary['high']);
    final medium = _intValue(summary['medium']);
    final color = high > 0
        ? const Color(0xFFDC2626)
        : medium > 0
            ? const Color(0xFFC2410C)
            : widget.accent;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_folder_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Runbook control',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${_runbookFilterCount(allItems, selected)} shown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: filters
                  .map(
                    (filter) => ButtonSegment<String>(
                      value: filter,
                      icon: Icon(_runbookFilterIcon(filter), size: 16),
                      label: Text(
                        '${_runbookFilterLabel(filter)} ${_runbookFilterCount(allItems, filter)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <String>{selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() {
                  _runbookFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: Icons.rule_folder_outlined,
                label: 'Runbooks',
                value: summary['runbooks_total'] ?? allItems.length,
                color: color,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.notification_important_outlined,
                label: 'High',
                value: summary['high'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.visibility_outlined,
                label: 'Medium',
                value: summary['medium'] ?? 0,
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.groups_outlined,
                label: 'Owners',
                value: summary['owners_total'] ?? owners.length,
                color: const Color(0xFF0F766E),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _runbookItemsPanel(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Runbook queue · ${items.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _runbookFilterLabel(_runbookFilter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final severity = (item['severity'] ?? 'low').toString().trim();
            final color = _severityColor(severity);
            final owner = (item['owner'] ?? '').toString().trim();
            final cadence = (item['review_cadence'] ?? '').toString().trim();
            final permission =
                (item['required_permission'] ?? '').toString().trim();
            final route = (item['dashboard_route'] ?? '').toString().trim();
            final cta =
                (item['cta_label'] ?? 'Open owner board').toString().trim();
            final lines = <String>[
              (item['first_step'] ?? '').toString().trim(),
              (item['evidence'] ?? '').toString().trim(),
              (item['done_when'] ?? '').toString().trim(),
              (item['escalation'] ?? '').toString().trim(),
            ].where((line) => line.isNotEmpty).take(3).toList(growable: false);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: route.isEmpty
                      ? null
                      : () => unawaited(
                            _openControlDashboardBackendRoute(
                              context,
                              baseUrl: widget.baseUrl,
                              dashboardRoute: route,
                            ),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _severityIcon(severity),
                                color: color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _itemTitle(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFF17362B),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    [
                                      if (owner.isNotEmpty) owner,
                                      if (cadence.isNotEmpty) cadence,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (route.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 112),
                                child: Text(
                                  cta.isEmpty ? 'Open board' : cta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _incidentMetricChip(
                              context,
                              icon: _severityIcon(severity),
                              label: 'Severity',
                              value: _labelForKey(severity),
                              color: color,
                            ),
                            if (permission.isNotEmpty)
                              _incidentMetricChip(
                                context,
                                icon: Icons.admin_panel_settings_outlined,
                                label: 'Scope',
                                value: _labelForKey(permission),
                                color: const Color(0xFF0F766E),
                              ),
                          ],
                        ),
                        ...lines.map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              line,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF5A6F66),
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _surfaceControlPanel(
    BuildContext context,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> authorities,
    List<Map<String, dynamic>> allItems,
  ) {
    final theme = Theme.of(context);
    const filters = <String>[
      'all',
      'watch',
      'high',
      'medium',
      'active',
      'authority',
      'events',
    ];
    final selected =
        filters.contains(_surfaceControlFilter) ? _surfaceControlFilter : 'all';
    final authorityPercent = _surfaceAuthorityPercent(summary, authorities);
    final watch = _surfaceFilterCount(allItems, 'watch');
    final high = _surfaceFilterCount(allItems, 'high');
    final color = high > 0
        ? const Color(0xFFDC2626)
        : watch > 0
            ? const Color(0xFFC2410C)
            : widget.accent;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_surfaceControlIcon(), color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_surfaceControlTitle()} control',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF17362B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$authorityPercent% source authority',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_surfaceFilterCount(allItems, selected)} shown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: filters
                  .map(
                    (filter) => ButtonSegment<String>(
                      value: filter,
                      icon: Icon(_surfaceFilterIcon(filter), size: 16),
                      label: Text(
                        '${_surfaceFilterLabel(filter)} ${_surfaceFilterCount(allItems, filter)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <String>{selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() {
                  _surfaceControlFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: _surfaceControlIcon(),
                label: 'Items',
                value: allItems.length,
                color: color,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.inventory_2_outlined,
                label: 'Inventory',
                value: _surfaceInventoryCount(summary),
                color: widget.accent,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.bolt_outlined,
                label: 'Active',
                value: _surfaceActiveCount(summary),
                color: const Color(0xFF0F766E),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.query_stats_outlined,
                label: 'Events',
                value: _surfaceEventCount(summary),
                color: const Color(0xFF2563EB),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.verified_user_outlined,
                label: 'Authority',
                value: '$authorityPercent%',
                color: authorityPercent < 70
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF047857),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _surfaceControlItemsPanel(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_surfaceControlIcon(), color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Surface queue · ${items.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _surfaceFilterLabel(_surfaceControlFilter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final severity = _surfaceSeverityForItem(item);
            final status = _surfaceStatusForItem(item);
            final color = _severityColor(severity);
            final line = _surfacePrimaryLine(item);
            final score = _surfaceScoreForItem(item);
            final section =
                (item['_surface_section'] ?? 'Surface').toString().trim();
            final route = (item['dashboard_route'] ?? '').toString().trim();
            final cta = (item['cta_label'] ?? 'Open board').toString().trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: route.isEmpty
                      ? null
                      : () => unawaited(
                            _openControlDashboardBackendRoute(
                              context,
                              baseUrl: widget.baseUrl,
                              dashboardRoute: route,
                            ),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _surfaceControlIcon(),
                                color: color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _itemTitle(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFF17362B),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (line.isNotEmpty)
                                    Text(
                                      line,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF5A6F66),
                                        fontWeight: FontWeight.w700,
                                        height: 1.35,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (route.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 112),
                                child: Text(
                                  cta.isEmpty ? 'Open board' : cta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _incidentMetricChip(
                              context,
                              icon: Icons.layers_outlined,
                              label: 'Lane',
                              value: section,
                              color: color,
                            ),
                            _incidentMetricChip(
                              context,
                              icon: _surfaceFilterIcon(severity),
                              label: 'State',
                              value: _labelForKey(status),
                              color: color,
                            ),
                            if (score > 0)
                              _incidentMetricChip(
                                context,
                                icon: Icons.query_stats_outlined,
                                label: 'Signal',
                                value: score,
                                color: const Color(0xFF2563EB),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _controlInboxTriagePanel(
    BuildContext context,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> allItems,
  ) {
    final theme = Theme.of(context);
    const filters = <String>[
      'all',
      'high',
      'medium',
      'low',
      'due',
      'attention',
      'permission',
    ];
    final selected =
        filters.contains(_controlInboxFilter) ? _controlInboxFilter : 'all';
    final high = _intValue(summary['high']);
    final medium = _intValue(summary['medium']);
    final color = high > 0
        ? const Color(0xFFDC2626)
        : medium > 0
            ? const Color(0xFFC2410C)
            : widget.accent;
    final primaryTitle = (summary['primary_title'] ?? '').toString().trim();
    final primaryOwner = (summary['primary_owner'] ?? '').toString().trim();
    final dueMinutes = _intValue(summary['due_in_minutes']);
    final detail = [
      if (primaryTitle.isNotEmpty) primaryTitle,
      if (primaryOwner.isNotEmpty) primaryOwner,
      if (dueMinutes > 0) 'due ${dueMinutes}m',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.all_inbox_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Control triage',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF17362B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF5A6F66),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${_controlInboxFilterCount(allItems, selected)} shown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: filters
                  .map(
                    (filter) => ButtonSegment<String>(
                      value: filter,
                      icon: Icon(_controlInboxFilterIcon(filter), size: 16),
                      label: Text(
                        '${_controlInboxFilterLabel(filter)} ${_controlInboxFilterCount(allItems, filter)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <String>{selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() {
                  _controlInboxFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: Icons.all_inbox_outlined,
                label: 'Items',
                value: summary['total'] ?? allItems.length,
                color: color,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.priority_high_rounded,
                label: 'Attention',
                value: summary['attention'] ?? 0,
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.notification_important_outlined,
                label: 'High',
                value: summary['high'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.timelapse_rounded,
                label: 'Medium',
                value: summary['medium'] ?? 0,
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.groups_outlined,
                label: 'Owners',
                value: summary['owners_total'] ?? 0,
                color: const Color(0xFF0F766E),
              ),
              if (dueMinutes > 0)
                _incidentMetricChip(
                  context,
                  icon: Icons.timer_outlined,
                  label: 'Due',
                  value: '${dueMinutes}m',
                  color: color,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlInboxItemsPanel(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Triage queue · ${items.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _controlInboxFilterLabel(_controlInboxFilter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final title = (item['title'] ?? '').toString().trim();
            final detail = (item['detail'] ?? '').toString().trim();
            final owner = (item['owner'] ?? '').toString().trim();
            final source = (item['source'] ?? '').toString().trim();
            final status = (item['status'] ?? '').toString().trim();
            final severity =
                (item['severity'] ?? 'low').toString().trim().isEmpty
                    ? 'low'
                    : (item['severity'] ?? 'low').toString().trim();
            final signalCount = _intValue(item['signal_count']);
            final rank = _intValue(item['rank']);
            final cadence = (item['review_cadence'] ?? '').toString().trim();
            final permission =
                (item['required_permission'] ?? '').toString().trim();
            final dueMinutes = _intValue(item['due_in_minutes']);
            final sla = (item['sla_label'] ?? '').toString().trim();
            final cta = (item['cta_label'] ?? 'Open board').toString().trim();
            final route = (item['dashboard_route'] ?? '').toString().trim();
            final runbookLine = _opsRunbookSummaryLine(item);
            final color = _severityColor(severity);
            final meta = [
              if (owner.isNotEmpty) owner,
              if (source.isNotEmpty) _labelForKey(source),
              if (cadence.isNotEmpty) cadence,
              if (dueMinutes > 0) 'due ${dueMinutes}m',
            ].join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: route.isEmpty
                      ? null
                      : () => unawaited(
                            _openControlDashboardBackendRoute(
                              context,
                              baseUrl: widget.baseUrl,
                              dashboardRoute: route,
                            ),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    rank > 0 ? '#$rank' : 'Q',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Icon(
                                    _severityIcon(severity),
                                    color: color,
                                    size: 17,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title.isEmpty ? 'Control item' : title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFF17362B),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (meta.isNotEmpty)
                                    Text(
                                      meta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: color,
                                        fontWeight: FontWeight.w800,
                                        height: 1.3,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (route.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 112),
                                child: Text(
                                  cta.isEmpty ? 'Open board' : cta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _incidentMetricChip(
                              context,
                              icon: _severityIcon(severity),
                              label: _labelForKey(severity),
                              value: signalCount,
                              color: color,
                            ),
                            if (status.isNotEmpty)
                              _incidentMetricChip(
                                context,
                                icon: Icons.radar_outlined,
                                label: 'Status',
                                value: _labelForKey(status),
                                color: color,
                              ),
                            if (sla.isNotEmpty)
                              _incidentMetricChip(
                                context,
                                icon: Icons.speed_rounded,
                                label: 'SLA',
                                value: sla,
                                color: const Color(0xFF2563EB),
                              ),
                            if (permission.isNotEmpty)
                              _incidentMetricChip(
                                context,
                                icon: Icons.admin_panel_settings_outlined,
                                label: 'Scope',
                                value: _labelForKey(permission),
                                color: const Color(0xFF0F766E),
                              ),
                          ],
                        ),
                        if (runbookLine.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            runbookLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF17362B),
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (detail.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5A6F66),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  List<Widget> _strategicSummaryChips(
    BuildContext context,
    Map<String, dynamic> summary,
    int itemCount,
    Color color,
  ) {
    final board = widget.title.toLowerCase();
    if (board == 'executive board') {
      return <Widget>[
        _incidentMetricChip(
          context,
          icon: Icons.priority_high_rounded,
          label: 'Attention',
          value: summary['executive_attention'] ?? summary['attention'] ?? 0,
          color: color,
        ),
        _incidentMetricChip(
          context,
          icon: Icons.gavel_outlined,
          label: 'Decision',
          value: summary['decision_required'] ?? 0,
          color: const Color(0xFFDC2626),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.verified_outlined,
          label: 'Quality',
          value: summary['quality_blocked'] ?? 0,
          color: const Color(0xFFC2410C),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.repeat_outlined,
          label: 'Retention',
          value: summary['retention_blocked'] ?? 0,
          color: const Color(0xFFC2410C),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.playlist_add_check_circle_outlined,
          label: 'Steps',
          value: summary['command_steps_total'] ?? 0,
          color: const Color(0xFF2563EB),
        ),
      ];
    }
    if (board == 'risk board') {
      return <Widget>[
        _incidentMetricChip(
          context,
          icon: Icons.shield_outlined,
          label: 'Risks',
          value: summary['total'] ?? itemCount,
          color: color,
        ),
        _incidentMetricChip(
          context,
          icon: Icons.notification_important_outlined,
          label: 'Critical',
          value: summary['critical'] ?? 0,
          color: const Color(0xFFDC2626),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.priority_high_rounded,
          label: 'Attention',
          value: summary['attention'] ?? 0,
          color: const Color(0xFFC2410C),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.gpp_bad_outlined,
          label: 'Open',
          value: summary['risk_not_accepted'] ?? 0,
          color: const Color(0xFFDC2626),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.playlist_add_check_circle_outlined,
          label: 'Steps',
          value: summary['mitigation_steps_total'] ?? 0,
          color: const Color(0xFF2563EB),
        ),
      ];
    }
    if (board == 'retention board') {
      return <Widget>[
        _incidentMetricChip(
          context,
          icon: Icons.repeat_outlined,
          label: 'Loops',
          value: summary['total'] ?? itemCount,
          color: color,
        ),
        _incidentMetricChip(
          context,
          icon: Icons.task_alt_rounded,
          label: 'Retained',
          value: summary['retained'] ?? 0,
          color: const Color(0xFF0F766E),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.block_outlined,
          label: 'Blocked',
          value: summary['blocked'] ?? 0,
          color: const Color(0xFFDC2626),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.insights_outlined,
          label: 'Measure',
          value: summary['measure'] ?? 0,
          color: const Color(0xFF2563EB),
        ),
        _incidentMetricChip(
          context,
          icon: Icons.playlist_add_check_circle_outlined,
          label: 'Steps',
          value: summary['retention_steps_total'] ?? 0,
          color: const Color(0xFF2563EB),
        ),
      ];
    }
    return <Widget>[
      _incidentMetricChip(
        context,
        icon: Icons.science_outlined,
        label: 'Experiments',
        value: summary['total'] ?? itemCount,
        color: color,
      ),
      _incidentMetricChip(
        context,
        icon: Icons.rocket_launch_outlined,
        label: 'Scale',
        value: summary['scale'] ?? 0,
        color: const Color(0xFF0F766E),
      ),
      _incidentMetricChip(
        context,
        icon: Icons.play_circle_outline_rounded,
        label: 'Running',
        value: summary['running'] ?? 0,
        color: const Color(0xFF2563EB),
      ),
      _incidentMetricChip(
        context,
        icon: Icons.block_outlined,
        label: 'Blocked',
        value: summary['blocked'] ?? 0,
        color: const Color(0xFFDC2626),
      ),
      _incidentMetricChip(
        context,
        icon: Icons.playlist_add_check_circle_outlined,
        label: 'Steps',
        value: summary['experiment_steps_total'] ?? 0,
        color: const Color(0xFF2563EB),
      ),
    ];
  }

  Widget _strategicBoardControlPanel(
    BuildContext context,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> allItems,
  ) {
    final theme = Theme.of(context);
    const filters = <String>[
      'all',
      'blocked',
      'attention',
      'ready',
      'decision',
      'measure',
      'high',
    ];
    final selected =
        filters.contains(_strategicBoardFilter) ? _strategicBoardFilter : 'all';
    final blocked = _intValue(summary['blocked']) +
        _intValue(summary['critical']) +
        _intValue(summary['decision_required']) +
        _intValue(summary['risk_not_accepted']);
    final attention = _intValue(summary['attention']) +
        _intValue(summary['executive_attention']);
    final color = blocked > 0
        ? const Color(0xFFDC2626)
        : attention > 0
            ? const Color(0xFFC2410C)
            : widget.accent;
    final primaryOwner = (summary['primary_owner'] ?? '').toString().trim();
    final primaryTitle = (summary['primary_title'] ?? '').toString().trim();
    final state = (summary['status'] ??
            summary['executive_command_state'] ??
            summary['risk_control_state'] ??
            '')
        .toString()
        .trim();
    final detail = [
      if (state.isNotEmpty) _labelForKey(state),
      if (primaryOwner.isNotEmpty) primaryOwner,
      if (primaryTitle.isNotEmpty) primaryTitle,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_strategicBoardIcon(), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _strategicBoardHeaderTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF17362B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF5A6F66),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${_strategicFilterCount(allItems, selected)} shown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: filters
                  .map(
                    (filter) => ButtonSegment<String>(
                      value: filter,
                      icon: Icon(_strategicFilterIcon(filter), size: 16),
                      label: Text(
                        '${_strategicFilterLabel(filter)} ${_strategicFilterCount(allItems, filter)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <String>{selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() {
                  _strategicBoardFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _strategicSummaryChips(
              context,
              summary,
              allItems.length,
              color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _strategicBoardItemsPanel(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Strategic queue · ${items.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _strategicFilterLabel(_strategicBoardFilter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final status = _strategicStatusForItem(item);
            final severity = _strategicSeverityForItem(item);
            final color = _severityColor(severity);
            final owner = (item['owner'] ?? '').toString().trim();
            final route = (item['dashboard_route'] ?? '').toString().trim();
            final cta = (item['cta_label'] ?? 'Open board').toString().trim();
            final authority = _strategicAuthorityForItem(item);
            final score = _strategicScoreForItem(item);
            final primaryLine = _strategicPrimaryLine(item);
            final gateLine = _strategicGateLine(item);
            final steps = _strategicSteps(item);
            final meta = [
              if (owner.isNotEmpty) owner,
              _labelForKey(status),
              if (authority.isNotEmpty) _labelForKey(authority),
            ].join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: route.isEmpty
                      ? null
                      : () => unawaited(
                            _openControlDashboardBackendRoute(
                              context,
                              baseUrl: widget.baseUrl,
                              dashboardRoute: route,
                            ),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _strategicBoardIcon(),
                                color: color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _itemTitle(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFF17362B),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (route.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 104),
                                child: Text(
                                  cta.isEmpty ? 'Open board' : cta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _incidentMetricChip(
                              context,
                              icon: _strategicFilterIcon('attention'),
                              label: 'State',
                              value: _labelForKey(status),
                              color: color,
                            ),
                            if (score > 0)
                              _incidentMetricChip(
                                context,
                                icon: Icons.speed_rounded,
                                label: 'Score',
                                value: score,
                                color: color,
                              ),
                            if (authority.isNotEmpty)
                              _incidentMetricChip(
                                context,
                                icon: Icons.verified_user_outlined,
                                label: 'Authority',
                                value: _labelForKey(authority),
                                color: const Color(0xFF0F766E),
                              ),
                          ],
                        ),
                        if (primaryLine.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            primaryLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF17362B),
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (gateLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            gateLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5A6F66),
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (steps.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...steps.map(
                            (step) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: color,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      step,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF5A6F66),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _operationalBoardControlPanel(
    BuildContext context,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> allItems,
  ) {
    final theme = Theme.of(context);
    const filters = <String>[
      'all',
      'high',
      'blocked',
      'watch',
      'ready',
      'due',
      'steps',
    ];
    final selected = filters.contains(_operationalBoardFilter)
        ? _operationalBoardFilter
        : 'all';
    final high = _intValue(summary['high']) +
        _intValue(summary['blocked']) +
        _intValue(summary['hold']);
    final medium = _intValue(summary['medium']) +
        _intValue(summary['watch']) +
        _intValue(summary['pilot']) +
        _intValue(summary['instrument']);
    final color = high > 0
        ? const Color(0xFFDC2626)
        : medium > 0
            ? const Color(0xFFC2410C)
            : widget.accent;
    final primaryTitle = (summary['primary_title'] ?? '').toString().trim();
    final primaryOwner = (summary['primary_owner'] ?? '').toString().trim();
    final state = (summary['status'] ??
            summary['source_authority'] ??
            summary['risk_control_state'] ??
            '')
        .toString()
        .trim();
    final dueMinutes = _intValue(summary['due_in_minutes']);
    final stepTotal = _operationalStepTotal(summary);
    final detail = [
      if (state.isNotEmpty) _labelForKey(state),
      if (primaryOwner.isNotEmpty) primaryOwner,
      if (primaryTitle.isNotEmpty) primaryTitle,
      if (dueMinutes > 0) 'due ${dueMinutes}m',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_operationalBoardIcon(), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _operationalBoardHeaderTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF17362B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF5A6F66),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${_operationalFilterCount(allItems, selected)} shown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: filters
                  .map(
                    (filter) => ButtonSegment<String>(
                      value: filter,
                      icon: Icon(_operationalFilterIcon(filter), size: 16),
                      label: Text(
                        '${_operationalFilterLabel(filter)} ${_operationalFilterCount(allItems, filter)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <String>{selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() {
                  _operationalBoardFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: _operationalBoardIcon(),
                label: 'Items',
                value: summary['total'] ?? allItems.length,
                color: color,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.notification_important_outlined,
                label: 'High',
                value: summary['high'] ??
                    summary['blocked'] ??
                    summary['hold'] ??
                    summary['missing'] ??
                    0,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.visibility_outlined,
                label: 'Watch',
                value: summary['medium'] ??
                    summary['watch'] ??
                    summary['instrument'] ??
                    summary['pilot'] ??
                    summary['limited'] ??
                    summary['review'] ??
                    summary['today'] ??
                    0,
                color: const Color(0xFFC2410C),
              ),
              if (dueMinutes > 0)
                _incidentMetricChip(
                  context,
                  icon: Icons.timer_outlined,
                  label: 'Due',
                  value: '${dueMinutes}m',
                  color: color,
                ),
              _incidentMetricChip(
                context,
                icon: Icons.groups_outlined,
                label: 'Owners',
                value: summary['owners_total'] ?? 0,
                color: const Color(0xFF0F766E),
              ),
              if (stepTotal != null)
                _incidentMetricChip(
                  context,
                  icon: Icons.playlist_add_check_circle_outlined,
                  label: 'Steps',
                  value: stepTotal,
                  color: const Color(0xFF2563EB),
                ),
              if (summary.containsKey('average_score'))
                _incidentMetricChip(
                  context,
                  icon: Icons.speed_rounded,
                  label: 'Score',
                  value: summary['average_score'],
                  color: widget.accent,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _operationalBoardItemsPanel(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dashboard_customize_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Operating queue · ${items.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _operationalFilterLabel(_operationalBoardFilter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final status = _operationalStatusForItem(item);
            final severity = _operationalSeverityForItem(item);
            final color = _severityColor(severity);
            final owner = (item['owner'] ?? '').toString().trim();
            final route = (item['dashboard_route'] ?? '').toString().trim();
            final cta = (item['cta_label'] ?? 'Open board').toString().trim();
            final authority = _operationalAuthorityForItem(item);
            final score = _operationalScoreForItem(item);
            final dueMinutes = _intValue(item['due_in_minutes']);
            final primaryLine = _operationalPrimaryLine(item);
            final gateLine = _operationalGateLine(item);
            final steps = _strategicSteps(item);
            final meta = [
              if (owner.isNotEmpty) owner,
              _labelForKey(status),
              if (dueMinutes > 0) '${dueMinutes}m',
            ].join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: route.isEmpty
                      ? null
                      : () => unawaited(
                            _openControlDashboardBackendRoute(
                              context,
                              baseUrl: widget.baseUrl,
                              dashboardRoute: route,
                            ),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _operationalBoardIcon(),
                                color: color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _itemTitle(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFF17362B),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (route.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 106),
                                child: Text(
                                  cta.isEmpty ? 'Open board' : cta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _incidentMetricChip(
                              context,
                              icon: _operationalFilterIcon('watch'),
                              label: 'State',
                              value: _labelForKey(status),
                              color: color,
                            ),
                            if (score > 0)
                              _incidentMetricChip(
                                context,
                                icon: Icons.speed_rounded,
                                label: 'Score',
                                value: score,
                                color: color,
                              ),
                            if (authority.isNotEmpty)
                              _incidentMetricChip(
                                context,
                                icon: Icons.verified_user_outlined,
                                label: 'Authority',
                                value: _labelForKey(authority),
                                color: const Color(0xFF0F766E),
                              ),
                            if (dueMinutes > 0)
                              _incidentMetricChip(
                                context,
                                icon: Icons.timer_outlined,
                                label: 'Due',
                                value: '${dueMinutes}m',
                                color: color,
                              ),
                          ],
                        ),
                        if (primaryLine.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            primaryLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF17362B),
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (gateLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            gateLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5A6F66),
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (steps.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...steps.map(
                            (step) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: color,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      step,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF5A6F66),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _commandWorklistControlPanel(
    BuildContext context,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> allItems,
  ) {
    final theme = Theme.of(context);
    const filters = <String>[
      'all',
      'executive',
      'owner',
      'critical',
      'attention',
      'watch',
      'due',
      'unclaimed',
    ];
    final selected = filters.contains(_commandWorklistFilter)
        ? _commandWorklistFilter
        : 'all';
    final commandState = (summary['command_state'] ?? 'watch').toString();
    final color = _commandStateColor(commandState);
    final primaryTitle = (summary['primary_title'] ?? '').toString().trim();
    final primaryOwner = (summary['primary_owner'] ?? '').toString().trim();
    final nextMinutes = _intValue(summary['next_response_minutes']);
    final detail = [
      if (primaryTitle.isNotEmpty) primaryTitle,
      if (primaryOwner.isNotEmpty) primaryOwner,
      if (nextMinutes > 0) 'next ${nextMinutes}m',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_commandStateIcon(commandState), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Command control',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF17362B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF5A6F66),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${_commandFilterCount(allItems, selected)} shown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: filters
                  .map(
                    (filter) => ButtonSegment<String>(
                      value: filter,
                      icon: Icon(_commandFilterIcon(filter), size: 16),
                      label: Text(
                        '${_commandFilterLabel(filter)} ${_commandFilterCount(allItems, filter)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <String>{selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() {
                  _commandWorklistFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: Icons.pending_actions_outlined,
                label: 'Commands',
                value: summary['total'] ?? allItems.length,
                color: color,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.corporate_fare_outlined,
                label: 'Executive',
                value: summary['executive_command_required'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.assignment_ind_outlined,
                label: 'Owner',
                value: summary['owner_command_required'] ?? 0,
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.notification_important_outlined,
                label: 'Critical',
                value: summary['critical'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.playlist_add_check_circle_outlined,
                label: 'Steps',
                value: summary['dispatch_steps_total'] ?? 0,
                color: const Color(0xFF2563EB),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.groups_outlined,
                label: 'Owners',
                value: summary['owners_total'] ?? 0,
                color: const Color(0xFF0F766E),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _commandWorklistItemsPanel(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.outbound_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Command queue · ${items.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _commandFilterLabel(_commandWorklistFilter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final status = (item['status'] ?? 'control_watch').toString();
            final health = (item['command_health'] ?? 'attention').toString();
            final color = health.trim().isEmpty
                ? _commandStateColor(status)
                : _incidentCommandHealthColor(health);
            final owner = (item['owner'] ?? '').toString().trim();
            final action = (item['recommended_action'] ?? '').toString().trim();
            final gate = (item['incident_action_gate'] ?? '').toString().trim();
            final route = (item['dashboard_route'] ?? '').toString().trim();
            final cta = (item['cta_label'] ?? 'Open command').toString().trim();
            final bucket =
                (item['response_bucket'] ?? 'due_soon').toString().trim();
            final rawSteps = item['incident_dispatch_steps'];
            final steps = rawSteps is List
                ? rawSteps
                    .map(_opsStepDisplayText)
                    .where((step) => step.isNotEmpty)
                    .take(2)
                    .toList(growable: false)
                : const <String>[];
            final nextMinutes = _intValue(item['next_response_minutes']);
            final meta = [
              if (owner.isNotEmpty) owner,
              _labelForKey(status),
              _incidentResponseBucketLabel(bucket),
              if (nextMinutes > 0) '${nextMinutes}m',
            ].join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: route.isEmpty
                      ? null
                      : () => unawaited(
                            _openControlDashboardBackendRoute(
                              context,
                              baseUrl: widget.baseUrl,
                              dashboardRoute: route,
                            ),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child:
                                  Icon(_commandStateIcon(status), color: color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _itemTitle(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFF17362B),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _incidentResponseBucketPill(bucket),
                          ],
                        ),
                        if (action.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            action,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF17362B),
                              fontWeight: FontWeight.w900,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (gate.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            gate,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5A6F66),
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (steps.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...steps.map(
                            (step) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: color,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      step,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF5A6F66),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (route.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            cta.isEmpty ? 'Open command' : cta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _ownerWorkloadControlPanel(
    BuildContext context,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> owners,
  ) {
    final theme = Theme.of(context);
    const filters = <String>[
      'all',
      'executive',
      'owner',
      'critical',
      'due',
      'unclaimed',
      'watch',
    ];
    final selected =
        filters.contains(_ownerWorkloadFilter) ? _ownerWorkloadFilter : 'all';
    final commandState = (summary['command_state'] ?? 'watch').toString();
    final color = _commandStateColor(commandState);
    final nextMinutes = _intValue(summary['next_response_minutes']);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_ind_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Owner workload control',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF17362B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      nextMinutes > 0
                          ? 'Next response in ${nextMinutes}m'
                          : 'Owner pressure grouped by team',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF5A6F66),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_ownerFilterCount(owners, selected)} shown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: filters
                  .map(
                    (filter) => ButtonSegment<String>(
                      value: filter,
                      icon: Icon(_ownerFilterIcon(filter), size: 16),
                      label: Text(
                        '${_ownerFilterLabel(filter)} ${_ownerFilterCount(owners, filter)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <String>{selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() {
                  _ownerWorkloadFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: Icons.groups_outlined,
                label: 'Owners',
                value: summary['owners_total'] ?? owners.length,
                color: color,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.pending_actions_outlined,
                label: 'Commands',
                value: summary['total'] ?? 0,
                color: widget.accent,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.corporate_fare_outlined,
                label: 'Executive',
                value: summary['executive_command_required'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.assignment_ind_outlined,
                label: 'Owner',
                value: summary['owner_command_required'] ?? 0,
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.playlist_add_check_circle_outlined,
                label: 'Steps',
                value: summary['dispatch_steps_total'] ?? 0,
                color: const Color(0xFF2563EB),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ownerWorkloadItemsPanel(
    BuildContext context,
    List<Map<String, dynamic>> owners,
  ) {
    final theme = Theme.of(context);
    if (owners.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Owner queue · ${owners.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _ownerFilterLabel(_ownerWorkloadFilter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...owners.map((owner) {
            final status = (owner['status'] ?? 'watch').toString();
            final color = _commandStateColor(status);
            final title = _itemTitle(owner);
            final route = (owner['dashboard_route'] ?? '').toString().trim();
            final count = _intValue(owner['count']);
            final executive = _intValue(owner['executive_command_required']);
            final ownerRequired = _intValue(owner['owner_command_required']);
            final critical = _intValue(owner['critical']);
            final dueSoon = _intValue(owner['due_soon']);
            final unclaimed = _intValue(owner['unclaimed']);
            final steps = _intValue(owner['dispatch_steps_total']);
            final nextMinutes = _intValue(owner['next_response_minutes']);
            final detail = [
              '$count command(s)',
              if (nextMinutes > 0) 'next ${nextMinutes}m',
              if (steps > 0) '$steps step(s)',
            ].join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: route.isEmpty
                      ? null
                      : () => unawaited(
                            _openControlDashboardBackendRoute(
                              context,
                              baseUrl: widget.baseUrl,
                              dashboardRoute: route,
                            ),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child:
                                  Icon(_commandStateIcon(status), color: color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFF17362B),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _incidentMetricChip(
                              context,
                              icon: Icons.corporate_fare_outlined,
                              label: 'Exec',
                              value: executive,
                              color: const Color(0xFFDC2626),
                            ),
                            _incidentMetricChip(
                              context,
                              icon: Icons.assignment_ind_outlined,
                              label: 'Owner',
                              value: ownerRequired,
                              color: const Color(0xFFC2410C),
                            ),
                            _incidentMetricChip(
                              context,
                              icon: Icons.notification_important_outlined,
                              label: 'Critical',
                              value: critical,
                              color: const Color(0xFFDC2626),
                            ),
                            _incidentMetricChip(
                              context,
                              icon: Icons.timer_outlined,
                              label: 'Due',
                              value: dueSoon,
                              color: const Color(0xFFC2410C),
                            ),
                            if (unclaimed > 0)
                              _incidentMetricChip(
                                context,
                                icon: Icons.person_off_outlined,
                                label: 'Open',
                                value: unclaimed,
                                color: const Color(0xFFC2410C),
                              ),
                          ],
                        ),
                        if (route.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Open owner board',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _incidentResponseLanePanel(
    BuildContext context,
    List<Map<String, dynamic>> lanes,
  ) {
    final theme = Theme.of(context);
    if (lanes.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.view_column_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Response lanes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${lanes.length} lanes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: lanes.map((lane) {
                final bucket = (lane['id'] ?? 'due_soon').toString().trim();
                final count = _intValue(lane['count']);
                final critical = _intValue(lane['critical']);
                final unclaimed = _intValue(lane['unclaimed']);
                final nextMinutes = _intValue(lane['next_response_minutes']);
                final title = (lane['title'] ?? '').toString().trim();
                final primaryTitle =
                    (lane['primary_title'] ?? '').toString().trim();
                final primaryAction =
                    (lane['primary_action'] ?? '').toString().trim();
                final color = _incidentResponseBucketColor(bucket);
                final targetFilter = bucket == 'page_now'
                    ? 'critical'
                    : bucket == 'watch_window'
                        ? 'watch'
                        : bucket == 'closed'
                            ? 'resolved'
                            : 'attention';
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Material(
                    color: color.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        setState(() {
                          _incidentWorkflowFilter = targetFilter;
                        });
                      },
                      child: Container(
                        width: 224,
                        constraints: const BoxConstraints(minHeight: 162),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: color.withValues(alpha: .16)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _incidentResponseBucketIcon(bucket),
                                  color: color,
                                  size: 18,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    title.isEmpty
                                        ? _incidentResponseBucketLabel(bucket)
                                        : title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFF17362B),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$count',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _incidentMetricChip(
                                  context,
                                  icon: Icons.notification_important_outlined,
                                  label: 'Critical',
                                  value: critical,
                                  color: color,
                                ),
                                if (unclaimed > 0)
                                  _incidentMetricChip(
                                    context,
                                    icon: Icons.person_off_outlined,
                                    label: 'Open',
                                    value: unclaimed,
                                    color: const Color(0xFFC2410C),
                                  ),
                                if (nextMinutes > 0)
                                  _incidentMetricChip(
                                    context,
                                    icon: Icons.timer_outlined,
                                    label: 'Next',
                                    value: '${nextMinutes}m',
                                    color: color,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              primaryTitle.isEmpty
                                  ? 'No incidents'
                                  : primaryTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (primaryAction.isNotEmpty)
                              Text(
                                primaryAction,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6F66),
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleIncidentMenuAction(
    Map<String, dynamic> item,
    String action,
  ) async {
    if (action == 'timeline') {
      await _showIncidentTimelineSheet(item);
      return;
    }
    if (const <String>{'assign', 'snooze', 'resolve', 'reopen'}
        .contains(action)) {
      await _showIncidentActionDialog(item, action);
      return;
    }
    await _postIncidentAction(
      item,
      action,
      note: 'Updated from SyrChat Control',
    );
  }

  Widget _incidentActionMenu(Map<String, dynamic> item) {
    final status = (item['workflow_status'] ??
            item['incident_status'] ??
            item['status'] ??
            '')
        .toString();
    final resolveAction = status == 'resolved' ? 'reopen' : 'resolve';
    return PopupMenuButton<String>(
      tooltip: 'Incident actions',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (action) =>
          unawaited(_handleIncidentMenuAction(item, action)),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'timeline',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.manage_history_rounded),
            title: Text('Timeline'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'claim',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.person_add_alt_1_outlined),
            title: Text('Claim'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'assign',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.assignment_ind_outlined),
            title: Text('Assign'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'acknowledge',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.done_all_rounded),
            title: Text('Acknowledge'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'snooze',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.schedule_rounded),
            title: Text('Snooze'),
          ),
        ),
        PopupMenuItem<String>(
          value: resolveAction,
          child: ListTile(
            dense: true,
            leading: Icon(
              resolveAction == 'reopen'
                  ? Icons.restart_alt_rounded
                  : Icons.task_alt_rounded,
            ),
            title: Text(resolveAction == 'reopen' ? 'Reopen' : 'Resolve'),
          ),
        ),
      ],
    );
  }

  String _sourceAuthorityLabel(String source) {
    switch (source) {
      case 'server_authoritative':
        return 'Server authority';
      case 'client_authenticated':
        return 'Client authenticated';
      default:
        return 'Legacy / unknown';
    }
  }

  Color _sourceAuthorityColor(String source) {
    switch (source) {
      case 'server_authoritative':
        return const Color(0xFF047857);
      case 'client_authenticated':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFFDC2626);
    }
  }

  IconData _sourceAuthorityIcon(String source) {
    switch (source) {
      case 'server_authoritative':
        return Icons.verified_user_outlined;
      case 'client_authenticated':
        return Icons.phone_android_outlined;
      default:
        return Icons.help_outline_rounded;
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFC2410C);
      default:
        return const Color(0xFF0F766E);
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'high':
        return Icons.priority_high_rounded;
      case 'medium':
        return Icons.timelapse_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  Widget _dashboardActionsPanel(
    BuildContext context,
    List<Map<String, dynamic>> actions,
  ) {
    final theme = Theme.of(context);
    final isControlInbox = widget.title.toLowerCase() == 'control inbox';
    final isDailyBrief = widget.title.toLowerCase() == 'daily brief';
    final isEscalations = widget.title.toLowerCase() == 'escalations';
    final isSlaBoard = widget.title.toLowerCase() == 'sla board';
    final isEvidenceBoard = widget.title.toLowerCase() == 'evidence board';
    final isSyncBoard = widget.title.toLowerCase() == 'sync board';
    final isQualityBoard = widget.title.toLowerCase() == 'quality board';
    final isLaunchBoard = widget.title.toLowerCase() == 'launch board';
    final isGrowthBoard = widget.title.toLowerCase() == 'growth board';
    final high = actions
        .where((item) => (item['severity'] ?? '').toString() == 'high')
        .length;
    final medium = actions
        .where((item) => (item['severity'] ?? '').toString() == 'medium')
        .length;
    final low = actions.length - high - medium;
    final headerSeverity = high > 0
        ? 'high'
        : medium > 0
            ? 'medium'
            : 'low';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_severityIcon(headerSeverity), color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${isControlInbox ? 'Control inbox' : isDailyBrief ? 'Daily actions' : isEscalations ? 'Escalation queue' : isSlaBoard ? 'SLA queue' : isEvidenceBoard ? 'Evidence queue' : isSyncBoard ? 'Sync queue' : isQualityBoard ? 'Quality queue' : isLaunchBoard ? 'Launch queue' : isGrowthBoard ? 'Growth queue' : 'Dashboard actions'} · ${actions.length}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$high high · $medium med · $low low',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...actions.take(4).map((item) {
            final title = (item['title'] ?? '').toString().trim();
            final detail = (item['detail'] ?? '').toString().trim();
            final owner = (item['owner'] ?? '').toString().trim();
            final cadence = (item['review_cadence'] ?? '').toString().trim();
            final dueMinutes = _intValue(item['due_in_minutes']);
            final cta = (item['cta_label'] ?? '').toString().trim();
            final route = (item['dashboard_route'] ?? '').toString().trim();
            final severity = (item['severity'] ?? 'low').toString();
            final color = _severityColor(severity);
            final runbookLine = _opsRunbookSummaryLine(item);
            final ownerLine = [
              if (owner.isNotEmpty) owner,
              if (cadence.isNotEmpty) cadence,
              if (dueMinutes > 0) 'due ${dueMinutes}m',
            ].join(' · ');
            final canOpen = route.isNotEmpty;
            final row = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_severityIcon(severity), color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Dashboard action' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF17362B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (ownerLine.isNotEmpty)
                        Text(
                          ownerLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                      if (runbookLine.isNotEmpty)
                        Text(
                          runbookLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF17362B),
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF5A6F66),
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
                if (canOpen && cta.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    cta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: canOpen
                  ? Material(
                      color: color.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => unawaited(
                          _openControlDashboardBackendRoute(
                            context,
                            baseUrl: widget.baseUrl,
                            dashboardRoute: route,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: row,
                        ),
                      ),
                    )
                  : row,
            );
          }),
        ],
      ),
    );
  }

  Widget _dailyCommandFocusPanel(
    BuildContext context,
    Map<String, dynamic> summary,
    Map<String, dynamic> item,
  ) {
    final theme = Theme.of(context);
    final state = (item['status'] ?? summary['command_state'] ?? 'watch')
        .toString()
        .trim();
    final color = _commandStateColor(state);
    final title = (item['title'] ?? summary['command_primary_title'] ?? '')
        .toString()
        .trim();
    final owner = (item['owner'] ?? summary['command_primary_owner'] ?? '')
        .toString()
        .trim();
    final detail = (item['detail'] ?? '').toString().trim();
    final route = (item['dashboard_route'] ??
            summary['command_primary_route'] ??
            '/admin/dashboards/command-worklist')
        .toString()
        .trim();
    final cta = (item['cta_label'] ?? 'Open command').toString().trim();
    final commandTotal =
        _intValue(item['signal_count'] ?? summary['command_total']);
    final executive =
        _intValue(summary['executive_command_required'] ?? item['executive']);
    final ownerRequired =
        _intValue(summary['owner_command_required'] ?? item['owner_required']);
    final dispatchSteps = _intValue(
      item['dispatch_steps_total'] ?? summary['command_dispatch_steps_total'],
    );
    final nextMinutes = _intValue(
      item['next_response_minutes'] ?? summary['command_next_response_minutes'],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_commandStateIcon(state), color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Command focus',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF17362B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (owner.isNotEmpty)
                      Text(
                        owner,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ),
              Tooltip(
                message: _labelForKey(state),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 162),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withValues(alpha: .16)),
                  ),
                  child: Text(
                    _labelForKey(state),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title.isEmpty ? 'Control command' : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: const Color(0xFF17362B),
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5A6F66),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _incidentMetricChip(
                context,
                icon: Icons.pending_actions_outlined,
                label: 'Commands',
                value: commandTotal,
                color: color,
              ),
              _incidentMetricChip(
                context,
                icon: Icons.corporate_fare_outlined,
                label: 'Executive',
                value: executive,
                color: const Color(0xFFDC2626),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.assignment_ind_outlined,
                label: 'Owner',
                value: ownerRequired,
                color: const Color(0xFFC2410C),
              ),
              _incidentMetricChip(
                context,
                icon: Icons.playlist_add_check_circle_outlined,
                label: 'Steps',
                value: dispatchSteps,
                color: const Color(0xFF2563EB),
              ),
              if (nextMinutes > 0)
                _incidentMetricChip(
                  context,
                  icon: Icons.timer_outlined,
                  label: 'Next',
                  value: '${nextMinutes}m',
                  color: color,
                ),
            ],
          ),
          if (route.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => unawaited(
                  _openControlDashboardBackendRoute(
                    context,
                    baseUrl: widget.baseUrl,
                    dashboardRoute: route,
                  ),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(cta.isEmpty ? 'Open command' : cta),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _trendValue(Map<String, dynamic> item) {
    var total = 0;
    for (final entry in item.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'day' || key == 'date' || key.endsWith('_at')) continue;
      final value = entry.value;
      if (value is num) total += value.toInt();
    }
    return total;
  }

  Widget _metricCard(
    BuildContext context,
    MapEntry<String, Object?> entry,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _labelForKey(entry.key),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5A6F66),
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            '${entry.value}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: const Color(0xFF17362B),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required String detail,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF17362B),
              fontWeight: FontWeight.w900,
            ),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5A6F66),
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceAuthorityPanel(
    BuildContext context,
    List<Map<String, dynamic>> authorities,
  ) {
    final theme = Theme.of(context);
    final total = authorities.fold<int>(
      0,
      (sum, item) => sum + _intValue(item['event_count']),
    );
    final trusted = authorities.fold<int>(0, (sum, item) {
      final source = (item['source_authority'] ?? '').toString();
      if (source == 'server_authoritative' ||
          source == 'client_authenticated') {
        return sum + _intValue(item['event_count']);
      }
      return sum;
    });
    final percent = total > 0 ? ((trusted * 100) / total).round() : 100;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: widget.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Source authority',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: widget.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            minHeight: 5,
            value: (percent / 100).clamp(0, 1).toDouble(),
            color: widget.accent,
            backgroundColor: widget.accent.withValues(alpha: .10),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: authorities.map((item) {
              final source = (item['source_authority'] ?? 'unknown').toString();
              final count = _intValue(item['event_count']);
              final color = _sourceAuthorityColor(source);
              return Chip(
                avatar: Icon(
                  _sourceAuthorityIcon(source),
                  color: color,
                  size: 16,
                ),
                label: Text('${_sourceAuthorityLabel(source)} · $count'),
                backgroundColor: color.withValues(alpha: .09),
                side: BorderSide(color: color.withValues(alpha: .16)),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _trendPanel(
    BuildContext context,
    List<Map<String, dynamic>> trendItems,
  ) {
    final theme = Theme.of(context);
    final visible = trendItems.length > 14
        ? trendItems.sublist(trendItems.length - 14)
        : trendItems;
    final maxValue = visible.fold<int>(
      0,
      (maxSoFar, item) => max(maxSoFar, _trendValue(item)),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD6E7DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '30-day operating pulse',
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF17362B),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: visible.map((item) {
                final value = _trendValue(item);
                final height = maxValue <= 0
                    ? 8.0
                    : (10 + (value / maxValue) * 54)
                        .clamp(8.0, 64.0)
                        .toDouble();
                final day = (item['day'] ?? item['date'] ?? '').toString();
                return Expanded(
                  child: Tooltip(
                    message: '$day · $value',
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: height,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: .82),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final detail = _itemDetail(item);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD6E7DF)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.icon, color: widget.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _itemTitle(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF5A6F66),
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          if (_isIncidentBoardItem(item)) ...[
            const SizedBox(width: 8),
            _incidentCommandHealthPill(item),
            const SizedBox(width: 2),
            _incidentActionMenu(item),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    final summary =
        data == null ? const <String, dynamic>{} : _summaryData(data);
    final metrics =
        data == null || _isControlIntelligenceSurface || _isRunbookSurface
            ? const <MapEntry<String, Object?>>[]
            : _metricEntries(summary);
    final authorities = data == null
        ? const <Map<String, dynamic>>[]
        : _sourceAuthorityItems(data);
    final actionPlan =
        data == null ? const <Map<String, dynamic>>[] : _actionPlanItems(data);
    final trend =
        data == null ? const <Map<String, dynamic>>[] : _trendItems(data);
    final features =
        data == null ? const <Map<String, dynamic>>[] : _featureItems(data);
    final ownerWorkloadItems = _isOwnerWorkloadSurface
        ? _filteredOwnerWorkloadItems(features)
        : const <Map<String, dynamic>>[];
    final visibleFeatures = _isOwnerWorkloadSurface ||
            _isControlInboxSurface ||
            _isStrategicBoardSurface ||
            _isOperationalBoardSurface ||
            _isControlIntelligenceSurface ||
            _isRunbookSurface ||
            _isSurfaceControlSurface
        ? const <Map<String, dynamic>>[]
        : features;
    final controlLanes = data == null || !_isControlIntelligenceSurface
        ? const <Map<String, dynamic>>[]
        : _controlIntelligenceItems(data, 'lanes', limit: 8);
    final readinessRoadmap = data == null || !_isControlIntelligenceSurface
        ? const <Map<String, dynamic>>[]
        : _controlIntelligenceItems(data, 'readiness_roadmap', limit: 6);
    final operatingGates = data == null || !_isControlIntelligenceSurface
        ? const <Map<String, dynamic>>[]
        : _controlIntelligenceItems(data, 'operating_gates', limit: 8);
    final commandQueue = data == null
        ? const <Map<String, dynamic>>[]
        : _commandQueueItems(data);
    final responseLanes = data == null
        ? const <Map<String, dynamic>>[]
        : _responseLaneItems(data);
    final dailyCommandFocus = data == null || !_isDailyBriefSurface
        ? null
        : _dailyCommandFocusItem(data);
    final rawItems =
        data == null ? const <Map<String, dynamic>>[] : _primaryItems(data);
    final surfaceControlSourceItems = data == null || !_isSurfaceControlSurface
        ? const <Map<String, dynamic>>[]
        : _surfaceControlSourceItems(data);
    final surfaceControlItems = _isSurfaceControlSurface
        ? _filteredSurfaceControlItems(surfaceControlSourceItems)
        : const <Map<String, dynamic>>[];
    final runbookItems = _isRunbookSurface
        ? _filteredRunbookItems(rawItems)
        : const <Map<String, dynamic>>[];
    final visibleRawItems = _isDailyBriefSurface && dailyCommandFocus != null
        ? rawItems
            .where((item) =>
                (item['id'] ?? '').toString().trim() != 'command_focus')
            .toList(growable: false)
        : rawItems;
    final controlInboxItems = _isControlInboxSurface
        ? _filteredControlInboxItems(rawItems)
        : const <Map<String, dynamic>>[];
    final strategicBoardItems = _isStrategicBoardSurface
        ? _filteredStrategicBoardItems(rawItems)
        : const <Map<String, dynamic>>[];
    final operationalBoardItems = _isOperationalBoardSurface
        ? _filteredOperationalBoardItems(rawItems)
        : const <Map<String, dynamic>>[];
    final items = _isCommandWorklistSurface
        ? _filteredCommandItems(visibleRawItems)
        : _isControlInboxSurface
            ? const <Map<String, dynamic>>[]
            : _isStrategicBoardSurface
                ? const <Map<String, dynamic>>[]
                : _isOperationalBoardSurface
                    ? const <Map<String, dynamic>>[]
                    : _isRunbookSurface ||
                            _isControlIntelligenceSurface ||
                            _isSurfaceControlSurface
                        ? const <Map<String, dynamic>>[]
                        : _filteredIncidentItems(visibleRawItems);
    final hasDashboardData = metrics.isNotEmpty ||
        actionPlan.isNotEmpty ||
        authorities.isNotEmpty ||
        trend.isNotEmpty ||
        features.isNotEmpty ||
        commandQueue.isNotEmpty ||
        responseLanes.isNotEmpty ||
        controlLanes.isNotEmpty ||
        readinessRoadmap.isNotEmpty ||
        operatingGates.isNotEmpty ||
        surfaceControlSourceItems.isNotEmpty ||
        rawItems.isNotEmpty;
    final showsOwnerWorkload =
        !_isOwnerWorkloadSurface && _showsOwnerWorkload(data);
    return AppScaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: widget.accent.withValues(alpha: .14),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(widget.icon, color: widget.accent),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.subtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF5A6F66),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              ),
            if (_status.isNotEmpty && !_loading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(_status, dense: true),
                ),
              ),
            if (metrics.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 104,
                  ),
                  itemCount: metrics.length,
                  itemBuilder: (context, index) =>
                      _metricCard(context, metrics[index]),
                ),
              ),
            if (_isControlIntelligenceSurface && data != null)
              SliverToBoxAdapter(
                child: _controlIntelligencePosturePanel(context, data),
              ),
            if (dailyCommandFocus != null)
              SliverToBoxAdapter(
                child: _dailyCommandFocusPanel(
                  context,
                  summary,
                  dailyCommandFocus,
                ),
              ),
            if (_isControlInboxSurface && rawItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _controlInboxTriagePanel(
                  context,
                  summary,
                  rawItems,
                ),
              ),
            if (_isCommandWorklistSurface && rawItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _commandWorklistControlPanel(
                  context,
                  summary,
                  rawItems,
                ),
              ),
            if (_isOwnerWorkloadSurface && features.isNotEmpty)
              SliverToBoxAdapter(
                child: _ownerWorkloadControlPanel(
                  context,
                  summary,
                  features,
                ),
              ),
            if (_isRunbookSurface && rawItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _runbookControlPanel(
                  context,
                  summary,
                  features,
                  rawItems,
                ),
              ),
            if (_isSurfaceControlSurface &&
                surfaceControlSourceItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _surfaceControlPanel(
                  context,
                  summary,
                  authorities,
                  surfaceControlSourceItems,
                ),
              ),
            if (_isStrategicBoardSurface && rawItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _strategicBoardControlPanel(
                  context,
                  summary,
                  rawItems,
                ),
              ),
            if (_isOperationalBoardSurface && rawItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _operationalBoardControlPanel(
                  context,
                  summary,
                  rawItems,
                ),
              ),
            if (actionPlan.isNotEmpty &&
                !_isControlInboxSurface &&
                !_isStrategicBoardSurface &&
                !_isOperationalBoardSurface &&
                !_isControlIntelligenceSurface &&
                !_isRunbookSurface &&
                !_isSurfaceControlSurface)
              SliverToBoxAdapter(
                child: _dashboardActionsPanel(context, actionPlan),
              ),
            if (authorities.isNotEmpty)
              SliverToBoxAdapter(
                child: _sourceAuthorityPanel(context, authorities),
              ),
            if (trend.isNotEmpty)
              SliverToBoxAdapter(
                child: _trendPanel(context, trend),
              ),
            if (visibleFeatures.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _sectionHeader(
                  context,
                  title: showsOwnerWorkload ? 'Owner workload' : 'Feature mix',
                  detail: showsOwnerWorkload
                      ? 'Teams, action pressure, owner SLAs, permissions, and next control boards.'
                      : 'Top modules, feature keys, and Mini Program telemetry.',
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverList.separated(
                  itemCount: visibleFeatures.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _itemRow(context, visibleFeatures[index]),
                ),
              ),
            ],
            if (_isControlIntelligenceSurface && controlLanes.isNotEmpty)
              SliverToBoxAdapter(
                child: _controlIntelligencePanel(
                  context,
                  title: 'Operating lanes',
                  icon: Icons.view_column_outlined,
                  items: controlLanes,
                  statusKey: 'status',
                ),
              ),
            if (_isControlIntelligenceSurface && readinessRoadmap.isNotEmpty)
              SliverToBoxAdapter(
                child: _controlIntelligencePanel(
                  context,
                  title: 'Readiness roadmap',
                  icon: Icons.eco_outlined,
                  items: readinessRoadmap,
                  statusKey: 'status',
                  countKey: 'metric_count',
                ),
              ),
            if (_isControlIntelligenceSurface && operatingGates.isNotEmpty)
              SliverToBoxAdapter(
                child: _controlIntelligencePanel(
                  context,
                  title: 'Operating gates',
                  icon: Icons.lock_outline_rounded,
                  items: operatingGates,
                  statusKey: 'gate_state',
                  countKey: 'review_sla_minutes',
                ),
              ),
            if (_isIncidentBoardSurface && rawItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _incidentWorkflowControlPanel(
                  context,
                  summary,
                  rawItems,
                ),
              ),
            if (_isIncidentBoardSurface && responseLanes.isNotEmpty)
              SliverToBoxAdapter(
                child: _incidentResponseLanePanel(context, responseLanes),
              ),
            if (_isIncidentBoardSurface && commandQueue.isNotEmpty)
              SliverToBoxAdapter(
                child: _incidentCommandQueuePanel(context, commandQueue),
              ),
            if (_isControlInboxSurface && controlInboxItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _controlInboxItemsPanel(context, controlInboxItems),
              ),
            if (_isStrategicBoardSurface && strategicBoardItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _strategicBoardItemsPanel(
                  context,
                  strategicBoardItems,
                ),
              ),
            if (_isOperationalBoardSurface && operationalBoardItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _operationalBoardItemsPanel(
                  context,
                  operationalBoardItems,
                ),
              ),
            if (_isCommandWorklistSurface && items.isNotEmpty)
              SliverToBoxAdapter(
                child: _commandWorklistItemsPanel(context, items),
              ),
            if (_isOwnerWorkloadSurface && ownerWorkloadItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _ownerWorkloadItemsPanel(context, ownerWorkloadItems),
              ),
            if (_isRunbookSurface && runbookItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _runbookItemsPanel(context, runbookItems),
              ),
            if (_isSurfaceControlSurface && surfaceControlItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _surfaceControlItemsPanel(context, surfaceControlItems),
              ),
            if (!_isCommandWorklistSurface &&
                !_isOwnerWorkloadSurface &&
                !_isControlInboxSurface &&
                !_isStrategicBoardSurface &&
                !_isOperationalBoardSurface &&
                !_isControlIntelligenceSurface &&
                !_isRunbookSurface &&
                !_isSurfaceControlSurface &&
                items.isNotEmpty)
              SliverToBoxAdapter(
                child: _sectionHeader(
                  context,
                  title: _isIncidentBoardSurface
                      ? 'Incident queue'
                      : 'Operating items',
                  detail: _isIncidentBoardSurface
                      ? '${items.length} incident(s) in ${_incidentFilterLabel(_incidentWorkflowFilter)} view.'
                      : 'Campaigns, recent events, or records that need operator review.',
                ),
              ),
            if (!_isCommandWorklistSurface &&
                !_isOwnerWorkloadSurface &&
                !_isControlInboxSurface &&
                !_isStrategicBoardSurface &&
                !_isOperationalBoardSurface &&
                !_isControlIntelligenceSurface &&
                !_isRunbookSurface &&
                !_isSurfaceControlSurface &&
                items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _itemRow(context, items[index])),
              ),
            if (_isIncidentBoardSurface && rawItems.isNotEmpty && items.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(
                    'No incidents in ${_incidentFilterLabel(_incidentWorkflowFilter)} view.',
                    dense: true,
                  ),
                ),
              ),
            if (_isControlInboxSurface &&
                rawItems.isNotEmpty &&
                controlInboxItems.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(
                    'No inbox items in ${_controlInboxFilterLabel(_controlInboxFilter)} view.',
                    dense: true,
                  ),
                ),
              ),
            if (_isStrategicBoardSurface &&
                rawItems.isNotEmpty &&
                strategicBoardItems.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(
                    'No strategic items in ${_strategicFilterLabel(_strategicBoardFilter)} view.',
                    dense: true,
                  ),
                ),
              ),
            if (_isOperationalBoardSurface &&
                rawItems.isNotEmpty &&
                operationalBoardItems.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(
                    'No operating items in ${_operationalFilterLabel(_operationalBoardFilter)} view.',
                    dense: true,
                  ),
                ),
              ),
            if (_isRunbookSurface &&
                rawItems.isNotEmpty &&
                runbookItems.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(
                    'No runbooks in ${_runbookFilterLabel(_runbookFilter)} view.',
                    dense: true,
                  ),
                ),
              ),
            if (_isSurfaceControlSurface &&
                surfaceControlSourceItems.isNotEmpty &&
                surfaceControlItems.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(
                    'No surface items in ${_surfaceFilterLabel(_surfaceControlFilter)} view.',
                    dense: true,
                  ),
                ),
              ),
            if (_isOwnerWorkloadSurface &&
                features.isNotEmpty &&
                ownerWorkloadItems.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(
                    'No owners in ${_ownerFilterLabel(_ownerWorkloadFilter)} view.',
                    dense: true,
                  ),
                ),
              ),
            if (_isCommandWorklistSurface &&
                rawItems.isNotEmpty &&
                items.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner.info(
                    'No commands in ${_commandFilterLabel(_commandWorklistFilter)} view.',
                    dense: true,
                  ),
                ),
              ),
            if (!_loading && _status.isEmpty && !hasDashboardData)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No control data available yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5A6F66),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _opsInvalidServerUrlMessage(BuildContext context) {
  final isArabic = L10n.of(context).isArabic;
  return isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
}

String _opsFeatureUnavailableMessage(
  BuildContext context, {
  required String feature,
}) {
  final isArabic = L10n.of(context).isArabic;
  switch (feature) {
    case 'sonic':
      return isArabic
          ? 'ميزة Sonic غير متاحة على هذا الخادم.'
          : 'Sonic is unavailable on this server.';
    case 'cash':
      return isArabic
          ? 'ميزة القسائم/السحب النقدي غير متاحة على هذا الخادم.'
          : 'Cash vouchers are unavailable on this server.';
    case 'topup_vouchers':
      return isArabic
          ? 'ميزة قسائم الشحن غير متاحة على هذا الخادم.'
          : 'Topup vouchers are unavailable on this server.';
    case 'topup_kiosk':
      return isArabic
          ? 'ميزة كشك الشحن غير متاحة على هذا الخادم.'
          : 'Topup kiosk is unavailable on this server.';
    case 'system_status':
      return isArabic
          ? 'ميزة حالة النظام غير متاحة على هذا الخادم.'
          : 'System status is unavailable on this server.';
    case 'superadmin_stats':
      return isArabic
          ? 'الإحصاءات العامة غير متاحة على هذا الخادم.'
          : 'Global stats are unavailable on this server.';
    case 'ops_console':
      return isArabic
          ? 'لا توجد أدوات مشغل مفعلة على هذا الخادم.'
          : 'No operator tools are enabled on this server.';
    default:
      return isArabic
          ? 'الميزة غير متاحة على هذا الخادم.'
          : 'This feature is unavailable on this server.';
  }
}

String _opsOfflineReplayUnsafeMessage(BuildContext context) {
  final isArabic = L10n.of(context).isArabic;
  return isArabic
      ? 'تم تعطيل إعادة المحاولة دون اتصال لهذا الإجراء. تحقق من النتيجة ثم أعد المحاولة عند عودة الاتصال.'
      : 'Offline replay is disabled for this action. Check the result, then retry when online.';
}

String _opsMaskSecretValue(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  if (raw.length <= 4) {
    return '*' * raw.length;
  }
  if (raw.length <= 6) {
    return '${raw[0]}***${raw[raw.length - 1]}';
  }
  return '${raw.substring(0, 2)}***${raw.substring(raw.length - 2)}';
}

// Public for unit tests in `main_ops_session_guard_test.dart`.
String shamellOpsMaskSensitivePayloadForDisplay(String payload) {
  final raw = payload.trim();
  if (raw.isEmpty) return raw;
  final parts = raw.split('|');
  if (parts.length <= 1) {
    return _opsMaskSecretValue(raw);
  }
  final out = <String>[parts.first];
  for (final part in parts.skip(1)) {
    final idx = part.indexOf('=');
    if (idx <= 0 || idx >= part.length - 1) {
      out.add(_opsMaskSecretValue(part));
      continue;
    }
    final key = part.substring(0, idx).trim();
    final value = part.substring(idx + 1);
    out.add('$key=${_opsMaskSecretValue(value)}');
  }
  return out.join('|');
}

// Public for unit tests in `main_ops_session_guard_test.dart`.
bool shamellOpsTrustedWebPathRequiresSensitiveReveal(
  List<String> pathSegments,
) {
  if (pathSegments.isEmpty) {
    return false;
  }
  final normalized = pathSegments
      .map((segment) => segment.trim().toLowerCase())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (normalized.isEmpty) {
    return false;
  }
  return normalized.first == 'admin';
}

class _ControlDashboardAction {
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final List<String> searchTerms;
  final VoidCallback onTap;

  const _ControlDashboardAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.searchTerms,
    required this.onTap,
  });
}

class _ControlDashboardSection {
  final String title;
  final String description;
  final List<_ControlDashboardAction> actions;

  const _ControlDashboardSection({
    required this.title,
    required this.description,
    required this.actions,
  });
}

bool _controlDashboardActionMatchesQuery(
  _ControlDashboardAction action,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  final haystack = <String>[
    action.title,
    action.description,
    ...action.searchTerms,
  ].join(' ').toLowerCase();
  return haystack.contains(normalized);
}

List<_ControlDashboardSection> _controlDashboardFilterSections(
  List<_ControlDashboardSection> sections,
  String query,
) {
  if (query.trim().isEmpty) {
    return sections;
  }
  return sections
      .map(
        (section) => _ControlDashboardSection(
          title: section.title,
          description: section.description,
          actions: section.actions
              .where((action) =>
                  _controlDashboardActionMatchesQuery(action, query))
              .toList(growable: false),
        ),
      )
      .where((section) => section.actions.isNotEmpty)
      .toList(growable: false);
}

Widget _controlDashboardBadge(
  BuildContext context, {
  required IconData icon,
  required String label,
  Color color = const Color(0xFF175B46),
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .74),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    ),
  );
}

Widget _controlDashboardSignalCard({
  required BuildContext context,
  required IconData icon,
  required String label,
  required String value,
  String? detail,
  Color accent = const Color(0xFF14532D),
}) {
  final theme = Theme.of(context);
  return Container(
    width: 220,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .86),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: accent.withValues(alpha: .14)),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x100A2018),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(height: 14),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: const Color(0xFF5A7167),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            color: const Color(0xFF16392D),
            fontWeight: FontWeight.w900,
          ),
        ),
        if (detail != null && detail.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5D6D66),
              height: 1.35,
            ),
          ),
        ],
      ],
    ),
  );
}

class _ControlDashboardIntelligencePanel extends StatefulWidget {
  final String baseUrl;
  final Future<void> Function(String dashboardRoute)? onOpenDashboardRoute;

  const _ControlDashboardIntelligencePanel({
    required this.baseUrl,
    this.onOpenDashboardRoute,
  });

  @override
  State<_ControlDashboardIntelligencePanel> createState() =>
      _ControlDashboardIntelligencePanelState();
}

class _ControlDashboardIntelligencePanelState
    extends State<_ControlDashboardIntelligencePanel> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ControlDashboardIntelligencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl) {
      _future = _load();
    }
  }

  Future<Map<String, dynamic>?> _load() async {
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: const <String>[
        'admin',
        'dashboards',
        'control-intelligence',
      ],
    );
    if (uri == null) return null;
    final client = shamellHttpClient();
    try {
      final response = await client
          .get(
            uri,
            headers: await shamellSessionHeadersForBaseUrl(widget.baseUrl),
          )
          .timeout(_opsRequestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final direct = decoded.cast<String, dynamic>();
      final intelligence = direct['control_intelligence'];
      return intelligence is Map
          ? intelligence.cast<String, dynamic>()
          : direct;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  String _labelForKey(String key) {
    final normalized = key
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return key;
    return normalized
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<void> _openDashboardRoute(String route) async {
    final opener = widget.onOpenDashboardRoute;
    if (opener == null) return;
    final normalized = route.trim();
    if (normalized.isEmpty) return;
    await opener(normalized);
  }

  int _intValue(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  List<Map<String, dynamic>> _listValue(
    Map<String, dynamic> source,
    String key,
  ) {
    final value = source[key];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'action':
        return const Color(0xFFDC2626);
      case 'watch':
        return const Color(0xFFC2410C);
      default:
        return const Color(0xFF0F766E);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'action':
        return Icons.priority_high_rounded;
      case 'watch':
        return Icons.visibility_outlined;
      default:
        return Icons.verified_user_outlined;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'action':
        return 'Action';
      case 'watch':
        return 'Watch';
      default:
        return 'Healthy';
    }
  }

  Color _readinessColor(String status) {
    switch (status) {
      case 'risk':
        return const Color(0xFFDC2626);
      case 'gap':
        return const Color(0xFF64748B);
      case 'active':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF0F766E);
    }
  }

  IconData _readinessIcon(String status) {
    switch (status) {
      case 'risk':
        return Icons.report_problem_outlined;
      case 'gap':
        return Icons.add_circle_outline_rounded;
      case 'active':
        return Icons.radio_button_checked_rounded;
      default:
        return Icons.verified_rounded;
    }
  }

  String _readinessLabel(String status) {
    switch (status) {
      case 'risk':
        return 'Risk';
      case 'gap':
        return 'Gap';
      case 'active':
        return 'Active';
      default:
        return 'Mature';
    }
  }

  Color _gateColor(String state) {
    switch (state) {
      case 'blocked':
        return const Color(0xFFDC2626);
      case 'watch':
        return const Color(0xFFC2410C);
      default:
        return const Color(0xFF0F766E);
    }
  }

  IconData _gateIcon(String state) {
    switch (state) {
      case 'blocked':
        return Icons.lock_outline_rounded;
      case 'watch':
        return Icons.policy_outlined;
      default:
        return Icons.lock_open_rounded;
    }
  }

  String _gateLabel(String state) {
    switch (state) {
      case 'blocked':
        return 'Blocked';
      case 'watch':
        return 'Watch';
      default:
        return 'Open';
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFC2410C);
      default:
        return const Color(0xFF0F766E);
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'high':
        return Icons.priority_high_rounded;
      case 'medium':
        return Icons.timelapse_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  Widget _shell({
    required BuildContext context,
    required Widget child,
    Color accent = const Color(0xFF0F766E),
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 620),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: .16)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x12091F18),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _shell(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Control intelligence',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF17362B),
                  ),
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 3),
              ],
            ),
          );
        }
        final data = snapshot.data;
        if (data == null || data.isEmpty) {
          return _shell(
            context: context,
            accent: const Color(0xFF64748B),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Backend intelligence is waiting for an authorized Control session.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF52645D),
                      height: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh intelligence',
                  icon: const Icon(Icons.refresh_rounded),
                  color: const Color(0xFF64748B),
                  onPressed: _refresh,
                ),
              ],
            ),
          );
        }
        final status = (data['status'] ?? 'healthy').toString();
        final accent = _statusColor(status);
        final score = _intValue(data, 'operational_score').clamp(0, 100);
        final attention = _intValue(data, 'attention_total');
        final authority = _intValue(data, 'source_authority_percent');
        final sla = _intValue(data, 'attention_sla_minutes');
        final posture = (data['operating_posture'] ?? '').toString();
        final postureDetail = (data['posture_detail'] ?? '').toString();
        final lanes = _listValue(data, 'lanes');
        final laneSummaryRaw = data['lane_summary'];
        final laneSummary = laneSummaryRaw is Map
            ? laneSummaryRaw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final laneTotal = _intValue(laneSummary, 'total');
        final laneAction = _intValue(laneSummary, 'action');
        final laneWatch = _intValue(laneSummary, 'watch');
        final laneHealthy = _intValue(laneSummary, 'healthy');
        final readinessRaw = data['ecosystem_readiness'];
        final readiness = readinessRaw is Map
            ? readinessRaw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final readinessScore = _intValue(readiness, 'score').clamp(0, 100);
        final readinessTotal = _intValue(readiness, 'total');
        final readinessMature = _intValue(readiness, 'mature');
        final readinessActive = _intValue(readiness, 'active');
        final readinessRisk = _intValue(readiness, 'risk');
        final readinessGap = _intValue(readiness, 'gap');
        final readinessTopStatus =
            (readiness['top_layer_status'] ?? 'mature').toString();
        final readinessLayers = _listValue(data, 'readiness_layers');
        final readinessRoadmap = _listValue(data, 'readiness_roadmap');
        final gateSummaryRaw = data['gate_summary'];
        final gateSummary = gateSummaryRaw is Map
            ? gateSummaryRaw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final gateTotal = _intValue(gateSummary, 'total');
        final gateBlocked = _intValue(gateSummary, 'blocked');
        final gateWatch = _intValue(gateSummary, 'watch');
        final gateOpen = _intValue(gateSummary, 'open');
        final operatingGates = _listValue(data, 'operating_gates');
        final gateActions = _listValue(data, 'gate_actions');
        final controlAdoptionRaw = data['control_adoption'];
        final controlAdoption = controlAdoptionRaw is Map
            ? controlAdoptionRaw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final controlEventAuditRaw = controlAdoption['event_authority_audit'] ??
            data['control_event_authority_audit'];
        final controlEventAudit = controlEventAuditRaw is Map
            ? controlEventAuditRaw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final controlAuditTotal =
            _intValue(controlEventAudit, 'total_events_30d');
        final controlAuditAccepted =
            _intValue(controlEventAudit, 'accepted_events_30d');
        final controlAuditIgnored =
            _intValue(controlEventAudit, 'ignored_events_30d');
        final controlAuditPercent =
            _intValue(controlEventAudit, 'acceptance_percent').clamp(0, 100);
        final controlAuditStatus =
            (controlEventAudit['status'] ?? '').toString();
        var controlEventAuthorityActions =
            _listValue(controlAdoption, 'event_authority_actions');
        if (controlEventAuthorityActions.isEmpty) {
          controlEventAuthorityActions =
              _listValue(data, 'control_event_authority_actions');
        }
        var controlEventAuthorityBreakdown =
            _listValue(controlAdoption, 'event_authority_breakdown_30d');
        if (controlEventAuthorityBreakdown.isEmpty) {
          controlEventAuthorityBreakdown =
              _listValue(data, 'control_event_authority_breakdown_30d');
        }
        final controlEventAuthorityBreakdownSummaryRaw =
            controlAdoption['event_authority_breakdown_summary'] ??
                data['control_event_authority_breakdown_summary'];
        final controlEventAuthorityBreakdownSummary =
            controlEventAuthorityBreakdownSummaryRaw is Map
                ? controlEventAuthorityBreakdownSummaryRaw
                    .cast<String, dynamic>()
                : const <String, dynamic>{};
        final controlEventAuthorityBreakdownRoutes =
            _intValue(controlEventAuthorityBreakdownSummary, 'route_count');
        final controlEventAuthorityBreakdownSignals =
            _intValue(controlEventAuthorityBreakdownSummary, 'signal_count');
        var controlEventAuthorityRemediationQueue =
            _listValue(controlAdoption, 'event_authority_remediation_queue');
        if (controlEventAuthorityRemediationQueue.isEmpty) {
          controlEventAuthorityRemediationQueue =
              _listValue(data, 'control_event_authority_remediation_queue');
        }
        final controlEventAuthorityRemediationSummaryRaw =
            controlAdoption['event_authority_remediation_summary'] ??
                data['control_event_authority_remediation_summary'];
        final controlEventAuthorityRemediationSummary =
            controlEventAuthorityRemediationSummaryRaw is Map
                ? controlEventAuthorityRemediationSummaryRaw
                    .cast<String, dynamic>()
                : const <String, dynamic>{};
        final controlEventAuthorityRemediationTotal =
            _intValue(controlEventAuthorityRemediationSummary, 'total');
        final controlEventAuthorityRemediationSignals =
            _intValue(controlEventAuthorityRemediationSummary, 'signal_count');
        final controlEventAuthorityRemediationAttention =
            _intValue(controlEventAuthorityRemediationSummary, 'attention');
        final controlOpenEvents = _intValue(controlAdoption, 'open_events_30d');
        final controlNativeEvents =
            _intValue(controlAdoption, 'native_open_events_30d');
        final controlWebEvents =
            _intValue(controlAdoption, 'web_open_events_30d');
        final controlNativePercent =
            _intValue(controlAdoption, 'native_percent').clamp(0, 100);
        final controlUniqueRoutes =
            _intValue(controlAdoption, 'unique_routes_30d');
        final controlTopTitle =
            (controlAdoption['top_dashboard_title_30d'] ?? '').toString();
        final controlTopRoute =
            (controlAdoption['top_dashboard_route_30d'] ?? '').toString();
        final controlAdoptionActions =
            _listValue(data, 'control_adoption_actions');
        var controlAdoptionRoutes = _listValue(controlAdoption, 'routes_30d');
        if (controlAdoptionRoutes.isEmpty) {
          controlAdoptionRoutes =
              _listValue(data, 'control_adoption_routes_30d');
        }
        final controlCoverageRaw =
            controlAdoption['coverage'] ?? data['control_route_coverage'];
        final controlCoverage = controlCoverageRaw is Map
            ? controlCoverageRaw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final controlCoverageSummaryRaw = controlCoverage['summary'];
        final controlCoverageSummary = controlCoverageSummaryRaw is Map
            ? controlCoverageSummaryRaw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final controlCoverageTotal = _intValue(controlCoverageSummary, 'total');
        final controlCoverageMissing =
            _intValue(controlCoverageSummary, 'missing');
        final controlCoverageReady =
            _intValue(controlCoverageSummary, 'native_ready');
        final controlCoveragePercent =
            _intValue(controlCoverageSummary, 'coverage_percent').clamp(0, 100);
        final controlRequiredRoutes =
            _intValue(controlCoverageSummary, 'required_native_routes');
        final controlCoverageItems = _listValue(controlCoverage, 'items');
        final controlCoverageAttention = controlCoverageItems
            .where((item) {
              final itemStatus = (item['status'] ?? '').toString();
              return itemStatus == 'missing' ||
                  itemStatus == 'web_heavy' ||
                  itemStatus == 'mixed';
            })
            .take(3)
            .toList(growable: false);
        final priorities = _listValue(data, 'priorities');
        final nextActions = _listValue(data, 'next_actions');
        final actionPlan = _listValue(data, 'action_plan');
        final actionPlanSummaryRaw = data['action_plan_summary'];
        final actionPlanSummary = actionPlanSummaryRaw is Map
            ? actionPlanSummaryRaw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final actionPlanTotal = _intValue(actionPlanSummary, 'total');
        final actionPlanHigh = _intValue(actionPlanSummary, 'high');
        final actionPlanMedium = _intValue(actionPlanSummary, 'medium');
        final actionPlanLow = _intValue(actionPlanSummary, 'low');
        final ownerActions = _listValue(data, 'owner_action_summary');
        return _shell(
          context: context,
          accent: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_statusIcon(status), color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Control intelligence',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF17362B),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${_statusLabel(status)} · $attention attention signal(s) · $authority% event authority',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF5A6F66),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$score',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Refresh intelligence',
                    icon: const Icon(Icons.refresh_rounded),
                    color: accent,
                    onPressed: _refresh,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: score / 100,
                minHeight: 5,
                color: accent,
                backgroundColor: accent.withValues(alpha: .12),
              ),
              if (posture.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: .14)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.route_outlined, color: accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sla > 0 ? '$posture · SLA ${sla}m' : posture,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (postureDetail.isNotEmpty)
                              Text(
                                postureDetail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6F66),
                                  height: 1.35,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (controlOpenEvents > 0 ||
                  controlAuditTotal > 0 ||
                  controlAdoptionActions.isNotEmpty ||
                  controlEventAuthorityActions.isNotEmpty ||
                  controlEventAuthorityRemediationQueue.isNotEmpty ||
                  controlEventAuthorityBreakdown.isNotEmpty ||
                  controlCoverageItems.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF0F766E).withValues(alpha: .14),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.dashboard_customize_outlined,
                        color: Color(0xFF0F766E),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Native control adoption · $controlNativePercent%',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              controlRequiredRoutes > 0
                                  ? '$controlNativeEvents native · $controlWebEvents web · $controlUniqueRoutes/$controlRequiredRoutes route(s)'
                                  : '$controlNativeEvents native · $controlWebEvents web · $controlUniqueRoutes route(s)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF0F766E),
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                            ),
                            if (controlTopTitle.trim().isNotEmpty ||
                                controlTopRoute.trim().isNotEmpty)
                              Text(
                                'Top: ${controlTopTitle.trim().isNotEmpty ? controlTopTitle.trim() : controlTopRoute.trim()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6F66),
                                  height: 1.35,
                                ),
                              ),
                            if (controlAuditTotal > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    controlAuditIgnored > 0
                                        ? Icons.filter_alt_outlined
                                        : Icons.verified_outlined,
                                    size: 16,
                                    color: controlAuditIgnored > 0
                                        ? const Color(0xFFC2410C)
                                        : const Color(0xFF0F766E),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Authority audit · $controlAuditAccepted accepted · $controlAuditIgnored ignored · $controlAuditPercent% accepted',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: controlAuditIgnored > 0
                                            ? const Color(0xFFC2410C)
                                            : const Color(0xFF0F766E),
                                        fontWeight: FontWeight.w800,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                  if (controlAuditStatus.isNotEmpty)
                                    Text(
                                      _labelForKey(controlAuditStatus),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: const Color(0xFF5A6F66),
                                        fontWeight: FontWeight.w800,
                                      ),
                                  ),
                                ],
                              ),
                            ],
                            if (controlEventAuthorityActions.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ...controlEventAuthorityActions
                                  .take(2)
                                  .map((action) {
                                final title =
                                    (action['title'] ?? '').toString().trim();
                                final detail =
                                    (action['detail'] ?? '').toString().trim();
                                final severity =
                                    (action['severity'] ?? 'low').toString();
                                final signalCount =
                                    _intValue(action, 'signal_count');
                                final route =
                                    (action['dashboard_route'] ?? '')
                                        .toString()
                                        .trim();
                                final canOpen = route.isNotEmpty &&
                                    widget.onOpenDashboardRoute != null;
                                final color = _severityColor(severity);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _severityIcon(severity),
                                        color: color,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title.isEmpty
                                                  ? 'Event authority action'
                                                  : title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: const Color(0xFF17362B),
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            if (detail.isNotEmpty)
                                              Text(
                                                signalCount > 0
                                                    ? '$signalCount signal(s) · $detail'
                                                    : detail,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.bodySmall
                                                    ?.copyWith(
                                                  color:
                                                      const Color(0xFF5A6F66),
                                                  height: 1.25,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (canOpen)
                                        InkResponse(
                                          radius: 18,
                                          onTap: () =>
                                              _openDashboardRoute(route),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.open_in_new_rounded,
                                              color: color,
                                              size: 15,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            if (controlEventAuthorityRemediationQueue
                                .isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Divider(
                                height: 1,
                                color: const Color(0xFF0F766E)
                                    .withValues(alpha: .14),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                controlEventAuthorityRemediationTotal > 0
                                    ? 'Authority remediation queue · $controlEventAuthorityRemediationTotal item(s) · $controlEventAuthorityRemediationSignals signal(s) · $controlEventAuthorityRemediationAttention attention'
                                    : 'Authority remediation queue',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              ...controlEventAuthorityRemediationQueue
                                  .take(3)
                                  .map((item) {
                                final title =
                                    (item['title'] ?? '').toString().trim();
                                final detail =
                                    (item['detail'] ?? '').toString().trim();
                                final severity =
                                    (item['severity'] ?? 'low').toString();
                                final signals =
                                    _intValue(item, 'signal_count');
                                final accounts =
                                    _intValue(item, 'accounts_30d');
                                final dueMinutes =
                                    _intValue(item, 'due_in_minutes');
                                final route =
                                    (item['dashboard_route'] ?? '')
                                        .toString()
                                        .trim();
                                final targetRoute =
                                    (item['target_dashboard_route'] ?? route)
                                        .toString()
                                        .trim();
                                final cta =
                                    (item['cta_label'] ?? '').toString().trim();
                                final issueType =
                                    (item['issue_type'] ?? '').toString();
                                final color = _severityColor(severity);
                                final canOpen = route.isNotEmpty &&
                                    widget.onOpenDashboardRoute != null;
                                final metaLine = [
                                  if (signals > 0) '$signals signal(s)',
                                  if (accounts > 0) '$accounts account(s)',
                                  if (dueMinutes > 0) 'due ${dueMinutes}m',
                                  if (issueType.trim().isNotEmpty)
                                    _labelForKey(issueType),
                                ].join(' · ');
                                return Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _severityIcon(severity),
                                        color: color,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title.isEmpty
                                                  ? 'Authority remediation'
                                                  : title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: const Color(0xFF17362B),
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            if (metaLine.isNotEmpty)
                                              Text(
                                                metaLine,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: color,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.2,
                                                ),
                                              ),
                                            if (targetRoute.isNotEmpty)
                                              Text(
                                                targetRoute,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.bodySmall
                                                    ?.copyWith(
                                                  color:
                                                      const Color(0xFF5A6F66),
                                                  height: 1.2,
                                                ),
                                              ),
                                            if (detail.isNotEmpty)
                                              Text(
                                                detail,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.bodySmall
                                                    ?.copyWith(
                                                  color:
                                                      const Color(0xFF5A6F66),
                                                  height: 1.25,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (canOpen)
                                        InkResponse(
                                          radius: 18,
                                          onTap: () =>
                                              _openDashboardRoute(route),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              cta.isEmpty
                                                  ? Icons.open_in_new_rounded
                                                  : Icons.task_alt_rounded,
                                              color: color,
                                              size: 15,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            if (controlEventAuthorityBreakdown.isNotEmpty &&
                                controlEventAuthorityRemediationQueue
                                    .isEmpty) ...[
                              const SizedBox(height: 10),
                              Divider(
                                height: 1,
                                color: const Color(0xFF0F766E)
                                    .withValues(alpha: .14),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                controlEventAuthorityBreakdownRoutes > 0
                                    ? 'Authority migration lanes · $controlEventAuthorityBreakdownRoutes route(s) · $controlEventAuthorityBreakdownSignals signal(s)'
                                    : 'Authority migration lanes',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              ...controlEventAuthorityBreakdown
                                  .take(3)
                                  .map((issue) {
                                final issueType =
                                    (issue['issue_type'] ?? '').toString();
                                final issueLabel =
                                    (issue['issue_label'] ??
                                            _labelForKey(issueType))
                                        .toString()
                                        .trim();
                                final route =
                                    (issue['target_dashboard_route'] ?? '')
                                        .toString()
                                        .trim();
                                final title =
                                    (issue['target_dashboard_title'] ?? route)
                                        .toString()
                                        .trim();
                                final source =
                                    (issue['source_authority'] ?? 'unknown')
                                        .toString()
                                        .trim();
                                final surface =
                                    (issue['surface_authority'] ?? 'missing')
                                        .toString()
                                        .trim();
                                final severity =
                                    (issue['severity'] ?? 'low').toString();
                                final signals =
                                    _intValue(issue, 'signal_count');
                                final accounts =
                                    _intValue(issue, 'accounts_30d');
                                final color = _severityColor(severity);
                                final canOpen = route.isNotEmpty &&
                                    widget.onOpenDashboardRoute != null &&
                                    route != '/admin/dashboards/unknown';
                                return Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _severityIcon(severity),
                                        color: color,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title.isEmpty
                                                  ? issueLabel
                                                  : '$issueLabel · $title',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: const Color(0xFF17362B),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              '$signals signal(s) · $accounts account(s) · $source/$surface',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: color,
                                                height: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (canOpen)
                                        InkResponse(
                                          radius: 18,
                                          onTap: () =>
                                              _openDashboardRoute(route),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.open_in_new_rounded,
                                              color: Color(0xFF0F766E),
                                              size: 15,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            if (controlAdoptionRoutes.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ...controlAdoptionRoutes.take(3).map((routeRow) {
                                final routeTitle =
                                    (routeRow['dashboard_title'] ??
                                            routeRow['dashboard_route'] ??
                                            '')
                                        .toString()
                                        .trim();
                                final route =
                                    (routeRow['dashboard_route'] ?? '')
                                        .toString()
                                        .trim();
                                final total =
                                    _intValue(routeRow, 'open_events_30d');
                                final native = _intValue(
                                    routeRow, 'native_open_events_30d');
                                final web =
                                    _intValue(routeRow, 'web_open_events_30d');
                                final percent =
                                    _intValue(routeRow, 'native_percent')
                                        .clamp(0, 100);
                                final canOpen = route.isNotEmpty &&
                                    widget.onOpenDashboardRoute != null;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              routeTitle.isEmpty
                                                  ? 'Control route'
                                                  : routeTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: const Color(0xFF17362B),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '$percent%',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: const Color(0xFF0F766E),
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          if (canOpen) ...[
                                            const SizedBox(width: 2),
                                            InkResponse(
                                              radius: 18,
                                              onTap: () =>
                                                  _openDashboardRoute(route),
                                              child: const Padding(
                                                padding: EdgeInsets.all(4),
                                                child: Icon(
                                                  Icons.open_in_new_rounded,
                                                  color: Color(0xFF0F766E),
                                                  size: 15,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      LinearProgressIndicator(
                                        value: percent / 100,
                                        minHeight: 3,
                                        color: const Color(0xFF0F766E),
                                        backgroundColor: const Color(0xFF0F766E)
                                            .withValues(alpha: .12),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '$total opens · $native native · $web web',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: const Color(0xFF5A6F66),
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            if (controlCoverageItems.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Divider(
                                height: 1,
                                color: const Color(0xFF0F766E)
                                    .withValues(alpha: .14),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                controlCoverageTotal > 0
                                    ? 'Required route coverage · $controlCoveragePercent% · $controlCoverageReady/$controlCoverageTotal native-ready · $controlCoverageMissing missing'
                                    : 'Required route coverage',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              ...controlCoverageAttention.map((item) {
                                final route = (item['dashboard_route'] ?? '')
                                    .toString()
                                    .trim();
                                final title = (item['dashboard_title'] ?? route)
                                    .toString()
                                    .trim();
                                final group = (item['route_group'] ?? 'Control')
                                    .toString()
                                    .trim();
                                final itemStatus =
                                    (item['status'] ?? 'missing').toString();
                                final percent =
                                    _intValue(item, 'native_percent')
                                        .clamp(0, 100);
                                final color = itemStatus == 'native_ready'
                                    ? const Color(0xFF0F766E)
                                    : itemStatus == 'missing'
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFFC2410C);
                                final canOpen = route.isNotEmpty &&
                                    widget.onOpenDashboardRoute != null;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Row(
                                    children: [
                                      Icon(
                                        itemStatus == 'missing'
                                            ? Icons.radio_button_unchecked
                                            : Icons.call_split_outlined,
                                        color: color,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title.isEmpty
                                                  ? 'Control route'
                                                  : title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: const Color(0xFF17362B),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              '$group · $itemStatus · $percent% native',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: color,
                                                height: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (canOpen)
                                        InkResponse(
                                          radius: 18,
                                          onTap: () =>
                                              _openDashboardRoute(route),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.open_in_new_rounded,
                                              color: Color(0xFF0F766E),
                                              size: 15,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (controlAdoptionActions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...controlAdoptionActions.take(2).map((action) {
                    final title = (action['title'] ?? '').toString();
                    final detail = (action['detail'] ?? '').toString();
                    final runbookLine = _opsRunbookSummaryLine(action);
                    final route =
                        (action['dashboard_route'] ?? '').toString().trim();
                    final cta = (action['cta_label'] ?? '').toString();
                    final canOpen =
                        route.isNotEmpty && widget.onOpenDashboardRoute != null;
                    final row = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.call_merge_outlined,
                          color: Color(0xFF0F766E),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.isEmpty ? 'Control adoption' : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (detail.isNotEmpty)
                                Text(
                                  detail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF5A6F66),
                                    height: 1.35,
                                  ),
                                ),
                              if (runbookLine.isNotEmpty)
                                Text(
                                  runbookLine,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF17362B),
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (canOpen && cta.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            cta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF0F766E),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: canOpen
                          ? Material(
                              color: const Color(0xFF0F766E)
                                  .withValues(alpha: .06),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _openDashboardRoute(route),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: row,
                                ),
                              ),
                            )
                          : row,
                    );
                  }),
                ],
              ],
              if (actionPlan.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      actionPlanHigh > 0
                          ? _severityIcon('high')
                          : actionPlanMedium > 0
                              ? _severityIcon('medium')
                              : _severityIcon('low'),
                      color: actionPlanHigh > 0
                          ? _severityColor('high')
                          : actionPlanMedium > 0
                              ? _severityColor('medium')
                              : _severityColor('low'),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        actionPlanTotal > 0
                            ? 'Control action plan · $actionPlanTotal'
                            : 'Control action plan',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF17362B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '$actionPlanHigh high · $actionPlanMedium med · $actionPlanLow low',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF5A6F66),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...actionPlan.take(3).map((item) {
                  final title = (item['title'] ?? '').toString();
                  final detail = (item['detail'] ?? '').toString();
                  final owner = (item['owner'] ?? '').toString();
                  final cadence = (item['review_cadence'] ?? '').toString();
                  final severity = (item['severity'] ?? 'low').toString();
                  final dueMinutes = _intValue(item, 'due_in_minutes');
                  final route = (item['dashboard_route'] ?? '').toString();
                  final cta = (item['cta_label'] ?? '').toString();
                  final severityColor = _severityColor(severity);
                  final runbookLine = _opsRunbookSummaryLine(item);
                  final canOpen = route.trim().isNotEmpty &&
                      widget.onOpenDashboardRoute != null;
                  final ownerLine = [
                    if (owner.trim().isNotEmpty) owner.trim(),
                    if (cadence.trim().isNotEmpty) cadence.trim(),
                    if (dueMinutes > 0) 'due ${dueMinutes}m',
                  ].join(' · ');
                  final row = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_severityIcon(severity), color: severityColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.isEmpty ? 'Control action' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (ownerLine.isNotEmpty)
                              Text(
                                ownerLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: severityColor,
                                  fontWeight: FontWeight.w800,
                                  height: 1.3,
                                ),
                              ),
                            if (runbookLine.isNotEmpty)
                              Text(
                                runbookLine,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            if (detail.isNotEmpty)
                              Text(
                                detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6F66),
                                  height: 1.35,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (canOpen && cta.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          cta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: severityColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: canOpen
                        ? Material(
                            color: severityColor.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openDashboardRoute(route),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: row,
                              ),
                            ),
                          )
                        : row,
                  );
                }),
              ],
              if (ownerActions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.assignment_ind_outlined,
                        color: accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Owner workload · ${ownerActions.length}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF17362B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...ownerActions.take(4).map((item) {
                  final owner =
                      (item['owner'] ?? item['title'] ?? '').toString();
                  final count = _intValue(item, 'count');
                  final high = _intValue(item, 'high');
                  final medium = _intValue(item, 'medium');
                  final low = _intValue(item, 'low');
                  final dueMinutes = _intValue(item, 'due_in_minutes');
                  final primaryTitle = (item['primary_title'] ?? '').toString();
                  final permission =
                      (item['required_permission'] ?? '').toString();
                  final cadence = (item['review_cadence'] ?? '').toString();
                  final route = (item['dashboard_route'] ?? '').toString();
                  final severity = high > 0
                      ? 'high'
                      : medium > 0
                          ? 'medium'
                          : 'low';
                  final severityColor = _severityColor(severity);
                  final canOpen = route.trim().isNotEmpty &&
                      widget.onOpenDashboardRoute != null;
                  final metaLine = [
                    if (count > 0) '$count action(s)',
                    if (high > 0) '$high high',
                    if (medium > 0) '$medium med',
                    if (low > 0) '$low low',
                    if (dueMinutes > 0) 'due ${dueMinutes}m',
                  ].join(' · ');
                  final controlLine = [
                    if (permission.trim().isNotEmpty) permission.trim(),
                    if (cadence.trim().isNotEmpty) cadence.trim(),
                  ].join(' · ');
                  final row = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.person_pin_circle_outlined,
                          color: severityColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              owner.trim().isEmpty
                                  ? 'Control Operations'
                                  : owner.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (metaLine.isNotEmpty)
                              Text(
                                metaLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: severityColor,
                                  fontWeight: FontWeight.w800,
                                  height: 1.3,
                                ),
                              ),
                            if (primaryTitle.trim().isNotEmpty)
                              Text(
                                primaryTitle.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            if (controlLine.isNotEmpty)
                              Text(
                                controlLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6F66),
                                  height: 1.35,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: canOpen
                        ? Material(
                            color: severityColor.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openDashboardRoute(route),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: row,
                              ),
                            ),
                          )
                        : row,
                  );
                }),
              ],
              if (readinessTotal > 0) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      color: _readinessColor(readinessTopStatus),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Super-app readiness · $readinessScore',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF17362B),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '$readinessMature mature · $readinessActive active · $readinessRisk risk · $readinessGap gap',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5A6F66),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (readinessLayers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      padding: EdgeInsets.zero,
                      itemCount: readinessLayers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final layer = readinessLayers[index];
                        final layerStatus =
                            (layer['status'] ?? 'mature').toString();
                        final layerColor = _readinessColor(layerStatus);
                        final title =
                            (layer['title'] ?? layer['id'] ?? '').toString();
                        final route =
                            (layer['dashboard_route'] ?? '').toString();
                        final canOpen = route.trim().isNotEmpty &&
                            widget.onOpenDashboardRoute != null;
                        return ActionChip(
                          avatar: Icon(
                            _readinessIcon(layerStatus),
                            size: 16,
                          ),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 190),
                            child: Text(
                              '$title · ${_readinessLabel(layerStatus)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          backgroundColor: layerColor.withValues(alpha: .10),
                          side: BorderSide(
                            color: layerColor.withValues(alpha: .20),
                          ),
                          tooltip: canOpen ? 'Open $title dashboard' : title,
                          onPressed:
                              canOpen ? () => _openDashboardRoute(route) : null,
                        );
                      },
                    ),
                  ),
                ],
              ],
              if (readinessRoadmap.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...readinessRoadmap.take(2).map((item) {
                  final title = (item['title'] ?? '').toString();
                  final objective = (item['objective'] ?? '').toString();
                  final status = (item['status'] ?? 'mature').toString();
                  final route = (item['dashboard_route'] ?? '').toString();
                  final cta = (item['cta_label'] ?? '').toString();
                  final owner = (item['owner'] ?? '').toString();
                  final cadence = (item['review_cadence'] ?? '').toString();
                  final accountability = [
                    if (owner.trim().isNotEmpty) owner.trim(),
                    if (cadence.trim().isNotEmpty) cadence.trim(),
                  ].join(' · ');
                  final canOpen = route.trim().isNotEmpty &&
                      widget.onOpenDashboardRoute != null;
                  final roadmapColor = _readinessColor(status);
                  final content = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_readinessIcon(status), color: roadmapColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.isEmpty
                                  ? _readinessLabel(status)
                                  : '$title · ${_readinessLabel(status)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (accountability.isNotEmpty)
                              Text(
                                accountability,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: roadmapColor,
                                  fontWeight: FontWeight.w800,
                                  height: 1.3,
                                ),
                              ),
                            if (objective.isNotEmpty)
                              Text(
                                objective,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6F66),
                                  height: 1.35,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (canOpen && cta.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          cta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: roadmapColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: canOpen
                        ? Material(
                            color: roadmapColor.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openDashboardRoute(route),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: content,
                              ),
                            ),
                          )
                        : content,
                  );
                }),
              ],
              if (operatingGates.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.traffic_outlined,
                      color: gateBlocked > 0
                          ? _gateColor('blocked')
                          : gateWatch > 0
                              ? _gateColor('watch')
                              : _gateColor('open'),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        gateTotal > 0
                            ? 'Operating gates · $gateTotal'
                            : 'Operating gates',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF17362B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '$gateBlocked blocked · $gateWatch watch · $gateOpen open',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF5A6F66),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: operatingGates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final gate = operatingGates[index];
                      final gateState =
                          (gate['gate_state'] ?? 'open').toString();
                      final gateColor = _gateColor(gateState);
                      final title =
                          (gate['title'] ?? gate['id'] ?? '').toString();
                      final route = (gate['dashboard_route'] ?? '').toString();
                      final decision = (gate['decision'] ?? '').toString();
                      final canOpen = route.trim().isNotEmpty &&
                          widget.onOpenDashboardRoute != null;
                      return ActionChip(
                        avatar: Icon(_gateIcon(gateState), size: 16),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190),
                          child: Text(
                            '$title · ${_gateLabel(gateState)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        backgroundColor: gateColor.withValues(alpha: .10),
                        side: BorderSide(
                          color: gateColor.withValues(alpha: .20),
                        ),
                        tooltip: decision.isNotEmpty ? decision : 'Open $title',
                        onPressed:
                            canOpen ? () => _openDashboardRoute(route) : null,
                      );
                    },
                  ),
                ),
                if (gateActions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...gateActions.take(2).map((action) {
                    final title = (action['title'] ?? '').toString();
                    final gateState =
                        (action['gate_state'] ?? 'blocked').toString();
                    final owner = (action['owner'] ?? '').toString();
                    final criteria =
                        (action['unlock_criteria'] ?? '').toString();
                    final cta = (action['cta_label'] ?? '').toString();
                    final route = (action['dashboard_route'] ?? '').toString();
                    final gateColor = _gateColor(gateState);
                    final runbookLine = _opsRunbookSummaryLine(action);
                    final canOpen = route.trim().isNotEmpty &&
                        widget.onOpenDashboardRoute != null;
                    final row = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_gateIcon(gateState), color: gateColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.isEmpty
                                    ? _gateLabel(gateState)
                                    : '$title · ${_gateLabel(gateState)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: const Color(0xFF17362B),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (owner.trim().isNotEmpty)
                                Text(
                                  owner.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: gateColor,
                                    fontWeight: FontWeight.w800,
                                    height: 1.3,
                                  ),
                                ),
                              if (runbookLine.isNotEmpty)
                                Text(
                                  runbookLine,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF17362B),
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                              if (criteria.isNotEmpty)
                                Text(
                                  criteria,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF5A6F66),
                                    height: 1.35,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (canOpen && cta.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            cta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: gateColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: canOpen
                          ? Material(
                              color: gateColor.withValues(alpha: .06),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _openDashboardRoute(route),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: row,
                                ),
                              ),
                            )
                          : row,
                    );
                  }),
                ],
              ],
              if (nextActions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: nextActions.map((action) {
                    final title = (action['cta_label'] ?? action['title'] ?? '')
                        .toString();
                    final route =
                        (action['dashboard_route'] ?? '').toString().trim();
                    final severity = (action['severity'] ?? 'low').toString();
                    final actionColor = severity == 'high'
                        ? const Color(0xFFDC2626)
                        : severity == 'medium'
                            ? const Color(0xFFC2410C)
                            : const Color(0xFF0F766E);
                    final canOpen =
                        route.isNotEmpty && widget.onOpenDashboardRoute != null;
                    return ActionChip(
                      avatar: Icon(
                        canOpen
                            ? Icons.open_in_new_rounded
                            : Icons.play_arrow_rounded,
                        size: 16,
                      ),
                      label: Text(title.isEmpty ? 'Open dashboard' : title),
                      backgroundColor: actionColor.withValues(alpha: .10),
                      side: BorderSide(
                        color: actionColor.withValues(alpha: .22),
                      ),
                      tooltip: canOpen ? title : null,
                      onPressed:
                          canOpen ? () => _openDashboardRoute(route) : null,
                    );
                  }).toList(growable: false),
                ),
              ],
              if (lanes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        laneTotal > 0
                            ? 'Operating lanes · $laneTotal'
                            : 'Operating lanes',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF17362B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '$laneAction action · $laneWatch watch · $laneHealthy healthy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF5A6F66),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: lanes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final lane = lanes[index];
                      final laneStatus =
                          (lane['status'] ?? 'healthy').toString();
                      final laneColor = _statusColor(laneStatus);
                      final title =
                          (lane['title'] ?? lane['id'] ?? '').toString();
                      final count = _intValue(lane, 'signal_count');
                      final route = (lane['dashboard_route'] ?? '').toString();
                      final canOpen = route.trim().isNotEmpty &&
                          widget.onOpenDashboardRoute != null;
                      return ActionChip(
                        avatar: Icon(_statusIcon(laneStatus), size: 16),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190),
                          child: Text(
                            '$title · $count',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        backgroundColor: laneColor.withValues(alpha: .10),
                        side: BorderSide(
                          color: laneColor.withValues(alpha: .20),
                        ),
                        tooltip: canOpen ? 'Open $title dashboard' : null,
                        onPressed:
                            canOpen ? () => _openDashboardRoute(route) : null,
                      );
                    },
                  ),
                ),
              ],
              if (priorities.isNotEmpty) ...[
                const SizedBox(height: 14),
                ...priorities.take(2).map((item) {
                  final title = (item['title'] ?? '').toString();
                  final detail = (item['detail'] ?? '').toString();
                  final severity = (item['severity'] ?? 'low').toString();
                  final route = (item['dashboard_route'] ?? '').toString();
                  final canOpen = route.trim().isNotEmpty &&
                      widget.onOpenDashboardRoute != null;
                  final priorityColor = severity == 'high'
                      ? const Color(0xFFDC2626)
                      : severity == 'medium'
                          ? const Color(0xFFC2410C)
                          : const Color(0xFF0F766E);
                  final row = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        canOpen
                            ? Icons.open_in_new_rounded
                            : Icons.arrow_right_alt_rounded,
                        color: priorityColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF17362B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (detail.isNotEmpty)
                              Text(
                                detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6F66),
                                  height: 1.35,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: canOpen
                        ? Material(
                            color: priorityColor.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openDashboardRoute(route),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: row,
                              ),
                            ),
                          )
                        : row,
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}

Widget _controlDashboardActionCard(
  BuildContext context,
  _ControlDashboardAction action,
) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 280,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: action.accent.withValues(alpha: .12)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0F081F17),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: action.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(action.icon, color: action.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF17362B),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          action.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF5A6F66),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Open board',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: action.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded, color: action.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _controlDashboardSectionCard(
  BuildContext context,
  _ControlDashboardSection section,
) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFFD7E8DF)),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x10091F18),
          blurRadius: 26,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF16362B),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          section.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF5A6F66),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: section.actions
              .map((action) => _controlDashboardActionCard(context, action))
              .toList(growable: false),
        ),
      ],
    ),
  );
}

Widget _controlDashboardBody({
  required BuildContext context,
  required String eyebrow,
  required String title,
  required String subtitle,
  required TextEditingController searchController,
  required ValueChanged<String> onSearchChanged,
  required List<Widget> badges,
  required List<Widget> signalCards,
  required List<_ControlDashboardSection> sections,
  required String emptyMessage,
}) {
  final theme = Theme.of(context);
  return Stack(
    children: [
      const AppBG(),
      SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFF5FBF8),
                    Color(0xFFE6F3EC),
                    Color(0xFFD3E8DD),
                  ],
                ),
                border: Border.all(color: const Color(0xFFD4E7DE)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x140A2017),
                    blurRadius: 34,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .78),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFD8E9E1)),
                    ),
                    child: Text(
                      eyebrow,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF165A45),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: const Color(0xFF15382B),
                      fontWeight: FontWeight.w900,
                      height: .95,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Text(
                      subtitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF476257),
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText:
                          'Search boards, queues, payouts, access, operators…',
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: .86),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFD4E6DD)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFD4E6DD)),
                      ),
                    ),
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: badges,
                    ),
                  ],
                ],
              ),
            ),
            if (signalCards.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: signalCards,
              ),
            ],
            const SizedBox(height: 20),
            if (sections.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .88),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFD8E7DF)),
                ),
                child: Text(
                  emptyMessage,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF4E655C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              ...sections.map(
                (section) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _controlDashboardSectionCard(context, section),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

Future<bool> _opsRequireSensitiveReveal(BuildContext context) async {
  return true;
}

Widget _opsFeatureUnavailableView(
  BuildContext context, {
  required String feature,
  required IconData icon,
}) {
  final theme = Theme.of(context);
  final isArabic = L10n.of(context).isArabic;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 40,
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
                const SizedBox(height: 12),
                Text(
                  _opsFeatureUnavailableMessage(context, feature: feature),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isArabic
                      ? 'تم إخفاء هذا التدفق لأن واجهات الخدمة غير مفعلة في الواجهة الخلفية الحالية.'
                      : 'This flow is hidden because the required backend APIs are not enabled on the current server.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _opsAccessDeniedMessage(
  BuildContext context, {
  required String console,
}) {
  final isArabic = L10n.of(context).isArabic;
  switch (console) {
    case 'ops':
      return isArabic
          ? 'حسابك غير مخول للوصول إلى أدوات المشغل.'
          : 'Your account is not allowed to access operator tools.';
    case 'admin':
      return isArabic
          ? 'حسابك غير مخول للوصول إلى لوحة الإدارة.'
          : 'Your account is not allowed to access the admin console.';
    case 'superadmin':
      return isArabic
          ? 'حسابك غير مخول للوصول إلى لوحة Superadmin.'
          : 'Your account is not allowed to access the Superadmin console.';
    case 'payments':
      return isArabic
          ? 'حسابك غير مخول للوصول إلى أدوات المدفوعات التشغيلية.'
          : 'Your account is not allowed to access payments operator tools.';
    default:
      return isArabic
          ? 'حسابك غير مخول للوصول إلى هذه الصفحة.'
          : 'Your account is not allowed to access this page.';
  }
}

Widget _opsAccessDeniedView(
  BuildContext context, {
  required String console,
  required IconData icon,
}) {
  final theme = Theme.of(context);
  final isArabic = L10n.of(context).isArabic;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 40,
                  color: theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
                const SizedBox(height: 12),
                Text(
                  _opsAccessDeniedMessage(context, console: console),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isArabic
                      ? 'تم حجب هذا المسار داخل التطبيق لأن الأدوار المخزنة للحساب لا تسمح به.'
                      : 'This route is blocked in-app because the stored account roles do not permit it.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _opsIdempotencyKey(String prefix) {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rnd = _opsIdempotencyRandom();
  final randHi =
      rnd.nextInt(_opsIdempotencyRandomMax).toRadixString(36).padLeft(7, '0');
  final randLo =
      rnd.nextInt(_opsIdempotencyRandomMax).toRadixString(36).padLeft(7, '0');
  return '$prefix-$ts-$randHi$randLo';
}

const int _opsIdempotencyRandomMax = 0x100000000;

Random _opsIdempotencyRandom() {
  try {
    return Random.secure();
  } catch (_) {
    return Random(DateTime.now().microsecondsSinceEpoch);
  }
}

SuperappAPI buildSuperadminPaymentsApi({
  required String baseUrl,
  required String walletId,
}) {
  return SuperappAPI.light(
    baseUrl: baseUrl,
    walletId: walletId,
  );
}

class TopupPage extends StatefulWidget {
  final String baseUrl;
  final bool triggerScanOnOpen;
  final http.Client? client;
  final Future<String?> Function(BuildContext context)? scanLauncher;
  final String? initialCurrency;
  const TopupPage(this.baseUrl,
      {super.key,
      this.triggerScanOnOpen = false,
      this.client,
      this.scanLauncher,
      this.initialCurrency});
  @override
  State<TopupPage> createState() => _TopupPageState();
}

class _TopupPageState extends State<TopupPage>
    with SafeSetStateMixin<TopupPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  final amtCtrl = TextEditingController(text: '10000');
  final walletCtrl = TextEditingController();
  String out = '';
  String topupPayload = '';
  String _curSym = 'SYP';
  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
    final initialCurrency = (widget.initialCurrency ?? '').trim();
    if (initialCurrency.isNotEmpty) _curSym = initialCurrency;
    _load();
    if (widget.triggerScanOnOpen) {
      Future.microtask(_scanTopupAndDo);
    }
  }

  @override
  void dispose() {
    amtCtrl.clear();
    walletCtrl.clear();
    amtCtrl.dispose();
    walletCtrl.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final storedWalletId =
        await loadStoredWalletId(sp: sp, baseUrlOverride: widget.baseUrl) ?? '';
    final cs = await loadStoredCurrencySymbol(
      baseUrl: widget.baseUrl,
      sp: sp,
    );
    if (walletCtrl.text.trim().isEmpty && storedWalletId.trim().isNotEmpty) {
      walletCtrl.text = storedWalletId;
    }
    if ((widget.initialCurrency ?? '').trim().isEmpty &&
        (_curSym.trim().isEmpty || _curSym == 'SYP') &&
        cs != null &&
        cs.isNotEmpty) {
      _curSym = cs;
    }
    setState(() {});
  }

  Future<void> _doTopup() async {
    setState(() => out = '...');
    final ikey = _opsIdempotencyKey('top');
    final w = walletCtrl.text.trim();
    final amt = double.tryParse(amtCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (w.isEmpty || !amt.isFinite || amt <= 0) {
      setState(() => out = 'Please check wallet and amount');
      return;
    }
    final amountCents = shamellPaymentAmountMajorToCents(amt);
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', 'wallets', w, 'topup'],
    );
    if (uri == null) {
      setState(() => out = _opsInvalidServerUrlMessage(context));
      return;
    }
    final headers = await _topupHeaders(
      idempotencyKey: ikey,
      walletId: w,
      amountCents: amountCents,
    );
    if (headers == null) {
      return;
    }
    final body = jsonEncode({'amount_cents': amountCents});
    try {
      final r = await _http
          .post(uri, headers: headers, body: body)
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        final isAr = L10n.of(context).isArabic;
        out = r.statusCode >= 200 && r.statusCode < 300
            ? (isAr ? 'تم.' : 'OK.')
            : sanitizeHttpError(
                statusCode: r.statusCode,
                rawBody: r.body,
                isArabic: isAr,
              );
      });
      if (r.statusCode >= 500) {
        await OfflineQueue.enqueue(
          OfflineTask(
              id: ikey,
              method: 'POST',
              url: uri.toString(),
              headers: headers,
              body: body,
              tag: 'payments_topup',
              createdAt: DateTime.now().millisecondsSinceEpoch),
          baseUrlOverride: widget.baseUrl,
        );
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Offline: queued top‑up')));
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      await OfflineQueue.enqueue(
        OfflineTask(
            id: ikey,
            method: 'POST',
            url: uri.toString(),
            headers: headers,
            body: body,
            tag: 'payments_topup',
            createdAt: DateTime.now().millisecondsSinceEpoch),
        baseUrlOverride: widget.baseUrl,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offline saved: Top‑up')));
      setState(() => out = 'Queued (offline)');
    }
  }

  Future<Map<String, String>?> _topupHeaders({
    required String idempotencyKey,
    required String walletId,
    required int amountCents,
  }) async {
    final headers = await _hdr(json: true, baseUrl: widget.baseUrl);
    headers['Idempotency-Key'] = idempotencyKey;
    final deviceId = await getOrCreateStableDeviceId(
      baseUrlOverride: widget.baseUrl,
    );
    headers['X-Device-ID'] = deviceId;
    try {
      final attestationHeaders =
          await shamellBuildPaymentMutationAttestationHeaders(
        baseUrl: widget.baseUrl,
        deviceId: deviceId,
        operation: 'payments_topup',
        resourceId: shamellPaymentTopupAttestationResourceId(
          walletId: walletId,
          amountCents: amountCents,
        ),
        client: _http,
      );
      headers.addAll(attestationHeaders);
      return headers;
    } on PaymentMutationAttestationHttpFailure catch (e) {
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: e.statusCode,
        rawBody: e.rawBody,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return null;
      }
      setState(() {
        out = sanitizeHttpError(
          statusCode: e.statusCode,
          rawBody: e.rawBody,
          isArabic: L10n.of(context).isArabic,
        );
      });
      return null;
    } catch (e) {
      setState(() {
        out = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
      return null;
    }
  }

  void _genTopupQR() {
    final w = walletCtrl.text.trim();
    final a = double.tryParse(amtCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
    if (w.isEmpty) {
      setState(() => out = 'Wallet required');
      return;
    }
    final amountCents =
        a.isFinite && a > 0 ? shamellPaymentAmountMajorToCents(a) : null;
    setState(() {
      topupPayload = buildShamellPaymentQrPayload(
        type: ShamellPaymentQrPayloadType.topup,
        walletId: w,
        currency: _curSym,
        amountCents: amountCents,
      );
    });
  }

  Future<void> _scanTopupAndDo() async {
    final res = await (widget.scanLauncher?.call(context) ??
        Navigator.push<String?>(
            context, MaterialPageRoute(builder: (_) => const ScanPage())));
    if (res == null) return;
    try {
      final parsed = parseShamellPaymentQrPayload(res);
      if (parsed != null &&
          parsed.type == ShamellPaymentQrPayloadType.topup &&
          (parsed.walletId ?? '').trim().isNotEmpty) {
        walletCtrl.text = parsed.walletId!.trim();
        final amountText = _amountInputText(parsed.amountCents);
        if (amountText.isNotEmpty) amtCtrl.text = amountText;
        final currency = (parsed.currency ?? '').trim();
        if (currency.isNotEmpty) {
          if (!shamellIsSupportedWalletCurrency(currency)) {
            if (mounted)
              setState(() => out = 'Unsupported QR currency: $currency.');
            return;
          }
          _curSym = currency;
        }
        if (mounted) setState(() {});
        await _doTopup();
        return;
      }
      final parts = res.split('|');
      if (parts.isEmpty) return;
      final kind = parts.first.toUpperCase();
      if (kind != 'TOPUP') return;
      final map = <String, String>{};
      for (final p in parts.skip(1)) {
        final kv = p.split('=');
        if (kv.length != 2) continue;
        String decoded;
        try {
          decoded = Uri.decodeComponent(kv[1]);
        } catch (_) {
          continue;
        }
        map[kv[0]] = decoded;
      }
      final amount = int.tryParse(map['amount'] ?? '0') ?? 0;
      if (map['code'] != null && map['sig'] != null) {
        if (!_opsTopupVoucherRedeemEnabled) {
          if (mounted) {
            setState(() {
              out = _opsFeatureUnavailableMessage(
                context,
                feature: 'topup_vouchers',
              );
            });
          }
          return;
        }
        // Voucher redeem flow
        final sp = await SharedPreferences.getInstance();
        final toWallet = await loadStoredWalletId(
              sp: sp,
              baseUrlOverride: widget.baseUrl,
            ) ??
            '';
        if (toWallet.isEmpty) {
          if (mounted) setState(() => out = 'No wallet in session');
          return;
        }
        final uri = _opsApiChildUri(
          baseUrl: widget.baseUrl,
          pathSegments: <String>['topup', 'redeem'],
        );
        if (uri == null) {
          if (mounted) {
            setState(() => out = _opsInvalidServerUrlMessage(context));
          }
          return;
        }
        final headers = await _hdr(json: true, baseUrl: widget.baseUrl);
        final body = jsonEncode({
          'code': map['code'],
          'amount_cents': amount,
          'sig': map['sig'],
          'to_wallet_id': toWallet
        });
        final r = await _http
            .post(uri, headers: headers, body: body)
            .timeout(_opsRequestTimeout);
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        setState(() {
          final isAr = L10n.of(context).isArabic;
          out = r.statusCode >= 200 && r.statusCode < 300
              ? (isAr ? 'تم.' : 'OK.')
              : sanitizeHttpError(
                  statusCode: r.statusCode,
                  rawBody: r.body,
                  isArabic: isAr,
                );
        });
        return;
      }
      if (map['wallet'] != null) {
        walletCtrl.text = map['wallet']!;
      }
      if (amount > 0) {
        amtCtrl.text = amount.toString();
      }
      setState(() {});
      await _doTopup();
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
    }
  }

  String _amountInputText(int? cents) {
    if (cents == null || cents <= 0) return '';
    if (cents % 100 == 0) return (cents ~/ 100).toString();
    return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final rawAmount = double.tryParse(amtCtrl.text.trim().replaceAll(',', '.'));
    final amountPreview = rawAmount != null && rawAmount > 0
        ? '${rawAmount.toStringAsFixed(rawAmount.truncateToDouble() == rawAmount ? 0 : 2)} $_curSym'
        : '—';
    final walletLabel = walletCtrl.text.trim().isEmpty
        ? '—'
        : walletCtrl.text.trim().length > 16
            ? '${walletCtrl.text.trim().substring(0, 8)}…${walletCtrl.text.trim().substring(walletCtrl.text.trim().length - 4)}'
            : walletCtrl.text.trim();
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShamellPaymentCardSurface(
            tone: ShamellPaymentCardTone.hero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.homeTopup,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.isArabic
                      ? 'اشحن المحفظة مباشرة أو حضّر رمز QR للشحن السريع.'
                      : 'Top up directly or generate a QR code for fast loading.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShamellPaymentMetricChip(
                      label: l.isArabic ? 'المحفظة' : 'Wallet',
                      value: walletLabel,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    ShamellPaymentMetricChip(
                      label: l.isArabic ? 'المعاينة' : 'Preview',
                      value: amountPreview,
                      icon: Icons.payments_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ShamellPaymentCardSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: walletCtrl,
                  decoration: const InputDecoration(labelText: 'Wallet ID'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amtCtrl,
                  decoration: InputDecoration(labelText: 'Amount ($_curSym)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PayActionButton(
                      icon: Icons.qr_code_scanner,
                      label: 'Scan & Topup',
                      onTap: _scanTopupAndDo,
                    ),
                    PayActionButton(
                      icon: Icons.qr_code_2,
                      label: 'Generate Topup QR',
                      onTap: _genTopupQR,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (topupPayload.isNotEmpty)
            ShamellPaymentCardSurface(
              tone: ShamellPaymentCardTone.soft,
              child: Column(
                children: [
                  SelectableText(
                    topupPayload,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  QrImageView(data: topupPayload, size: 220),
                ],
              ),
            ),
          if (out.isNotEmpty) ...[
            const SizedBox(height: 12),
            ShamellPaymentCardSurface(
              tone: ShamellPaymentCardTone.soft,
              child: SelectableText(
                out,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.84),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return DomainPageScaffold(
      background: const AppBG(),
      title: l.homeTopup,
      child: content,
      scrollable: true,
    );
  }
}

// Topup Kiosk: create and print batches of topup vouchers
class TopupKioskPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? client;
  const TopupKioskPage(this.baseUrl, {super.key, this.client});
  @override
  State<TopupKioskPage> createState() => _TopupKioskPageState();
}

// Ops hub page: consolidate operator/admin tools under one icon
class OpsPage extends StatefulWidget {
  final String baseUrl;
  const OpsPage(this.baseUrl, {super.key});

  @override
  State<OpsPage> createState() => _OpsPageState();
}

class _OpsPageState extends State<OpsPage> with SafeSetStateMixin<OpsPage> {
  bool _loadingPrivileges = true;
  bool _opsAllowed = false;
  bool _adminAllowed = false;
  bool _paymentsAllowed = false;
  bool _coachBoardingAllowed = false;
  bool _coachEnabled = false;
  ShamellDashboardPolicy? _dashboardPolicy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPrivileges();
    });
  }

  Future<void> _loadPrivileges() async {
    final policy = await shamellResolveDashboardPolicy(
      context,
      baseUrl: widget.baseUrl,
    );
    if (!mounted) return;
    setState(() {
      _dashboardPolicy = policy;
      _opsAllowed = policy.allowsOpsConsole;
      _adminAllowed = policy.allowsAdminConsole;
      _paymentsAllowed = policy.allowsPaymentsOperatorSurface;
      _coachEnabled = policy.capabilities.coach;
      _coachBoardingAllowed = policy.allowsCoachBoardingConsole;
      _loadingPrivileges = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(title: Text(l.opsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_opsAllowed) {
      return Scaffold(
        appBar: AppBar(title: Text(l.opsTitle)),
        body: _opsAccessDeniedView(
          context,
          console: 'ops',
          icon: Icons.layers_outlined,
        ),
      );
    }
    void showWebAdminLaunchError() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تعذّر فتح صفحة الإدارة.'
                : 'Could not open the admin page.',
          ),
        ),
      );
    }

    Future<void> openTrustedWebPath(List<String> pathSegments) async {
      if (shamellOpsTrustedWebPathRequiresSensitiveReveal(pathSegments)) {
        final approved = await _opsRequireSensitiveReveal(context);
        if (!approved) {
          return;
        }
      }
      final uri = shamellTrustedWebChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: pathSegments,
      );
      if (uri == null) {
        showWebAdminLaunchError();
        return;
      }
      await launchWithSession(uri);
    }

    Widget btn(IconData icon, String label, VoidCallback onTap) {
      return SizedBox(
        width: 240,
        child: PayActionButton(icon: icon, label: label, onTap: onTap),
      );
    }

    void openPaymentsControlDashboard() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShamellControlDomainDashboardPage(
            baseUrl: widget.baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'payments'],
            title: 'Payments control',
            subtitle:
                'Wallet authority, send safety, attestation hygiene, active challenges, and trusted payment telemetry.',
            icon: Icons.account_balance_wallet_outlined,
            accent: Tokens.colorPayments,
          ),
        ),
      );
    }

    final nativeTiles = <Widget>[
      if (_paymentsAllowed)
        btn(Icons.account_balance_wallet_outlined, 'Payments control', () {
          openPaymentsControlDashboard();
        }),
      if (_coachEnabled && _coachBoardingAllowed)
        btn(Icons.directions_bus_outlined, 'Coach control', () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShamellControlDomainDashboardPage(
                baseUrl: widget.baseUrl,
                pathSegments: const <String>['admin', 'dashboards', 'coach'],
                title: 'Coach control',
                subtitle:
                    'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority in one control board.',
                icon: Icons.directions_bus_outlined,
                accent: const Color(0xFF0F766E),
              ),
            ),
          );
        }),
      if (_opsTopupKioskEnabled)
        btn(Icons.local_printshop_outlined, 'Topup Kiosk', () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TopupKioskPage(widget.baseUrl)),
          );
        }),
      if (_opsSystemStatusEnabled)
        btn(Icons.health_and_safety_outlined, l.opsSystemStatus, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SystemStatusPage(widget.baseUrl)),
          );
        }),
    ];
    final webTiles = <Widget>[
      if (_adminAllowed)
        btn(Icons.shield_moon_outlined, 'Risk Admin', () {
          openTrustedWebPath(const ['admin', 'risk']);
        }),
      if (_adminAllowed)
        btn(Icons.file_download_outlined, 'Admin Exports', () {
          openTrustedWebPath(const ['admin', 'exports']);
        }),
      if (_adminAllowed)
        btn(Icons.manage_accounts_outlined, 'Topup Sellers', () {
          openTrustedWebPath(const ['admin', 'topup-sellers']);
        }),
    ];
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.opsTitle),
        const SizedBox(height: 8),
        _ControlDashboardIntelligencePanel(
          baseUrl: widget.baseUrl,
          onOpenDashboardRoute: (route) => _openControlDashboardBackendRoute(
            context,
            baseUrl: widget.baseUrl,
            dashboardRoute: route,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: nativeTiles,
        ),
        if (webTiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Web Admin (opens browser)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: webTiles,
          ),
        ],
        if (nativeTiles.isEmpty && webTiles.isEmpty) ...[
          const SizedBox(height: 12),
          _opsFeatureUnavailableView(
            context,
            feature: 'ops_console',
            icon: Icons.layers_outlined,
          ),
        ],
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.opsTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      ),
    );
  }
}

class AdminDashboardPage extends StatefulWidget {
  final String baseUrl;
  const AdminDashboardPage(this.baseUrl, {super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SafeSetStateMixin<AdminDashboardPage> {
  bool _loadingPrivileges = true;
  bool _adminAllowed = false;
  bool _coachEnabled = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ShamellDashboardPolicy? _dashboardPolicy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPrivileges();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPrivileges() async {
    final policy = await shamellResolveDashboardPolicy(
      context,
      baseUrl: widget.baseUrl,
    );
    if (!mounted) return;
    setState(() {
      _dashboardPolicy = policy;
      _adminAllowed = policy.allowsAdminConsole;
      _coachEnabled = policy.capabilities.coach;
      _loadingPrivileges = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(title: Text(l.adminDashboardTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_adminAllowed) {
      return Scaffold(
        appBar: AppBar(title: Text(l.adminDashboardTitle)),
        body: _opsAccessDeniedView(
          context,
          console: 'admin',
          icon: Icons.admin_panel_settings_outlined,
        ),
      );
    }
    void showWebAdminLaunchError() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تعذّر فتح صفحة الإدارة.'
                : 'Could not open the admin page.',
          ),
        ),
      );
    }

    Future<void> openTrustedWebPath(List<String> pathSegments) async {
      if (shamellOpsTrustedWebPathRequiresSensitiveReveal(pathSegments)) {
        final approved = await _opsRequireSensitiveReveal(context);
        if (!approved) {
          return;
        }
      }
      final uri = shamellTrustedWebChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: pathSegments,
      );
      if (uri == null) {
        showWebAdminLaunchError();
        return;
      }
      await launchWithSession(uri);
    }

    final sections = _controlDashboardFilterSections(
      <_ControlDashboardSection>[
        _ControlDashboardSection(
          title: 'Live queues',
          description:
              'Start with the boards that handle active trips, operator handoffs, and same-day intervention.',
          actions: <_ControlDashboardAction>[
            _ControlDashboardAction(
              title: l.opsTitle,
              description:
                  'Open the live operator desk for escalations and active work.',
              icon: Icons.layers_outlined,
              accent: const Color(0xFF334155),
              searchTerms: const <String>[
                'ops',
                'live ops',
                'dispatch',
                'operator desk'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  shamellDashboardPolicyRoute<void>(
                    context: context,
                    baseUrl: widget.baseUrl,
                    policyOverride: _dashboardPolicy,
                    child: OpsPage(widget.baseUrl),
                  ),
                );
              },
            ),
            if (_coachEnabled)
              _ControlDashboardAction(
                title: 'Coach control',
                description:
                    'Review bookings, tickets, boarding, feed health, refunds, and operator authority.',
                icon: Icons.directions_bus_outlined,
                accent: const Color(0xFF0F766E),
                searchTerms: const <String>['coach', 'admin', 'partner', 'bus'],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ShamellControlDomainDashboardPage(
                        baseUrl: widget.baseUrl,
                        pathSegments: const <String>[
                          'admin',
                          'dashboards',
                          'coach'
                        ],
                        title: 'Coach control',
                        subtitle:
                            'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority in one control board.',
                        icon: Icons.directions_bus_outlined,
                        accent: const Color(0xFF0F766E),
                      ),
                    ),
                  );
                },
              ),
            if (_coachEnabled)
              _ControlDashboardAction(
                title: 'Coach operations',
                description:
                    'Monitor departures, boarding pressure, feed freshness, and ticket handoffs in Coach control.',
                icon: Icons.directions_bus_outlined,
                accent: const Color(0xFF2563EB),
                searchTerms: const <String>[
                  'coach',
                  'ops',
                  'queue',
                  'departures'
                ],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ShamellControlDomainDashboardPage(
                        baseUrl: widget.baseUrl,
                        pathSegments: const <String>[
                          'admin',
                          'dashboards',
                          'coach'
                        ],
                        title: 'Coach control',
                        subtitle:
                            'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority in one control board.',
                        icon: Icons.directions_bus_outlined,
                        accent: const Color(0xFF0F766E),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        _ControlDashboardSection(
          title: 'Trusted web consoles',
          description:
              'Sensitive browser-only tools stay separated from live operations and require a stronger open path.',
          actions: <_ControlDashboardAction>[
            _ControlDashboardAction(
              title: 'Admin overview (web)',
              description:
                  'Open the browser-based overview for wider admin reporting and controls.',
              icon: Icons.dashboard_outlined,
              accent: const Color(0xFF7C3AED),
              searchTerms: const <String>[
                'admin',
                'overview',
                'web',
                'dashboard'
              ],
              onTap: () => openTrustedWebPath(const ['admin', 'overview']),
            ),
            _ControlDashboardAction(
              title: 'Admin exports (web)',
              description:
                  'Access exports and reporting workflows for sensitive admin tasks.',
              icon: Icons.file_download_outlined,
              accent: const Color(0xFFC2410C),
              searchTerms: const <String>['admin', 'exports', 'audit', 'web'],
              onTap: () => openTrustedWebPath(const ['admin', 'exports']),
            ),
            _ControlDashboardAction(
              title: 'Topup sellers (web)',
              description:
                  'Manage seller enrollment and related browser-only payment controls.',
              icon: Icons.manage_accounts_outlined,
              accent: Tokens.colorPayments,
              searchTerms: const <String>['topup', 'sellers', 'wallet', 'web'],
              onTap: () => openTrustedWebPath(const ['admin', 'topup-sellers']),
            ),
          ],
        ),
      ],
      _searchQuery,
    );

    final signalCards = <Widget>[
      _controlDashboardSignalCard(
        context: context,
        icon: Icons.security_outlined,
        label: 'Control access',
        value: 'Admin granted',
        detail:
            'This home stays focused on active queues and trusted browser consoles.',
        accent: const Color(0xFF0F766E),
      ),
      _controlDashboardSignalCard(
        context: context,
        icon: _coachEnabled
            ? Icons.directions_bus_outlined
            : Icons.block_outlined,
        label: 'Coach operations',
        value: _coachEnabled ? 'Enabled' : 'Offline',
        detail: _coachEnabled
            ? 'Coach admin and coach ops queue are available on this server.'
            : 'Coach queues are hidden because this backend does not expose coach capability.',
        accent:
            _coachEnabled ? const Color(0xFF2563EB) : const Color(0xFF64748B),
      ),
      _controlDashboardSignalCard(
        context: context,
        icon: Icons.open_in_browser_outlined,
        label: 'Trusted web paths',
        value: '3 boards',
        detail:
            'Overview, exports, and topup-seller tools open in the browser with session continuity.',
        accent: const Color(0xFF7C3AED),
      ),
      _ControlDashboardIntelligencePanel(
        baseUrl: widget.baseUrl,
        onOpenDashboardRoute: (route) => _openControlDashboardBackendRoute(
          context,
          baseUrl: widget.baseUrl,
          dashboardRoute: route,
        ),
      ),
    ];

    final badges = <Widget>[
      _controlDashboardBadge(
        context,
        icon: Icons.monitor_heart_outlined,
        label: 'Operations-first',
      ),
      _controlDashboardBadge(
        context,
        icon: Icons.warning_amber_rounded,
        label: 'Exceptions before reports',
        color: const Color(0xFFC2410C),
      ),
      if (_coachEnabled)
        _controlDashboardBadge(
          context,
          icon: Icons.directions_bus_outlined,
          label: 'Coach live',
          color: const Color(0xFF2563EB),
        ),
    ];

    return AppScaffold(
      appBar: AppBar(title: Text(l.adminDashboardTitle)),
      body: _controlDashboardBody(
        context: context,
        eyebrow: 'SyrChat Control',
        title: 'Admin command desk',
        subtitle:
            'Run the live operating desk first, then step into browser-only admin tools for reporting and sensitive controls.',
        searchController: _searchController,
        onSearchChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        badges: badges,
        signalCards: signalCards,
        sections: sections,
        emptyMessage:
            'No boards match the current search. Try operator, coach, exports, or sellers.',
      ),
    );
  }
}

class SuperadminDashboardPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final http.Client? client;
  const SuperadminDashboardPage(
    this.baseUrl, {
    super.key,
    this.client,
    this.walletId = '',
  });

  @override
  State<SuperadminDashboardPage> createState() =>
      _SuperadminDashboardPageState();
}

class _SuperadminDashboardPageState extends State<SuperadminDashboardPage>
    with SafeSetStateMixin<SuperadminDashboardPage> {
  String _financeRange = '24h'; // 24h, 7d, 30d
  bool _reauthTriggered = false;
  Future<bool>? _reauthFuture;
  bool _loadingPrivileges = true;
  bool _superadminAllowed = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ShamellDashboardPolicy? _dashboardPolicy;

  String get baseUrl => widget.baseUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPrivileges();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPrivileges() async {
    final policy = await shamellResolveDashboardPolicy(
      context,
      baseUrl: baseUrl,
    );
    if (!mounted) return;
    setState(() {
      _dashboardPolicy = policy;
      _superadminAllowed = policy.allowsSuperadminDashboard;
      _loadingPrivileges = false;
    });
  }

  Future<bool> _forceReauthOnCriticalDashboardHttpFailure({
    required int statusCode,
    String? rawBody,
  }) async {
    if (_reauthTriggered) return true;
    if (_reauthFuture != null) {
      return await _reauthFuture!;
    }
    final future = shamellForceReauthIfCriticalAccountSessionHttpFailure(
      context,
      statusCode: statusCode,
      rawBody: rawBody,
      loginPageBuilder: (_) => const LoginPage(),
    );
    _reauthFuture = future;
    final forced = await future;
    if (forced) {
      _reauthTriggered = true;
      return true;
    }
    if (identical(_reauthFuture, future)) {
      _reauthFuture = null;
    }
    return false;
  }

  Future<bool> _forceReauthOnCriticalDashboardError(Object error) async {
    if (_reauthTriggered) return true;
    if (_reauthFuture != null) {
      return await _reauthFuture!;
    }
    final future = shamellForceReauthIfCriticalDeviceBindingDrift(
      context,
      error: error,
      loginPageBuilder: (_) => const LoginPage(),
    );
    _reauthFuture = future;
    final forced = await future;
    if (forced) {
      _reauthTriggered = true;
      return true;
    }
    if (identical(_reauthFuture, future)) {
      _reauthFuture = null;
    }
    return false;
  }

  Future<Map<String, dynamic>> _fetchStats() async {
    if (!_superadminAllowed || !_opsSuperadminGlobalStatsEnabled) {
      return const {};
    }
    final uri = _opsApiChildUri(
      baseUrl: baseUrl,
      pathSegments: const <String>['admin', 'stats'],
    );
    if (uri == null) {
      return const {};
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final r = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_opsRequestTimeout);
      if (await _forceReauthOnCriticalDashboardHttpFailure(
        statusCode: r.statusCode,
        rawBody: r.body,
      )) {
        return const {};
      }
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return j;
      }
    } catch (e) {
      if (await _forceReauthOnCriticalDashboardError(e)) {
        return const {};
      }
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
    return const {};
  }

  Future<Map<String, dynamic>> _fetchFinanceStats() async {
    if (!_superadminAllowed || !_opsSuperadminGlobalStatsEnabled) {
      return const {};
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      // Compute time range on client side.
      DateTime now = DateTime.now().toUtc();
      Duration d;
      switch (_financeRange) {
        case '7d':
          d = const Duration(days: 7);
          break;
        case '30d':
          d = const Duration(days: 30);
          break;
        case '24h':
        default:
          d = const Duration(days: 1);
      }
      final start = now.subtract(d);
      String iso(DateTime dt) =>
          dt.toIso8601String().replaceFirst(RegExp(r'\\+00:00\$'), 'Z');
      final params = {
        'from_iso': iso(start),
        'to_iso': iso(now),
      };
      final uri = _opsApiChildUri(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'finance_stats'],
        queryParameters: params,
      );
      if (uri == null) {
        return const {};
      }
      final r = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_opsRequestTimeout);
      if (await _forceReauthOnCriticalDashboardHttpFailure(
        statusCode: r.statusCode,
        rawBody: r.body,
      )) {
        return const {};
      }
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return j;
      }
    } catch (e) {
      if (await _forceReauthOnCriticalDashboardError(e)) {
        return const {};
      }
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(title: Text(l.superadminDashboardTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_superadminAllowed) {
      return Scaffold(
        appBar: AppBar(title: Text(l.superadminDashboardTitle)),
        body: _opsAccessDeniedView(
          context,
          console: 'superadmin',
          icon: Icons.security,
        ),
      );
    }
    Future<void> openPaymentsControl() async {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShamellControlDomainDashboardPage(
            baseUrl: baseUrl,
            pathSegments: const <String>['admin', 'dashboards', 'payments'],
            title: 'Payments control',
            subtitle:
                'Wallet authority, send safety, attestation hygiene, active challenges, and trusted payment telemetry.',
            icon: Icons.account_balance_wallet_outlined,
            accent: Tokens.colorPayments,
          ),
        ),
      );
    }

    final sections = _controlDashboardFilterSections(
      <_ControlDashboardSection>[
        _ControlDashboardSection(
          title: 'Immediate work',
          description:
              'Start with the boards that control the platform in real time: operations, access, and frontline escalation.',
          actions: <_ControlDashboardAction>[
            _ControlDashboardAction(
              title: l.isArabic
                  ? 'صلاحيات SyrChat Control'
                  : 'SyrChat Control access',
              description:
                  'Grant, revoke, and inspect scoped access assignments across staff and partner users.',
              icon: Icons.manage_accounts_outlined,
              accent: const Color(0xFF0F766E),
              searchTerms: const <String>[
                'access',
                'roles',
                'assignments',
                'shamell control'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SuperadminControlAccessPage(baseUrl: baseUrl),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: l.isArabic ? 'نشاط المستخدمين' : 'User activity',
              description:
                  'See username/password signups and the app actions each account performs.',
              icon: Icons.manage_search_outlined,
              accent: const Color(0xFF2563EB),
              searchTerms: const <String>[
                'activity',
                'audit',
                'signup',
                'actions',
                'users'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SuperadminUserActivityPage(
                      baseUrl: baseUrl,
                      httpClient: widget.client,
                    ),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: l.isArabic ? 'بلاغات المحادثات' : 'Chat moderation',
              description:
                  'Review reported chat messages and move moderation cases through the queue.',
              icon: Icons.report_gmailerrorred_outlined,
              accent: const Color(0xFF7C3AED),
              searchTerms: const <String>[
                'chat',
                'moderation',
                'reports',
                'messages',
                'abuse'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SuperadminChatModerationPage(
                      baseUrl: baseUrl,
                      httpClient: widget.client,
                    ),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: l.adminDashboardTitle,
              description:
                  'Open the admin command desk for trusted browser consoles and coach coordination.',
              icon: Icons.admin_panel_settings_outlined,
              accent: const Color(0xFFDC2626),
              searchTerms: const <String>[
                'admin',
                'dashboard',
                'overview',
                'control'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  shamellDashboardPolicyRoute<void>(
                    context: context,
                    baseUrl: baseUrl,
                    policyOverride: _dashboardPolicy,
                    child: AdminDashboardPage(baseUrl),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: l.opsTitle,
              description:
                  'Jump into the live operator desk for active interventions and queue handling.',
              icon: Icons.layers_outlined,
              accent: const Color(0xFF334155),
              searchTerms: const <String>['ops', 'live', 'dispatch', 'queue'],
              onTap: () {
                Navigator.push(
                  context,
                  shamellDashboardPolicyRoute<void>(
                    context: context,
                    baseUrl: baseUrl,
                    policyOverride: _dashboardPolicy,
                    child: OpsPage(baseUrl),
                  ),
                );
              },
            ),
          ],
        ),
        _ControlDashboardSection(
          title: 'Exception desks',
          description:
              'Treat payments, risk, support, and disruptions as operating queues instead of buried reports.',
          actions: <_ControlDashboardAction>[
            _ControlDashboardAction(
              title: 'Payment',
              description:
                  'Review wallet, cash-agent, finance, and guardrail surfaces from the payments command board.',
              icon: Icons.account_balance_wallet_outlined,
              accent: Tokens.colorPayments,
              searchTerms: const <String>[
                'payment',
                'wallet',
                'cash',
                'finance'
              ],
              onTap: openPaymentsControl,
            ),
            _ControlDashboardAction(
              title: 'Coach finance journal',
              description:
                  'Inspect coach-side money movements, payouts, refunds, and journal anomalies.',
              icon: Icons.receipt_long_outlined,
              accent: const Color(0xFF0EA5E9),
              searchTerms: const <String>[
                'coach',
                'finance',
                'journal',
                'refund'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CoachAdminFinanceJournalPage(baseUrl: baseUrl),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: 'Coach support cases',
              description:
                  'Work refund, change, and passenger cases that need operator or finance follow-up.',
              icon: Icons.support_agent_outlined,
              accent: const Color(0xFF7C3AED),
              searchTerms: const <String>[
                'coach',
                'support',
                'cases',
                'refund'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CoachAdminSupportCasesPage(baseUrl: baseUrl),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: 'Coach risk dashboard',
              description:
                  'Track overdue risk items, suspicious flows, and operational severity across coach workflows.',
              icon: Icons.shield_outlined,
              accent: const Color(0xFFC2410C),
              searchTerms: const <String>['coach', 'risk', 'sla', 'fraud'],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CoachAdminRiskDashboardPage(baseUrl: baseUrl),
                  ),
                );
              },
            ),
          ],
        ),
        _ControlDashboardSection(
          title: 'Domain boards',
          description:
              'Move from platform control into the specialist boards that operators and domain teams use every day.',
          actions: <_ControlDashboardAction>[
            _ControlDashboardAction(
              title: 'Coach control',
              description:
                  'Run bookings, tickets, boarding scans, feed health, refunds, and operator authority.',
              icon: Icons.directions_bus_outlined,
              accent: const Color(0xFF0F766E),
              searchTerms: const <String>[
                'coach',
                'admin',
                'partner',
                'routes'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShamellControlDomainDashboardPage(
                      baseUrl: baseUrl,
                      pathSegments: const <String>[
                        'admin',
                        'dashboards',
                        'coach'
                      ],
                      title: 'Coach control',
                      subtitle:
                          'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority in one control board.',
                      icon: Icons.directions_bus_outlined,
                      accent: const Color(0xFF0F766E),
                    ),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: 'Coach operations',
              description:
                  'Monitor departures, boarding pressure, feed freshness, and ticket handoffs in Coach control.',
              icon: Icons.directions_bus_outlined,
              accent: const Color(0xFF2563EB),
              searchTerms: const <String>[
                'coach',
                'ops',
                'departures',
                'boarding'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShamellControlDomainDashboardPage(
                      baseUrl: baseUrl,
                      pathSegments: const <String>[
                        'admin',
                        'dashboards',
                        'coach'
                      ],
                      title: 'Coach control',
                      subtitle:
                          'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority in one control board.',
                      icon: Icons.directions_bus_outlined,
                      accent: const Color(0xFF0F766E),
                    ),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: 'Partner onboarding',
              description:
                  'Review operator onboarding quality, release readiness, and partner status.',
              icon: Icons.group_add_outlined,
              accent: const Color(0xFF16A34A),
              searchTerms: const <String>[
                'partner',
                'onboarding',
                'coach',
                'operator'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CoachAdminPartnerOnboardingPage(baseUrl: baseUrl),
                  ),
                );
              },
            ),
            _ControlDashboardAction(
              title: 'Disruptions',
              description:
                  'Handle delayed, cancelled, and disrupted coach journeys with a dedicated queue.',
              icon: Icons.report_problem_outlined,
              accent: const Color(0xFFB91C1C),
              searchTerms: const <String>[
                'disruptions',
                'coach',
                'delays',
                'cancellations'
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CoachAdminDisruptionsPage(baseUrl: baseUrl),
                  ),
                );
              },
            ),
          ],
        ),
      ],
      _searchQuery,
    );

    final signalCards = <Widget>[
      _controlDashboardSignalCard(
        context: context,
        icon: Icons.public_outlined,
        label: 'Control scope',
        value: 'Platform-wide',
        detail:
            'This account can cross product boundaries and operate from one command home.',
        accent: const Color(0xFF0F766E),
      ),
      _controlDashboardSignalCard(
        context: context,
        icon: Icons.layers_outlined,
        label: 'Domain boards',
        value: 'Admin + Ops',
        detail:
            'Payments, coach, access, and live operations are available from this surface.',
        accent: const Color(0xFF334155),
      ),
      _controlDashboardSignalCard(
        context: context,
        icon: Icons.search_rounded,
        label: 'Global command search',
        value: 'Boards first',
        detail:
            'Use the search box to jump by queue, domain, payout, access, or operator task.',
        accent: const Color(0xFF7C3AED),
      ),
      _ControlDashboardIntelligencePanel(
        baseUrl: baseUrl,
        onOpenDashboardRoute: (route) => _openControlDashboardBackendRoute(
          context,
          baseUrl: baseUrl,
          dashboardRoute: route,
        ),
      ),
    ];

    final badges = <Widget>[
      _controlDashboardBadge(
        context,
        icon: Icons.flash_on_outlined,
        label: 'Exceptions first',
        color: const Color(0xFFC2410C),
      ),
      _controlDashboardBadge(
        context,
        icon: Icons.manage_accounts_outlined,
        label: 'Scope-aware access',
        color: const Color(0xFF0F766E),
      ),
      _controlDashboardBadge(
        context,
        icon: Icons.account_balance_wallet_outlined,
        label: 'Finance + risk',
        color: Tokens.colorPayments,
      ),
    ];

    final statsPanel = <Widget>[
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .88),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFD6E7DF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Right now',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Keep the home focused on queues and exceptions. Metrics here exist to support action, not replace it.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5A6F66),
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('24h'),
                  selected: _financeRange == '24h',
                  onSelected: (_) {
                    setState(() => _financeRange = '24h');
                  },
                ),
                ChoiceChip(
                  label: const Text('7d'),
                  selected: _financeRange == '7d',
                  onSelected: (_) {
                    setState(() => _financeRange = '7d');
                  },
                ),
                ChoiceChip(
                  label: const Text('30d'),
                  selected: _financeRange == '30d',
                  onSelected: (_) {
                    setState(() => _financeRange = '30d');
                  },
                ),
              ],
            ),
            if (!_opsSuperadminGlobalStatsEnabled) ...[
              const SizedBox(height: 12),
              GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _opsFeatureUnavailableMessage(
                    context,
                    feature: 'superadmin_stats',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .80),
                      ),
                ),
              ),
            ],
            if (_opsSuperadminGlobalStatsEnabled) ...[
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: _fetchFinanceStats(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  final data = snap.data ?? const {};
                  if (data.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final totalTxns = data['total_txns'] ?? 0;
                  final totalFeeCents = data['total_fee_cents'] ?? 0;
                  final fromIso = (data['from_iso'] ?? '') as String;
                  final toIso = (data['to_iso'] ?? '') as String;
                  final feeStr = totalFeeCents is int
                      ? '${(totalFeeCents / 100.0).toStringAsFixed(2)} SYP'
                      : totalFeeCents.toString();

                  return _controlDashboardSignalCard(
                    context: context,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Finance overview',
                    value: 'Txns: $totalTxns',
                    detail:
                        'Fees: $feeStr${fromIso.isNotEmpty || toIso.isNotEmpty ? ' · Range: ${fromIso.isNotEmpty ? fromIso : '?'} → ${toIso.isNotEmpty ? toIso : '?'}' : ''}',
                    accent: Tokens.colorPayments,
                  );
                },
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: _fetchStats(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  final data = snap.data ?? const {};
                  final actions = (data['actions'] as Map?) ?? const {};
                  final guardrails = (data['guardrails'] as Map?) ?? const {};
                  final totalEvents = data['total_events'] ?? 0;

                  int _intFor(String key) {
                    final v = actions[key];
                    if (v is int) return v;
                    if (v is num) return v.toInt();
                    if (v is String) {
                      return int.tryParse(v) ?? 0;
                    }
                    return 0;
                  }

                  final payOk = _intFor('pay_send_ok');
                  final payFail = _intFor('pay_send_fail');
                  final guardrailHits = guardrails.values.fold<int>(
                    0,
                    (sum, value) => sum + (value as int? ?? 0),
                  );

                  if (totalEvents == 0 &&
                      payOk == 0 &&
                      payFail == 0 &&
                      guardrailHits == 0) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _controlDashboardSignalCard(
                        context: context,
                        icon: Icons.monitor_heart_outlined,
                        label: 'System overview',
                        value: 'Events: $totalEvents',
                        detail:
                            'Payments ok: $payOk · fail: $payFail · guardrails: $guardrailHits',
                        accent: const Color(0xFF334155),
                      ),
                      if (guardrailHits > 0) ...[
                        const SizedBox(height: 12),
                        StatusBanner.info(
                          'Guardrail hits: $guardrailHits',
                          dense: true,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    ];

    return AppScaffold(
      appBar: AppBar(title: Text(l.superadminDashboardTitle)),
      body: _controlDashboardBody(
        context: context,
        eyebrow: 'SyrChat Control',
        title: 'Platform command center',
        subtitle:
            'Operate the platform from queues and scoped boards, then drop into specialist domains for payments, coach operations, access, and risk.',
        searchController: _searchController,
        onSearchChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        badges: badges,
        signalCards: [
          ...signalCards,
          ...statsPanel,
        ],
        sections: sections,
        emptyMessage:
            'No boards match the current search. Try access, payments, coach, support, or disruptions.',
      ),
    );
  }
}

class _TopupKioskPageState extends State<TopupKioskPage>
    with SafeSetStateMixin<TopupKioskPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loadingPrivileges = true;
  bool _paymentsOpsAllowed = false;
  int _denom = 10000; // SYP major
  final _countCtrl = TextEditingController(text: '10');
  final _noteCtrl = TextEditingController();
  String out = '';
  String _batchId = '';
  List<dynamic> _items = [];
  List<dynamic> _batches = [];
  bool _mineOnly = true;

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
    _init();
  }

  Future<void> _init() async {
    final snapshot = await loadAccountPrivilegeSnapshotForBaseUrl(
      widget.baseUrl,
    );
    if (!mounted) return;
    setState(() {
      _paymentsOpsAllowed =
          shamellDashboardAllowsPaymentsOperatorSurfaceSnapshot(snapshot);
      _loadingPrivileges = false;
    });
    if (_paymentsOpsAllowed && _opsTopupKioskEnabled) {
      await _loadBatches();
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
    _countCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _createBatch() async {
    if (!_opsTopupKioskEnabled) {
      setState(() {
        out = _opsFeatureUnavailableMessage(context, feature: 'topup_kiosk');
      });
      return;
    }
    setState(() => out = '...');
    try {
      final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
      if (count <= 0) {
        setState(() => out = 'Count must be > 0');
        return;
      }
      final uri = _opsApiChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: const <String>['topup', 'batch_create'],
      );
      if (uri == null) {
        setState(() => out = _opsInvalidServerUrlMessage(context));
        return;
      }
      final r = await _http
          .post(uri,
              headers: await _hdr(json: true),
              body: jsonEncode({
                'amount': _denom,
                'count': count,
                'note':
                    _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim()
              }))
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      final j = jsonDecode(r.body);
      if (r.statusCode == 200) {
        _batchId = (j['batch_id'] ?? '').toString();
        _items = (j['items'] as List?) ?? [];
        setState(() => out = 'Created batch $_batchId');
      } else {
        setState(() {
          out = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        out = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    }
  }

  Future<void> _loadBatches() async {
    if (!_opsTopupKioskEnabled) {
      if (!mounted) return;
      setState(() {
        out = _opsFeatureUnavailableMessage(context, feature: 'topup_kiosk');
      });
      return;
    }
    try {
      final uri = _opsApiChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: const <String>['topup', 'batches'],
        queryParameters: <String, String>{
          'limit': '50',
          if (!_mineOnly) 'seller_id': '',
        },
      );
      if (uri == null) {
        if (!mounted) return;
        setState(() => out = _opsInvalidServerUrlMessage(context));
        return;
      }
      final r = await _http
          .get(uri, headers: await _hdr())
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return;
      }
      _batches = jsonDecode(r.body) as List? ?? [];
      if (mounted) setState(() {});
    } catch (e) {
      await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      );
    }
  }

  Future<void> _openBatch(String bid) async {
    if (!_opsTopupKioskEnabled) {
      setState(() {
        out = _opsFeatureUnavailableMessage(context, feature: 'topup_kiosk');
      });
      return;
    }
    setState(() => out = '...');
    try {
      final uri = _opsApiChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: <String>['topup', 'batches', bid],
      );
      if (uri == null) {
        setState(() => out = _opsInvalidServerUrlMessage(context));
        return;
      }
      final r = await _http
          .get(uri, headers: await _hdr())
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        setState(() {
          out = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
        return;
      }
      _batchId = bid;
      _items = jsonDecode(r.body) as List? ?? [];
      setState(() => out = 'Loaded $bid');
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        out = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(title: Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_paymentsOpsAllowed) {
      return Scaffold(
        appBar: AppBar(title: Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk')),
        body: _opsAccessDeniedView(
          context,
          console: 'payments',
          icon: Icons.local_printshop_outlined,
        ),
      );
    }
    if (!_opsTopupKioskEnabled) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk'),
          elevation: 0,
        ),
        body: _opsFeatureUnavailableView(
          context,
          feature: 'topup_kiosk',
          icon: Icons.local_printshop_outlined,
        ),
      );
    }
    final chips = [5000, 10000, 20000, 50000];
    final grid = _items.isEmpty
        ? const SizedBox()
        : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: .9,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final v = _items[i] as Map;
              final payload = (v['payload'] ?? '').toString();
              final code = (v['code'] ?? '').toString();
              final amt = (v['amount_cents'] ?? 0) as int;
              final status = (v['status'] ?? '').toString();
              return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Expanded(
                            child: Center(
                                child: Container(
                                    width: 180,
                                    height: 180,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: payload.isEmpty
                                        ? const Icon(Icons.qr_code_2,
                                            size: 64, color: Colors.black54)
                                        : QrImageView(
                                            data: payload,
                                            version: QrVersions.auto,
                                            backgroundColor: Colors.white,
                                            eyeStyle: const QrEyeStyle(
                                              eyeShape: QrEyeShape.square,
                                              color: Colors.black,
                                            ),
                                            dataModuleStyle:
                                                const QrDataModuleStyle(
                                              dataModuleShape:
                                                  QrDataModuleShape.square,
                                              color: Colors.black,
                                            ),
                                          )))),
                        const SizedBox(height: 6),
                        Text(code, style: const TextStyle(fontSize: 12)),
                        Text(
                            '$amt SYP · ${status.isEmpty ? 'reserved' : status}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 6),
                        if (status == 'reserved')
                          SizedBox(
                              width: double.infinity,
                              child: PayActionButton(
                                  icon: Icons.remove_circle_outline,
                                  label: 'Void',
                                  onTap: () => _voidVoucher(code)))
                      ])));
            },
          );
    final batchesList = _batches.isEmpty
        ? const SizedBox()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            const Text('Recent Batches'),
            const SizedBox(height: 8),
            ..._batches.map((b) {
              final bid = (b['batch_id'] ?? '').toString();
              final total = (b['total'] ?? 0) as int;
              final reserved = (b['reserved'] ?? 0) as int;
              final redeemed = (b['redeemed'] ?? 0) as int;
              return ListTile(
                  title: Text(bid, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      'total $total  reserved $reserved  redeemed $redeemed'),
                  trailing: IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => _openBatch(bid)));
            }).toList()
          ]);

    void showPrintLaunchError() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تعذّر فتح صفحة الطباعة.'
                : 'Could not open the print page.',
          ),
        ),
      );
    }

    Future<void> openTrustedPrintPath(List<String> pathSegments) async {
      final uri = shamellTrustedWebChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: pathSegments,
      );
      if (uri == null) {
        showPrintLaunchError();
        return;
      }
      await launchWithSession(uri);
    }

    final content = ListView(padding: const EdgeInsets.all(16), children: [
      Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk'),
      const SizedBox(height: 8),
      Wrap(
          spacing: 8,
          children: chips.map((v) {
            final sel = _denom == v;
            return ChoiceChip(
                label: Text('$v'),
                selected: sel,
                onSelected: (_) {
                  setState(() => _denom = v);
                });
          }).toList()),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.isArabic ? 'دفعاتي فقط' : 'My batches only'),
                value: _mineOnly,
                onChanged: (v) {
                  setState(() => _mineOnly = v);
                  _loadBatches();
                })),
        const SizedBox(width: 8),
        Expanded(child: Container())
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
            child: TextField(
                controller: _countCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'عدد القسائم' : 'Count'),
                keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                    labelText:
                        l.isArabic ? 'ملاحظة (اختياري)' : 'Note (optional)'))),
      ]),
      const SizedBox(height: 12),
      PayActionButton(
          icon: Icons.grid_view,
          label: l.isArabic ? 'إنشاء دفعة' : 'Create Batch',
          onTap: _createBatch),
      if (_batchId.isNotEmpty)
        Row(children: [
          Expanded(
              child: PayActionButton(
                  icon: Icons.print_outlined,
                  label: l.isArabic ? 'طباعة الدفعة' : 'Print Batch',
                  onTap: () {
                    openTrustedPrintPath(['topup', 'print', _batchId]);
                  })),
          const SizedBox(width: 8),
          Expanded(
              child: PayActionButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  onTap: () {
                    openTrustedPrintPath(['topup', 'print_pdf', _batchId]);
                  })),
        ]),
      if (_batchId.isNotEmpty) const SizedBox(height: 8),
      if (_batchId.isNotEmpty)
        PayActionButton(
            icon: Icons.refresh,
            label: l.isArabic ? 'إعادة تحميل الدفعة' : 'Reload Batch',
            onTap: () => _openBatch(_batchId)),
      const SizedBox(height: 8),
      grid,
      SelectableText(out),
      batchesList,
    ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      ),
    );
  }

  Future<void> _voidVoucher(String code) async {
    if (!_opsTopupKioskEnabled) {
      setState(() {
        out = _opsFeatureUnavailableMessage(context, feature: 'topup_kiosk');
      });
      return;
    }
    setState(() => out = '...');
    try {
      final uri = _opsApiChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: <String>['topup', 'vouchers', code, 'void'],
      );
      if (uri == null) {
        setState(() => out = _opsInvalidServerUrlMessage(context));
        return;
      }
      final r = await _http
          .post(uri, headers: await _hdr())
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode == 200) {
        setState(() => out = 'Voided $code');
        if (_batchId.isNotEmpty) await _openBatch(_batchId);
      } else {
        setState(() {
          out = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        out = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    }
  }
}

class SystemStatusPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? client;
  const SystemStatusPage(this.baseUrl, {super.key, this.client});
  @override
  State<SystemStatusPage> createState() => _SystemStatusPageState();
}

class _SystemStatusPageState extends State<SystemStatusPage>
    with SafeSetStateMixin<SystemStatusPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  Map<String, dynamic>? _data;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
    if (_opsSystemStatusEnabled) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!_opsSystemStatusEnabled) {
      if (mounted) {
        setState(() {
          _error = _opsFeatureUnavailableMessage(
            context,
            feature: 'system_status',
          );
          _loading = false;
        });
      } else {
        _error = _opsFeatureUnavailableMessage(
          context,
          feature: 'system_status',
        );
        _loading = false;
      }
      return;
    }
    setState(() => _loading = true);
    _error = '';
    try {
      final uri = _opsApiChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: const <String>['upstreams', 'health'],
      );
      if (uri == null) {
        setState(() {
          _error = _opsInvalidServerUrlMessage(context);
          _loading = false;
        });
        return;
      }
      final r = await _http
          .get(uri, headers: await _hdr())
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode == 200) {
        Perf.action('system_status_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _data = j);
      } else {
        Perf.action('system_status_fail');
        setState(() {
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      Perf.action('system_status_error');
      setState(() {
        _error = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Color _statusColor(Map<String, dynamic> v) {
    final sc = v['status_code'];
    final err = v['error'];
    if (err != null) {
      return Colors.red;
    }
    if (sc is int) {
      if (sc >= 200 && sc < 300) return Tokens.colorPayments;
      if (sc >= 500) return Colors.red;
      return Colors.orange;
    }
    return Colors.grey;
  }

  String _statusLabel(Map<String, dynamic> v) {
    final sc = v['status_code'];
    final err = v['error'];
    if (err != null) {
      return 'ERROR';
    }
    if (sc is int) {
      if (sc >= 200 && sc < 300) return 'OK';
      if (sc >= 500) return 'DOWN';
      return 'WARN';
    }
    return 'UNKNOWN';
  }

  @override
  Widget build(BuildContext context) {
    if (!_opsSystemStatusEnabled) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).systemStatusTitle),
        ),
        body: _opsFeatureUnavailableView(
          context,
          feature: 'system_status',
          icon: Icons.health_and_safety_outlined,
        ),
      );
    }
    Widget body;
    final l = L10n.of(context);
    if (_loading && _data == null && _error.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatusBanner.error(_error),
        ],
      );
    } else {
      final entries = (_data ?? const {}).entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length + (_error.isNotEmpty ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0 && _error.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StatusBanner.error(_error, dense: true),
              );
            }
            final adjIndex = _error.isNotEmpty ? index - 1 : index;
            final e = entries[adjIndex];
            final name = e.key;
            final v = (e.value as Map).cast<String, dynamic>();
            final col = _statusColor(v);
            final status = _statusLabel(v);
            final sc = v['status_code'];
            final err = v['error'];
            final detail = err is String
                ? err
                : (v['body'] is Map && (v['body'] as Map).containsKey('status')
                    ? (v['body']['status'] ?? '').toString()
                    : '');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  status == 'OK'
                      ? Icons.check_circle_outline
                      : status == 'DOWN'
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                  color: col,
                ),
                title: Text(name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.systemStatusStatusLabel}: $status'
                        '${sc != null ? ' · ${l.systemStatusHttpLabel} $sc' : ''}'),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.systemStatusTitle),
      ),
      body: body,
    );
  }
}

class GlassCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const GlassCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bg = theme.cardColor;
    final Color fg = theme.colorScheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 42, color: fg),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  const SettingsPage(
      {super.key, required this.baseUrl, required this.walletId});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SafeSetStateMixin<SettingsPage> {
  late final TextEditingController baseUrlCtrl;
  late final TextEditingController walletCtrl;
  bool _metricsRemote = false;

  @override
  void initState() {
    super.initState();
    baseUrlCtrl = TextEditingController(text: widget.baseUrl);
    walletCtrl = TextEditingController(text: widget.walletId);
    // Removed manual Google Maps API key and currency selection (SYP default)
    _scrubDeadDebugPrefs();
    _loadMetrics();
  }

  Future<void> _scrubDeadDebugPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('debug_skeleton_long');
      await sp.remove('skip_login');
    } catch (_) {}
  }

  Future<void> _loadMetrics() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _metricsRemote = await Perf.loadRemotePreference(
        sp: sp,
        baseUrlOverride: widget.baseUrl,
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    baseUrlCtrl.clear();
    walletCtrl.clear();
    baseUrlCtrl.dispose();
    walletCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = ListView(
      padding: const EdgeInsets.all(0),
      children: [
        TextField(
          controller: baseUrlCtrl,
          decoration: InputDecoration(labelText: l.settingsBaseUrl),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: walletCtrl,
          decoration: InputDecoration(labelText: l.settingsMyWallet),
        ),
        const SizedBox(height: 8),
        // Removed manual UI route selector; SyrChat-style layout is always used.
        const SizedBox(height: 8),
        SwitchListTile(
          value: _metricsRemote,
          onChanged: (v) {
            setState(() => _metricsRemote = v);
          },
          title: Text(l.settingsSendMetrics),
        ),
        const SizedBox(height: 16),
        WaterButton(label: l.settingsSave, onTap: _save),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l = L10n.of(context);
    final normalizedBaseUrl = normalizeSecureApiBaseUrl(baseUrlCtrl.text);
    if (normalizedBaseUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'يجب استخدام HTTPS (وفي وضع التطوير يُسمح بـ HTTP على localhost أو الشبكة المحلية).'
                : 'HTTPS is required (non-release builds also allow HTTP for localhost/LAN).',
          ),
        ),
      );
      return;
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', normalizedBaseUrl);
    await saveStoredWalletId(
      walletCtrl.text.trim(),
      sp: sp,
      baseUrlOverride: normalizedBaseUrl,
    );
    await sp.remove('debug_skeleton_long');
    await sp.remove('skip_login');
    await Perf.saveRemotePreference(
      _metricsRemote,
      sp: sp,
      baseUrlOverride: normalizedBaseUrl,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class SonicPayPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? client;
  const SonicPayPage(this.baseUrl, {super.key, this.client});
  @override
  State<SonicPayPage> createState() => _SonicPayPageState();
}

class _SonicPayPageState extends State<SonicPayPage>
    with SafeSetStateMixin<SonicPayPage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loadingPrivileges = true;
  bool _paymentsOpsAllowed = false;
  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final amtCtrl = TextEditingController(text: '1000');
  String payload = '';
  String out = '';
  bool _payloadVisible = false;
  bool _paymentsSonicEnabled = false;
  bool _capabilitiesLoaded = false;

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
    _init();
  }

  Future<void> _init() async {
    final snapshot = await loadAccountPrivilegeSnapshotForBaseUrl(
      widget.baseUrl,
    );
    try {
      final caps = await ShamellCapabilities.loadForBaseUrl(widget.baseUrl);
      _paymentsSonicEnabled = caps.paymentsSonic;
    } catch (_) {
      _paymentsSonicEnabled = false;
    } finally {
      _paymentsOpsAllowed =
          shamellDashboardAllowsPaymentsOperatorSurfaceSnapshot(snapshot);
      _loadingPrivileges = false;
      _capabilitiesLoaded = true;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    fromCtrl.clear();
    toCtrl.clear();
    amtCtrl.clear();
    fromCtrl.dispose();
    toCtrl.dispose();
    amtCtrl.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<void> _issue() async {
    if (!_paymentsSonicEnabled) {
      setState(
          () => out = _opsFeatureUnavailableMessage(context, feature: 'sonic'));
      return;
    }
    setState(() => out = '...');
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', 'sonic', 'issue'],
    );
    if (uri == null) {
      setState(() => out = _opsInvalidServerUrlMessage(context));
      return;
    }
    try {
      final r = await _http
          .post(uri,
              headers: await _hdr(json: true),
              body: jsonEncode({
                'from_wallet_id': fromCtrl.text.trim(),
                'amount_cents': int.tryParse(amtCtrl.text.trim()) ?? 0,
              }))
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = r.statusCode >= 200 && r.statusCode < 300
          ? (L10n.of(context).isArabic ? 'تم.' : 'OK.')
          : sanitizeHttpError(
              statusCode: r.statusCode,
              rawBody: r.body,
              isArabic: L10n.of(context).isArabic,
            );
      try {
        final j = jsonDecode(r.body);
        final tok = j['token'] ?? '';
        payload = tok is String && tok.startsWith('SONIC|')
            ? tok
            : 'SONIC|token=' + tok.toString();
        _payloadVisible = false;
      } catch (_) {}
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _togglePayloadVisibility() async {
    if (payload.trim().isEmpty) return;
    if (_payloadVisible) {
      if (mounted) {
        setState(() => _payloadVisible = false);
      }
      return;
    }
    final approved = await _opsRequireSensitiveReveal(context);
    if (!approved) return;
    if (mounted) {
      setState(() => _payloadVisible = true);
    }
  }

  Future<void> _copyPayload() async {
    final p = payload.trim();
    if (p.isEmpty) return;
    final approved =
        _payloadVisible || await _opsRequireSensitiveReveal(context);
    if (!approved) return;
    await shamellCopyToClipboard(p, sensitive: true);
    if (!mounted) return;
    final l = L10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.isArabic ? 'تم النسخ.' : 'Copied.'),
      ),
    );
  }

  Future<void> _redeem() async {
    if (!_paymentsSonicEnabled) {
      setState(
          () => out = _opsFeatureUnavailableMessage(context, feature: 'sonic'));
      return;
    }
    setState(() => out = '...');
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', 'sonic', 'redeem'],
    );
    if (uri == null) {
      setState(() => out = _opsInvalidServerUrlMessage(context));
      return;
    }
    try {
      // payload format: SONIC|token=... or any text, server expects token
      final map = <String, String>{};
      try {
        for (final p in payload.split('|').skip(1)) {
          final kv = p.split('=');
          if (kv.length == 2) map[kv[0]] = kv[1];
        }
      } catch (_) {}
      final token = map['token'] ?? payload;
      final r = await _http
          .post(uri,
              headers: await _hdr(json: true),
              body: jsonEncode({
                'token': token,
                'to_wallet_id':
                    toCtrl.text.trim().isEmpty ? null : toCtrl.text.trim(),
              }))
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = r.statusCode >= 200 && r.statusCode < 300
          ? (L10n.of(context).isArabic ? 'تم.' : 'OK.')
          : sanitizeHttpError(
              statusCode: r.statusCode,
              rawBody: r.body,
              isArabic: L10n.of(context).isArabic,
            );
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final body = _loadingPrivileges
        ? const Center(child: CircularProgressIndicator())
        : !_paymentsOpsAllowed
            ? _opsAccessDeniedView(
                context,
                console: 'payments',
                icon: Icons.bolt,
              )
            : !_capabilitiesLoaded
                ? const Center(child: CircularProgressIndicator())
                : !_paymentsSonicEnabled
                    ? _opsFeatureUnavailableView(
                        context,
                        feature: 'sonic',
                        icon: Icons.bolt,
                      )
                    : ListView(padding: const EdgeInsets.all(16), children: [
                        TextField(
                            controller: fromCtrl,
                            decoration:
                                InputDecoration(labelText: l.sonicFromWallet)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: toCtrl,
                            decoration:
                                InputDecoration(labelText: l.sonicToWalletOpt)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: amtCtrl,
                            decoration:
                                InputDecoration(labelText: l.labelAmount),
                            keyboardType: TextInputType.number),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: WaterButton(
                                  label: l.sonicIssueToken, onTap: _issue)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: WaterButton(
                                  label: l.sonicRedeem, onTap: _redeem))
                        ]),
                        const SizedBox(height: 12),
                        if (payload.isNotEmpty)
                          Center(
                              child: Column(children: [
                            SelectableText(
                              _payloadVisible
                                  ? payload
                                  : shamellOpsMaskSensitivePayloadForDisplay(
                                      payload),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _togglePayloadVisibility,
                                  icon: Icon(
                                    _payloadVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  label: Text(
                                    _payloadVisible
                                        ? (l.isArabic ? 'إخفاء' : 'Hide')
                                        : (l.isArabic ? 'إظهار' : 'Reveal'),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _copyPayload,
                                  icon: const Icon(Icons.copy_outlined),
                                  label: Text(l.isArabic ? 'نسخ' : 'Copy'),
                                ),
                              ],
                            ),
                            if (_payloadVisible) ...[
                              const SizedBox(height: 8),
                              QrImageView(data: payload, size: 220),
                            ],
                          ])),
                        const SizedBox(height: 12),
                        SelectableText(out),
                      ]);
    return Scaffold(
      appBar: AppBar(title: Text(l.sonicTitle)),
      body: body,
    );
  }
}

class CashMandatePage extends StatefulWidget {
  final String baseUrl;
  final http.Client? client;
  const CashMandatePage(this.baseUrl, {super.key, this.client});
  @override
  State<CashMandatePage> createState() => _CashMandatePageState();
}

class _CashMandatePageState extends State<CashMandatePage>
    with SafeSetStateMixin<CashMandatePage> {
  late final http.Client _http;
  late final bool _ownsHttpClient;
  bool _loadingPrivileges = true;
  bool _cashManageAllowed = false;
  bool _cashRedeemAllowed = false;
  final amtCtrl = TextEditingController(text: '1000');
  final phraseCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String out = '';
  String payload = '';
  bool _payloadVisible = false;
  bool _paymentsCashVouchersEnabled = false;
  bool _capabilitiesLoaded = false;

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.client == null;
    _http = widget.client ?? shamellHttpClient();
    _init();
  }

  Future<void> _init() async {
    final snapshot = await loadAccountPrivilegeSnapshotForBaseUrl(
      widget.baseUrl,
    );
    try {
      final caps = await ShamellCapabilities.loadForBaseUrl(widget.baseUrl);
      _paymentsCashVouchersEnabled = caps.paymentsCashVouchers;
    } catch (_) {
      _paymentsCashVouchersEnabled = false;
    } finally {
      _cashManageAllowed =
          shamellDashboardAllowsPaymentsOperatorSurfaceSnapshot(snapshot);
      _cashRedeemAllowed =
          shamellDashboardAllowsPaymentsCashRedeemSurfaceSnapshot(snapshot);
      _loadingPrivileges = false;
      _capabilitiesLoaded = true;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    amtCtrl.clear();
    phraseCtrl.clear();
    codeCtrl.clear();
    amtCtrl.dispose();
    phraseCtrl.dispose();
    codeCtrl.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!_paymentsCashVouchersEnabled) {
      setState(
          () => out = _opsFeatureUnavailableMessage(context, feature: 'cash'));
      return;
    }
    setState(() => out = '...');
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', 'cash', 'create'],
    );
    if (uri == null) {
      setState(() => out = _opsInvalidServerUrlMessage(context));
      return;
    }
    String? myWallet;
    try {
      myWallet = await loadStoredWalletId(baseUrlOverride: widget.baseUrl);
    } catch (_) {}
    final body = jsonEncode({
      'from_wallet_id': myWallet,
      'amount_cents': int.tryParse(amtCtrl.text.trim()) ?? 0,
      'phrase': phraseCtrl.text.trim().isEmpty ? null : phraseCtrl.text.trim(),
    });
    try {
      final headers = await _hdr(json: true);
      final r = await _http
          .post(uri, headers: headers, body: body)
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = r.statusCode >= 200 && r.statusCode < 300
          ? (L10n.of(context).isArabic ? 'تم.' : 'OK.')
          : sanitizeHttpError(
              statusCode: r.statusCode,
              rawBody: r.body,
              isArabic: L10n.of(context).isArabic,
            );
      if (r.statusCode >= 500) {
        out = _opsOfflineReplayUnsafeMessage(context);
      }
      try {
        final j = jsonDecode(r.body);
        final code = j['code'] ?? '';
        codeCtrl.text = code.toString();
        payload = 'CASH|code=' + codeCtrl.text;
        _payloadVisible = false;
      } catch (_) {}
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = _opsOfflineReplayUnsafeMessage(context);
    }
    if (mounted) setState(() {});
  }

  Future<void> _togglePayloadVisibility() async {
    if (payload.trim().isEmpty) return;
    if (_payloadVisible) {
      if (mounted) {
        setState(() => _payloadVisible = false);
      }
      return;
    }
    final approved = await _opsRequireSensitiveReveal(context);
    if (!approved) return;
    if (mounted) {
      setState(() => _payloadVisible = true);
    }
  }

  Future<void> _copyPayload() async {
    final p = payload.trim();
    if (p.isEmpty) return;
    final approved =
        _payloadVisible || await _opsRequireSensitiveReveal(context);
    if (!approved) return;
    await shamellCopyToClipboard(p, sensitive: true);
    if (!mounted) return;
    final l = L10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.isArabic ? 'تم النسخ.' : 'Copied.'),
      ),
    );
  }

  Future<void> _status() async {
    if (!_paymentsCashVouchersEnabled) {
      setState(
          () => out = _opsFeatureUnavailableMessage(context, feature: 'cash'));
      return;
    }
    setState(() => out = '...');
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>[
        'payments',
        'cash',
        'status',
        codeCtrl.text.trim()
      ],
    );
    if (uri == null) {
      setState(() => out = _opsInvalidServerUrlMessage(context));
      return;
    }
    try {
      final r = await _http.get(uri).timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = r.statusCode >= 200 && r.statusCode < 300
          ? (L10n.of(context).isArabic ? 'تم.' : 'OK.')
          : sanitizeHttpError(
              statusCode: r.statusCode,
              rawBody: r.body,
              isArabic: L10n.of(context).isArabic,
            );
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _cancel() async {
    if (!_paymentsCashVouchersEnabled) {
      setState(
          () => out = _opsFeatureUnavailableMessage(context, feature: 'cash'));
      return;
    }
    setState(() => out = '...');
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', 'cash', 'cancel'],
    );
    if (uri == null) {
      setState(() => out = _opsInvalidServerUrlMessage(context));
      return;
    }
    try {
      final r = await _http
          .post(uri,
              headers: await _hdr(json: true),
              body: jsonEncode({'code': codeCtrl.text.trim()}))
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = r.statusCode >= 200 && r.statusCode < 300
          ? (L10n.of(context).isArabic ? 'تم.' : 'OK.')
          : sanitizeHttpError(
              statusCode: r.statusCode,
              rawBody: r.body,
              isArabic: L10n.of(context).isArabic,
            );
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _redeem() async {
    if (!_paymentsCashVouchersEnabled) {
      setState(
          () => out = _opsFeatureUnavailableMessage(context, feature: 'cash'));
      return;
    }
    setState(() => out = '...');
    final uri = _opsApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['payments', 'cash', 'redeem'],
    );
    if (uri == null) {
      setState(() => out = _opsInvalidServerUrlMessage(context));
      return;
    }
    try {
      String? myWallet;
      try {
        myWallet = await loadStoredWalletId(baseUrlOverride: widget.baseUrl);
      } catch (_) {}
      final r = await _http
          .post(uri,
              headers: await _hdr(json: true),
              body: jsonEncode({
                'code': codeCtrl.text.trim(),
                'phrase': phraseCtrl.text.trim().isEmpty
                    ? null
                    : phraseCtrl.text.trim(),
                'to_wallet_id': myWallet,
              }))
          .timeout(_opsRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = r.statusCode >= 200 && r.statusCode < 300
          ? (L10n.of(context).isArabic ? 'تم.' : 'OK.')
          : sanitizeHttpError(
              statusCode: r.statusCode,
              rawBody: r.body,
              isArabic: L10n.of(context).isArabic,
            );
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      out = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = _loadingPrivileges
        ? const Center(child: CircularProgressIndicator())
        : !_cashRedeemAllowed
            ? _opsAccessDeniedView(
                context,
                console: 'payments',
                icon: Icons.card_giftcard_outlined,
              )
            : !_capabilitiesLoaded
                ? const Center(child: CircularProgressIndicator())
                : !_paymentsCashVouchersEnabled
                    ? _opsFeatureUnavailableView(
                        context,
                        feature: 'cash',
                        icon: Icons.card_giftcard_outlined,
                      )
                    : ListView(padding: const EdgeInsets.all(16), children: [
                        TextField(
                            controller: phraseCtrl,
                            decoration: InputDecoration(
                                labelText: l.cashSecretPhraseOpt)),
                        const SizedBox(height: 12),
                        if (_cashManageAllowed) ...[
                          TextField(
                              controller: amtCtrl,
                              decoration:
                                  InputDecoration(labelText: l.labelAmount),
                              keyboardType: TextInputType.number),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: WaterButton(
                                    label: l.cashCreate, onTap: _create)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: WaterButton(
                                    label: l.cashStatus, onTap: _status)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: WaterButton(
                                    label: l.cashCancel, onTap: _cancel))
                          ]),
                        ] else ...[
                          Text(
                            l.isArabic
                                ? 'هذه الجلسة تملك صلاحية استبدال القسائم فقط.'
                                : 'This session can redeem cash vouchers only.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(
                                        context,
                                      )
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: .72),
                                    ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                            controller: codeCtrl,
                            decoration:
                                InputDecoration(labelText: l.labelCode)),
                        const SizedBox(height: 8),
                        WaterButton(label: l.cashRedeem, onTap: _redeem),
                        const SizedBox(height: 12),
                        if (payload.isNotEmpty)
                          Center(
                              child: Column(children: [
                            SelectableText(
                              _payloadVisible
                                  ? payload
                                  : shamellOpsMaskSensitivePayloadForDisplay(
                                      payload),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _togglePayloadVisibility,
                                  icon: Icon(
                                    _payloadVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  label: Text(
                                    _payloadVisible
                                        ? (l.isArabic ? 'إخفاء' : 'Hide')
                                        : (l.isArabic ? 'إظهار' : 'Reveal'),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _copyPayload,
                                  icon: const Icon(Icons.copy_outlined),
                                  label: Text(l.isArabic ? 'نسخ' : 'Copy'),
                                ),
                              ],
                            ),
                            if (_payloadVisible) ...[
                              const SizedBox(height: 8),
                              QrImageView(data: payload, size: 220),
                            ],
                          ])),
                        const SizedBox(height: 12),
                        SelectableText(out),
                      ]);
    return Scaffold(
        appBar: AppBar(
            title: Text(l.vouchersTitleText),
            backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          const AppBG(),
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}
