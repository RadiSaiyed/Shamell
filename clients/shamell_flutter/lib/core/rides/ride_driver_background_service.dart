import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../base_url.dart';
import '../notification_service.dart';
import '../runtime_base_scope.dart';
import 'ride_hailing_store.dart';
import 'ride_mobility_api.dart';

const String rideDriverPrefsKeyPrefix = 'ride.driver.surface.v1.';
const String rideDriverBackgroundConfigPrefix = 'ride.driver.background.v1.';
const String _rideDriverBackgroundUniqueName =
    'ride.driver.background.presence.periodic.v1';
const String _rideDriverBackgroundKickUniqueName =
    'ride.driver.background.presence.kick.v1';
const String _rideDriverBackgroundTaskName = 'rideDriverBackgroundPresence';
const String _rideDriverBackgroundKickTaskName =
    'rideDriverBackgroundPresenceKick';
const Duration _rideDriverBackgroundFrequency = Duration(minutes: 15);
const Duration _rideDriverBackgroundInitialDelay = Duration(seconds: 10);

bool _rideDriverBackgroundInitialized = false;

String _rideDriverBackgroundConfigKey(String suffix) =>
    '$rideDriverBackgroundConfigPrefix$suffix';

String rideDriverBackgroundOnlineKey() =>
    _rideDriverBackgroundConfigKey('online');
String rideDriverBackgroundBaseUrlKey() =>
    _rideDriverBackgroundConfigKey('base_url');
String rideDriverBackgroundDriverNameKey() =>
    _rideDriverBackgroundConfigKey('driver_name');
String rideDriverBackgroundCarPlateKey() =>
    _rideDriverBackgroundConfigKey('car_plate');
String rideDriverBackgroundQueueCountKey() =>
    _rideDriverBackgroundConfigKey('queue_count');
String rideDriverBackgroundActiveRideIdKey() =>
    _rideDriverBackgroundConfigKey('active_ride_id');
String rideDriverBackgroundActiveStatusKey() =>
    _rideDriverBackgroundConfigKey('active_status');

@visibleForTesting
bool rideDriverBackgroundShouldSchedule({
  required bool online,
  required String baseUrl,
  required String driverName,
  required String carPlate,
}) {
  return online &&
      normalizeSecureApiBaseUrl(baseUrl.trim()) != null &&
      driverName.trim().isNotEmpty &&
      carPlate.trim().isNotEmpty;
}

@visibleForTesting
bool rideDriverBackgroundShouldNotifyQueueGrowth({
  required int? previousQueueCount,
  required int nextQueueCount,
}) {
  if (previousQueueCount == null) {
    return false;
  }
  return nextQueueCount > previousQueueCount;
}

@visibleForTesting
bool rideDriverBackgroundShouldNotifyTripTransition({
  required String? previousRideId,
  required RideTripStatus? previousStatus,
  required RideTrip? nextTrip,
}) {
  if (nextTrip == null || previousRideId == null || previousStatus == null) {
    return false;
  }
  if (previousRideId != nextTrip.rideId) {
    return false;
  }
  return previousStatus != nextTrip.status;
}

bool rideDriverBackgroundShouldKickForPushType(String pushType) {
  switch (pushType.trim().toLowerCase()) {
    case 'ride_driver_dispatch':
    case 'ride_driver_update':
      return true;
    default:
      return false;
  }
}

String _rideDriverBackgroundTripStatusLabel(
  RideTripStatus status, {
  required bool isArabic,
}) {
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

Future<void> rideDriverInitializeBackgroundWork() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  if (_rideDriverBackgroundInitialized) {
    return;
  }
  await Workmanager().initialize(
    rideDriverBackgroundCallbackDispatcher,
  );
  _rideDriverBackgroundInitialized = true;
}

