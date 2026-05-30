import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account_privilege_store.dart';
import '../account_session_bootstrap.dart';
import '../app_surface.dart';
import '../dashboard_policy_scope.dart';
import '../format.dart';
import '../l10n.dart';
import '../demand_heatmap_page.dart';
import '../notification_service.dart';
import '../operator_cancellation_analytics_page.dart';
import '../operator_promo_management_page.dart';
import '../operator_scheduled_rides_page.dart';
import '../passenger_rating_api.dart';
import '../privacy_redaction.dart';
import '../safety_alerts_api.dart';
import '../push_readiness_banner.dart';
import '../role_signup_api.dart';
import '../role_signup_gate.dart';
import '../shamell_loading_shimmer.dart';
import '../shamell_support.dart';
import 'ride_driver_fleet_map_card.dart';
import 'ride_hailing_store.dart';
import 'ride_mobility_api.dart';
import 'ride_platform_contracts.dart';
import 'ride_taxi_feature_widgets.dart';

enum _RideOperatorFleetFilter {
  all,
  idle,
  onTrip,
  stale,
  noGps,
}

const Duration _rideOperatorStaleDriverThreshold = Duration(seconds: 30);
const bool _rideOperatorDiagnosticLogs =
    bool.fromEnvironment('SHAMELL_DIAGNOSTIC_BOOTSTRAP_LOGS');

@visibleForTesting
bool rideOperatorDriverIsStale(
  RideOperatorDriverRosterEntry driver, {
  DateTime? now,
}) {
  final parsed = DateTime.tryParse(driver.lastSeenAtIso);
  if (parsed == null) {
    return true;
  }
  final reference = (now ?? DateTime.now()).toUtc();
  return reference.difference(parsed.toUtc()) >=
      _rideOperatorStaleDriverThreshold;
}

@visibleForTesting
bool rideOperatorDriverMatchesFleetFilter({
  required RideOperatorDriverRosterEntry driver,
  required String filterWireValue,
  DateTime? now,
}) {
  switch (filterWireValue) {
    case 'idle':
      return driver.isIdleOnline;
    case 'on_trip':
      return driver.isOnline && driver.activeRideId != null;
    case 'stale':
      return driver.isOnline && rideOperatorDriverIsStale(driver, now: now);
    case 'no_gps':
      return driver.isOnline && driver.location == null;
    case 'all':
    default:
      return true;
  }
}

@visibleForTesting
bool rideOperatorShouldNotifyFocusTripTransition({
  required RideTrip? previousTrip,
  required RideTrip? nextTrip,
}) {
  if (previousTrip == null || nextTrip == null) {
    return false;
  }
  if (previousTrip.rideId != nextTrip.rideId) {
    return false;
  }
  return previousTrip.status != nextTrip.status;
}

@visibleForTesting
bool rideOperatorSensitiveRevealStillValid(
  DateTime? unlockedUntil, {
  DateTime? now,
}) {
  if (unlockedUntil == null) {
    return false;
  }
  final reference = (now ?? DateTime.now()).toUtc();
  return unlockedUntil.isAfter(reference);
}

@visibleForTesting
bool rideOperatorPlatformRequiresSensitiveLocalAuth({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  if (isWeb) {
    return false;
  }
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return false;
  }
}

@visibleForTesting
String rideOperatorPrivacySafeTripTransitionBody({
  required RideTrip nextTrip,
  required bool isArabic,
  required String statusLabel,
}) {
  final rideLabel = shamellShortRideId(nextTrip.rideId);
  return isArabic
      ? 'الرحلة $rideLabel: الحالة الآن $statusLabel.'
      : 'Ride $rideLabel: now $statusLabel.';
}

@visibleForTesting
String rideOperatorTripIdLabel(String rideId, {required bool isArabic}) {
  final rideLabel = shamellShortRideId(rideId);
  return isArabic ? 'المعرّف $rideLabel' : 'Ride ID $rideLabel';
}

@visibleForTesting
String rideOperatorActiveRideLabel(String? rideId, {required bool isArabic}) {
  final normalized = rideId?.trim() ?? '';
  if (normalized.isEmpty) {
    return '';
  }
  final rideLabel = shamellShortRideId(normalized);
  return isArabic ? 'رحلة نشطة $rideLabel' : 'Active trip $rideLabel';
}

@visibleForTesting
RideTrip? rideOperatorFindTripById({
  required RideOperatorLiveBoard? board,
  required String rideId,
}) {
  final normalizedRideId = rideId.trim();
  if (board == null || normalizedRideId.isEmpty) {
    return null;
  }
  for (final trip in board.activeTrips) {
    if (trip.rideId.trim() == normalizedRideId) {
      return trip;
    }
  }
  for (final trip in board.openDispatches) {
    if (trip.rideId.trim() == normalizedRideId) {
      return trip;
    }
  }
  return null;
}

String _rideOperatorWorkspaceLabel(
  String workspace, {
  required bool isArabic,
}) {
  switch (workspace) {
    case 'dispatches':
      return isArabic ? 'الطلبات' : 'Dispatches';
    case 'fleet':
      return isArabic ? 'الأسطول' : 'Fleet';
    case 'cases':
      return isArabic ? 'القضايا' : 'Cases';
    case 'support':
      return isArabic ? 'الدعم' : 'Support';
    case 'documents':
      return isArabic ? 'الوثائق' : 'Documents';
    case 'payouts':
      return isArabic ? 'السحوبات' : 'Payouts';
    case 'signups':
      // Cycle 101 — role signup review queue.
      return isArabic ? 'طلبات التسجيل' : 'Signups';
    default:
      return isArabic ? 'الكل' : 'All';
  }
}

bool _rideOperatorWorkspaceVisible(String selectedWorkspace, String workspace) {
  return selectedWorkspace == 'all' || selectedWorkspace == workspace;
}

_RideOperatorFleetFilter? _rideOperatorFleetFilterFromWireValue(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'all':
      return _RideOperatorFleetFilter.all;
    case 'idle':
      return _RideOperatorFleetFilter.idle;
    case 'on_trip':
      return _RideOperatorFleetFilter.onTrip;
    case 'stale':
      return _RideOperatorFleetFilter.stale;
    case 'no_gps':
      return _RideOperatorFleetFilter.noGps;
    default:
      return null;
  }
}

const Set<String> _rideOperatorSortableWorkspaces = <String>{
  'fleet',
  'dispatches',
  'cases',
  'support',
  'documents',
  'payouts',
};

class RideOperatorConsolePage extends StatefulWidget {
  final String? baseUrl;
  final RideMobilityApi? apiOverride;
  final ShamellDashboardPolicy? dashboardPolicyOverride;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;
  final bool bootstrapOnInit;
  final RidePlatformBootstrap? initialBootstrap;
  final RideOperatorLiveBoard? initialBoard;
  final RideOperatorDriverRoster? initialDriverRoster;
  final RideOperatorCaseQueue? initialCaseQueue;
  final RideOperatorSupportQueue? initialSupportQueue;
  final RideOperatorFinanceQueue? initialFinanceQueue;
  final RideOperatorDocumentQueue? initialDocumentQueue;
  final RideOperatorPricingPolicyDashboard? initialPricingPolicies;
  final RideTrip? initialFocusTrip;
  final RideTomTomQuote? initialFocusQuote;
  final RideLiveTrackingSnapshot? initialFocusTracking;

  const RideOperatorConsolePage({
    super.key,
    this.baseUrl,
    this.apiOverride,
    this.dashboardPolicyOverride,
    this.privilegeSnapshotOverride,
    this.bootstrapOnInit = true,
    this.initialBootstrap,
    this.initialBoard,
    this.initialDriverRoster,
    this.initialCaseQueue,
    this.initialSupportQueue,
    this.initialFinanceQueue,
    this.initialDocumentQueue,
    this.initialPricingPolicies,
    this.initialFocusTrip,
    this.initialFocusQuote,
    this.initialFocusTracking,
  });

  @override
  State<RideOperatorConsolePage> createState() =>
      _RideOperatorConsolePageState();
}

class _RideOperatorConsolePageState extends State<RideOperatorConsolePage> {
  static const String _pageStorageStateIdentifier =
      'ride_operator_console_ui_state';
  late final RideMobilityApi _mobilityApi;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _fleetSectionKey = GlobalKey(
    debugLabel: 'rideOpsFleetSection',
  );
  final GlobalKey _dispatchesSectionKey = GlobalKey(
    debugLabel: 'rideOpsDispatchesSection',
  );
  final GlobalKey _caseQueueSectionKey = GlobalKey(
    debugLabel: 'rideOpsCaseQueueSection',
  );
  final GlobalKey _supportQueueSectionKey = GlobalKey(
    debugLabel: 'rideOpsSupportQueueSection',
  );
  final GlobalKey _documentQueueSectionKey = GlobalKey(
    debugLabel: 'rideOpsDocumentQueueSection',
  );
  final GlobalKey _financeQueueSectionKey = GlobalKey(
    debugLabel: 'rideOpsFinanceQueueSection',
  );
  // Cycle 103 — scroll-target for the role-signup admin workspace
  // so the command desk's attention chip can jump there on tap.
  final GlobalKey _signupQueueSectionKey = GlobalKey(
    debugLabel: 'rideOpsSignupQueueSection',
  );

  Timer? _pollTimer;
  Timer? _updatesRetryTimer;
  StreamSubscription<String>? _updatesSub;
  RidePlatformBootstrap? _bootstrap;
  RideOperatorLiveBoard? _board;
  RideOperatorDriverRoster? _driverRoster;
  RideOperatorCaseQueue? _caseQueue;
  RideOperatorSupportQueue? _supportQueue;
  RideOperatorFinanceQueue? _financeQueue;
  RideOperatorDocumentQueue? _documentQueue;
  RideOperatorPricingPolicyDashboard? _pricingPolicies;
  // Cycle 101 — role-signup admin queue. Null until the first
  // admin-only refresh; empty list means "no pending requests".
  List<RoleSignupRequest>? _signupQueue;
  // Cycle 105 — selected role filter for the Signups workspace:
  // null = all, otherwise a specific role id from
  // `RoleSignupRoleIds`. Persisted across rebuilds within a session
  // so the admin's chosen view sticks while they triage.
  String? _signupRoleFilter;
  RideTrip? _focusTrip;
  RideTomTomQuote? _focusQuote;
  RideLiveTrackingSnapshot? _focusTracking;
  List<String> _opsDataWarnings = const <String>[];
  AccountPrivilegeSnapshot _privileges = AccountPrivilegeSnapshot.empty;
  int? _lastOpenDispatches;
  int? _lastActiveTrips;
  int? _lastCriticalCases;
  int? _lastOpenSupportTickets;
  int? _lastPendingPayoutRequests;
  int? _lastPendingDocuments;
  RideTrip? _lastNotifiedFocusTrip;
  // Cycle 154 — active SOS alerts shown as a top banner. Refreshed
  // alongside the rest in `_refreshAll`. We keep an int seen-count
  // so we can chirp + push a notification only on the rising edge
  // (a new alert landed) — not on every poll-tick refresh.
  List<SafetyAlert> _safetyAlerts = const <SafetyAlert>[];
  int _lastNotifiedActiveSafetyAlertCount = 0;
  bool _loading = true;
  bool _refreshing = false;
  // Cycle 88 — last successful _refreshAll completion timestamp.
  // Drives the AppBar action chip so operators can tell at a glance
  // whether the dashboard is fresh or stalled.
  DateTime? _lastRefreshedAt;
  _RideOperatorFleetFilter _fleetFilter = _RideOperatorFleetFilter.all;
  String _selectedWorkspace = 'all';
  String _selectedTaxiZoneMode = 'Balanced';
  final Set<String> _collapsedWorkspaces = <String>{};
  final Map<String, String> _workspaceSorts = <String, String>{};
  bool _restoredStoredState = false;

  bool get _opsAllowed => shamellHasRideOperatorSnapshotAccess(_privileges);

  bool get _supportAllowed => shamellHasRideSupportSnapshotAccess(_privileges);

  bool get _financeAllowed => shamellHasRideFinanceSnapshotAccess(_privileges);

  bool get _financeSensitiveAllowed =>
      shamellHasRideFinanceSensitiveSnapshotAccess(_privileges);

  bool get _complianceAllowed =>
      shamellHasRideComplianceSnapshotAccess(_privileges);

  bool get _complianceSensitiveAllowed =>
      shamellHasRideComplianceSensitiveSnapshotAccess(_privileges);

  bool get _pricingAllowed => shamellHasRidePricingSnapshotAccess(_privileges);

  Future<bool> _requireSensitiveReveal({
    required String reason,
  }) async {
    return true;
  }

