import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:url_launcher/url_launcher.dart';

import '../account_identity_store.dart';
import '../app_surface.dart';
import '../device_id.dart';
import '../format.dart';
import '../l10n.dart';
import '../notification_service.dart';
import '../payments/payments_shell.dart';
import '../privacy_redaction.dart';
import '../ride_chat_api.dart';
import '../ride_chat_sheet.dart';
import '../ride_rating_api.dart';
import '../ride_history_page.dart';
import '../cancellation_reason_picker.dart';
import '../coach_bus/coach_bus_mini_program_page.dart';
import '../promo_api.dart';
import '../promo_entry_dialog.dart';
import '../ride_share_api.dart';
import '../ride_share_dialog.dart';
import '../ride_tip_api.dart';
import '../ride_tip_dialog.dart';
import '../safety_alerts_api.dart';
import '../saved_places_page.dart';
import '../scheduled_rides_page.dart';
import '../sos_dialog.dart';
import '../ride_rating_dialog.dart';
import '../push_readiness_banner.dart';
import '../shamell_loading_shimmer.dart';
import '../shamell_phase_strip.dart';
import '../shamell_support.dart';
import '../wechat_ui.dart';
import 'ride_mobility_api.dart';
import 'ride_hailing_store.dart';
import 'ride_pickup_pin_page.dart';
import 'ride_platform_contracts.dart';
import 'ride_taxi_feature_widgets.dart';
import 'ride_trip_map_card.dart';
import 'ride_trip_map_support.dart';

enum _RideClass { economy, comfort, van }

enum _PickupSelectionMode { search, currentLocation, pinnedMap }

enum RideBookingValidationIssue {
  activeTripInProgress,
  pickupMissing,
  pickupUnresolved,
  destinationMissing,
  destinationUnresolved,
  samePlace,
}

enum RidePlaceSuggestionFeedback { none, noResults, unavailable }

const Duration _ridePersistedActiveTripDiscardThreshold = Duration(minutes: 15);
const RideSearchPlace _rideSavedRoutePickupPlace = RideSearchPlace(
  displayName: 'Bab Touma Damascus',
  point: RideGeoPoint(lat: 33.5138, lon: 36.3138),
);
const RideSearchPlace _rideSavedRouteDestinationPlace = RideSearchPlace(
  displayName: 'Malki Damascus',
  point: RideGeoPoint(lat: 33.5152, lon: 36.29637),
);

class _RideLiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _RideLiquidGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .38 : .82),
          width: .7,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? .16 : .045),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}


@visibleForTesting
maplibre.LatLng rideHailingInitialMapTarget({
  required List<maplibre.LatLng> routePreviewPoints,
  required RideGeoPoint? currentLocation,
}) {
  return rideTripMapInitialTarget(
    snapshot: RideTripMapSnapshot(
      routePoints: routePreviewPoints,
      driverLocation: null,
      pickupLocation: null,
      destinationLocation: null,
    ),
    currentLocation: currentLocation,
  );
}

@visibleForTesting
double rideHailingInitialMapZoom({
  required List<maplibre.LatLng> routePreviewPoints,
  required RideGeoPoint? currentLocation,
}) {
  return rideTripMapInitialZoom(
    snapshot: RideTripMapSnapshot(
      routePoints: routePreviewPoints,
      driverLocation: null,
      pickupLocation: null,
      destinationLocation: null,
    ),
    currentLocation: currentLocation,
  );
}

String _rideClassCode(_RideClass rideClass) {
  switch (rideClass) {
    case _RideClass.economy:
      return 'economy';
    case _RideClass.comfort:
      return 'comfort';
    case _RideClass.van:
      return 'van';
  }
}

String _rideClassLabel(_RideClass rideClass, {required bool isArabic}) {
  switch (rideClass) {
    case _RideClass.economy:
      return isArabic ? 'اقتصادي' : 'Economy';
    case _RideClass.comfort:
      return isArabic ? 'مريح' : 'Comfort';
    case _RideClass.van:
      return isArabic ? 'فان' : 'Van';
  }
}

String _rideStatusLabel(RideTripStatus status, {required bool isArabic}) {
  switch (status) {
    case RideTripStatus.idle:
      return isArabic ? 'خامل' : 'Idle';
    case RideTripStatus.quoteShown:
      return isArabic ? 'تم عرض السعر' : 'Quote shown';
    case RideTripStatus.rideRequested:
      return isArabic ? 'تم طلب الرحلة' : 'Ride requested';
    case RideTripStatus.matching:
      return isArabic ? 'جارٍ المطابقة' : 'Matching';
    case RideTripStatus.driverAssigned:
      return isArabic ? 'تم تعيين السائق' : 'Driver assigned';
    case RideTripStatus.driverArriving:
      return isArabic ? 'السائق في الطريق' : 'Driver arriving';
    case RideTripStatus.driverArrived:
      return isArabic ? 'السائق وصل' : 'Driver arrived';
    case RideTripStatus.tripStarted:
      return isArabic ? 'بدأت الرحلة' : 'Trip started';
    case RideTripStatus.tripInProgress:
      return isArabic ? 'الرحلة جارية' : 'Trip in progress';
    case RideTripStatus.tripCompleted:
      return isArabic ? 'اكتملت الرحلة' : 'Trip completed';
    case RideTripStatus.canceled:
      return isArabic ? 'ملغاة' : 'Canceled';
    case RideTripStatus.paymentFailed:
      return isArabic ? 'فشل الدفع' : 'Payment failed';
  }
}

/// Three-phase grouping that the phase indicator surfaces to the user.
/// The fine-grained RideTripStatus values stay in the per-section UI for
/// detail; the phase is the at-a-glance "what part of the journey am I in".
enum _RidePhase { plan, active, done }

_RidePhase _ridePhaseFor(RideTrip? activeTrip) {
  if (activeTrip == null) {
    return _RidePhase.plan;
  }
  switch (activeTrip.status) {
    case RideTripStatus.idle:
    case RideTripStatus.quoteShown:
    case RideTripStatus.rideRequested:
    case RideTripStatus.matching:
      return _RidePhase.plan;
    case RideTripStatus.driverAssigned:
    case RideTripStatus.driverArriving:
    case RideTripStatus.driverArrived:
    case RideTripStatus.tripStarted:
    case RideTripStatus.tripInProgress:
      return _RidePhase.active;
    case RideTripStatus.tripCompleted:
    case RideTripStatus.canceled:
    case RideTripStatus.paymentFailed:
      return _RidePhase.done;
  }
}

/// Builds the rider-facing phase strip for `AppBar.bottom`. The fine-
/// grained `RideTripStatus` only surfaces during the Active phase —
/// in Plan we already show the search form right below, and in Done a
/// receipt card carries the detail.
ShamellPhaseStrip _buildRidePhaseStrip({
  required _RidePhase phase,
  required RideTripStatus? activeStatus,
  required bool isArabic,
}) {
  final steps = <ShamellPhaseStep>[
    ShamellPhaseStep(
      icon: Icons.edit_location_alt_outlined,
      label: isArabic ? 'الخطة' : 'Plan',
    ),
    ShamellPhaseStep(
      icon: Icons.local_taxi_rounded,
      label: isArabic ? 'الرحلة' : 'Active',
    ),
    ShamellPhaseStep(
      icon: Icons.check_circle_outline_rounded,
      label: isArabic ? 'انتهت' : 'Done',
    ),
  ];
  final activeIndex = switch (phase) {
    _RidePhase.plan => 0,
    _RidePhase.active => 1,
    _RidePhase.done => 2,
  };
  final showSubStatus = phase == _RidePhase.active && activeStatus != null;
  return ShamellPhaseStrip(
    steps: steps,
    activeIndex: activeIndex,
    subStatusText: showSubStatus
        ? _rideStatusLabel(activeStatus, isArabic: isArabic)
        : null,
    semanticsLabel: isArabic
        ? 'مرحلة الرحلة ${activeIndex + 1} من 3: ${steps[activeIndex].label}'
        : 'Ride phase ${activeIndex + 1} of 3: ${steps[activeIndex].label}',
  );
}

@visibleForTesting
bool rideShouldDiscardPersistedActiveTrip({
  required bool authoritativeNoActiveFromServer,
  required RideTrip? trackingTrip,
  required RideTrip? persistedTrip,
  DateTime? now,
}) {
  if (!authoritativeNoActiveFromServer ||
      trackingTrip != null ||
      persistedTrip == null ||
      rideTripStatusIsTerminal(persistedTrip.status)) {
    return false;
  }
  final parsed = DateTime.tryParse(persistedTrip.lastUpdatedAtIso);
  if (parsed == null) {
    return false;
  }
  final reference = (now ?? DateTime.now()).toUtc();
  return reference.difference(parsed.toUtc()) >=
      _ridePersistedActiveTripDiscardThreshold;
}

@visibleForTesting
String rideNormalizePlaceInput(String raw) {
  final compact = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.length <= 80) return compact;
  return compact.substring(0, 80);
}

@visibleForTesting
bool ridePlaceSelectionMatchesQuery({
  required String query,
  required RideSearchPlace? selectedPlace,
}) {
  if (selectedPlace == null) {
    return false;
  }
  final normalizedQuery = rideNormalizePlaceInput(query).toLowerCase();
  final normalizedSelected =
      rideNormalizePlaceInput(selectedPlace.displayName).toLowerCase();
  if (normalizedQuery.isEmpty || normalizedSelected.isEmpty) {
    return false;
  }
  return normalizedQuery == normalizedSelected;
}

@visibleForTesting
bool ridePlacesResolveSameLocation({
  required String pickupQuery,
  required String destinationQuery,
  required RideSearchPlace? selectedPickup,
  required RideSearchPlace? selectedDestination,
}) {
  final normalizedPickup = rideNormalizePlaceInput(pickupQuery).toLowerCase();
  final normalizedDestination =
      rideNormalizePlaceInput(destinationQuery).toLowerCase();
  if (normalizedPickup.isNotEmpty &&
      normalizedPickup == normalizedDestination) {
    return true;
  }
  if (selectedPickup == null || selectedDestination == null) {
    return false;
  }
  const coordinateTolerance = 0.00015;
  return (selectedPickup.point.lat - selectedDestination.point.lat).abs() <=
          coordinateTolerance &&
      (selectedPickup.point.lon - selectedDestination.point.lon).abs() <=
          coordinateTolerance;
}

@visibleForTesting
RideBookingValidationIssue? rideBookingValidationIssue({
  required String pickupQuery,
  required String destinationQuery,
  required RideSearchPlace? selectedPickup,
  required RideSearchPlace? selectedDestination,
  required bool hasActiveTrip,
}) {
  if (hasActiveTrip) {
    return RideBookingValidationIssue.activeTripInProgress;
  }
  final normalizedPickup = rideNormalizePlaceInput(pickupQuery);
  if (normalizedPickup.isEmpty) {
    return RideBookingValidationIssue.pickupMissing;
  }
  if (!ridePlaceSelectionMatchesQuery(
    query: normalizedPickup,
    selectedPlace: selectedPickup,
  )) {
    return RideBookingValidationIssue.pickupUnresolved;
  }
  final normalizedDestination = rideNormalizePlaceInput(destinationQuery);
  if (normalizedDestination.isEmpty) {
    return RideBookingValidationIssue.destinationMissing;
  }
  if (!ridePlaceSelectionMatchesQuery(
    query: normalizedDestination,
    selectedPlace: selectedDestination,
  )) {
    return RideBookingValidationIssue.destinationUnresolved;
  }
  if (ridePlacesResolveSameLocation(
    pickupQuery: normalizedPickup,
    destinationQuery: normalizedDestination,
    selectedPickup: selectedPickup,
    selectedDestination: selectedDestination,
  )) {
    return RideBookingValidationIssue.samePlace;
  }
  return null;
}

@visibleForTesting
RidePlaceSuggestionFeedback ridePlaceSuggestionFeedback({
  required String query,
  required bool loading,
  required bool unavailable,
  required List<RideSearchPlace> suggestions,
}) {
  final normalizedQuery = rideNormalizePlaceInput(query);
  if (loading || normalizedQuery.length < 2) {
    return RidePlaceSuggestionFeedback.none;
  }
  if (unavailable) {
    return RidePlaceSuggestionFeedback.unavailable;
  }
  if (suggestions.isEmpty) {
    return RidePlaceSuggestionFeedback.noResults;
  }
  return RidePlaceSuggestionFeedback.none;
}

@visibleForTesting
String? rideActiveTripSemanticsSummaryLabel({
  required RideTrip? trip,
  required RideLiveTrackingSnapshot? trackingSnapshot,
  required bool isArabic,
  required String? Function(String? iso, {required bool isArabic})
      trackingAgeLabel,
}) {
  if (trip == null) return null;
  final lines = <String>[
    isArabic ? 'ملخص الرحلة الحالية' : 'Current ride summary',
    '${_rideStatusLabel(trip.status, isArabic: isArabic)} • '
        '${trip.driverName} • ${shamellMaskVehiclePlate(trip.carPlate)}',
    isArabic
        ? 'من ${trip.pickup} إلى ${trip.destination}'
        : '${trip.pickup} -> ${trip.destination}',
    isArabic
        ? 'التقدير ${fmtCents(trip.fareEstimateCents)} SYP • ETA ${trip.etaMinutes} د'
        : 'Estimate ${fmtCents(trip.fareEstimateCents)} SYP • ETA ${trip.etaMinutes} min',
  ];
  final latestDriverLocation = trackingSnapshot?.latestDriverLocation;
  if (latestDriverLocation != null) {
    final age = trackingAgeLabel(
      latestDriverLocation.createdAtIso,
      isArabic: isArabic,
    );
    lines.add(
      isArabic
          ? 'آخر تحديث للسائق: ${age ?? latestDriverLocation.createdAtIso}'
          : 'Driver last update: ${age ?? latestDriverLocation.createdAtIso}',
    );
    final location = latestDriverLocation.location;
    if (location != null) {
      lines.add(
        isArabic
            ? 'الموقع التقريبي ${shamellApproximateCoordinatePair(lat: location.lat, lon: location.lon)}'
            : 'Approx. location ${shamellApproximateCoordinatePair(lat: location.lat, lon: location.lon)}',
      );
    }
  }
  if (trackingSnapshot != null && trackingSnapshot.timeline.isNotEmpty) {
    lines.add(
      isArabic
          ? 'التتبع المباشر: ${trackingSnapshot.timeline.length} تحديثات'
          : 'Live tracking: ${trackingSnapshot.timeline.length} updates',
    );
  }
  return lines.join('\n');
}

@visibleForTesting
bool rideHailingShowsSavedRouteMenu({required bool standaloneApp}) {
  return kDebugMode && standaloneApp;
}

