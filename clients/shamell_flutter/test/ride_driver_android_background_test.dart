import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/rides/ride_driver_android_background.dart';

void main() {
  group('rideDriverIsAggressiveBackgroundVendor', () {
    test('flags Xiaomi-family devices as aggressive vendors', () {
      expect(
        rideDriverIsAggressiveBackgroundVendor(
          'Xiaomi',
          brand: 'Redmi',
        ),
        isTrue,
      );
      expect(
        rideDriverIsAggressiveBackgroundVendor(
          'Google',
          brand: 'Pixel',
        ),
        isFalse,
      );
    });
  });

  group('rideDriverAndroidBackgroundHardeningLevel', () {
    const unrestrictedPixel = RideDriverAndroidBackgroundStatus(
      manufacturer: 'Google',
      brand: 'Pixel',
      ignoringBatteryOptimizations: true,
      canManageBatteryOptimizations: true,
      supportsVendorAutostartSettings: false,
      aggressiveBackgroundVendor: false,
    );
    const restrictedXiaomi = RideDriverAndroidBackgroundStatus(
      manufacturer: 'Xiaomi',
      brand: 'Redmi',
      ignoringBatteryOptimizations: false,
      canManageBatteryOptimizations: true,
      supportsVendorAutostartSettings: true,
      aggressiveBackgroundVendor: true,
    );
    const unrestrictedXiaomi = RideDriverAndroidBackgroundStatus(
      manufacturer: 'Xiaomi',
      brand: 'Redmi',
      ignoringBatteryOptimizations: true,
      canManageBatteryOptimizations: true,
      supportsVendorAutostartSettings: true,
      aggressiveBackgroundVendor: true,
    );

    test('stays quiet when the driver is offline', () {
      expect(
        rideDriverAndroidBackgroundHardeningLevel(
          online: false,
          status: restrictedXiaomi,
        ),
        RideDriverAndroidBackgroundHardeningLevel.none,
      );
    });

    test('requires action while battery optimization still restricts tracking',
        () {
      expect(
        rideDriverAndroidBackgroundHardeningLevel(
          online: true,
          status: restrictedXiaomi,
        ),
        RideDriverAndroidBackgroundHardeningLevel.required,
      );
    });

    test('downgrades to recommended once unrestricted battery is enabled', () {
      expect(
        rideDriverAndroidBackgroundHardeningLevel(
          online: true,
          status: unrestrictedXiaomi,
        ),
        RideDriverAndroidBackgroundHardeningLevel.recommended,
      );
    });

    test('clears the warning on calmer vendors once unrestricted', () {
      expect(
        rideDriverAndroidBackgroundHardeningLevel(
          online: true,
          status: unrestrictedPixel,
        ),
        RideDriverAndroidBackgroundHardeningLevel.none,
      );
    });
  });
}
