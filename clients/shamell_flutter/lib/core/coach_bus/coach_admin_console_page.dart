import 'dart:async';

import 'package:flutter/material.dart';

import '../account_privilege_store.dart';
import '../dashboard_policy_scope.dart';
import '../format.dart';
import '../l10n.dart';
import '../safe_set_state.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_admin_disruptions_page.dart';
import 'coach_admin_finance_journal_page.dart';
import 'coach_admin_partner_onboarding_page.dart';
import 'coach_admin_shamell_pay_reconciliation_page.dart';
import 'coach_admin_risk_dashboard_page.dart';
import 'coach_admin_support_cases_page.dart';
import 'coach_mobility_api.dart';
import 'coach_ops_feature_widgets.dart';

String _coachAdminIsoLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
}

String _coachAdminMoneyLabel(String currency, int minorUnits) {
  return '${fmtCents(minorUnits)} $currency';
}

String _coachFeedFreshnessLabel(CoachOperatorFeedHealth feed) {
  if (feed.syncStatus != 'ok') {
    return 'Sync ${feed.syncStatus}';
  }
  return feed.freshnessStatus;
}

String _coachAdminSectionLabel(
  String section,
  bool isArabic,
) {
  switch (section) {
    case 'live_ops':
      return isArabic ? 'العمليات الحية' : 'Live ops';
    case 'support':
      return isArabic ? 'الدعم' : 'Support';
    case 'finance':
      return isArabic ? 'المالية' : 'Finance';
    case 'risk':
      return isArabic ? 'المخاطر' : 'Risk';
    case 'partners':
      return isArabic ? 'الشركاء' : 'Partners';
    default:
      return isArabic ? 'الكل' : 'All';
  }
}

int _coachAdminSectionSignalCount(
  CoachAdminOverviewResponse overview,
  String section,
) {
  final disruptionSummary = overview.disruptionSummary;
  final feedSummary = overview.feedHealth.summary;
  final onboardingSummary = overview.partnerOnboardingSummary;
  switch (section) {
    case 'live_ops':
      return overview.liveOpsSummary.needsAttentionPassengers +
          (disruptionSummary?.actionRequiredTrips ?? 0);
    case 'support':
      return overview.supportSummary.urgentRequestCount +
          overview.supportSummary.pendingReviewCount;
    case 'finance':
      return overview.financeSummary.failedPayoutRuns > 0
          ? overview.financeSummary.failedPayoutRuns
          : overview.financeSummary.queuedPayoutRuns;
    case 'risk':
      return overview.supportSummary.urgentRequestCount +
          overview.financeSummary.failedPayoutRuns +
          overview.liveOpsSummary.needsAttentionPassengers +
          feedSummary.degradedFeeds +
          feedSummary.staleFeeds;
    case 'partners':
      return (onboardingSummary?.actionRequiredOperators ?? 0) +
          feedSummary.degradedFeeds +
          feedSummary.staleFeeds;
    default:
      return 0;
  }
}

bool _coachAdminSectionVisible(String selectedSection, String section) {
  return selectedSection == 'all' || selectedSection == section;
}

class CoachAdminConsolePage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final ShamellDashboardPolicy? dashboardPolicyOverride;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;
  final CoachAdminOverviewResponse? initialOverview;

  const CoachAdminConsolePage({
    super.key,
    required this.baseUrl,
    this.api,
    this.dashboardPolicyOverride,
    this.privilegeSnapshotOverride,
    this.initialOverview,
  });

  @override
  State<CoachAdminConsolePage> createState() => _CoachAdminConsolePageState();
}

