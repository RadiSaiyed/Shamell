import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _rideDriverAndroidSystemChannel =
    MethodChannel('shamell/android_system');

enum RideDriverAndroidBackgroundHardeningLevel {
  none,
  recommended,
  required,
}

class RideDriverAndroidBackgroundStatus {
  final String manufacturer;
  final String brand;
  final bool ignoringBatteryOptimizations;
  final bool canManageBatteryOptimizations;
  final bool supportsVendorAutostartSettings;
  final bool aggressiveBackgroundVendor;

  const RideDriverAndroidBackgroundStatus({
    required this.manufacturer,
    required this.brand,
    required this.ignoringBatteryOptimizations,
    required this.canManageBatteryOptimizations,
    required this.supportsVendorAutostartSettings,
    required this.aggressiveBackgroundVendor,
  });

  String get vendorLabel =>
      rideDriverAndroidVendorLabel(manufacturer, brand: brand);

  factory RideDriverAndroidBackgroundStatus.fromChannelMap(
    Map<Object?, Object?> raw,
  ) {
    final manufacturer = (raw['manufacturer'] as String? ?? '').trim();
    final brand = (raw['brand'] as String? ?? '').trim();
    return RideDriverAndroidBackgroundStatus(
      manufacturer: manufacturer,
      brand: brand,
      ignoringBatteryOptimizations:
          raw['ignoring_battery_optimizations'] == true,
      canManageBatteryOptimizations:
          raw['can_manage_battery_optimizations'] == true,
      supportsVendorAutostartSettings:
          raw['supports_vendor_autostart_settings'] == true,
      aggressiveBackgroundVendor: raw['aggressive_background_vendor'] == true,
    );
  }
}

@visibleForTesting
String rideDriverAndroidVendorLabel(
  String manufacturer, {
  required String brand,
}) {
  final manufacturerLabel = manufacturer.trim();
  if (manufacturerLabel.isNotEmpty) {
    return manufacturerLabel;
  }
  final brandLabel = brand.trim();
  if (brandLabel.isNotEmpty) {
    return brandLabel;
  }
  return 'Android';
}

@visibleForTesting
bool rideDriverIsAggressiveBackgroundVendor(
  String manufacturer, {
  required String brand,
}) {
  final normalized = '${manufacturer.trim()} ${brand.trim()}'.toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  const needles = <String>[
    'xiaomi',
    'redmi',
    'poco',
    'oppo',
    'realme',
    'vivo',
    'iqoo',
    'huawei',
    'honor',
    'oneplus',
  ];
  for (final needle in needles) {
    if (normalized.contains(needle)) {
      return true;
    }
  }
  return false;
}

RideDriverAndroidBackgroundHardeningLevel
    rideDriverAndroidBackgroundHardeningLevel({
  required bool online,
  required RideDriverAndroidBackgroundStatus? status,
}) {
  if (!online || status == null) {
    return RideDriverAndroidBackgroundHardeningLevel.none;
  }
  if (status.canManageBatteryOptimizations &&
      !status.ignoringBatteryOptimizations) {
    return RideDriverAndroidBackgroundHardeningLevel.required;
  }
  if (status.aggressiveBackgroundVendor &&
      status.supportsVendorAutostartSettings) {
    return RideDriverAndroidBackgroundHardeningLevel.recommended;
  }
  return RideDriverAndroidBackgroundHardeningLevel.none;
}

Future<RideDriverAndroidBackgroundStatus?>
    loadRideDriverAndroidBackgroundStatus() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  try {
    final raw =
        await _rideDriverAndroidSystemChannel.invokeMapMethod<Object?, Object?>(
            'driver_background_hardening_status');
    if (raw == null) {
      return null;
    }
    return RideDriverAndroidBackgroundStatus.fromChannelMap(raw);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

Future<bool> openRideDriverBatteryOptimizationSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    return await _rideDriverAndroidSystemChannel
            .invokeMethod<bool>('open_driver_background_battery_settings') ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

Future<bool> openRideDriverAutostartSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    return await _rideDriverAndroidSystemChannel
            .invokeMethod<bool>('open_driver_background_autostart_settings') ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

Future<bool> openRideDriverAppInfoSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    return await _rideDriverAndroidSystemChannel
            .invokeMethod<bool>('open_driver_app_info_settings') ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
