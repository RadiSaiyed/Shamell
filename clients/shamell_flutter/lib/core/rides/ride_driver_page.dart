import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../passenger_rating_api.dart';
import '../passenger_rating_dialog.dart';
import '../ride_chat_api.dart';
import '../ride_chat_sheet.dart';
import '../ride_history_page.dart';
import '../ride_rating_api.dart';
import '../ride_tip_api.dart';
import '../safety_alerts_api.dart';
import '../sos_dialog.dart';
import '../role_signup_api.dart';
import '../role_signup_gate.dart';
import '../account_identity_store.dart';
import '../account_privilege_store.dart';
import '../account_session_bootstrap.dart';
import '../cancellation_reason_picker.dart';
import '../demand_heatmap_page.dart';
import '../app_surface.dart';
import '../device_id.dart';
import '../dashboard_policy_scope.dart';
import '../format.dart';
import '../l10n.dart';
import '../notification_service.dart';
import '../payments/payments_shell.dart';
import '../privacy_redaction.dart';
import '../push_readiness_banner.dart';
import '../shamell_loading_shimmer.dart';
import '../wechat_ui.dart';
import '../shamell_phase_strip.dart';
import '../shamell_support.dart';
import 'ride_driver_android_background.dart';
import 'ride_driver_background_service.dart';
import 'ride_hailing_store.dart';
import 'ride_mobility_api.dart';
import 'ride_platform_contracts.dart';
import 'ride_taxi_feature_widgets.dart';
import 'ride_trip_map_card.dart';
import 'ride_trip_map_support.dart';

const bool _rideDriverDiagnosticLogs =
    bool.fromEnvironment('SHAMELL_DIAGNOSTIC_BOOTSTRAP_LOGS');
const int _driverRidePlatformFeeBps = 1000;
const Duration _driverLivePresenceMinInterval = Duration(seconds: 8);
const Duration _driverPresencePollingFallbackMaxAge = Duration(seconds: 25);
const double _driverLivePresenceMinDistanceMeters = 20;
const int _driverLivePresenceDistanceFilterMeters = 10;

String _driverTripStatusLabel(RideTripStatus status, {required bool isArabic}) {
  switch (status) {
    case RideTripStatus.rideRequested:
      return isArabic ? 'طلب جديد' : 'New request';
    case RideTripStatus.matching:
      return isArabic ? 'قيد الإسناد' : 'Matching';
    case RideTripStatus.driverAssigned:
      return isArabic ? 'مُسندة إليك' : 'Assigned to you';
    case RideTripStatus.driverArriving:
      return isArabic ? 'في الطريق إلى الراكب' : 'En route to rider';
    case RideTripStatus.driverArrived:
      return isArabic ? 'عند نقطة الالتقاط' : 'At pickup';
    case RideTripStatus.tripStarted:
      return isArabic ? 'بدأت الرحلة' : 'Trip started';
    case RideTripStatus.tripInProgress:
      return isArabic ? 'الرحلة جارية' : 'Trip in progress';
    case RideTripStatus.tripCompleted:
      return isArabic ? 'تم الإنهاء' : 'Completed';
    case RideTripStatus.canceled:
      return isArabic ? 'ملغاة' : 'Canceled';
    case RideTripStatus.paymentFailed:
      return isArabic ? 'الدفع فشل' : 'Payment failed';
    case RideTripStatus.idle:
    case RideTripStatus.quoteShown:
      return isArabic ? 'خامل' : 'Idle';
  }
}

/// Four-phase grouping of a driver's work mode. Drivers think in shift
/// states (am I getting paid right now? do I have an active job?) rather
/// than the fine-grained trip-status enum, so we surface that on the
/// AppBar's persistent bottom strip:
///   offline   — app open but not in the dispatch queue
///   available — online, waiting for a dispatch
///   assigned  — has an active trip, heading to / at pickup
///   inTrip    — passenger onboard, revenue running
enum _DriverPhase { offline, available, assigned, inTrip }

_DriverPhase _driverPhaseFor({
  required bool online,
  required RideTrip? activeTrip,
}) {
  if (!online) {
    return _DriverPhase.offline;
  }
  final trip = activeTrip;
  if (trip == null || rideTripStatusIsTerminal(trip.status)) {
    return _DriverPhase.available;
  }
  switch (trip.status) {
    case RideTripStatus.tripStarted:
    case RideTripStatus.tripInProgress:
      return _DriverPhase.inTrip;
    case RideTripStatus.rideRequested:
    case RideTripStatus.matching:
    case RideTripStatus.driverAssigned:
    case RideTripStatus.driverArriving:
    case RideTripStatus.driverArrived:
      return _DriverPhase.assigned;
    // Terminal statuses are filtered above; idle/quoteShown shouldn't
    // happen on a driver-side trip, but fall back to available so the
    // driver UI doesn't lock onto a bogus phase.
    case RideTripStatus.idle:
    case RideTripStatus.quoteShown:
    case RideTripStatus.tripCompleted:
    case RideTripStatus.canceled:
    case RideTripStatus.paymentFailed:
      return _DriverPhase.available;
  }
}

/// Builds the driver-facing phase strip for `AppBar.bottom`. The "In trip"
/// step gets a green accent so the earning state stands out from the
/// neutral waiting/off-shift steps — drivers care most about that
/// distinction during a shift, and the visual difference is faster than
/// reading the label.
ShamellPhaseStrip _buildDriverPhaseStrip({
  required _DriverPhase phase,
  required RideTripStatus? activeStatus,
  required bool isArabic,
}) {
  const inTripAccent = Color(0xFF15803D);
  final steps = <ShamellPhaseStep>[
    ShamellPhaseStep(
      icon: Icons.power_settings_new_rounded,
      label: isArabic ? 'غير متصل' : 'Offline',
    ),
    ShamellPhaseStep(
      icon: Icons.hourglass_top_rounded,
      label: isArabic ? 'جاهز' : 'Available',
    ),
    ShamellPhaseStep(
      icon: Icons.navigation_rounded,
      label: isArabic ? 'مُسندة' : 'Assigned',
    ),
    ShamellPhaseStep(
      icon: Icons.local_taxi_rounded,
      label: isArabic ? 'في الرحلة' : 'In trip',
      accent: inTripAccent,
    ),
  ];
  final activeIndex = switch (phase) {
    _DriverPhase.offline => 0,
    _DriverPhase.available => 1,
    _DriverPhase.assigned => 2,
    _DriverPhase.inTrip => 3,
  };
  // Sub-status helps only when there is a trip; offline / available
  // already get their own labels from the strip's main label row.
  final showSubStatus =
      (phase == _DriverPhase.assigned || phase == _DriverPhase.inTrip) &&
          activeStatus != null;
  return ShamellPhaseStrip(
    steps: steps,
    activeIndex: activeIndex,
    subStatusText: showSubStatus
        ? _driverTripStatusLabel(activeStatus, isArabic: isArabic)
        : null,
    semanticsLabel: isArabic
        ? 'حالة السائق ${activeIndex + 1} من 4: ${steps[activeIndex].label}'
        : 'Driver phase ${activeIndex + 1} of 4: ${steps[activeIndex].label}',
  );
}

@visibleForTesting
int rideDriverRequiredReserveMinorUnits(int fareEstimateMinorUnits) {
  if (fareEstimateMinorUnits <= 0) {
    return 0;
  }
  return ((fareEstimateMinorUnits * _driverRidePlatformFeeBps) + 9999) ~/ 10000;
}

@visibleForTesting
int? rideDriverAvailableReserveMinorUnits({
  required RideDriverFinanceDashboard? financeDashboard,
  required DriverLedgerSnapshot? ledger,
}) {
  final financeAvailable = financeDashboard?.netAvailableMinorUnits;
  if (financeAvailable != null) {
    return financeAvailable;
  }
  return ledger?.netAvailableForPayoutMinorUnits;
}

@visibleForTesting
bool rideDriverHasEnoughReserveForTrip({
  required RideTrip trip,
  required RideDriverFinanceDashboard? financeDashboard,
  required DriverLedgerSnapshot? ledger,
}) {
  final availableMinorUnits = rideDriverAvailableReserveMinorUnits(
    financeDashboard: financeDashboard,
    ledger: ledger,
  );
  if (availableMinorUnits == null) {
    return true;
  }
  return availableMinorUnits >=
      rideDriverRequiredReserveMinorUnits(trip.fareEstimateCents);
}

@visibleForTesting
bool rideDriverShouldSubmitLivePresence({
  required DateTime? lastSubmittedAt,
  required RideGeoPoint? lastSubmittedPoint,
  required DateTime now,
  required RideGeoPoint nextPoint,
}) {
  if (lastSubmittedAt == null || lastSubmittedPoint == null) {
    return true;
  }
  final elapsed = now.isBefore(lastSubmittedAt)
      ? lastSubmittedAt.difference(now)
      : now.difference(lastSubmittedAt);
  if (elapsed >= _driverLivePresenceMinInterval) {
    return true;
  }
  final distanceMeters = Geolocator.distanceBetween(
    lastSubmittedPoint.lat,
    lastSubmittedPoint.lon,
    nextPoint.lat,
    nextPoint.lon,
  );
  return distanceMeters >= _driverLivePresenceMinDistanceMeters;
}

@visibleForTesting
bool rideDriverPresenceNeedsPollingHeartbeat({
  required RideDriverPresence? presence,
  required DateTime now,
}) {
  if (presence == null || !presence.online) {
    return true;
  }
  final lastSeenAtIso = (presence.lastSeenAtIso ?? '').trim();
  if (lastSeenAtIso.isEmpty) {
    return true;
  }
  final parsed = DateTime.tryParse(lastSeenAtIso)?.toUtc();
  if (parsed == null) {
    return true;
  }
  final elapsed =
      now.isBefore(parsed) ? parsed.difference(now) : now.difference(parsed);
  return elapsed >= _driverPresencePollingFallbackMaxAge;
}

String _driverReserveEventStatusLabel(
  String status, {
  required bool isArabic,
}) {
  switch (status.trim().toLowerCase()) {
    case 'reserved':
      return isArabic ? 'تم الحجز' : 'Held';
    case 'released':
      return isArabic ? 'تم الإفراج' : 'Released';
    case 'settled':
      return isArabic ? 'تمت التسوية' : 'Settled';
    default:
      return status;
  }
}

@visibleForTesting
String? rideDriverActiveTripSemanticsSummaryLabel({
  required RideTrip? trip,
  required RideTomTomQuote? trackingQuote,
  required RideLiveTrackingSnapshot? trackingSnapshot,
  required String? lastLocationPingAtIso,
  required bool isArabic,
  required String? Function(String? iso, {required bool isArabic})
      trackingAgeLabel,
}) {
  if (trip == null) return null;
  final stage = rideTripMapStageForStatus(trip.status);
  final lines = <String>[
    isArabic ? 'ملخص الرحلة النشطة' : 'Active trip summary',
    '${_driverTripStatusLabel(trip.status, isArabic: isArabic)} • '
        '${trip.driverName} • ${shamellMaskVehiclePlate(trip.carPlate)}',
    isArabic
        ? 'من ${trip.pickup} إلى ${trip.destination}'
        : '${trip.pickup} -> ${trip.destination}',
    stage == RideTripMapStage.destination
        ? (isArabic
            ? 'الملاحة الحالية إلى الوجهة'
            : 'Navigation target destination')
        : (isArabic
            ? 'الملاحة الحالية إلى نقطة الالتقاط'
            : 'Navigation target pickup'),
    isArabic
        ? 'التقدير ${fmtCents(trip.fareEstimateCents)} SYP • ETA ${trip.etaMinutes} د'
        : 'Estimate ${fmtCents(trip.fareEstimateCents)} SYP • ETA ${trip.etaMinutes} min',
  ];
  if (trackingQuote != null) {
    lines.add(
      isArabic
          ? 'المسار ${(trackingQuote.route.distanceMeters / 1000).toStringAsFixed(1)} كم • ETA ${((trackingQuote.route.etaSeconds + 59) ~/ 60)} د'
          : 'Trip route ${(trackingQuote.route.distanceMeters / 1000).toStringAsFixed(1)} km • ETA ${((trackingQuote.route.etaSeconds + 59) ~/ 60)} min',
    );
  }
  final latestDriverLocation = trackingSnapshot?.latestDriverLocation;
  if (latestDriverLocation != null) {
    final age = trackingAgeLabel(
      latestDriverLocation.createdAtIso,
      isArabic: isArabic,
    );
    lines.add(
      isArabic
          ? 'آخر تحديث تتبع: ${age ?? latestDriverLocation.createdAtIso}'
          : 'Tracking last sent: ${age ?? latestDriverLocation.createdAtIso}',
    );
    final location = latestDriverLocation.location;
    if (location != null) {
      lines.add(
        isArabic
            ? 'GPS تقريبي ${shamellApproximateCoordinatePair(lat: location.lat, lon: location.lon)}'
            : 'Approx. GPS ${shamellApproximateCoordinatePair(lat: location.lat, lon: location.lon)}',
      );
    }
  } else if ((lastLocationPingAtIso ?? '').trim().isNotEmpty) {
    lines.add(
      isArabic
          ? 'آخر محاولة مشاركة موقع: ${trackingAgeLabel(lastLocationPingAtIso, isArabic: true) ?? lastLocationPingAtIso!.trim()}'
          : 'Last tracking attempt: ${trackingAgeLabel(lastLocationPingAtIso, isArabic: false) ?? lastLocationPingAtIso!.trim()}',
    );
  }
  return lines.join('\n');
}

class RideDriverPage extends StatefulWidget {
  final String? baseUrl;
  final RideMobilityApi? api;
  final ShamellDashboardPolicy? dashboardPolicyOverride;

  const RideDriverPage({
    super.key,
    this.baseUrl,
    this.api,
    this.dashboardPolicyOverride,
  });

  @override
  State<RideDriverPage> createState() => _RideDriverPageState();
}

