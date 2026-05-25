import 'hardware_attestation_contract.dart';

class HardwareAttestation {
  static Future<RuntimeCompromiseState> getRuntimeCompromiseState() async =>
      RuntimeCompromiseState.safe;

  static Future<bool> isRuntimeIntegrityFailClosed() async => false;

  static Future<String?> tryGetAppleDeviceCheckTokenB64() async => null;

  static Future<String?> tryGetPlayIntegrityToken({
    required String nonceB64,
  }) async =>
      null;

  static Future<int?> tryGetAndroidSdkInt() async => null;

  static Future<String?> tryGetAndroidSecureId({
    bool? platformIsAndroid,
  }) async =>
      null;

  static Future<bool> isProbablyAndroidEmulator({
    bool? platformIsAndroid,
  }) async =>
      false;
}