String? _rideCommandForTargetStatus(RideTripStatus status) {
  switch (status) {
    case RideTripStatus.matching:
      return 'enter_matching';
    case RideTripStatus.driverAssigned:
      return 'assign_driver';
    case RideTripStatus.driverArriving:
      return 'mark_driver_arriving';
    case RideTripStatus.driverArrived:
      return 'mark_driver_arrived';
    case RideTripStatus.tripStarted:
      return 'start_trip';
    case RideTripStatus.tripInProgress:
      return 'mark_in_progress';
    case RideTripStatus.paymentFailed:
      return 'mark_payment_failed';
    case RideTripStatus.tripCompleted:
      return 'complete_trip';
    case RideTripStatus.canceled:
      return 'cancel_trip';
    case RideTripStatus.idle:
    case RideTripStatus.quoteShown:
    case RideTripStatus.rideRequested:
      return null;
  }
}

bool _rideTripHasAssignedDriver(RideTrip trip) {
  final driverName = trip.driverName.trim().toLowerCase();
  final carPlate = trip.carPlate.trim();
  if (driverName.isEmpty || driverName == 'driver pending') {
    return false;
  }
  if (carPlate.isEmpty || carPlate == '--') {
    return false;
  }
  return true;
}

class RideHailingPage extends StatefulWidget {
  final String? baseUrl;
  final String? initialRideId;
  final bool runStartupTasks;
  final bool standaloneApp;

  const RideHailingPage({
    super.key,
    this.baseUrl,
    this.initialRideId,
    this.runStartupTasks = true,
    this.standaloneApp = false,
  });

  @override
  State<RideHailingPage> createState() => _RideHailingPageState();
}

class _RideHailingPageState extends State<RideHailingPage> {
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _destinationCtrl = TextEditingController();
  /// Cycle 65/66 — drives the new draggable bottom sheet. The peek
  /// hero at the top of the sheet calls `animateTo(0.92)` to slide
  /// the full booking form into view.
  final DraggableScrollableController _hailingSheetCtrl =
      DraggableScrollableController();
  final FocusNode _destinationFocus = FocusNode();
  late final RideMobilityApi _mobilityApi =
      RideMobilityApi(baseUrl: widget.baseUrl ?? '');
  Timer? _pickupSearchDebounce;
  Timer? _destinationSearchDebounce;
  Timer? _pollTimer;
  Timer? _updatesRetryTimer;
  StreamSubscription<String>? _updatesSub;
  bool _suppressPickupOnChanged = false;
  bool _suppressDestinationOnChanged = false;
  _RideClass _rideClass = _RideClass.economy;
  RideTrip? _activeTrip;
  RideLiveTrackingSnapshot? _trackingSnapshot;
  List<RideTrip> _history = const <RideTrip>[];
  List<RideSupportTicket> _supportTickets = const <RideSupportTicket>[];
  List<RideSearchPlace> _pickupSuggestions = const <RideSearchPlace>[];
  List<RideSearchPlace> _destinationSuggestions = const <RideSearchPlace>[];
  RideSearchPlace? _selectedPickup;
  RideSearchPlace? _selectedDestination;
  bool _loadingPickupSuggestions = false;
  bool _loadingDestinationSuggestions = false;
  bool _pickupSearchUnavailable = false;
  bool _destinationSearchUnavailable = false;
  int _pickupSearchGeneration = 0;
  int _destinationSearchGeneration = 0;
  RidePlatformBootstrap? _platformBootstrap;
  RideRouteQuote? _lastRouteQuote;
  RideTrafficSnapshot? _lastTrafficSnapshot;
  RidePricingPreview? _lastPricingPreview;
  RiderWalletSnapshot? _walletSnapshot;
  String _walletId = '';
  String _selectedRideCurrency = 'SYP';
  String _selectedRidePaymentMode = 'Wallet';
  String _selectedRideFareMode = 'Fixed';
  String _selectedRideRoutePreference = 'Fastest';
  String _selectedRideProfile = 'Standard';
  String _selectedRideBusinessMode = 'Personal';
  bool _ridePoolingEnabled = false;
  bool _rideFamilyModeEnabled = false;
  bool _favoriteDriverModeEnabled = false;
  int _extraRideStopCount = 0;
  int _selectedTipPercent = 10;
  String _ridePickupCode = '';
  bool _rideRouteDeviationAlertsEnabled = true;
  int _rideWaitingGraceMinutes = 3;
  String _selectedRideCancellationRule = 'Grace 3 min';
  String _selectedRideAccessibilityNeed = 'None';
  bool _petTaxiEnabled = false;
  bool _packageRideEnabled = false;
  bool _recurringRideEnabled = false;
  bool _pickupInstructionsReady = false;
  int _fareSplitContactCount = 0;
  int _promoCreditMinorUnits = 0;
  bool _surgeExplanationVisible = false;
  List<maplibre.LatLng> _routePreviewPoints = const <maplibre.LatLng>[];
  RideTripMapSnapshot? _tripMapSnapshot;
  bool _requestingProviderEstimate = false;
  RideTripStatus? _lastNotifiedActiveStatus;
  bool _loading = true;
  bool _locationPermissionRequested = false;
  RideGeoPoint? _currentLocation;
  _PickupSelectionMode? _pickupSelectionMode;
  bool _destinationPinnedOnMap = false;

  bool get _showSavedRouteMenu =>
      rideHailingShowsSavedRouteMenu(standaloneApp: widget.standaloneApp);