Future<void> rideDriverScheduleImmediateBackgroundKick() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final online = prefs.getBool(rideDriverBackgroundOnlineKey()) ?? false;
  final baseUrl =
      (prefs.getString(rideDriverBackgroundBaseUrlKey()) ?? '').trim();
  final driverName =
      (prefs.getString(rideDriverBackgroundDriverNameKey()) ?? '').trim();
  final carPlate =
      (prefs.getString(rideDriverBackgroundCarPlateKey()) ?? '').trim();
  if (!rideDriverBackgroundShouldSchedule(
    online: online,
    baseUrl: baseUrl,
    driverName: driverName,
    carPlate: carPlate,
  )) {
    return;
  }
  await rideDriverInitializeBackgroundWork();
  await Workmanager().registerOneOffTask(
    _rideDriverBackgroundKickUniqueName,
    _rideDriverBackgroundKickTaskName,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

Future<void> rideDriverSyncBackgroundTracking({
  required String? activeBaseUrl,
  required bool online,
  required String driverName,
  required String carPlate,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final resolvedBaseUrl = shamellResolveRuntimeBaseUrl(
    storedBaseUrl: prefs.getString('base_url') ?? '',
    activeBaseUrl: activeBaseUrl,
  );
  final normalizedBaseUrl = normalizeSecureApiBaseUrl(resolvedBaseUrl) ?? '';
  final normalizedDriverName = driverName.trim();
  final normalizedCarPlate = carPlate.trim().toUpperCase();

  await prefs.setBool(rideDriverBackgroundOnlineKey(), online);
  await prefs.setString(rideDriverBackgroundBaseUrlKey(), normalizedBaseUrl);
  await prefs.setString(
    rideDriverBackgroundDriverNameKey(),
    normalizedDriverName,
  );
  await prefs.setString(
    rideDriverBackgroundCarPlateKey(),
    normalizedCarPlate,
  );

  await rideDriverInitializeBackgroundWork();
  if (!rideDriverBackgroundShouldSchedule(
    online: online,
    baseUrl: normalizedBaseUrl,
    driverName: normalizedDriverName,
    carPlate: normalizedCarPlate,
  )) {
    await Workmanager().cancelByUniqueName(_rideDriverBackgroundUniqueName);
    await Workmanager().cancelByUniqueName(_rideDriverBackgroundKickUniqueName);
    return;
  }

  final constraints = Constraints(networkType: NetworkType.connected);
  await Workmanager().registerPeriodicTask(
    _rideDriverBackgroundUniqueName,
    _rideDriverBackgroundTaskName,
    frequency: _rideDriverBackgroundFrequency,
    initialDelay: _rideDriverBackgroundInitialDelay,
    constraints: constraints,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
  await Workmanager().registerOneOffTask(
    _rideDriverBackgroundKickUniqueName,
    _rideDriverBackgroundKickTaskName,
    initialDelay: _rideDriverBackgroundInitialDelay,
    constraints: constraints,
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

Future<void> rideDriverSyncBackgroundObservedState({
  required int queueCount,
  required RideTrip? activeTrip,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(rideDriverBackgroundQueueCountKey(), queueCount);
  if (activeTrip == null || rideTripStatusIsTerminal(activeTrip.status)) {
    await prefs.remove(rideDriverBackgroundActiveRideIdKey());
    await prefs.remove(rideDriverBackgroundActiveStatusKey());
    return;
  }
  await prefs.setString(
      rideDriverBackgroundActiveRideIdKey(), activeTrip.rideId);
  await prefs.setString(
    rideDriverBackgroundActiveStatusKey(),
    rideTripStatusWireValue(activeTrip.status),
  );
}

@pragma('vm:entry-point')
void rideDriverBackgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      DartPluginRegistrant.ensureInitialized();
    } catch (_) {}
    return _executeRideDriverBackgroundTask(taskName);
  });
}

Future<bool> _executeRideDriverBackgroundTask(String taskName) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }
  final prefs = await SharedPreferences.getInstance();
  final online = prefs.getBool(rideDriverBackgroundOnlineKey()) ?? false;
  final baseUrl =
      (prefs.getString(rideDriverBackgroundBaseUrlKey()) ?? '').trim();
  final driverName =
      (prefs.getString(rideDriverBackgroundDriverNameKey()) ?? '').trim();
  final carPlate =
      (prefs.getString(rideDriverBackgroundCarPlateKey()) ?? '').trim();
  if (!rideDriverBackgroundShouldSchedule(
    online: online,
    baseUrl: baseUrl,
    driverName: driverName,
    carPlate: carPlate,
  )) {
    return true;
  }

  final api = RideMobilityApi(baseUrl: baseUrl);
  final position = await _rideDriverBackgroundResolvePosition();
  try {
    await api.setDriverPresence(
      online: true,
      lat: position?.latitude,
      lon: position?.longitude,
      driverName: driverName,
      carPlate: carPlate,
    );
  } catch (_) {
    return false;
  }

  try {
    await NotificationService.initialize();
  } catch (_) {}

  try {
    final queue = await api.driverQueueTrips(limit: 1);
    final previousQueueCount =
        prefs.getInt(rideDriverBackgroundQueueCountKey());
    final nextQueueCount = queue.length;
    if (rideDriverBackgroundShouldNotifyQueueGrowth(
      previousQueueCount: previousQueueCount,
      nextQueueCount: nextQueueCount,
    )) {
      final nextTrip = queue.first;
      await NotificationService.showIncomingRide(
        rideId: nextTrip.rideId,
        pickupSummary: '${nextTrip.pickup} -> ${nextTrip.destination}',
      );
    }
    await prefs.setInt(rideDriverBackgroundQueueCountKey(), nextQueueCount);
  } catch (_) {}

  try {
    final nextTrip = await api.driverActiveTrip();
    final previousRideId =
        (prefs.getString(rideDriverBackgroundActiveRideIdKey()) ?? '').trim();
    final previousStatusRaw =
        (prefs.getString(rideDriverBackgroundActiveStatusKey()) ?? '').trim();
    final previousStatus = rideTripStatusFromWire(previousStatusRaw);
    if (rideDriverBackgroundShouldNotifyTripTransition(
      previousRideId: previousRideId.isEmpty ? null : previousRideId,
      previousStatus: previousStatus,
      nextTrip: nextTrip,
    )) {
      final isArabic =
          PlatformDispatcher.instance.locale.languageCode.startsWith('ar');
      final label = _rideDriverBackgroundTripStatusLabel(
        nextTrip!.status,
        isArabic: isArabic,
      );
      await NotificationService.showDriverTripUpdate(
        rideId: nextTrip.rideId,
        title: isArabic ? 'تحديث الرحلة' : 'Trip update',
        body: isArabic
            ? 'تم تحديث الرحلة الحالية: $label'
            : 'Active trip updated: $label',
      );
    }
    if (nextTrip == null || rideTripStatusIsTerminal(nextTrip.status)) {
      await prefs.remove(rideDriverBackgroundActiveRideIdKey());
      await prefs.remove(rideDriverBackgroundActiveStatusKey());
    } else {
      await prefs.setString(
        rideDriverBackgroundActiveRideIdKey(),
        nextTrip.rideId,
      );
      await prefs.setString(
        rideDriverBackgroundActiveStatusKey(),
        rideTripStatusWireValue(nextTrip.status),
      );
    }
  } catch (_) {}

  // Both periodic and kick tasks treat reachability as success; per-call
  // failures (e.g. setDriverPresence) already short-circuit with `return
  // false` so Workmanager can retry the periodic run on backoff.
  return true;
}

Future<Position?> _rideDriverBackgroundResolvePosition() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return null;
  }
  final permission = await Geolocator.checkPermission();
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