  Future<AccountPrivilegeSnapshot> _refreshPrivileges() async {
    final override = widget.privilegeSnapshotOverride;
    if (override != null) {
      return override;
    }
    final scopedPolicy = shamellDashboardPolicyOverrideOrScope(
      context,
      baseUrl: widget.baseUrl ?? '',
      policyOverride: widget.dashboardPolicyOverride,
    );
    if (scopedPolicy != null) {
      return scopedPolicy.privilegeSnapshot;
    }
    final baseUrl = (widget.baseUrl ?? '').trim();
    final stored = await loadAccountPrivilegeSnapshotForBaseUrl(baseUrl);
    final cached = await loadAccountPrivilegeSnapshotFromCachedHomeSnapshot(
      baseUrlOverride: baseUrl,
    );
    final fallback = accountPrivilegeSnapshotHasData(stored) ? stored : cached;
    if (_rideOperatorDiagnosticLogs) {
      debugPrint(
        'OPS_PRIVILEGES_STORED: origin_present=${baseUrl.isNotEmpty} role_count=${stored.roles.length} '
        'superadmin=${stored.isSuperadmin} '
        'cached_role_count=${cached.roles.length} '
        'cached_superadmin=${cached.isSuperadmin}',
      );
    }
    if (baseUrl.isEmpty) {
      return fallback;
    }
    try {
      final snapshot = await refreshAndPersistAccountHomeSnapshot(
        baseUrl: baseUrl,
        ensureSession: false,
      );
      final privileges = accountPrivilegeSnapshotFromPayload(snapshot.payload);
      await saveAccountPrivilegeSnapshot(
        roles: privileges.roles,
        isSuperadmin: privileges.isSuperadmin,
        operatorIds: privileges.operatorIds,
        permissions: privileges.permissions,
        products: privileges.products,
        officialAccountIds: privileges.officialAccountIds,
        officialAccountWildcard: privileges.officialAccountWildcard,
        hasPlatformScope: privileges.hasPlatformScope,
        isAdmin: privileges.isAdmin,
        baseUrlOverride: baseUrl,
      );
      if (_rideOperatorDiagnosticLogs) {
        debugPrint(
          'OPS_PRIVILEGES_REFRESHED: origin_present=${baseUrl.isNotEmpty} role_count=${privileges.roles.length} '
          'superadmin=${privileges.isSuperadmin} permission_count=${privileges.permissions.length}',
        );
      }
      return privileges;
    } catch (error) {
      if (_rideOperatorDiagnosticLogs) {
        debugPrint(
          'OPS_PRIVILEGES_REFRESH_FAILED: origin_present=${baseUrl.isNotEmpty} error=$error '
          'fallback_role_count=${fallback.roles.length} '
          'fallback_superadmin=${fallback.isSuperadmin}',
        );
      }
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _mobilityApi =
        widget.apiOverride ?? RideMobilityApi(baseUrl: widget.baseUrl ?? '');
    _seedInitialState();
    if (widget.bootstrapOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_bootstrapConsole());
      });
    } else {
      _loading = false;
    }
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
    final selectedWorkspace = stored['selectedWorkspace'];
    const knownWorkspaces = <String>{
      'all',
      'dispatches',
      'fleet',
      'cases',
      'support',
      'documents',
      'payouts',
    };
    if (selectedWorkspace is String &&
        knownWorkspaces.contains(selectedWorkspace)) {
      _selectedWorkspace = selectedWorkspace;
    }
    final selectedTaxiZoneMode = stored['selectedTaxiZoneMode'];
    if (selectedTaxiZoneMode is String &&
        taxiOperatorZoneModes.contains(selectedTaxiZoneMode)) {
      _selectedTaxiZoneMode = selectedTaxiZoneMode;
    }
    final collapsedWorkspaces = stored['collapsedWorkspaces'];
    if (collapsedWorkspaces is List) {
      _collapsedWorkspaces
        ..clear()
        ..addAll(
          collapsedWorkspaces
              .map((entry) => entry.toString().trim())
              .where((entry) => knownWorkspaces.contains(entry))
              .where((entry) => entry != 'all'),
        );
    }
    final fleetFilter = stored['fleetFilter'];
    if (fleetFilter is String) {
      final restoredFilter = _rideOperatorFleetFilterFromWireValue(
        fleetFilter,
      );
      if (restoredFilter != null) {
        _fleetFilter = restoredFilter;
      }
    }
    final workspaceSorts = stored['workspaceSorts'];
    if (workspaceSorts is Map) {
      _workspaceSorts
        ..clear()
        ..addEntries(
          workspaceSorts.entries
              .map(
                (entry) => MapEntry(
                  entry.key.toString().trim(),
                  entry.value.toString().trim(),
                ),
              )
              .where(
                (entry) =>
                    _rideOperatorSortableWorkspaces.contains(entry.key) &&
                    _workspaceSortOptions(entry.key, isArabic: false)
                        .any((option) => option.id == entry.value),
              ),
        );
    }
    // Cycle 112 — restore the role filter from the Signups workspace
    // so an admin who triages "Drivers only" before lunch comes back
    // to the same view in the afternoon.
    final signupRoleFilter = stored['signupRoleFilter'];
    if (signupRoleFilter is String) {
      final trimmed = signupRoleFilter.trim();
      if (trimmed == RoleSignupRoleIds.driver ||
          trimmed == RoleSignupRoleIds.operator ||
          trimmed == RoleSignupRoleIds.busOperator ||
          trimmed == RoleSignupRoleIds.hotelOperator ||
          trimmed == RoleSignupRoleIds.carrier ||
          trimmed == RoleSignupRoleIds.syrcom) {
        _signupRoleFilter = trimmed;
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _updatesRetryTimer?.cancel();
    _updatesSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _seedInitialState() {
    final seededBoard = widget.initialBoard;
    final seededFocusTrip = widget.initialFocusTrip ??
        (seededBoard?.activeTrips.isNotEmpty == true
            ? seededBoard!.activeTrips.first
            : seededBoard?.openDispatches.isNotEmpty == true
                ? seededBoard!.openDispatches.first
                : null);
    _bootstrap = widget.initialBootstrap;
    _board = seededBoard;
    _driverRoster = widget.initialDriverRoster;
    _caseQueue = widget.initialCaseQueue;
    _supportQueue = widget.initialSupportQueue;
    _financeQueue = widget.initialFinanceQueue;
    _documentQueue = widget.initialDocumentQueue;
    _pricingPolicies = widget.initialPricingPolicies;
    _focusTrip = seededFocusTrip;
    _focusQuote = widget.initialFocusQuote;
    _focusTracking = widget.initialFocusTracking;
    _privileges = widget.privilegeSnapshotOverride ??
        widget.dashboardPolicyOverride?.privilegeSnapshot ??
        _privileges;
    _lastOpenDispatches = seededBoard?.counts.openDispatches;
    _lastActiveTrips = seededBoard?.counts.activeTrips;
    _lastCriticalCases = widget.initialCaseQueue?.totals.criticalCases;
    _lastOpenSupportTickets = widget.initialSupportQueue?.totals.openTickets;
    _lastPendingPayoutRequests =
        widget.initialFinanceQueue?.totals.pendingRequests;
    _lastPendingDocuments =
        widget.initialDocumentQueue?.totals.pendingDocuments;
    _lastNotifiedFocusTrip = seededFocusTrip;
  }

  void _persistOperatorUiState() {
    PageStorage.maybeOf(context)?.writeState(
      context,
      <String, Object?>{
        'selectedWorkspace': _selectedWorkspace,
        'selectedTaxiZoneMode': _selectedTaxiZoneMode,
        'collapsedWorkspaces': _collapsedWorkspaces.toList(growable: false),
        'fleetFilter': _fleetFilterWireValue(_fleetFilter),
        'workspaceSorts': Map<String, String>.from(_workspaceSorts),
        // Cycle 112 — persist the Signups workspace role filter.
        'signupRoleFilter': _signupRoleFilter,
      },
      identifier: _pageStorageStateIdentifier,
    );
  }

  void _showOperatorTaxiFeatureNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openOperatorRideReplay() {
    final isArabic = L10n.of(context).isArabic;
    _showOperatorTaxiFeatureNotice(
      isArabic
          ? 'Ride replay جاهز كتسلسل: طلب، مطابقة، مسار، دفع ودعم.'
          : 'Ride replay is ready as a timeline: request, match, route, payment, and support.',
    );
  }

  void _prepareOperatorEvidenceBundle() {
    final isArabic = L10n.of(context).isArabic;
    _showOperatorTaxiFeatureNotice(
      isArabic
          ? 'تم تجهيز حزمة الأدلة: المسار، الدردشة، المكالمات، الدفع والتايملاين.'
          : 'Evidence bundle prepared: route, chat, calls, payment, and timeline.',
    );
  }

  void _runOperatorAutoRematch() {
    final isArabic = L10n.of(context).isArabic;
    _showOperatorTaxiFeatureNotice(
      isArabic
          ? 'Auto-rematch يفحص السائقين غير المستجيبين أو البعيدين.'
          : 'Auto-rematch checks unresponsive or drifting drivers.',
    );
  }

  void _openOperatorDocumentExpiry() {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _selectedWorkspace = 'documents';
      _collapsedWorkspaces.remove('documents');
      _persistOperatorUiState();
    });
    _showOperatorTaxiFeatureNotice(
      isArabic
          ? 'تم فتح مساحة وثائق السائقين لمراجعة الانتهاء والتجديد.'
          : 'Driver documents workspace opened for expiry and renewal review.',
    );
  }

  List<String> _visibleWorkspaces({
    required List<String> availableWorkspaces,
    required String selectedWorkspace,
  }) {
    if (selectedWorkspace == 'all') {
      return availableWorkspaces;
    }
    return availableWorkspaces
        .where((workspace) => workspace == selectedWorkspace)
        .toList(growable: false);
  }

  void _selectWorkspace(String workspace) {
    setState(() {
      _selectedWorkspace = workspace;
      if (workspace != 'all') {
        _collapsedWorkspaces.remove(workspace);
      }
      _persistOperatorUiState();
    });
  }

  void _toggleWorkspaceCollapsed(String workspace) {
    setState(() {
      if (_collapsedWorkspaces.contains(workspace)) {
        _collapsedWorkspaces.remove(workspace);
      } else {
        _collapsedWorkspaces.add(workspace);
      }
      _persistOperatorUiState();
    });
  }

  void _collapseVisibleWorkspaces({
    required List<String> availableWorkspaces,
    required String selectedWorkspace,
  }) {
    setState(() {
      _collapsedWorkspaces.addAll(
        _visibleWorkspaces(
          availableWorkspaces: availableWorkspaces,
          selectedWorkspace: selectedWorkspace,
        ),
      );
      _persistOperatorUiState();
    });
  }

  void _expandVisibleWorkspaces({
    required List<String> availableWorkspaces,
    required String selectedWorkspace,
  }) {
    setState(() {
      _collapsedWorkspaces.removeAll(
        _visibleWorkspaces(
          availableWorkspaces: availableWorkspaces,
          selectedWorkspace: selectedWorkspace,
        ),
      );
      _persistOperatorUiState();
    });
  }

  String _defaultWorkspaceSort(String workspace) {
    switch (workspace) {
      case 'fleet':
        return 'attention';
      case 'dispatches':
        return 'eta';
      case 'cases':
        return 'severity';
      case 'support':
        return 'priority';
      case 'documents':
        return 'blocking';
      case 'payouts':
        return 'pending';
      default:
        return 'default';
    }
  }

  String _workspaceSortValue(String workspace) {
    return _workspaceSorts[workspace] ?? _defaultWorkspaceSort(workspace);
  }

  void _setWorkspaceSort(String workspace, String sort) {
    setState(() {
      _workspaceSorts[workspace] = sort;
      _persistOperatorUiState();
    });
  }

  List<_RideOperatorWorkspaceSortOptionData> _workspaceSortOptions(
    String workspace, {
    required bool isArabic,
  }) {
    switch (workspace) {
      case 'fleet':
        return <_RideOperatorWorkspaceSortOptionData>[
          _RideOperatorWorkspaceSortOptionData(
            id: 'attention',
            label: isArabic ? 'الانتباه' : 'Attention',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'heartbeat',
            label: isArabic ? 'آخر نبضة' : 'Latest heartbeat',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'name',
            label: isArabic ? 'اسم السائق' : 'Driver name',
          ),
        ];
      case 'dispatches':
        return <_RideOperatorWorkspaceSortOptionData>[
          _RideOperatorWorkspaceSortOptionData(
            id: 'eta',
            label: isArabic ? 'ETA' : 'ETA',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'newest',
            label: isArabic ? 'الأحدث' : 'Newest',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'fare',
            label: isArabic ? 'الأكبر قيمة' : 'Highest fare',
          ),
        ];
      case 'cases':
        return <_RideOperatorWorkspaceSortOptionData>[
          _RideOperatorWorkspaceSortOptionData(
            id: 'severity',
            label: isArabic ? 'الخطورة' : 'Severity',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'latest',
            label: isArabic ? 'الأحدث' : 'Latest',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'amount',
            label: isArabic ? 'الأكبر قيمة' : 'Largest amount',
          ),
        ];
      case 'support':
        return <_RideOperatorWorkspaceSortOptionData>[
          _RideOperatorWorkspaceSortOptionData(
            id: 'priority',
            label: isArabic ? 'الأولوية' : 'Priority',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'latest',
            label: isArabic ? 'الأحدث' : 'Latest',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'oldest',
            label: isArabic ? 'الأقدم' : 'Oldest',
          ),
        ];
      case 'documents':
        return <_RideOperatorWorkspaceSortOptionData>[
          _RideOperatorWorkspaceSortOptionData(
            id: 'blocking',
            label: isArabic ? 'الحجب' : 'Blocking',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'expiry',
            label: isArabic ? 'الأقرب انتهاء' : 'Expiry first',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'latest',
            label: isArabic ? 'الأحدث' : 'Latest',
          ),
        ];
      case 'payouts':
        return <_RideOperatorWorkspaceSortOptionData>[
          _RideOperatorWorkspaceSortOptionData(
            id: 'pending',
            label: isArabic ? 'المعلقة أولاً' : 'Pending first',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'oldest',
            label: isArabic ? 'الأقدم' : 'Oldest',
          ),
          _RideOperatorWorkspaceSortOptionData(
            id: 'amount',
            label: isArabic ? 'الأكبر قيمة' : 'Largest amount',
          ),
        ];
      default:
        return const <_RideOperatorWorkspaceSortOptionData>[];
    }
  }

  DateTime? _tryParseIso(String? iso) {
    final normalized = (iso ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized)?.toUtc();
  }

  int _compareDateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return b.compareTo(a);
  }

  int _compareDateAsc(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }

  int _caseSeverityRank(RideOperatorAlertSeverity severity) {
    switch (severity) {
      case RideOperatorAlertSeverity.critical:
        return 4;
      case RideOperatorAlertSeverity.high:
        return 3;
      case RideOperatorAlertSeverity.medium:
        return 2;
      case RideOperatorAlertSeverity.info:
        return 1;
    }
  }

  int _supportPriorityRank(RideSupportTicket ticket) {
    final categoryScore = switch (ticket.category) {
      RideSupportTicketCategory.safety => 4,
      RideSupportTicketCategory.paymentIssue ||
      RideSupportTicketCategory.driverBehavior =>
        3,
      RideSupportTicketCategory.bookingIssue ||
      RideSupportTicketCategory.lostItem =>
        2,
      RideSupportTicketCategory.other => 1,
    };
    return categoryScore + (ticket.isOpen ? 2 : 0);
  }

  int _documentPriorityRank(RideDriverDocument document) {
    switch (document.status) {
      case RideDriverDocumentStatus.expired:
        return 5;
      case RideDriverDocumentStatus.rejected:
        return 4;
      case RideDriverDocumentStatus.pending:
        return 3;
      case RideDriverDocumentStatus.missing:
        return 2;
      case RideDriverDocumentStatus.approved:
        return 1;
    }
  }

  int _payoutPriorityRank(RidePayoutRequest request) {
    switch (request.status) {
      case RidePayoutRequestStatus.pending:
        return 4;
      case RidePayoutRequestStatus.accepted:
        return 3;
      case RidePayoutRequestStatus.expired:
        return 2;
      case RidePayoutRequestStatus.canceled:
        return 1;
    }
  }

  int _fleetAttentionRank(RideOperatorDriverRosterEntry driver) {
    var score = 0;
    if (driver.isOnline && rideOperatorDriverIsStale(driver)) {
      score += 4;
    }
    if (driver.isOnline && driver.location == null) {
      score += 3;
    }
    if (driver.isOnline && driver.activeRideId != null) {
      score += 2;
    } else if (driver.isIdleOnline) {
      score += 1;
    }
    return score;
  }

  String _driverSortLabel(RideOperatorDriverRosterEntry driver) {
    final label = (driver.driverName ?? '').trim();
    if (label.isNotEmpty) {
      return label.toLowerCase();
    }
    return driver.driverAccountId.toLowerCase();
  }

  List<RideOperatorDriverRosterEntry> _sortedDriverRosterEntries(
    List<RideOperatorDriverRosterEntry> drivers, {
    required String sort,
  }) {
    final sorted = drivers.toList(growable: false);
    sorted.sort((a, b) {
      switch (sort) {
        case 'name':
          final nameCompare =
              _driverSortLabel(a).compareTo(_driverSortLabel(b));
          if (nameCompare != 0) {
            return nameCompare;
          }
          return _compareDateDesc(
            _tryParseIso(a.lastSeenAtIso),
            _tryParseIso(b.lastSeenAtIso),
          );
        case 'heartbeat':
          return _compareDateDesc(
            _tryParseIso(a.lastSeenAtIso),
            _tryParseIso(b.lastSeenAtIso),
          );
        case 'attention':
        default:
          final attentionCompare =
              _fleetAttentionRank(b).compareTo(_fleetAttentionRank(a));
          if (attentionCompare != 0) {
            return attentionCompare;
          }
          return _compareDateDesc(
            _tryParseIso(a.lastSeenAtIso),
            _tryParseIso(b.lastSeenAtIso),
          );
      }
    });
    return sorted;
  }

  List<RideTrip> _sortedTrips(
    List<RideTrip> trips, {
    required String sort,
  }) {
    final sorted = trips.toList(growable: false);
    sorted.sort((a, b) {
      switch (sort) {
        case 'newest':
          return _compareDateDesc(
            _tryParseIso(a.lastUpdatedAtIso),
            _tryParseIso(b.lastUpdatedAtIso),
          );
        case 'fare':
          final fareCompare =
              b.fareEstimateCents.compareTo(a.fareEstimateCents);
          if (fareCompare != 0) {
            return fareCompare;
          }
          return _compareDateDesc(
            _tryParseIso(a.lastUpdatedAtIso),
            _tryParseIso(b.lastUpdatedAtIso),
          );
        case 'eta':
        default:
          final etaCompare = a.etaMinutes.compareTo(b.etaMinutes);
          if (etaCompare != 0) {
            return etaCompare;
          }
          return _compareDateDesc(
            _tryParseIso(a.lastUpdatedAtIso),
            _tryParseIso(b.lastUpdatedAtIso),
          );
      }
    });
    return sorted;
  }

  List<RideOperatorCaseItem> _sortedCaseItems(
    List<RideOperatorCaseItem> items, {
    required String sort,
  }) {
    final sorted = items.toList(growable: false);
    sorted.sort((a, b) {
      switch (sort) {
        case 'latest':
          return _compareDateDesc(
            _tryParseIso(a.lastUpdatedAtIso),
            _tryParseIso(b.lastUpdatedAtIso),
          );
        case 'amount':
          final amountCompare =
              b.fareEstimateMinorUnits.compareTo(a.fareEstimateMinorUnits);
          if (amountCompare != 0) {
            return amountCompare;
          }
          return b.ageSeconds.compareTo(a.ageSeconds);
        case 'severity':
        default:
          final severityCompare = _caseSeverityRank(b.severity)
              .compareTo(_caseSeverityRank(a.severity));
          if (severityCompare != 0) {
            return severityCompare;
          }
          return b.ageSeconds.compareTo(a.ageSeconds);
      }
    });
    return sorted;
  }

  List<RideSupportTicket> _sortedSupportTickets(
    List<RideSupportTicket> tickets, {
    required String sort,
  }) {
    final sorted = tickets.toList(growable: false);
    sorted.sort((a, b) {
      switch (sort) {
        case 'latest':
          return _compareDateDesc(
            _tryParseIso(a.updatedAtIso),
            _tryParseIso(b.updatedAtIso),
          );
        case 'oldest':
          return _compareDateAsc(
            _tryParseIso(a.createdAtIso),
            _tryParseIso(b.createdAtIso),
          );
        case 'priority':
        default:
          final priorityCompare =
              _supportPriorityRank(b).compareTo(_supportPriorityRank(a));
          if (priorityCompare != 0) {
            return priorityCompare;
          }
          return _compareDateDesc(
            _tryParseIso(a.updatedAtIso),
            _tryParseIso(b.updatedAtIso),
          );
      }
    });
    return sorted;
  }

  List<RideDriverDocument> _sortedDocuments(
    List<RideDriverDocument> documents, {
    required String sort,
  }) {
    final sorted = documents.toList(growable: false);
    sorted.sort((a, b) {
      switch (sort) {
        case 'expiry':
          final expiryCompare = _compareDateAsc(
            _tryParseIso(a.expiresAtIso),
            _tryParseIso(b.expiresAtIso),
          );
          if (expiryCompare != 0) {
            return expiryCompare;
          }
          return _documentPriorityRank(b).compareTo(_documentPriorityRank(a));
        case 'latest':
          return _compareDateDesc(
            _tryParseIso(a.submittedAtIso ?? a.reviewedAtIso),
            _tryParseIso(b.submittedAtIso ?? b.reviewedAtIso),
          );
        case 'blocking':
        default:
          final blockingCompare =
              _documentPriorityRank(b).compareTo(_documentPriorityRank(a));
          if (blockingCompare != 0) {
            return blockingCompare;
          }
          return _compareDateAsc(
            _tryParseIso(a.expiresAtIso),
            _tryParseIso(b.expiresAtIso),
          );
      }
    });
    return sorted;
  }

  List<RidePayoutRequest> _sortedPayoutRequests(
    List<RidePayoutRequest> requests, {
    required String sort,
  }) {
    final sorted = requests.toList(growable: false);
    sorted.sort((a, b) {
      switch (sort) {
        case 'oldest':
          return b.ageSeconds.compareTo(a.ageSeconds);
        case 'amount':
          return b.amountMinorUnits.compareTo(a.amountMinorUnits);
        case 'pending':
        default:
          final priorityCompare =
              _payoutPriorityRank(b).compareTo(_payoutPriorityRank(a));
          if (priorityCompare != 0) {
            return priorityCompare;
          }
          return b.ageSeconds.compareTo(a.ageSeconds);
      }
    });
    return sorted;
  }

  Future<void> _scrollToSection(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.06,
    );
  }

  int _workspaceCount({
    required String workspace,
    required RideOperatorLiveBoard? board,
    required RideOperatorDriverRoster? driverRoster,
    required RideOperatorCaseQueue? caseQueue,
    required RideOperatorSupportQueue? supportQueue,
    required RideOperatorDocumentQueue? documentQueue,
    required RideOperatorFinanceQueue? financeQueue,
  }) {
    switch (workspace) {
      case 'dispatches':
        return (board?.counts.openDispatches ?? 0) +
            (board?.counts.activeTrips ?? 0);
      case 'fleet':
        return driverRoster?.drivers.length ?? 0;
      case 'cases':
        return caseQueue?.totals.openCases ?? 0;
      case 'support':
        return supportQueue?.totals.openTickets ?? 0;
      case 'documents':
        return (documentQueue?.totals.pendingDocuments ?? 0) +
            (documentQueue?.totals.blockedDrivers ?? 0);
      case 'payouts':
        return financeQueue?.totals.pendingRequests ?? 0;
      case 'signups':
        // Cycle 102 — surface the pending-signup count on the
        // Workspace-focus chip so admins know at a glance how many
        // applicants are waiting on review.
        return _signupQueue?.length ?? 0;
      default:
        return 0;
    }
  }

  Future<void> _bootstrapConsole() async {
    _privileges = await _refreshPrivileges();
    await _refreshAll(showNotifications: false);
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    _startPolling();
    if (_opsAllowed) {
      _startUpdatesStream();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshAll(showNotifications: true));
    });
  }

  void _startUpdatesStream() {
    if (!_opsAllowed) {
      return;
    }
    _updatesRetryTimer?.cancel();
    _updatesSub?.cancel();
    _updatesSub = _mobilityApi.operatorUpdateStream().listen(
          (_) => unawaited(_refreshAll(showNotifications: true)),
          onDone: _scheduleUpdatesRetry,
          onError: (_, __) => _scheduleUpdatesRetry(),
          cancelOnError: true,
        );
  }

  void _scheduleUpdatesRetry() {
    if (!mounted || !_opsAllowed) {
      return;
    }
    _updatesRetryTimer?.cancel();
    _updatesRetryTimer = Timer(
      const Duration(seconds: 3),
      _startUpdatesStream,
    );
  }

  Future<void> _refreshAll({required bool showNotifications}) async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final bootstrapFuture = _bootstrap == null
          ? _mobilityApi.bootstrapConfig()
          : Future<RidePlatformBootstrap?>.value(_bootstrap);
      final boardFuture = _opsAllowed
          ? _mobilityApi.operatorLiveBoard(openLimit: 12, activeLimit: 12)
          : Future<RideOperatorLiveBoard?>.value(null);
      final driverRosterFuture = _opsAllowed
          ? _mobilityApi.operatorDriverRoster(limit: 18)
          : Future<RideOperatorDriverRoster?>.value(null);
      final caseQueueFuture = _opsAllowed
          ? _mobilityApi.operatorCaseQueue(limit: 16)
          : Future<RideOperatorCaseQueue?>.value(null);
      final supportQueueFuture = _supportAllowed
          ? _mobilityApi.operatorSupportQueue(limit: 16)
          : Future<RideOperatorSupportQueue?>.value(null);
      final documentQueueFuture = _complianceAllowed
          ? _mobilityApi.operatorDocumentQueue(limit: 16)
          : Future<RideOperatorDocumentQueue?>.value(null);
      final pricingPoliciesFuture = _pricingAllowed
          ? _mobilityApi.operatorPricingPolicy()
          : Future<RideOperatorPricingPolicyDashboard?>.value(null);
      final financeQueueFuture = _financeAllowed
          ? _mobilityApi.operatorFinanceQueue(limit: 16)
          : Future<RideOperatorFinanceQueue?>.value(null);
      final results = await Future.wait<Object?>([
        bootstrapFuture,
        boardFuture,
        driverRosterFuture,
        caseQueueFuture,
        supportQueueFuture,
        documentQueueFuture,
        pricingPoliciesFuture,
        financeQueueFuture,
      ]);
      final nextBootstrap = results[0] as RidePlatformBootstrap?;
      final nextBoard = results[1] as RideOperatorLiveBoard?;
      final nextDriverRoster = results[2] as RideOperatorDriverRoster?;
      final nextCaseQueue = results[3] as RideOperatorCaseQueue?;
      final nextSupportQueue = results[4] as RideOperatorSupportQueue?;
      final nextDocumentQueue = results[5] as RideOperatorDocumentQueue?;
      final nextPricingPolicies =
          results[6] as RideOperatorPricingPolicyDashboard?;
      final nextFinanceQueue = results[7] as RideOperatorFinanceQueue?;
      final nextWarnings = <String>[
        if (_opsAllowed && nextBoard == null) 'live_board_unavailable',
        if (_opsAllowed && nextDriverRoster == null) 'fleet_live_unavailable',
        if (_opsAllowed && nextCaseQueue == null) 'case_queue_unavailable',
        if (_supportAllowed && nextSupportQueue == null)
          'support_queue_unavailable',
        if (_complianceAllowed && nextDocumentQueue == null)
          'document_queue_unavailable',
        if (_financeAllowed && nextFinanceQueue == null)
          'finance_queue_unavailable',
        if (_pricingAllowed && nextPricingPolicies == null)
          'pricing_unavailable',
      ];
      final effectiveBoard = nextBoard ?? _board;
      final focusTrip = effectiveBoard?.activeTrips.isNotEmpty == true
          ? effectiveBoard!.activeTrips.first
          : effectiveBoard?.openDispatches.isNotEmpty == true
              ? effectiveBoard!.openDispatches.first
              : null;
      final nextFocusQuote = focusTrip == null
          ? (nextBoard == null ? _focusQuote : null)
          : await _mobilityApi.quoteByText(
              pickupQuery: focusTrip.pickup,
              destinationQuery: focusTrip.destination,
            );
      final nextFocusTracking = focusTrip == null
          ? (nextBoard == null ? _focusTracking : null)
          : await _mobilityApi.trackingSnapshot(focusTrip.rideId);
      // Cycle 101 — try to load the role-signup admin queue. The
      // BFF returns 403 when the principal lacks
      // `access.assignment.write`; the helper swallows that and
      // returns null, so the Signups workspace simply stays hidden
      // for non-admin operators.
      final nextSignupQueue = _opsAllowed
          ? await RoleSignupApi(baseUrl: widget.baseUrl ?? '').adminList()
          : _signupQueue;
      if (!mounted) {
        return;
      }
      if (showNotifications && nextBoard != null) {
        _emitCountNotifications(nextBoard);
      }
      if (showNotifications) {
        _emitFocusTripNotifications(focusTrip);
      }
      if (showNotifications && nextCaseQueue != null) {
        _emitCaseNotifications(nextCaseQueue);
      }
      if (showNotifications && nextSupportQueue != null) {
        _emitSupportQueueNotifications(nextSupportQueue);
      }
      if (showNotifications && nextDocumentQueue != null) {
        _emitDocumentQueueNotifications(nextDocumentQueue);
      }
      if (showNotifications && nextFinanceQueue != null) {
        _emitFinanceQueueNotifications(nextFinanceQueue);
      }
      // Cycle 154 — fetch safety alerts in the same refresh so the
      // banner updates without a separate timer. Best-effort: empty
      // list on failure keeps the banner hidden instead of stale.
      final nextSafetyAlerts = _opsAllowed && (widget.baseUrl?.isNotEmpty ?? false)
          ? await SafetyAlertsApi(baseUrl: widget.baseUrl!).operatorQueue()
          : _safetyAlerts;
      // Notification fires on the rising edge — count of `active`
      // (not yet acknowledged) alerts going up means a brand-new
      // SOS landed and dispatch should look at the banner now.
      final nextActiveCount = nextSafetyAlerts.where((a) => a.isActive).length;
      if (showNotifications &&
          nextActiveCount > _lastNotifiedActiveSafetyAlertCount) {
        if (mounted) {
          final l = L10n.of(context);
          final body = l.isArabic
              ? 'تم استلام إنذار طوارئ جديد. تحقّق من اللوحة.'
              : 'A new emergency SOS just arrived. Check the banner.';
          unawaited(NotificationService.showOperatorAlert(
            title: l.isArabic ? 'إنذار طوارئ جديد' : 'New SOS alert',
            body: body,
          ));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFD32F2F),
              content: Row(
                children: <Widget>[
                  const Icon(Icons.shield_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      body,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
      _lastNotifiedActiveSafetyAlertCount = nextActiveCount;
      setState(() {
        _bootstrap = nextBootstrap ?? _bootstrap;
        _board = nextBoard ?? _board;
        _driverRoster = nextDriverRoster ?? _driverRoster;
        _caseQueue = nextCaseQueue ?? _caseQueue;
        _supportQueue = nextSupportQueue ?? _supportQueue;
        _documentQueue = nextDocumentQueue ?? _documentQueue;
        _pricingPolicies = nextPricingPolicies ?? _pricingPolicies;
        _financeQueue = nextFinanceQueue ?? _financeQueue;
        _focusTrip = focusTrip;
        _focusQuote = nextFocusQuote;
        _focusTracking = nextFocusTracking;
        _opsDataWarnings = nextWarnings;
        _signupQueue = nextSignupQueue;
        _safetyAlerts = nextSafetyAlerts;
        // Cycle 88 — stamp the successful refresh so the AppBar chip
        // can render an accurate "Last updated" age. Only update on
        // the success path so a failed poll doesn't make stale data
        // look fresh.
        _lastRefreshedAt = DateTime.now();
      });
    } finally {
      _refreshing = false;
    }
  }

  void _emitCaseNotifications(RideOperatorCaseQueue queue) {
    final nextCriticalCases = queue.totals.criticalCases;
    final previousCriticalCases = _lastCriticalCases;
    _lastCriticalCases = nextCriticalCases;
    if (!mounted) {
      return;
    }
    if (previousCriticalCases != null &&
        nextCriticalCases > previousCriticalCases) {
      final delta = nextCriticalCases - previousCriticalCases;
      final l = L10n.of(context);
      final body = l.isArabic
          ? 'ظهرت $delta حالات حرجة جديدة في قائمة التشغيل.'
          : '$delta new critical ride cases entered the queue.';
      unawaited(NotificationService.showOperatorAlert(
        title: l.isArabic ? 'حالات حرجة جديدة' : 'New critical ride cases',
        body: body,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body),
        ),
      );
    }
  }

  void _emitSupportQueueNotifications(RideOperatorSupportQueue queue) {
    final nextOpenTickets = queue.totals.openTickets;
    final previousOpenTickets = _lastOpenSupportTickets;
    _lastOpenSupportTickets = nextOpenTickets;
    if (!mounted) {
      return;
    }
    if (previousOpenTickets != null && nextOpenTickets > previousOpenTickets) {
      final delta = nextOpenTickets - previousOpenTickets;
      final l = L10n.of(context);
      final body = l.isArabic
          ? 'دخلت $delta تذاكر دعم جديدة إلى الطابور.'
          : '$delta new ride support tickets entered the queue.';
      unawaited(NotificationService.showOperatorAlert(
        title: l.isArabic ? 'تذاكر دعم جديدة' : 'New support tickets',
        body: body,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body),
        ),
      );
    }
  }

  void _emitFinanceQueueNotifications(RideOperatorFinanceQueue queue) {
    final nextPending = queue.totals.pendingRequests;
    final previousPending = _lastPendingPayoutRequests;
    _lastPendingPayoutRequests = nextPending;
    if (!mounted) {
      return;
    }
    if (previousPending != null && nextPending > previousPending) {
      final delta = nextPending - previousPending;
      final l = L10n.of(context);
      final body = l.isArabic
          ? 'دخلت $delta طلبات سحب جديدة إلى طابور المالية.'
          : '$delta new payout requests entered the finance queue.';
      unawaited(NotificationService.showOperatorAlert(
        title: l.isArabic ? 'طلبات سحب جديدة' : 'New payout requests',
        body: body,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body),
        ),
      );
    }
  }

  void _emitDocumentQueueNotifications(RideOperatorDocumentQueue queue) {
    final nextPending = queue.totals.pendingDocuments;
    final previousPending = _lastPendingDocuments;
    _lastPendingDocuments = nextPending;
    if (!mounted) {
      return;
    }
    if (previousPending != null && nextPending > previousPending) {
      final delta = nextPending - previousPending;
      final l = L10n.of(context);
      final body = l.isArabic
          ? 'دخلت $delta وثائق جديدة إلى طابور الامتثال.'
          : '$delta new driver documents entered the compliance queue.';
      unawaited(NotificationService.showOperatorAlert(
        title: l.isArabic ? 'وثائق جديدة' : 'New compliance documents',
        body: body,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body),
        ),
      );
    }
  }

  void _emitCountNotifications(RideOperatorLiveBoard board) {
    final nextOpenDispatches = board.counts.openDispatches;
    final nextActiveTrips = board.counts.activeTrips;
    final previousOpenDispatches = _lastOpenDispatches;
    final previousActiveTrips = _lastActiveTrips;
    _lastOpenDispatches = nextOpenDispatches;
    _lastActiveTrips = nextActiveTrips;
    if (!mounted) {
      return;
    }
    final l = L10n.of(context);
    if (previousOpenDispatches != null &&
        nextOpenDispatches > previousOpenDispatches) {
      final delta = nextOpenDispatches - previousOpenDispatches;
      final rideId = board.openDispatches.isNotEmpty
          ? board.openDispatches.first.rideId
          : null;
      final body = l.isArabic
          ? 'دخلت $delta طلبات جديدة إلى لوحة التشغيل.'
          : '$delta new ride requests entered the live board.';
      unawaited(NotificationService.showOperatorAlert(
        title: l.isArabic ? 'طلبات جديدة' : 'New ride requests',
        body: body,
        rideId: rideId,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body),
        ),
      );
    } else if (previousActiveTrips != null &&
        nextActiveTrips > previousActiveTrips) {
      final delta = nextActiveTrips - previousActiveTrips;
      final rideId =
          board.activeTrips.isNotEmpty ? board.activeTrips.first.rideId : null;
      final body = l.isArabic
          ? 'ارتفع عدد الرحلات النشطة بمقدار $delta.'
          : 'Active rides increased by $delta.';
      unawaited(NotificationService.showOperatorAlert(
        title: l.isArabic ? 'رحلات نشطة جديدة' : 'Active rides increased',
        body: body,
        rideId: rideId,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body),
        ),
      );
    }
  }

  void _emitFocusTripNotifications(RideTrip? trip) {
    final previousTrip = _lastNotifiedFocusTrip;
    _lastNotifiedFocusTrip = trip;
    if (!mounted ||
        !rideOperatorShouldNotifyFocusTripTransition(
          previousTrip: previousTrip,
          nextTrip: trip,
        )) {
      return;
    }
    final nextTrip = trip!;
    final l = L10n.of(context);
    final statusLabel = _statusLabel(nextTrip.status, isArabic: l.isArabic);
    final body = rideOperatorPrivacySafeTripTransitionBody(
      nextTrip: nextTrip,
      isArabic: l.isArabic,
      statusLabel: statusLabel,
    );
    unawaited(NotificationService.showOperatorAlert(
      title: l.isArabic ? 'تحديث الرحلة' : 'Trip update',
      body: body,
      rideId: nextTrip.rideId,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(body),
      ),
    );
  }

  Future<void> _contactSupportByMail() async {
    final uri = shamellSupportEmailUri(subject: 'Ride operator support');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _contactSupportByPhone() async {
    await launchUrl(shamellSupportPhoneUri(),
        mode: LaunchMode.externalApplication);
  }

  String _supportCategoryLabel(
    RideSupportTicketCategory category, {
    required bool isArabic,
  }) {
    switch (category) {
      case RideSupportTicketCategory.bookingIssue:
        return isArabic ? 'مشكلة حجز' : 'Booking issue';
      case RideSupportTicketCategory.driverBehavior:
        return isArabic ? 'سلوك السائق' : 'Driver behavior';
      case RideSupportTicketCategory.safety:
        return isArabic ? 'سلامة' : 'Safety';
      case RideSupportTicketCategory.paymentIssue:
        return isArabic ? 'مشكلة دفع' : 'Payment issue';
      case RideSupportTicketCategory.lostItem:
        return isArabic ? 'غرض مفقود' : 'Lost item';
      case RideSupportTicketCategory.other:
        return isArabic ? 'أخرى' : 'Other';
    }
  }

  String _supportStatusLabel(
    RideSupportTicketStatus status, {
    required bool isArabic,
  }) {
    switch (status) {
      case RideSupportTicketStatus.open:
        return isArabic ? 'مفتوح' : 'Open';
      case RideSupportTicketStatus.resolved:
        return isArabic ? 'تم الحل' : 'Resolved';
    }
  }

  Future<void> _resolveSupportTicket(RideSupportTicket ticket) async {
    if (!_opsAllowed || !ticket.isOpen) {
      return;
    }
    final noteCtrl = TextEditingController(
      text: 'Customer updated and issue resolved.',
    );
    final String? note;
    try {
      note = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Resolve support ticket'),
          content: TextField(
            controller: noteCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Resolution note',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(noteCtrl.text.trim()),
              child: const Text('Resolve'),
            ),
          ],
        ),
      );
    } finally {
      noteCtrl.dispose();
    }
    if (note == null || note.isEmpty) {
      return;
    }
    final updated = await _mobilityApi.resolveOperatorSupportTicket(
      ticketId: ticket.ticketId,
      note: note,
    );
    if (!mounted) {
      return;
    }
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not resolve support ticket.')),
      );
      return;
    }
    await _refreshAll(showNotifications: false);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Support ticket resolved: ${updated.ticketId}'),
      ),
    );
  }

  Future<void> _approvePayoutRequest(RidePayoutRequest request) async {
    if (!_financeSensitiveAllowed) {
      return;
    }
    final approvedReveal = await _requireSensitiveReveal(
      reason: 'Authenticate to approve sensitive operator payout actions.',
    );
    if (!approvedReveal) {
      return;
    }
    final requestId = (request.requestId ?? '').trim();
    final feeWalletId = (_financeQueue?.feeWalletId ?? '').trim();
    if (requestId.isEmpty || feeWalletId.isEmpty) {
      return;
    }
    final approved = await _mobilityApi.approveOperatorPayoutRequest(
      requestId: requestId,
      feeWalletId: feeWalletId,
    );
    if (!mounted) {
      return;
    }
    if (approved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not approve payout request.')),
      );
      return;
    }
    await _refreshAll(showNotifications: false);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Payout approved: ${fmtCents(approved.amountMinorUnits)} ${approved.currency}',
        ),
      ),
    );
  }

  String _documentTypeLabel(
    RideDriverDocumentType type, {
    required bool isArabic,
  }) {
    switch (type) {
      case RideDriverDocumentType.driverLicense:
        return isArabic ? 'رخصة القيادة' : 'Driver license';
      case RideDriverDocumentType.vehicleRegistration:
        return isArabic ? 'رخصة المركبة' : 'Vehicle registration';
      case RideDriverDocumentType.insurance:
        return isArabic ? 'التأمين' : 'Insurance';
      case RideDriverDocumentType.identityCard:
        return isArabic ? 'الهوية' : 'Identity card';
    }
  }

  String _documentStatusLabel(
    RideDriverDocumentStatus status, {
    required bool isArabic,
  }) {
    switch (status) {
      case RideDriverDocumentStatus.missing:
        return isArabic ? 'مفقود' : 'Missing';
      case RideDriverDocumentStatus.pending:
        return isArabic ? 'قيد المراجعة' : 'Pending review';
      case RideDriverDocumentStatus.approved:
        return isArabic ? 'معتمد' : 'Approved';
      case RideDriverDocumentStatus.rejected:
        return isArabic ? 'مرفوض' : 'Rejected';
      case RideDriverDocumentStatus.expired:
        return isArabic ? 'منتهي' : 'Expired';
    }
  }

  Future<void> _reviewDocument(
    RideDriverDocument document,
    String decision,
  ) async {
    if (!_complianceSensitiveAllowed) {
      return;
    }
    final approvedReveal = await _requireSensitiveReveal(
      reason: 'Authenticate to review sensitive driver compliance documents.',
    );
    if (!approvedReveal) {
      return;
    }
    final documentId = (document.documentId ?? '').trim();
    if (documentId.isEmpty) {
      return;
    }
    final noteCtrl = TextEditingController(
      text: decision == 'reject' ? 'Please resubmit with a clearer copy.' : '',
    );
    final String? note;
    try {
      note = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
              decision == 'approve' ? 'Approve document' : 'Reject document'),
          content: TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Review note',
            ),
            minLines: 2,
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(noteCtrl.text.trim()),
              child: Text(decision == 'approve' ? 'Approve' : 'Reject'),
            ),
          ],
        ),
      );
    } finally {
      noteCtrl.dispose();
    }
    if (note == null) {
      return;
    }
    final updated = await _mobilityApi.reviewOperatorDocument(
      documentId: documentId,
      decision: decision,
      note: note,
    );
    if (!mounted) {
      return;
    }
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update document review.')),
      );
      return;
    }
    await _refreshAll(showNotifications: false);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Document ${decision == 'approve' ? 'approved' : 'rejected'}: ${_documentTypeLabel(updated.documentType, isArabic: false)}',
        ),
      ),
    );
  }

  Future<void> _editPricingPolicy(RidePricingPolicy policy) async {
    if (!_pricingAllowed) {
      return;
    }
    final baseFareCtrl =
        TextEditingController(text: policy.baseFareMinorUnits.toString());
    final perKmCtrl =
        TextEditingController(text: policy.perKmMinorUnits.toString());
    final perMinuteCtrl =
        TextEditingController(text: policy.perMinuteMinorUnits.toString());
    final trafficDelayCtrl = TextEditingController(
      text: policy.trafficDelayPerMinuteMinorUnits.toString(),
    );
    final bookingFeeCtrl =
        TextEditingController(text: policy.bookingFeeMinorUnits.toString());
    final minimumFareCtrl =
        TextEditingController(text: policy.minimumFareMinorUnits.toString());
    final driverShareCtrl =
        TextEditingController(text: policy.driverShareBps.toString());
    final pricingControllers = <TextEditingController>[
      baseFareCtrl,
      perKmCtrl,
      perMinuteCtrl,
      trafficDelayCtrl,
      bookingFeeCtrl,
      minimumFareCtrl,
      driverShareCtrl,
    ];
    final RidePricingPolicy? updated;
    try {
      updated = await showDialog<RidePricingPolicy>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            'Pricing: ${_rideClassLabel(policy.rideClass, isArabic: false)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseFareCtrl,
                decoration: const InputDecoration(labelText: 'Base fare'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: perKmCtrl,
                decoration: const InputDecoration(labelText: 'Per km'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: perMinuteCtrl,
                decoration: const InputDecoration(labelText: 'Per minute'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: trafficDelayCtrl,
                decoration: const InputDecoration(labelText: 'Traffic / min'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bookingFeeCtrl,
                decoration: const InputDecoration(labelText: 'Booking fee'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: minimumFareCtrl,
                decoration: const InputDecoration(labelText: 'Minimum fare'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: driverShareCtrl,
                decoration:
                    const InputDecoration(labelText: 'Driver share (bps)'),
                keyboardType: TextInputType.number,
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
            onPressed: () async {
              final parsed = await _mobilityApi.upsertOperatorPricingPolicy(
                rideClass: policy.rideClass,
                baseFareMinorUnits:
                    int.tryParse(baseFareCtrl.text.trim()) ?? -1,
                perKmMinorUnits: int.tryParse(perKmCtrl.text.trim()) ?? -1,
                perMinuteMinorUnits:
                    int.tryParse(perMinuteCtrl.text.trim()) ?? -1,
                trafficDelayPerMinuteMinorUnits:
                    int.tryParse(trafficDelayCtrl.text.trim()) ?? -1,
                bookingFeeMinorUnits:
                    int.tryParse(bookingFeeCtrl.text.trim()) ?? -1,
                minimumFareMinorUnits:
                    int.tryParse(minimumFareCtrl.text.trim()) ?? -1,
                driverShareBps: int.tryParse(driverShareCtrl.text.trim()) ?? -1,
              );
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pop(parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      );
    } finally {
      for (final ctrl in pricingControllers) {
        ctrl.dispose();
      }
    }
    if (!mounted || updated == null) {
      return;
    }
    await _refreshAll(showNotifications: false);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pricing updated for ${_rideClassLabel(updated.rideClass, isArabic: false)}.',
        ),
      ),
    );
  }

  String _statusLabel(RideTripStatus status, {required bool isArabic}) {
    switch (status) {
      case RideTripStatus.rideRequested:
        return isArabic ? 'طلب جديد' : 'New request';
      case RideTripStatus.matching:
        return isArabic ? 'قيد الإسناد' : 'Matching';
      case RideTripStatus.driverAssigned:
        return isArabic ? 'مُسندة' : 'Assigned';
      case RideTripStatus.driverArriving:
        return isArabic ? 'السائق قادم' : 'Driver arriving';
      case RideTripStatus.driverArrived:
        return isArabic ? 'عند الالتقاط' : 'At pickup';
      case RideTripStatus.tripStarted:
        return isArabic ? 'بدأت' : 'Started';
      case RideTripStatus.tripInProgress:
        return isArabic ? 'جارية' : 'In progress';
      case RideTripStatus.tripCompleted:
        return isArabic ? 'مكتملة' : 'Completed';
      case RideTripStatus.canceled:
        return isArabic ? 'ملغاة' : 'Canceled';
      case RideTripStatus.paymentFailed:
        return isArabic ? 'دفع فاشل' : 'Payment failed';
      case RideTripStatus.idle:
      case RideTripStatus.quoteShown:
        return isArabic ? 'خامل' : 'Idle';
    }
  }

  Widget _buildCommandDeskSection(
    BuildContext context, {
    required RideOperatorLiveBoard? board,
    required RideOperatorSummary? summary,
    required RideOperatorCaseQueue? caseQueue,
    required RideOperatorSupportQueue? supportQueue,
    required RideOperatorDocumentQueue? documentQueue,
    required RideOperatorFinanceQueue? financeQueue,
    required int staleDriverCount,
    required int noGpsDriverCount,
    required bool isArabic,
  }) {
    final theme = Theme.of(context);
    final attentionItems = <_RideOperatorAttentionItemData>[
      if (summary != null && summary.capacityGapDispatches > 0)
        _RideOperatorAttentionItemData(
          icon: Icons.local_shipping_outlined,
          title: isArabic ? 'فجوة سعة في الإسناد' : 'Dispatch capacity gap',
          detail: isArabic
              ? '${summary.capacityGapDispatches} طلبات مفتوحة تنتظر سائقين متاحين.'
              : '${summary.capacityGapDispatches} open dispatches are waiting for available supply.',
          severity: _RideOperatorAttentionSeverity.urgent,
          targetWorkspace: 'dispatches',
          targetSectionKey: _dispatchesSectionKey,
        ),
      if (summary != null &&
          (summary.stalledDispatches > 0 ||
              summary.overdueArrivals > 0 ||
              summary.longRunningTrips > 0))
        _RideOperatorAttentionItemData(
          icon: Icons.route_outlined,
          title: isArabic ? 'رحلات تتجاوز التوقيت' : 'Trips slipping SLA',
          detail: isArabic
              ? '${summary.stalledDispatches} طلبات متأخرة • ${summary.overdueArrivals} وصولات متأخرة • ${summary.longRunningTrips} رحلات طويلة.'
              : '${summary.stalledDispatches} stalled dispatches • ${summary.overdueArrivals} overdue arrivals • ${summary.longRunningTrips} long-running trips.',
          severity: _RideOperatorAttentionSeverity.urgent,
          targetWorkspace: 'dispatches',
          targetSectionKey: _dispatchesSectionKey,
        ),
      if (caseQueue != null && caseQueue.totals.criticalCases > 0)
        _RideOperatorAttentionItemData(
          icon: Icons.crisis_alert_outlined,
          title: isArabic ? 'قضايا حرجة مفتوحة' : 'Critical case queue',
          detail: isArabic
              ? '${caseQueue.totals.criticalCases} قضايا حرجة و${caseQueue.totals.openCases} إجمالي القضايا المفتوحة.'
              : '${caseQueue.totals.criticalCases} critical cases across ${caseQueue.totals.openCases} open ops cases.',
          severity: _RideOperatorAttentionSeverity.urgent,
          targetWorkspace: 'cases',
          targetSectionKey: _caseQueueSectionKey,
        ),
      if (supportQueue != null && supportQueue.totals.urgentTickets > 0)
        _RideOperatorAttentionItemData(
          icon: Icons.support_agent_outlined,
          title: isArabic ? 'تذاكر عملاء عاجلة' : 'Urgent customer tickets',
          detail: isArabic
              ? '${supportQueue.totals.urgentTickets} تذاكر عاجلة ما زالت مفتوحة في الدعم.'
              : '${supportQueue.totals.urgentTickets} urgent tickets are still open in support.',
          severity: _RideOperatorAttentionSeverity.urgent,
          targetWorkspace: 'support',
          targetSectionKey: _supportQueueSectionKey,
        ),
      if (documentQueue != null &&
          (documentQueue.totals.blockedDrivers > 0 ||
              documentQueue.totals.pendingDocuments > 0))
        _RideOperatorAttentionItemData(
          icon: Icons.badge_outlined,
          title:
              isArabic ? 'عوائق امتثال للسائقين' : 'Driver compliance blockers',
          detail: isArabic
              ? '${documentQueue.totals.blockedDrivers} سائقين محجوبين و${documentQueue.totals.pendingDocuments} وثائق بانتظار المراجعة.'
              : '${documentQueue.totals.blockedDrivers} blocked drivers and ${documentQueue.totals.pendingDocuments} documents waiting review.',
          severity: _RideOperatorAttentionSeverity.warning,
          targetWorkspace: 'documents',
          targetSectionKey: _documentQueueSectionKey,
        ),
      if (financeQueue != null && financeQueue.totals.pendingRequests > 0)
        _RideOperatorAttentionItemData(
          icon: Icons.account_balance_wallet_outlined,
          title: isArabic ? 'موافقات سحب معلقة' : 'Payout approvals waiting',
          detail: isArabic
              ? '${financeQueue.totals.pendingRequests} طلبات سحب بانتظار قرار، والأقدم منذ ${_formatAgeSeconds(financeQueue.totals.oldestPendingAgeSeconds, isArabic: true)}.'
              : '${financeQueue.totals.pendingRequests} payout requests are pending, with the oldest waiting ${_formatAgeSeconds(financeQueue.totals.oldestPendingAgeSeconds, isArabic: false)}.',
          severity: _RideOperatorAttentionSeverity.warning,
          targetWorkspace: 'payouts',
          targetSectionKey: _financeQueueSectionKey,
        ),
      if (board != null && board.counts.paymentFailures > 0)
        _RideOperatorAttentionItemData(
          icon: Icons.payments_outlined,
          title: isArabic ? 'حالات دفع فاشلة' : 'Payment failures live',
          detail: isArabic
              ? '${board.counts.paymentFailures} رحلات أو دفعات تحتاج متابعة مالية أو دعم عملاء.'
              : '${board.counts.paymentFailures} rides need payment follow-up across finance or support.',
          severity: _RideOperatorAttentionSeverity.urgent,
          targetWorkspace: 'cases',
          targetSectionKey: _caseQueueSectionKey,
        ),
      if (staleDriverCount > 0 || noGpsDriverCount > 0)
        _RideOperatorAttentionItemData(
          icon: Icons.gps_off_outlined,
          title:
              isArabic ? 'فجوات رؤية في الأسطول' : 'Live fleet visibility gaps',
          detail: isArabic
              ? '$staleDriverCount سائقين بنبضات قديمة و$noGpsDriverCount بدون GPS في العرض الحي.'
              : '$staleDriverCount stale drivers and $noGpsDriverCount without GPS in the live fleet.',
          severity: _RideOperatorAttentionSeverity.warning,
          targetWorkspace: 'fleet',
          targetSectionKey: _fleetSectionKey,
        ),
      // Cycle 103 — pending role-signup applications. Surfaces the
      // queue on the command desk so admins see the workload even
      // without selecting the Signups workspace tab. Severity is
      // `info` because no rider / driver is blocked while waiting,
      // and a tap jumps straight to the review surface.
      if ((_signupQueue ?? const <RoleSignupRequest>[]).isNotEmpty)
        _RideOperatorAttentionItemData(
          icon: Icons.person_add_alt_1_rounded,
          title: isArabic
              ? 'طلبات تسجيل بانتظار المراجعة'
              : 'Signup requests pending review',
          detail: isArabic
              ? '${_signupQueue!.length} طلب تسجيل (سائق / مشغّل) ينتظر الموافقة.'
              : '${_signupQueue!.length} driver / operator signup ${_signupQueue!.length == 1 ? "application is" : "applications are"} awaiting approval.',
          severity: _RideOperatorAttentionSeverity.info,
          targetWorkspace: 'signups',
          targetSectionKey: _signupQueueSectionKey,
        ),
    ];
    if (attentionItems.isEmpty) {
      attentionItems.add(
        _RideOperatorAttentionItemData(
          icon: Icons.task_alt_outlined,
          title:
              isArabic ? 'لا توجد تصعيدات فورية' : 'No immediate escalations',
          detail: isArabic
              ? 'لوحة التشغيل مستقرة حالياً. راقب الطلبات الحية والطوابير للتغيرات الجديدة.'
              : 'The operator board is stable right now. Monitor live dispatch and queues for new changes.',
          severity: _RideOperatorAttentionSeverity.success,
        ),
      );
    }

    final actionButtons = <Widget>[
      if (board != null)
        _buildSectionJumpButton(
          workspace: 'dispatches',
          sectionKey: _dispatchesSectionKey,
          icon: Icons.local_shipping_outlined,
          label: isArabic ? 'راجع الطلبات' : 'Inspect dispatches',
          primary: true,
        ),
      if (_driverRoster != null)
        _buildSectionJumpButton(
          workspace: 'fleet',
          sectionKey: _fleetSectionKey,
          icon: Icons.map_outlined,
          label: isArabic ? 'افحص الأسطول' : 'Inspect fleet',
        ),
      if (caseQueue != null && caseQueue.cases.isNotEmpty)
        _buildSectionJumpButton(
          workspace: 'cases',
          sectionKey: _caseQueueSectionKey,
          icon: Icons.assignment_late_outlined,
          label: isArabic ? 'راجع القضايا' : 'Review cases',
        ),
      if (supportQueue != null)
        _buildSectionJumpButton(
          workspace: 'support',
          sectionKey: _supportQueueSectionKey,
          icon: Icons.support_agent_outlined,
          label: isArabic ? 'راجع الدعم' : 'Review support',
        ),
      if (documentQueue != null)
        _buildSectionJumpButton(
          workspace: 'documents',
          sectionKey: _documentQueueSectionKey,
          icon: Icons.badge_outlined,
          label: isArabic ? 'راجع الوثائق' : 'Review documents',
        ),
      if (financeQueue != null)
        _buildSectionJumpButton(
          workspace: 'payouts',
          sectionKey: _financeQueueSectionKey,
          icon: Icons.account_balance_wallet_outlined,
          label: isArabic ? 'افحص السحوبات' : 'Check payouts',
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'مكتب التشغيل' : 'Command desk',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'ابدأ من ضغط الإسناد، تذاكر العملاء، عوائق الامتثال، والسحوبات المعلقة.'
                  : 'Start from dispatch pressure, customer risk, compliance blockers, and pending payouts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _RideOperatorCommandMetricCard(
                  icon: Icons.local_shipping_outlined,
                  label: isArabic ? 'الطلبات المفتوحة' : 'Open dispatches',
                  value:
                      board == null ? '--' : '${board.counts.openDispatches}',
                ),
                _RideOperatorCommandMetricCard(
                  icon: Icons.route_outlined,
                  label: isArabic ? 'الرحلات النشطة' : 'Active rides',
                  value: board == null ? '--' : '${board.counts.activeTrips}',
                ),
                _RideOperatorCommandMetricCard(
                  icon: Icons.crisis_alert_outlined,
                  label: isArabic ? 'القضايا الحرجة' : 'Critical cases',
                  value: caseQueue == null
                      ? '--'
                      : '${caseQueue.totals.criticalCases}',
                ),
                _RideOperatorCommandMetricCard(
                  icon: Icons.support_agent_outlined,
                  label: isArabic ? 'الدعم العاجل' : 'Urgent support',
                  value: supportQueue == null
                      ? '--'
                      : '${supportQueue.totals.urgentTickets}',
                ),
                _RideOperatorCommandMetricCard(
                  icon: Icons.badge_outlined,
                  label: isArabic ? 'سائقون محجوبون' : 'Blocked drivers',
                  value: documentQueue == null
                      ? '--'
                      : '${documentQueue.totals.blockedDrivers}',
                ),
                _RideOperatorCommandMetricCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: isArabic ? 'سحوبات معلقة' : 'Pending payouts',
                  value: financeQueue == null
                      ? '--'
                      : '${financeQueue.totals.pendingRequests}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              isArabic ? 'يحتاج انتباه' : 'Needs attention',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            // Cycle 75 — on wide layouts (tablet / landscape) the
            // "Needs attention" list lays out in 2 columns to lift
            // information density without making single phones
            // unreadable. Threshold 600 dp matches Material's
            // tablet-ish breakpoint.
            //
            // Cycle 80 — items with a `targetWorkspace` are now
            // tappable; we hand each widget a closure that drives the
            // same workspace-jump + scroll-to-section pattern as the
            // "Jump to workspace" outlined buttons below.
            LayoutBuilder(builder: (ctx, constraints) {
              VoidCallback? tapFor(_RideOperatorAttentionItemData item) {
                final ws = item.targetWorkspace;
                final sk = item.targetSectionKey;
                if (ws == null || sk == null) return null;
                return () {
                  // Cycle 100 — light haptic on attention-item taps so
                  // operators get the same tactile confirmation that
                  // driver / rider primary actions have (Cycles 98+99).
                  unawaited(HapticFeedback.selectionClick());
                  _selectWorkspace(ws);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(_scrollToSection(sk));
                  });
                };
              }

              final wide = constraints.maxWidth >= 600;
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final item in attentionItems) ...<Widget>[
                      _RideOperatorAttentionItem(
                        item: item,
                        onTap: tapFor(item),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              const spacing = 10.0;
              final itemWidth =
                  (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: <Widget>[
                  for (final item in attentionItems)
                    SizedBox(
                      width: itemWidth,
                      child: _RideOperatorAttentionItem(
                        item: item,
                        onTap: tapFor(item),
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 10),
            if (actionButtons.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                isArabic ? 'الانتقال السريع' : 'Jump to workspace',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: actionButtons,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceFocusSection(
    BuildContext context, {
    required List<String> availableWorkspaces,
    required String selectedWorkspace,
    required Set<String> collapsedWorkspaces,
    required RideOperatorLiveBoard? board,
    required RideOperatorDriverRoster? driverRoster,
    required RideOperatorCaseQueue? caseQueue,
    required RideOperatorSupportQueue? supportQueue,
    required RideOperatorDocumentQueue? documentQueue,
    required RideOperatorFinanceQueue? financeQueue,
    required bool isArabic,
  }) {
    final visibleWorkspaces = _visibleWorkspaces(
      availableWorkspaces: availableWorkspaces,
      selectedWorkspace: selectedWorkspace,
    );
    final visibleWorkspaceCount =
        selectedWorkspace == 'all' ? availableWorkspaces.length : 1;
    final collapsedVisibleCount = visibleWorkspaces
        .where((workspace) => collapsedWorkspaces.contains(workspace))
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'تركيز مساحة العمل' : 'Workspace focus',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'اعرض جميع مساحات العمل أو ركّز على مساحة تشغيل واحدة في الصفحة الحالية.'
                  : 'Show every workspace or stay inside one ride-ops workspace at a time.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                ChoiceChip(
                  key: const ValueKey('rideOpsWorkspaceFocus_all'),
                  label: Text(
                    '${_rideOperatorWorkspaceLabel('all', isArabic: isArabic)} (${availableWorkspaces.length})',
                  ),
                  selected: selectedWorkspace == 'all',
                  onSelected: (selected) {
                    if (!selected) return;
                    _selectWorkspace('all');
                  },
                ),
                for (final workspace in availableWorkspaces)
                  ChoiceChip(
                    key: ValueKey('rideOpsWorkspaceFocus_$workspace'),
                    label: Text(
                      '${_rideOperatorWorkspaceLabel(workspace, isArabic: isArabic)} (${_workspaceCount(
                        workspace: workspace,
                        board: board,
                        driverRoster: driverRoster,
                        caseQueue: caseQueue,
                        supportQueue: supportQueue,
                        documentQueue: documentQueue,
                        financeQueue: financeQueue,
                      )})',
                    ),
                    selected: selectedWorkspace == workspace,
                    onSelected: (selected) {
                      if (!selected) return;
                      _selectWorkspace(workspace);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('rideOpsCollapseVisible'),
                  onPressed: visibleWorkspaces.isEmpty
                      ? null
                      : () => _collapseVisibleWorkspaces(
                            availableWorkspaces: availableWorkspaces,
                            selectedWorkspace: selectedWorkspace,
                          ),
                  icon: const Icon(Icons.unfold_less_rounded),
                  label: Text(isArabic ? 'طي الظاهر' : 'Collapse visible'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('rideOpsExpandVisible'),
                  onPressed: visibleWorkspaces.isEmpty
                      ? null
                      : () => _expandVisibleWorkspaces(
                            availableWorkspaces: availableWorkspaces,
                            selectedWorkspace: selectedWorkspace,
                          ),
                  icon: const Icon(Icons.unfold_more_rounded),
                  label: Text(isArabic ? 'توسيع الظاهر' : 'Expand visible'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'إظهار $visibleWorkspaceCount من ${availableWorkspaces.length} مساحات عمل'
                  : 'Showing $visibleWorkspaceCount of ${availableWorkspaces.length} workspaces',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .72),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'مطوي $collapsedVisibleCount من $visibleWorkspaceCount مساحات عمل'
                  : 'Collapsed $collapsedVisibleCount of $visibleWorkspaceCount workspaces',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .72),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionJumpButton({
    required String workspace,
    required GlobalKey sectionKey,
    required IconData icon,
    required String label,
    bool primary = false,
  }) {
    void onPressed() {
      _selectWorkspace(workspace);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_scrollToSection(sectionKey));
      });
    }

    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  /// Cycle 101 — render the role-signup admin workspace. Shows one
  /// card per pending request with an Approve / Reject row. Approve
  /// grants the role via the existing `auth_role_assignments` path
  /// and the gate widget on the user's side flips to "approved"
  /// on the next poll.
  Widget _buildSignupsWorkspace(
    BuildContext context, {
    required List<RoleSignupRequest> requests,
    required bool isArabic,
  }) {
    final theme = Theme.of(context);
    // Cycle 105 — driver / operator filter chips so admins can
    // focus on one role at a time when the queue is mixed. Counts
    // alongside each chip show how many of that kind are pending.
    final driverCount = requests
        .where((r) => r.requestedRoleId == RoleSignupRoleIds.driver)
        .length;
    final operatorCount = requests
        .where((r) => r.requestedRoleId == RoleSignupRoleIds.operator)
        .length;
    // Cycle 146 — cross-flavor signup queues. Each of these maps to a
    // dedicated standalone-app gate (Bus / Hotel / Carrier APKs); the
    // operator console is the single review surface, so we surface
    // them as siblings to driver/operator instead of forcing admins
    // to filter by raw role-id from a URL.
    final busOperatorCount = requests
        .where((r) => r.requestedRoleId == RoleSignupRoleIds.busOperator)
        .length;
    final hotelOperatorCount = requests
        .where((r) => r.requestedRoleId == RoleSignupRoleIds.hotelOperator)
        .length;
    final carrierCount = requests
        .where((r) => r.requestedRoleId == RoleSignupRoleIds.carrier)
        .length;
    // Cycle 147 — SyrCom workforce-member queue. Same sibling pattern
    // as the other cross-flavor tabs above.
    final syrcomCount = requests
        .where((r) => r.requestedRoleId == RoleSignupRoleIds.syrcom)
        .length;
    final filtered = _signupRoleFilter == null
        ? requests
        : requests
            .where((r) => r.requestedRoleId == _signupRoleFilter)
            .toList(growable: false);
    return Card(
      key: _signupQueueSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.person_add_alt_1_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic
                        ? 'طلبات التسجيل قيد المراجعة'
                        : 'Pending signup requests',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text('${filtered.length}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                ChoiceChip(
                  label: Text(
                    isArabic
                        ? 'الكل (${requests.length})'
                        : 'All (${requests.length})',
                  ),
                  selected: _signupRoleFilter == null,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _signupRoleFilter = null;
                      _persistOperatorUiState();
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    isArabic
                        ? 'سائقون ($driverCount)'
                        : 'Drivers ($driverCount)',
                  ),
                  selected:
                      _signupRoleFilter == RoleSignupRoleIds.driver,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _signupRoleFilter = RoleSignupRoleIds.driver;
                      _persistOperatorUiState();
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    isArabic
                        ? 'مشغّلون ($operatorCount)'
                        : 'Operators ($operatorCount)',
                  ),
                  selected:
                      _signupRoleFilter == RoleSignupRoleIds.operator,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _signupRoleFilter = RoleSignupRoleIds.operator;
                      _persistOperatorUiState();
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    isArabic
                        ? 'مشغّلو الحافلات ($busOperatorCount)'
                        : 'Bus operators ($busOperatorCount)',
                  ),
                  selected:
                      _signupRoleFilter == RoleSignupRoleIds.busOperator,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _signupRoleFilter = RoleSignupRoleIds.busOperator;
                      _persistOperatorUiState();
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    isArabic
                        ? 'مشغّلو الفنادق ($hotelOperatorCount)'
                        : 'Hotel operators ($hotelOperatorCount)',
                  ),
                  selected:
                      _signupRoleFilter == RoleSignupRoleIds.hotelOperator,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _signupRoleFilter = RoleSignupRoleIds.hotelOperator;
                      _persistOperatorUiState();
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    isArabic
                        ? 'ناقلون ($carrierCount)'
                        : 'Carriers ($carrierCount)',
                  ),
                  selected:
                      _signupRoleFilter == RoleSignupRoleIds.carrier,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _signupRoleFilter = RoleSignupRoleIds.carrier;
                      _persistOperatorUiState();
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    isArabic
                        ? 'سركم ($syrcomCount)'
                        : 'SyrCom ($syrcomCount)',
                  ),
                  selected:
                      _signupRoleFilter == RoleSignupRoleIds.syrcom,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _signupRoleFilter = RoleSignupRoleIds.syrcom;
                      _persistOperatorUiState();
                    });
                  },
                ),
              ],
            ),
            if (filtered.isEmpty) ...<Widget>[
              // Cycle 114 — empty-state for filtered Signups workspace.
              // When the admin picks "Drivers" but only operator
              // applications are pending, the section used to render
              // as a header-only card with no content. This message
              // tells them the filter is the reason and offers a
              // one-tap reset.
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.filter_alt_off_rounded,
                        size: 18,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .60)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isArabic
                            ? 'لا توجد طلبات لهذا الفلتر. اختر "الكل" لعرض جميع الطلبات.'
                            : 'No applications match this filter. Pick "All" to see every request.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            for (final request in filtered) ...<Widget>[
              const Divider(height: 16),
              _RoleSignupAdminCard(
                request: request,
                api: RoleSignupApi(baseUrl: widget.baseUrl ?? ''),
                isArabic: isArabic,
                onReviewed: () {
                  unawaited(_refreshAll(showNotifications: false));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceDesk(
    BuildContext context, {
    required String workspace,
    required String title,
    required String summary,
    required List<_RideOperatorWorkspaceSignalData> signals,
    List<_RideOperatorWorkspaceSortOptionData> sortOptions =
        const <_RideOperatorWorkspaceSortOptionData>[],
    String? selectedSort,
    ValueChanged<String>? onSortSelected,
    required bool isArabic,
    required Widget body,
  }) {
    final collapsed = _collapsedWorkspaces.contains(workspace);
    return Container(
      key: ValueKey('rideOpsWorkspace_$workspace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: ValueKey('rideOpsWorkspaceToggle_$workspace'),
                        onPressed: () => _toggleWorkspaceCollapsed(workspace),
                        icon: Icon(
                          collapsed
                              ? Icons.unfold_more_rounded
                              : Icons.unfold_less_rounded,
                        ),
                        label: Text(isArabic
                            ? (collapsed ? 'توسيع' : 'طي')
                            : (collapsed ? 'Expand' : 'Collapse')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .72),
                        ),
                  ),
                  if (signals.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: signals
                          .map(
                            (signal) => _RideOperatorWorkspaceSignalChip(
                              key: ValueKey(
                                'rideOpsWorkspaceSignal_${workspace}_${signal.id}',
                              ),
                              signal: signal,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  if (sortOptions.isNotEmpty &&
                      selectedSort != null &&
                      onSortSelected != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      isArabic ? 'ترتيب محلي' : 'Local sort',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .78),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sortOptions
                          .map(
                            (option) => ChoiceChip(
                              key: ValueKey(
                                'rideOpsWorkspaceSort_${workspace}_${option.id}',
                              ),
                              label: Text(option.label),
                              selected: selectedSort == option.id,
                              onSelected: (selected) {
                                if (!selected) {
                                  return;
                                }
                                onSortSelected(option.id);
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: collapsed
                ? Card(
                    key: ValueKey('rideOpsWorkspaceCollapsed_$workspace'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        isArabic
                            ? 'مساحة العمل مطوية. وسّعها لمراجعة التفاصيل.'
                            : 'Workspace collapsed. Expand it to review details.',
                      ),
                    ),
                  )
                : Container(
                    key: ValueKey('rideOpsWorkspaceBody_$workspace'),
                    child: body,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(value),
          ],
        ),
      ),
    );
  }

  String _formatPercentFromBps(int bps) {
    final percent = bps / 100;
    if (bps % 100 == 0) {
      return '${percent.toStringAsFixed(0)}%';
    }
    return '${percent.toStringAsFixed(1)}%';
  }

  String _driverAvailabilityLabel(
    RideOperatorDriverRosterEntry driver, {
    required bool isArabic,
  }) {
    if (driver.isOnline && rideOperatorDriverIsStale(driver)) {
      return isArabic ? 'نبضة قديمة' : 'Stale';
    }
    if (driver.isOnline && driver.location == null) {
      return isArabic ? 'بدون GPS' : 'No GPS';
    }
    if (driver.isIdleOnline) {
      return isArabic ? 'متاح' : 'Idle';
    }
    if (driver.isOnline) {
      return isArabic ? 'في رحلة' : 'Active';
    }
    return isArabic ? 'غير متصل' : 'Offline';
  }

  String _reserveEventStatusLabel(
    String status, {
    required bool isArabic,
  }) {
    switch (status.trim().toLowerCase()) {
      case 'reserved':
        return isArabic ? 'محجوز' : 'Held';
      case 'released':
        return isArabic ? 'مفرج عنه' : 'Released';
      case 'settled':
        return isArabic ? 'مسوى' : 'Settled';
      default:
        return status;
    }
  }

  String _shortDriverHandle(String accountId) {
    if (accountId.length <= 12) {
      return accountId;
    }
    return '${accountId.substring(0, 12)}…';
  }

  String _relativeIsoLabel(
    String iso, {
    required bool isArabic,
  }) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return isArabic ? 'غير معروف' : 'Unknown';
    }
    final delta = DateTime.now().difference(parsed.toLocal());
    if (delta.inMinutes < 1) {
      return isArabic ? 'الآن' : 'just now';
    }
    if (delta.inHours < 1) {
      return isArabic ? 'منذ ${delta.inMinutes} د' : '${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return isArabic ? 'منذ ${delta.inHours} س' : '${delta.inHours}h ago';
    }
    return isArabic ? 'منذ ${delta.inDays} ي' : '${delta.inDays}d ago';
  }

  String _fleetFilterWireValue(_RideOperatorFleetFilter filter) {
    switch (filter) {
      case _RideOperatorFleetFilter.all:
        return 'all';
      case _RideOperatorFleetFilter.idle:
        return 'idle';
      case _RideOperatorFleetFilter.onTrip:
        return 'on_trip';
      case _RideOperatorFleetFilter.stale:
        return 'stale';
      case _RideOperatorFleetFilter.noGps:
        return 'no_gps';
    }
  }

  String _fleetFilterLabel(
    _RideOperatorFleetFilter filter, {
    required bool isArabic,
  }) {
    switch (filter) {
      case _RideOperatorFleetFilter.all:
        return isArabic ? 'الكل' : 'All';
      case _RideOperatorFleetFilter.idle:
        return isArabic ? 'متاح' : 'Idle';
      case _RideOperatorFleetFilter.onTrip:
        return isArabic ? 'في رحلة' : 'On trip';
      case _RideOperatorFleetFilter.stale:
        return isArabic ? 'نبضة قديمة' : 'Stale';
      case _RideOperatorFleetFilter.noGps:
        return isArabic ? 'بدون GPS' : 'No GPS';
    }
  }

  String _opsDataWarningLabel(
    String warning, {
    required bool isArabic,
  }) {
    switch (warning) {
      case 'live_board_unavailable':
        return isArabic
            ? 'تعذّر تحديث لوحة الرحلات الحية. يتم عرض آخر حالة معروفة.'
            : 'Live trip board refresh failed. Showing the last known trip state.';
      case 'fleet_live_unavailable':
        return isArabic
            ? 'تعذّر تحديث الأسطول الحي. يتم عرض آخر حالة معروفة للسائقين.'
            : 'Live fleet refresh failed. Showing the last known driver state.';
      case 'case_queue_unavailable':
        return isArabic
            ? 'تعذّر تحديث طابور الحالات.'
            : 'Case queue refresh failed.';
      case 'support_queue_unavailable':
        return isArabic
            ? 'تعذّر تحديث طابور الدعم.'
            : 'Support queue refresh failed.';
      case 'document_queue_unavailable':
        return isArabic
            ? 'تعذّر تحديث طابور الوثائق.'
            : 'Document queue refresh failed.';
      case 'finance_queue_unavailable':
        return isArabic
            ? 'تعذّر تحديث طابور المالية.'
            : 'Finance queue refresh failed.';
      case 'pricing_unavailable':
        return isArabic
            ? 'تعذّر تحديث سياسات التسعير.'
            : 'Pricing policy refresh failed.';
      default:
        return isArabic
            ? 'تعذّر تحديث بعض بيانات التشغيل.'
            : 'Some operations data could not be refreshed.';
    }
  }

  Future<void> _openTripFromDriverSheet(
    String rideId, {
    required BuildContext sheetContext,
    required bool isArabic,
  }) async {
    final trip = rideOperatorFindTripById(
      board: _board,
      rideId: rideId,
    );
    if (trip == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تعذر العثور على الرحلة النشطة الحالية في اللوحة الحية.'
                : 'Could not find the current active trip in the live board.',
          ),
        ),
      );
      return;
    }
    Navigator.of(sheetContext).pop();
    await _showTripDetailsSheet(trip, isArabic: isArabic);
  }

  Widget _tripTile({
    required BuildContext context,
    required RideTrip trip,
    required bool isArabic,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _showTripDetailsSheet(trip, isArabic: isArabic),
        leading: const Icon(Icons.route_outlined),
        title: Text(
          '${trip.pickup} -> ${trip.destination}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_statusLabel(trip.status, isArabic: isArabic)} • ${fmtCents(trip.fareEstimateCents)} SYP • ${trip.etaMinutes} min',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Future<void> _cancelTripAsOperator(
    RideTrip trip, {
    required bool isArabic,
  }) async {
    final approvedReveal = await _requireSensitiveReveal(
      reason: isArabic
          ? 'أكد هويتك لإلغاء رحلة تشغيلية حساسة.'
          : 'Authenticate to cancel a sensitive operator trip.',
    );
    if (!approvedReveal) {
      return;
    }
    final reasonCtrl = TextEditingController(
      text:
          isArabic ? 'أُلغي من قبل التشغيل.' : 'Cancelled by ride operations.',
    );
    final String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isArabic ? 'إلغاء الرحلة' : 'Cancel trip'),
          content: TextField(
            controller: reasonCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: isArabic ? 'سبب الإلغاء' : 'Cancellation reason',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(isArabic ? 'رجوع' : 'Back'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(reasonCtrl.text.trim()),
              child: Text(isArabic ? 'إلغاء الرحلة' : 'Cancel trip'),
            ),
          ],
        ),
      );
    } finally {
      reasonCtrl.dispose();
    }
    if (reason == null || reason.trim().isEmpty) {
      return;
    }
    try {
      final updated = await _mobilityApi.operatorCommandTrip(
        rideId: trip.rideId,
        command: 'cancel_trip',
        reason: reason.trim(),
        cancelReasonCode: 'ops_cancelled',
      );
      if (!mounted) {
        return;
      }
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic ? 'تعذر تحديث الرحلة.' : 'Could not update ride.',
            ),
          ),
        );
        return;
      }
      await _refreshAll(showNotifications: false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'أُلغيت الرحلة ${shamellShortRideId(updated.rideId)}.'
                : 'Trip ${shamellShortRideId(updated.rideId)} cancelled.',
          ),
        ),
      );
    } on RideApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    }
  }

  bool _canCancelTrip(RideTrip trip) =>
      _opsAllowed && !rideTripStatusIsTerminal(trip.status);

  bool _canReassignTrip(RideTrip trip) {
    switch (trip.status) {
      case RideTripStatus.driverAssigned:
      case RideTripStatus.driverArriving:
      case RideTripStatus.driverArrived:
        return true;
      case RideTripStatus.idle:
      case RideTripStatus.quoteShown:
      case RideTripStatus.rideRequested:
      case RideTripStatus.matching:
      case RideTripStatus.tripStarted:
      case RideTripStatus.tripInProgress:
      case RideTripStatus.paymentFailed:
      case RideTripStatus.tripCompleted:
      case RideTripStatus.canceled:
        return false;
    }
  }

  Future<void> _reassignTripAsOperator(
    RideTrip trip, {
    required bool isArabic,
  }) async {
    final approvedReveal = await _requireSensitiveReveal(
      reason: isArabic
          ? 'أكد هويتك لإعادة تعيين رحلة تشغيلية حساسة.'
          : 'Authenticate to reassign a sensitive operator trip.',
    );
    if (!approvedReveal) {
      return;
    }
    final reason = isArabic
        ? 'أُعيدت الرحلة إلى المطابقة بواسطة التشغيل.'
        : 'Trip returned to matching by ride operations.';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(isArabic ? 'إعادة تعيين السائق' : 'Reassign driver'),
        content: Text(
          isArabic
              ? 'ستعود هذه الرحلة إلى المطابقة وسيُزال السائق الحالي من الإسناد.'
              : 'This trip will return to matching and the current driver assignment will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(isArabic ? 'رجوع' : 'Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isArabic ? 'إعادة التعيين' : 'Reassign'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final updated = await _mobilityApi.operatorCommandTrip(
        rideId: trip.rideId,
        command: 'reassign_trip',
        reason: reason,
      );
      if (!mounted) {
        return;
      }
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'تعذر إعادة تعيين الرحلة.'
                  : 'Could not reassign ride.',
            ),
          ),
        );
        return;
      }
      await _refreshAll(showNotifications: false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'أُعيدت الرحلة ${shamellShortRideId(updated.rideId)} إلى المطابقة.'
                : 'Trip ${shamellShortRideId(updated.rideId)} returned to matching.',
          ),
        ),
      );
    } on RideApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.detail)),
      );
    }
  }

  Future<void> _showTripDetailsSheet(
    RideTrip trip, {
    required bool isArabic,
  }) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final canCancel = _opsAllowed && !rideTripStatusIsTerminal(trip.status);
        final canReassign = _opsAllowed && _canReassignTrip(trip);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .72,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  isArabic ? 'تفاصيل الرحلة' : 'Trip details',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route_outlined),
                  title: Text(
                    '${trip.pickup} -> ${trip.destination}',
                  ),
                  subtitle: Text(
                    '${_statusLabel(trip.status, isArabic: isArabic)} • ${_rideClassLabel(trip.rideClass, isArabic: isArabic)}',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  rideOperatorTripIdLabel(trip.rideId, isArabic: isArabic),
                ),
                const SizedBox(height: 6),
                Text(
                  isArabic
                      ? 'التقدير ${fmtCents(trip.fareEstimateCents)} SYP • ETA ${trip.etaMinutes} د'
                      : 'Estimate ${fmtCents(trip.fareEstimateCents)} SYP • ETA ${trip.etaMinutes} min',
                ),
                if (trip.driverName.trim().isNotEmpty ||
                    trip.carPlate.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    isArabic
                        ? 'السائق ${trip.driverName} • ${shamellMaskVehiclePlate(trip.carPlate)}'
                        : 'Driver ${trip.driverName} • ${shamellMaskVehiclePlate(trip.carPlate)}',
                  ),
                ],
                // Cycle 144 — passenger rating aggregate, fetched
                // lazily so the sheet open is snappy. The endpoint
                // resolves rider→aggregate server-side without
                // leaking the rider account_id to the operator.
                const SizedBox(height: 10),
                _OperatorTripPassengerRatingBlock(
                  baseUrl: widget.baseUrl,
                  rideId: trip.rideId,
                  isArabic: isArabic,
                ),
                if ((trip.cancelReasonCode ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    isArabic
                        ? 'رمز الإلغاء ${trip.cancelReasonCode}'
                        : 'Cancel code ${trip.cancelReasonCode}',
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  isArabic ? 'الطوابع الزمنية' : 'Timestamps',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('Created: ${trip.createdAtIso}'),
                Text('Updated: ${trip.lastUpdatedAtIso}'),
                if ((trip.assignedAtIso ?? '').trim().isNotEmpty)
                  Text('Assigned: ${trip.assignedAtIso}'),
                if ((trip.arrivingAtIso ?? '').trim().isNotEmpty)
                  Text('Arriving: ${trip.arrivingAtIso}'),
                if ((trip.arrivedAtIso ?? '').trim().isNotEmpty)
                  Text('Arrived: ${trip.arrivedAtIso}'),
                if ((trip.startedAtIso ?? '').trim().isNotEmpty)
                  Text('Started: ${trip.startedAtIso}'),
                if ((trip.completedAtIso ?? '').trim().isNotEmpty)
                  Text('Completed: ${trip.completedAtIso}'),
                if (canCancel) ...[
                  const SizedBox(height: 16),
                  if (canReassign)
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _reassignTripAsOperator(
                          trip,
                          isArabic: isArabic,
                        );
                      },
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: Text(
                        isArabic ? 'إعادة تعيين السائق' : 'Reassign driver',
                      ),
                    ),
                  if (canReassign) const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(sheetContext).colorScheme.error,
                      foregroundColor:
                          Theme.of(sheetContext).colorScheme.onError,
                    ),
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _cancelTripAsOperator(
                        trip,
                        isArabic: isArabic,
                      );
                    },
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(isArabic ? 'إلغاء الرحلة' : 'Cancel trip'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDriverDetailsSheet(
    RideOperatorDriverRosterEntry driver, {
    required bool isArabic,
  }) async {
    if (!mounted) {
      return;
    }
    if (_complianceSensitiveAllowed) {
      final approvedReveal = await _requireSensitiveReveal(
        reason: 'Authenticate to reveal sensitive operator ride details.',
      );
      if (!approvedReveal) {
        return;
      }
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .62,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                isArabic ? 'تفاصيل السائق' : 'Driver details',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                driver.driverName ?? _shortDriverHandle(driver.driverAccountId),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              if ((driver.carPlate ?? '').trim().isNotEmpty)
                Text(shamellMaskVehiclePlate(driver.carPlate!)),
              const SizedBox(height: 10),
              Text(
                isArabic
                    ? 'الحالة ${_driverAvailabilityLabel(driver, isArabic: true)}'
                    : 'Status ${_driverAvailabilityLabel(driver, isArabic: false)}',
              ),
              Text(
                isArabic
                    ? 'آخر نبضة ${_relativeIsoLabel(driver.lastSeenAtIso, isArabic: true)}'
                    : 'Last heartbeat ${_relativeIsoLabel(driver.lastSeenAtIso, isArabic: false)}',
              ),
              if ((driver.lastOnlineAtIso ?? '').trim().isNotEmpty)
                Text(
                  isArabic
                      ? 'آخر اتصال ${driver.lastOnlineAtIso}'
                      : 'Last online ${driver.lastOnlineAtIso}',
                ),
              // Cycle 138 — passenger-driven rating roll-up so the
              // operator can spot persistent low scorers (or quietly
              // promote consistent 5-star drivers) at a glance.
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFFB8860B),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      driver.hasRatings
                          ? (isArabic
                              ? 'التقييم ${driver.averageStars!.toStringAsFixed(1)} من 5 (${driver.ratingCount} تقييم)'
                              : 'Rating ${driver.averageStars!.toStringAsFixed(1)} / 5 (${driver.ratingCount} ratings)')
                          : (isArabic
                              ? 'لا توجد تقييمات بعد'
                              : 'No ratings yet'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (_complianceSensitiveAllowed) ...[
                const SizedBox(height: 12),
                Text(
                  isArabic ? 'المعرّفات' : 'Identifiers',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  isArabic
                      ? 'السائق ${shamellMaskIdentifier(driver.driverAccountId, prefix: 6, suffix: 4)}'
                      : 'Driver ${shamellMaskIdentifier(driver.driverAccountId, prefix: 6, suffix: 4)}',
                ),
              ],
              if (driver.location != null) ...[
                const SizedBox(height: 12),
                Text(
                  isArabic ? 'الموقع الحالي' : 'Current location',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  shamellApproximateCoordinatePair(
                    lat: driver.location!.lat,
                    lon: driver.location!.lon,
                  ),
                ),
              ],
              if ((driver.activeRideId ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  isArabic ? 'الرحلة النشطة' : 'Active trip',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  rideOperatorTripIdLabel(
                    driver.activeRideId!,
                    isArabic: isArabic,
                  ),
                ),
                if (_complianceSensitiveAllowed &&
                    (driver.activePickup ?? '').trim().isNotEmpty &&
                    (driver.activeDestination ?? '').trim().isNotEmpty)
                  Text('${driver.activePickup} -> ${driver.activeDestination}'),
                if (driver.activeTripStatus != null)
                  Text(
                    _statusLabel(
                      driver.activeTripStatus!,
                      isArabic: isArabic,
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _openTripFromDriverSheet(
                    driver.activeRideId!,
                    sheetContext: sheetContext,
                    isArabic: isArabic,
                  ),
                  icon: const Icon(Icons.route_outlined),
                  label: Text(
                    isArabic ? 'فتح تفاصيل الرحلة' : 'Open trip details',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _contactSupportByMail,
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: Text(isArabic ? 'راسل الدعم' : 'Email support'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _contactSupportByPhone,
                    icon: const Icon(Icons.phone_outlined),
                    label: Text(isArabic ? 'اتصل بالدعم' : 'Call support'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _rideClassLabel(String rideClass, {required bool isArabic}) {
    switch (rideClass.trim().toLowerCase()) {
      case 'economy':
        return isArabic ? 'اقتصادي' : 'Economy';
      case 'xl':
        return isArabic ? 'XL / فان' : 'XL / Van';
      case 'premium':
        return isArabic ? 'مميز' : 'Premium';
      case 'delivery':
        return isArabic ? 'توصيل' : 'Delivery';
      case 'corporate':
        return isArabic ? 'شركات' : 'Corporate';
      default:
        return rideClass;
    }
  }

  Color _alertColor(BuildContext context, RideOperatorAlertSeverity severity) {
    final scheme = Theme.of(context).colorScheme;
    switch (severity) {
      case RideOperatorAlertSeverity.info:
        return scheme.primary;
      case RideOperatorAlertSeverity.medium:
        return Colors.orange.shade700;
      case RideOperatorAlertSeverity.high:
        return scheme.error;
      case RideOperatorAlertSeverity.critical:
        return Colors.red.shade900;
    }
  }

  String _caseCategoryLabel(
    RideOperatorCaseCategory category, {
    required bool isArabic,
  }) {
    switch (category) {
      case RideOperatorCaseCategory.finance:
        return isArabic ? 'مالي' : 'Finance';
      case RideOperatorCaseCategory.support:
        return isArabic ? 'دعم' : 'Support';
      case RideOperatorCaseCategory.compliance:
        return isArabic ? 'امتثال' : 'Compliance';
    }
  }

  String _formatAgeSeconds(int ageSeconds, {required bool isArabic}) {
    final hours = ageSeconds ~/ 3600;
    final minutes = (ageSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return isArabic ? '${hours}س ${minutes}د' : '${hours}h ${minutes}m';
    }
    return isArabic ? '${minutes}د' : '${minutes}m';
  }

  /// Cycle 88 — render a short "Just now" / "2m ago" / "1h ago"
  /// freshness label off the last successful refresh timestamp.
  String? _operatorFreshnessLabel(DateTime stamp, {required bool isArabic}) {
    final diff = DateTime.now().difference(stamp);
    if (diff.isNegative) return null;
    if (diff.inSeconds < 15) {
      return isArabic ? 'الآن' : 'Just now';
    }
    if (diff.inMinutes < 1) {
      return isArabic ? '${diff.inSeconds} ثانية' : '${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return isArabic ? 'منذ ${diff.inMinutes} د' : '${diff.inMinutes}m ago';
    }
    final hours = diff.inHours;
    return isArabic ? 'منذ ${hours} س' : '${hours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final bootstrap = _bootstrap;
    final board = _board;
    final caseQueue = _caseQueue;
    final supportQueue = _supportQueue;
    final documentQueue = _documentQueue;
    final pricingPolicies = _pricingPolicies;
    final financeQueue = _financeQueue;
    final focusTrip = _focusTrip;
    final focusQuote = _focusQuote;
    final focusTracking = _focusTracking;
    final summary = board?.summary;
    final dispatchSort = _workspaceSortValue('dispatches');
    final fleetSort = _workspaceSortValue('fleet');
    final caseSort = _workspaceSortValue('cases');
    final supportSort = _workspaceSortValue('support');
    final documentSort = _workspaceSortValue('documents');
    final payoutSort = _workspaceSortValue('payouts');
    final sortedOpenDispatches = _sortedTrips(
      board?.openDispatches ?? const <RideTrip>[],
      sort: dispatchSort,
    );
    final sortedActiveTrips = _sortedTrips(
      board?.activeTrips ?? const <RideTrip>[],
      sort: dispatchSort,
    );
    final sortedCaseItems = _sortedCaseItems(
      caseQueue?.cases ?? const <RideOperatorCaseItem>[],
      sort: caseSort,
    );
    final sortedSupportTickets = _sortedSupportTickets(
      supportQueue?.tickets ?? const <RideSupportTicket>[],
      sort: supportSort,
    );
    final sortedDocuments = _sortedDocuments(
      documentQueue?.documents ?? const <RideDriverDocument>[],
      sort: documentSort,
    );
    final sortedPayoutRequests = _sortedPayoutRequests(
      financeQueue?.requests ?? const <RidePayoutRequest>[],
      sort: payoutSort,
    );
    final rosterDrivers =
        _driverRoster?.drivers ?? const <RideOperatorDriverRosterEntry>[];
    final filteredDrivers = rosterDrivers
        .where(
          (driver) => rideOperatorDriverMatchesFleetFilter(
            driver: driver,
            filterWireValue: _fleetFilterWireValue(_fleetFilter),
          ),
        )
        .toList(growable: false);
    final sortedFilteredDrivers = _sortedDriverRosterEntries(
      filteredDrivers,
      sort: fleetSort,
    );
    final onlineDriverCount =
        rosterDrivers.where((driver) => driver.isOnline).length;
    final idleDriverCount =
        rosterDrivers.where((driver) => driver.isIdleOnline).length;
    final onTripDriverCount = rosterDrivers
        .where((driver) => driver.isOnline && driver.activeRideId != null)
        .length;
    final staleDriverCount = rosterDrivers
        .where((driver) => driver.isOnline && rideOperatorDriverIsStale(driver))
        .length;
    final noGpsDriverCount = rosterDrivers
        .where((driver) => driver.isOnline && driver.location == null)
        .length;
    final safetyTicketCount = supportQueue?.tickets
            .where(
              (ticket) => ticket.category == RideSupportTicketCategory.safety,
            )
            .length ??
        0;
    final lostFoundTicketCount = supportQueue?.tickets
            .where(
              (ticket) => ticket.category == RideSupportTicketCategory.lostItem,
            )
            .length ??
        0;
    final openDispatchCount = board?.counts.openDispatches ?? 0;
    final autoRematchCandidateCount = openDispatchCount > idleDriverCount
        ? openDispatchCount - idleDriverCount
        : 0;
    final urgentIncidentCount = (caseQueue?.totals.criticalCases ?? 0) +
        (supportQueue?.totals.urgentTickets ?? 0);
    final hasCommandDeskData = board != null ||
        _driverRoster != null ||
        caseQueue != null ||
        supportQueue != null ||
        documentQueue != null ||
        financeQueue != null;
    final signupQueue = _signupQueue ?? const <RoleSignupRequest>[];
    final availableWorkspaces = <String>[
      if (board != null) 'dispatches',
      if (_driverRoster != null) 'fleet',
      if (caseQueue != null) 'cases',
      if (supportQueue != null) 'support',
      if (documentQueue != null) 'documents',
      if (financeQueue != null) 'payouts',
      // Cycle 101 — show the Signups workspace whenever the admin
      // queue has at least one pending request (so non-admins, who
      // get null from the BFF, never see this tab).
      if (signupQueue.isNotEmpty) 'signups',
    ];
    final selectedWorkspace = availableWorkspaces.contains(_selectedWorkspace)
        ? _selectedWorkspace
        : 'all';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          shamellSurfaceAppTitle(
            isArabic: l.isArabic,
            surface: ShamellAppSurface.operator,
          ),
        ),
        // Cycle 91 — thin progress strip at the AppBar bottom while
        // a background refresh is in flight. Pairs with Cycle 88's
        // last-updated chip to give a true "fresh data is on the way"
        // signal instead of a silent stale board.
        bottom: _refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                ),
              )
            : null,
        // Cycle 88 — tappable "Last updated N min ago" chip in the
        // AppBar. Operators run the console for long stretches; this
        // gives them an unambiguous freshness signal + one-tap retry.
        //
        // Cycle 92 — the chip background now tracks data age: fresh
        // (<60s) reads as neutral white-alpha, stale (60-180s)
        // amber-warning, very stale (>180s) red. The poll cycle is
        // 30 s so anything over a minute means a missed/failed poll.
        actions: <Widget>[
          if (_lastRefreshedAt != null)
            Builder(builder: (ctx) {
              final ageSeconds = _refreshing
                  ? 0
                  : DateTime.now().difference(_lastRefreshedAt!).inSeconds;
              Color bg;
              Color fg;
              if (_refreshing || ageSeconds < 60) {
                bg = Colors.white.withValues(alpha: .14);
                fg = Colors.white.withValues(alpha: .92);
              } else if (ageSeconds < 180) {
                bg = const Color(0xFFFFA000).withValues(alpha: .85);
                fg = Colors.white;
              } else {
                bg = Theme.of(ctx).colorScheme.error.withValues(alpha: .92);
                fg = Colors.white;
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 10),
                child: Tooltip(
                  message: l.isArabic
                      ? 'اضغط للتحديث الآن'
                      : 'Tap to refresh now',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () {
                      // Cycle 124 — light haptic on AppBar refresh
                      // chip so admins get tactile confirmation that
                      // the manual refresh kicked off, matching the
                      // pattern used by other admin actions.
                      unawaited(HapticFeedback.selectionClick());
                      unawaited(_refreshAll(showNotifications: false));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _refreshing
                                ? Icons.sync_rounded
                                : (ageSeconds >= 180
                                    ? Icons.error_outline_rounded
                                    : (ageSeconds >= 60
                                        ? Icons.warning_amber_rounded
                                        : Icons
                                            .check_circle_outline_rounded)),
                            size: 14,
                            color: fg,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _refreshing
                                ? (l.isArabic ? 'جارٍ التحديث…' : 'Refreshing…')
                                : (_operatorFreshnessLabel(
                                        _lastRefreshedAt!,
                                        isArabic: l.isArabic) ??
                                    (l.isArabic ? 'محدّث' : 'Up to date')),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          // Cycle 178 — quick access to the upcoming-scheduled-rides
          // queue. Lives in the AppBar so dispatch can flip between
          // the live board and tomorrow's planned bookings in one tap.
          IconButton(
            tooltip:
                l.isArabic ? 'الحجوزات القادمة' : 'Upcoming scheduled rides',
            icon: const Icon(Icons.event_available_outlined),
            onPressed: () {
              final baseUrl = widget.baseUrl;
              if (baseUrl == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (ctx) =>
                      OperatorScheduledRidesPage(baseUrl: baseUrl),
                ),
              );
            },
          ),
          // Cycle 202 — cancellation reason analytics. 30-day
          // breakdown helps dispatch spot trends ("X% no-shows
          // this week → toughen no-show policy").
          IconButton(
            tooltip: l.isArabic
                ? 'تحليل أسباب الإلغاء'
                : 'Cancellation analytics',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () {
              final baseUrl = widget.baseUrl;
              if (baseUrl == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (ctx) =>
                      OperatorCancellationAnalyticsPage(baseUrl: baseUrl),
                ),
              );
            },
          ),
          // Cycle 209 — promo code management. Operators mint,
          // list, and disable codes from one surface.
          IconButton(
            tooltip: l.isArabic ? 'أكواد الخصم' : 'Promo codes',
            icon: const Icon(Icons.local_offer_outlined),
            onPressed: () {
              final baseUrl = widget.baseUrl;
              if (baseUrl == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (ctx) =>
                      OperatorPromoManagementPage(baseUrl: baseUrl),
                ),
              );
            },
          ),
          // Cycle 215 — demand heatmap. Dispatch can spot where
          // pickups are clustering right now and pre-position cars.
          IconButton(
            tooltip:
                l.isArabic ? 'خريطة الطلب الحية' : 'Live demand heatmap',
            icon: const Icon(Icons.local_fire_department_outlined),
            onPressed: () {
              final baseUrl = widget.baseUrl;
              if (baseUrl == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (ctx) => DemandHeatmapPage(
                    baseUrl: baseUrl,
                    isOperator: true,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const ShamellSkeletonList(itemCount: 7)
          : RefreshIndicator(
              onRefresh: () => _refreshAll(showNotifications: false),
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                children: [
                  // Cycle 73 — the old "Operations status" Card
                  // restated "you're authorized" on every console
                  // load, eating ~120px above the Command Desk.
                  // Now it's a loud Card only when NOT authorized
                  // (rare, blocking state); the authorized steady
                  // state collapses to a thin top-row badge.
                  // Cycle 101 — operator signup gate. Replaces the
                  // static "not authorized" banner with a self-service
                  // signup form. Approval grants `rides.driver_ops`
                  // and the gate is unmounted on the next refresh.
                  if (!_opsAllowed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RoleSignupGate(
                        roleId: RoleSignupRoleIds.operator,
                        roleLabel: 'operator',
                        roleLabelArabic: 'مشغّل',
                        fields: RoleSignupFormFields.operator,
                        api: RoleSignupApi(baseUrl: widget.baseUrl ?? ''),
                        isArabic: l.isArabic,
                        onSubmitted: () {
                          unawaited(
                              _refreshAll(showNotifications: false));
                        },
                      ),
                    ),
                  // Cycle 154 — Safety banner. Renders only when at
                  // least one alert is active or acknowledged so
                  // operators don't see ambient red unless there's
                  // actually a live incident. Card has its own
                  // acknowledge/resolve actions inline so dispatch
                  // can react without leaving the dashboard.
                  if (_opsAllowed && _safetyAlerts.isNotEmpty)
                    _OperatorSafetyBanner(
                      baseUrl: widget.baseUrl,
                      alerts: _safetyAlerts,
                      isArabic: l.isArabic,
                      onChanged: () =>
                          unawaited(_refreshAll(showNotifications: false)),
                    ),
                  if (_opsAllowed && _privileges.roles.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          Chip(
                            avatar: const Icon(
                              Icons.verified_user_outlined,
                              size: 16,
                              color: Color(0xFF4CAF50),
                            ),
                            label: Text(
                              l.isArabic ? 'مفعّل' : 'Authorized',
                              style: const TextStyle(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          for (final role in _privileges.roles)
                            Chip(
                              label: Text(role,
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                  PushReadinessBanner(isArabic: l.isArabic),
                  // Cycle 83 — the refresh-warnings banner is now
                  // tappable to retry the failing fetches, and its
                  // palette follows the same `urgent` severity used
                  // by the command desk's attention items. Operators
                  // no longer have to scroll to the pull-to-refresh
                  // gesture or wait for the next 30 s poll tick.
                  if (_opsDataWarnings.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withValues(alpha: .42),
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => unawaited(
                              _refreshAll(showNotifications: false)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 20,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withValues(alpha: .95),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.isArabic
                                            ? 'تحذيرات التحديث — اضغط للمحاولة'
                                            : 'Refresh warnings — tap to retry',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      for (final warning
                                          in _opsDataWarnings) ...[
                                        Text(
                                          '• ${_opsDataWarningLabel(warning, isArabic: l.isArabic)}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        const SizedBox(height: 4),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 20,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withValues(alpha: .85),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (hasCommandDeskData)
                    _buildCommandDeskSection(
                      context,
                      board: board,
                      summary: summary,
                      caseQueue: caseQueue,
                      supportQueue: supportQueue,
                      documentQueue: documentQueue,
                      financeQueue: financeQueue,
                      staleDriverCount: staleDriverCount,
                      noGpsDriverCount: noGpsDriverCount,
                      isArabic: l.isArabic,
                    ),
                  if (availableWorkspaces.isNotEmpty)
                    _buildWorkspaceFocusSection(
                      context,
                      availableWorkspaces: availableWorkspaces,
                      selectedWorkspace: selectedWorkspace,
                      collapsedWorkspaces: _collapsedWorkspaces,
                      board: board,
                      driverRoster: _driverRoster,
                      caseQueue: caseQueue,
                      supportQueue: supportQueue,
                      documentQueue: documentQueue,
                      financeQueue: financeQueue,
                      isArabic: l.isArabic,
                    ),
                  if (focusTrip != null)
                    Semantics(
                      container: true,
                      label:
                          'Active trip operations ${shamellShortRideId(focusTrip.rideId)}',
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.isArabic
                                    ? 'عمليات الرحلة الحالية'
                                    : 'Active trip operations',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${focusTrip.pickup} -> ${focusTrip.destination}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                rideOperatorTripIdLabel(
                                  focusTrip.rideId,
                                  isArabic: l.isArabic,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l.isArabic
                                    ? '${_statusLabel(focusTrip.status, isArabic: true)} • ${fmtCents(focusTrip.fareEstimateCents)} SYP • ETA ${focusTrip.etaMinutes} د'
                                    : '${_statusLabel(focusTrip.status, isArabic: false)} • ${fmtCents(focusTrip.fareEstimateCents)} SYP • ETA ${focusTrip.etaMinutes} min',
                              ),
                              if (focusTrip.driverName.trim().isNotEmpty ||
                                  focusTrip.carPlate.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  l.isArabic
                                      ? 'السائق ${focusTrip.driverName} • ${shamellMaskVehiclePlate(focusTrip.carPlate)}'
                                      : 'Driver ${focusTrip.driverName} • ${shamellMaskVehiclePlate(focusTrip.carPlate)}',
                                ),
                              ],
                              if (focusTracking?.latestDriverLocation !=
                                  null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  l.isArabic
                                      ? 'آخر تتبّع للسائق: ${focusTracking!.latestDriverLocation!.createdAtIso}'
                                      : 'Driver tracking last seen: ${focusTracking!.latestDriverLocation!.createdAtIso}',
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => _showTripDetailsSheet(
                                      focusTrip,
                                      isArabic: l.isArabic,
                                    ),
                                    icon: const Icon(Icons.open_in_new_rounded),
                                    label: Text(
                                      l.isArabic
                                          ? 'فتح التفاصيل'
                                          : 'View details',
                                    ),
                                  ),
                                  if (_canReassignTrip(focusTrip))
                                    OutlinedButton.icon(
                                      onPressed: () => _reassignTripAsOperator(
                                        focusTrip,
                                        isArabic: l.isArabic,
                                      ),
                                      icon:
                                          const Icon(Icons.swap_horiz_rounded),
                                      label: Text(
                                        l.isArabic
                                            ? 'إعادة تعيين السائق'
                                            : 'Reassign driver',
                                      ),
                                    ),
                                  if (_canCancelTrip(focusTrip))
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            Theme.of(context).colorScheme.error,
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onError,
                                      ),
                                      onPressed: () => _cancelTripAsOperator(
                                        focusTrip,
                                        isArabic: l.isArabic,
                                      ),
                                      icon: const Icon(Icons.cancel_outlined),
                                      label: Text(
                                        l.isArabic
                                            ? 'إلغاء الرحلة'
                                            : 'Cancel trip',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_driverRoster != null &&
                      _rideOperatorWorkspaceVisible(
                        selectedWorkspace,
                        'fleet',
                      ))
                    _buildWorkspaceDesk(
                      context,
                      workspace: 'fleet',
                      title: l.isArabic ? 'مكتب الأسطول' : 'Fleet desk',
                      summary: l.isArabic
                          ? 'إظهار ${filteredDrivers.length} من أصل ${rosterDrivers.length} سائقين • متاحون $idleDriverCount • على رحلة $onTripDriverCount'
                          : 'Showing ${filteredDrivers.length} of ${rosterDrivers.length} drivers • Idle $idleDriverCount • On trip $onTripDriverCount',
                      signals: <_RideOperatorWorkspaceSignalData>[
                        _RideOperatorWorkspaceSignalData(
                          id: 'online',
                          label: l.isArabic ? 'متصلون' : 'Online',
                          value: '$onlineDriverCount',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'idle',
                          label: l.isArabic ? 'متاحون' : 'Idle',
                          value: '$idleDriverCount',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'stale',
                          label: l.isArabic ? 'نبضة قديمة' : 'Stale',
                          value: '$staleDriverCount',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'no_gps',
                          label: l.isArabic ? 'بدون GPS' : 'No GPS',
                          value: '$noGpsDriverCount',
                        ),
                      ],
                      sortOptions: _workspaceSortOptions(
                        'fleet',
                        isArabic: l.isArabic,
                      ),
                      selectedSort: fleetSort,
                      onSortSelected: (sort) => _setWorkspaceSort(
                        'fleet',
                        sort,
                      ),
                      isArabic: l.isArabic,
                      body: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeyedSubtree(
                            key: _fleetSectionKey,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.isArabic
                                          ? 'فلاتر الأسطول الحي'
                                          : 'Live fleet filters',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final filter
                                            in _RideOperatorFleetFilter.values)
                                          ChoiceChip(
                                            key: ValueKey(
                                              'rideOpsFleetFilter_${_fleetFilterWireValue(filter)}',
                                            ),
                                            label: Text(
                                              switch (filter) {
                                                _RideOperatorFleetFilter.all =>
                                                  '${_fleetFilterLabel(filter, isArabic: l.isArabic)} ${rosterDrivers.length}',
                                                _RideOperatorFleetFilter.idle =>
                                                  '${_fleetFilterLabel(filter, isArabic: l.isArabic)} $idleDriverCount',
                                                _RideOperatorFleetFilter
                                                      .onTrip =>
                                                  '${_fleetFilterLabel(filter, isArabic: l.isArabic)} $onTripDriverCount',
                                                _RideOperatorFleetFilter
                                                      .stale =>
                                                  '${_fleetFilterLabel(filter, isArabic: l.isArabic)} $staleDriverCount',
                                                _RideOperatorFleetFilter
                                                      .noGps =>
                                                  '${_fleetFilterLabel(filter, isArabic: l.isArabic)} $noGpsDriverCount',
                                              },
                                            ),
                                            selected: _fleetFilter == filter,
                                            onSelected: (_) {
                                              setState(() {
                                                _fleetFilter = filter;
                                                _persistOperatorUiState();
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l.isArabic
                                          ? 'إظهار ${filteredDrivers.length} من أصل ${rosterDrivers.length} سائقين في العرض الحالي.'
                                          : 'Showing ${filteredDrivers.length} of ${rosterDrivers.length} drivers in the current view.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          RideDriverFleetMapCard(
                            baseUrl: widget.baseUrl,
                            bootstrap: bootstrap,
                            drivers: sortedFilteredDrivers,
                            isArabic: l.isArabic,
                            fullscreenTitle:
                                l.isArabic ? 'خريطة الأسطول' : 'Fleet map',
                          ),
                          if (sortedFilteredDrivers.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.isArabic
                                          ? 'قائمة السائقين الحية'
                                          : 'Live driver roster',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ...sortedFilteredDrivers.map(
                                      (driver) => ListTile(
                                        key: ValueKey(
                                          'rideOpsDriver_${driver.driverAccountId}',
                                        ),
                                        onTap: () => _showDriverDetailsSheet(
                                          driver,
                                          isArabic: l.isArabic,
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: Icon(
                                          driver.isIdleOnline
                                              ? Icons.person_pin_circle_outlined
                                              : driver.isOnline
                                                  ? Icons.route_outlined
                                                  : Icons.person_off_outlined,
                                        ),
                                        title: Text(
                                          driver.driverName ??
                                              _shortDriverHandle(
                                                driver.driverAccountId,
                                              ),
                                        ),
                                        subtitle: Text(
                                          [
                                            if (driver.carPlate != null)
                                              shamellMaskVehiclePlate(
                                                driver.carPlate!,
                                              ),
                                            if ((driver.activeRideId ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              rideOperatorActiveRideLabel(
                                                driver.activeRideId,
                                                isArabic: l.isArabic,
                                              ),
                                            '${l.isArabic ? "آخر نبضة" : "Last heartbeat"} ${_relativeIsoLabel(driver.lastSeenAtIso, isArabic: l.isArabic)}',
                                          ].join(' • '),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _driverAvailabilityLabel(
                                                driver,
                                                isArabic: l.isArabic,
                                              ),
                                              textAlign: TextAlign.end,
                                            ),
                                            // Cycle 138 — rating chip in the
                                            // trailing column. Brand-new
                                            // drivers (count==0) get a quiet
                                            // "—" so the eye doesn't latch on
                                            // to a "0.0" that means "unrated"
                                            // not "bad".
                                            const SizedBox(height: 2),
                                            if (driver.hasRatings)
                                              Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.star_rounded,
                                                    size: 13,
                                                    color: Color(0xFFB8860B),
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '${driver.averageStars!.toStringAsFixed(1)}'
                                                    ' (${driver.ratingCount})',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12,
                                                      color: Color(0xFFB8860B),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            else
                                              const Text(
                                                '— ★',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black38,
                                                ),
                                              ),
                                          ],
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
                  _metricTile(
                    context: context,
                    icon: Icons.local_shipping_outlined,
                    title: l.isArabic ? 'الطلبات المفتوحة' : 'Open dispatches',
                    value: board == null
                        ? '--'
                        : board.counts.openDispatches.toString(),
                  ),
                  _metricTile(
                    context: context,
                    icon: Icons.badge_outlined,
                    title: l.isArabic ? 'السائقون المتصلون' : 'Online drivers',
                    value: board == null
                        ? '--'
                        : board.counts.onlineDrivers.toString(),
                  ),
                  _metricTile(
                    context: context,
                    icon: Icons.drive_eta_outlined,
                    title: l.isArabic ? 'الرحلات النشطة' : 'Active rides',
                    value: board == null
                        ? '--'
                        : board.counts.activeTrips.toString(),
                  ),
                  _metricTile(
                    context: context,
                    icon: Icons.near_me_outlined,
                    title: l.isArabic ? 'في الطريق' : 'En route',
                    value: board == null
                        ? '--'
                        : board.counts.enRouteTrips.toString(),
                  ),
                  _metricTile(
                    context: context,
                    icon: Icons.payments_outlined,
                    title: l.isArabic ? 'حالات دفع فاشلة' : 'Payment failures',
                    value: board == null
                        ? '--'
                        : board.counts.paymentFailures.toString(),
                  ),
                  if (summary != null) ...[
                    _metricTile(
                      context: context,
                      icon: Icons.assignment_ind_outlined,
                      title:
                          l.isArabic ? 'سائقون على رحلات' : 'Drivers on trips',
                      value: summary.activeDriverCount.toString(),
                    ),
                    _metricTile(
                      context: context,
                      icon: Icons.person_search_outlined,
                      title: l.isArabic
                          ? 'سائقون متاحون الآن'
                          : 'Idle online drivers',
                      value: summary.idleOnlineDrivers.toString(),
                    ),
                    _metricTile(
                      context: context,
                      icon: Icons.speed_outlined,
                      title:
                          l.isArabic ? 'إشغال السائقين' : 'Driver utilization',
                      value: _formatPercentFromBps(
                        summary.driverUtilizationBps,
                      ),
                    ),
                    _metricTile(
                      context: context,
                      icon: Icons.warning_outlined,
                      title: l.isArabic
                          ? 'فجوة سعة الإسناد'
                          : 'Dispatch capacity gap',
                      value: summary.capacityGapDispatches.toString(),
                    ),
                  ],
                  if (caseQueue != null) ...[
                    _metricTile(
                      context: context,
                      icon: Icons.support_agent_outlined,
                      title: l.isArabic ? 'القضايا المفتوحة' : 'Open cases',
                      value: caseQueue.totals.openCases.toString(),
                    ),
                    _metricTile(
                      context: context,
                      icon: Icons.crisis_alert_outlined,
                      title: l.isArabic ? 'حالات حرجة' : 'Critical cases',
                      value: caseQueue.totals.criticalCases.toString(),
                    ),
                  ],
                  if (documentQueue != null) ...[
                    _metricTile(
                      context: context,
                      icon: Icons.badge_outlined,
                      title: l.isArabic
                          ? 'وثائق قيد المراجعة'
                          : 'Pending documents',
                      value: documentQueue.totals.pendingDocuments.toString(),
                    ),
                    _metricTile(
                      context: context,
                      icon: Icons.gpp_maybe_outlined,
                      title: l.isArabic ? 'سائقون محجوبون' : 'Blocked drivers',
                      value: documentQueue.totals.blockedDrivers.toString(),
                    ),
                  ],
                  if (financeQueue != null) ...[
                    _metricTile(
                      context: context,
                      icon: Icons.pending_actions_outlined,
                      title: l.isArabic
                          ? 'طلبات السحب المعلقة'
                          : 'Pending payout requests',
                      value: financeQueue.totals.pendingRequests.toString(),
                    ),
                    _metricTile(
                      context: context,
                      icon: Icons.savings_outlined,
                      title: l.isArabic
                          ? 'قيمة السحب المعلقة'
                          : 'Pending payout value',
                      value:
                          '${fmtCents(financeQueue.totals.pendingAmountMinorUnits)} SYP',
                    ),
                  ],
                  if (summary != null) ...[
                    _metricTile(
                      context: context,
                      icon: Icons.request_page_outlined,
                      title: l.isArabic
                          ? 'قيمة الطلبات المفتوحة'
                          : 'Open dispatch value',
                      value:
                          '${fmtCents(summary.openDispatchValueMinorUnits)} SYP',
                    ),
                    _metricTile(
                      context: context,
                      icon: Icons.attach_money_outlined,
                      title: l.isArabic
                          ? 'إيراد الرحلات المكتملة/24س'
                          : 'Completed revenue / 24h',
                      value:
                          '${fmtCents(summary.completedTodayValueMinorUnits)} SYP',
                    ),
                    _metricTile(
                      context: context,
                      icon: Icons.timeline_outlined,
                      title: l.isArabic
                          ? 'متوسط ETA المفتوح/النشط'
                          : 'Avg ETA open/active',
                      value:
                          '${(summary.avgOpenEtaSeconds / 60).ceil()} / ${(summary.avgActiveEtaSeconds / 60).ceil()} min',
                    ),
                  ],
                  if (bootstrap != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic ? 'منطق المنصة' : 'Platform logic',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l.isArabic
                                  ? 'الإصدار ${bootstrap.version} • ${bootstrap.serviceClasses.length} فئات خدمة • ${bootstrap.operatorRoles.length} أدوار تشغيل'
                                  : 'Version ${bootstrap.version} • ${bootstrap.serviceClasses.length} service classes • ${bootstrap.operatorRoles.length} operator roles',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l.isArabic
                                  ? 'العرض الخرائطي: ${bootstrap.mapDisplayStack}\nالتوجيه/ETA: ${bootstrap.mapRoutingStack}'
                                  : 'Display map: ${bootstrap.mapDisplayStack}\nRouting/ETA: ${bootstrap.mapRoutingStack}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (pricingPolicies != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic
                                  ? 'سياسات التسعير'
                                  : 'Pricing policies',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (pricingPolicies.policies.isEmpty)
                              Text(
                                l.isArabic
                                    ? 'لا توجد سياسات تسعير محمّلة.'
                                    : 'No pricing policies loaded.',
                              )
                            else
                              ...pricingPolicies.policies.map(
                                (policy) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading:
                                      const Icon(Icons.price_change_outlined),
                                  title: Text(
                                    _rideClassLabel(
                                      policy.rideClass,
                                      isArabic: l.isArabic,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${l.isArabic ? "أساس" : "Base"} ${fmtCents(policy.baseFareMinorUnits)} • '
                                    '${l.isArabic ? "كم" : "km"} ${fmtCents(policy.perKmMinorUnits)} • '
                                    '${l.isArabic ? "دقيقة" : "min"} ${fmtCents(policy.perMinuteMinorUnits)}\n'
                                    '${l.isArabic ? "رسوم الحجز" : "Booking"} ${fmtCents(policy.bookingFeeMinorUnits)} • '
                                    '${l.isArabic ? "الحد الأدنى" : "Minimum"} ${fmtCents(policy.minimumFareMinorUnits)} • '
                                    '${l.isArabic ? "حصة السائق" : "Driver share"} ${(policy.driverShareBps / 100).toStringAsFixed(0)}%',
                                  ),
                                  trailing: _pricingAllowed
                                      ? FilledButton.tonal(
                                          onPressed: () =>
                                              _editPricingPolicy(policy),
                                          child: Text(
                                            l.isArabic ? 'تعديل' : 'Edit',
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (summary != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic
                                  ? 'جودة التشغيل والمخاطر'
                                  : 'Ops quality and risk',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l.isArabic
                                  ? 'طلبات متأخرة: ${summary.stalledDispatches} • وصولات متأخرة: ${summary.overdueArrivals} • رحلات طويلة: ${summary.longRunningTrips} • تتبع صامت: ${summary.silentTrackingTrips} • فجوات بيانات: ${summary.metadataGaps}'
                                  : 'Stalled dispatches: ${summary.stalledDispatches} • Overdue arrivals: ${summary.overdueArrivals} • Long-running trips: ${summary.longRunningTrips} • Silent tracking: ${summary.silentTrackingTrips} • Metadata gaps: ${summary.metadataGaps}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l.isArabic
                                  ? 'سائقون على رحلات: ${summary.activeDriverCount} • متاحون الآن: ${summary.idleOnlineDrivers} • إشغال: ${_formatPercentFromBps(summary.driverUtilizationBps)} • فجوة سعة: ${summary.capacityGapDispatches}'
                                  : 'Drivers on trips: ${summary.activeDriverCount} • Idle online: ${summary.idleOnlineDrivers} • Utilization: ${_formatPercentFromBps(summary.driverUtilizationBps)} • Capacity gap: ${summary.capacityGapDispatches}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l.isArabic
                                  ? 'رحلات مكتملة آخر 24 ساعة: ${summary.completedTodayCount}'
                                  : 'Completed rides in the last 24h: ${summary.completedTodayCount}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (summary != null && summary.classBreakdown.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic
                                  ? 'مزيج فئات الخدمة'
                                  : 'Service class mix',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...summary.classBreakdown.map(
                              (item) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading: const Icon(Icons.layers_outlined),
                                title: Text(
                                  _rideClassLabel(
                                    item.rideClass,
                                    isArabic: l.isArabic,
                                  ),
                                ),
                                subtitle: Text(
                                  l.isArabic
                                      ? 'مفتوحة ${item.openDispatches} • نشطة ${item.activeTrips} • مكتملة/24س ${item.completedTodayCount}'
                                      : 'Open ${item.openDispatches} • Active ${item.activeTrips} • Completed/24h ${item.completedTodayCount}',
                                ),
                                trailing: Text(
                                  '${fmtCents(item.completedTodayValueMinorUnits)} SYP',
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (summary != null && summary.alerts.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic ? 'تنبيهات حية' : 'Live alerts',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...summary.alerts.map(
                              (alert) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.warning_amber_rounded,
                                  color: _alertColor(context, alert.severity),
                                ),
                                title: Text(alert.title),
                                subtitle: Text(alert.detail),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (caseQueue != null &&
                      _rideOperatorWorkspaceVisible(
                        selectedWorkspace,
                        'cases',
                      ))
                    _buildWorkspaceDesk(
                      context,
                      workspace: 'cases',
                      title: l.isArabic ? 'مكتب القضايا' : 'Case desk',
                      summary: l.isArabic
                          ? 'مفتوحة ${caseQueue.totals.openCases} • حرجة ${caseQueue.totals.criticalCases} • عالية ${caseQueue.totals.highCases}'
                          : 'Open ${caseQueue.totals.openCases} • Critical ${caseQueue.totals.criticalCases} • High ${caseQueue.totals.highCases}',
                      signals: <_RideOperatorWorkspaceSignalData>[
                        _RideOperatorWorkspaceSignalData(
                          id: 'open',
                          label: l.isArabic ? 'مفتوحة' : 'Open',
                          value: '${caseQueue.totals.openCases}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'critical',
                          label: l.isArabic ? 'حرجة' : 'Critical',
                          value: '${caseQueue.totals.criticalCases}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'finance',
                          label: l.isArabic ? 'مالية' : 'Finance',
                          value: '${caseQueue.totals.financeCases}',
                        ),
                      ],
                      sortOptions: _workspaceSortOptions(
                        'cases',
                        isArabic: l.isArabic,
                      ),
                      selectedSort: caseSort,
                      onSortSelected: (sort) => _setWorkspaceSort(
                        'cases',
                        sort,
                      ),
                      isArabic: l.isArabic,
                      body: KeyedSubtree(
                        key: _caseQueueSectionKey,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.isArabic ? 'قائمة القضايا' : 'Case queue',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  l.isArabic
                                      ? 'مالية ${caseQueue.totals.financeCases} • دعم ${caseQueue.totals.supportCases} • امتثال ${caseQueue.totals.complianceCases}'
                                      : 'Finance ${caseQueue.totals.financeCases} • Support ${caseQueue.totals.supportCases} • Compliance ${caseQueue.totals.complianceCases}',
                                ),
                                const SizedBox(height: 10),
                                if (sortedCaseItems.isEmpty)
                                  Text(
                                    l.isArabic
                                        ? 'لا توجد قضايا تشغيل مفتوحة حالياً.'
                                        : 'No open operator cases right now.',
                                  )
                                else
                                  ...sortedCaseItems.map(
                                    (item) => ListTile(
                                      key: ValueKey(
                                        'rideOpsCase_${item.caseId}',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        Icons.assignment_late_outlined,
                                        color: _alertColor(
                                          context,
                                          item.severity,
                                        ),
                                      ),
                                      title: Text(item.title),
                                      subtitle: Text(
                                        '${rideOperatorTripIdLabel(item.rideId, isArabic: l.isArabic)}\n'
                                        '${_caseCategoryLabel(item.category, isArabic: l.isArabic)} • '
                                        '${_statusLabel(item.status, isArabic: l.isArabic)} • '
                                        '${_formatAgeSeconds(item.ageSeconds, isArabic: l.isArabic)}\n'
                                        '${shamellPrivacySafeTextPreview(item.detail, maxChars: 120)}\n'
                                        '${l.isArabic ? "الإجراء" : "Action"}: ${item.suggestedAction}',
                                      ),
                                      trailing: Text(
                                        '${fmtCents(item.fareEstimateMinorUnits)}\nSYP',
                                        textAlign: TextAlign.end,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (supportQueue != null &&
                      _rideOperatorWorkspaceVisible(
                        selectedWorkspace,
                        'support',
                      ))
                    _buildWorkspaceDesk(
                      context,
                      workspace: 'support',
                      title: l.isArabic ? 'مكتب الدعم' : 'Support desk',
                      summary: l.isArabic
                          ? 'مفتوحة ${supportQueue.totals.openTickets} • عاجلة ${supportQueue.totals.urgentTickets}'
                          : 'Open ${supportQueue.totals.openTickets} • Urgent ${supportQueue.totals.urgentTickets}',
                      signals: <_RideOperatorWorkspaceSignalData>[
                        _RideOperatorWorkspaceSignalData(
                          id: 'open',
                          label: l.isArabic ? 'مفتوحة' : 'Open',
                          value: '${supportQueue.totals.openTickets}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'urgent',
                          label: l.isArabic ? 'عاجلة' : 'Urgent',
                          value: '${supportQueue.totals.urgentTickets}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'safety',
                          label: l.isArabic ? 'سلامة' : 'Safety',
                          value: '$safetyTicketCount',
                        ),
                      ],
                      sortOptions: _workspaceSortOptions(
                        'support',
                        isArabic: l.isArabic,
                      ),
                      selectedSort: supportSort,
                      onSortSelected: (sort) => _setWorkspaceSort(
                        'support',
                        sort,
                      ),
                      isArabic: l.isArabic,
                      body: KeyedSubtree(
                        key: _supportQueueSectionKey,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.isArabic ? 'طابور الدعم' : 'Support queue',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  l.isArabic
                                      ? 'مفتوحة ${supportQueue.totals.openTickets} • عاجلة ${supportQueue.totals.urgentTickets}'
                                      : 'Open ${supportQueue.totals.openTickets} • Urgent ${supportQueue.totals.urgentTickets}',
                                ),
                                const SizedBox(height: 10),
                                if (sortedSupportTickets.isEmpty)
                                  Text(
                                    l.isArabic
                                        ? 'لا توجد تذاكر دعم مفتوحة حالياً.'
                                        : 'No open ride support tickets right now.',
                                  )
                                else
                                  ...sortedSupportTickets.map(
                                    (ticket) => ListTile(
                                      key: ValueKey(
                                        'rideOpsSupportTicket_${ticket.ticketId}',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        ticket.category ==
                                                RideSupportTicketCategory.safety
                                            ? Icons.health_and_safety_outlined
                                            : Icons.support_agent_outlined,
                                        color: ticket.category ==
                                                RideSupportTicketCategory.safety
                                            ? Theme.of(context)
                                                .colorScheme
                                                .error
                                            : null,
                                      ),
                                      title: Text(ticket.subject),
                                      subtitle: Text(
                                        '${_supportCategoryLabel(ticket.category, isArabic: l.isArabic)} • ${_supportStatusLabel(ticket.status, isArabic: l.isArabic)}'
                                        '${ticket.rideId == null ? '' : '\n${rideOperatorTripIdLabel(ticket.rideId!, isArabic: l.isArabic)}'}'
                                        '\n${shamellPrivacySafeTextPreview(ticket.body, maxChars: 120)}',
                                      ),
                                      trailing: ticket.isOpen && _supportAllowed
                                          ? FilledButton(
                                              onPressed: () =>
                                                  _resolveSupportTicket(
                                                ticket,
                                              ),
                                              child: Text(
                                                l.isArabic ? 'حل' : 'Resolve',
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (documentQueue != null &&
                      _rideOperatorWorkspaceVisible(
                        selectedWorkspace,
                        'documents',
                      ))
                    _buildWorkspaceDesk(
                      context,
                      workspace: 'documents',
                      title: l.isArabic ? 'مكتب الوثائق' : 'Document desk',
                      summary: l.isArabic
                          ? 'معلقة ${documentQueue.totals.pendingDocuments} • محجوبون ${documentQueue.totals.blockedDrivers} • منتهية ${documentQueue.totals.expiredDocuments}'
                          : 'Pending ${documentQueue.totals.pendingDocuments} • Blocked ${documentQueue.totals.blockedDrivers} • Expired ${documentQueue.totals.expiredDocuments}',
                      signals: <_RideOperatorWorkspaceSignalData>[
                        _RideOperatorWorkspaceSignalData(
                          id: 'pending',
                          label: l.isArabic ? 'معلقة' : 'Pending',
                          value: '${documentQueue.totals.pendingDocuments}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'blocked',
                          label: l.isArabic ? 'محجوبون' : 'Blocked',
                          value: '${documentQueue.totals.blockedDrivers}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'expired',
                          label: l.isArabic ? 'منتهية' : 'Expired',
                          value: '${documentQueue.totals.expiredDocuments}',
                        ),
                      ],
                      sortOptions: _workspaceSortOptions(
                        'documents',
                        isArabic: l.isArabic,
                      ),
                      selectedSort: documentSort,
                      onSortSelected: (sort) => _setWorkspaceSort(
                        'documents',
                        sort,
                      ),
                      isArabic: l.isArabic,
                      body: KeyedSubtree(
                        key: _documentQueueSectionKey,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.isArabic
                                      ? 'طابور الوثائق'
                                      : 'Document queue',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  l.isArabic
                                      ? 'معلّق ${documentQueue.totals.pendingDocuments} • مرفوض ${documentQueue.totals.rejectedDocuments} • منتهي ${documentQueue.totals.expiredDocuments} • سائقون محجوبون ${documentQueue.totals.blockedDrivers}'
                                      : 'Pending ${documentQueue.totals.pendingDocuments} • Rejected ${documentQueue.totals.rejectedDocuments} • Expired ${documentQueue.totals.expiredDocuments} • Blocked drivers ${documentQueue.totals.blockedDrivers}',
                                ),
                                const SizedBox(height: 10),
                                if (sortedDocuments.isEmpty)
                                  Text(
                                    l.isArabic
                                        ? 'لا توجد وثائق بحاجة إلى مراجعة في النافذة الحالية.'
                                        : 'No driver documents require review in the current window.',
                                  )
                                else
                                  ...sortedDocuments.map(
                                    (document) => ListTile(
                                      key: ValueKey(
                                        'rideOpsDocument_${document.documentId ?? document.documentType.name}_${document.driverAccountId ?? 'restricted'}',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.badge_outlined),
                                      title: Text(
                                        _documentTypeLabel(
                                          document.documentType,
                                          isArabic: l.isArabic,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${document.driverAccountId == null ? (l.isArabic ? "هوية السائق مقيّدة" : "Driver identity restricted") : shamellMaskIdentifier(document.driverAccountId!, prefix: 6, suffix: 4)}\n'
                                        '${_documentStatusLabel(document.status, isArabic: l.isArabic)}'
                                        '${document.documentNumberMasked == null ? '' : ' • ${document.documentNumberMasked}'}'
                                        '${document.issuingCountry == null ? '' : ' • ${document.issuingCountry}'}'
                                        '${document.expiresAtIso == null ? '' : '\n${l.isArabic ? "ينتهي" : "Expires"}: ${document.expiresAtIso}'}'
                                        '${document.reviewNote == null ? '' : '\n${shamellPrivacySafeTextPreview(document.reviewNote!, maxChars: 96)}'}',
                                      ),
                                      trailing: document.documentId != null &&
                                              _complianceSensitiveAllowed
                                          ? Wrap(
                                              spacing: 8,
                                              children: [
                                                FilledButton.tonal(
                                                  onPressed: () =>
                                                      _reviewDocument(
                                                    document,
                                                    'reject',
                                                  ),
                                                  child: Text(
                                                    l.isArabic
                                                        ? 'رفض'
                                                        : 'Reject',
                                                  ),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      _reviewDocument(
                                                    document,
                                                    'approve',
                                                  ),
                                                  child: Text(
                                                    l.isArabic
                                                        ? 'اعتماد'
                                                        : 'Approve',
                                                  ),
                                                ),
                                              ],
                                            )
                                          : null,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (financeQueue != null &&
                      _rideOperatorWorkspaceVisible(
                        selectedWorkspace,
                        'payouts',
                      ))
                    _buildWorkspaceDesk(
                      context,
                      workspace: 'payouts',
                      title: l.isArabic ? 'مكتب السحوبات' : 'Payout desk',
                      summary: l.isArabic
                          ? 'معلقة ${financeQueue.totals.pendingRequests} • معتمدة ${financeQueue.totals.approvedRequests} • محجوبة ${financeQueue.totals.blockedRequests}'
                          : 'Pending ${financeQueue.totals.pendingRequests} • Approved ${financeQueue.totals.approvedRequests} • Blocked ${financeQueue.totals.blockedRequests}',
                      signals: <_RideOperatorWorkspaceSignalData>[
                        _RideOperatorWorkspaceSignalData(
                          id: 'pending',
                          label: l.isArabic ? 'معلقة' : 'Pending',
                          value: '${financeQueue.totals.pendingRequests}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'blocked',
                          label: l.isArabic ? 'محجوبة' : 'Blocked',
                          value: '${financeQueue.totals.blockedRequests}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'held',
                          label: l.isArabic ? 'محجوزة' : 'Held',
                          value: '${financeQueue.totals.reservedFeeEvents}',
                        ),
                      ],
                      sortOptions: _workspaceSortOptions(
                        'payouts',
                        isArabic: l.isArabic,
                      ),
                      selectedSort: payoutSort,
                      onSortSelected: (sort) => _setWorkspaceSort(
                        'payouts',
                        sort,
                      ),
                      isArabic: l.isArabic,
                      body: KeyedSubtree(
                        key: _financeQueueSectionKey,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.isArabic ? 'طابور السحب' : 'Payout queue',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  l.isArabic
                                      ? 'معلق ${financeQueue.totals.pendingRequests} • معتمد ${financeQueue.totals.approvedRequests} • محجوب ${financeQueue.totals.blockedRequests}'
                                      : 'Pending ${financeQueue.totals.pendingRequests} • Approved ${financeQueue.totals.approvedRequests} • Blocked ${financeQueue.totals.blockedRequests}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l.isArabic
                                      ? 'الاحتياطي: محجوز ${financeQueue.totals.reservedFeeEvents} • مُفرج ${financeQueue.totals.releasedFeeEvents} • مُسوّى ${financeQueue.totals.settledFeeEvents}'
                                      : 'Reserve events: held ${financeQueue.totals.reservedFeeEvents} • released ${financeQueue.totals.releasedFeeEvents} • settled ${financeQueue.totals.settledFeeEvents}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l.isArabic
                                      ? 'أقدم طلب معلق: ${_formatAgeSeconds(financeQueue.totals.oldestPendingAgeSeconds, isArabic: true)}'
                                      : 'Oldest pending request: ${_formatAgeSeconds(financeQueue.totals.oldestPendingAgeSeconds, isArabic: false)}',
                                ),
                                const SizedBox(height: 10),
                                if (sortedPayoutRequests.isEmpty)
                                  Text(
                                    l.isArabic
                                        ? 'لا توجد طلبات سحب في نافذة المراجعة الحالية.'
                                        : 'No payout requests in the current review window.',
                                  )
                                else
                                  ...sortedPayoutRequests.map(
                                    (request) => ListTile(
                                      key: ValueKey(
                                        'rideOpsPayout_${request.requestId ?? request.createdAtIso}',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.account_balance_wallet_outlined,
                                      ),
                                      title: Text(
                                        '${fmtCents(request.amountMinorUnits)} ${request.currency}',
                                      ),
                                      subtitle: Text(
                                        '${request.requestId == null ? (l.isArabic ? "المعرّفات المالية مقيّدة" : "Sensitive finance identifiers restricted") : shamellMaskIdentifier(request.requestId!, prefix: 6, suffix: 4)}'
                                        '${request.fromWalletId == null || request.toWalletId == null ? '' : '\n${shamellMaskIdentifier(request.fromWalletId!, prefix: 6, suffix: 4)} -> ${shamellMaskIdentifier(request.toWalletId!, prefix: 6, suffix: 4)}'}\n'
                                        '${request.status.name.toUpperCase()} • '
                                        '${_formatAgeSeconds(request.ageSeconds, isArabic: l.isArabic)}',
                                      ),
                                      trailing: request.isPending &&
                                              _financeSensitiveAllowed &&
                                              request.requestId != null &&
                                              ((_financeQueue?.feeWalletId ??
                                                      '')
                                                  .trim()
                                                  .isNotEmpty)
                                          ? FilledButton(
                                              onPressed: () =>
                                                  _approvePayoutRequest(
                                                request,
                                              ),
                                              child: Text(
                                                l.isArabic
                                                    ? 'اعتماد'
                                                    : 'Approve',
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                if (financeQueue
                                    .recentReserveEvents.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    l.isArabic
                                        ? 'آخر حركات الاحتياطي'
                                        : 'Recent reserve events',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...financeQueue.recentReserveEvents.map(
                                    (event) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      leading:
                                          const Icon(Icons.history_rounded),
                                      title: Text(
                                        '${_reserveEventStatusLabel(event.status, isArabic: l.isArabic)} • ${fmtCents(event.amountMinorUnits)} SYP',
                                      ),
                                      subtitle: Text(
                                        '${rideOperatorTripIdLabel(event.rideId, isArabic: l.isArabic)}'
                                        '${event.walletId == null ? '' : '\n${shamellMaskIdentifier(event.walletId!, prefix: 6, suffix: 4)}'}',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Cycle 101 — admin Signups workspace. Only visible
                  // when the BFF returned a non-empty pending queue
                  // for this operator (the `availableWorkspaces` build
                  // gates on `signupQueue.isNotEmpty`).
                  if (signupQueue.isNotEmpty &&
                      _rideOperatorWorkspaceVisible(
                        selectedWorkspace,
                        'signups',
                      ))
                    _buildSignupsWorkspace(
                      context,
                      requests: signupQueue,
                      isArabic: l.isArabic,
                    ),
                  if (focusQuote != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic
                                  ? 'تتبّع حي مرجعي'
                                  : 'Live routing snapshot',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${focusQuote.pickup.displayName}\n-> ${focusQuote.destination.displayName}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l.isArabic
                                  ? 'المسافة ${focusQuote.route.distanceMeters} م • ETA ${(focusQuote.route.etaSeconds / 60).ceil()} د • تأخير ${(focusQuote.route.trafficDelaySeconds / 60).ceil()} د'
                                  : 'Distance ${focusQuote.route.distanceMeters} m • ETA ${(focusQuote.route.etaSeconds / 60).ceil()} min • Delay ${(focusQuote.route.trafficDelaySeconds / 60).ceil()} min',
                            ),
                            if (focusTracking?.latestDriverLocation !=
                                null) ...[
                              const SizedBox(height: 8),
                              Text(
                                l.isArabic
                                    ? 'آخر تتبّع للسائق: ${focusTracking!.latestDriverLocation!.createdAtIso}'
                                    : 'Driver tracking last seen: ${focusTracking!.latestDriverLocation!.createdAtIso}',
                              ),
                              if (focusTracking
                                      .latestDriverLocation!.location !=
                                  null)
                                Text(
                                  'GPS: ${focusTracking.latestDriverLocation!.location!.lat.toStringAsFixed(5)}, '
                                  '${focusTracking.latestDriverLocation!.location!.lon.toStringAsFixed(5)}',
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (board != null &&
                      _rideOperatorWorkspaceVisible(
                        selectedWorkspace,
                        'dispatches',
                      ))
                    _buildWorkspaceDesk(
                      context,
                      workspace: 'dispatches',
                      title: l.isArabic ? 'مكتب الإسناد' : 'Dispatch desk',
                      summary: l.isArabic
                          ? 'طلبات مفتوحة ${board.counts.openDispatches} • رحلات جارية ${board.counts.activeTrips} • في الطريق ${board.counts.enRouteTrips}'
                          : 'Open dispatches ${board.counts.openDispatches} • Active rides ${board.counts.activeTrips} • En route ${board.counts.enRouteTrips}',
                      signals: <_RideOperatorWorkspaceSignalData>[
                        _RideOperatorWorkspaceSignalData(
                          id: 'open',
                          label: l.isArabic ? 'مفتوحة' : 'Open',
                          value: '${board.counts.openDispatches}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'active',
                          label: l.isArabic ? 'جارية' : 'Active',
                          value: '${board.counts.activeTrips}',
                        ),
                        _RideOperatorWorkspaceSignalData(
                          id: 'payment_failures',
                          label: l.isArabic ? 'فشل دفع' : 'Pay fail',
                          value: '${board.counts.paymentFailures}',
                        ),
                      ],
                      sortOptions: _workspaceSortOptions(
                        'dispatches',
                        isArabic: l.isArabic,
                      ),
                      selectedSort: dispatchSort,
                      onSortSelected: (sort) => _setWorkspaceSort(
                        'dispatches',
                        sort,
                      ),
                      isArabic: l.isArabic,
                      body: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeyedSubtree(
                            key: _dispatchesSectionKey,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.isArabic
                                          ? 'الطلبات المفتوحة'
                                          : 'Open dispatches',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    if (sortedOpenDispatches.isEmpty)
                                      Text(
                                        l.isArabic
                                            ? 'لا توجد طلبات مفتوحة حالياً.'
                                            : 'No open dispatches right now.',
                                      )
                                    else
                                      ...sortedOpenDispatches.map(
                                        (trip) => _tripTile(
                                          context: context,
                                          trip: trip,
                                          isArabic: l.isArabic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.isArabic
                                        ? 'الرحلات الجارية'
                                        : 'Active trips',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (sortedActiveTrips.isEmpty)
                                    Text(
                                      l.isArabic
                                          ? 'لا توجد رحلات جارية حالياً.'
                                          : 'No active rides right now.',
                                    )
                                  else
                                    ...sortedActiveTrips.map(
                                      (trip) => _tripTile(
                                        context: context,
                                        trip: trip,
                                        isArabic: l.isArabic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TaxiOperatorControlPanel(
                    openDispatches: board?.counts.openDispatches ?? 0,
                    activeTrips: board?.counts.activeTrips ?? 0,
                    onlineDrivers: onlineDriverCount,
                    idleDrivers: idleDriverCount,
                    staleDrivers: staleDriverCount,
                    noGpsDrivers: noGpsDriverCount,
                    criticalCases: caseQueue?.totals.criticalCases ?? 0,
                    urgentSupportTickets:
                        supportQueue?.totals.urgentTickets ?? 0,
                    pendingDocuments:
                        documentQueue?.totals.pendingDocuments ?? 0,
                    pendingPayouts: financeQueue?.totals.pendingRequests ?? 0,
                    paymentFailures: board?.counts.paymentFailures ?? 0,
                  ),
                  TaxiOperatorRiskPaymentPanel(
                    paymentFailures: board?.counts.paymentFailures ?? 0,
                    pendingPayouts: financeQueue?.totals.pendingRequests ?? 0,
                    criticalCases: caseQueue?.totals.criticalCases ?? 0,
                    openSupportTickets: supportQueue?.totals.openTickets ?? 0,
                    capacityGap: summary?.capacityGapDispatches ?? 0,
                    longRunningTrips: summary?.longRunningTrips ?? 0,
                  ),
                  TaxiOperatorZoneControlPanel(
                    selectedZoneMode: _selectedTaxiZoneMode,
                    activeZones: availableWorkspaces.length,
                    surgeZones: pricingPolicies?.policies.length ?? 0,
                    airportQueue: summary?.capacityGapDispatches ?? 0,
                    eventQueue: summary?.stalledDispatches ?? 0,
                    businessAccounts: financeQueue?.totals.pendingRequests ?? 0,
                    childSeniorRides: safetyTicketCount,
                    disputeCount: caseQueue?.totals.openCases ?? 0,
                    lostFoundCount: lostFoundTicketCount,
                    onZoneModeSelected: (mode) {
                      setState(() {
                        _selectedTaxiZoneMode = mode;
                        _persistOperatorUiState();
                      });
                    },
                  ),
                  TaxiOperatorAssurancePanel(
                    routeDeviationAlerts: summary?.longRunningTrips ?? 0,
                    noShowReviews: summary?.stalledDispatches ?? 0,
                    autoRematchCandidates: autoRematchCandidateCount,
                    expiringDocuments:
                        documentQueue?.totals.pendingDocuments ?? 0,
                    incidentEvidenceBundles: urgentIncidentCount,
                    rideReplayCount: (board?.counts.openDispatches ?? 0) +
                        (board?.counts.activeTrips ?? 0),
                    accessibilityRideCount: safetyTicketCount,
                    packageRideCount: lostFoundTicketCount,
                    promoCreditRequests:
                        financeQueue?.totals.pendingRequests ?? 0,
                    onOpenRideReplay: _openOperatorRideReplay,
                    onPrepareEvidenceBundle: _prepareOperatorEvidenceBundle,
                    onRunAutoRematch: _runOperatorAutoRematch,
                    onOpenDocumentExpiry: _openOperatorDocumentExpiry,
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.isArabic
                                ? 'الدعم والامتثال'
                                : 'Support and compliance',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.isArabic
                                ? 'التنبيهات الحية مفعلة عبر polling قصير. يمكن لاحقاً وصل Push/WebSocket فوق نفس لوحة التشغيل.'
                                : 'Live notifications are active via short polling. Push or WebSocket can later attach to the same operator board.',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.isArabic
                                ? 'هذه النسخة تركّز على البث الحي للطلبات والرحلات، بينما تبقى الأدوات المالية/الامتثال التفصيلية قابلة للإضافة فوق نفس الصلاحيات.'
                                : 'This console focuses on live dispatch and trip supervision; finance, compliance and support workflows can layer on top of the same role model.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _contactSupportByMail,
                                icon: const Icon(Icons.mail_outline),
                                label: Text(l.isArabic
                                    ? 'بريد الدعم'
                                    : 'Email support'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _contactSupportByPhone,
                                icon: const Icon(Icons.phone_outlined),
                                label:
                                    Text(l.isArabic ? 'اتصال' : 'Call support'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Cycle 77 — severity for attention items so the operator can
/// triage at-a-glance. Before this, every chip used the same tinted
/// primaryContainer; a payment-failure row looked identical to the
/// "all clear" row. Now color and icon tint follow the level:
///
///   * [success] — calm green, used for the empty / all-clear state.
///   * [info]    — neutral primaryContainer (the default).
///   * [warning] — amber tint (stale fleet, low-priority queues).
///   * [urgent]  — error tint (payouts pending, payment failures).
enum _RideOperatorAttentionSeverity { success, info, warning, urgent }

class _RideOperatorAttentionItemData {
  final IconData icon;
  final String title;
  final String detail;
  final _RideOperatorAttentionSeverity severity;
  // Cycle 80 — optional navigation target. When set, the item becomes
  // tappable and jumps the console straight to the matching workspace
  // section. Keeps the attention list a true "click-to-act" surface.
  final String? targetWorkspace;
  final GlobalKey? targetSectionKey;

  const _RideOperatorAttentionItemData({
    required this.icon,
    required this.title,
    required this.detail,
    this.severity = _RideOperatorAttentionSeverity.info,
    this.targetWorkspace,
    this.targetSectionKey,
  });
}

class _RideOperatorWorkspaceSignalData {
  final String id;
  final String label;
  final String value;

  const _RideOperatorWorkspaceSignalData({
    required this.id,
    required this.label,
    required this.value,
  });
}

class _RideOperatorWorkspaceSortOptionData {
  final String id;
  final String label;

  const _RideOperatorWorkspaceSortOptionData({
    required this.id,
    required this.label,
  });
}

class _RideOperatorCommandMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RideOperatorCommandMetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: .45,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .50),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: theme.colorScheme.primary.withValues(alpha: .90),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .72),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideOperatorWorkspaceSignalChip extends StatelessWidget {
  final _RideOperatorWorkspaceSignalData signal;

  const _RideOperatorWorkspaceSignalChip({
    super.key,
    required this.signal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            signal.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .72),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            signal.value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RideOperatorAttentionItem extends StatelessWidget {
  final _RideOperatorAttentionItemData item;
  // Cycle 80 — when non-null the tile becomes tappable (InkWell) and
  // routes the operator to the relevant workspace + section.
  final VoidCallback? onTap;

  const _RideOperatorAttentionItem({
    required this.item,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Cycle 77 — severity-driven palette so the operator's eye snaps
    // to the urgent rows first instead of scanning a wall of
    // identically tinted chips. Tones stay subtle (alpha ≤ .32) so
    // we don't overwhelm the rest of the command desk.
    Color bg;
    Color iconColor;
    switch (item.severity) {
      case _RideOperatorAttentionSeverity.urgent:
        bg = theme.colorScheme.errorContainer.withValues(alpha: .42);
        iconColor = theme.colorScheme.error.withValues(alpha: .95);
        break;
      case _RideOperatorAttentionSeverity.warning:
        bg = const Color(0xFFFFA000).withValues(alpha: .18);
        iconColor = const Color(0xFFB45309);
        break;
      case _RideOperatorAttentionSeverity.success:
        bg = const Color(0xFF2E7D32).withValues(alpha: .14);
        iconColor = const Color(0xFF2E7D32);
        break;
      case _RideOperatorAttentionSeverity.info:
        bg = theme.colorScheme.primaryContainer.withValues(alpha: .32);
        iconColor = theme.colorScheme.primary.withValues(alpha: .95);
        break;
    }
    final radius = BorderRadius.circular(14);
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 18,
            color: iconColor,
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
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: .55),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: content,
      );
    }
    return Material(
      color: bg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: double.infinity, child: content),
      ),
    );
  }
}

/// Cycle 101 — single pending-signup card with Approve / Reject
/// buttons. State-bearing so the spinner + outcome SnackBar can
/// render inside one row without re-triggering the parent's poll.
class _RoleSignupAdminCard extends StatefulWidget {
  final RoleSignupRequest request;
  final RoleSignupApi api;
  final bool isArabic;
  final VoidCallback? onReviewed;

  const _RoleSignupAdminCard({
    required this.request,
    required this.api,
    required this.isArabic,
    this.onReviewed,
  });

  @override
  State<_RoleSignupAdminCard> createState() => _RoleSignupAdminCardState();
}

class _RoleSignupAdminCardState extends State<_RoleSignupAdminCard> {
  bool _busy = false;
  String? _error;
  String? _outcomeLabel;

  Future<void> _approve() async {
    unawaited(HapticFeedback.selectionClick());
    await _review(approve: true, notes: null);
  }

  Future<void> _reject() async {
    final reason = await _promptRejectReason();
    if (reason == null) return;
    unawaited(HapticFeedback.selectionClick());
    await _review(approve: false, notes: reason);
  }

  Future<String?> _promptRejectReason() async {
    final controller = TextEditingController();
    final isArabic = widget.isArabic;
    // Cycle 108 — preset reject reasons. Admins can one-tap a common
    // reason rather than type from scratch each time; tap a chip to
    // populate the text field, then optionally append details.
    final presets = isArabic
        ? const <String>[
            'رقم رخصة القيادة غير صالح',
            'بيانات ناقصة في النموذج',
            'رقم الهاتف غير قابل للوصول',
            'يحتاج المزيد من التحقق',
          ]
        : const <String>[
            'License number invalid',
            'Form is missing required details',
            'Phone number unreachable',
            'Needs further verification',
          ];
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(isArabic ? 'سبب الرفض' : 'Rejection reason'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final preset in presets)
                      ActionChip(
                        label: Text(preset),
                        onPressed: () {
                          // Cycle 125 — selection haptic on preset
                          // chips so admins get tactile confirmation
                          // a reason snapped into the text field.
                          unawaited(HapticFeedback.selectionClick());
                          controller.text = preset;
                          controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: preset.length),
                          );
                          setLocalState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 240,
                  maxLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: isArabic
                        ? 'سيراها مقدم الطلب (اختياري)'
                        : 'Shown to the applicant (optional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(isArabic ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(isArabic ? 'رفض' : 'Reject'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _review({required bool approve, String? notes}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = approve
          ? await widget.api
              .adminApprove(requestId: widget.request.id, notes: notes)
          : await widget.api
              .adminReject(requestId: widget.request.id, notes: notes);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outcomeLabel = updated.status;
      });
      // Cycle 122 — surface the outcome via a SnackBar in case the
      // admin scrolled past this card before the parent refresh
      // wipes the row. Always-visible bottom toast > inline outcome
      // that might be off-screen.
      final isArabic = widget.isArabic;
      final isDriver =
          widget.request.requestedRoleId == RoleSignupRoleIds.driver;
      final roleWord = isDriver
          ? (isArabic ? 'سائق' : 'driver')
          : (isArabic ? 'مشغّل' : 'operator');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: approve
              ? const Color(0xFF2E7D32)
              : Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
          content: Text(
            approve
                ? (isArabic
                    ? 'تمت الموافقة على طلب $roleWord'
                    : 'Approved $roleWord signup')
                : (isArabic
                    ? 'تم رفض طلب $roleWord'
                    : 'Rejected $roleWord signup'),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      widget.onReviewed?.call();
    } on RoleSignupApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.detail.isNotEmpty
            ? err.detail
            : (widget.isArabic ? 'فشلت المراجعة' : 'Review failed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.isArabic
            ? 'تعذّر تطبيق المراجعة'
            : 'Could not apply review';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.request;
    final isArabic = widget.isArabic;
    final isDriver = r.requestedRoleId == RoleSignupRoleIds.driver;
    final roleLabel = isDriver
        ? (isArabic ? 'سائق' : 'Driver')
        : (isArabic ? 'مشغّل' : 'Operator');
    // Cycle 120 — animate between form / approved / rejected so the
    // admin's eye registers the outcome rather than a jarring instant
    // swap. AnimatedSwitcher cross-fades with a 250 ms duration; the
    // outcome rows live a few seconds before the parent refresh
    // removes the card altogether.
    final outcomeApproved = _outcomeLabel == 'approved';
    final outcomeRejected = _outcomeLabel == 'rejected';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: outcomeApproved
          ? Padding(
              key: const ValueKey('signup-approved-outcome'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF2E7D32), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isArabic
                          ? 'تمت الموافقة على طلب $roleLabel للحساب ${r.subjectAccountId}'
                          : 'Approved $roleLabel signup for ${r.subjectAccountId}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          : outcomeRejected
              ? Padding(
                  key: const ValueKey('signup-rejected-outcome'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.cancel_rounded,
                          color: theme.colorScheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isArabic
                              ? 'تم رفض طلب $roleLabel للحساب ${r.subjectAccountId}'
                              : 'Rejected $roleLabel signup for ${r.subjectAccountId}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              : _buildFormContent(context, r, isDriver, roleLabel, isArabic),
    );
  }

  Widget _buildFormContent(BuildContext context, RoleSignupRequest r,
      bool isDriver, String roleLabel, bool isArabic) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('signup-pending-form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (isDriver
                        ? theme.colorScheme.primary
                        : const Color(0xFFB45309))
                    .withValues(alpha: .18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                roleLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isDriver
                      ? theme.colorScheme.primary
                      : const Color(0xFFB45309),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                r.profileString('full_name').isNotEmpty
                    ? r.profileString('full_name')
                    : r.subjectAccountId,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              // Cycle 111 — friendly relative timestamp on the admin
              // card, matching the user-side Cycle 106 pattern. Falls
              // back to the raw ISO when parsing fails.
              _relativeSignupTimestamp(r.submittedAt, isArabic: isArabic),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: .60),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Cycle 119 — tap the ID row to copy the subject account id
        // to the clipboard. Admins regularly cross-reference an
        // applicant against support tickets / wallet logs; one tap
        // saves them a long-press select gesture.
        InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            Clipboard.setData(ClipboardData(text: r.subjectAccountId));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 2),
                content: Text(
                  isArabic
                      ? 'تم نسخ معرّف الحساب'
                      : 'Account ID copied to clipboard',
                ),
              ),
            );
          },
          child: Row(
            children: <Widget>[
              Icon(
                Icons.content_copy_rounded,
                size: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: .50),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'ID: ${r.subjectAccountId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (r.profileString('phone').isNotEmpty)
          Text(
            '${isArabic ? "الهاتف" : "Phone"}: ${r.profileString('phone')}',
            style: const TextStyle(fontSize: 13),
          ),
        if (r.profileString('car_plate').isNotEmpty)
          Text(
            '${isArabic ? "اللوحة" : "Plate"}: ${r.profileString('car_plate')}',
            style: const TextStyle(fontSize: 13),
          ),
        if (r.profileString('license_number').isNotEmpty)
          Text(
            '${isArabic ? "رقم الرخصة" : "License"}: ${r.profileString('license_number')}',
            style: const TextStyle(fontSize: 13),
          ),
        if (r.profileString('reason').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${isArabic ? "السبب" : "Reason"}: ${r.profileString('reason')}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _approve,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(isArabic ? 'موافقة' : 'Approve'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _reject,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(isArabic ? 'رفض' : 'Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Cycle 111 — render a signup submission timestamp as a short
/// relative phrase for the operator-console admin card. Kept as a
/// top-level helper so both the card and other surfaces can use it
/// without leaking through the state class.
String _relativeSignupTimestamp(String iso, {required bool isArabic}) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final diff = DateTime.now().toUtc().difference(parsed.toUtc());
  if (diff.isNegative || diff.inSeconds < 45) {
    return isArabic ? 'الآن' : 'just now';
  }
  if (diff.inMinutes < 1) {
    return isArabic ? '${diff.inSeconds} ث' : '${diff.inSeconds}s';
  }
  if (diff.inMinutes < 60) {
    return isArabic ? 'منذ ${diff.inMinutes} د' : '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return isArabic ? 'منذ ${diff.inHours} س' : '${diff.inHours}h ago';
  }
  return isArabic ? 'منذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
}

/// Cycle 154 — top-of-dashboard safety banner. Renders one card
/// per active/acknowledged SOS alert with inline acknowledge +
/// resolve actions. Color: red border when any are still `active`
/// (unclaimed); amber when all are at least acknowledged. The
/// goal is "you cannot miss this when it lands".
class _OperatorSafetyBanner extends StatelessWidget {
  final String? baseUrl;
  final List<SafetyAlert> alerts;
  final bool isArabic;
  final VoidCallback onChanged;

  const _OperatorSafetyBanner({
    required this.baseUrl,
    required this.alerts,
    required this.isArabic,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final anyActive = alerts.any((a) => a.isActive);
    final accent = anyActive
        ? const Color(0xFFD32F2F)
        : const Color(0xFFFB8C00);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accent, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.shield_rounded, color: accent, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isArabic
                          ? 'إنذارات الطوارئ (${alerts.length})'
                          : 'Safety alerts (${alerts.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final alert in alerts.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _SafetyAlertTile(
                    baseUrl: baseUrl,
                    alert: alert,
                    isArabic: isArabic,
                    onChanged: onChanged,
                  ),
                ),
              if (alerts.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    isArabic
                        ? '+ ${alerts.length - 3} إنذارات أخرى في القائمة.'
                        : '+ ${alerts.length - 3} more in the queue.',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyAlertTile extends StatefulWidget {
  final String? baseUrl;
  final SafetyAlert alert;
  final bool isArabic;
  final VoidCallback onChanged;

  const _SafetyAlertTile({
    required this.baseUrl,
    required this.alert,
    required this.isArabic,
    required this.onChanged,
  });

  @override
  State<_SafetyAlertTile> createState() => _SafetyAlertTileState();
}

class _SafetyAlertTileState extends State<_SafetyAlertTile> {
  bool _busy = false;

  Future<void> _acknowledge() async {
    final url = widget.baseUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _busy = true);
    final api = SafetyAlertsApi(baseUrl: url);
    await api.operatorAcknowledge(alertId: widget.alert.id);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
  }

  Future<void> _resolve() async {
    final url = widget.baseUrl;
    if (url == null || url.isEmpty) return;
    final isArabic = widget.isArabic;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArabic ? 'إغلاق الإنذار' : 'Resolve alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(isArabic
                ? 'سجل ملاحظات الإغلاق (اختياري) ثم تأكيد.'
                : 'Optionally record a resolution note before closing.'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: isArabic ? 'ملاحظة' : 'Note',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isArabic ? 'إغلاق' : 'Resolve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final api = SafetyAlertsApi(baseUrl: url);
    await api.operatorResolve(
      alertId: widget.alert.id,
      resolutionNote: controller.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    final alert = widget.alert;
    final isActive = alert.isActive;
    final accent = isActive ? const Color(0xFFD32F2F) : const Color(0xFFFB8C00);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isActive ? Icons.error_rounded : Icons.access_time_rounded,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isArabic
                      ? '${alert.reporterRole == "rider" ? "راكب" : "سائق"} • رحلة ${alert.rideId.substring(0, alert.rideId.length.clamp(0, 8))}…'
                      : '${alert.reporterRole.toUpperCase()} • Trip ${alert.rideId.substring(0, alert.rideId.length.clamp(0, 8))}…',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              Text(
                isActive
                    ? (isArabic ? 'نشط' : 'ACTIVE')
                    : (isArabic ? 'مستلم' : 'ACK'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          if (alert.lastKnownLat != null && alert.lastKnownLon != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                isArabic
                    ? 'الموقع: ${alert.lastKnownLat!.toStringAsFixed(5)}, ${alert.lastKnownLon!.toStringAsFixed(5)}'
                    : 'Location: ${alert.lastKnownLat!.toStringAsFixed(5)}, ${alert.lastKnownLon!.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          if ((alert.note ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                alert.note!,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: <Widget>[
              if (isActive)
                FilledButton.icon(
                  onPressed: _busy ? null : _acknowledge,
                  icon: const Icon(Icons.front_hand_rounded, size: 16),
                  label: Text(isArabic ? 'استلام' : 'Acknowledge'),
                ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _resolve,
                icon: const Icon(Icons.task_alt_rounded, size: 16),
                label: Text(isArabic ? 'إغلاق' : 'Resolve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cycle 144 — passenger-rating chip inside the operator's
/// trip-details sheet. Loads the aggregate lazily via the operator-
/// only endpoint that resolves rider→aggregate server-side without
/// exposing the rider's account_id. Renders three states:
///   - loading (shimmer)
///   - no ratings yet (neutral chip)
///   - rated (★ X.X over N ratings)
class _OperatorTripPassengerRatingBlock extends StatefulWidget {
  final String? baseUrl;
  final String rideId;
  final bool isArabic;

  const _OperatorTripPassengerRatingBlock({
    required this.baseUrl,
    required this.rideId,
    required this.isArabic,
  });

  @override
  State<_OperatorTripPassengerRatingBlock> createState() =>
      _OperatorTripPassengerRatingBlockState();
}

class _OperatorTripPassengerRatingBlockState
    extends State<_OperatorTripPassengerRatingBlock> {
  PassengerRatingAggregate? _aggregate;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final url = widget.baseUrl;
    if (url == null || url.trim().isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final api = PassengerRatingApi(baseUrl: url);
    final agg =
        await api.operatorTripPassengerAggregate(rideId: widget.rideId);
    if (!mounted) return;
    setState(() {
      _aggregate = agg;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    if (_loading) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            isArabic ? 'جاري تحميل تقييم الراكب…' : 'Loading passenger rating…',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      );
    }
    final agg = _aggregate;
    final hasRating = agg != null && agg.ratingCount > 0;
    return Row(
      children: [
        const Icon(Icons.person_pin_rounded,
            size: 18, color: Color(0xFFB8860B)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hasRating
                ? (isArabic
                    ? 'تقييم الراكب ${agg.averageStars.toStringAsFixed(1)} من 5 (${agg.ratingCount} تقييم)'
                    : 'Passenger rating ${agg.averageStars.toStringAsFixed(1)} / 5 (${agg.ratingCount} ratings)')
                : (isArabic
                    ? 'لا توجد تقييمات للراكب بعد'
                    : 'No passenger ratings yet'),
            style: TextStyle(
              fontWeight: hasRating ? FontWeight.w700 : FontWeight.w500,
              color: hasRating
                  ? const Color(0xFFB8860B)
                  : Colors.black54,
            ),
          ),
        ),
      ],
    );
  }
}
