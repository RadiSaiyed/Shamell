import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the native `IncomingCallRingerService` (Android only).
///
/// The native service owns:
///  - the looped `MediaPlayer` ringtone playback under doze / app-backgrounded
///    conditions (foreground-service-with-`phoneCall` type),
///  - the +30 s missed-call fallback notification, fired automatically when no
///    explicit `stop(...)` arrives in time (user neither accepted nor
///    declined, e.g. they walked away from the phone).
///
/// From the Flutter side we just signal lifecycle:
///  - [start] when the ringer banner appears (with the resolved caller name
///    so the missed-call follow-up notification can use the same label),
///  - [stop] with a [StopReason] when the user accepts, declines, or the
///    server cancels the call (suppresses missed-call), or with [StopReason.external]
///    when the cancel comes from another in-app path.
///
/// On non-Android platforms these methods are no-ops so the call sites in
/// shared code can stay unconditional.
class IncomingCallRinger {
  IncomingCallRinger._();

  static const MethodChannel _channel =
      MethodChannel('shamell/incoming_call_ringer');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Start the looped ringtone + arm the missed-call fallback timer.
  ///
  /// [callerLabel] is the resolved display name from the caller-name lookup
  /// chain (friend alias → contact name → fallback). It's reused as the
  /// title of the missed-call follow-up if the call isn't answered.
  /// [mode] should be `'audio'` or `'video'`.
  static Future<void> start({
    required String callerLabel,
    required String mode,
    String callerSubtitle = '',
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('start', <String, dynamic>{
        'caller_label': callerLabel,
        'caller_subtitle': callerSubtitle,
        'mode': mode,
      });
    } catch (_) {
      // Failure to start the ringer must not block the rest of the
      // incoming-call surface (banner, vibration, navigation). The user
      // still sees and feels the notification.
    }
  }

  /// Stop the looped ringtone and release the foreground service. [reason]
  /// suppresses the missed-call follow-up notification when the user
  /// actively answered (accept / decline). Safe to call even if the service
  /// was never started.
  static Future<void> stop({StopReason reason = StopReason.external}) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stop', <String, dynamic>{
        'reason': reason.wireValue,
      });
    } catch (_) {}
  }
}

/// Why the ringer is being stopped. Affects whether the +30 s missed-call
/// follow-up notification fires (it doesn't, for [accept] / [decline] —
/// those are user-driven answers and a missed-call surface would be wrong).
enum StopReason {
  accept('accept'),
  decline('decline'),
  external('external');

  const StopReason(this.wireValue);
  final String wireValue;
}
