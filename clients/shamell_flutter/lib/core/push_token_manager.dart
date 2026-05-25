import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import 'privacy_redaction.dart';

typedef PushTokenRegistrar = Future<void> Function({
  required String deviceId,
  required String token,
  String? platform,
});

typedef PushTokenUnregistrar = Future<void> Function({
  required String deviceId,
});

typedef PushTokenBindingFingerprintLoader = Future<String?> Function({
  required String deviceId,
});

typedef PushTokenBindingFingerprintSaver = Future<void> Function({
  required String deviceId,
  required String fingerprint,
});

typedef PushTokenBindingFingerprintClearer = Future<void> Function({
  required String deviceId,
});

const String _pushTokenBindingFingerprintVersion = 'v2';

String pushTokenPlatformLabel(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    _ => 'flutter',
  };
}

String pushTokenBindingFingerprint({
  required String token,
  required String platform,
}) {
  final normalizedToken = token.trim();
  final normalizedPlatform = platform.trim().toLowerCase();
  final digest = crypto.sha256
      .convert(
        utf8.encode(
          '$_pushTokenBindingFingerprintVersion|$normalizedPlatform|$normalizedToken',
        ),
      )
      .toString();
  return 'sha256:$digest';
}

class PushTokenManager {
  static StreamSubscription<String>? _tokenRefreshSub;
  static Object? _registrationScope;
  static String? _registeredDeviceId;
  static String? _registeredToken;

  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _registrationScope = null;
    _registeredDeviceId = null;
    _registeredToken = null;
  }

  static Future<String?> warmUpPushToken({
    Future<void> Function()? initializeFirebaseOverride,
    Future<NotificationPermissionState> Function()? ensurePermissionOverride,
    Future<String?> Function()? getTokenOverride,
  }) async {
    return _resolveCurrentToken(
      initializeFirebaseOverride: initializeFirebaseOverride,
      ensurePermissionOverride: ensurePermissionOverride,
      getTokenOverride: getTokenOverride,
    );
  }

  static Future<void> ensureRegisteredForDevice({
    required Object registrationScope,
    required String deviceId,
    required PushTokenRegistrar registerToken,
    required PushTokenUnregistrar unregisterToken,
    PushTokenBindingFingerprintLoader? loadPersistedBindingFingerprint,
    PushTokenBindingFingerprintSaver? savePersistedBindingFingerprint,
    PushTokenBindingFingerprintClearer? clearPersistedBindingFingerprint,
    Future<void> Function()? initializeFirebaseOverride,
    Future<NotificationPermissionState> Function()? ensurePermissionOverride,
    Future<String?> Function()? getTokenOverride,
    Stream<String>? onTokenRefreshOverride,
    TargetPlatform? targetPlatformOverride,
  }) async {
    final token = await _resolveCurrentToken(
      initializeFirebaseOverride: initializeFirebaseOverride,
      ensurePermissionOverride: ensurePermissionOverride,
      getTokenOverride: getTokenOverride,
    );
    if (token == null) {
      final persistedFingerprint = await _loadPersistedBindingFingerprint(
        loadPersistedBindingFingerprint,
        deviceId: deviceId,
      );
      if (persistedFingerprint.isNotEmpty) {
        await unregisterForDevice(
          deviceId: deviceId,
          unregisterToken: unregisterToken,
          clearPersistedBindingFingerprint: clearPersistedBindingFingerprint,
        );
        return;
      }
      await _unregisterIfCurrentBinding(
        registrationScope: registrationScope,
        deviceId: deviceId,
        unregisterToken: unregisterToken,
        clearPersistedBindingFingerprint: clearPersistedBindingFingerprint,
      );
      return;
    }

    final platform = pushTokenPlatformLabel(
      targetPlatformOverride ?? defaultTargetPlatform,
    );
    final bindingFingerprint = pushTokenBindingFingerprint(
      token: token,
      platform: platform,
    );
    await _registerTokenIfNeeded(
      registrationScope: registrationScope,
      deviceId: deviceId,
      token: token,
      platform: platform,
      bindingFingerprint: bindingFingerprint,
      registerToken: registerToken,
      savePersistedBindingFingerprint: savePersistedBindingFingerprint,
    );
    await _bindTokenRefresh(
      registrationScope: registrationScope,
      deviceId: deviceId,
      registerToken: registerToken,
      unregisterToken: unregisterToken,
      savePersistedBindingFingerprint: savePersistedBindingFingerprint,
      clearPersistedBindingFingerprint: clearPersistedBindingFingerprint,
      platform: platform,
      onTokenRefreshOverride: onTokenRefreshOverride,
    );
  }

  static Future<void> unregisterForDevice({
    required String deviceId,
    required PushTokenUnregistrar unregisterToken,
    PushTokenBindingFingerprintClearer? clearPersistedBindingFingerprint,
  }) async {
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      await clearRegistrationForDevice();
      return;
    }
    try {
      await unregisterToken(deviceId: normalizedDeviceId);
    } finally {
      await _clearPersistedBindingFingerprint(
        clearPersistedBindingFingerprint,
        deviceId: normalizedDeviceId,
      );
      await clearRegistrationForDevice(deviceId: normalizedDeviceId);
    }
  }

  static Future<void> reconcileRegistrationForDevice({
    required String deviceId,
    required PushTokenRegistrar registerToken,
    required PushTokenUnregistrar unregisterToken,
    PushTokenBindingFingerprintLoader? loadPersistedBindingFingerprint,
    PushTokenBindingFingerprintSaver? savePersistedBindingFingerprint,
    PushTokenBindingFingerprintClearer? clearPersistedBindingFingerprint,
    Future<void> Function()? initializeFirebaseOverride,
    Future<NotificationPermissionState> Function()? ensurePermissionOverride,
    Future<String?> Function()? getTokenOverride,
    TargetPlatform? targetPlatformOverride,
  }) async {
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      await clearRegistrationForDevice();
      return;
    }
    final token = await _resolveCurrentToken(
      initializeFirebaseOverride: initializeFirebaseOverride,
      ensurePermissionOverride: ensurePermissionOverride,
      getTokenOverride: getTokenOverride,
    );
    if (token == null) {
      await unregisterForDevice(
        deviceId: normalizedDeviceId,
        unregisterToken: unregisterToken,
        clearPersistedBindingFingerprint: clearPersistedBindingFingerprint,
      );
      return;
    }
    final platform = pushTokenPlatformLabel(
      targetPlatformOverride ?? defaultTargetPlatform,
    );
    final bindingFingerprint = pushTokenBindingFingerprint(
      token: token,
      platform: platform,
    );
    if (_registeredDeviceId != null &&
        _registeredDeviceId != normalizedDeviceId) {
      await clearRegistrationForDevice();
    }
    final persistedFingerprint = await _loadPersistedBindingFingerprint(
      loadPersistedBindingFingerprint,
      deviceId: normalizedDeviceId,
    );
    if (_registeredDeviceId == normalizedDeviceId &&
        _registeredToken == token &&
        persistedFingerprint == bindingFingerprint) {
      _registeredDeviceId = normalizedDeviceId;
      _registeredToken = token;
      return;
    }
    if (_registeredDeviceId == normalizedDeviceId &&
        _registeredToken == token) {
      if (persistedFingerprint != bindingFingerprint) {
        await _savePersistedBindingFingerprint(
          savePersistedBindingFingerprint,
          deviceId: normalizedDeviceId,
          fingerprint: bindingFingerprint,
        );
      }
      _registeredToken = token;
      return;
    }
    await registerToken(
      deviceId: normalizedDeviceId,
      token: token,
      platform: platform,
    );
    await _savePersistedBindingFingerprint(
      savePersistedBindingFingerprint,
      deviceId: normalizedDeviceId,
      fingerprint: bindingFingerprint,
    );
    _registeredDeviceId = normalizedDeviceId;
    _registeredToken = token;
  }

  static Future<void> clearRegistrationForDevice({String? deviceId}) async {
    final normalizedDeviceId = deviceId?.trim();
    if (normalizedDeviceId != null &&
        normalizedDeviceId.isNotEmpty &&
        _registeredDeviceId != normalizedDeviceId) {
      return;
    }
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _registrationScope = null;
    _registeredDeviceId = null;
    _registeredToken = null;
  }

  static Future<String?> _resolveCurrentToken({
    Future<void> Function()? initializeFirebaseOverride,
    Future<NotificationPermissionState> Function()? ensurePermissionOverride,
    Future<String?> Function()? getTokenOverride,
  }) async {
    final permissionState = await (ensurePermissionOverride ??
        NotificationService.ensureNotificationPermission)();
    if (!notificationPermissionAllowsPush(permissionState)) {
      debugPrint(
        'PUSH_TOKEN_SKIP: notifications not allowed ($permissionState)',
      );
      return null;
    }
    try {
      await (initializeFirebaseOverride ?? Firebase.initializeApp)();
    } catch (error) {
      debugPrint('PUSH_TOKEN_FIREBASE_INIT_ERROR: $error');
    }
    String? token;
    try {
      token = await (getTokenOverride ?? FirebaseMessaging.instance.getToken)();
    } catch (error) {
      debugPrint('PUSH_TOKEN_GET_ERROR: $error');
      rethrow;
    }
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) {
      debugPrint('PUSH_TOKEN_EMPTY');
      return null;
    }
    debugPrint('PUSH_TOKEN_READY: ${normalized.length} chars');
    return normalized;
  }

  static Future<void> _registerTokenIfNeeded({
    required Object registrationScope,
    required String deviceId,
    required String token,
    required String platform,
    required String bindingFingerprint,
    required PushTokenRegistrar registerToken,
    PushTokenBindingFingerprintSaver? savePersistedBindingFingerprint,
  }) async {
    if (_registeredDeviceId == deviceId && _registeredToken == token) {
      if (_registrationScope == null) {
        _registrationScope = registrationScope;
      }
      if (identical(_registrationScope, registrationScope)) {
        return;
      }
    }
    await registerToken(
      deviceId: deviceId,
      token: token,
      platform: platform,
    );
    debugPrint(
      'PUSH_TOKEN_REGISTERED: device=${shamellMaskIdentifier(deviceId, prefix: 3, suffix: 2)} platform=$platform',
    );
    await _savePersistedBindingFingerprint(
      savePersistedBindingFingerprint,
      deviceId: deviceId,
      fingerprint: bindingFingerprint,
    );
    _registrationScope = registrationScope;
    _registeredDeviceId = deviceId;
    _registeredToken = token;
  }

  static Future<void> _bindTokenRefresh({
    required Object registrationScope,
    required String deviceId,
    required PushTokenRegistrar registerToken,
    required PushTokenUnregistrar unregisterToken,
    PushTokenBindingFingerprintSaver? savePersistedBindingFingerprint,
    PushTokenBindingFingerprintClearer? clearPersistedBindingFingerprint,
    required String platform,
    Stream<String>? onTokenRefreshOverride,
  }) async {
    final unchangedBinding = identical(_registrationScope, registrationScope) &&
        _registeredDeviceId == deviceId &&
        _tokenRefreshSub != null;
    if (unchangedBinding) {
      return;
    }
    await _tokenRefreshSub?.cancel();
    final stream =
        onTokenRefreshOverride ?? FirebaseMessaging.instance.onTokenRefresh;
    _tokenRefreshSub = stream.listen((rawToken) {
      final token = rawToken.trim();
      if (token.isEmpty) {
        unawaited(
          _unregisterIfCurrentBinding(
            registrationScope: registrationScope,
            deviceId: deviceId,
            unregisterToken: unregisterToken,
            clearPersistedBindingFingerprint: clearPersistedBindingFingerprint,
          ),
        );
        return;
      }
      final bindingFingerprint = pushTokenBindingFingerprint(
        token: token,
        platform: platform,
      );
      unawaited(
        _registerTokenIfNeeded(
          registrationScope: registrationScope,
          deviceId: deviceId,
          token: token,
          platform: platform,
          bindingFingerprint: bindingFingerprint,
          registerToken: registerToken,
          savePersistedBindingFingerprint: savePersistedBindingFingerprint,
        ),
      );
    });
  }

  static Future<void> _unregisterIfCurrentBinding({
    required Object registrationScope,
    required String deviceId,
    required PushTokenUnregistrar unregisterToken,
    PushTokenBindingFingerprintClearer? clearPersistedBindingFingerprint,
  }) async {
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) return;
    if (_registeredDeviceId != normalizedDeviceId) {
      return;
    }
    if (_registrationScope != null &&
        !identical(_registrationScope, registrationScope)) {
      return;
    }
    await unregisterForDevice(
      deviceId: normalizedDeviceId,
      unregisterToken: unregisterToken,
      clearPersistedBindingFingerprint: clearPersistedBindingFingerprint,
    );
  }

  static Future<String> _loadPersistedBindingFingerprint(
    PushTokenBindingFingerprintLoader? loader, {
    required String deviceId,
  }) async {
    if (loader == null) return '';
    try {
      return (await loader(deviceId: deviceId) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static Future<void> _savePersistedBindingFingerprint(
    PushTokenBindingFingerprintSaver? saver, {
    required String deviceId,
    required String fingerprint,
  }) async {
    if (saver == null) return;
    try {
      await saver(deviceId: deviceId, fingerprint: fingerprint);
    } catch (_) {}
  }

  static Future<void> _clearPersistedBindingFingerprint(
    PushTokenBindingFingerprintClearer? clearer, {
    required String deviceId,
  }) async {
    if (clearer == null) return;
    try {
      await clearer(deviceId: deviceId);
    } catch (_) {}
  }
}