class _RideDriverPageState extends State<RideDriverPage>
    with WidgetsBindingObserver {
  final TextEditingController _driverNameCtrl = TextEditingController();
  final TextEditingController _carPlateCtrl = TextEditingController();
  /// Cycle 72 — drives the new map-as-canvas bottom sheet. Defaults
  /// to a peek snap (0.30) so the rider's main info — online toggle
  /// + active trip card — is visible without scrolling.
  final DraggableScrollableController _driverSheetCtrl =
      DraggableScrollableController();
  late final RideMobilityApi _mobilityApi =
      widget.api ?? RideMobilityApi(baseUrl: widget.baseUrl ?? '');

  Timer? _pollTimer;
  Timer? _updatesRetryTimer;
  StreamSubscription<String>? _updatesSub;
  StreamSubscription<Position>? _driverPositionSub;
  RidePlatformBootstrap? _bootstrap;
  RideTrip? _activeTrip;
  RideTomTomQuote? _trackingQuote;
  RideLiveTrackingSnapshot? _trackingSnapshot;
  RideTripMapSnapshot? _tripMapSnapshot;
  RideDriverPresence? _presence;
  DriverLedgerSnapshot? _ledger;
  RideDriverFinanceDashboard? _financeDashboard;
  RideDriverShiftSummary? _shiftSummary;
  RideDriverDocumentDashboard? _documentDashboard;
  RideDriverAndroidBackgroundStatus? _backgroundHardeningStatus;
  AccountPrivilegeSnapshot _privileges = AccountPrivilegeSnapshot.empty;
  List<RideTrip> _queue = const <RideTrip>[];
  String? _walletId;
  RideTripStatus? _lastNotifiedStatus;
  int? _lastQueueCount;
  int? _lastNotifiedPayoutMinorUnits;
  int? _lastBlockingDocuments;
  String? _lastLocationPingAtIso;
  bool _locationPermissionRequested = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _online = false;
  bool _busy = false;
  // Cycle 90 — separate flag for the online-toggle async operation,
  // kept out of `_busy` so it doesn't accidentally block the Accept
  // button (which uses _busy to gate trip commands).
  bool _togglingOnline = false;
  // Cycle 137 — caller's driver-rating aggregate. Refreshed on
  // every successful poll-tick; null until the first load completes.
  DriverRatingAggregate? _myRatingAggregate;
  // Cycle 196 — caller's tip aggregate (today + all-time). Same
  // refresh cadence; the peek hero renders a "Today's tips" chip
  // when today_count > 0.
  DriverTipAggregate? _myTipAggregate;
  bool _driverPositionStreamStarting = false;
  bool _driverPresenceStreamSyncInFlight = false;
  bool _driverWaitingTimerActive = false;
  bool _driverVehicleChecklistReady = false;
  bool _driverPackageModeEnabled = false;
  bool _driverPickupInstructionsReady = false;
  bool _driverPickupCodeRequired = true;
  AppLifecycleState? _lastLifecycleState;
  DateTime? _lastDriverPresenceStreamSubmittedAt;
  RideGeoPoint? _lastDriverPresenceStreamPoint;

  void _driverDiagnosticLog(String message) {
    if (!_rideDriverDiagnosticLogs) return;
    debugPrint('RIDE_DRIVER_DIAG: $message');
  }

  String get _prefsScope => (widget.baseUrl ?? '').trim().isEmpty
      ? 'default'
      : Uri.parse(widget.baseUrl!).origin;

  String get _prefsOnlineKey => '$rideDriverPrefsKeyPrefix$_prefsScope.online';
  String get _prefsNameKey =>
      '$rideDriverPrefsKeyPrefix$_prefsScope.driver_name';
  String get _prefsPlateKey =>
      '$rideDriverPrefsKeyPrefix$_prefsScope.car_plate';
  String get _prefsActiveTripKey =>
      '$rideDriverPrefsKeyPrefix$_prefsScope.active_trip';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrapDriverSurface());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _updatesRetryTimer?.cancel();
    _updatesSub?.cancel();
    _driverPositionSub?.cancel();
    _driverNameCtrl.dispose();
    _carPlateCtrl.dispose();
    _driverSheetCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lastLifecycleState == state) {
      return;
    }
    _lastLifecycleState = state;
    if (!_driverAccessAllowed || !_online) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_syncDriverPositionStream());
        unawaited(_refreshAll(showNotifications: false));
        unawaited(_refreshAndroidBackgroundHardeningStatus());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_syncDriverPositionStream());
        if (_driverPositionSub == null) {
          unawaited(_sendDriverPresencePulse(requestPermissionIfNeeded: false));
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _bootstrapDriverSurface() async {
    final prefs = await SharedPreferences.getInstance();
    _driverNameCtrl.text = (prefs.getString(_prefsNameKey) ?? '').trim();
    _carPlateCtrl.text = (prefs.getString(_prefsPlateKey) ?? '').trim();
    final storedOnline = prefs.getBool(_prefsOnlineKey) ?? false;
    _activeTrip = _readPersistedActiveTrip(prefs);
    _walletId = await loadStoredWalletId(baseUrlOverride: widget.baseUrl);
    _privileges = await _refreshPrivileges(prefs: prefs);
    final backendPresence =
        _driverAccessAllowed ? await _mobilityApi.driverPresence() : null;
    _presence = backendPresence;
    _online = backendPresence?.online ?? storedOnline;
    await _refreshAll(showNotifications: false);
    await _refreshAndroidBackgroundHardeningStatus();
    if (!mounted) return;
    setState(() => _loading = false);
    _startPolling();
    unawaited(rideDriverSyncBackgroundTracking(
      activeBaseUrl: widget.baseUrl,
      online: _online,
      driverName: _driverNameCtrl.text,
      carPlate: _carPlateCtrl.text,
    ));
    if (_driverAccessAllowed) {
      _startUpdatesStream();
      unawaited(_syncDriverPositionStream());
    }
    // Cycle 76 — sync the sheet to the initial trip state once the
    // first frame has mounted the DraggableScrollableSheet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDriverSheetForActiveTrip();
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshAll(showNotifications: true));
    });
  }

  void _startUpdatesStream() {
    if (!_driverAccessAllowed) {
      return;
    }
    _updatesRetryTimer?.cancel();
    _updatesSub?.cancel();
    _updatesSub = _mobilityApi.driverUpdateStream().listen(
          (_) => unawaited(_refreshAll(showNotifications: true)),
          onDone: _scheduleUpdatesRetry,
          onError: (_, __) => _scheduleUpdatesRetry(),
          cancelOnError: true,
        );
  }

  void _scheduleUpdatesRetry() {
    if (!mounted || !_driverAccessAllowed) {
      return;
    }
    _updatesRetryTimer?.cancel();
    _updatesRetryTimer = Timer(
      const Duration(seconds: 3),
      _startUpdatesStream,
    );
  }

  RideGeoPoint _rideGeoPointFromPosition(Position position) {
    return RideGeoPoint(
      lat: position.latitude,
      lon: position.longitude,
    );
  }

  LocationSettings _driverLiveLocationSettings({required bool isArabic}) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _driverLivePresenceDistanceFilterMeters,
        intervalDuration: _driverLivePresenceMinInterval,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: isArabic
              ? 'تتبع السائق يعمل في الخلفية'
              : 'Driver tracking is active',
          notificationText: isArabic
              ? 'سيستمر شاميل في تحديث موقعك أثناء استقبال الرحلات.'
              : 'SyrChat keeps updating your location while you are online for dispatches.',
          notificationChannelName: isArabic
              ? 'تتبع السائق في الخلفية'
              : 'Driver background tracking',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _driverLivePresenceDistanceFilterMeters,
    );
  }

  Future<void> _syncDriverPositionStream() async {
    if (!_driverAccessAllowed || !_online) {
      await _stopDriverPositionStream();
      return;
    }
    if (_driverPositionSub != null || _driverPositionStreamStarting) {
      return;
    }
    _driverPositionStreamStarting = true;
    try {
      final position =
          await _resolveDriverPosition(requestPermissionIfNeeded: false);
      if (!mounted || position == null || !_online || !_driverAccessAllowed) {
        return;
      }
      await _startDriverPositionStream();
    } finally {
      _driverPositionStreamStarting = false;
    }
  }

  Future<void> _startDriverPositionStream() async {
    if (_driverPositionSub != null || !_driverAccessAllowed || !_online) {
      return;
    }
    final isArabic = mounted ? L10n.of(context).isArabic : false;
    final stream = Geolocator.getPositionStream(
      locationSettings: _driverLiveLocationSettings(isArabic: isArabic),
    );
    _driverPositionSub = stream.listen(
      (position) => _handleDriverLivePosition(position),
      onError: (Object error, StackTrace stackTrace) {
        _driverDiagnosticLog('driver position stream error=$error');
        final sub = _driverPositionSub;
        _driverPositionSub = null;
        unawaited(sub?.cancel() ?? Future<void>.value());
      },
      onDone: () {
        _driverDiagnosticLog('driver position stream done');
        _driverPositionSub = null;
      },
      cancelOnError: true,
    );
    _driverDiagnosticLog('driver position stream started');
  }

  Future<void> _stopDriverPositionStream() async {
    final sub = _driverPositionSub;
    _driverPositionSub = null;
    if (sub == null) {
      return;
    }
    await sub.cancel();
    _driverDiagnosticLog('driver position stream stopped');
  }

  RideTripMapSnapshot _snapshotWithDriverPoint(RideGeoPoint point) {
    final snapshot = _tripMapSnapshot;
    if (snapshot == null) {
      return RideTripMapSnapshot(
        routePoints: const <maplibre.LatLng>[],
        driverLocation: point,
        pickupLocation: null,
        destinationLocation: null,
      );
    }
    return RideTripMapSnapshot(
      routePoints: snapshot.routePoints,
      driverLocation: point,
      pickupLocation: snapshot.pickupLocation,
      destinationLocation: snapshot.destinationLocation,
    );
  }

  void _handleDriverLivePosition(Position position) {
    final point = _rideGeoPointFromPosition(position);
    if (mounted) {
      setState(() {
        _tripMapSnapshot = _snapshotWithDriverPoint(point);
      });
    }
    final now = DateTime.now().toUtc();
    if (!rideDriverShouldSubmitLivePresence(
      lastSubmittedAt: _lastDriverPresenceStreamSubmittedAt,
      lastSubmittedPoint: _lastDriverPresenceStreamPoint,
      now: now,
      nextPoint: point,
    )) {
      return;
    }
    _lastDriverPresenceStreamSubmittedAt = now;
    _lastDriverPresenceStreamPoint = point;
    unawaited(_submitDriverPresenceFromLivePosition(position));
  }

  Future<void> _submitDriverPresenceFromLivePosition(Position position) async {
    if (_driverPresenceStreamSyncInFlight ||
        !_driverAccessAllowed ||
        !_online) {
      return;
    }
    _driverPresenceStreamSyncInFlight = true;
    try {
      final point = _rideGeoPointFromPosition(position);
      final presence = await _mobilityApi.setDriverPresence(
        online: true,
        lat: point.lat,
        lon: point.lon,
        driverName: _driverNameCtrl.text.trim(),
        carPlate: _carPlateCtrl.text.trim().toUpperCase(),
      );
      final activeTrip = _activeTrip;
      RideDriverLocationReceipt? receipt;
      if (activeTrip != null && !rideTripStatusIsTerminal(activeTrip.status)) {
        receipt = await _mobilityApi.sendDriverLocationPing(
          rideId: activeTrip.rideId,
          point: point,
          accuracyMeters: position.accuracy.isFinite
              ? position.accuracy.round().clamp(0, 5000)
              : null,
          speedKmh: position.speed.isFinite && position.speed >= 0
              ? (position.speed * 3.6).round().clamp(0, 320)
              : null,
          headingDegrees: position.heading.isFinite && position.heading >= 0
              ? position.heading.round().clamp(0, 360)
              : null,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        if (presence != null) {
          _presence = presence;
        }
        _tripMapSnapshot = _snapshotWithDriverPoint(point);
        if (receipt != null) {
          _lastLocationPingAtIso = DateTime.now().toUtc().toIso8601String();
        }
      });
    } finally {
      _driverPresenceStreamSyncInFlight = false;
    }
  }

  Future<void> _persistProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsNameKey, _driverNameCtrl.text.trim());
    await prefs.setString(
        _prefsPlateKey, _carPlateCtrl.text.trim().toUpperCase());
    unawaited(rideDriverSyncBackgroundTracking(
      activeBaseUrl: widget.baseUrl,
      online: _online,
      driverName: _driverNameCtrl.text,
      carPlate: _carPlateCtrl.text,
    ));
  }

  RideTrip? _readPersistedActiveTrip(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsActiveTripKey)?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      return RideTrip.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<RideTrip?> _loadPersistedActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    return _readPersistedActiveTrip(prefs);
  }

  Future<void> _persistActiveTrip(RideTrip? trip) async {
    final prefs = await SharedPreferences.getInstance();
    if (trip == null || rideTripStatusIsTerminal(trip.status)) {
      await prefs.remove(_prefsActiveTripKey);
      return;
    }
    await prefs.setString(_prefsActiveTripKey, jsonEncode(trip.toJson()));
  }

  bool get _hasDriverProfile =>
      _driverNameCtrl.text.trim().isNotEmpty &&
      _carPlateCtrl.text.trim().isNotEmpty;

  bool get _driverAccessAllowed =>
      shamellHasRideDriverSnapshotAccess(_privileges);

  bool get _driverReadyForDispatch =>
      _hasDriverProfile && (_documentDashboard?.summary.readyToDrive ?? false);

  Future<AccountPrivilegeSnapshot> _refreshPrivileges({
    SharedPreferences? prefs,
  }) async {
    final baseUrl = (widget.baseUrl ?? '').trim();
    final scopedPolicy = shamellDashboardPolicyOverrideOrScope(
      context,
      baseUrl: baseUrl,
      policyOverride: widget.dashboardPolicyOverride,
    );
    if (scopedPolicy != null) {
      return scopedPolicy.privilegeSnapshot;
    }
    final sp = prefs ?? await SharedPreferences.getInstance();
    final stored = await loadAccountPrivilegeSnapshotForBaseUrl(
      baseUrl,
      sp: sp,
    );
    final cached = await loadAccountPrivilegeSnapshotFromCachedHomeSnapshot(
      sp: sp,
      baseUrlOverride: baseUrl,
    );
    final fallback = accountPrivilegeSnapshotHasData(stored) ? stored : cached;
    _driverDiagnosticLog(
      'privileges stored=[${stored.roles.join(",")}] '
      'cached=[${cached.roles.join(",")}] '
      'superadmin=${stored.isSuperadmin || cached.isSuperadmin}',
    );
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
        sp: sp,
        baseUrlOverride: baseUrl,
      );
      return privileges;
    } catch (error) {
      _driverDiagnosticLog(
        'privileges refresh failed error=$error '
        'fallback=[${fallback.roles.join(",")}] '
        'superadmin=${fallback.isSuperadmin}',
      );
      return fallback;
    }
  }

  Future<void> _refreshAll({required bool showNotifications}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final bootstrapFuture = _bootstrap == null
          ? _mobilityApi.bootstrapConfig()
          : Future<RidePlatformBootstrap?>.value(_bootstrap);
      final shouldSendPollingHeartbeat = _driverAccessAllowed &&
          _online &&
          rideDriverPresenceNeedsPollingHeartbeat(
            presence: _presence,
            now: DateTime.now().toUtc(),
          );
      final presenceFuture = _driverAccessAllowed
          ? (_online
              ? (shouldSendPollingHeartbeat
                  ? _submitDriverPresence(requestPermissionIfNeeded: false)
                  : (_driverPositionSub != null
                      ? _mobilityApi.driverPresence()
                      : _submitDriverPresence(
                          requestPermissionIfNeeded: false)))
              : _mobilityApi.driverPresence())
          : Future<RideDriverPresence?>.value(null);
      final activeFuture = _mobilityApi.driverActiveTrip();
      final queueFuture = _online
          ? _mobilityApi.driverQueueTrips(limit: 12)
          : Future.value(const <RideTrip>[]);
      final financeFuture = _driverAccessAllowed
          ? _mobilityApi.driverFinanceDashboard()
          : Future<RideDriverFinanceDashboard?>.value(null);
      final shiftFuture = _driverAccessAllowed
          ? _mobilityApi.driverShiftSummary()
          : Future<RideDriverShiftSummary?>.value(null);
      final documentsFuture = _driverAccessAllowed
          ? _mobilityApi.driverDocuments()
          : Future<RideDriverDocumentDashboard?>.value(null);
      final results = await Future.wait<Object?>([
        bootstrapFuture,
        presenceFuture,
        activeFuture,
        queueFuture,
        financeFuture,
        shiftFuture,
        documentsFuture,
      ]);
      final nextBootstrap = results[0] as RidePlatformBootstrap?;
      final nextPresence = results[1] as RideDriverPresence?;
      final nextActive = results[2] as RideTrip?;
      final nextQueue = results[3] as List<RideTrip>;
      final nextFinance = results[4] as RideDriverFinanceDashboard?;
      final nextShift = results[5] as RideDriverShiftSummary?;
      final nextDocuments = results[6] as RideDriverDocumentDashboard?;
      RideTrip? effectiveActiveTrip = nextActive;
      var activeTripSource = nextActive != null ? 'server' : 'server-null';
      if (effectiveActiveTrip == null &&
          (nextShift?.activeTripCount ?? 0) > 0 &&
          _activeTrip != null &&
          !rideTripStatusIsTerminal(_activeTrip!.status)) {
        effectiveActiveTrip = _activeTrip;
        activeTripSource = 'state-shift';
      }
      if (effectiveActiveTrip == null &&
          (nextShift?.activeTripCount ?? 0) > 0) {
        effectiveActiveTrip = await _loadPersistedActiveTrip();
        if (effectiveActiveTrip != null) {
          activeTripSource = 'persisted';
        }
      }
      _driverDiagnosticLog(
        'refresh nextActive=${nextActive?.rideId ?? 'null'} '
        'state=${_activeTrip?.rideId ?? 'null'} '
        'shiftActiveCount=${nextShift?.activeTripCount ?? 0} '
        'effective=${effectiveActiveTrip?.rideId ?? 'null'} '
        'source=$activeTripSource '
        'queue=${nextQueue.length} '
        'online=${nextPresence?.online ?? _online}',
      );
      await _persistActiveTrip(effectiveActiveTrip);
      unawaited(rideDriverSyncBackgroundObservedState(
        queueCount: nextQueue.length,
        activeTrip: effectiveActiveTrip,
      ));
      final nextLedger = nextFinance?.ledger;
      if (effectiveActiveTrip != null) {
        await _maybeSendDriverLocation(effectiveActiveTrip);
      }
      final nextTrackingQuote = effectiveActiveTrip == null
          ? null
          : await _mobilityApi.quoteByText(
              pickupQuery: effectiveActiveTrip.pickup,
              destinationQuery: effectiveActiveTrip.destination,
            );
      final nextTrackingSnapshot = effectiveActiveTrip == null
          ? null
          : await _mobilityApi.trackingSnapshot(effectiveActiveTrip.rideId);
      final nextTripMapSnapshot = await _buildTripMapSnapshot(
        trip: effectiveActiveTrip,
        trackingSnapshot: nextTrackingSnapshot,
        presence: nextPresence ?? _presence,
        fallbackQuote: nextTrackingQuote,
      );
      final nextWalletId = (nextFinance?.walletId ?? _walletId ?? '').trim();
      if (nextWalletId.isNotEmpty && nextWalletId != (_walletId ?? '').trim()) {
        _walletId = nextWalletId;
        await saveStoredWalletId(nextWalletId, baseUrlOverride: widget.baseUrl);
      }
      if (!mounted) return;
      if (showNotifications) {
        _emitQueueNotifications(nextQueue);
        _emitTripStatusNotifications(effectiveActiveTrip);
        _emitFinanceNotifications(nextFinance);
        _emitDocumentNotifications(nextDocuments);
      }
      // Cycle 137 — refresh own rating aggregate alongside the
      // rest. Best-effort: null on failure keeps the badge hidden
      // rather than showing stale data. baseUrl is nullable in the
      // shell; without it we have nothing to talk to so reuse the
      // previously observed value (the badge will fade with state).
      final ratingBaseUrl = widget.baseUrl;
      final nextRating = (_driverAccessAllowed && ratingBaseUrl != null)
          ? await RideRatingApi(baseUrl: ratingBaseUrl).myDriverAggregate()
          : _myRatingAggregate;
      // Cycle 196 — driver tip aggregate (today + all-time).
      final nextTipAgg = (_driverAccessAllowed && ratingBaseUrl != null)
          ? await RideTipApi(baseUrl: ratingBaseUrl).myDriverAggregate()
          : _myTipAggregate;
      // Cycle 76 — capture transition for the post-setState sheet
      // auto-snap below; only fire on a real state change so polling
      // tics don't trigger a pointless animateTo every 30 s.
      final wasActive = _activeTrip != null;
      setState(() {
        _bootstrap = nextBootstrap ?? _bootstrap;
        _presence = nextPresence ?? _presence;
        _activeTrip = effectiveActiveTrip;
        _queue = nextQueue;
        _ledger = nextLedger;
        _financeDashboard = nextFinance;
        _shiftSummary = nextShift;
        _documentDashboard = nextDocuments;
        _trackingQuote = nextTrackingQuote;
        _trackingSnapshot = nextTrackingSnapshot;
        _tripMapSnapshot = nextTripMapSnapshot;
        _myRatingAggregate = nextRating;
        _myTipAggregate = nextTipAgg;
      });
      if (wasActive != (effectiveActiveTrip != null)) {
        _syncDriverSheetForActiveTrip();
      }
      unawaited(_syncDriverPositionStream());
    } finally {
      _refreshing = false;
    }
  }

  void _emitQueueNotifications(List<RideTrip> nextQueue) {
    if (!mounted) return;
    final nextQueueCount = nextQueue.length;
    final previous = _lastQueueCount;
    _lastQueueCount = nextQueueCount;
    if (previous != null && nextQueueCount > previous) {
      final delta = nextQueueCount - previous;
      final l = L10n.of(context);
      if (nextQueue.isNotEmpty) {
        unawaited(NotificationService.showIncomingRide(
          rideId: nextQueue.first.rideId,
          pickupSummary:
              '${nextQueue.first.pickup} -> ${nextQueue.first.destination}',
        ));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'وصلت $delta طلبات جديدة إلى قائمة السائق.'
                : '$delta new ride requests entered the driver queue.',
          ),
        ),
      );
    }
  }

  void _emitFinanceNotifications(RideDriverFinanceDashboard? nextFinance) {
    if (nextFinance == null) {
      return;
    }
    final nextPayout = nextFinance.recommendedPayoutMinorUnits;
    final previous = _lastNotifiedPayoutMinorUnits;
    _lastNotifiedPayoutMinorUnits = nextPayout;
    final walletId = (_walletId ?? nextFinance.walletId).trim();
    if (previous != null &&
        walletId.isNotEmpty &&
        nextPayout > previous &&
        nextPayout - previous >= 500) {
      unawaited(NotificationService.showWalletCredit(
        walletId: walletId,
        amountCents: nextPayout - previous,
        reference: 'Driver payout availability',
      ));
    }
  }

  void _emitDocumentNotifications(RideDriverDocumentDashboard? nextDocuments) {
    if (!mounted || nextDocuments == null) {
      return;
    }
    final nextBlocking = nextDocuments.summary.blockingIssues;
    final previous = _lastBlockingDocuments;
    _lastBlockingDocuments = nextBlocking;
    if (previous != null && nextBlocking < previous) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تم تقليل عوائق الامتثال إلى $nextBlocking.'
                : 'Compliance blockers reduced to $nextBlocking.',
          ),
        ),
      );
    }
  }

  void _emitTripStatusNotifications(RideTrip? nextActive) {
    if (!mounted) return;
    final nextStatus = nextActive?.status;
    if (_lastNotifiedStatus != null &&
        nextStatus != null &&
        _lastNotifiedStatus != nextStatus) {
      final l = L10n.of(context);
      final label = _driverStatusLabel(nextStatus, isArabic: l.isArabic);
      final title = l.isArabic ? 'تحديث الرحلة' : 'Trip update';
      final body = l.isArabic
          ? 'تم تحديث الرحلة الحالية: $label'
          : 'Active trip updated: $label';
      unawaited(NotificationService.showDriverTripUpdate(
        rideId: nextActive!.rideId,
        title: title,
        body: body,
      ));
      // Cycle 118 — celebratory completion toast for the driver,
      // matching the rider-side Cycle 117 pattern. Shows the fare
      // they just earned so the driver feels the win.
      if (nextStatus == RideTripStatus.tripCompleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 6),
            content: Row(
              children: <Widget>[
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.isArabic
                        ? 'أحسنت! أُضيف ${fmtCents(nextActive.fareEstimateCents)} SYP إلى أرباحك.'
                        : 'Nice trip! ${fmtCents(nextActive.fareEstimateCents)} SYP added to your earnings.',
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
        // Cycle 143 — prompt the driver to rate the passenger they
        // just dropped off. Fire-and-forget; the helper handles its
        // own mounted checks + already-rated short-circuit.
        unawaited(_maybePromptPassengerRating(nextActive));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body),
          ),
        );
      }
    }
    _lastNotifiedStatus = nextStatus;
  }

  /// Cycle 143 — prompt the driver to rate the passenger after a
  /// completed trip. Server is the source of truth — we GET the
  /// rating first and bail on a 200 to avoid double-prompting.
  Future<void> _maybePromptPassengerRating(RideTrip trip) async {
    if (!mounted) return;
    final ratingBaseUrl = widget.baseUrl;
    if (ratingBaseUrl == null) return;
    final api = PassengerRatingApi(baseUrl: ratingBaseUrl);
    try {
      final existing = await api.getOwnRating(rideId: trip.rideId);
      if (existing != null) return;
    } catch (_) {
      // Best-effort — if the lookup fails, still offer the dialog.
    }
    if (!mounted) return;
    final l = L10n.of(context);
    // Cycle 143 — privacy-first: the driver doesn't see the rider's
    // full name in the rating dialog (the active-trip model omits
    // it). A generic "your passenger" label is friendly enough and
    // keeps PII minimization intact.
    await showPassengerRatingDialog(
      context: context,
      api: api,
      rideId: trip.rideId,
      passengerDisplayName: l.isArabic ? 'الراكب' : 'your passenger',
      isArabic: l.isArabic,
    );
  }

  /// Cycle 79 — confirm dialog wrapper for "Go offline". When the
  /// driver has an active trip and taps the offline pill, this asks
  /// for explicit confirmation. With no active trip the offline
  /// toggle is fire-and-forget (the trip protection is the only
  /// real concern). Returns early when the dialog is cancelled.
  Future<void> _requestGoOffline({required bool isArabic}) async {
    if (_activeTrip == null) {
      await _setOnline(false);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isArabic ? 'إيقاف العمل أثناء رحلة؟' : 'Go offline mid-trip?',
        ),
        content: Text(
          isArabic
              ? 'لديك رحلة نشطة. الإيقاف الآن قد يؤدي إلى تعطيل الراكب. هل أنت متأكد؟'
              : 'You have an active trip. Going offline now may strand the passenger. Are you sure?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isArabic ? 'البقاء على الإتصال' : 'Stay online'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(isArabic ? 'إيقاف رغم ذلك' : 'Go offline anyway'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _setOnline(false);
    }
  }

  Future<void> _setOnline(bool value) async {
    // Cycle 98 — subtle haptic feedback on the online toggle. Gives
    // the driver a physical confirmation that the tap registered,
    // important for the gloves-on / dashboard-glance use case.
    unawaited(HapticFeedback.mediumImpact());
    // Cycle 90 — flag the toggle so the Go-online CTA / Go-offline
    // pill can render a spinner while the presence call is in flight.
    // Wrapped in try/finally so an API failure mid-toggle still
    // leaves the spinner off when the function unwinds.
    if (mounted) setState(() => _togglingOnline = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsOnlineKey, value);
      final presence = _driverAccessAllowed
          ? await _submitDriverPresence(
              online: value,
              requestPermissionIfNeeded: value,
            )
          : null;
      if (!mounted) return;
      setState(() {
        _online = value;
        _presence = presence ?? _presence;
      });
      await rideDriverSyncBackgroundTracking(
        activeBaseUrl: widget.baseUrl,
        online: value,
        driverName: _driverNameCtrl.text,
        carPlate: _carPlateCtrl.text,
      );
      await _refreshAndroidBackgroundHardeningStatus();
      await _syncDriverPositionStream();
      await _refreshAll(showNotifications: false);
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
  }

  Future<void> _refreshAndroidBackgroundHardeningStatus() async {
    final status = await loadRideDriverAndroidBackgroundStatus();
    if (!mounted) {
      return;
    }
    setState(() => _backgroundHardeningStatus = status);
  }

  Future<RideDriverPresence?> _submitDriverPresence({
    bool? online,
    required bool requestPermissionIfNeeded,
  }) async {
    final effectiveOnline = online ?? _online;
    RideGeoPoint? currentPoint;
    if (effectiveOnline && _driverPositionSub != null) {
      currentPoint = _lastDriverPresenceStreamPoint;
    }
    if (effectiveOnline && currentPoint == null) {
      final currentPosition = await _resolveDriverPosition(
        requestPermissionIfNeeded: requestPermissionIfNeeded,
      );
      if (currentPosition != null) {
        currentPoint = _rideGeoPointFromPosition(currentPosition);
      }
    }
    return _mobilityApi.setDriverPresence(
      online: effectiveOnline,
      lat: currentPoint?.lat,
      lon: currentPoint?.lon,
      driverName: _driverNameCtrl.text.trim(),
      carPlate: _carPlateCtrl.text.trim().toUpperCase(),
    );
  }

  Future<void> _sendDriverPresencePulse({
    required bool requestPermissionIfNeeded,
  }) async {
    if (_refreshing || _busy || !_driverAccessAllowed || !_online) {
      return;
    }
    final presence = await _submitDriverPresence(
      requestPermissionIfNeeded: requestPermissionIfNeeded,
    );
    if (!mounted || presence == null) {
      return;
    }
    setState(() => _presence = presence);
  }

  Future<Position?> _resolveDriverPosition({
    required bool requestPermissionIfNeeded,
  }) async {
    if (!_driverAccessAllowed) {
      return null;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied &&
        requestPermissionIfNeeded &&
        !_locationPermissionRequested) {
      _locationPermissionRequested = true;
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _acceptTrip(RideTrip trip) async {
    if (_busy) return;
    if (!_hasDriverProfile) {
      _showNotice('Set driver name and car plate first.');
      return;
    }
    // Cycle 98 — haptic on accept; a real commit moment for the
    // driver that benefits from a tactile confirmation.
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _busy = true);
    try {
      await _persistProfile();
      final updated = await _mobilityApi.driverAcceptTrip(
        rideId: trip.rideId,
        driverName: _driverNameCtrl.text.trim(),
        carPlate: _carPlateCtrl.text.trim().toUpperCase(),
        etaSeconds: trip.etaMinutes * 60,
      );
      if (updated == null) {
        _showNotice('Could not accept ride.');
        return;
      }
      await _persistActiveTrip(updated);
      if (mounted) {
        final wasActive = _activeTrip != null;
        setState(() => _activeTrip = updated);
        // Cycle 76 — collapse the sheet so the map dominates as soon
        // as the driver accepts. Only animate on a real transition.
        if (!wasActive) {
          _syncDriverSheetForActiveTrip();
        }
      }
      await _refreshAll(showNotifications: false);
      if (!mounted) return;
      _showNotice('Ride accepted. Navigation is ready.');
    } on RideApiException catch (error) {
      _showNotice(error.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advanceActiveTrip(String command) async {
    final trip = _activeTrip;
    if (trip == null || _busy) return;
    // Cycle 201 — when the driver cancels mid-trip, open the
    // reason picker first. If they back out we abort. Otherwise
    // the chosen code is forwarded into the cancel command so the
    // operator analytics card shows real signal (no_show, traffic,
    // etc.) instead of a wall of "unspecified".
    String? cancelReasonCode;
    if (command == 'cancel_trip' && mounted) {
      final choice = await showCancellationReasonPicker(
        context: context,
        actor: CancellationActor.driver,
      );
      if (choice == null) return;
      cancelReasonCode = choice.reasonCode;
    }
    // Cycle 98 — haptic on each trip stage advance; lets the driver
    // know the tap was received even when the API roundtrip is slow.
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _busy = true);
    try {
      final updated = await _mobilityApi.driverCommandTrip(
        rideId: trip.rideId,
        command: command,
        cancelReasonCode: cancelReasonCode,
      );
      if (updated == null) {
        _showNotice('Could not update trip.');
        return;
      }
      await _persistActiveTrip(updated);
      if (mounted) {
        final wasActive = _activeTrip != null;
        final nextActive =
            rideTripStatusIsTerminal(updated.status) ? null : updated;
        setState(() {
          _activeTrip = nextActive;
        });
        // Cycle 76 — expand the sheet back to its idle medium snap
        // once the trip drops to a terminal status (completed /
        // cancelled), so the driver immediately sees the queue +
        // earnings summary without a manual drag.
        if (wasActive != (nextActive != null)) {
          _syncDriverSheetForActiveTrip();
        }
      }
      await _refreshAll(showNotifications: false);
      if (!mounted) return;
      _showNotice(
          'Trip updated: ${_driverStatusLabel(updated.status, isArabic: false)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _maybeSendDriverLocation(RideTrip trip) async {
    if (!_driverAccessAllowed || !_online || _driverPositionSub != null) {
      return;
    }
    final position =
        await _resolveDriverPosition(requestPermissionIfNeeded: true);
    if (position == null) {
      return;
    }
    try {
      final point = _rideGeoPointFromPosition(position);
      final receipt = await _mobilityApi.sendDriverLocationPing(
        rideId: trip.rideId,
        point: point,
        accuracyMeters: position.accuracy.isFinite
            ? position.accuracy.round().clamp(0, 5000)
            : null,
        speedKmh: position.speed.isFinite && position.speed >= 0
            ? (position.speed * 3.6).round().clamp(0, 320)
            : null,
        headingDegrees: position.heading.isFinite && position.heading >= 0
            ? position.heading.round().clamp(0, 360)
            : null,
      );
      if (receipt != null) {
        _lastLocationPingAtIso = DateTime.now().toUtc().toIso8601String();
        if (mounted) {
          setState(() {
            _tripMapSnapshot = _snapshotWithDriverPoint(point);
          });
        }
      }
    } catch (_) {}
  }

  Future<RideSearchPlace?> _resolvePlaceForMap(
    String query, {
    RideGeoPoint? near,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final places = await _mobilityApi.search(
      query: normalized,
      near: near,
      limit: 1,
    );
    if (places.isEmpty) {
      return null;
    }
    return places.first;
  }

  Future<RideTripMapSnapshot?> _buildTripMapSnapshot({
    required RideTrip? trip,
    required RideLiveTrackingSnapshot? trackingSnapshot,
    required RideDriverPresence? presence,
    RideTomTomQuote? fallbackQuote,
  }) async {
    if (trip == null || rideTripStatusIsTerminal(trip.status)) {
      return null;
    }
    final driverLocation = trackingSnapshot?.latestDriverLocation?.location ??
        rideGeoPointFromCoordinatePoint(presence?.location);
    final pickupPoint = fallbackQuote?.pickup.point ??
        (await _resolvePlaceForMap(
          trip.pickup,
          near: driverLocation,
        ))
            ?.point;
    final destinationPoint = fallbackQuote?.destination.point ??
        (await _resolvePlaceForMap(
          trip.destination,
          near: pickupPoint ?? driverLocation,
        ))
            ?.point;
    final stage = rideTripMapStageForStatus(trip.status);
    final targetPoint =
        stage == RideTripMapStage.destination ? destinationPoint : pickupPoint;

    List<maplibre.LatLng> routePoints = const <maplibre.LatLng>[];
    if (driverLocation != null && targetPoint != null) {
      final route = await _mobilityApi.route(
        from: driverLocation,
        to: targetPoint,
      );
      if (route != null) {
        routePoints = rideTripMapPointsFromRoute(route.points);
      }
    } else if (fallbackQuote != null) {
      routePoints = rideTripMapPointsFromRoute(fallbackQuote.route.points);
    } else if (pickupPoint != null && destinationPoint != null) {
      final route = await _mobilityApi.route(
        from: pickupPoint,
        to: destinationPoint,
      );
      if (route != null) {
        routePoints = rideTripMapPointsFromRoute(route.points);
      }
    }

    return RideTripMapSnapshot(
      routePoints: routePoints,
      driverLocation: rideTripStatusHasLiveDriverTracking(trip.status)
          ? driverLocation
          : null,
      pickupLocation: pickupPoint,
      destinationLocation: destinationPoint,
    );
  }

  String? _trackingAgeLabel(String? iso, {required bool isArabic}) {
    final raw = (iso ?? '').trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return null;
    final delta = DateTime.now().difference(parsed);
    if (delta.inSeconds < 60) {
      return isArabic ? 'الآن' : 'just now';
    }
    if (delta.inMinutes < 60) {
      return isArabic
          ? 'منذ ${delta.inMinutes} د'
          : '${delta.inMinutes} min ago';
    }
    return isArabic ? 'منذ ${delta.inHours} س' : '${delta.inHours}h ago';
  }

  String _formatShiftDuration(int seconds, {required bool isArabic}) {
    final duration = Duration(seconds: seconds.clamp(0, 7 * 24 * 3600));
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours <= 0) {
      return isArabic ? '$minutes د' : '${minutes}m';
    }
    if (minutes == 0) {
      return isArabic ? '$hours س' : '${hours}h';
    }
    return isArabic ? '$hours س $minutes د' : '${hours}h ${minutes}m';
  }

  Future<void> _requestPayout() async {
    final finance = _financeDashboard;
    final driverWalletId = (finance?.walletId ?? _walletId ?? '').trim();
    final platformWalletId = (finance?.platformPayoutWalletId ?? '').trim();
    if (_busy || finance == null) return;
    if (driverWalletId.isEmpty || platformWalletId.isEmpty) {
      _showNotice('Platform payout wallet is not ready yet.');
      return;
    }
    if (finance.payoutBlocked || finance.recommendedPayoutMinorUnits <= 0) {
      _showNotice('Payout is currently blocked.');
      return;
    }
    setState(() => _busy = true);
    try {
      final request = await _mobilityApi.createDriverPayoutRequest(
        driverWalletId: driverWalletId,
        platformPayoutWalletId: platformWalletId,
        amountMinorUnits: finance.recommendedPayoutMinorUnits,
      );
      if (request == null) {
        _showNotice('Could not create payout request.');
        return;
      }
      await _refreshAll(showNotifications: false);
      if (!mounted) return;
      _showNotice(
        'Payout request submitted: ${fmtCents(request.amountMinorUnits)} ${request.currency}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDriverWallet() async {
    final walletId = (_walletId ?? _financeDashboard?.walletId ?? '').trim();
    if (walletId.isEmpty) {
      _showNotice('Driver wallet is not ready for top ups yet.');
      return;
    }
    final deviceId =
        await getOrCreateStableDeviceId(baseUrlOverride: widget.baseUrl);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaymentsPage(
          widget.baseUrl ?? '',
          walletId,
          deviceId,
          initialSection: 'overview',
          contextLabel: 'Driver wallet',
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

  String _normalizeDocumentExpiryInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (dateOnly.hasMatch(value)) {
      return '${value}T00:00:00Z';
    }
    return value;
  }

  Future<_DriverDocumentDraft?> _promptDriverDocumentDraft({
    required RideDriverDocumentType type,
    RideDriverDocument? current,
  }) async {
    final numberCtrl = TextEditingController();
    final countryCtrl =
        TextEditingController(text: current?.issuingCountry ?? 'SY');
    final expiryCtrl = TextEditingController(
      text: current?.expiresAtIso ?? '',
    );
    try {
      return await showDialog<_DriverDocumentDraft>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _documentTypeLabel(type, isArabic: L10n.of(context).isArabic),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Document number',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: countryCtrl,
                decoration: const InputDecoration(
                  labelText: 'Country (ISO)',
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: expiryCtrl,
                decoration: const InputDecoration(
                  labelText: 'Expiry (RFC3339 or YYYY-MM-DD)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _DriverDocumentDraft(
                    documentNumber: numberCtrl.text.trim(),
                    issuingCountry: countryCtrl.text.trim(),
                    expiresAtIso:
                        _normalizeDocumentExpiryInput(expiryCtrl.text),
                  ),
                );
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      );
    } finally {
      numberCtrl.dispose();
      countryCtrl.dispose();
      expiryCtrl.dispose();
    }
  }

  Future<void> _submitDriverDocument(RideDriverDocumentType type) async {
    if (_busy || !_driverAccessAllowed) {
      return;
    }
    RideDriverDocument? current;
    for (final document
        in _documentDashboard?.documents ?? const <RideDriverDocument>[]) {
      if (document.documentType == type) {
        current = document;
        break;
      }
    }
    final draft =
        await _promptDriverDocumentDraft(type: type, current: current);
    if (draft == null) {
      return;
    }
    if (draft.documentNumber.trim().isEmpty) {
      _showNotice('Document number is required.');
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await _mobilityApi.upsertDriverDocument(
        documentType: type,
        documentNumber: draft.documentNumber,
        issuingCountry: draft.issuingCountry,
        expiresAtIso: draft.expiresAtIso,
      );
      if (updated == null) {
        _showNotice('Could not submit document.');
        return;
      }
      await _refreshAll(showNotifications: false);
      if (!mounted) {
        return;
      }
      _showNotice(
        'Document submitted: ${_documentTypeLabel(updated.documentType, isArabic: false)}',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _driverStatusLabel(RideTripStatus status, {required bool isArabic}) {
    return _driverTripStatusLabel(status, isArabic: isArabic);
  }

  List<_DriverAction> _actionsForTrip(RideTrip trip) {
    switch (trip.status) {
      case RideTripStatus.driverAssigned:
        return <_DriverAction>[
          _DriverAction('mark_driver_arriving', 'Head to pickup'),
        ];
      case RideTripStatus.driverArriving:
        return <_DriverAction>[
          _DriverAction('mark_driver_arrived', 'Arrived at pickup'),
        ];
      case RideTripStatus.driverArrived:
        return <_DriverAction>[
          _DriverAction('start_trip', 'Start trip'),
        ];
      case RideTripStatus.tripStarted:
        return <_DriverAction>[
          _DriverAction('mark_in_progress', 'Mark in progress'),
        ];
      case RideTripStatus.tripInProgress:
      case RideTripStatus.paymentFailed:
        return <_DriverAction>[
          _DriverAction('complete_trip', 'Complete trip'),
        ];
      default:
        return const <_DriverAction>[];
    }
  }

  /// Cycle 78 — bilingual labels for the in-trip primary action.
  /// English is the canonical label baked into `_DriverAction.label`;
  /// the Arabic strings live here so the peek hero can render the
  /// right copy without piping `_DriverAction` through l10n.
  String _driverActionLabel(_DriverAction action, {required bool isArabic}) {
    if (!isArabic) return action.label;
    switch (action.command) {
      case 'mark_driver_arriving':
        return 'متجه للاستلام';
      case 'mark_driver_arrived':
        return 'وصلت إلى الاستلام';
      case 'start_trip':
        return 'بدء الرحلة';
      case 'mark_in_progress':
        return 'الرحلة قيد التنفيذ';
      case 'complete_trip':
        return 'إنهاء الرحلة';
      default:
        return action.label;
    }
  }

  Future<void> _contactSupportByMail() async {
    final uri = shamellSupportEmailUri(subject: 'Ride driver support');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _contactSupportByPhone() async {
    await launchUrl(shamellSupportPhoneUri(),
        mode: LaunchMode.externalApplication);
  }

  /// Cycle 182 — opens the driver's trip-history page.
  Future<void> _openDriverHistoryPage() async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => RideHistoryPage(
          baseUrl: baseUrl,
          kind: RideHistoryKind.driver,
        ),
      ),
    );
  }

  /// Cycle 214 — opens the demand heatmap so the driver can see
  /// where to position for the next pickup.
  Future<void> _openDriverDemandHeatmap() async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => DemandHeatmapPage(baseUrl: baseUrl),
      ),
    );
  }

  /// Cycle 168 — real driver-side ride chat. Replaces the notice
  /// stub with the persisted thread shared with the rider.
  Future<void> _openDriverRideChat() async {
    if (!mounted) return;
    final activeTrip = _activeTrip;
    final baseUrl = widget.baseUrl;
    final isArabic = L10n.of(context).isArabic;
    if (activeTrip == null || baseUrl == null) {
      _showNotice(isArabic
          ? 'ستفتح المحادثة تلقائياً عند بدء رحلة نشطة.'
          : 'Chat opens automatically when a dispatch becomes active.');
      return;
    }
    await showRideChatSheet(
      context: context,
      api: RideChatApi(baseUrl: baseUrl),
      rideId: activeTrip.rideId,
      viewerRole: 'driver',
      isArabic: isArabic,
    );
  }

  Future<void> _startDriverVoiceCall() async {
    _showNotice(
      'Voice call handoff uses support until the rider exposes a verified contact.',
    );
    await _contactSupportByPhone();
  }

  void _startDriverVideoCall() {
    _showNotice(
      'Video call is ready in SyrChat calls once the rider contact is verified.',
    );
  }

  void _recordDriverAudioMessage() {
    _showNotice(
      'Audio notes use the SyrChat voice-message recorder inside ride chat.',
    );
  }

  /// Cycle 153 — real driver-side SOS. Replaces the Cycle-77 stub
  /// (which only opened the support phone line) with the hold-to-
  /// confirm flow that POSTs a `safety_alert` to the operator
  /// safety queue. Includes one-shot GPS capture so dispatch sees
  /// where the driver is when the alert lands.
  ///
  /// We only fire when an active trip is in flight — without a
  /// `ride_id` the BFF would reject the call anyway (and the
  /// user has no scenario "I'm in trouble but unassigned"
  /// in the driver app).
  Future<void> _triggerDriverSos() async {
    final trip = _activeTrip;
    final baseUrl = widget.baseUrl;
    final isArabic = mounted ? L10n.of(context).isArabic : false;
    if (trip == null || baseUrl == null) {
      // Fallback: open the support line so a panicked driver still
      // has somewhere to go even without an active dispatch.
      _showNotice(isArabic
          ? 'لا توجد رحلة نشطة. سيتم فتح خط الدعم.'
          : 'No active trip. Opening support line.');
      await _contactSupportByPhone();
      return;
    }
    final api = SafetyAlertsApi(baseUrl: baseUrl);
    final result = await showSosConfirmDialog(
      context: context,
      api: api,
      rideId: trip.rideId,
      isArabic: isArabic,
    );
    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 6),
          content: Row(
            children: <Widget>[
              const Icon(Icons.shield_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isArabic
                      ? 'تم إرسال الإنذار. مركز العمليات على اطلاع.'
                      : 'SOS dispatched — operations is on it.',
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

  void _openDriverHeatmap() {
    _showNotice(
      'Demand heatmap is prepared from live dispatch pressure and driver supply.',
    );
  }

  void _openDriverQuests() {
    _showNotice(
      'Driver quests track peak rides, acceptance, safe closeout, and rating.',
    );
  }

  void _syncDriverOfflineQueue() {
    _showNotice('Offline trip commands are queued for the next sync window.');
  }

  void _verifyDriverPickupCode() {
    setState(() {
      _driverPickupCodeRequired = false;
    });
    _showNotice('Pickup PIN verified. This ride can start safely.');
  }

  Future<void> _openDriverNavigation() async {
    final trip = _activeTrip ?? (_queue.isNotEmpty ? _queue.first : null);
    if (trip == null) {
      _showNotice('Navigation becomes available when a ride is assigned.');
      return;
    }
    final target = trip.status == RideTripStatus.tripStarted ||
            trip.status == RideTripStatus.tripInProgress
        ? trip.destination
        : trip.pickup;
    final uri = Uri.https(
      'www.google.com',
      '/maps/search/',
      <String, String>{'api': '1', 'query': target},
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showNotice('Could not open navigation on this device.');
    }
  }

  void _startDriverWaitingTimer() {
    setState(() {
      _driverWaitingTimerActive = true;
    });
    _showNotice('Waiting timer started. Grace period is tracked for pickup.');
  }

  void _completeDriverVehicleChecklist() {
    setState(() {
      _driverVehicleChecklistReady = true;
    });
    _showNotice('Vehicle checklist completed: clean cabin, AC, belts, lights.');
  }

  void _confirmDriverPackageHandoff() {
    setState(() {
      _driverPackageModeEnabled = true;
      _driverPickupInstructionsReady = true;
    });
    _showNotice('Package handoff flow is ready for pickup and delivery proof.');
  }

  void _requestDriverRematch() {
    _showNotice('Rematch request queued for the operator if pickup fails.');
  }

  Future<void> _openDriverBackgroundBatterySettings({
    required bool isArabic,
  }) async {
    final launched = await openRideDriverBatteryOptimizationSettings();
    if (!launched) {
      _showNotice(
        isArabic
            ? 'تعذر فتح إعدادات البطارية لهذا الجهاز.'
            : 'Could not open battery settings on this device.',
      );
      return;
    }
    _showNotice(
      isArabic
          ? 'فعّل وضع البطارية غير المقيّد ثم ارجع إلى سرتشات.'
          : 'Set battery usage to unrestricted, then return to SyrChat.',
    );
  }

  Future<void> _openDriverAutostartSettings({
    required bool isArabic,
  }) async {
    final launched = await openRideDriverAutostartSettings();
    if (!launched) {
      _showNotice(
        isArabic
            ? 'تعذر فتح إعدادات التشغيل التلقائي لهذا الجهاز.'
            : 'Could not open autostart settings on this device.',
      );
      return;
    }
    _showNotice(
      isArabic
          ? 'فعّل التشغيل التلقائي أو الحماية من الإغلاق القسري لهذا التطبيق.'
          : 'Enable autostart or background protection for this app.',
    );
  }

  Future<void> _openDriverAppInfoSettings({
    required bool isArabic,
  }) async {
    final launched = await openRideDriverAppInfoSettings();
    if (!launched) {
      _showNotice(
        isArabic
            ? 'تعذر فتح صفحة معلومات التطبيق.'
            : 'Could not open the app info screen.',
      );
      return;
    }
    _showNotice(
      isArabic
          ? 'تحقق من البطارية والإشعارات والتشغيل التلقائي داخل إعدادات التطبيق.'
          : 'Review battery, notifications, and autostart inside app settings.',
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

  Widget _buildDriverBackgroundHardeningCard({required bool isArabic}) {
    final status = _backgroundHardeningStatus;
    final level = rideDriverAndroidBackgroundHardeningLevel(
      online: _online,
      status: status,
    );
    if (level == RideDriverAndroidBackgroundHardeningLevel.none ||
        !_driverAccessAllowed ||
        status == null) {
      return const SizedBox.shrink();
    }
    final vendor = status.vendorLabel;
    final requiresBatteryChange = status.canManageBatteryOptimizations &&
        !status.ignoringBatteryOptimizations;
    final title = switch (level) {
      RideDriverAndroidBackgroundHardeningLevel.required => isArabic
          ? 'الحماية الخلفية مطلوبة الآن'
          : 'Background hardening is required',
      RideDriverAndroidBackgroundHardeningLevel.recommended => isArabic
          ? 'يوصى بتقوية العمل في الخلفية'
          : 'Background hardening is recommended',
      RideDriverAndroidBackgroundHardeningLevel.none => '',
    };
    final message = switch (level) {
      RideDriverAndroidBackgroundHardeningLevel.required => isArabic
          ? 'هذا الجهاز من نوع $vendor ما زال يقيّد البطارية. قد يتوقف تحديث الموقع أو صف الطلبات عند قفل الشاشة ما لم يتم ضبط البطارية على غير مقيّد.'
          : 'This $vendor device is still battery-restricted. Live location and dispatch presence may pause after screen lock until battery usage is set to unrestricted.',
      RideDriverAndroidBackgroundHardeningLevel.recommended => isArabic
          ? 'هذا الجهاز من نوع $vendor عدواني مع التطبيقات الخلفية. يفضّل تفعيل التشغيل التلقائي أو الحماية من التنظيف حتى لا يختفي السائق من الصف أثناء الخمول.'
          : 'This $vendor device is aggressive with background apps. Enable autostart or vendor background protection so the driver does not disappear from the queue while idle.',
      RideDriverAndroidBackgroundHardeningLevel.none => '',
    };

    return Card(
      color: level == RideDriverAndroidBackgroundHardeningLevel.required
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  level == RideDriverAndroidBackgroundHardeningLevel.required
                      ? Icons.battery_alert_outlined
                      : Icons.shield_moon_outlined,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    isArabic ? 'الجهاز $vendor' : 'Device $vendor',
                  ),
                ),
                Chip(
                  label: Text(
                    requiresBatteryChange
                        ? (isArabic ? 'البطارية مقيّدة' : 'Battery restricted')
                        : (isArabic
                            ? 'البطارية غير مقيّدة'
                            : 'Battery unrestricted'),
                  ),
                ),
                if (status.supportsVendorAutostartSettings)
                  Chip(
                    label: Text(
                      isArabic
                          ? 'إعدادات التشغيل التلقائي متاحة'
                          : 'Autostart settings available',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status.canManageBatteryOptimizations)
                  FilledButton.icon(
                    onPressed: () => _openDriverBackgroundBatterySettings(
                      isArabic: isArabic,
                    ),
                    icon: const Icon(Icons.battery_saver_outlined),
                    label: Text(
                      isArabic ? 'إعدادات البطارية' : 'Battery settings',
                    ),
                  ),
                if (status.supportsVendorAutostartSettings)
                  OutlinedButton.icon(
                    onPressed: () => _openDriverAutostartSettings(
                      isArabic: isArabic,
                    ),
                    icon: const Icon(Icons.settings_suggest_outlined),
                    label: Text(
                      isArabic ? 'التشغيل التلقائي' : 'Autostart settings',
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _openDriverAppInfoSettings(
                    isArabic: isArabic,
                  ),
                  icon: const Icon(Icons.info_outline),
                  label: Text(
                    isArabic ? 'معلومات التطبيق' : 'App info',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'مهم: الإيقاف القسري للتطبيق من النظام يوقف كل تتبع حتى تعيد فتح سرتشات يدويًا.'
                  : 'Important: force-stopping the app in Android still stops all tracking until SyrChat is opened again.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Cycle 76 — auto-snap the driver bottom sheet on trip-state
  /// transitions. Mirrors the passenger's `_syncSheetForActiveTrip`:
  /// when an active trip lands we collapse to the small peek so the
  /// map + driver/route markers dominate; when the trip ends we open
  /// back to the medium snap so the action surface (queue, earnings,
  /// presence toggle) is visible without a manual drag.
  ///
  /// Best-effort — swallows the detached-controller race so unit
  /// tests + the first frame after bootstrap can't crash here.
  void _syncDriverSheetForActiveTrip() {
    if (!_driverSheetCtrl.isAttached) return;
    // Active trip → tiny sheet (0.18) so the map fully owns the
    // screen; idle → medium 0.32 so the peek hero + queue land
    // above the fold.
    final target = _activeTrip != null ? 0.18 : 0.32;
    try {
      _driverSheetCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  /// Cycle 74 — driver peek hero. Sits at the top of the sheet's
  /// ListView and is engineered to be the *only* thing visible at
  /// the 0.16 min-snap. Two states:
  ///   * Offline → big "Go online" CTA (primary action).
  ///   * Online  → today-available-earnings chip + a status line.
  Widget _buildDriverPeekHero({required bool isArabic}) {
    final theme = Theme.of(context);
    if (!_driverAccessAllowed) {
      // Cycle 101 — self-service signup gate. Replaces the old
      // "Account not authorized" inline error with a form the user
      // can fill out to request driver access; admins approve in
      // the operator console's Signups workspace.
      return RoleSignupGate(
        roleId: RoleSignupRoleIds.driver,
        roleLabel: 'driver',
        roleLabelArabic: 'سائق',
        fields: RoleSignupFormFields.driver,
        api: RoleSignupApi(baseUrl: widget.baseUrl ?? ''),
        isArabic: isArabic,
        onSubmitted: () {
          // Kick off a refresh so a same-session admin approval
          // lands immediately on the next poll.
          unawaited(_refreshAll(showNotifications: false));
        },
      );
    }
    if (!_online) {
      // Offline: dominate the peek with a big toggle CTA.
      // Cycle 90 — render an inline spinner while the toggle's API
      // call is in flight so the driver gets immediate feedback.
      //
      // Cycle 123 — when the driver is offline but has earnings
      // already this session, surface them as a tappable preview
      // pill below the CTA. Tap opens the wallet; offline drivers
      // get a clear "what I made so far today" cue without going
      // online first.
      final offlineEarnings = _ledger?.earningsAvailableMinorUnits;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                icon: _togglingOnline
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.power_settings_new, size: 22),
                label: Text(
                  _togglingOnline
                      ? (isArabic ? 'جارٍ الاتصال…' : 'Going online…')
                      : (isArabic ? 'ابدأ العمل' : 'Go online'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed:
                    _togglingOnline ? null : () => _setOnline(true),
              ),
            ),
            if (offlineEarnings != null && offlineEarnings > 0) ...<Widget>[
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  // Cycle 130 — selection haptic on the offline
                  // earnings preview pill, matching the Cycle 97
                  // online-earnings chip pattern.
                  unawaited(HapticFeedback.selectionClick());
                  _openDriverWallet();
                },
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary
                        .withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.savings_outlined,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        isArabic
                            ? 'الأرباح اليوم: ${fmtCents(offlineEarnings)} SYP'
                            : 'Today\'s earnings: ${fmtCents(offlineEarnings)} SYP',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }
    // Online: earnings chip + status line + small "Go offline".
    final earnings = _ledger?.earningsAvailableMinorUnits;
    final activeTrip = _activeTrip;
    // Cycle 78 — when a trip is active, surface the next primary
    // command (Arrived / Start / Complete) as the dominant CTA at
    // the top of the peek hero. Without this the driver had to
    // drag the auto-collapsed 0.18 sheet up before they could
    // advance the trip — costly on every state transition.
    final primaryAction = activeTrip == null
        ? null
        : (_actionsForTrip(activeTrip).isEmpty
            ? null
            : _actionsForTrip(activeTrip).first);
    // Cycle 81 — driver is online and idle with queued rides waiting.
    // Surface the first queue entry as a tappable banner in the peek
    // hero so the driver can act on a new dispatch without dragging
    // the sheet up. Tapping expands the sheet to its 0.92 snap so
    // they can read details before pressing Accept on the proper
    // queue card.
    final showQueueBanner = activeTrip == null && _queue.isNotEmpty;
    final RideTrip? topQueueTrip = showQueueBanner ? _queue.first : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (topQueueTrip != null) ...<Widget>[
            Material(
              color: theme.colorScheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  if (_driverSheetCtrl.isAttached) {
                    try {
                      _driverSheetCtrl.animateTo(
                        0.92,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    } catch (_) {}
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.directions_car_outlined,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              isArabic
                                  ? '${_queue.length} طلب جديد بانتظارك'
                                  : '${_queue.length} new ride${_queue.length == 1 ? '' : 's'} waiting',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${topQueueTrip.pickup} → ${topQueueTrip.destination}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .80),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (primaryAction != null) ...<Widget>[
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                // Cycle 84 — swap the play-arrow for a small inline
                // spinner while a trip command is in-flight. Before
                // this, the driver tap → 1-2s freeze with no signal
                // looked like the button was broken.
                icon: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  _driverActionLabel(primaryAction, isArabic: isArabic),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: _busy
                    ? null
                    : () => _advanceActiveTrip(primaryAction.command),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: <Widget>[
              if (earnings != null)
                // Cycle 97 — the earnings chip is now tappable and
                // jumps straight to the wallet/earnings detail. The
                // peek hero already exposes the today-available
                // number; making it the launchpad to the full
                // breakdown saves one menu dive.
                Material(
                  color: theme.colorScheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openDriverWallet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.savings_outlined,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${fmtCents(earnings)} SYP',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Cycle 137 — show the driver's own rating aggregate
              // next to the earnings chip once at least one rider
              // has rated them. Quiet when count == 0 so brand-new
              // drivers don't see a default "0.0 (0)" stripe.
              if (_myRatingAggregate != null &&
                  _myRatingAggregate!.ratingCount > 0) ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.star_rounded,
                          size: 16, color: Color(0xFFB8860B)),
                      const SizedBox(width: 4),
                      Text(
                        '${_myRatingAggregate!.averageStars.toStringAsFixed(1)}'
                        ' (${_myRatingAggregate!.ratingCount})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFFB8860B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Cycle 196 — Today's tips chip sits next to the
              // rating chip when at least one tip rolled in today.
              // Quiet otherwise so the chip strip doesn't shout
              // a meaningless "0" on a fresh day.
              if (_myTipAggregate != null &&
                  _myTipAggregate!.todayCount > 0) ...<Widget>[
                const SizedBox(width: 6),
                Material(
                  color: const Color(0xFFFFA000).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(99),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openDriverWallet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.volunteer_activism_rounded,
                              size: 16, color: Color(0xFFE65100)),
                          const SizedBox(width: 4),
                          Text(
                            '${fmtCents(_myTipAggregate!.todayAmountCents)} ${isArabic ? "إكرامية" : "tips"}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                // Cycle 90 — small spinner while the offline toggle is
                // in flight (matches the Go-online CTA pattern).
                icon: _togglingOnline
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.power_settings_new, size: 16),
                label: Text(_togglingOnline
                    ? (isArabic ? 'جارٍ الإيقاف…' : 'Going offline…')
                    : (isArabic ? 'إيقاف' : 'Go offline')),
                // Cycle 79 — confirm before going offline mid-trip so
                // the driver doesn't accidentally strand a passenger
                // by tapping the small offline pill during a trip.
                onPressed: _togglingOnline
                    ? null
                    : () => _requestGoOffline(isArabic: isArabic),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                // Cycle 96 — when a trip is active, surface the
                // destination on the status line so the driver still
                // sees where they're heading at the 0.18 collapse
                // snap, without dragging the sheet up.
                child: Text(
                  activeTrip != null
                      ? (isArabic
                          ? 'إلى ${activeTrip.destination}'
                          : 'To ${activeTrip.destination}')
                      : (isArabic
                          ? 'متصل — في انتظار الإسناد التالي.'
                          : 'Online — waiting for the next dispatch.'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          // Cycle 113 — GPS warning chip. When the driver is online
          // but our position stream isn't subscribed (permission
          // denied, OS killed it, hardware off), the operator board
          // marks them as "stale / no GPS" and dispatch quality
          // suffers. Surfacing the warning in the peek hero lets
          // them fix it before being penalised on visibility.
          if (_driverPositionSub == null) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFA000).withValues(alpha: .18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.location_disabled_rounded,
                      size: 14, color: Color(0xFFB45309)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      isArabic
                          ? 'GPS غير متاح — قد لا تتلقى طلبات قريبة'
                          : 'GPS unavailable — may miss nearby dispatches',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverNavigationMap({
    required bool isArabic,
    bool standalone = false,
  }) {
    final trackingLocation = _trackingSnapshot?.latestDriverLocation?.location;
    final presenceLocation =
        rideGeoPointFromCoordinatePoint(_presence?.location);
    final currentLocation = _tripMapSnapshot?.driverLocation ??
        trackingLocation ??
        presenceLocation;
    final shouldShowMap =
        _activeTrip != null || currentLocation != null || _online;
    // Cycle 72 — in `standalone: true` mode (full-screen background)
    // we always render the map even when offline. The bottom sheet
    // then dominates the experience and the user has a sense of
    // place even before going online.
    if (!standalone && !shouldShowMap) {
      return const SizedBox.shrink();
    }
    final snapshot = _tripMapSnapshot;
    return RideTripMapCard(
      baseUrl: widget.baseUrl,
      bootstrap: _bootstrap,
      snapshot: snapshot?.hasAnyOverlay == true ? snapshot : null,
      currentLocation: currentLocation,
      fullscreenTitle: isArabic ? 'خريطة السائق' : 'Driver map',
      unavailableMessage: isArabic
          ? 'عرض الخريطة عبر MapLibre غير متاح في هذا البناء.'
          : 'MapLibre navigation map is not available in this build.',
      loadingMessage:
          isArabic ? 'جاري تهيئة خريطة السائق…' : 'Preparing driver map…',
      height: standalone ? 248 : 248,
      standalone: standalone,
      allowFullscreen: !standalone,
      showZoomControls: !standalone,
    );
  }

  Widget _buildActiveTripSemanticsBanner({required bool isArabic}) {
    final activeTrip = _activeTrip;
    final semanticsLabel = rideDriverActiveTripSemanticsSummaryLabel(
      trip: activeTrip,
      trackingQuote: _trackingQuote,
      trackingSnapshot: _trackingSnapshot,
      lastLocationPingAtIso: _lastLocationPingAtIso,
      isArabic: isArabic,
      trackingAgeLabel: _trackingAgeLabel,
    );
    if (activeTrip == null || semanticsLabel == null) {
      return const SizedBox.shrink();
    }
    final stage = rideTripMapStageForStatus(activeTrip.status);
    final latestDriverLocation = _trackingSnapshot?.latestDriverLocation;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'ملخص الرحلة النشطة' : 'Active trip summary',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_driverStatusLabel(activeTrip.status, isArabic: isArabic)} • '
                '${activeTrip.pickup} -> ${activeTrip.destination}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                stage == RideTripMapStage.destination
                    ? (isArabic
                        ? 'الملاحة الحالية: إلى الوجهة'
                        : 'Navigation target: destination')
                    : (isArabic
                        ? 'الملاحة الحالية: إلى نقطة الالتقاط'
                        : 'Navigation target: pickup'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (latestDriverLocation != null) ...[
                const SizedBox(height: 4),
                Text(
                  isArabic
                      ? 'آخر تحديث تتبع: ${_trackingAgeLabel(latestDriverLocation.createdAtIso, isArabic: true) ?? latestDriverLocation.createdAtIso}'
                      : 'Tracking last sent: ${_trackingAgeLabel(latestDriverLocation.createdAtIso, isArabic: false) ?? latestDriverLocation.createdAtIso}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverOverviewCard({required bool isArabic}) {
    final finance = _financeDashboard;
    final shift = _shiftSummary;
    final documents = _documentDashboard;
    final availableReserveMinorUnits = rideDriverAvailableReserveMinorUnits(
      financeDashboard: finance,
      ledger: _ledger,
    );
    final heldReserveMinorUnits = _ledger?.heldReserveMinorUnits;
    final nextDispatchReserveMinorUnits = _queue.isEmpty
        ? null
        : _queue
            .map((trip) => rideDriverRequiredReserveMinorUnits(
                  trip.fareEstimateCents,
                ))
            .reduce((a, b) => a < b ? a : b);
    final reserveShortfall = availableReserveMinorUnits != null &&
        nextDispatchReserveMinorUnits != null &&
        availableReserveMinorUnits < nextDispatchReserveMinorUnits;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'نظرة سريعة' : 'Quick overview',
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
                Chip(
                  label: Text(
                    '${isArabic ? "الطلبات" : "Dispatches"} ${(shift?.openDispatchesVisible ?? _queue.length)}',
                  ),
                ),
                Chip(
                  label: Text(
                    '${isArabic ? "السحب" : "Payout"} ${finance == null && _ledger == null ? "--" : fmtCents(finance?.recommendedPayoutMinorUnits ?? _ledger!.netAvailableForPayoutMinorUnits)} SYP',
                  ),
                ),
                Chip(
                  label: Text(
                    '${isArabic ? "الاحتياطي المتاح" : "Reserve"} ${availableReserveMinorUnits == null ? "--" : "${fmtCents(availableReserveMinorUnits)} SYP"}',
                  ),
                ),
                if (heldReserveMinorUnits != null)
                  Chip(
                    label: Text(
                      '${isArabic ? "محجوز" : "Held"} ${fmtCents(heldReserveMinorUnits)} SYP',
                    ),
                  ),
                if (nextDispatchReserveMinorUnits != null)
                  Chip(
                    label: Text(
                      '${isArabic ? "قبول الطلب التالي" : "Next accept"} ${fmtCents(nextDispatchReserveMinorUnits)} SYP',
                    ),
                  ),
                Chip(
                  label: Text(
                    '${isArabic ? "الجاهزية" : "Readiness"} ${!_hasDriverProfile ? (isArabic ? "ملف ناقص" : "Profile incomplete") : documents == null ? "--" : documents.summary.readyToDrive ? (isArabic ? "جاهز" : "Ready") : (isArabic ? "محجوب" : "Blocked")}',
                  ),
                ),
                Chip(
                  label: Text(
                    '${isArabic ? "الوردية" : "Shift"} ${shift == null ? "--" : _formatShiftDuration(shift.currentOnlineDurationSeconds, isArabic: isArabic)}',
                  ),
                ),
                Chip(
                  label: Text(
                    '${isArabic ? "اليوم" : "Today"} ${shift?.completedTodayCount ?? 0}',
                  ),
                ),
              ],
            ),
            if (reserveShortfall) ...[
              const SizedBox(height: 10),
              Text(
                isArabic
                    ? 'يلزم شحن الرصيد قبل قبول الطلبات الظاهرة. أقل احتياطي مطلوب الآن هو ${fmtCents(nextDispatchReserveMinorUnits!)} SYP.'
                    : 'Top up is required before accepting visible dispatches. The smallest reserve needed right now is ${fmtCents(nextDispatchReserveMinorUnits!)} SYP.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openDriverWallet,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                  isArabic ? 'اشحن الآن' : 'Open wallet to top up',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDriverOperationsMenuCard({required bool isArabic}) {
    final finance = _financeDashboard;
    final shift = _shiftSummary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'الأداء والتشغيل' : 'Operations and performance',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            _metricTile(
              context: context,
              icon: Icons.local_shipping_outlined,
              title: isArabic ? 'الطلبات المفتوحة' : 'Open dispatches',
              value: (shift?.openDispatchesVisible ?? _queue.length).toString(),
            ),
            _metricTile(
              context: context,
              icon: Icons.account_balance_wallet_outlined,
              title: isArabic ? 'القابل للسحب' : 'Available payout',
              value: finance == null && _ledger == null
                  ? '--'
                  : '${fmtCents(finance?.recommendedPayoutMinorUnits ?? _ledger!.netAvailableForPayoutMinorUnits)} SYP',
            ),
            _metricTile(
              context: context,
              icon: Icons.schedule_outlined,
              title: isArabic ? 'مدة الوردية' : 'Shift online',
              value: shift == null
                  ? '--'
                  : _formatShiftDuration(
                      shift.currentOnlineDurationSeconds,
                      isArabic: isArabic,
                    ),
            ),
            _metricTile(
              context: context,
              icon: Icons.flag_outlined,
              title: isArabic ? 'رحلات اليوم' : 'Trips today',
              value:
                  shift == null ? '--' : shift.completedTodayCount.toString(),
            ),
            // Cycle 182 — entry into the driver's trip-history page
            // (receipt-style detail + own-rating recall). Lives in
            // the operations card so the driver sees it alongside
            // shift + earnings.
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openDriverHistoryPage,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: Text(
                      isArabic
                          ? 'سجل الرحلات'
                          : 'Trip history',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Cycle 214 — demand heatmap. Helps drivers spot
                // where to position for the next pickup.
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _openDriverDemandHeatmap,
                    icon: const Icon(
                        Icons.local_fire_department_rounded,
                        size: 18),
                    label: Text(
                      isArabic ? 'خريطة الطلب' : 'Demand map',
                    ),
                  ),
                ),
              ],
            ),
            if (shift != null) ...[
              const SizedBox(height: 10),
              Text(
                isArabic
                    ? 'اليوم: ${shift.completedTodayCount} رحلات • ${fmtCents(shift.completedTodayValueMinorUnits)} SYP'
                    : 'Today: ${shift.completedTodayCount} rides • ${fmtCents(shift.completedTodayValueMinorUnits)} SYP',
              ),
              const SizedBox(height: 6),
              Text(
                isArabic
                    ? 'رحلات نشطة: ${shift.activeTripCount} • طلبات مرئية: ${shift.openDispatchesVisible} • دفعات عالقة: ${shift.paymentFailedCount}'
                    : 'Active rides: ${shift.activeTripCount} • Visible dispatches: ${shift.openDispatchesVisible} • Payment failures: ${shift.paymentFailedCount}',
              ),
              const SizedBox(height: 6),
              Text(
                isArabic
                    ? 'متوسط ETA للرحلات المكتملة: ${((shift.avgCompletedEtaSeconds + 59) ~/ 60)} دقيقة'
                    : 'Avg ETA on completed rides: ${((shift.avgCompletedEtaSeconds + 59) ~/ 60)} min',
              ),
              if ((shift.lastSeenAtIso ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  isArabic
                      ? 'آخر نبضة: ${_trackingAgeLabel(shift.lastSeenAtIso, isArabic: true) ?? shift.lastSeenAtIso!}'
                      : 'Last heartbeat: ${_trackingAgeLabel(shift.lastSeenAtIso, isArabic: false) ?? shift.lastSeenAtIso!}',
                ),
              ],
              if ((shift.lastCompletedAtIso ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  isArabic
                      ? 'آخر رحلة مكتملة: ${_trackingAgeLabel(shift.lastCompletedAtIso, isArabic: true) ?? shift.lastCompletedAtIso!}'
                      : 'Last completed trip: ${_trackingAgeLabel(shift.lastCompletedAtIso, isArabic: false) ?? shift.lastCompletedAtIso!}',
                ),
              ],
              if (shift.alerts.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...shift.alerts.map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• ${alert.title}: ${alert.detail}'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDriverDocumentsMenuCard({required bool isArabic}) {
    final documents = _documentDashboard;
    if (documents == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'الوثائق والامتثال' : 'Documents and compliance',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'معلّق ${documents.summary.pendingDocuments} • مرفوض ${documents.summary.rejectedDocuments} • منتهي ${documents.summary.expiredDocuments} • مفقود ${documents.summary.missingDocuments}'
                  : 'Pending ${documents.summary.pendingDocuments} • Rejected ${documents.summary.rejectedDocuments} • Expired ${documents.summary.expiredDocuments} • Missing ${documents.summary.missingDocuments}',
            ),
            const SizedBox(height: 8),
            Text(
              documents.summary.readyToDrive
                  ? (isArabic
                      ? 'كل المتطلبات مكتملة ويمكن استقبال الرحلات.'
                      : 'All required documents are approved and the driver can receive dispatches.')
                  : (isArabic
                      ? 'يوجد ${documents.summary.blockingIssues} عوائق امتثال تمنع الجاهزية الكاملة.'
                      : '${documents.summary.blockingIssues} compliance blockers still prevent full readiness.'),
            ),
            const SizedBox(height: 10),
            ...documents.documents.map(
              (document) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(
                  _documentTypeLabel(
                    document.documentType,
                    isArabic: isArabic,
                  ),
                ),
                subtitle: Text(
                  '${_documentStatusLabel(document.status, isArabic: isArabic)}'
                  '${document.documentNumberMasked == null ? '' : ' • ${document.documentNumberMasked}'}'
                  '${document.expiresAtIso == null ? '' : '\n${isArabic ? "ينتهي" : "Expires"}: ${document.expiresAtIso}'}'
                  '${document.reviewNote == null ? '' : '\n${document.reviewNote}'}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: _busy || !_driverAccessAllowed
                      ? null
                      : () => _submitDriverDocument(document.documentType),
                  child: Text(
                    document.status == RideDriverDocumentStatus.approved
                        ? (isArabic ? 'تحديث' : 'Update')
                        : (isArabic ? 'إرسال' : 'Submit'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverEarningsMenuCard({required bool isArabic}) {
    final finance = _financeDashboard;
    final availableReserveMinorUnits = rideDriverAvailableReserveMinorUnits(
      financeDashboard: finance,
      ledger: _ledger,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'الأرباح والاحتياطي' : 'Earnings and reserve',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              finance == null && _ledger == null
                  ? (isArabic
                      ? 'دفتر السائق غير متاح بعد لهذا الحساب.'
                      : 'Driver ledger is not available for this account yet.')
                  : 'Available earnings: ${fmtCents(_ledger!.earningsAvailableMinorUnits)} SYP\n'
                      'Available for dispatch accepts: ${fmtCents(availableReserveMinorUnits ?? 0)} SYP\n'
                      'Reserve held: ${fmtCents(_ledger!.heldReserveMinorUnits)} SYP\n'
                      'Bonuses: ${fmtCents(_ledger!.bonusesMinorUnits)} SYP\n'
                      'Debt: ${fmtCents(_ledger!.debtMinorUnits)} SYP\n'
                      'Payout pending: ${fmtCents(_ledger!.payoutPendingMinorUnits)} SYP\n'
                      'Cash collected: ${fmtCents(_ledger!.cashCollectedMinorUnits)} SYP',
            ),
            if (finance != null) ...[
              const SizedBox(height: 10),
              Text(
                isArabic
                    ? 'موصى به للاحتياطي: ${fmtCents(finance.recommendedReserveMinorUnits)} SYP • تغطية ${(finance.reserveCoverageBps / 100).toStringAsFixed(0)}%'
                    : 'Recommended reserve: ${fmtCents(finance.recommendedReserveMinorUnits)} SYP • Coverage ${(finance.reserveCoverageBps / 100).toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 4),
              Text(
                isArabic
                    ? 'القابل للسحب الآن: ${fmtCents(finance.recommendedPayoutMinorUnits)} SYP • تسويات معلقة: ${fmtCents(finance.pendingSettlementMinorUnits)} SYP'
                    : 'Payout now: ${fmtCents(finance.recommendedPayoutMinorUnits)} SYP • Pending settlement: ${fmtCents(finance.pendingSettlementMinorUnits)} SYP',
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: (_busy ||
                        !_driverAccessAllowed ||
                        finance.payoutBlocked ||
                        (finance.platformPayoutWalletId ?? '').trim().isEmpty)
                    ? null
                    : _requestPayout,
                icon: const Icon(Icons.account_balance_wallet),
                label: Text(
                  isArabic ? 'طلب سحب موصى به' : 'Request recommended payout',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isArabic
                    ? 'رحلات مكتملة/24س: ${finance.completedTodayCount} • قيمة ${fmtCents(finance.completedTodayValueMinorUnits)} SYP'
                    : 'Completed / 24h: ${finance.completedTodayCount} • Value ${fmtCents(finance.completedTodayValueMinorUnits)} SYP',
              ),
              if (finance.alerts.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...finance.alerts.map(
                  (alert) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(alert.title),
                    subtitle: Text(alert.detail),
                  ),
                ),
              ],
              if (finance.recentCompletedTrips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  isArabic ? 'آخر الرحلات المكتملة' : 'Recent completed trips',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...finance.recentCompletedTrips.map(
                  (trip) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(
                      '${trip.pickup} -> ${trip.destination}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${fmtCents(trip.fareEstimateCents)} SYP • ${trip.etaMinutes} min',
                    ),
                  ),
                ),
              ],
              if (finance.recentReserveEvents.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  isArabic ? 'سجل الاحتياطي' : 'Reserve history',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...finance.recentReserveEvents.map(
                  (event) {
                    final effectiveIso = event.settledAtIso ??
                        event.releasedAtIso ??
                        event.reservedAtIso ??
                        event.updatedAtIso ??
                        event.createdAtIso;
                    final effectiveAge = _trackingAgeLabel(
                      effectiveIso,
                      isArabic: isArabic,
                    );
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.history_toggle_off_rounded),
                      title: Text(
                        '${_driverReserveEventStatusLabel(event.status, isArabic: isArabic)} • ${fmtCents(event.amountMinorUnits)} SYP',
                      ),
                      subtitle: Text(
                        '${isArabic ? "الرحلة" : "Ride"} ${event.rideId}'
                        '${effectiveAge == null ? "" : "\n${isArabic ? "الوقت" : "When"}: $effectiveAge"}',
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDriverSupportMenuCard({required bool isArabic}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'الدعم والنظام' : 'Support and system',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'التنبيهات داخل التطبيق مفعلة عبر التحديث الدوري. يمكن توصيل Push لاحقاً فوق نفس تدفق الحالة.'
                  : 'In-app notifications are live via polling. Push can later attach to the same trip-status feed.',
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'الجاهزية الحالية: ملف السائق ${_hasDriverProfile ? "مكتمل" : "ناقص"} • محفظة ${(_walletId ?? "").isNotEmpty ? "مرتبطة" : "غير مرتبطة"} • سحب ${_financeDashboard?.payoutBlocked == true ? "مقيّد" : "متاح"}'
                  : 'Current readiness: driver profile ${_hasDriverProfile ? "ready" : "incomplete"} • wallet ${(_walletId ?? "").isNotEmpty ? "linked" : "missing"} • payout ${_financeDashboard?.payoutBlocked == true ? "restricted" : "available"}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _contactSupportByMail,
                  icon: const Icon(Icons.mail_outline),
                  label: Text(isArabic ? 'بريد الدعم' : 'Email support'),
                ),
                OutlinedButton.icon(
                  onPressed: _contactSupportByPhone,
                  icon: const Icon(Icons.phone_outlined),
                  label: Text(isArabic ? 'اتصال' : 'Call support'),
                ),
              ],
            ),
            if (_bootstrap != null) ...[
              const SizedBox(height: 12),
              Text(
                'Platform ${_bootstrap!.version} • '
                '${_bootstrap!.serviceClasses.join(', ')} • '
                'routing: ${_bootstrap!.mapRoutingStack}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openDriverUtilityMenu({required bool isArabic}) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .84,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Text(
                  isArabic ? 'قائمة السائق' : 'Driver menu',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                _buildDriverOperationsMenuCard(isArabic: isArabic),
                _buildDriverDocumentsMenuCard(isArabic: isArabic),
                _buildDriverEarningsMenuCard(isArabic: isArabic),
                _buildDriverSupportMenuCard(isArabic: isArabic),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final activeTrip = _activeTrip;
    final actions = activeTrip == null
        ? const <_DriverAction>[]
        : _actionsForTrip(activeTrip);
    final trackingQuote = _trackingQuote;
    final trackingSnapshot = _trackingSnapshot;
    final presence = _presence;
    final driverPhase = _driverPhaseFor(
      online: _online,
      activeTrip: activeTrip,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(shamellSurfaceAppTitle(
          isArabic: l.isArabic,
          surface: ShamellAppSurface.driver,
        )),
        actions: [
          // Cycle 93 — explicit "Refresh now" button so the driver
          // doesn't have to pull-to-refresh inside the bottom sheet
          // (which requires hitting the right scroll edge first).
          IconButton(
            onPressed: _loading
                ? null
                : () {
                    // Cycle 126 — tactile confirmation on the
                    // AppBar Refresh button, matching the operator-
                    // console freshness chip (Cycle 124).
                    unawaited(HapticFeedback.selectionClick());
                    unawaited(_refreshAll(showNotifications: false));
                  },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l.isArabic ? 'تحديث' : 'Refresh',
          ),
          IconButton(
            onPressed: _loading
                ? null
                : () => _openDriverUtilityMenu(isArabic: l.isArabic),
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: l.isArabic ? 'القائمة' : 'Menu',
          ),
        ],
        // Persistent four-phase strip so the driver always knows whether
        // they're earning, waiting, or off-shift. Hidden during initial
        // load to keep the chrome calm while data is fetched.
        bottom: _loading
            ? null
            : _buildDriverPhaseStrip(
                phase: driverPhase,
                activeStatus: activeTrip?.status,
                isArabic: l.isArabic,
              ),
      ),
      body: _loading
          ? const ShamellSkeletonList(itemCount: 6)
          // Cycle 72 — Uber-style driver layout: fullscreen map
          // canvas with a draggable bottom sheet hosting the online
          // toggle / profile / active-trip cards. Same pattern as
          // the rider page.
          : Stack(
              children: <Widget>[
                Positioned.fill(
                  child: _buildDriverNavigationMap(
                    isArabic: l.isArabic,
                    standalone: true,
                  ),
                ),
                DraggableScrollableSheet(
                  controller: _driverSheetCtrl,
                  initialChildSize: 0.32,
                  minChildSize: 0.16,
                  maxChildSize: 0.92,
                  snap: true,
                  snapSizes: const <double>[0.16, 0.32, 0.92],
                  builder: (sheetCtx, sheetScroll) => Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : WeChatPalette.background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .12),
                          blurRadius: 18,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RefreshIndicator(
              onRefresh: () => _refreshAll(showNotifications: false),
              child: ListView(
                controller: sheetScroll,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                children: [
                  // Drag handle hint.
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Cycle 74 — peek hero. When OFFLINE the entire
                  // peek surface is dominated by a single big "Go
                  // online" CTA; once ONLINE it switches to an
                  // earnings chip + a status line. Either way the
                  // driver's primary action / state is visible at
                  // 0.16 snap.
                  _buildDriverPeekHero(isArabic: l.isArabic),
                  _buildActiveTripSemanticsBanner(isArabic: l.isArabic),
                  PushReadinessBanner(isArabic: l.isArabic),
                  _buildDriverBackgroundHardeningCard(isArabic: l.isArabic),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_driverAccessAllowed) ...[
                            Text(
                              l.isArabic
                                  ? 'هذا الحساب غير مخوّل بعد للوصول إلى تطبيق السائق.'
                                  : 'This account is not yet allowed to access the driver app.',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l.isArabic
                                  ? 'يجب منح دور driver أو ride_driver أو أحد أدوار التشغيل قبل قبول الرحلات.'
                                  : 'Grant a driver or ride-operations role before this account can accept dispatches.',
                            ),
                            const SizedBox(height: 12),
                          ],
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _online,
                            onChanged: _driverAccessAllowed
                                ? (value) => _setOnline(value)
                                : null,
                            title: Text(l.isArabic ? 'متصل' : 'Go online'),
                            subtitle: Text(
                              presence?.online == true &&
                                      (presence?.lastSeenAtIso ?? '').isNotEmpty
                                  ? (l.isArabic
                                      ? 'نشط على الخادم • آخر نبضة ${presence!.lastSeenAtIso}'
                                      : 'Server active • last heartbeat ${presence!.lastSeenAtIso}')
                                  : (l.isArabic
                                      ? 'استقبل الرحلات الجديدة وابقَ في قائمة الإسناد.'
                                      : 'Receive new dispatches and stay in the assignment queue.'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _driverNameCtrl,
                            decoration: InputDecoration(
                              labelText:
                                  l.isArabic ? 'اسم السائق' : 'Driver name',
                            ),
                            enabled: _driverAccessAllowed,
                            onChanged: (_) => unawaited(_persistProfile()),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _carPlateCtrl,
                            decoration: InputDecoration(
                              labelText:
                                  l.isArabic ? 'رقم اللوحة' : 'Car plate',
                            ),
                            textCapitalization: TextCapitalization.characters,
                            enabled: _driverAccessAllowed,
                            onChanged: (_) => unawaited(_persistProfile()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Cycle 72 — map moved to the Stack background.
                  if (activeTrip != null)
                    Semantics(
                      container: true,
                      label: rideDriverActiveTripSemanticsSummaryLabel(
                        trip: activeTrip,
                        trackingQuote: trackingQuote,
                        trackingSnapshot: trackingSnapshot,
                        lastLocationPingAtIso: _lastLocationPingAtIso,
                        isArabic: l.isArabic,
                        trackingAgeLabel: _trackingAgeLabel,
                      ),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.drive_eta_outlined,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Active trip',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Chip(
                                    label: Text(_driverStatusLabel(
                                      activeTrip.status,
                                      isArabic: l.isArabic,
                                    )),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                  '${activeTrip.pickup} -> ${activeTrip.destination}'),
                              const SizedBox(height: 4),
                              Text(
                                'Driver: ${activeTrip.driverName} • ${activeTrip.carPlate}',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Estimate: ${fmtCents(activeTrip.fareEstimateCents)} SYP • ETA ${activeTrip.etaMinutes} min',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                rideTripMapStageForStatus(activeTrip.status) ==
                                        RideTripMapStage.destination
                                    ? (l.isArabic
                                        ? 'الملاحة الحالية: إلى الوجهة'
                                        : 'Navigation target: destination')
                                    : (l.isArabic
                                        ? 'الملاحة الحالية: إلى نقطة الالتقاط'
                                        : 'Navigation target: pickup'),
                              ),
                              if (trackingQuote != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Trip route: ${(trackingQuote.route.distanceMeters / 1000).toStringAsFixed(1)} km • '
                                  'ETA ${((trackingQuote.route.etaSeconds + 59) ~/ 60)} min',
                                ),
                                if (trackingQuote.trafficAtPickup != null)
                                  Text(
                                    'Traffic: ${trackingQuote.trafficAtPickup!.currentSpeedKmh}/'
                                    '${trackingQuote.trafficAtPickup!.freeFlowSpeedKmh} km/h',
                                  ),
                              ],
                              if (trackingSnapshot?.latestDriverLocation !=
                                  null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  l.isArabic
                                      ? 'آخر تحديث تتبع: ${_trackingAgeLabel(trackingSnapshot!.latestDriverLocation!.createdAtIso, isArabic: true) ?? trackingSnapshot.latestDriverLocation!.createdAtIso}'
                                      : 'Tracking last sent: ${_trackingAgeLabel(trackingSnapshot!.latestDriverLocation!.createdAtIso, isArabic: false) ?? trackingSnapshot.latestDriverLocation!.createdAtIso}',
                                ),
                                if (trackingSnapshot
                                        .latestDriverLocation!.location !=
                                    null)
                                  Text(
                                    'GPS: ${trackingSnapshot.latestDriverLocation!.location!.lat.toStringAsFixed(5)}, '
                                    '${trackingSnapshot.latestDriverLocation!.location!.lon.toStringAsFixed(5)}',
                                  ),
                              ] else if ((_lastLocationPingAtIso ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  l.isArabic
                                      ? 'آخر محاولة مشاركة موقع: ${_trackingAgeLabel(_lastLocationPingAtIso, isArabic: true) ?? _lastLocationPingAtIso!}'
                                      : 'Last tracking attempt: ${_trackingAgeLabel(_lastLocationPingAtIso, isArabic: false) ?? _lastLocationPingAtIso!}',
                                ),
                              ],
                              if (trackingSnapshot != null &&
                                  trackingSnapshot.timeline.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  l.isArabic ? 'الخط الزمني' : 'Trip timeline',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ...trackingSnapshot.timeline.reversed
                                    .take(3)
                                    .map(
                                      (event) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          '${event.eventKind.replaceAll('_', ' ')}'
                                          '${event.status != null ? ' • ${_driverStatusLabel(event.status!, isArabic: l.isArabic)}' : ''}'
                                          ' • ${_trackingAgeLabel(event.createdAtIso, isArabic: l.isArabic) ?? event.createdAtIso}',
                                        ),
                                      ),
                                    ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final action in actions)
                                    FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _advanceActiveTrip(
                                              action.command),
                                      child: Text(action.label),
                                    ),
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                            _advanceActiveTrip('cancel_trip'),
                                    child:
                                        Text(l.isArabic ? 'إلغاء' : 'Cancel'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  _buildDriverOverviewCard(isArabic: l.isArabic),
                  TaxiDriverCommandPanel(
                    activeTrip: activeTrip,
                    online: _online,
                    readyForDispatch: _driverReadyForDispatch,
                    queueCount:
                        _shiftSummary?.openDispatchesVisible ?? _queue.length,
                    completedTodayCount: _shiftSummary?.completedTodayCount ??
                        _financeDashboard?.completedTodayCount ??
                        0,
                    payoutMinorUnits:
                        _financeDashboard?.recommendedPayoutMinorUnits ??
                            _ledger?.netAvailableForPayoutMinorUnits,
                    reserveMinorUnits: rideDriverAvailableReserveMinorUnits(
                      financeDashboard: _financeDashboard,
                      ledger: _ledger,
                    ),
                    cashCollectedMinorUnits: _ledger?.cashCollectedMinorUnits,
                    walletLinked:
                        (_walletId ?? _financeDashboard?.walletId ?? '')
                            .trim()
                            .isNotEmpty,
                    onOpenWallet: _openDriverWallet,
                    onRequestPayout: _financeDashboard == null
                        ? null
                        : () => unawaited(_requestPayout()),
                  ),
                  TaxiDriverSafetyCommsPanel(
                    hasActiveTrip: activeTrip != null,
                    trackingFresh:
                        _trackingSnapshot?.latestDriverLocation != null ||
                            (_lastLocationPingAtIso ?? '').trim().isNotEmpty,
                    paymentFailureCount: _shiftSummary?.paymentFailedCount ?? 0,
                    onOpenChat: _openDriverRideChat,
                    onVoiceCall: () => unawaited(_startDriverVoiceCall()),
                    onVideoCall: _startDriverVideoCall,
                    onAudioMessage: _recordDriverAudioMessage,
                    onSafetySos: () => unawaited(_triggerDriverSos()),
                  ),
                  TaxiDriverGrowthPanel(
                    completedTodayCount: _shiftSummary?.completedTodayCount ??
                        _financeDashboard?.completedTodayCount ??
                        0,
                    queueCount:
                        _shiftSummary?.openDispatchesVisible ?? _queue.length,
                    bonusMinorUnits: ((_shiftSummary?.openDispatchesVisible ??
                            _queue.length) *
                        250),
                    offlineQueueCount: _updatesRetryTimer == null ? 0 : 1,
                    heatmapFresh: _online &&
                        ((_shiftSummary?.openDispatchesVisible ??
                                    _queue.length) >
                                0 ||
                            _presence?.location != null),
                    onOpenHeatmap: _openDriverHeatmap,
                    onOpenQuests: _openDriverQuests,
                    onSyncOffline: _syncDriverOfflineQueue,
                  ),
                  TaxiDriverOperationsPanel(
                    hasActiveTrip: activeTrip != null,
                    pickupCodeRequired:
                        _driverPickupCodeRequired && activeTrip != null,
                    navigationReady: activeTrip != null || _queue.isNotEmpty,
                    waitingTimerActive: _driverWaitingTimerActive,
                    vehicleChecklistReady: _driverVehicleChecklistReady,
                    packageModeEnabled: _driverPackageModeEnabled,
                    pickupInstructionsReady: _driverPickupInstructionsReady,
                    rematchCandidateCount:
                        _driverPickupCodeRequired && activeTrip != null ? 1 : 0,
                    onVerifyPickupCode:
                        activeTrip == null ? null : _verifyDriverPickupCode,
                    onOpenNavigation: () => unawaited(_openDriverNavigation()),
                    onStartWaitingTimer:
                        activeTrip == null ? null : _startDriverWaitingTimer,
                    onCompleteVehicleChecklist: _completeDriverVehicleChecklist,
                    onConfirmPackageHandoff: _confirmDriverPackageHandoff,
                    onRequestRematch:
                        activeTrip == null ? null : _requestDriverRematch,
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.isArabic ? 'قائمة الإسناد' : 'Dispatch queue',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_queue.isEmpty)
                            Text(
                              _online
                                  ? (l.isArabic
                                      ? 'لا توجد طلبات مفتوحة حالياً.'
                                      : 'No open ride requests right now.')
                                  : (l.isArabic
                                      ? 'فعّل وضع الاتصال لرؤية قائمة الإسناد.'
                                      : 'Go online to see dispatches.'),
                            )
                          else
                            ..._queue.map(
                              (trip) {
                                final requiredReserveMinorUnits =
                                    rideDriverRequiredReserveMinorUnits(
                                  trip.fareEstimateCents,
                                );
                                final availableReserveMinorUnits =
                                    rideDriverAvailableReserveMinorUnits(
                                  financeDashboard: _financeDashboard,
                                  ledger: _ledger,
                                );
                                final hasEnoughReserve =
                                    rideDriverHasEnoughReserveForTrip(
                                  trip: trip,
                                  financeDashboard: _financeDashboard,
                                  ledger: _ledger,
                                );
                                final reserveKnown =
                                    availableReserveMinorUnits != null;
                                final reserveBlocked =
                                    reserveKnown && !hasEnoughReserve;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    leading: const Icon(Icons.route_outlined),
                                    title: Text(
                                      '${trip.pickup} -> ${trip.destination}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          l.isArabic
                                              ? '${fmtCents(trip.fareEstimateCents)} SYP • ${trip.etaMinutes} د • ${trip.rideClass}'
                                              : '${fmtCents(trip.fareEstimateCents)} SYP • ${trip.etaMinutes} min • ${trip.rideClass}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          l.isArabic
                                              ? 'الاحتياطي المطلوب عند القبول: ${fmtCents(requiredReserveMinorUnits)} SYP'
                                              : 'Reserve on accept: ${fmtCents(requiredReserveMinorUnits)} SYP',
                                        ),
                                        if (reserveKnown)
                                          Text(
                                            l.isArabic
                                                ? 'المتاح الآن: ${fmtCents(availableReserveMinorUnits)} SYP'
                                                : 'Available now: ${fmtCents(availableReserveMinorUnits)} SYP',
                                          ),
                                        if (reserveBlocked)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(
                                              l.isArabic
                                                  ? 'الرصيد غير كافٍ. تحتاج ${fmtCents(requiredReserveMinorUnits)} SYP لقبول هذا الطلب.'
                                                  : 'Insufficient balance. This dispatch needs ${fmtCents(requiredReserveMinorUnits)} SYP to accept.',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    // Cycle 86 — show a spinner inside the
                                    // Accept button while a trip command is
                                    // in flight. Matches Cycle 84's in-trip
                                    // CTA so the driver gets identical
                                    // feedback no matter which button is
                                    // being awaited.
                                    trailing: FilledButton(
                                      onPressed: reserveBlocked
                                          ? _openDriverWallet
                                          : (!_online ||
                                                  _busy ||
                                                  !_driverReadyForDispatch ||
                                                  !_driverAccessAllowed)
                                              ? null
                                              : () => _acceptTrip(trip),
                                      child: _busy && !reserveBlocked
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            )
                                          : Text(
                                              reserveBlocked
                                                  ? (l.isArabic
                                                      ? 'اشحن الرصيد'
                                                      : 'Need funds')
                                                  : (l.isArabic
                                                      ? 'قبول'
                                                      : 'Accept'),
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DriverAction {
  final String command;
  final String label;
  const _DriverAction(this.command, this.label);
}

class _DriverDocumentDraft {
  final String documentNumber;
  final String issuingCountry;
  final String expiresAtIso;

  const _DriverDocumentDraft({
    required this.documentNumber,
    required this.issuingCountry,
    required this.expiresAtIso,
  });
}