  @override
  void initState() {
    super.initState();
    if (widget.runStartupTasks) {
      unawaited(_loadInitialCurrentLocation());
      unawaited(_loadState());
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _pickupSearchDebounce?.cancel();
    _destinationSearchDebounce?.cancel();
    _pollTimer?.cancel();
    _updatesRetryTimer?.cancel();
    _updatesSub?.cancel();
    _pickupCtrl.dispose();
    _destinationCtrl.dispose();
    _destinationFocus.dispose();
    _hailingSheetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final history =
        await loadRideHailingHistory(baseUrlOverride: widget.baseUrl);
    final persistedActive =
        await loadActiveRideHailingTrip(baseUrlOverride: widget.baseUrl);
    final activeSnapshot = await _mobilityApi.activeTripSnapshot();
    final activeFromServer = activeSnapshot.trip;
    final trackingSeed = activeFromServer ?? persistedActive;
    final trackingSnapshot = trackingSeed == null
        ? null
        : await _mobilityApi.trackingSnapshot(trackingSeed.rideId);
    final discardPersistedActive = rideShouldDiscardPersistedActiveTrip(
      authoritativeNoActiveFromServer:
          activeSnapshot.authoritativeNoActiveFromServer,
      trackingTrip: trackingSnapshot?.ride,
      persistedTrip: persistedActive,
    );
    final active = resolveBestRideActiveTrip(
      serverTrip: activeFromServer,
      trackingTrip: trackingSnapshot?.ride,
      persistedTrip: discardPersistedActive ? null : persistedActive,
    );
    final walletId =
        (await loadStoredWalletId(baseUrlOverride: widget.baseUrl) ?? '')
            .trim();
    final riderId =
        await loadStoredShamellUserId(baseUrlOverride: widget.baseUrl);
    final walletSnapshot = walletId.isEmpty
        ? null
        : await _mobilityApi.riderWalletSnapshot(
            walletId: walletId,
            riderId: riderId,
          );
    if (active != null) {
      await saveActiveRideHailingTrip(active, baseUrlOverride: widget.baseUrl);
      await upsertRideHailingHistoryTrip(active,
          baseUrlOverride: widget.baseUrl);
    } else if (persistedActive != null || discardPersistedActive) {
      await saveActiveRideHailingTrip(null, baseUrlOverride: widget.baseUrl);
    }
    final bootstrap = await _mobilityApi.bootstrapConfig();
    final tripMapSnapshot =
        await _buildActiveTripMapSnapshot(active, trackingSnapshot);
    final supportTickets =
        (await _mobilityApi.supportTickets(limit: 6))?.tickets ??
            const <RideSupportTicket>[];
    if (!mounted) return;
    setState(() {
      _history = history;
      _activeTrip = active;
      _trackingSnapshot = trackingSnapshot;
      _supportTickets = supportTickets;
      _platformBootstrap = bootstrap;
      _walletId = walletId;
      _walletSnapshot = walletSnapshot;
      _tripMapSnapshot = tripMapSnapshot;
      _loading = false;
    });
    _lastNotifiedActiveStatus = active?.status;
    _startPolling();
    _startUpdatesStream();
    // Cycle 68 — sheet snap follows trip state after initial load.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSheetForActiveTrip();
    });
  }

  Future<void> _loadInitialCurrentLocation() async {
    final currentLocation = await _resolveCurrentLocation();
    if (!mounted || currentLocation == null) return;
    setState(() {
      _currentLocation = currentLocation;
    });
  }

  Future<RideGeoPoint?> _resolveCurrentLocation({
    bool forcePermissionRequest = false,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied &&
        (!_locationPermissionRequested || forcePermissionRequest)) {
      _locationPermissionRequested = true;
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return RideGeoPoint(lat: position.latitude, lon: position.longitude);
    } catch (_) {
      return null;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshActiveTripState(showNotifications: true));
    });
  }

  void _startUpdatesStream() {
    _updatesRetryTimer?.cancel();
    _updatesSub?.cancel();
    _updatesSub = _mobilityApi.activeTripUpdateStream().listen(
          (_) => unawaited(_refreshActiveTripState(showNotifications: true)),
          onDone: _scheduleUpdatesRetry,
          onError: (_, __) => _scheduleUpdatesRetry(),
          cancelOnError: true,
        );
  }

  void _scheduleUpdatesRetry() {
    if (!mounted) {
      return;
    }
    _updatesRetryTimer?.cancel();
    _updatesRetryTimer = Timer(
      const Duration(seconds: 3),
      _startUpdatesStream,
    );
  }

  Future<void> _refreshActiveTripState(
      {required bool showNotifications}) async {
    final persistedActive = _activeTrip;
    final activeSnapshot = await _mobilityApi.activeTripSnapshot();
    final nextServerActive = activeSnapshot.trip;
    final trackingSeed = nextServerActive ?? persistedActive;
    final nextTracking = trackingSeed == null
        ? null
        : await _mobilityApi.trackingSnapshot(trackingSeed.rideId);
    final discardPersistedActive = rideShouldDiscardPersistedActiveTrip(
      authoritativeNoActiveFromServer:
          activeSnapshot.authoritativeNoActiveFromServer,
      trackingTrip: nextTracking?.ride,
      persistedTrip: persistedActive,
    );
    final nextActive = resolveBestRideActiveTrip(
      serverTrip: nextServerActive,
      trackingTrip: nextTracking?.ride,
      persistedTrip: discardPersistedActive ? null : persistedActive,
    );
    final nextMapSnapshot =
        await _buildActiveTripMapSnapshot(nextActive, nextTracking);
    final nextSupportTickets =
        (await _mobilityApi.supportTickets(limit: 6))?.tickets ??
            _supportTickets;
    if (nextActive != null) {
      await saveActiveRideHailingTrip(nextActive,
          baseUrlOverride: widget.baseUrl);
      await upsertRideHailingHistoryTrip(nextActive,
          baseUrlOverride: widget.baseUrl);
    } else if (persistedActive != null || discardPersistedActive) {
      await saveActiveRideHailingTrip(null, baseUrlOverride: widget.baseUrl);
    }
    if (!mounted) return;
    if (showNotifications) {
      await _emitActiveTripNotifications(nextActive);
    }
    final wasActive = _activeTrip != null;
    setState(() {
      _activeTrip = nextActive;
      _trackingSnapshot = nextTracking;
      _tripMapSnapshot = nextMapSnapshot;
      _supportTickets = nextSupportTickets;
      if (nextActive != null) {
        final nextHistory = _history
            .where((trip) => trip.rideId != nextActive.rideId)
            .toList(growable: true);
        nextHistory.insert(0, nextActive);
        _history = nextHistory.take(12).toList(growable: false);
      }
    });
    // Cycle 68 — slide the sheet on trip-state transitions only,
    // not on every poll-tick (the helper itself is idempotent but a
    // pointless animateTo every 2 s would be wasteful).
    if (wasActive != (nextActive != null)) {
      _syncSheetForActiveTrip();
    }
  }

  /// Cycle 136 — prompt the rider to rate the just-completed trip.
  /// Skips if they already submitted a rating (server is the
  /// source of truth — we GET /rating first and bail on a 200).
  /// "Later" dismissal is non-persistent for now; if the trip
  /// stays terminal across polls, we won't re-prompt because the
  /// poll's "transition" gate only fires on the first flip.
  /// Cycle 152 — opens the SOS confirm dialog. Called from the
  /// active-trip card's red SOS button. The dialog itself does the
  /// hold-to-confirm UX + GPS capture + API POST. We just show a
  /// follow-up snackbar so the rider feels acknowledged.
  Future<void> _openSosDialog(String rideId) async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    final api = SafetyAlertsApi(baseUrl: baseUrl);
    final isArabic = L10n.of(context).isArabic;
    final result = await showSosConfirmDialog(
      context: context,
      api: api,
      rideId: rideId,
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

  /// Cycle 182 — opens the rider's past-trip history page with
  /// fare receipts + own ratings.
  Future<void> _openRideHistoryPage() async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => RideHistoryPage(
          baseUrl: baseUrl,
          kind: RideHistoryKind.rider,
        ),
      ),
    );
  }

  /// Cycle 217 — opens the Coach Bus passenger surface. Per user
  /// feedback (2026-05-29), lands directly on the search/plan tab of
  /// the full mini-program shell (Plan / Trips / Tickets) rather than
  /// the older Hub page that puts a hero CTA in front of search.
  /// Same end-to-end flow (search → offers → booking → live
  /// tracking), one tap fewer to start a new journey.
  Future<void> _openCoachBusHub() async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => CoachBusMiniProgramPage(baseUrl: baseUrl),
      ),
    );
  }

  /// Cycle 208 — opens the promo code entry dialog. Rider can
  /// validate any code (we pass the current fare estimate so the
  /// server resolves the exact discount cents).
  Future<void> _openPromoEntry() async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    final isArabic = L10n.of(context).isArabic;
    final fareCents = _lastPricingPreview?.totalFareMinorUnits ??
        (_lastRouteQuote != null
            ? _fareFromTomTomRoute(_lastRouteQuote!)
            : null);
    await showPromoEntryDialog(
      context: context,
      api: PromoApi(baseUrl: baseUrl),
      isArabic: isArabic,
      fareEstimateCents: fareCents,
    );
  }

  /// Cycle 189 — opens the saved-places manager. Quick win for
  /// daily commuters; the page handles its own create/edit/delete.
  Future<void> _openSavedPlacesManager() async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => SavedPlacesPage(baseUrl: baseUrl),
      ),
    );
  }

  /// Cycle 175 — opens the "My scheduled rides" surface. Future-
  /// pickup bookings are handled there end-to-end (list, create,
  /// cancel). Bails quietly if baseUrl isn't ready yet.
  Future<void> _openScheduledRidesPage() async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => MyScheduledRidesPage(baseUrl: baseUrl),
      ),
    );
  }

  /// Cycle 161 — opens the share-trip dialog. Mints a fresh token
  /// on dialog open; the dialog handles the rest (share intent,
  /// copy, revoke).
  Future<void> _openShareDialog(String rideId) async {
    if (!mounted) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    final isArabic = L10n.of(context).isArabic;
    await showRideShareDialog(
      context: context,
      api: RideShareApi(baseUrl: baseUrl),
      rideId: rideId,
      isArabic: isArabic,
    );
  }

  Future<void> _maybePromptRideRating(RideTrip trip) async {
    if (!mounted) return;
    final ratingBaseUrl = widget.baseUrl;
    if (ratingBaseUrl == null) return;
    final api = RideRatingApi(baseUrl: ratingBaseUrl);
    try {
      final existing = await api.getOwnRating(rideId: trip.rideId);
      if (existing != null) {
        // Already rated; still offer a tip prompt if they qualify
        // and haven't tipped yet. Keeps the "thank your driver"
        // path open even if rating happened earlier.
        unawaited(_maybePromptRideTip(trip, ratedStars: existing.stars));
        return;
      }
    } catch (_) {
      // Best-effort — if the lookup fails, still offer the dialog.
    }
    if (!mounted) return;
    final isArabic = L10n.of(context).isArabic;
    final submitted = await showRideRatingDialog(
      context: context,
      api: api,
      rideId: trip.rideId,
      driverDisplayName: trip.driverName.trim().isEmpty
          ? (isArabic ? 'السائق' : 'your driver')
          : trip.driverName,
      isArabic: isArabic,
    );
    if (submitted != true || !mounted) return;
    // Cycle 195 — chain into the tip prompt for happy ratings.
    // We re-fetch the rating to read the stars (the dialog
    // returns only a bool); if the lookup fails we conservatively
    // skip the tip step.
    try {
      final saved = await api.getOwnRating(rideId: trip.rideId);
      if (saved == null || !mounted) return;
      await _maybePromptRideTip(trip, ratedStars: saved.stars);
    } catch (_) {
      // best-effort
    }
  }

  /// Cycle 195 — opens the tip dialog when the rider gave 4+ stars
  /// and hasn't already tipped this trip. Fire-and-forget.
  Future<void> _maybePromptRideTip(
    RideTrip trip, {
    required int ratedStars,
  }) async {
    if (!mounted) return;
    if (ratedStars < 4) return;
    final baseUrl = widget.baseUrl;
    if (baseUrl == null) return;
    final api = RideTipApi(baseUrl: baseUrl);
    try {
      final existing = await api.getOwnTip(rideId: trip.rideId);
      if (existing != null && existing.amountCents > 0) return;
    } catch (_) {
      // ignore, still offer
    }
    if (!mounted) return;
    final isArabic = L10n.of(context).isArabic;
    final tip = await showRideTipDialog(
      context: context,
      api: api,
      rideId: trip.rideId,
      tripFareCents: trip.fareEstimateCents,
      driverDisplayName: trip.driverName.trim().isEmpty
          ? (isArabic ? 'السائق' : 'your driver')
          : trip.driverName,
      isArabic: isArabic,
    );
    if (tip != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFFA000),
          duration: const Duration(seconds: 4),
          content: Text(
            isArabic
                ? 'شكراً! تم إرسال الإكرامية.'
                : 'Thank you — the tip is on its way.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _emitActiveTripNotifications(RideTrip? nextActive) async {
    final nextStatus = nextActive?.status;
    if (_lastNotifiedActiveStatus != null &&
        nextActive != null &&
        nextStatus != null &&
        nextStatus != _lastNotifiedActiveStatus) {
      final isArabic = L10n.of(context).isArabic;
      final label = _rideStatusLabel(nextStatus, isArabic: isArabic);
      await NotificationService.showRiderTripUpdate(
        rideId: nextActive.rideId,
        title: isArabic ? 'تحديث حالة الرحلة' : 'Ride update',
        body: isArabic
            ? '$label • ${nextActive.pickup}'
            : '$label • ${nextActive.pickup}',
      );
      if (!mounted) return;
      // Cycle 117 — when the trip completes, replace the generic
      // "Current ride updated" SnackBar with a celebratory toast
      // showing the final fare. Closes the journey loop and gives
      // the rider a clear "you're done" moment.
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
                    isArabic
                        ? 'شكراً لاستخدامك سرتشات! الأجرة: ${fmtCents(nextActive.fareEstimateCents)} SYP'
                        : 'Thanks for riding with SyrChat! Fare: ${fmtCents(nextActive.fareEstimateCents)} SYP',
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
        // Cycle 136 — prompt for a rating. Fire-and-forget so the
        // poll loop doesn't block, and the helper itself swallows
        // already-rated trips so it's safe on repeat ticks.
        unawaited(_maybePromptRideRating(nextActive));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'تم تحديث الرحلة الحالية: $label'
                  : 'Current ride updated: $label',
            ),
          ),
        );
      }
    }
    _lastNotifiedActiveStatus = nextStatus;
  }

  Future<void> _contactSupportByMail() async {
    final uri = shamellSupportEmailUri(subject: 'Ride rider support');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _contactSupportByPhone() async {
    await launchUrl(
      shamellSupportPhoneUri(),
      mode: LaunchMode.externalApplication,
    );
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

  String _supportTicketStatusLabel(
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

  String _supportContactLabel(
    RideSupportTicketContactPreference contact, {
    required bool isArabic,
  }) {
    switch (contact) {
      case RideSupportTicketContactPreference.inApp:
        return isArabic ? 'داخل التطبيق' : 'In app';
      case RideSupportTicketContactPreference.email:
        return isArabic ? 'البريد' : 'Email';
      case RideSupportTicketContactPreference.phone:
        return isArabic ? 'الهاتف' : 'Phone';
    }
  }

  Future<void> _openSupportTicketComposer({
    RideSupportTicketCategory initialCategory =
        RideSupportTicketCategory.bookingIssue,
  }) async {
    final isArabic = L10n.of(context).isArabic;
    var category = initialCategory;
    var contact = RideSupportTicketContactPreference.inApp;
    final bodyCtrl = TextEditingController();
    final rideId = _activeTrip?.rideId ??
        (_history.isNotEmpty ? _history.first.rideId : '');
    final (RideSupportTicketCategory, RideSupportTicketContactPreference, String)?
        submitted;
    try {
      submitted = await showDialog<
          (
            RideSupportTicketCategory,
            RideSupportTicketContactPreference,
            String
          )>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(isArabic ? 'فتح تذكرة دعم' : 'Open support ticket'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<RideSupportTicketCategory>(
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: isArabic ? 'نوع المشكلة' : 'Issue type',
                  ),
                  items: RideSupportTicketCategory.values
                      .map(
                        (item) => DropdownMenuItem<RideSupportTicketCategory>(
                          value: item,
                          child: Text(
                            _supportCategoryLabel(item, isArabic: isArabic),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => category = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RideSupportTicketContactPreference>(
                  initialValue: contact,
                  decoration: InputDecoration(
                    labelText: isArabic ? 'قناة التواصل' : 'Reply via',
                  ),
                  items: RideSupportTicketContactPreference.values
                      .map(
                        (item) => DropdownMenuItem<
                            RideSupportTicketContactPreference>(
                          value: item,
                          child: Text(
                            _supportContactLabel(item, isArabic: isArabic),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => contact = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: isArabic ? 'اشرح المشكلة' : 'Describe the issue',
                    hintText: rideId.isEmpty
                        ? null
                        : (isArabic
                            ? 'سيتم ربط التذكرة بالرحلة $rideId'
                            : 'Ticket will be linked to ride $rideId'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(isArabic ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop((
                  category,
                  contact,
                  bodyCtrl.text.trim(),
                )),
                child: Text(isArabic ? 'إرسال' : 'Submit'),
              ),
            ],
          ),
        );
      },
      );
    } finally {
      bodyCtrl.dispose();
    }
    if (submitted == null || submitted.$3.isEmpty) {
      return;
    }
    final created = await _mobilityApi.createSupportTicket(
      rideId: rideId.isEmpty ? null : rideId,
      category: submitted.$1,
      body: submitted.$3,
      preferredContact: submitted.$2,
    );
    if (!mounted) {
      return;
    }
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تعذر إنشاء تذكرة الدعم.'
                : 'Could not create support ticket.',
          ),
        ),
      );
      return;
    }
    final tickets = (await _mobilityApi.supportTickets(limit: 6))?.tickets ??
        _supportTickets;
    if (!mounted) {
      return;
    }
    setState(() {
      _supportTickets = tickets;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isArabic
              ? 'تم إنشاء تذكرة الدعم ${created.ticketId}.'
              : 'Support ticket created: ${created.ticketId}.',
        ),
      ),
    );
  }

  void _showRideFeatureNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openRideWallet({
    String initialSection = 'overview',
    bool triggerScanOnOpen = false,
    int? initialAmountMinorUnits,
  }) async {
    final walletId = _walletId.trim();
    final isArabic = L10n.of(context).isArabic;
    if (walletId.isEmpty) {
      _showRideFeatureNotice(
        isArabic
            ? 'اربط محفظة SyrChat Pay قبل دفع رحلة التاكسي.'
            : 'Link a SyrChat Pay wallet before paying for taxi rides.',
      );
      return;
    }
    final deviceId =
        await getOrCreateStableDeviceId(baseUrlOverride: widget.baseUrl);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaymentsPage(
          widget.baseUrl ?? '',
          walletId,
          deviceId,
          triggerScanOnOpen: triggerScanOnOpen,
          initialAmountCents: initialAmountMinorUnits ??
              _activeTrip?.fareEstimateCents ??
              _lastPricingPreview?.totalFareMinorUnits,
          initialSection: initialSection,
          initialCurrency: _selectedRideCurrency,
          contextLabel: 'Taxi ride',
        ),
      ),
    );
  }

  Future<void> _openRidePaymentRequests() async {
    await _openRideWallet(initialSection: 'requests');
  }

  Future<void> _openRideQrPay() async {
    await _openRideWallet(
      initialSection: 'scan',
      triggerScanOnOpen: true,
    );
  }

  Future<void> _showRideSchedulingSheet() async {
    final isArabic = L10n.of(context).isArabic;
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final options = <String>[
          isArabic ? 'الآن' : 'Now',
          isArabic ? 'بعد 15 دقيقة' : 'In 15 minutes',
          isArabic ? 'بعد 30 دقيقة' : 'In 30 minutes',
          isArabic ? 'غدا صباحا' : 'Tomorrow morning',
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'جدولة رحلة تاكسي' : 'Schedule taxi ride',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in options)
                      ChoiceChip(
                        label: Text(option),
                        selected: false,
                        onSelected: (_) => Navigator.of(context).pop(option),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selection == null || !mounted) return;
    _showRideFeatureNotice(
      isArabic
          ? 'تم اختيار موعد الرحلة: $selection.'
          : 'Ride window selected: $selection.',
    );
  }

  Future<void> _showRideReceipt() async {
    final isArabic = L10n.of(context).isArabic;
    final trip = _activeTrip ?? (_history.isNotEmpty ? _history.first : null);
    if (trip == null) {
      _showRideFeatureNotice(
        isArabic
            ? 'لا يوجد إيصال رحلة بعد.'
            : 'No taxi receipt is available yet.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isArabic ? 'إيصال الرحلة' : 'Taxi receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${trip.pickup} -> ${trip.destination}'),
            const SizedBox(height: 8),
            Text(
              '${taxiRideStatusLabel(trip.status, isArabic: isArabic)} • '
              '${fmtCents(trip.fareEstimateCents)} SYP',
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'العملة المختارة: $_selectedRideCurrency'
                  : 'Selected currency: $_selectedRideCurrency',
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'طريقة التسوية: $_selectedRidePaymentMode'
                  : 'Settlement mode: $_selectedRidePaymentMode',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isArabic ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRateRideSheet() async {
    final isArabic = L10n.of(context).isArabic;
    int selectedRating = 5;
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isArabic ? 'تقييم الرحلة' : 'Rate this ride',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var rating = 1; rating <= 5; rating++)
                        ChoiceChip(
                          label: Text('$rating'),
                          selected: selectedRating == rating,
                          onSelected: (_) =>
                              setSheetState(() => selectedRating = rating),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(selectedRating),
                    icon: const Icon(Icons.star_outline),
                    label: Text(isArabic ? 'حفظ التقييم' : 'Save rating'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    _showRideFeatureNotice(
      isArabic
          ? 'تم حفظ تقييم الرحلة: $result/5.'
          : 'Ride rating saved: $result/5.',
    );
  }

  /// Cycle 167 — real ride chat. Replaces the Cycle-1ish canned-
  /// message stub with the persisted thread sheet. The sheet polls
  /// the BFF every 8s while open and sends optimistically.
  Future<void> _openRideChatSheet() async {
    if (!mounted) return;
    final isArabic = L10n.of(context).isArabic;
    final trip = _activeTrip;
    final baseUrl = widget.baseUrl;
    if (trip == null || baseUrl == null) {
      _showRideFeatureNotice(
        isArabic
            ? 'سترتبط المحادثة تلقائيا بعد تعيين السائق.'
            : 'Chat attaches automatically after a driver is assigned.',
      );
      return;
    }
    await showRideChatSheet(
      context: context,
      api: RideChatApi(baseUrl: baseUrl),
      rideId: trip.rideId,
      viewerRole: 'rider',
      isArabic: isArabic,
    );
  }

  Future<void> _startRideVoiceCall() async {
    final isArabic = L10n.of(context).isArabic;
    _showRideFeatureNotice(
      isArabic
          ? 'سيتم استخدام اتصال الدعم إلى أن يرسل السائق رقم اتصال موثق.'
          : 'Using support calling until the driver has a verified ride contact.',
    );
    await _contactSupportByPhone();
  }

  void _startRideVideoCall() {
    final isArabic = L10n.of(context).isArabic;
    _showRideFeatureNotice(
      isArabic
          ? 'مكالمة الفيديو جاهزة في طبقة سرتشات، وتحتاج جهة اتصال سائق موثقة.'
          : 'Video call is ready in the SyrChat call layer and needs a verified driver contact.',
    );
  }

  void _recordRideAudioMessage() {
    final isArabic = L10n.of(context).isArabic;
    _showRideFeatureNotice(
      isArabic
          ? 'الرسائل الصوتية تستخدم نفس مسجل سرتشات داخل محادثة الرحلة.'
          : 'Audio notes use the same SyrChat recorder inside ride chat.',
    );
  }

  Future<void> _triggerRideSos() async {
    await _openSupportTicketComposer(
      initialCategory: RideSupportTicketCategory.safety,
    );
  }

  void _addRideStop() {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _extraRideStopCount += 1;
    });
    _showRideFeatureNotice(
      isArabic
          ? 'تمت إضافة توقف جديد للرحلة.'
          : 'Added another stop to this taxi ride.',
    );
  }

  Future<void> _sendRideTip({required int? fareMinorUnits}) async {
    final isArabic = L10n.of(context).isArabic;
    final tipAmount = fareMinorUnits == null
        ? null
        : (fareMinorUnits * _selectedTipPercent) ~/ 100;
    if ((tipAmount ?? 0) <= 0) {
      _showRideFeatureNotice(
        isArabic
            ? 'اختر نسبة بقشيش أكبر من 0%.'
            : 'Choose a tip percentage above 0%.',
      );
      return;
    }
    await _openRideWallet(
      initialSection: 'send',
      initialAmountMinorUnits: tipAmount,
    );
  }

  Future<void> _openLostAndFound() async {
    await _openSupportTicketComposer(
      initialCategory: RideSupportTicketCategory.lostItem,
    );
  }

  Future<void> _openRideDispute() async {
    await _openSupportTicketComposer(
      initialCategory: RideSupportTicketCategory.paymentIssue,
    );
  }

  void _generateRidePickupCode() {
    final isArabic = L10n.of(context).isArabic;
    final code = (1000 + Random().nextInt(9000)).toString();
    setState(() {
      _ridePickupCode = code;
    });
    _showRideFeatureNotice(
      isArabic
          ? 'رمز الالتقاط جاهز: $code. أعطه للسائق عند الركوب.'
          : 'Pickup code ready: $code. Share it with the driver at boarding.',
    );
  }

  void _showWaitingFeeInfo() {
    final isArabic = L10n.of(context).isArabic;
    _showRideFeatureNotice(
      isArabic
          ? 'تبدأ رسوم الانتظار بعد $_rideWaitingGraceMinutes دقائق من وصول السائق.'
          : 'Waiting fees start after $_rideWaitingGraceMinutes minutes once the driver arrives.',
    );
  }

  Future<void> _openPickupInstructionsSheet() async {
    final isArabic = L10n.of(context).isArabic;
    final instructionsCtrl = TextEditingController();
    final String? instructions;
    try {
      instructions = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'تعليمات الالتقاط' : 'Pickup instructions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: instructionsCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: isArabic
                        ? 'مثال: أنتظر عند البوابة الحمراء'
                        : 'Example: I am waiting by the red gate',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(instructionsCtrl.text.trim()),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(isArabic ? 'حفظ' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      instructionsCtrl.dispose();
    }
    if (instructions == null || instructions.isEmpty || !mounted) return;
    setState(() {
      _pickupInstructionsReady = true;
    });
    _showRideFeatureNotice(
      isArabic
          ? 'تم حفظ تعليمات الالتقاط للسائق.'
          : 'Pickup instructions saved for the driver.',
    );
  }

  void _addFareSplitContact() {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _fareSplitContactCount += 1;
    });
    _showRideFeatureNotice(
      isArabic
          ? 'تمت إضافة جهة لتقسيم السعر.'
          : 'Added a contact to split the fare.',
    );
  }

  void _applyRidePromoCode() {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _promoCreditMinorUnits += 500;
    });
    _showRideFeatureNotice(
      isArabic
          ? 'تم تطبيق رصيد Promo بقيمة 5.00 SYP.'
          : 'Applied a 5.00 SYP ride promo credit.',
    );
  }

  void _showRideSurgeExplanation() {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _surgeExplanationVisible = true;
    });
    _showRideFeatureNotice(
      isArabic
          ? 'شرح Surge: الطلب، المرور، المنطقة وتوفر السائقين.'
          : 'Surge explanation: demand, traffic, zone pressure, and driver supply.',
    );
  }

  Future<void> _refreshRoutePricingPreview() async {
    final pickup = _selectedPickup;
    final destination = _selectedDestination;
    if (pickup == null || destination == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastRouteQuote = null;
        _lastTrafficSnapshot = null;
        _lastPricingPreview = null;
        _routePreviewPoints = const <maplibre.LatLng>[];
      });
      return;
    }
    if (mounted) {
      setState(() {
        _requestingProviderEstimate = true;
      });
    }
    try {
      final route = await _mobilityApi.route(
        from: pickup.point,
        to: destination.point,
      );
      final traffic =
          route == null ? null : await _mobilityApi.traffic(at: pickup.point);
      final pricing = route == null
          ? null
          : await _mobilityApi.pricingPreview(
              rideClass: _rideClassCode(_rideClass),
              distanceMeters: route.distanceMeters,
              etaSeconds: route.etaSeconds,
              trafficDelaySeconds: route.trafficDelaySeconds,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastRouteQuote = route;
        _lastTrafficSnapshot = traffic;
        _lastPricingPreview = pricing;
        _routePreviewPoints = route == null
            ? const <maplibre.LatLng>[]
            : _toMapPoints(route.points);
      });
    } finally {
      if (mounted) {
        setState(() {
          _requestingProviderEstimate = false;
        });
      }
    }
  }

  String _normalizePlace(String raw) {
    return rideNormalizePlaceInput(raw);
  }

  RideSearchPlace _normalizedPlaceSelection(RideSearchPlace place) {
    final label = _normalizePlace(place.displayName);
    return RideSearchPlace(
      displayName: label.isEmpty ? place.displayName.trim() : label,
      point: place.point,
    );
  }

  Future<String> _resolvePinnedLocationLabel(RideGeoPoint point) async {
    final reverseLabel = _normalizePlace(
      await _mobilityApi.reverseGeocode(point: point) ?? '',
    );
    if (reverseLabel.isNotEmpty) {
      return reverseLabel;
    }
    return rideTripMapCoordinateLabel(point);
  }

  void _applyPickupSelection(
    RideSearchPlace place, {
    required _PickupSelectionMode mode,
  }) {
    final normalizedPlace = _normalizedPlaceSelection(place);
    _pickupSearchDebounce?.cancel();
    _pickupSearchGeneration += 1;
    _suppressPickupOnChanged = true;
    _pickupCtrl
      ..text = normalizedPlace.displayName
      ..selection = TextSelection.collapsed(
        offset: normalizedPlace.displayName.length,
      );
    _suppressPickupOnChanged = false;
    setState(() {
      _selectedPickup = normalizedPlace;
      _pickupSelectionMode = mode;
      _pickupSuggestions = const <RideSearchPlace>[];
      _loadingPickupSuggestions = false;
      _pickupSearchUnavailable = false;
    });
    if (_selectedDestination != null) {
      unawaited(_refreshRoutePricingPreview());
    }
  }

  void _applyDestinationSelection(
    RideSearchPlace place, {
    required bool pinnedOnMap,
  }) {
    final normalizedPlace = _normalizedPlaceSelection(place);
    _destinationSearchDebounce?.cancel();
    _destinationSearchGeneration += 1;
    _suppressDestinationOnChanged = true;
    _destinationCtrl
      ..text = normalizedPlace.displayName
      ..selection = TextSelection.collapsed(
        offset: normalizedPlace.displayName.length,
      );
    _suppressDestinationOnChanged = false;
    setState(() {
      _selectedDestination = normalizedPlace;
      _destinationPinnedOnMap = pinnedOnMap;
      _destinationSuggestions = const <RideSearchPlace>[];
      _loadingDestinationSuggestions = false;
      _destinationSearchUnavailable = false;
    });
    if (_selectedPickup != null) {
      unawaited(_refreshRoutePricingPreview());
    }
  }

  String? _pickupModeHint({required bool isArabic}) {
    switch (_pickupSelectionMode) {
      case _PickupSelectionMode.currentLocation:
        return isArabic
            ? 'سيتم استخدام موقعك الحالي كنقطة انطلاق.'
            : 'Using your current location as pickup.';
      case _PickupSelectionMode.pinnedMap:
        return isArabic
            ? 'تم تثبيت نقطة الانطلاق على الخريطة.'
            : 'Pickup pinned on the map.';
      case _PickupSelectionMode.search:
      case null:
        return null;
    }
  }

  String? _destinationModeHint({required bool isArabic}) {
    if (!_destinationPinnedOnMap) {
      return null;
    }
    return isArabic
        ? 'تم تثبيت الوجهة على الخريطة.'
        : 'Destination pinned on the map.';
  }

  Future<void> _useCurrentLocationAsPickup({required bool isArabic}) async {
    final location =
        await _resolveCurrentLocation(forcePermissionRequest: true);
    if (!mounted) return;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تعذر الوصول إلى الموقع الحالي.'
                : 'Could not access current location.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _currentLocation = location;
    });
    final label = await _resolvePinnedLocationLabel(location);
    if (!mounted) return;
    _applyPickupSelection(
      RideSearchPlace(displayName: label, point: location),
      mode: _PickupSelectionMode.currentLocation,
    );
  }

  Future<void> _pinPickupOnMap({required bool isArabic}) async {
    final location =
        await _resolveCurrentLocation(forcePermissionRequest: true);
    if (!mounted) return;
    if (location != null) {
      setState(() {
        _currentLocation = location;
      });
    }
    final pinnedPoint = await Navigator.of(context).push<RideGeoPoint>(
      MaterialPageRoute<RideGeoPoint>(
        builder: (context) => RideLocationPinPage(
          baseUrl: widget.baseUrl,
          bootstrap: _platformBootstrap,
          currentLocation: location ?? _currentLocation,
          initialPinnedLocation:
              _selectedPickup?.point ?? location ?? _currentLocation,
          pickupLocation: _selectedPickup?.point,
          destinationLocation: _selectedDestination?.point,
          isArabic: isArabic,
          pinningDestination: false,
        ),
      ),
    );
    if (!mounted || pinnedPoint == null) return;
    final label = await _resolvePinnedLocationLabel(pinnedPoint);
    if (!mounted) return;
    _applyPickupSelection(
      RideSearchPlace(displayName: label, point: pinnedPoint),
      mode: _PickupSelectionMode.pinnedMap,
    );
  }

  Future<void> _pinDestinationOnMap({required bool isArabic}) async {
    final location = _currentLocation;
    final pinnedPoint = await Navigator.of(context).push<RideGeoPoint>(
      MaterialPageRoute<RideGeoPoint>(
        builder: (context) => RideLocationPinPage(
          baseUrl: widget.baseUrl,
          bootstrap: _platformBootstrap,
          currentLocation: location,
          initialPinnedLocation:
              _selectedDestination?.point ?? _selectedPickup?.point ?? location,
          pickupLocation: _selectedPickup?.point,
          destinationLocation: _selectedDestination?.point,
          isArabic: isArabic,
          pinningDestination: true,
        ),
      ),
    );
    if (!mounted || pinnedPoint == null) return;
    final label = await _resolvePinnedLocationLabel(pinnedPoint);
    if (!mounted) return;
    _applyDestinationSelection(
      RideSearchPlace(displayName: label, point: pinnedPoint),
      pinnedOnMap: true,
    );
  }

  int _requestSignal(String pickup, String destination, _RideClass rideClass) {
    final seed = '$pickup|$destination|${_rideClassCode(rideClass)}';
    var acc = 0;
    for (final rune in seed.runes) {
      acc = ((acc * 131) + rune) % 0x7fffffff;
    }
    return acc;
  }

  (int etaMin, int fareCents) _estimate(String pickup, String destination) {
    final signal = _requestSignal(pickup, destination, _rideClass);
    final distanceKm = 3 + (signal % 18); // 3..20
    final baseFare = 350 + (distanceKm * 120);
    final multiplier = switch (_rideClass) {
      _RideClass.economy => 1.0,
      _RideClass.comfort => 1.35,
      _RideClass.van => 1.75,
    };
    final fare = (baseFare * multiplier).round();
    final eta = 4 + (signal % 10); // 4..13
    return (eta, fare);
  }

  int _fareFromTomTomRoute(RideRouteQuote route) {
    final distanceKm = max(1.0, route.distanceMeters / 1000.0);
    final baseFare = 350 + (distanceKm * 120).round();
    final trafficSurcharge =
        min(600, (route.trafficDelaySeconds / 30).round() * 12);
    final multiplier = switch (_rideClass) {
      _RideClass.economy => 1.0,
      _RideClass.comfort => 1.35,
      _RideClass.van => 1.75,
    };
    return ((baseFare + trafficSurcharge) * multiplier).round();
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

  void _onPickupChanged(String raw) {
    if (_suppressPickupOnChanged) return;
    final normalized = _normalizePlace(raw);
    final selected = _selectedPickup;
    var clearedSelected = false;
    if (selected != null &&
        selected.displayName.trim().toLowerCase() != normalized.toLowerCase()) {
      _selectedPickup = null;
      _pickupSelectionMode = null;
      clearedSelected = true;
    }
    _pickupSearchDebounce?.cancel();
    _pickupSearchGeneration += 1;
    if (normalized.length < 2) {
      setState(() {
        _pickupSuggestions = const <RideSearchPlace>[];
        _loadingPickupSuggestions = false;
        _pickupSearchUnavailable = false;
        if (clearedSelected) {
          _pickupSelectionMode = null;
          _lastRouteQuote = null;
          _lastTrafficSnapshot = null;
          _lastPricingPreview = null;
          _routePreviewPoints = const <maplibre.LatLng>[];
        }
      });
      return;
    }
    setState(() {
      _loadingPickupSuggestions = true;
      _pickupSearchUnavailable = false;
      if (clearedSelected) {
        _pickupSelectionMode = null;
        _lastRouteQuote = null;
        _lastTrafficSnapshot = null;
        _lastPricingPreview = null;
        _routePreviewPoints = const <maplibre.LatLng>[];
      }
    });
    final generation = _pickupSearchGeneration;
    _pickupSearchDebounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_fetchPickupSuggestions(normalized, generation));
    });
  }

  void _onDestinationChanged(String raw) {
    if (_suppressDestinationOnChanged) return;
    final normalized = _normalizePlace(raw);
    final selected = _selectedDestination;
    var clearedSelected = false;
    if (selected != null &&
        selected.displayName.trim().toLowerCase() != normalized.toLowerCase()) {
      _selectedDestination = null;
      _destinationPinnedOnMap = false;
      clearedSelected = true;
    }
    _destinationSearchDebounce?.cancel();
    _destinationSearchGeneration += 1;
    if (normalized.length < 2) {
      setState(() {
        _destinationSuggestions = const <RideSearchPlace>[];
        _loadingDestinationSuggestions = false;
        _destinationSearchUnavailable = false;
        if (clearedSelected) {
          _destinationPinnedOnMap = false;
          _lastRouteQuote = null;
          _lastTrafficSnapshot = null;
          _lastPricingPreview = null;
          _routePreviewPoints = const <maplibre.LatLng>[];
        }
      });
      return;
    }
    setState(() {
      _loadingDestinationSuggestions = true;
      _destinationSearchUnavailable = false;
      if (clearedSelected) {
        _destinationPinnedOnMap = false;
        _lastRouteQuote = null;
        _lastTrafficSnapshot = null;
        _lastPricingPreview = null;
        _routePreviewPoints = const <maplibre.LatLng>[];
      }
    });
    final generation = _destinationSearchGeneration;
    _destinationSearchDebounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_fetchDestinationSuggestions(normalized, generation));
    });
  }

  Future<void> _fetchPickupSuggestions(String query, int generation) async {
    final result = await _mobilityApi.searchWithStatus(query: query, limit: 5);
    if (!mounted) return;
    if (generation != _pickupSearchGeneration) return;
    if (_normalizePlace(_pickupCtrl.text).toLowerCase() !=
        query.toLowerCase()) {
      return;
    }
    setState(() {
      _pickupSuggestions = result.places;
      _loadingPickupSuggestions = false;
      _pickupSearchUnavailable =
          result.status == RidePlaceSearchStatus.unavailable;
    });
  }

  Future<void> _fetchDestinationSuggestions(
      String query, int generation) async {
    final result = await _mobilityApi.searchWithStatus(
      query: query,
      near: _selectedPickup?.point,
      limit: 5,
    );
    if (!mounted) return;
    if (generation != _destinationSearchGeneration) return;
    if (_normalizePlace(_destinationCtrl.text).toLowerCase() !=
        query.toLowerCase()) {
      return;
    }
    setState(() {
      _destinationSuggestions = result.places;
      _loadingDestinationSuggestions = false;
      _destinationSearchUnavailable =
          result.status == RidePlaceSearchStatus.unavailable;
    });
  }

  void _selectPickupSuggestion(RideSearchPlace place) {
    _applyPickupSelection(place, mode: _PickupSelectionMode.search);
  }

  void _selectDestinationSuggestion(RideSearchPlace place) {
    _applyDestinationSelection(place, pinnedOnMap: false);
  }

  List<maplibre.LatLng> _toMapPoints(List<RideGeoPoint> points) =>
      rideTripMapPointsFromRoute(points);

  RideSearchPlace? _selectedPlaceForQuery(
    String query,
    RideSearchPlace? candidate,
  ) {
    return ridePlaceSelectionMatchesQuery(
            query: query, selectedPlace: candidate)
        ? candidate
        : null;
  }

  String? _pickupValidationMessage(
    RideBookingValidationIssue? issue, {
    required bool isArabic,
  }) {
    switch (issue) {
      case RideBookingValidationIssue.pickupMissing:
        return isArabic
            ? 'أدخل نقطة الانطلاق أو استخدم موقعك الحالي.'
            : 'Enter a pickup or use your current location.';
      case RideBookingValidationIssue.pickupUnresolved:
        return isArabic
            ? 'أكد نقطة الانطلاق من البحث أو بتثبيتها على الخريطة.'
            : 'Confirm pickup from search or by pinning it on the map.';
      default:
        return null;
    }
  }

  String? _destinationValidationMessage(
    RideBookingValidationIssue? issue, {
    required bool isArabic,
  }) {
    switch (issue) {
      case RideBookingValidationIssue.destinationMissing:
        return isArabic
            ? 'أدخل الوجهة أو ثبتها على الخريطة.'
            : 'Enter a destination or pin it on the map.';
      case RideBookingValidationIssue.destinationUnresolved:
        return isArabic
            ? 'أكد الوجهة من البحث أو بتثبيتها على الخريطة.'
            : 'Confirm destination from search or by pinning it on the map.';
      case RideBookingValidationIssue.samePlace:
        return isArabic
            ? 'الوجهة مطابقة تقريبًا لنقطة الانطلاق.'
            : 'Destination is effectively the same as pickup.';
      default:
        return null;
    }
  }

  String? _bookingValidationMessage(
    RideBookingValidationIssue? issue, {
    required bool isArabic,
  }) {
    switch (issue) {
      case RideBookingValidationIssue.activeTripInProgress:
        return isArabic
            ? 'أنهِ الرحلة الحالية أو ألغها قبل طلب رحلة جديدة.'
            : 'Finish or cancel the current ride before requesting another one.';
      case RideBookingValidationIssue.pickupMissing:
      case RideBookingValidationIssue.pickupUnresolved:
      case RideBookingValidationIssue.destinationMissing:
      case RideBookingValidationIssue.destinationUnresolved:
      case RideBookingValidationIssue.samePlace:
      case null:
        return null;
    }
  }

  Future<RideSearchPlace?> _resolvePlaceForMap(
    String query, {
    RideGeoPoint? near,
    RideSearchPlace? preferred,
  }) async {
    final normalized = _normalizePlace(query);
    if (normalized.isEmpty) {
      return null;
    }
    final matchedPreferred = _selectedPlaceForQuery(normalized, preferred);
    if (matchedPreferred != null) {
      return matchedPreferred;
    }
    final matches = await _mobilityApi.search(
      query: normalized,
      near: near,
      limit: 1,
    );
    if (matches.isEmpty) {
      return null;
    }
    return matches.first;
  }

  Future<RideTripMapSnapshot?> _buildActiveTripMapSnapshot(
    RideTrip? trip,
    RideLiveTrackingSnapshot? trackingSnapshot,
  ) async {
    if (trip == null || rideTripStatusIsTerminal(trip.status)) {
      return null;
    }
    final driverLocation = trackingSnapshot?.latestDriverLocation?.location;
    final pickupPlace = await _resolvePlaceForMap(
      trip.pickup,
      near: driverLocation,
      preferred: _selectedPickup,
    );
    final destinationPlace = await _resolvePlaceForMap(
      trip.destination,
      near: pickupPlace?.point ?? driverLocation,
      preferred: _selectedDestination,
    );
    final stage = rideTripMapStageForStatus(trip.status);
    final targetPoint = stage == RideTripMapStage.destination
        ? destinationPlace?.point
        : pickupPlace?.point;
    List<maplibre.LatLng> routePoints = const <maplibre.LatLng>[];
    if (driverLocation != null && targetPoint != null) {
      final route = await _mobilityApi.route(
        from: driverLocation,
        to: targetPoint,
      );
      if (route != null) {
        routePoints = _toMapPoints(route.points);
      }
    } else if (pickupPlace != null && destinationPlace != null) {
      final route = await _mobilityApi.route(
        from: pickupPlace.point,
        to: destinationPlace.point,
      );
      if (route != null) {
        routePoints = _toMapPoints(route.points);
      }
    }
    return RideTripMapSnapshot(
      routePoints: routePoints,
      driverLocation: rideTripStatusHasLiveDriverTracking(trip.status)
          ? driverLocation
          : null,
      pickupLocation: pickupPlace?.point,
      destinationLocation: destinationPlace?.point,
    );
  }

  RideTripMapSnapshot _previewMapSnapshot() {
    return RideTripMapSnapshot(
      routePoints: _routePreviewPoints,
      driverLocation: null,
      pickupLocation: _selectedPickup?.point,
      destinationLocation: _selectedDestination?.point,
    );
  }

  Future<void> _submitRideRequest({
    required String pickup,
    required String destination,
    RideSearchPlace? selectedPickup,
    RideSearchPlace? selectedDestination,
  }) async {
    // Cycle 99 — haptic feedback on ride submission. Matches the
    // driver-side Cycle 98 cadence so both ends of a journey have
    // tactile confirmation on their primary commit action.
    unawaited(HapticFeedback.mediumImpact());
    final l = L10n.of(context);
    final issue = rideBookingValidationIssue(
      pickupQuery: pickup,
      destinationQuery: destination,
      selectedPickup: selectedPickup,
      selectedDestination: selectedDestination,
      hasActiveTrip:
          _activeTrip != null && !rideTripStatusIsTerminal(_activeTrip!.status),
    );
    final normalizedPickup = _normalizePlace(pickup);
    final normalizedDestination = _normalizePlace(destination);
    if (issue != null) {
      final message = switch (issue) {
        RideBookingValidationIssue.activeTripInProgress => l.isArabic
            ? 'لديك رحلة نشطة بالفعل.'
            : 'You already have an active ride.',
        RideBookingValidationIssue.pickupMissing =>
          _pickupValidationMessage(issue, isArabic: l.isArabic) ??
              (l.isArabic ? 'أدخل موقع الانطلاق.' : 'Enter a pickup.'),
        RideBookingValidationIssue.pickupUnresolved =>
          _pickupValidationMessage(issue, isArabic: l.isArabic) ??
              (l.isArabic
                  ? 'أكد نقطة الانطلاق من البحث أو الخريطة.'
                  : 'Confirm the pickup from search or the map.'),
        RideBookingValidationIssue.destinationMissing =>
          _destinationValidationMessage(issue, isArabic: l.isArabic) ??
              (l.isArabic ? 'أدخل الوجهة.' : 'Enter a destination.'),
        RideBookingValidationIssue.destinationUnresolved =>
          _destinationValidationMessage(issue, isArabic: l.isArabic) ??
              (l.isArabic
                  ? 'أكد الوجهة من البحث أو الخريطة.'
                  : 'Confirm the destination from search or the map.'),
        RideBookingValidationIssue.samePlace => l.isArabic
            ? 'موقع الانطلاق والوجهة متشابهان.'
            : 'Pickup and destination are too similar.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
      return;
    }

    setState(() {
      _requestingProviderEstimate = true;
    });

    final hasSelectedPickup = selectedPickup != null &&
        selectedPickup.displayName.trim().toLowerCase() ==
            normalizedPickup.toLowerCase();
    final hasSelectedDestination = selectedDestination != null &&
        selectedDestination.displayName.trim().toLowerCase() ==
            normalizedDestination.toLowerCase();

    RideTomTomQuote? providerQuote;
    RideRouteQuote? selectedRoute;
    RideTrafficSnapshot? selectedTraffic;
    RidePricingPreview? pricingPreview = _lastPricingPreview;
    try {
      if (hasSelectedPickup && hasSelectedDestination) {
        selectedRoute = await _mobilityApi.route(
          from: selectedPickup!.point,
          to: selectedDestination!.point,
        );
        if (selectedRoute != null) {
          selectedTraffic =
              await _mobilityApi.traffic(at: selectedPickup.point);
          providerQuote = RideTomTomQuote(
            pickup: selectedPickup,
            destination: selectedDestination!,
            route: selectedRoute,
            trafficAtPickup: selectedTraffic,
          );
          pricingPreview = await _mobilityApi.pricingPreview(
            rideClass: _rideClassCode(_rideClass),
            distanceMeters: selectedRoute.distanceMeters,
            etaSeconds: selectedRoute.etaSeconds,
            trafficDelaySeconds: selectedRoute.trafficDelaySeconds,
          );
        }
      } else {
        providerQuote = await _mobilityApi.quoteByText(
          pickupQuery: normalizedPickup,
          destinationQuery: normalizedDestination,
        );
        final route = providerQuote?.route;
        if (route != null) {
          pricingPreview = await _mobilityApi.pricingPreview(
            rideClass: _rideClassCode(_rideClass),
            distanceMeters: route.distanceMeters,
            etaSeconds: route.etaSeconds,
            trafficDelaySeconds: route.trafficDelaySeconds,
          );
        }
      }
    } catch (_) {
      providerQuote = null;
    } finally {
      if (mounted) {
        setState(() {
          _requestingProviderEstimate = false;
        });
      }
    }
    if (!mounted) return;

    final resolvedPickup =
        providerQuote?.pickup.displayName ?? normalizedPickup;
    final resolvedDestination =
        providerQuote?.destination.displayName ?? normalizedDestination;
    final estimate = pricingPreview != null
        ? (
            max(1, (pricingPreview.etaSeconds / 60).ceil()),
            pricingPreview.totalFareMinorUnits,
          )
        : providerQuote == null
            ? _estimate(resolvedPickup, resolvedDestination)
            : (
                max(1, (providerQuote.route.etaSeconds / 60).round()),
                _fareFromTomTomRoute(providerQuote.route),
              );
    if (providerQuote != null) {
      _lastRouteQuote = providerQuote.route;
      _lastTrafficSnapshot = providerQuote.trafficAtPickup;
      _lastPricingPreview = pricingPreview;
      _routePreviewPoints = _toMapPoints(providerQuote.route.points);
    }
    final createdFromServer = await _mobilityApi.createTrip(
      pickup: resolvedPickup,
      destination: resolvedDestination,
      rideClass: _rideClassCode(_rideClass),
      fareEstimateCents: estimate.$2,
      etaSeconds: estimate.$1 * 60,
    );
    if (createdFromServer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تعذّر إنشاء طلب الرحلة على الخادم.'
                : 'Could not create ride request on server.',
          ),
        ),
      );
      return;
    }
    var trip = createdFromServer;
    if (trip.status == RideTripStatus.rideRequested) {
      final matchingTrip = await _mobilityApi.commandTrip(
        rideId: trip.rideId,
        command: 'enter_matching',
      );
      if (matchingTrip != null) {
        trip = matchingTrip;
      }
    }

    await upsertRideHailingHistoryTrip(trip, baseUrlOverride: widget.baseUrl);
    await saveActiveRideHailingTrip(trip, baseUrlOverride: widget.baseUrl);
    await _loadState();
    if (!mounted) return;
    final rideConfirmedWithDriver = _rideTripHasAssignedDriver(trip) &&
        (trip.status == RideTripStatus.driverAssigned ||
            trip.status == RideTripStatus.driverArriving ||
            trip.status == RideTripStatus.driverArrived ||
            trip.status == RideTripStatus.tripStarted ||
            trip.status == RideTripStatus.tripInProgress);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          rideConfirmedWithDriver
              ? (l.isArabic
                  ? 'تم تأكيد الطلب. السائق ${trip.driverName} سيصل خلال ${trip.etaMinutes} د.'
                  : 'Ride confirmed. ${trip.driverName} arrives in ${trip.etaMinutes} min.')
              : (l.isArabic
                  ? 'تم إرسال طلب الرحلة. جارٍ مطابقة سائق الآن.'
                  : 'Ride request submitted. Matching a driver now.'),
        ),
      ),
    );
  }

  Future<void> _requestRide() async {
    await _submitRideRequest(
      pickup: _pickupCtrl.text,
      destination: _destinationCtrl.text,
      selectedPickup: _selectedPickup,
      selectedDestination: _selectedDestination,
    );
  }

  Future<void> _runSavedRouteRequest({required bool isArabic}) async {
    _suppressPickupOnChanged = true;
    _suppressDestinationOnChanged = true;
    _pickupCtrl.text = _rideSavedRoutePickupPlace.displayName;
    _destinationCtrl.text = _rideSavedRouteDestinationPlace.displayName;
    _suppressPickupOnChanged = false;
    _suppressDestinationOnChanged = false;
    setState(() {
      _selectedPickup = _rideSavedRoutePickupPlace;
      _selectedDestination = _rideSavedRouteDestinationPlace;
      _pickupSuggestions = const <RideSearchPlace>[];
      _destinationSuggestions = const <RideSearchPlace>[];
      _pickupSelectionMode = _PickupSelectionMode.search;
      _destinationPinnedOnMap = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isArabic
              ? 'جارٍ إرسال الرحلة: باب توما إلى المالكي.'
              : 'Submitting ride: Bab Touma to Malki.',
        ),
      ),
    );
    await _submitRideRequest(
      pickup: _rideSavedRoutePickupPlace.displayName,
      destination: _rideSavedRouteDestinationPlace.displayName,
      selectedPickup: _rideSavedRoutePickupPlace,
      selectedDestination: _rideSavedRouteDestinationPlace,
    );
  }

  Future<void> _updateActiveTrip(
    RideTripStatus status, {
    // Cycle 201 — when the rider cancels, the picker hands us a
    // canonical reason code (e.g. 'wrong_pickup') that we thread
    // into the server's existing cancel_reason_code field.
    String? cancelReasonCode,
  }) async {
    final active = _activeTrip;
    if (active == null) return;
    final l = L10n.of(context);
    if (!rideTripStatusCanTransition(from: active.status, to: status)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'انتقال حالة غير صالح: ${_rideStatusLabel(active.status, isArabic: true)} → ${_rideStatusLabel(status, isArabic: true)}'
                : 'Invalid state transition: ${_rideStatusLabel(active.status, isArabic: false)} -> ${_rideStatusLabel(status, isArabic: false)}',
          ),
        ),
      );
      return;
    }
    final nextEtaMinutes = (status == RideTripStatus.driverArriving ||
            status == RideTripStatus.driverArrived)
        ? max(1, active.etaMinutes ~/ 2)
        : active.etaMinutes;
    final command = _rideCommandForTargetStatus(status);
    RideTrip? updatedFromServer;
    if (command != null) {
      updatedFromServer = await _mobilityApi.commandTrip(
        rideId: active.rideId,
        command: command,
        etaSeconds: nextEtaMinutes * 60,
        driverName:
            status == RideTripStatus.driverAssigned ? active.driverName : null,
        carPlate:
            status == RideTripStatus.driverAssigned ? active.carPlate : null,
        reason: status == RideTripStatus.canceled ? 'rider_cancelled' : null,
        cancelReasonCode:
            status == RideTripStatus.canceled ? cancelReasonCode : null,
      );
      if (updatedFromServer == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر تحديث حالة الرحلة على الخادم.'
                  : 'Could not update ride state on server.',
            ),
          ),
        );
        return;
      }
    }
    final updated = updatedFromServer ??
        active.copyWith(
          status: status,
          lastUpdatedAtIso: DateTime.now().toUtc().toIso8601String(),
          etaMinutes: nextEtaMinutes,
        );
    await upsertRideHailingHistoryTrip(
      updated,
      baseUrlOverride: widget.baseUrl,
    );
    if (rideTripStatusIsTerminal(status)) {
      await saveActiveRideHailingTrip(null, baseUrlOverride: widget.baseUrl);
    } else {
      await saveActiveRideHailingTrip(updated, baseUrlOverride: widget.baseUrl);
    }
    await _loadState();
  }

  /// Cycle 68 — animate the draggable sheet to the snap that fits
  /// the current trip state: small (0.32) when a trip is active so
  /// the map + driver marker dominate, and the same default 0.32
  /// when idle so the peek hero is fully visible without crowding
  /// the map. Best-effort; swallows controller-detached errors.
  void _syncSheetForActiveTrip() {
    if (!_hailingSheetCtrl.isAttached) return;
    // Active trip → tiny sheet so the driver/route map dominates;
    // idle → the default 0.32 peek size.
    final target = _activeTrip != null ? 0.20 : 0.32;
    try {
      _hailingSheetCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  /// Cycle 66 — collapsed peek hero. Lives at the top of the
  /// bottom-sheet's ListView; designed so that a sheet at 0.18
  /// snap-size shows ONLY this and the drag handle. Tapping the
  /// "Where to?" strip animates the sheet to its full size + focuses
  /// the destination field below.
  ///
  /// Cycle 68 — hidden when a trip is active. During an active trip
  /// the user shouldn't see "Where to?"; the active-trip card is the
  /// primary surface.
  Widget _buildHailingPeekHero({required bool isArabic}) {
    if (_activeTrip != null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cashCents = _walletSnapshot
        ?.bucketBalance(RideWalletBucketType.cashBalance);
    final walletPill = cashCents == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${fmtCents(cashCents)} SYP',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (walletPill != null)
            Row(children: <Widget>[walletPill]),
          if (walletPill != null) const SizedBox(height: 10),
          // Big "Where to?" strip — primary CTA when collapsed.
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                // Cycle 129 — selection haptic so the tap on the
                // "Where to?" strip registers before the sheet
                // animates up. Pairs with the destination focus
                // hand-off so the keyboard rises right after.
                unawaited(HapticFeedback.selectionClick());
                try {
                  await _hailingSheetCtrl.animateTo(
                    0.92,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                  );
                } catch (_) {}
                if (mounted) {
                  _destinationFocus.requestFocus();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.search,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isArabic ? 'إلى أين؟' : 'Where to?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: .65),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Quick chip: saved demo route. Future cycle adds Home/Work
          // proper saved-place entries.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ActionChip(
                avatar: const Icon(Icons.bookmark_outline, size: 16),
                label: Text(isArabic ? 'باب توما → المالكي' : 'Saved route'),
                onPressed: () =>
                    unawaited(_runSavedRouteRequest(isArabic: isArabic)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapPreview({required bool isArabic}) {
    final activeTrip = _activeTrip;
    final activeSnapshot = activeTrip == null ? null : _tripMapSnapshot;
    final mapSnapshot = activeSnapshot ?? _previewMapSnapshot();
    // Cycle 65/67 — when used as the full-screen background under
    // the draggable sheet, the map must run in `standalone: true`
    // mode so it expands to fill the parent (the Card wrapper would
    // otherwise pin it to the default 220-px height) and we hide
    // the fullscreen / zoom controls that are now redundant because
    // the user can pinch directly on the canvas.
    return RideTripMapCard(
      baseUrl: widget.baseUrl,
      bootstrap: _platformBootstrap,
      snapshot: mapSnapshot.hasAnyOverlay ? mapSnapshot : null,
      currentLocation: _currentLocation,
      fullscreenTitle: isArabic ? 'خريطة الرحلة' : 'Ride map',
      unavailableMessage: isArabic
          ? 'عرض الخريطة عبر MapLibre غير متاح في هذا البناء.'
          : 'MapLibre map preview is not available in this build.',
      loadingMessage:
          isArabic ? 'جاري تهيئة مزود الخريطة…' : 'Preparing map provider…',
      standalone: true,
      allowFullscreen: false,
      showZoomControls: false,
    );
  }

  Widget _buildSuggestionsList({
    required bool isArabic,
    required String query,
    required bool loading,
    required bool unavailable,
    required List<RideSearchPlace> suggestions,
    required void Function(RideSearchPlace place) onSelect,
  }) {
    final feedback = ridePlaceSuggestionFeedback(
      query: query,
      loading: loading,
      unavailable: unavailable,
      suggestions: suggestions,
    );
    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(isArabic ? 'جاري البحث…' : 'Searching…'),
          ],
        ),
      );
    }
    if (feedback == RidePlaceSuggestionFeedback.unavailable) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          isArabic
              ? 'بحث الأماكن غير متاح حالياً. حاول مرة أخرى.'
              : 'Place search is temporarily unavailable. Try again.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    }
    if (feedback == RidePlaceSuggestionFeedback.noResults) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          isArabic
              ? 'لم يتم العثور على نتائج مطابقة.'
              : 'No matching places found.',
          style: TextStyle(
            fontSize: 12,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
          ),
        ),
      );
    }
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .5),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: suggestions
            .take(4)
            .map(
              (place) => ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined, size: 18),
                title: Text(
                  place.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelect(place),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildActiveTripCard({required bool isArabic}) {
    final trip = _activeTrip;
    final trackingSnapshot = _trackingSnapshot;
    if (trip == null) return const SizedBox.shrink();

    final canCancel = rideTripStatusRiderCanCancel(trip.status);
    final semanticsLabel = rideActiveTripSemanticsSummaryLabel(
      trip: trip,
      trackingSnapshot: trackingSnapshot,
      isArabic: isArabic,
      trackingAgeLabel: _trackingAgeLabel,
    );

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: _RideLiquidGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_taxi_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic ? 'الرحلة الحالية' : 'Current ride',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Chip(
                  label:
                      Text(_rideStatusLabel(trip.status, isArabic: isArabic)),
                ),
              ],
            ),
            // Cycle 95 — pre-assignment reassurance. While the trip
            // is still in `rideRequested` / `matching` we show a
            // small LinearProgressIndicator and a "Searching for
            // nearby drivers…" line so the rider doesn't think the
            // app got stuck waiting on a placeholder driver name.
            if (trip.status == RideTripStatus.rideRequested ||
                trip.status == RideTripStatus.matching) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.radar_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isArabic
                          ? 'جارٍ البحث عن سائقين قريبين منك…'
                          : 'Searching for nearby drivers…',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Cycle 89 — promote ETA into a prominent chip below the
            // title. The ETA was previously buried in a one-line
            // Text alongside the fare estimate, with no visual
            // weight. Now it's the second thing the passenger reads
            // (after status) — which is the question they actually
            // ask when their phone shows an active ride.
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.access_time_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        isArabic
                            ? 'وصول خلال ${trip.etaMinutes} د'
                            : 'ETA ${trip.etaMinutes} min',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .secondaryContainer
                        .withValues(alpha: .42),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.payments_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${fmtCents(trip.fareEstimateCents)} SYP',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'السائق: ${trip.driverName} • ${trip.carPlate}'
                  : 'Driver: ${trip.driverName} • ${trip.carPlate}',
            ),
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'من ${trip.pickup} إلى ${trip.destination}'
                  : '${trip.pickup} -> ${trip.destination}',
            ),
            if (trackingSnapshot?.latestDriverLocation != null) ...[
              const SizedBox(height: 6),
              Text(
                isArabic
                    ? 'آخر تحديث للسائق: ${_trackingAgeLabel(trackingSnapshot!.latestDriverLocation!.createdAtIso, isArabic: true) ?? trackingSnapshot.latestDriverLocation!.createdAtIso}'
                    : 'Driver last update: ${_trackingAgeLabel(trackingSnapshot!.latestDriverLocation!.createdAtIso, isArabic: false) ?? trackingSnapshot.latestDriverLocation!.createdAtIso}',
              ),
              if (trackingSnapshot.latestDriverLocation!.location != null)
                Text(
                  isArabic
                      ? 'الموقع: ${trackingSnapshot.latestDriverLocation!.location!.lat.toStringAsFixed(5)}, ${trackingSnapshot.latestDriverLocation!.location!.lon.toStringAsFixed(5)}'
                      : 'Location: ${trackingSnapshot.latestDriverLocation!.location!.lat.toStringAsFixed(5)}, ${trackingSnapshot.latestDriverLocation!.location!.lon.toStringAsFixed(5)}',
                ),
            ],
            if (trackingSnapshot != null &&
                trackingSnapshot.timeline.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                isArabic ? 'التتبع المباشر' : 'Live tracking',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...trackingSnapshot.timeline.reversed.take(4).map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${event.eventKind.replaceAll('_', ' ')}'
                        '${event.status != null ? ' • ${_rideStatusLabel(event.status!, isArabic: isArabic)}' : ''}'
                        ' • ${_trackingAgeLabel(event.createdAtIso, isArabic: isArabic) ?? event.createdAtIso}',
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            // Cycle 82 — surface the driver-chat shortcut directly on
            // the active-trip card. Before this, the chat entry was
            // buried in the "More options" expansion, forcing the
            // passenger to drag the sheet to 0.92 + tap through a
            // panel just to message their driver. Now it's one tap
            // from the peeked sheet.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(_openRideChatSheet()),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(
                      isArabic ? 'محادثة السائق' : 'Chat with driver'),
                ),
                // Cycle 152 — SOS button. Visible once a driver is
                // assigned (anything past matching) so the rider
                // can summon help during pickup, in-vehicle, or in
                // any post-acceptance phase. Hold-to-confirm
                // pattern prevents pocket-press false alarms.
                if (trip.status != RideTripStatus.rideRequested &&
                    trip.status != RideTripStatus.matching &&
                    !rideTripStatusIsTerminal(trip.status))
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD32F2F),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => unawaited(_openSosDialog(trip.rideId)),
                    icon: const Icon(Icons.shield_rounded, size: 18),
                    label: Text(isArabic ? 'SOS' : 'SOS'),
                  ),
                // Cycle 161 — Share trip button. Same gating as the
                // SOS button (post-matching, non-terminal). Lets the
                // rider hand a public live-tracking link to family.
                if (trip.status != RideTripStatus.rideRequested &&
                    trip.status != RideTripStatus.matching &&
                    !rideTripStatusIsTerminal(trip.status))
                  FilledButton.tonalIcon(
                    onPressed: () => unawaited(_openShareDialog(trip.rideId)),
                    icon: const Icon(Icons.share_location_rounded, size: 18),
                    label: Text(isArabic ? 'مشاركة الرحلة' : 'Share trip'),
                  ),
                if (canCancel)
                  OutlinedButton(
                    // Cycle 121 — confirm before cancelling. A
                    // mis-tap on this button cost the rider their
                    // pickup window and the driver their queue
                    // slot; the confirmation dialog mirrors the
                    // driver-side Cycle 79 offline-confirm pattern.
                    onPressed: () async {
                      // Cycle 201 — replace the binary confirm
                      // dialog with the reason picker. The picker
                      // returns null when the rider backs out (so
                      // the cancel doesn't proceed); a non-null
                      // choice both confirms and gives us analytics.
                      final choice = await showCancellationReasonPicker(
                        context: context,
                        actor: CancellationActor.rider,
                      );
                      if (choice == null || !mounted) return;
                      await _updateActiveTrip(
                        RideTripStatus.canceled,
                        cancelReasonCode: choice.reasonCode,
                      );
                    },
                    child: Text(isArabic ? 'إلغاء' : 'Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTripSemanticsBanner({required bool isArabic}) {
    final trip = _activeTrip;
    final semanticsLabel = rideActiveTripSemanticsSummaryLabel(
      trip: trip,
      trackingSnapshot: _trackingSnapshot,
      isArabic: isArabic,
      trackingAgeLabel: _trackingAgeLabel,
    );
    if (trip == null || semanticsLabel == null) {
      return const SizedBox.shrink();
    }
    final latestDriverLocation = _trackingSnapshot?.latestDriverLocation;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: _RideLiquidGlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'ملخص الرحلة الحالية' : 'Current ride summary',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_rideStatusLabel(trip.status, isArabic: isArabic)} • '
              '${trip.driverName} • ${trip.carPlate}',
            ),
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'من ${trip.pickup} إلى ${trip.destination}'
                  : '${trip.pickup} -> ${trip.destination}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (latestDriverLocation != null) ...[
              const SizedBox(height: 4),
              Text(
                isArabic
                    ? 'آخر تحديث للسائق: ${_trackingAgeLabel(latestDriverLocation.createdAtIso, isArabic: true) ?? latestDriverLocation.createdAtIso}'
                    : 'Driver last update: ${_trackingAgeLabel(latestDriverLocation.createdAtIso, isArabic: false) ?? latestDriverLocation.createdAtIso}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList({required bool isArabic}) {
    if (_history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          isArabic ? 'لا يوجد سجل رحلات بعد.' : 'No rides yet.',
          style: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .65),
          ),
        ),
      );
    }
    // Cycle 87 — swap the raw rideId UUID trailing for a friendly
    // "X days ago" relative timestamp. The rideId is internal noise
    // for end users; the timestamp answers the question they
    // actually have when scanning history ("when did I take that?").
    return Column(
      children: _history
          .take(12)
          .map(
            (trip) {
              final completed = trip.completedAtIso ?? trip.createdAtIso;
              final ageLabel = _trackingAgeLabel(completed, isArabic: isArabic);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.route_outlined),
                  title: Text('${trip.pickup} -> ${trip.destination}'),
                  subtitle: Text(
                    '${_rideStatusLabel(trip.status, isArabic: isArabic)} • ${fmtCents(trip.fareEstimateCents)} SYP',
                  ),
                  trailing: ageLabel == null
                      ? null
                      : Text(
                          ageLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .65),
                          ),
                        ),
                ),
              );
            },
          )
          .toList(growable: false),
    );
  }

  Widget _buildRideHistoryCard({required bool isArabic}) {
    return _RideLiquidGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'سجل الرحلات' : 'Ride history',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          _buildHistoryList(isArabic: isArabic),
        ],
      ),
    );
  }

  Widget _buildRideWalletCard({required bool isArabic}) {
    if (_walletSnapshot == null && _walletId.isEmpty) {
      return const SizedBox.shrink();
    }
    return _RideLiquidGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'محفظة الرحلات' : 'Ride wallet',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isArabic
                ? 'المحفظة: ${_walletId.isEmpty ? "غير متصلة" : _walletId}'
                : 'Wallet: ${_walletId.isEmpty ? "Not linked" : _walletId}',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .72),
            ),
          ),
          const SizedBox(height: 10),
          if (_walletSnapshot == null)
            Text(
              isArabic
                  ? 'لا تتوفر أرصدة الرحلات بعد. افتح SyrChat Pay لشحن الرصيد وربط المحافظ.'
                  : 'Ride balances are not available yet. Open SyrChat Pay to top up and manage wallet buckets.',
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    '${isArabic ? "نقدي" : "Cash"} ${fmtCents(_walletSnapshot!.bucketBalance(RideWalletBucketType.cashBalance))} SYP',
                  ),
                ),
                Chip(
                  label: Text(
                    '${isArabic ? "رصيد ترويجي" : "Promo"} ${fmtCents(_walletSnapshot!.bucketBalance(RideWalletBucketType.promoCredit))} SYP',
                  ),
                ),
                Chip(
                  label: Text(
                    '${isArabic ? "استرجاع" : "Refund"} ${fmtCents(_walletSnapshot!.bucketBalance(RideWalletBucketType.refundCredit))} SYP',
                  ),
                ),
                Chip(
                  label: Text(
                    '${isArabic ? "شركة" : "Corporate"} ${fmtCents(_walletSnapshot!.bucketBalance(RideWalletBucketType.corporateCredit))} SYP',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRideSupportCard({required bool isArabic}) {
    return _RideLiquidGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'الدعم' : 'Support',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _contactSupportByMail,
                icon: const Icon(Icons.mail_outline),
                label: Text(isArabic ? 'بريد الدعم' : 'Email support'),
              ),
              FilledButton.icon(
                onPressed: _openSupportTicketComposer,
                icon: const Icon(Icons.support_agent_outlined),
                label: Text(isArabic ? 'فتح تذكرة' : 'Open ticket'),
              ),
              OutlinedButton.icon(
                onPressed: _contactSupportByPhone,
                icon: const Icon(Icons.phone_outlined),
                label: Text(isArabic ? 'اتصال' : 'Call support'),
              ),
            ],
          ),
          if (_supportTickets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              isArabic ? 'آخر التذاكر' : 'Recent tickets',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._supportTickets.take(3).map(
                  (ticket) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      ticket.isOpen
                          ? Icons.mark_email_unread_outlined
                          : Icons.verified_outlined,
                    ),
                    title: Text(ticket.subject),
                    subtitle: Text(
                      '${_supportCategoryLabel(ticket.category, isArabic: isArabic)} • ${_supportTicketStatusLabel(ticket.status, isArabic: isArabic)}'
                      '${ticket.rideId == null ? '' : '\n${ticket.rideId}'}'
                      '${ticket.resolutionNote == null ? '' : '\n${ticket.resolutionNote}'}',
                    ),
                    trailing: Text(
                      _supportContactLabel(
                        ticket.preferredContact,
                        isArabic: isArabic,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildRideServiceInfoCard({required bool isArabic}) {
    final hasBootstrap = _platformBootstrap != null;
    final hasRoutingTelemetry =
        _lastRouteQuote != null || _lastTrafficSnapshot != null;
    if (!hasBootstrap && !hasRoutingTelemetry) {
      return const SizedBox.shrink();
    }
    return _RideLiquidGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'تفاصيل الخدمة' : 'Service details',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          if (_platformBootstrap != null) ...[
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'Ride Config ${_platformBootstrap!.version}: ${_platformBootstrap!.serviceClasses.length} فئات • ${_platformBootstrap!.operatorRoles.length} أدوار'
                  : 'Ride config ${_platformBootstrap!.version}: ${_platformBootstrap!.serviceClasses.length} classes • ${_platformBootstrap!.operatorRoles.length} roles',
            ),
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'عرض الخرائط: ${_platformBootstrap!.mapDisplayStack} • التوجيه: ${_platformBootstrap!.mapRoutingStack}'
                  : 'Map display: ${_platformBootstrap!.mapDisplayStack} • Routing: ${_platformBootstrap!.mapRoutingStack}',
            ),
          ],
          if (_lastRouteQuote != null) ...[
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'TomTom ETA: ${max(1, (_lastRouteQuote!.etaSeconds / 60).round())} د • ${(_lastRouteQuote!.distanceMeters / 1000).toStringAsFixed(1)} كم'
                  : 'TomTom ETA: ${max(1, (_lastRouteQuote!.etaSeconds / 60).round())} min • ${(_lastRouteQuote!.distanceMeters / 1000).toStringAsFixed(1)} km',
            ),
          ],
          if (_lastTrafficSnapshot != null) ...[
            const SizedBox(height: 4),
            Text(
              isArabic
                  ? 'TomTom Traffic: ${_lastTrafficSnapshot!.currentSpeedKmh}/${_lastTrafficSnapshot!.freeFlowSpeedKmh} كم/س'
                  : 'TomTom Traffic: ${_lastTrafficSnapshot!.currentSpeedKmh}/${_lastTrafficSnapshot!.freeFlowSpeedKmh} km/h',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openRideUtilityMenu({required bool isArabic}) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) {
        return ColoredBox(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF0F172A)
              : WeChatPalette.background,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .82,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  Text(
                    isArabic ? 'قائمة الرحلات' : 'Ride menu',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_showSavedRouteMenu)
                    Card(
                      child: ListTile(
                        key:
                            const ValueKey<String>('ride-saved-route-tile'),
                        leading: const Icon(Icons.science_outlined),
                        title: Text(
                          isArabic ? 'استخدام مسار جاهز' : 'Use saved route',
                        ),
                        subtitle: Text(
                          isArabic
                              ? 'باب توما -> المالكي مع تعبئة الحقول تلقائياً'
                              : 'Bab Touma -> Malki with fields prefilled',
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          unawaited(_runSavedRouteRequest(isArabic: isArabic));
                        },
                      ),
                    ),
                  _buildRideWalletCard(isArabic: isArabic),
                  // Cycle 175 — entry to the scheduled-rides surface
                  // (future-pickup bookings). Lives in the same
                  // menu as wallet / support / history.
                  Card(
                    child: ListTile(
                      key: const ValueKey<String>('ride-scheduled-tile'),
                      leading: const Icon(Icons.event_available_rounded),
                      title: Text(
                        isArabic
                            ? 'الرحلات المجدولة'
                            : 'Scheduled rides',
                      ),
                      subtitle: Text(
                        isArabic
                            ? 'احجز رحلة لوقت لاحق (حتى 30 يوماً مقدماً)'
                            : 'Book a ride for later (up to 30 days ahead)',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(_openScheduledRidesPage());
                      },
                    ),
                  ),
                  // Cycle 189 — Saved places (Home / Work / Other)
                  // shortcut. Tapping opens the manager; from there
                  // riders can prefill pickup/destination later via
                  // the picker-mode entry.
                  Card(
                    child: ListTile(
                      key: const ValueKey<String>('ride-saved-places-tile'),
                      leading: const Icon(Icons.bookmarks_outlined),
                      title: Text(
                        isArabic ? 'الأماكن المحفوظة' : 'Saved places',
                      ),
                      subtitle: Text(
                        isArabic
                            ? 'وفّر وقتك: احفظ المنزل والعمل والأماكن المفضلة'
                            : 'Save time: store Home, Work, and favorites',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(_openSavedPlacesManager());
                      },
                    ),
                  ),
                  // Cycle 208 — Promo code entry. MVP surfaces the
                  // validation flow + saved discount preview;
                  // actual fare deduction lands in a follow-up
                  // cycle when the pricing pipeline learns about
                  // promo discounts.
                  Card(
                    child: ListTile(
                      key: const ValueKey<String>('ride-promo-tile'),
                      leading: const Icon(Icons.local_offer_outlined),
                      title: Text(
                        isArabic ? 'كود خصم' : 'Promo code',
                      ),
                      subtitle: Text(
                        isArabic
                            ? 'لديك كود؟ تحقق منه قبل الطلب'
                            : 'Have a code? Validate it before requesting',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(_openPromoEntry());
                      },
                    ),
                  ),
                  // Cycle 217 — Coach Bus passenger hub. Intercity
                  // bus booking lives here as a separate section
                  // (different commercial product, distinct UX).
                  Card(
                    child: ListTile(
                      key: const ValueKey<String>('ride-coach-tile'),
                      leading:
                          const Icon(Icons.directions_bus_filled_rounded),
                      title: Text(
                        isArabic
                            ? 'الباصات بين المدن'
                            : 'Intercity coaches',
                      ),
                      subtitle: Text(
                        isArabic
                            ? 'احجز رحلتك بين دمشق وحمص وحلب واللاذقية'
                            : 'Book journeys between Damascus, Homs, Aleppo, Latakia',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(_openCoachBusHub());
                      },
                    ),
                  ),
                  // Cycle 182 — entry to past-trip history with
                  // receipt-style detail per row + your own rating.
                  Card(
                    child: ListTile(
                      key: const ValueKey<String>('ride-history-tile'),
                      leading: const Icon(Icons.history_rounded),
                      title: Text(
                        isArabic ? 'سجل الرحلات' : 'Trip history',
                      ),
                      subtitle: Text(
                        isArabic
                            ? 'آخر ٥٠ رحلة مع إيصالات وتقييمات'
                            : 'Last 50 trips with receipts + ratings',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(_openRideHistoryPage());
                      },
                    ),
                  ),
                  _buildRideSupportCard(isArabic: isArabic),
                  _buildRideHistoryCard(isArabic: isArabic),
                  _buildRideServiceInfoCard(isArabic: isArabic),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    final pickup = _normalizePlace(_pickupCtrl.text);
    final destination = _normalizePlace(_destinationCtrl.text);
    final bookingIssue = rideBookingValidationIssue(
      pickupQuery: pickup,
      destinationQuery: destination,
      selectedPickup: _selectedPickup,
      selectedDestination: _selectedDestination,
      hasActiveTrip:
          _activeTrip != null && !rideTripStatusIsTerminal(_activeTrip!.status),
    );
    final canRequestRide =
        bookingIssue == null && !_requestingProviderEstimate && !_loading;
    final pickupValidation =
        _pickupValidationMessage(bookingIssue, isArabic: isArabic);
    final destinationValidation =
        _destinationValidationMessage(bookingIssue, isArabic: isArabic);
    final bookingValidation =
        _bookingValidationMessage(bookingIssue, isArabic: isArabic);
    final hasEstimate = ridePlaceSelectionMatchesQuery(
          query: pickup,
          selectedPlace: _selectedPickup,
        ) &&
        ridePlaceSelectionMatchesQuery(
          query: destination,
          selectedPlace: _selectedDestination,
        );
    final estimate = _lastPricingPreview != null
        ? (
            max(1, (_lastPricingPreview!.etaSeconds / 60).ceil()),
            _lastPricingPreview!.totalFareMinorUnits,
          )
        : _lastRouteQuote != null
            ? (
                max(1, (_lastRouteQuote!.etaSeconds / 60).ceil()),
                _fareFromTomTomRoute(_lastRouteQuote!),
              )
            : hasEstimate
                ? _estimate(pickup, destination)
                : null;
    final fareForTaxiPanels = _activeTrip?.fareEstimateCents ?? estimate?.$2;
    final liveMeterFare = fareForTaxiPanels == null
        ? null
        : fareForTaxiPanels +
            (_extraRideStopCount * 900) +
            (_selectedRideFareMode == 'Meter' ? 350 : 0);

    final ridePhase = _ridePhaseFor(_activeTrip);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          shamellRidePageTitle(
            isArabic: isArabic,
            standaloneApp: widget.standaloneApp,
          ),
        ),
        actions: [
          // Cycle 94 — explicit Refresh button so the rider can pull
          // a fresh active-trip / wallet snapshot without dragging
          // the bottom sheet up to find the right scroll edge.
          IconButton(
            onPressed: _loading
                ? null
                : () {
                    // Cycle 127 — haptic on tap matches the driver
                    // Refresh button (Cycle 126) and operator
                    // freshness chip (Cycle 124).
                    unawaited(HapticFeedback.selectionClick());
                    unawaited(_refreshActiveTripState(
                        showNotifications: false));
                  },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: isArabic ? 'تحديث' : 'Refresh',
          ),
          IconButton(
            onPressed: _loading
                ? null
                : () => _openRideUtilityMenu(isArabic: isArabic),
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: isArabic ? 'القائمة' : 'Menu',
          ),
        ],
        // Persistent 3-phase indicator pinned below the title so the
        // rider always sees "Plan → Active → Done" without scrolling
        // through the long booking/tracking ListView to figure out
        // which part of the journey they're in.
        bottom: _loading
            ? null
            : _buildRidePhaseStrip(
                phase: ridePhase,
                activeStatus: _activeTrip?.status,
                isArabic: isArabic,
              ),
      ),
      body: _loading
          ? const ColoredBox(
              color: Color(0xFF0F172A),
              child: ShamellSkeletonList(itemCount: 6),
            )
          // Cycle 65 — Uber/Careem-style layout: full-screen map as
          // the canvas with a draggable bottom sheet holding the
          // booking form, active-trip card, history etc. The sheet
          // starts at ~55% of the screen so the user sees the map
          // context + the most important controls without scrolling.
          : Stack(
              children: <Widget>[
                Positioned.fill(
                  child: _buildMapPreview(isArabic: isArabic),
                ),
                DraggableScrollableSheet(
                  controller: _hailingSheetCtrl,
                  initialChildSize: 0.32,
                  minChildSize: 0.18,
                  maxChildSize: 0.92,
                  snap: true,
                  snapSizes: const <double>[0.18, 0.32, 0.92],
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
                    // Cycle 70 — Column-with-Expanded so the
                    // "Request ride" CTA can pin to the sheet's
                    // footer (visible regardless of scroll position),
                    // matching Uber/Careem's call-to-action pattern.
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: ListView(
                      controller: sheetScroll,
                      padding:
                          const EdgeInsets.fromLTRB(12, 10, 12, 20),
                      children: [
                        // Drag handle so the sheet's affordance is
                        // obvious even with the keyboard up.
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Cycle 66 — collapsed peek hero. The first
                        // ~120 px of the sheet are dedicated to the
                        // wallet balance + a big tappable "Where to?"
                        // strip + a saved-route quick chip. When the
                        // sheet is at min size the rider sees ONLY
                        // this; dragging up (or tapping the strip)
                        // animates to 0.92 and the full booking form
                        // reveals below.
                        _buildHailingPeekHero(isArabic: isArabic),
                        PushReadinessBanner(isArabic: isArabic),
                        if ((widget.initialRideId ?? '').trim().isNotEmpty)
                          _RideLiquidGlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              isArabic
                                  ? 'تم فتح الرحلات من إشعار: ${widget.initialRideId!.trim()}'
                                  : 'Opened from ride notification: ${widget.initialRideId!.trim()}',
                            ),
                          ),
                        _buildActiveTripSemanticsBanner(isArabic: isArabic),
                  if (_activeTrip == null && _requestingProviderEstimate)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 2),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  // Cycle 71 — quiet idle: the TomTom ETA/Traffic
                  // mini-strips only show once the rider has both a
                  // pickup AND a destination selected. Before that
                  // they were noise on an otherwise empty sheet.
                  if (_activeTrip == null &&
                      _lastRouteQuote != null &&
                      _selectedPickup != null &&
                      _selectedDestination != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        isArabic
                            ? 'TomTom ETA: ${max(1, (_lastRouteQuote!.etaSeconds / 60).round())} د • ${(_lastRouteQuote!.distanceMeters / 1000).toStringAsFixed(1)} كم'
                            : 'TomTom ETA: ${max(1, (_lastRouteQuote!.etaSeconds / 60).round())} min • ${(_lastRouteQuote!.distanceMeters / 1000).toStringAsFixed(1)} km',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .72),
                        ),
                      ),
                    ),
                  if (_activeTrip == null &&
                      _lastTrafficSnapshot != null &&
                      _selectedPickup != null &&
                      _selectedDestination != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        isArabic
                            ? 'TomTom Traffic: ${_lastTrafficSnapshot!.currentSpeedKmh}/${_lastTrafficSnapshot!.freeFlowSpeedKmh} كم/س'
                            : 'TomTom Traffic: ${_lastTrafficSnapshot!.currentSpeedKmh}/${_lastTrafficSnapshot!.freeFlowSpeedKmh} km/h',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .72),
                        ),
                      ),
                    ),
                  _buildActiveTripCard(isArabic: isArabic),
                  _RideLiquidGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isArabic ? 'احجز رحلة' : 'Book a ride',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _pickupCtrl,
                          textInputAction: TextInputAction.next,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: isArabic ? 'نقطة الانطلاق' : 'Pickup',
                            border: const OutlineInputBorder(),
                            errorText: pickupValidation,
                          ),
                          onChanged: _onPickupChanged,
                        ),
                        _buildSuggestionsList(
                          isArabic: isArabic,
                          query: pickup,
                          loading: _loadingPickupSuggestions,
                          unavailable: _pickupSearchUnavailable,
                          suggestions: _pickupSuggestions,
                          onSelect: _selectPickupSuggestion,
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                // Cycle 131 — selection haptic when
                                // tapping "Use current location" so
                                // the rider feels the gesture before
                                // the geolocation prompt kicks in.
                                unawaited(
                                    HapticFeedback.selectionClick());
                                unawaited(
                                  _useCurrentLocationAsPickup(
                                    isArabic: isArabic,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.my_location_rounded),
                              label: Text(
                                isArabic
                                    ? 'استخدم موقعي الحالي'
                                    : 'Use current location',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                unawaited(
                                  _pinPickupOnMap(isArabic: isArabic),
                                );
                              },
                              icon: const Icon(Icons.place_outlined),
                              label: Text(
                                isArabic
                                    ? 'ثبت نقطة الانطلاق'
                                    : 'Pin pickup on map',
                              ),
                            ),
                          ],
                        ),
                        if (_pickupModeHint(isArabic: isArabic) != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _pickupModeHint(isArabic: isArabic)!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .88),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: _destinationCtrl,
                          focusNode: _destinationFocus,
                          textInputAction: TextInputAction.done,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: isArabic ? 'الوجهة' : 'Destination',
                            border: const OutlineInputBorder(),
                            errorText: destinationValidation,
                          ),
                          onChanged: _onDestinationChanged,
                        ),
                        _buildSuggestionsList(
                          isArabic: isArabic,
                          query: destination,
                          loading: _loadingDestinationSuggestions,
                          unavailable: _destinationSearchUnavailable,
                          suggestions: _destinationSuggestions,
                          onSelect: _selectDestinationSuggestion,
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                unawaited(
                                  _pinDestinationOnMap(isArabic: isArabic),
                                );
                              },
                              icon: const Icon(Icons.flag_outlined),
                              label: Text(
                                isArabic
                                    ? 'ثبت الوجهة'
                                    : 'Pin destination on map',
                              ),
                            ),
                          ],
                        ),
                        if (_destinationModeHint(isArabic: isArabic) !=
                            null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _destinationModeHint(isArabic: isArabic)!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .88),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: _RideClass.values
                              .map(
                                (rideClass) => ChoiceChip(
                                  label: Text(_rideClassLabel(
                                    rideClass,
                                    isArabic: isArabic,
                                  )),
                                  selected: _rideClass == rideClass,
                                  onSelected: (_) {
                                    setState(() {
                                      _rideClass = rideClass;
                                    });
                                    if (_selectedPickup != null &&
                                        _selectedDestination != null) {
                                      unawaited(_refreshRoutePricingPreview());
                                    }
                                  },
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 10),
                        if (estimate != null)
                          Text(
                            isArabic
                                ? 'التقدير: ${fmtCents(estimate.$2)} SYP • ETA ${estimate.$1} د'
                                : 'Estimate: ${fmtCents(estimate.$2)} SYP • ETA ${estimate.$1} min',
                          ),
                        if (_lastPricingPreview != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            isArabic
                                ? 'الأساس ${fmtCents(_lastPricingPreview!.baseFareMinorUnits)} • المسافة ${fmtCents(_lastPricingPreview!.distanceComponentMinorUnits)} • الزمن ${fmtCents(_lastPricingPreview!.timeComponentMinorUnits)} • الازدحام ${fmtCents(_lastPricingPreview!.trafficSurchargeMinorUnits)} • الرسوم ${fmtCents(_lastPricingPreview!.bookingFeeMinorUnits)}'
                                : 'Base ${fmtCents(_lastPricingPreview!.baseFareMinorUnits)} • Distance ${fmtCents(_lastPricingPreview!.distanceComponentMinorUnits)} • Time ${fmtCents(_lastPricingPreview!.timeComponentMinorUnits)} • Traffic ${fmtCents(_lastPricingPreview!.trafficSurchargeMinorUnits)} • Fees ${fmtCents(_lastPricingPreview!.bookingFeeMinorUnits)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: .72),
                            ),
                          ),
                        ],
                        // Cycle 70 — the primary Request-ride CTA
                        // moved to a sticky footer at the sheet's
                        // bottom (`_buildStickyRequestRideFooter`).
                        // Only the validation-error line stays
                        // inline so it surfaces below the form
                        // fields it relates to.
                        if (bookingValidation != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            bookingValidation,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Cycle 69 — six advanced taxi panels (Journey,
                  // Payment, Safety, Comfort, PostRide, Trust) used
                  // to crowd the sheet directly. Now collapsed
                  // behind a single "More options" expansion so the
                  // first-load reads as: Where-to → Pickup/Dest →
                  // Class → Estimate → Request. Power users tap to
                  // expand for the full set.
                  _RideLiquidGlassCard(
                    padding: EdgeInsets.zero,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        leading: const Icon(Icons.tune_outlined),
                        title: Text(
                          isArabic ? 'خيارات إضافية' : 'More options',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          isArabic
                              ? 'الدفع، السلامة، الراحة، الموثوقية…'
                              : 'Payment, safety, comfort, trust…',
                          style: const TextStyle(fontSize: 12),
                        ),
                        children: <Widget>[
                  TaxiPassengerJourneyPanel(
                    activeTrip: _activeTrip,
                    pickupLabel: pickup,
                    destinationLabel: destination,
                    estimateMinorUnits: estimate?.$2,
                    estimateEtaMinutes: estimate?.$1,
                    hasRoutePreview: _routePreviewPoints.isNotEmpty ||
                        _selectedPickup != null ||
                        _currentLocation != null,
                    hasDriverLocation:
                        _trackingSnapshot?.latestDriverLocation != null,
                    onScheduleRide: _showRideSchedulingSheet,
                    onOpenReceipt: _showRideReceipt,
                    onRateRide: _showRateRideSheet,
                  ),
                  TaxiPassengerPaymentPanel(
                    fareMinorUnits: fareForTaxiPanels,
                    selectedCurrency: _selectedRideCurrency,
                    selectedPaymentMode: _selectedRidePaymentMode,
                    walletLinked: _walletId.trim().isNotEmpty,
                    onCurrencySelected: (currency) {
                      setState(() => _selectedRideCurrency = currency);
                    },
                    onPaymentModeSelected: (mode) {
                      setState(() => _selectedRidePaymentMode = mode);
                    },
                    onOpenWallet: _openRideWallet,
                    onOpenQrPay: _openRideQrPay,
                    onOpenPaymentRequests: _openRidePaymentRequests,
                  ),
                  TaxiPassengerSafetyCommsPanel(
                    hasActiveTrip: _activeTrip != null,
                    openSupportTickets:
                        _supportTickets.where((ticket) => ticket.isOpen).length,
                    onOpenChat: _openRideChatSheet,
                    onVoiceCall: () => unawaited(_startRideVoiceCall()),
                    onVideoCall: _startRideVideoCall,
                    onAudioMessage: _recordRideAudioMessage,
                    onSafetySos: () => unawaited(_triggerRideSos()),
                  ),
                  TaxiPassengerAdvancedBookingPanel(
                    liveMeterMinorUnits: liveMeterFare,
                    extraStopCount: _extraRideStopCount,
                    selectedFareMode: _selectedRideFareMode,
                    selectedRoutePreference: _selectedRideRoutePreference,
                    selectedRideProfile: _selectedRideProfile,
                    selectedBusinessMode: _selectedRideBusinessMode,
                    poolingEnabled: _ridePoolingEnabled,
                    familyModeEnabled: _rideFamilyModeEnabled,
                    favoriteDriverEnabled: _favoriteDriverModeEnabled,
                    onFareModeSelected: (mode) {
                      setState(() => _selectedRideFareMode = mode);
                    },
                    onRoutePreferenceSelected: (preference) {
                      setState(() => _selectedRideRoutePreference = preference);
                    },
                    onRideProfileSelected: (profile) {
                      setState(() => _selectedRideProfile = profile);
                    },
                    onBusinessModeSelected: (mode) {
                      setState(() => _selectedRideBusinessMode = mode);
                    },
                    onPoolingChanged: (value) {
                      setState(() => _ridePoolingEnabled = value);
                    },
                    onFamilyModeChanged: (value) {
                      setState(() => _rideFamilyModeEnabled = value);
                    },
                    onFavoriteDriverChanged: (value) {
                      setState(() => _favoriteDriverModeEnabled = value);
                    },
                    onAddStop: _addRideStop,
                  ),
                  TaxiPassengerPostRideServicesPanel(
                    fareMinorUnits: fareForTaxiPanels,
                    selectedTipPercent: _selectedTipPercent,
                    hasRidePass: _selectedRideBusinessMode == 'Ride Pass',
                    onTipPercentSelected: (percent) {
                      setState(() => _selectedTipPercent = percent);
                    },
                    onSendTip: () => unawaited(
                      _sendRideTip(fareMinorUnits: fareForTaxiPanels),
                    ),
                    onLostAndFound: () => unawaited(_openLostAndFound()),
                    onOpenDispute: () => unawaited(_openRideDispute()),
                  ),
                  TaxiPassengerTrustOptionsPanel(
                    ridePin: _ridePickupCode,
                    routeDeviationAlertsEnabled:
                        _rideRouteDeviationAlertsEnabled,
                    waitingGraceMinutes: _rideWaitingGraceMinutes,
                    selectedCancellationRule: _selectedRideCancellationRule,
                    selectedAccessibilityNeed: _selectedRideAccessibilityNeed,
                    petTaxiEnabled: _petTaxiEnabled,
                    packageRideEnabled: _packageRideEnabled,
                    recurringRideEnabled: _recurringRideEnabled,
                    pickupInstructionsReady: _pickupInstructionsReady,
                    fareSplitContactCount: _fareSplitContactCount,
                    promoCreditMinorUnits: _promoCreditMinorUnits == 0
                        ? null
                        : _promoCreditMinorUnits,
                    surgeExplanationVisible: _surgeExplanationVisible,
                    onGenerateRidePin: _generateRidePickupCode,
                    onRouteDeviationAlertsChanged: (value) {
                      setState(() => _rideRouteDeviationAlertsEnabled = value);
                    },
                    onWaitingFeeInfo: _showWaitingFeeInfo,
                    onCancellationRuleSelected: (rule) {
                      setState(() => _selectedRideCancellationRule = rule);
                    },
                    onAccessibilityNeedSelected: (need) {
                      setState(() => _selectedRideAccessibilityNeed = need);
                    },
                    onPetTaxiChanged: (value) {
                      setState(() => _petTaxiEnabled = value);
                    },
                    onPackageRideChanged: (value) {
                      setState(() => _packageRideEnabled = value);
                    },
                    onRecurringRideChanged: (value) {
                      setState(() => _recurringRideEnabled = value);
                    },
                    onPickupInstructions: () =>
                        unawaited(_openPickupInstructionsSheet()),
                    onFareSplit: _addFareSplitContact,
                    onPromoCode: _applyRidePromoCode,
                    onSurgeExplanation: _showRideSurgeExplanation,
                  ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
                        ),
                        // Cycle 70 — sticky footer with the primary
                        // request-ride CTA. Hidden during an active
                        // trip (no booking action available) and
                        // disabled while validation prevents the
                        // request. Sits OUTSIDE the scrollable
                        // ListView so it stays in view at any sheet
                        // snap-point.
                        if (_activeTrip == null)
                          _buildStickyRequestRideFooter(
                            isArabic: isArabic,
                            canRequest: canRequestRide,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Cycle 70 — primary Request-ride CTA pinned at the bottom of the
  /// bottom sheet. Always visible while the rider has no active
  /// trip; tapping fires the same `_requestRide` handler that lived
  /// inline in the form before.
  Widget _buildStickyRequestRideFooter({
    required bool isArabic,
    required bool canRequest,
  }) {
    final theme = Theme.of(context);
    // Cycle 85 — replace the static taxi icon with an inline spinner
    // while the booking request is in flight. The button is already
    // disabled during the request, but the disabled state alone read
    // as "broken button" to first-time users.
    final requesting = _requestingProviderEstimate;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF0F172A)
              : WeChatPalette.background,
          border: Border(
            top: BorderSide(
              color: theme.dividerColor.withValues(alpha: .22),
              width: 1,
            ),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: canRequest ? _requestRide : null,
            icon: requesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.local_taxi_outlined),
            label: Text(
              requesting
                  ? (isArabic ? 'جارٍ الإرسال…' : 'Sending…')
                  : (isArabic ? 'اطلب سيارة الآن' : 'Request ride now'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