class _CoachAdminConsolePageState extends State<CoachAdminConsolePage>
    with SafeSetStateMixin<CoachAdminConsolePage> {
  static const String _pageStorageStateIdentifier =
      'coach_admin_console_ui_state';
  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);

  bool _loadingPrivileges = true;
  bool _accessAllowed = false;
  bool _loadingOverview = false;
  String _selectedSection = 'all';
  final Set<String> _collapsedSections = <String>{};
  bool _restoredStoredState = false;
  String? _errorMessage;
  CoachAdminOverviewResponse? _overview;

  @override
  void initState() {
    super.initState();
    _overview = widget.initialOverview;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPrivilegesAndOverview();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredStoredState) {
      return;
    }
    _restoredStoredState = true;
    final stored = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _pageStorageStateIdentifier);
    if (stored is! Map) {
      return;
    }
    final selectedSection = stored['selectedSection'];
    final collapsedSections = stored['collapsedSections'];
    const knownSections = <String>{
      'all',
      'live_ops',
      'support',
      'finance',
      'risk',
      'partners',
    };
    if (selectedSection is String && knownSections.contains(selectedSection)) {
      _selectedSection = selectedSection;
    }
    if (collapsedSections is List) {
      _collapsedSections
        ..clear()
        ..addAll(
          collapsedSections
              .map((entry) => entry.toString().trim())
              .where((entry) => knownSections.contains(entry))
              .where((entry) => entry != 'all'),
        );
    }
  }

  Future<void> _loadPrivilegesAndOverview() async {
    final policy = await shamellResolveDashboardPolicy(
      context,
      baseUrl: widget.baseUrl,
      policyOverride: widget.dashboardPolicyOverride,
      privilegeSnapshotOverride: widget.privilegeSnapshotOverride,
    );
    final snapshot = policy.privilegeSnapshot;
    if (!mounted) return;
    setState(() {
      _accessAllowed =
          shamellDashboardAllowsCoachAdminConsoleSnapshot(snapshot);
      _loadingPrivileges = false;
    });
    if (!_accessAllowed) {
      return;
    }
    await _loadOverview();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _loadingOverview = true;
      _errorMessage = null;
    });
    try {
      final overview = await _api.adminOverview();
      setState(() {
        _overview = overview;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _loadingOverview = false;
      });
    }
  }

  Future<void> _openSupportCasesPage() async {
    await Navigator.of(context).push(
      shamellDashboardPolicyRoute<void>(
        context: context,
        baseUrl: widget.baseUrl,
        policyOverride: widget.dashboardPolicyOverride,
        child: CoachAdminSupportCasesPage(
          baseUrl: widget.baseUrl,
          api: _api,
        ),
      ),
    );
  }

  Future<void> _openFinanceJournalPage() async {
    await Navigator.of(context).push(
      shamellDashboardPolicyRoute<void>(
        context: context,
        baseUrl: widget.baseUrl,
        policyOverride: widget.dashboardPolicyOverride,
        child: CoachAdminFinanceJournalPage(
          baseUrl: widget.baseUrl,
          api: _api,
        ),
      ),
    );
  }

  Future<void> _openShamellPayReconciliationPage() async {
    await Navigator.of(context).push(
      shamellDashboardPolicyRoute<void>(
        context: context,
        baseUrl: widget.baseUrl,
        policyOverride: widget.dashboardPolicyOverride,
        child: CoachAdminShamellPayReconciliationPage(
          baseUrl: widget.baseUrl,
          api: _api,
        ),
      ),
    );
  }

  Future<void> _openRiskDashboardPage() async {
    await Navigator.of(context).push(
      shamellDashboardPolicyRoute<void>(
        context: context,
        baseUrl: widget.baseUrl,
        policyOverride: widget.dashboardPolicyOverride,
        child: CoachAdminRiskDashboardPage(
          baseUrl: widget.baseUrl,
          api: _api,
        ),
      ),
    );
  }

  Future<void> _openPartnerOnboardingPage() async {
    await Navigator.of(context).push(
      shamellDashboardPolicyRoute<void>(
        context: context,
        baseUrl: widget.baseUrl,
        policyOverride: widget.dashboardPolicyOverride,
        child: CoachAdminPartnerOnboardingPage(
          baseUrl: widget.baseUrl,
          api: _api,
        ),
      ),
    );
  }

  Future<void> _openDisruptionsPage() async {
    await Navigator.of(context).push(
      shamellDashboardPolicyRoute<void>(
        context: context,
        baseUrl: widget.baseUrl,
        policyOverride: widget.dashboardPolicyOverride,
        child: CoachAdminDisruptionsPage(
          baseUrl: widget.baseUrl,
          api: _api,
        ),
      ),
    );
  }

  void _runIncidentPlaybook(CoachIncidentTemplate template) {
    switch (template.id) {
      case 'bus_delay':
      case 'bus_cancelled':
        unawaited(_openDisruptionsPage());
        return;
      case 'passenger_missing':
      case 'invalid_qr':
        unawaited(_openSupportCasesPage());
        return;
      case 'duplicate_boarding':
        unawaited(_openRiskDashboardPage());
        return;
      default:
        unawaited(_openSupportCasesPage());
    }
  }

  void _toggleSectionCollapsed(String section) {
    setState(() {
      if (_collapsedSections.contains(section)) {
        _collapsedSections.remove(section);
      } else {
        _collapsedSections.add(section);
      }
      _persistConsoleUiState();
    });
  }

  void _collapseVisibleSections(Iterable<String> sections) {
    setState(() {
      _collapsedSections.addAll(sections);
      _persistConsoleUiState();
    });
  }

  void _expandVisibleSections(Iterable<String> sections) {
    setState(() {
      _collapsedSections.removeAll(sections);
      _persistConsoleUiState();
    });
  }

  void _persistConsoleUiState() {
    PageStorage.maybeOf(context)?.writeState(
      context,
      <String, Object>{
        'selectedSection': _selectedSection,
        'collapsedSections': _collapsedSections.toList(growable: false),
      },
      identifier: _pageStorageStateIdentifier,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'إدارة الحافلات' : 'Coach admin'),
        actions: [
          IconButton(
            onPressed:
                !_accessAllowed || _loadingOverview ? null : _loadOverview,
            icon: const Icon(Icons.refresh),
            tooltip: isArabic ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: _buildBody(context, isArabic),
    );
  }

  Widget _buildBody(BuildContext context, bool isArabic) {
    if (_loadingPrivileges) {
      return const ShamellSkeletonList(itemCount: 5);
    }
    if (!_accessAllowed) {
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
                    const Icon(Icons.admin_panel_settings_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      isArabic
                          ? 'هذا الحساب غير مخول لعرض لوحة إدارة الحافلات.'
                          : 'This account is not allowed to access the coach admin console.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (_loadingOverview && _overview == null) {
      return const ShamellSkeletonList(itemCount: 5);
    }
    if (_overview == null) {
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
                    if (_errorMessage != null)
                      StatusBanner.error(_errorMessage!),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loadOverview,
                      icon: const Icon(Icons.refresh),
                      label: Text(isArabic ? 'أعد المحاولة' : 'Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final overview = _overview!;
    const sections = <String>[
      'live_ops',
      'support',
      'finance',
      'risk',
      'partners',
    ];
    final visibleSections = sections
        .where(
            (section) => _coachAdminSectionVisible(_selectedSection, section))
        .toList(growable: false);
    final sectionWidgets = <Widget>[];
    void addSection(String section, Widget child) {
      if (!_coachAdminSectionVisible(_selectedSection, section)) {
        return;
      }
      if (sectionWidgets.isNotEmpty) {
        sectionWidgets.add(const SizedBox(height: 16));
      }
      sectionWidgets.add(child);
    }

    addSection('live_ops', _buildLiveOpsSection(context, overview, isArabic));
    addSection('support', _buildSupportSection(context, overview, isArabic));
    addSection('finance', _buildFinanceSection(context, overview, isArabic));
    addSection('risk', _buildRiskSection(context, overview, isArabic));
    addSection('partners', _buildPartnersSection(context, overview, isArabic));
    final firstDeparture = overview.departures.departures.isEmpty
        ? null
        : overview.departures.departures.first;
    final adminOpenTasks = sections.fold<int>(
      0,
      (sum, section) => sum + _coachAdminSectionSignalCount(overview, section),
    );
    final adminHealthScore = (100 -
            (overview.liveOpsSummary.pendingBoardingPassengers * 2) -
            (overview.liveOpsSummary.needsAttentionPassengers * 6) -
            ((overview.disruptionSummary?.actionRequiredTrips ?? 0) * 8) -
            (overview.financeSummary.failedPayoutRuns * 5) -
            (overview.feedHealth.summary.degradedFeeds * 4) -
            (overview.feedHealth.summary.staleFeeds * 4))
        .clamp(0, 100)
        .toInt();
    final adminFeaturePanels = <Widget>[
      _buildSimpleHomeSection(context, overview, isArabic),
      const SizedBox(height: 16),
      CoachShiftPanel(
        roleLabel: isArabic ? 'وردية الإدارة' : 'Admin shift',
        assignedTrips: overview.liveOpsSummary.tripCount,
        openTasks: adminOpenTasks,
        crewMembers: overview.departures.departures.length,
      ),
      const SizedBox(height: 16),
      CoachIncidentFlowPanel(
        onRunPlaybook: _runIncidentPlaybook,
      ),
      const SizedBox(height: 16),
      CoachPassengerNotificationPanel(
        impactedPassengers: overview.disruptionSummary?.affectedBookingCount ??
            overview.liveOpsSummary.needsAttentionPassengers,
        contextLabel: isArabic ? 'ركاب الحافلات' : 'Coach passengers',
      ),
      const SizedBox(height: 16),
      CoachNotificationsInboxPanel(
        items: <CoachNotificationInboxItem>[
          CoachNotificationInboxItem(
            title: 'Delay update',
            audience:
                '${overview.disruptionSummary?.affectedBookingCount ?? 0} passenger(s)',
            status: (overview.disruptionSummary?.actionRequiredTrips ?? 0) > 0
                ? 'Pending'
                : 'Delivered',
            timeLabel: _coachAdminIsoLabel(overview.generatedAtIso),
            icon: Icons.schedule_outlined,
          ),
          CoachNotificationInboxItem(
            title: 'Refund decision',
            audience:
                '${overview.supportSummary.openRefundRequests} refund request(s)',
            status: overview.supportSummary.pendingReviewCount > 0
                ? 'Pending'
                : 'Opened',
            timeLabel: _coachAdminIsoLabel(overview.generatedAtIso),
            icon: Icons.payments_outlined,
          ),
          CoachNotificationInboxItem(
            title: 'Payout status',
            audience:
                '${overview.financeSummary.queuedPayoutRuns} payout run(s)',
            status: overview.financeSummary.failedPayoutRuns > 0
                ? 'Failed'
                : 'Delivered',
            timeLabel: _coachAdminIsoLabel(overview.generatedAtIso),
            icon: Icons.account_balance_wallet_outlined,
          ),
        ],
      ),
      const SizedBox(height: 16),
      CoachRecoveryFlowPanel(
        routeLabel: firstDeparture == null
            ? 'All active coach routes'
            : '${firstDeparture.from} -> ${firstDeparture.to}',
        impactedPassengers: overview.disruptionSummary?.affectedBookingCount ??
            overview.liveOpsSummary.needsAttentionPassengers,
        rebookingOptions: <String>[
          if (firstDeparture != null)
            '${firstDeparture.from} -> ${firstDeparture.to} next departure',
          'Partner standby inventory',
          'Full refund to SyrChat wallet',
        ],
        compensationLabel: 'Service recovery voucher',
      ),
      const SizedBox(height: 16),
      CoachApprovalQueuePanel(
        items: <CoachApprovalQueueItem>[
          if (overview.supportSummary.openRefundRequests > 0)
            CoachApprovalQueueItem(
              title: 'Large refund review',
              detail:
                  '${overview.supportSummary.openRefundRequests} refund request(s) need admin decision.',
              riskLabel: 'Money movement',
              icon: Icons.request_quote_outlined,
            ),
          if (overview.financeSummary.failedPayoutRuns > 0)
            CoachApprovalQueueItem(
              title: 'Failed payout release',
              detail:
                  '${overview.financeSummary.failedPayoutRuns} payout run(s) need release approval.',
              riskLabel: 'Finance risk',
              icon: Icons.account_balance_wallet_outlined,
            ),
          if (overview.liveOpsSummary.needsAttentionPassengers > 0)
            CoachApprovalQueueItem(
              title: 'Manual passenger recovery',
              detail:
                  '${overview.liveOpsSummary.needsAttentionPassengers} passenger(s) need exception handling.',
              riskLabel: 'Passenger care',
              icon: Icons.support_agent_outlined,
            ),
        ],
      ),
      const SizedBox(height: 16),
      CoachTripHealthScorePanel(
        score: adminHealthScore,
        tripLabel: firstDeparture == null
            ? 'Network view'
            : '${firstDeparture.from} -> ${firstDeparture.to}',
        factors: <CoachTripHealthFactor>[
          CoachTripHealthFactor(
            icon: Icons.people_outline,
            label: 'Pending',
            value: '${overview.liveOpsSummary.pendingBoardingPassengers}',
            healthy: overview.liveOpsSummary.pendingBoardingPassengers == 0,
          ),
          CoachTripHealthFactor(
            icon: Icons.warning_amber_outlined,
            label: 'Attention',
            value: '${overview.liveOpsSummary.needsAttentionPassengers}',
            healthy: overview.liveOpsSummary.needsAttentionPassengers == 0,
          ),
          CoachTripHealthFactor(
            icon: Icons.report_problem_outlined,
            label: 'Disruptions',
            value: '${overview.disruptionSummary?.actionRequiredTrips ?? 0}',
            healthy:
                (overview.disruptionSummary?.actionRequiredTrips ?? 0) == 0,
          ),
          CoachTripHealthFactor(
            icon: Icons.hub_outlined,
            label: 'Feeds',
            value:
                '${overview.feedHealth.summary.degradedFeeds + overview.feedHealth.summary.staleFeeds}',
            healthy: overview.feedHealth.summary.degradedFeeds +
                    overview.feedHealth.summary.staleFeeds ==
                0,
          ),
        ],
      ),
      const SizedBox(height: 16),
      CoachPartnerPerformancePanel(
        partnerLabel: 'All coach partners',
        metrics: <CoachPerformanceMetric>[
          CoachPerformanceMetric(
            label: 'Feed health',
            value:
                '${overview.feedHealth.summary.healthyOperators}/${overview.feedHealth.summary.operatorsTotal}',
            detail: 'Healthy operators',
            icon: Icons.hub_outlined,
            color: const Color(0xFF2563EB),
          ),
          CoachPerformanceMetric(
            label: 'Refund load',
            value: '${overview.supportSummary.openRefundRequests}',
            detail: 'Open refund requests',
            icon: Icons.request_quote_outlined,
            color: const Color(0xFFB45309),
          ),
          CoachPerformanceMetric(
            label: 'Payout queue',
            value: '${overview.financeSummary.queuedPayoutRuns}',
            detail: 'Runs ready for finance',
            icon: Icons.account_balance_wallet_outlined,
            color: const Color(0xFF0F766E),
          ),
          CoachPerformanceMetric(
            label: 'Trip coverage',
            value: '${overview.liveOpsSummary.tripCount}',
            detail: 'Trips on the board',
            icon: Icons.departure_board_outlined,
            color: const Color(0xFF7C3AED),
          ),
        ],
      ),
      const SizedBox(height: 16),
      CoachTimelinePanel(
        title: isArabic ? 'خط زمني تشغيلي' : 'Coach operations timeline',
        events: <CoachTimelineEvent>[
          CoachTimelineEvent(
            icon: Icons.departure_board_outlined,
            title: isArabic ? 'الرحلة التالية' : 'Next departure',
            detail: firstDeparture == null
                ? (isArabic ? 'لا توجد رحلات محملة.' : 'No trips loaded.')
                : '${firstDeparture.from} -> ${firstDeparture.to}',
            timeLabel: firstDeparture == null
                ? '-'
                : _coachAdminIsoLabel(firstDeparture.departureAtIso),
            done: firstDeparture != null,
          ),
          CoachTimelineEvent(
            icon: Icons.warning_amber_outlined,
            title: isArabic ? 'التعطلات' : 'Disruptions',
            detail:
                '${overview.disruptionSummary?.actionRequiredTrips ?? 0} action required.',
            timeLabel: _coachAdminIsoLabel(overview.generatedAtIso),
            done: (overview.disruptionSummary?.actionRequiredTrips ?? 0) > 0,
          ),
          CoachTimelineEvent(
            icon: Icons.support_agent_outlined,
            title: isArabic ? 'الدعم' : 'Support',
            detail:
                '${overview.supportSummary.pendingReviewCount} pending review.',
            timeLabel: _coachAdminIsoLabel(overview.generatedAtIso),
            done: overview.supportSummary.pendingReviewCount > 0,
          ),
          CoachTimelineEvent(
            icon: Icons.account_balance_wallet_outlined,
            title: isArabic ? 'المالية' : 'Finance',
            detail:
                '${overview.financeSummary.queuedPayoutRuns} queued payout runs.',
            timeLabel: _coachAdminIsoLabel(overview.generatedAtIso),
            done: overview.financeSummary.queuedPayoutRuns > 0,
          ),
        ],
      ),
    ];
    return RefreshIndicator(
      onRefresh: _loadOverview,
      child: ListView(
        cacheExtent: 50000,
        padding: const EdgeInsets.all(16),
        children: [
          if (_errorMessage != null) ...[
            StatusBanner.warning(_errorMessage!),
            const SizedBox(height: 12),
          ],
          Text(
            isArabic
                ? 'آخر تحديث ${_coachAdminIsoLabel(overview.generatedAtIso)}'
                : 'Updated ${_coachAdminIsoLabel(overview.generatedAtIso)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _buildCommandDeskSection(context, overview, isArabic),
          const SizedBox(height: 16),
          _buildDeskFocusSection(
            context,
            overview,
            isArabic,
            sections,
            visibleSections.length,
            visibleSections,
          ),
          if (sectionWidgets.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...sectionWidgets,
          ],
          const SizedBox(height: 16),
          ...adminFeaturePanels,
        ],
      ),
    );
  }

  Widget _buildSimpleHomeSection(
    BuildContext context,
    CoachAdminOverviewResponse overview,
    bool isArabic,
  ) {
    final theme = Theme.of(context);
    final disruptionSummary = overview.disruptionSummary;
    final feedIssueCount = overview.feedHealth.summary.degradedFeeds +
        overview.feedHealth.summary.staleFeeds;
    final onboardingSummary = overview.partnerOnboardingSummary;
    final disruptionCount = disruptionSummary?.actionRequiredTrips ?? 0;
    final supportCount = overview.supportSummary.urgentRequestCount +
        overview.supportSummary.pendingReviewCount;
    final financeCount = overview.financeSummary.failedPayoutRuns > 0
        ? overview.financeSummary.failedPayoutRuns
        : overview.financeSummary.queuedPayoutRuns;
    final riskCount = overview.supportSummary.urgentRequestCount +
        overview.financeSummary.failedPayoutRuns +
        overview.liveOpsSummary.needsAttentionPassengers +
        feedIssueCount;
    final partnerCount = (onboardingSummary?.actionRequiredOperators ?? 0) +
        (onboardingSummary?.missingDocuments ?? 0);

    late final IconData primaryIcon;
    late final String primaryLabel;
    late final String primaryDetail;
    late final VoidCallback primaryAction;
    if (disruptionCount > 0) {
      primaryIcon = Icons.warning_amber_outlined;
      primaryLabel = isArabic ? 'افتح التعطلات الآن' : 'Open disruptions now';
      primaryDetail = isArabic
          ? '$disruptionCount رحلات تحتاج إجراء.'
          : '$disruptionCount trips need action.';
      primaryAction = _openDisruptionsPage;
    } else if (supportCount > 0) {
      primaryIcon = Icons.support_agent_outlined;
      primaryLabel = isArabic ? 'افتح الدعم الآن' : 'Open support now';
      primaryDetail = isArabic
          ? '$supportCount طلبات دعم تنتظر القرار.'
          : '$supportCount support items need review.';
      primaryAction = _openSupportCasesPage;
    } else if (financeCount > 0) {
      primaryIcon = Icons.account_balance_wallet_outlined;
      primaryLabel = isArabic ? 'افتح المالية الآن' : 'Open finance now';
      primaryDetail = isArabic
          ? '$financeCount دفعات تحتاج متابعة.'
          : '$financeCount payout items need follow-up.';
      primaryAction = _openFinanceJournalPage;
    } else if (riskCount > 0) {
      primaryIcon = Icons.shield_outlined;
      primaryLabel = isArabic ? 'افتح المخاطر الآن' : 'Open risk now';
      primaryDetail = isArabic
          ? '$riskCount إشارات مخاطرة نشطة.'
          : '$riskCount active risk signals.';
      primaryAction = _openRiskDashboardPage;
    } else if (partnerCount > 0) {
      primaryIcon = Icons.assignment_turned_in_outlined;
      primaryLabel = isArabic ? 'افتح الشركاء الآن' : 'Open partners now';
      primaryDetail = isArabic
          ? '$partnerCount عناصر جاهزية للشركاء.'
          : '$partnerCount partner readiness items.';
      primaryAction = _openPartnerOnboardingPage;
    } else {
      primaryIcon = Icons.check_circle_outline;
      primaryLabel = isArabic ? 'لا توجد أولوية عاجلة' : 'No urgent lane';
      primaryDetail = isArabic
          ? 'كل المكاتب هادئة. حدّث عند بدء الوردية التالية.'
          : 'All desks are quiet. Refresh when the next shift starts.';
      primaryAction = _loadOverview;
    }

    return Container(
      key: const ValueKey('coachAdminSimpleHome'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'ابدأ من هنا' : 'Start here',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'الصفحة الآن مرتبة حسب المهام اليومية: عالج الأهم أولاً، ثم افتح التفاصيل عند الحاجة.'
                : 'The coach admin app is now task-first: handle the most important queue, then open details only when needed.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('coachAdminSimplePrimaryAction'),
            onPressed: primaryAction,
            icon: Icon(primaryIcon),
            label: Text(primaryLabel),
          ),
          const SizedBox(height: 8),
          Text(
            primaryDetail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .68),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CoachAdminSimpleActionTile(
                key: const ValueKey('coachAdminSimpleAction_disruptions'),
                icon: Icons.warning_amber_outlined,
                title: isArabic ? 'التعطلات' : 'Disruptions',
                value: '$disruptionCount',
                detail:
                    isArabic ? 'رحلات تحتاج قرار' : 'Trips needing a decision',
                color: const Color(0xFFB91C1C),
                onTap: _openDisruptionsPage,
              ),
              _CoachAdminSimpleActionTile(
                key: const ValueKey('coachAdminSimpleAction_support'),
                icon: Icons.support_agent_outlined,
                title: isArabic ? 'الدعم' : 'Support',
                value: '$supportCount',
                detail: isArabic
                    ? 'عاجل وبانتظار المراجعة'
                    : 'Urgent and pending review',
                color: const Color(0xFF1D4ED8),
                onTap: _openSupportCasesPage,
              ),
              _CoachAdminSimpleActionTile(
                key: const ValueKey('coachAdminSimpleAction_finance'),
                icon: Icons.account_balance_wallet_outlined,
                title: isArabic ? 'المالية' : 'Finance',
                value: '$financeCount',
                detail: isArabic
                    ? 'دفعات فاشلة أو في الانتظار'
                    : 'Failed or queued payouts',
                color: const Color(0xFF0F766E),
                onTap: _openFinanceJournalPage,
              ),
              _CoachAdminSimpleActionTile(
                key: const ValueKey('coachAdminSimpleAction_risk'),
                icon: Icons.shield_outlined,
                title: isArabic ? 'المخاطر' : 'Risk',
                value: '$riskCount',
                detail: isArabic
                    ? 'تغذيات وصعود ودعم'
                    : 'Feeds, boarding, and support',
                color: const Color(0xFF7C3AED),
                onTap: _openRiskDashboardPage,
              ),
              _CoachAdminSimpleActionTile(
                key: const ValueKey('coachAdminSimpleAction_partners'),
                icon: Icons.assignment_turned_in_outlined,
                title: isArabic ? 'الشركاء' : 'Partners',
                value: '$partnerCount',
                detail: isArabic
                    ? 'جاهزية ووثائق ناقصة'
                    : 'Readiness and missing docs',
                color: const Color(0xFFB45309),
                onTap: _openPartnerOnboardingPage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeskFocusSection(
    BuildContext context,
    CoachAdminOverviewResponse overview,
    bool isArabic,
    List<String> sections,
    int visibleCount,
    List<String> visibleSections,
  ) {
    final collapsedVisibleCount = visibleSections
        .where((section) => _collapsedSections.contains(section))
        .length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE4EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'تركيز المكاتب' : 'Desk focus',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF1E293B),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'اعرض جميع المكاتب أو ركز على مكتب واحد داخل هذه الصفحة.'
                : 'Show every desk or stay inside one console section at a time.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF526176),
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('coachAdminCollapseVisible'),
                onPressed: visibleSections.isEmpty
                    ? null
                    : () => _collapseVisibleSections(visibleSections),
                icon: const Icon(Icons.unfold_less_outlined),
                label: Text(
                  isArabic ? 'طي المعروض' : 'Collapse visible',
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('coachAdminExpandVisible'),
                onPressed: visibleSections.isEmpty
                    ? null
                    : () => _expandVisibleSections(visibleSections),
                icon: const Icon(Icons.unfold_more_outlined),
                label: Text(
                  isArabic ? 'توسيع المعروض' : 'Expand visible',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('coachAdminSectionFocus_all'),
                label: Text(
                  '${_coachAdminSectionLabel('all', isArabic)} (${sections.length})',
                ),
                selected: _selectedSection == 'all',
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() {
                    _selectedSection = 'all';
                    _persistConsoleUiState();
                  });
                },
              ),
              for (final section in sections)
                ChoiceChip(
                  key: ValueKey('coachAdminSectionFocus_$section'),
                  label: Text(
                    '${_coachAdminSectionLabel(section, isArabic)} (${_coachAdminSectionSignalCount(overview, section)})',
                  ),
                  selected: _selectedSection == section,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _selectedSection = section;
                      _collapsedSections.remove(section);
                      _persistConsoleUiState();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isArabic
                ? 'يتم عرض $visibleCount من ${sections.length} مكاتب'
                : 'Showing $visibleCount of ${sections.length} desks',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF526176),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            isArabic
                ? 'مطوي $collapsedVisibleCount من $visibleCount'
                : 'Collapsed $collapsedVisibleCount of $visibleCount',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandDeskSection(
    BuildContext context,
    CoachAdminOverviewResponse overview,
    bool isArabic,
  ) {
    final theme = Theme.of(context);
    final disruptionSummary = overview.disruptionSummary;
    final payoutSummary = overview.payoutRuns.summary;
    final feedIssueCount = overview.feedHealth.summary.degradedFeeds +
        overview.feedHealth.summary.staleFeeds;
    final onboardingSummary = overview.partnerOnboardingSummary;
    final financeAttentionCount = overview.financeSummary.failedPayoutRuns > 0
        ? overview.financeSummary.failedPayoutRuns
        : overview.financeSummary.queuedPayoutRuns;
    final riskSignalCount = overview.supportSummary.urgentRequestCount +
        overview.financeSummary.failedPayoutRuns +
        overview.liveOpsSummary.needsAttentionPassengers +
        feedIssueCount;
    final attentionItems = <_CoachAdminAttentionItemData>[
      if (disruptionSummary != null &&
          disruptionSummary.actionRequiredTrips > 0)
        _CoachAdminAttentionItemData(
          icon: Icons.warning_amber_outlined,
          title: isArabic
              ? 'رحلات تحتاج تدخل تشغيلي'
              : 'Trips need disruption handling',
          detail: isArabic
              ? '${disruptionSummary.actionRequiredTrips} رحلة تحتاج متابعة عبر ${disruptionSummary.affectedBookingCount} حجز متأثر.'
              : '${disruptionSummary.actionRequiredTrips} trips need action across ${disruptionSummary.affectedBookingCount} affected bookings.',
        ),
      if (overview.supportSummary.urgentRequestCount > 0)
        _CoachAdminAttentionItemData(
          icon: Icons.support_agent_outlined,
          title: isArabic ? 'طلبات دعم عاجلة' : 'Urgent support queue',
          detail: isArabic
              ? '${overview.supportSummary.urgentRequestCount} طلبات عاجلة بانتظار قرار من فريق العمليات.'
              : '${overview.supportSummary.urgentRequestCount} urgent requests are waiting on ops review.',
        ),
      if (overview.financeSummary.failedPayoutRuns > 0)
        _CoachAdminAttentionItemData(
          icon: Icons.account_balance_wallet_outlined,
          title: isArabic ? 'دفعات فاشلة' : 'Failed payouts',
          detail: isArabic
              ? '${overview.financeSummary.failedPayoutRuns} تشغيلات دفع فشلت وتحتاج معالجة مالية.'
              : '${overview.financeSummary.failedPayoutRuns} payout runs failed and need finance follow-up.',
        )
      else if (overview.financeSummary.queuedPayoutRuns > 0)
        _CoachAdminAttentionItemData(
          icon: Icons.account_balance_wallet_outlined,
          title: isArabic ? 'دفعات في الانتظار' : 'Queued payouts',
          detail: isArabic
              ? '${overview.financeSummary.queuedPayoutRuns} تشغيلات دفع ما زالت بانتظار التنفيذ أو المطابقة.'
              : '${overview.financeSummary.queuedPayoutRuns} payout runs are still waiting for execution or reconciliation.',
        ),
      if (feedIssueCount > 0)
        _CoachAdminAttentionItemData(
          icon: Icons.hub_outlined,
          title: isArabic ? 'تغذيات شركاء متدهورة' : 'Partner feeds degraded',
          detail: isArabic
              ? '$feedIssueCount تغذيات متدهورة أو متقادمة تؤثر على المراقبة والعمليات.'
              : '$feedIssueCount partner feeds are degraded or stale and need follow-up.',
        ),
      if (onboardingSummary != null &&
          (onboardingSummary.actionRequiredOperators > 0 ||
              onboardingSummary.missingDocuments > 0))
        _CoachAdminAttentionItemData(
          icon: Icons.assignment_turned_in_outlined,
          title: isArabic
              ? 'توثيق الشركاء غير مكتمل'
              : 'Partner onboarding blocked',
          detail: isArabic
              ? '${onboardingSummary.actionRequiredOperators} مشغلين يحتاجون إجراء و${onboardingSummary.missingDocuments} وثائق ناقصة.'
              : '${onboardingSummary.actionRequiredOperators} operators need action and ${onboardingSummary.missingDocuments} documents are missing.',
        ),
      if (overview.liveOpsSummary.needsAttentionPassengers > 0)
        _CoachAdminAttentionItemData(
          icon: Icons.airline_seat_recline_normal_outlined,
          title: isArabic ? 'تنبيهات صعود' : 'Boarding attention',
          detail: isArabic
              ? '${overview.liveOpsSummary.needsAttentionPassengers} ركاب يحتاجون متابعة في الصعود أو المنع.'
              : '${overview.liveOpsSummary.needsAttentionPassengers} passengers need boarding review or intervention.',
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF8FBFF),
            Color(0xFFF1F6FB),
            Color(0xFFE8EFF8),
          ],
        ),
        border: Border.all(color: const Color(0xFFD8E1ED)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12081F17),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .82),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFD8E1ED)),
              ),
              child: Text(
                isArabic ? 'مكتب إدارة الحافلات' : 'Coach admin control room',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF1D4ED8),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isArabic ? 'مكتب القيادة التشغيلي' : 'Command desk',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF1E293B),
                fontWeight: FontWeight.w900,
                height: .96,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(
                isArabic
                    ? 'ابدأ من إشارات التشغيل الأشد إلحاحًا، ثم افتح المكتب المناسب مباشرة: التعطلات، الدعم، المالية، مطابقة SyrChat Pay، المخاطر، أو جاهزية الشركاء.'
                    : 'Start from the loudest operating signals, then jump straight into the right desk: disruptions, support, finance, SyrChat Pay reconciliation, risk, or partner readiness.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF526176),
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _CoachAdminCommandHeaderBadge(
                  icon: Icons.airline_seat_recline_normal_outlined,
                  label: isArabic ? 'تنبيهات الصعود' : 'Boarding alerts',
                  value: '${overview.liveOpsSummary.needsAttentionPassengers}',
                  color: const Color(0xFFB45309),
                ),
                _CoachAdminCommandHeaderBadge(
                  icon: Icons.support_agent_outlined,
                  label: isArabic ? 'الدعم العاجل' : 'Urgent support',
                  value: '${overview.supportSummary.urgentRequestCount}',
                  color: const Color(0xFFB91C1C),
                ),
                _CoachAdminCommandHeaderBadge(
                  icon: Icons.account_balance_wallet_outlined,
                  label: isArabic ? 'قائمة الدفعات' : 'Payout queue',
                  value: '$financeAttentionCount',
                  color: const Color(0xFF0F766E),
                ),
                _CoachAdminCommandHeaderBadge(
                  icon: Icons.hub_outlined,
                  label: isArabic ? 'مشاكل التغذية' : 'Feed issues',
                  value: '$feedIssueCount',
                  color: const Color(0xFF7C3AED),
                ),
                _CoachAdminCommandHeaderBadge(
                  icon: Icons.update_outlined,
                  label: isArabic ? 'آخر تحديث' : 'Updated',
                  value: _coachAdminIsoLabel(overview.generatedAtIso),
                  color: const Color(0xFF475569),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              isArabic ? 'مسارات الأولوية' : 'Priority lanes',
              style: theme.textTheme.titleSmall?.copyWith(
                color: const Color(0xFF1E293B),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _CoachAdminDeskLaneCard(
                  key: const ValueKey('coachAdminDeskLane_disruptions'),
                  icon: Icons.warning_amber_outlined,
                  value: '${disruptionSummary?.actionRequiredTrips ?? 0}',
                  label: isArabic ? 'التعطلات' : 'Disruptions',
                  detail: isArabic
                      ? '${disruptionSummary?.criticalTrips ?? 0} حرجة • ${disruptionSummary?.affectedBookingCount ?? 0} حجوزات متأثرة'
                      : '${disruptionSummary?.criticalTrips ?? 0} critical • ${disruptionSummary?.affectedBookingCount ?? 0} bookings hit',
                  actionLabel:
                      isArabic ? 'افتح مكتب التعطلات' : 'Open disruption desk',
                  accentColor: const Color(0xFFB91C1C),
                  onTap: _openDisruptionsPage,
                ),
                _CoachAdminDeskLaneCard(
                  key: const ValueKey('coachAdminDeskLane_support'),
                  icon: Icons.manage_search_outlined,
                  value: '${overview.supportSummary.urgentRequestCount}',
                  label: isArabic ? 'الدعم' : 'Support',
                  detail: isArabic
                      ? '${overview.supportSummary.pendingReviewCount} بانتظار المراجعة • ${overview.supportSummary.openRefundRequests} استرداد'
                      : '${overview.supportSummary.pendingReviewCount} pending review • ${overview.supportSummary.openRefundRequests} refunds',
                  actionLabel:
                      isArabic ? 'افتح مكتب الدعم' : 'Open support desk',
                  accentColor: const Color(0xFF1D4ED8),
                  onTap: _openSupportCasesPage,
                ),
                _CoachAdminDeskLaneCard(
                  key: const ValueKey('coachAdminDeskLane_finance'),
                  icon: Icons.account_balance_outlined,
                  value: '$financeAttentionCount',
                  label: isArabic ? 'المالية' : 'Finance',
                  detail: isArabic
                      ? '${overview.financeSummary.failedPayoutRuns} دفعات فاشلة • ${overview.financeSummary.queuedPayoutRuns} في الانتظار'
                      : '${overview.financeSummary.failedPayoutRuns} failed payouts • ${overview.financeSummary.queuedPayoutRuns} queued',
                  actionLabel:
                      isArabic ? 'افتح دفتر المالية' : 'Open finance journal',
                  accentColor: const Color(0xFF0F766E),
                  onTap: _openFinanceJournalPage,
                ),
                _CoachAdminDeskLaneCard(
                  key: const ValueKey('coachAdminDeskLane_shamell_pay'),
                  icon: Icons.sync_alt_outlined,
                  value: '${payoutSummary.queuedRuns}',
                  label: isArabic ? 'مطابقة SyrChat Pay' : 'SyrChat Pay',
                  detail: isArabic
                      ? '${_coachAdminMoneyLabel(payoutSummary.currency, payoutSummary.queuedNetPayableMinorUnits)} قيد العبور'
                      : '${_coachAdminMoneyLabel(payoutSummary.currency, payoutSummary.queuedNetPayableMinorUnits)} in transit',
                  actionLabel: isArabic
                      ? 'افتح مكتب المطابقة'
                      : 'Open reconciliation desk',
                  accentColor: const Color(0xFFB45309),
                  onTap: _openShamellPayReconciliationPage,
                ),
                _CoachAdminDeskLaneCard(
                  key: const ValueKey('coachAdminDeskLane_risk'),
                  icon: Icons.shield_outlined,
                  value: '$riskSignalCount',
                  label: isArabic ? 'المخاطر' : 'Risk',
                  detail: isArabic
                      ? '$feedIssueCount تغذيات متدهورة • ${overview.liveOpsSummary.needsAttentionPassengers} تنبيهات صعود'
                      : '$feedIssueCount feed issues • ${overview.liveOpsSummary.needsAttentionPassengers} boarding alerts',
                  actionLabel:
                      isArabic ? 'افتح لوحة المخاطر' : 'Open risk dashboard',
                  accentColor: const Color(0xFF7C3AED),
                  onTap: _openRiskDashboardPage,
                ),
                _CoachAdminDeskLaneCard(
                  key: const ValueKey('coachAdminDeskLane_partners'),
                  icon: Icons.assignment_turned_in_outlined,
                  value: '${onboardingSummary?.actionRequiredOperators ?? 0}',
                  label: isArabic ? 'الشركاء' : 'Partners',
                  detail: isArabic
                      ? '${onboardingSummary?.missingDocuments ?? 0} وثائق ناقصة • ${onboardingSummary?.inReviewOperators ?? 0} قيد المراجعة'
                      : '${onboardingSummary?.missingDocuments ?? 0} missing docs • ${onboardingSummary?.inReviewOperators ?? 0} in review',
                  actionLabel: isArabic
                      ? 'افتح جاهزية الشركاء'
                      : 'Open partner readiness',
                  accentColor: const Color(0xFFB91C1C),
                  onTap: _openPartnerOnboardingPage,
                ),
              ],
            ),
            if (attentionItems.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                isArabic ? 'يحتاج متابعة' : 'Needs attention',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF1E293B),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  for (final item in attentionItems) ...[
                    _CoachAdminAttentionItem(item: item),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLiveOpsSection(
    BuildContext context,
    CoachAdminOverviewResponse overview,
    bool isArabic,
  ) {
    final disruptionSummary = overview.disruptionSummary;
    return _CoachAdminSectionShell(
      key: const ValueKey('coachAdminSection_live_ops'),
      sectionId: 'live_ops',
      eyebrow: isArabic ? 'لوحة مباشرة' : 'Realtime board',
      title: isArabic ? 'العمليات الحية' : 'Live ops',
      subtitle: isArabic
          ? 'راقب الصعود والضغط على الرحلات الحية ثم مرر الرحلات المتأثرة سريعًا إلى مكتب التعطلات.'
          : 'Monitor boarding pressure across live departures, then hand off impacted trips into the disruption desk.',
      accentColor: const Color(0xFFB45309),
      collapsed: _collapsedSections.contains('live_ops'),
      onToggleCollapsed: () => _toggleSectionCollapsed('live_ops'),
      headerBadges: [
        _CoachAdminSectionBadge(
          icon: Icons.alt_route_outlined,
          label: isArabic
              ? 'الرحلات ${overview.liveOpsSummary.tripCount}'
              : 'Trips ${overview.liveOpsSummary.tripCount}',
          color: const Color(0xFFB45309),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.priority_high_outlined,
          label: isArabic
              ? 'تحتاج متابعة ${overview.liveOpsSummary.needsAttentionPassengers}'
              : 'Attention ${overview.liveOpsSummary.needsAttentionPassengers}',
          color: const Color(0xFFB91C1C),
        ),
        if (disruptionSummary != null)
          _CoachAdminSectionBadge(
            icon: Icons.warning_amber_outlined,
            label: isArabic
                ? 'تعطلات ${disruptionSummary.actionRequiredTrips}'
                : 'Disruptions ${disruptionSummary.actionRequiredTrips}',
            color: const Color(0xFFB91C1C),
          ),
        if (disruptionSummary != null)
          _CoachAdminSectionBadge(
            icon: Icons.swap_horiz_outlined,
            label: isArabic
                ? 'إعادة تسكين ${disruptionSummary.queuedReaccommodationCount}'
                : 'Reaccommodation ${disruptionSummary.queuedReaccommodationCount}',
            color: const Color(0xFF1D4ED8),
          ),
      ],
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'الصعود المكتمل' : 'Boarded',
              value: '${overview.liveOpsSummary.boardedPassengers}',
              detail: isArabic
                  ? '${overview.liveOpsSummary.pendingBoardingPassengers} بانتظار الصعود'
                  : '${overview.liveOpsSummary.pendingBoardingPassengers} pending boarding',
            ),
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'تنبيهات الصعود' : 'Boarding alerts',
              value: '${overview.liveOpsSummary.needsAttentionPassengers}',
              detail: isArabic
                  ? 'مراجعة منع الصعود أو المتأخرين'
                  : 'Review denied boarding and platform misses',
            ),
            if (disruptionSummary != null)
              _CoachAdminSectionMetricCard(
                label: isArabic ? 'الرحلات المتأثرة' : 'Affected trips',
                value: '${disruptionSummary.affectedBookingCount}',
                detail: isArabic
                    ? '${disruptionSummary.criticalTrips} حالات حرجة'
                    : '${disruptionSummary.criticalTrips} critical disruptions',
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final departure in overview.departures.departures.take(4)) ...[
          _CoachAdminSectionPreviewCard(
            icon: Icons.alt_route_outlined,
            accentColor: const Color(0xFFB45309),
            title: '${departure.from} → ${departure.to}',
            subtitle:
                '${departure.operatorName} • ${_coachAdminIsoLabel(departure.departureAtIso)}\n${departure.gateLabel} • ${departure.vehicleLabel}',
            trailing: Text(
              '${departure.boardedCount}/${departure.manifestCount}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            tags: [
              _CoachAdminSectionTag(
                label: isArabic
                    ? 'صعود ${departure.boardedCount}'
                    : 'Boarded ${departure.boardedCount}',
                color: const Color(0xFF0F766E),
              ),
              _CoachAdminSectionTag(
                label: isArabic
                    ? 'قيد الانتظار ${departure.pendingCount}'
                    : 'Pending ${departure.pendingCount}',
                color: const Color(0xFFB45309),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _openDisruptionsPage,
            icon: const Icon(Icons.warning_amber_outlined),
            label: const Text('Disruptions'),
          ),
        ),
      ],
    );
  }

  Widget _buildSupportSection(
    BuildContext context,
    CoachAdminOverviewResponse overview,
    bool isArabic,
  ) {
    return _CoachAdminSectionShell(
      key: const ValueKey('coachAdminSection_support'),
      sectionId: 'support',
      eyebrow: isArabic ? 'فرز العملاء' : 'Customer triage',
      title: isArabic ? 'الدعم' : 'Support',
      subtitle: isArabic
          ? 'افتح الطلبات العاجلة وطلبات الاسترداد والتغيير قبل إغلاق نوافذ الانطلاق.'
          : 'Open urgent refund and change work before departure windows close.',
      accentColor: const Color(0xFF1D4ED8),
      collapsed: _collapsedSections.contains('support'),
      onToggleCollapsed: () => _toggleSectionCollapsed('support'),
      headerBadges: [
        _CoachAdminSectionBadge(
          icon: Icons.schedule_outlined,
          label: isArabic
              ? 'بانتظار المراجعة ${overview.supportSummary.pendingReviewCount}'
              : 'Pending review ${overview.supportSummary.pendingReviewCount}',
          color: const Color(0xFF526176),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.priority_high_outlined,
          label: isArabic
              ? 'عاجلة ${overview.supportSummary.urgentRequestCount}'
              : 'Urgent ${overview.supportSummary.urgentRequestCount}',
          color: const Color(0xFFB91C1C),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.undo_outlined,
          label: isArabic
              ? 'استرداد ${overview.supportSummary.openRefundRequests}'
              : 'Refunds ${overview.supportSummary.openRefundRequests}',
          color: const Color(0xFF0F766E),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.swap_horiz_outlined,
          label: isArabic
              ? 'تغييرات ${overview.supportSummary.openChangeRequests}'
              : 'Changes ${overview.supportSummary.openChangeRequests}',
          color: const Color(0xFFB45309),
        ),
      ],
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'عاجلة' : 'Urgent',
              value: '${overview.supportSummary.urgentRequestCount}',
              detail: isArabic
                  ? 'طلبات تحتاج قرار عمليات'
                  : 'Requests waiting on ops judgment',
            ),
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'استرداد مفتوح' : 'Open refunds',
              value: '${overview.supportSummary.openRefundRequests}',
              detail: isArabic
                  ? 'راقب طلبات استرداد المغادرة القريبة'
                  : 'Watch refund exposure before departure',
            ),
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'تغييرات مفتوحة' : 'Open changes',
              value: '${overview.supportSummary.openChangeRequests}',
              detail: isArabic
                  ? 'طلبات تبديل أو تحصيل فروقات'
                  : 'Reschedule and collection work in flight',
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final request in overview.refundQueue.requests.take(2)) ...[
          _CoachAdminSectionPreviewCard(
            icon: Icons.undo_outlined,
            accentColor: const Color(0xFF0F766E),
            title: '${request.from} → ${request.to}',
            subtitle:
                '${request.operatorName} • ${request.suggestedAction}\n${_coachAdminIsoLabel(request.departureAtIso)}',
            trailing: Text(
              _coachAdminMoneyLabel(
                request.currency,
                request.requestedMinorUnits,
              ),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            tags: [
              _CoachAdminSectionTag(
                label: isArabic ? 'استرداد' : 'Refund',
                color: const Color(0xFF0F766E),
              ),
              _CoachAdminSectionTag(
                label: request.requestStatus,
                color: const Color(0xFF526176),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        for (final request in overview.changeQueue.requests.take(2)) ...[
          _CoachAdminSectionPreviewCard(
            icon: Icons.swap_horiz_outlined,
            accentColor: const Color(0xFFB45309),
            title: '${request.from} → ${request.to}',
            subtitle:
                '${request.operatorName} • ${request.suggestedAction}\n${_coachAdminIsoLabel(request.departureAtIso)}',
            trailing: Text(
              _coachAdminMoneyLabel(
                request.currency,
                request.totalDueMinorUnits,
              ),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            tags: [
              _CoachAdminSectionTag(
                label: isArabic ? 'تغيير' : 'Change',
                color: const Color(0xFFB45309),
              ),
              _CoachAdminSectionTag(
                label: request.requestStatus,
                color: const Color(0xFF526176),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _openSupportCasesPage,
            icon: const Icon(Icons.manage_search_outlined),
            label: Text(isArabic ? 'حالات الدعم' : 'Support cases'),
          ),
        ),
      ],
    );
  }

  Widget _buildFinanceSection(
    BuildContext context,
    CoachAdminOverviewResponse overview,
    bool isArabic,
  ) {
    return _CoachAdminSectionShell(
      key: const ValueKey('coachAdminSection_finance'),
      sectionId: 'finance',
      eyebrow: isArabic ? 'حركة الأموال' : 'Money movement',
      title: isArabic ? 'المالية' : 'Finance',
      subtitle: isArabic
          ? 'تتبع الجاهزية للكشوف وتشغيلات الدفع والجسر المالي قبل خروج الأموال.'
          : 'Track statement readiness, payout runs, and the settlement bridge before cash leaves the system.',
      accentColor: const Color(0xFF0F766E),
      collapsed: _collapsedSections.contains('finance'),
      onToggleCollapsed: () => _toggleSectionCollapsed('finance'),
      headerBadges: [
        _CoachAdminSectionBadge(
          icon: Icons.receipt_long_outlined,
          label: isArabic
              ? 'كشوف ${overview.financeSummary.statementCount}'
              : 'Statements ${overview.financeSummary.statementCount}',
          color: const Color(0xFF0F766E),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.account_balance_wallet_outlined,
          label: isArabic
              ? 'تشغيلات دفع ${overview.financeSummary.queuedPayoutRuns}'
              : 'Queued payouts ${overview.financeSummary.queuedPayoutRuns}',
          color: const Color(0xFF1D4ED8),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.error_outline,
          label: isArabic
              ? 'فاشلة ${overview.financeSummary.failedPayoutRuns}'
              : 'Failed ${overview.financeSummary.failedPayoutRuns}',
          color: const Color(0xFFB91C1C),
        ),
      ],
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2FBF7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFCDE8DD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _coachAdminMoneyLabel(
                  overview.financeSummary.currency,
                  overview.financeSummary.netPayableMinorUnits,
                ),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F766E),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? 'كشوف ${overview.financeSummary.statementCount} • تشغيلات دفع ${overview.financeSummary.queuedPayoutRuns} • فاشلة ${overview.financeSummary.failedPayoutRuns}'
                    : 'Statements ${overview.financeSummary.statementCount} • Queued payouts ${overview.financeSummary.queuedPayoutRuns} • Failed ${overview.financeSummary.failedPayoutRuns}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final statement
            in overview.settlementStatements.statements.take(3)) ...[
          _CoachAdminSectionPreviewCard(
            icon: Icons.receipt_long_outlined,
            accentColor: const Color(0xFF0F766E),
            title: statement.operatorName,
            subtitle:
                '${statement.status}\n${_coachAdminIsoLabel(statement.periodStartIso)} → ${_coachAdminIsoLabel(statement.periodEndIso)}',
            trailing: Text(
              _coachAdminMoneyLabel(
                statement.currency,
                statement.totals.netPayableMinorUnits,
              ),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            tags: [
              _CoachAdminSectionTag(
                label: statement.statementId,
                color: const Color(0xFF0F766E),
              ),
              _CoachAdminSectionTag(
                label: statement.status,
                color: const Color(0xFF0F766E),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        for (final run in overview.payoutRuns.runs.take(2)) ...[
          _CoachAdminSectionPreviewCard(
            icon: Icons.account_balance_wallet_outlined,
            accentColor: const Color(0xFF1D4ED8),
            title: run.operatorNames.join(', '),
            subtitle:
                '${run.payoutRunId} • ${run.status}\n${_coachAdminIsoLabel(run.createdAtIso)}',
            trailing: Text(
              _coachAdminMoneyLabel(
                run.currency,
                run.netPayableMinorUnits,
              ),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            tags: [
              _CoachAdminSectionTag(
                label: run.status,
                color: const Color(0xFF1D4ED8),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _openFinanceJournalPage,
              icon: const Icon(Icons.account_balance_outlined),
              label: const Text('Finance journal'),
            ),
            OutlinedButton.icon(
              onPressed: _openShamellPayReconciliationPage,
              icon: const Icon(Icons.sync_alt_outlined),
              label: const Text('SyrChat Pay reconciliation'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRiskSection(
    BuildContext context,
    CoachAdminOverviewResponse overview,
    bool isArabic,
  ) {
    final partnerSummary = overview.feedHealth.summary;
    return _CoachAdminSectionShell(
      key: const ValueKey('coachAdminSection_risk'),
      sectionId: 'risk',
      eyebrow: isArabic ? 'إشارات مركبة' : 'Signal fusion',
      title: isArabic ? 'المخاطر والامتثال' : 'Risk & compliance',
      subtitle: isArabic
          ? 'اجمع الإلحاح من الدعم والمالية والصعود وصحة الشركاء في صف واحد للتصعيد.'
          : 'Fuse urgency from support, finance, boarding, and partner health into one escalation lane.',
      accentColor: const Color(0xFF7C3AED),
      collapsed: _collapsedSections.contains('risk'),
      onToggleCollapsed: () => _toggleSectionCollapsed('risk'),
      headerBadges: [
        _CoachAdminSectionBadge(
          icon: Icons.support_agent_outlined,
          label: isArabic
              ? 'إلحاح ${overview.supportSummary.urgentRequestCount}'
              : 'Urgent ${overview.supportSummary.urgentRequestCount}',
          color: const Color(0xFFB91C1C),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.account_balance_wallet_outlined,
          label: isArabic
              ? 'دفع فاشل ${overview.financeSummary.failedPayoutRuns}'
              : 'Failed payouts ${overview.financeSummary.failedPayoutRuns}',
          color: const Color(0xFFB45309),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.airline_seat_recline_normal_outlined,
          label: isArabic
              ? 'تنبيه الصعود ${overview.liveOpsSummary.needsAttentionPassengers}'
              : 'Boarding alerts ${overview.liveOpsSummary.needsAttentionPassengers}',
          color: const Color(0xFF1D4ED8),
        ),
      ],
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'إشارات حمراء' : 'Red flags',
              value:
                  '${overview.supportSummary.urgentRequestCount + overview.financeSummary.failedPayoutRuns}',
              detail: isArabic
                  ? 'إلحاح الدعم وتعثر الدفعات'
                  : 'Support urgency plus payout failures',
            ),
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'ضغط التشغيل' : 'Ops pressure',
              value: '${overview.liveOpsSummary.needsAttentionPassengers}',
              detail: isArabic
                  ? 'حالات صعود تحتاج قرارًا'
                  : 'Boarding cases that need a decision',
            ),
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'صحة الشركاء' : 'Partner health',
              value:
                  '${partnerSummary.degradedFeeds + partnerSummary.staleFeeds}',
              detail: isArabic
                  ? '${partnerSummary.degradedFeeds} متدهورة • ${partnerSummary.staleFeeds} متقادمة'
                  : '${partnerSummary.degradedFeeds} degraded • ${partnerSummary.staleFeeds} stale',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _CoachAdminSectionPreviewCard(
          icon: Icons.shield_outlined,
          accentColor: const Color(0xFF7C3AED),
          title: isArabic
              ? 'مراجعة المخاطر التشغيلية والمالية'
              : 'Review operational and finance risk signals',
          subtitle: isArabic
              ? 'صف واحد يجمع الحوادث الحرجة، الدفعات الفاشلة، أعطال الشركاء وتنبيهات الصعود.'
              : 'One queue for critical incidents, failed payouts, partner feed issues, and boarding alerts.',
          tags: [
            _CoachAdminSectionTag(
              label: isArabic
                  ? 'التغذيات المتدهورة ${partnerSummary.degradedFeeds}'
                  : 'Degraded feeds ${partnerSummary.degradedFeeds}',
              color: const Color(0xFF7C3AED),
            ),
            _CoachAdminSectionTag(
              label: isArabic
                  ? 'التغذيات المتقادمة ${partnerSummary.staleFeeds}'
                  : 'Stale feeds ${partnerSummary.staleFeeds}',
              color: const Color(0xFF526176),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _openRiskDashboardPage,
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Risk dashboard'),
          ),
        ),
      ],
    );
  }

  Widget _buildPartnersSection(
    BuildContext context,
    CoachAdminOverviewResponse overview,
    bool isArabic,
  ) {
    final summary = overview.feedHealth.summary;
    final onboardingSummary = overview.partnerOnboardingSummary;
    return _CoachAdminSectionShell(
      key: const ValueKey('coachAdminSection_partners'),
      sectionId: 'partners',
      eyebrow: isArabic ? 'التغذية والاعتماد' : 'Feed and onboarding',
      title: isArabic ? 'صحة الشركاء' : 'Partner health',
      subtitle: isArabic
          ? 'راقب انتعاش التغذيات وجاهزية الشركاء قبل أن تتحول المشكلات الصامتة إلى ضوضاء تشغيلية.'
          : 'Track feed freshness and partner readiness before quiet partner issues spill into operations.',
      accentColor: const Color(0xFFB91C1C),
      collapsed: _collapsedSections.contains('partners'),
      onToggleCollapsed: () => _toggleSectionCollapsed('partners'),
      headerBadges: [
        _CoachAdminSectionBadge(
          icon: Icons.groups_outlined,
          label: isArabic
              ? 'المشغلون ${summary.operatorsTotal}'
              : 'Operators ${summary.operatorsTotal}',
          color: const Color(0xFF526176),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.check_circle_outline,
          label: isArabic
              ? 'سليم ${summary.healthyOperators}'
              : 'Healthy ${summary.healthyOperators}',
          color: const Color(0xFF0F766E),
        ),
        _CoachAdminSectionBadge(
          icon: Icons.warning_amber_outlined,
          label: isArabic
              ? 'متدهور ${summary.degradedFeeds}'
              : 'Degraded ${summary.degradedFeeds}',
          color: const Color(0xFFB91C1C),
        ),
        if (onboardingSummary != null)
          _CoachAdminSectionBadge(
            icon: Icons.assignment_turned_in_outlined,
            label: isArabic
                ? 'إجراء مطلوب ${onboardingSummary.actionRequiredOperators}'
                : 'Action required ${onboardingSummary.actionRequiredOperators}',
            color: const Color(0xFFB45309),
          ),
      ],
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _CoachAdminSectionMetricCard(
              label: isArabic ? 'متقادم' : 'Stale',
              value: '${summary.staleFeeds}',
              detail: isArabic
                  ? 'تغذيات لم تتجدد في الوقت'
                  : 'Feeds that missed freshness windows',
            ),
            if (onboardingSummary != null)
              _CoachAdminSectionMetricCard(
                label: isArabic ? 'قيد المراجعة' : 'In review',
                value: '${onboardingSummary.inReviewOperators}',
                detail: isArabic
                    ? '${onboardingSummary.missingDocuments} وثائق ناقصة'
                    : '${onboardingSummary.missingDocuments} missing docs',
              ),
            if (onboardingSummary != null)
              _CoachAdminSectionMetricCard(
                label: isArabic ? 'معلقة' : 'Expiring docs',
                value: '${onboardingSummary.expiringDocuments}',
                detail: isArabic
                    ? 'وثائق تقترب من الانتهاء'
                    : 'Documents approaching expiry',
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _openPartnerOnboardingPage,
            icon: const Icon(Icons.assignment_turned_in_outlined),
            label: Text(
              isArabic ? 'إعداد الشركاء' : 'Partner onboarding',
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final feed in overview.feedHealth.feeds.take(6)) ...[
          _CoachAdminSectionPreviewCard(
            icon: feed.isHealthy
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
            accentColor: feed.isHealthy
                ? const Color(0xFF0F766E)
                : const Color(0xFFB91C1C),
            title: '${feed.operatorName} • ${feed.feedKind}',
            subtitle:
                '${_coachFeedFreshnessLabel(feed)} • ${feed.operatorIntegrationMode}\n${feed.lastSucceededAtIso == null ? '-' : _coachAdminIsoLabel(feed.lastSucceededAtIso!)}',
            tags: [
              _CoachAdminSectionTag(
                label: feed.syncStatus,
                color: feed.isHealthy
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFB91C1C),
              ),
              _CoachAdminSectionTag(
                label: feed.freshnessStatus,
                color: const Color(0xFF526176),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CoachAdminAttentionItemData {
  final IconData icon;
  final String title;
  final String detail;

  const _CoachAdminAttentionItemData({
    required this.icon,
    required this.title,
    required this.detail,
  });
}

class _CoachAdminCommandHeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _CoachAdminCommandHeaderBadge({
    required this.icon,
    required this.label,
    required this.value,
    this.color = const Color(0xFF526176),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E1ED)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label $value',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _CoachAdminDeskLaneCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String detail;
  final String actionLabel;
  final Color accentColor;
  final VoidCallback onTap;

  const _CoachAdminDeskLaneCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.detail,
    required this.actionLabel,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .78),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD8E1ED)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: accentColor),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF526176),
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        actionLabel,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: accentColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoachAdminSectionShell extends StatelessWidget {
  final String sectionId;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color accentColor;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final List<Widget> headerBadges;
  final List<Widget> children;

  const _CoachAdminSectionShell({
    super.key,
    required this.sectionId,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.headerBadges,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE4EE)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 22,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: const Color(0xFF1E293B),
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('coachAdminSectionToggle_$sectionId'),
                tooltip: collapsed ? 'Expand section' : 'Collapse section',
                onPressed: onToggleCollapsed,
                icon: Icon(
                  collapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF526176),
                    height: 1.45,
                  ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: collapsed
                ? Padding(
                    key: ValueKey('coachAdminSectionCollapsed_$sectionId'),
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCE4EE)),
                      ),
                      child: Text(
                        'Section collapsed. Expand to inspect details.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF526176),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  )
                : Column(
                    key: ValueKey('coachAdminSectionBody_$sectionId'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (headerBadges.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: headerBadges,
                        ),
                      ],
                      const SizedBox(height: 16),
                      ...children,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CoachAdminSectionBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CoachAdminSectionBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
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
}

class _CoachAdminSectionMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String detail;

  const _CoachAdminSectionMetricCard({
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCE4EE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF526176),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    height: 1.35,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachAdminSimpleActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  const _CoachAdminSimpleActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 210,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .46),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const Spacer(),
                    Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    height: 1.35,
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

class _CoachAdminSectionPreviewCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> tags;

  const _CoachAdminSectionPreviewCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.tags = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE4EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF1E293B),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF526176),
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags,
            ),
          ],
        ],
      ),
    );
  }
}

class _CoachAdminSectionTag extends StatelessWidget {
  final String label;
  final Color color;

  const _CoachAdminSectionTag({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _CoachAdminAttentionItem extends StatelessWidget {
  final _CoachAdminAttentionItemData item;

  const _CoachAdminAttentionItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 18,
            color: theme.colorScheme.primary.withValues(alpha: .95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
