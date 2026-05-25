import 'package:flutter/foundation.dart';

enum NotificationTapTargetKind {
  sync,
  chat,
  paymentRequest,
  wallet,
  ride,
  incomingCall,
}

@immutable
class IncomingCallTap {
  const IncomingCallTap({
    required this.callId,
    required this.fromDeviceId,
    required this.mode,
  });

  final String callId;
  final String fromDeviceId;
  final String mode; // 'audio' or 'video'
}

@immutable
class NotificationTapTarget {
  const NotificationTapTarget._(this.kind, [this.id, this.call]);

  const NotificationTapTarget.sync() : this._(NotificationTapTargetKind.sync);
  const NotificationTapTarget.chat() : this._(NotificationTapTargetKind.chat);
  const NotificationTapTarget.paymentRequest(String id)
      : this._(NotificationTapTargetKind.paymentRequest, id);
  const NotificationTapTarget.wallet(String id)
      : this._(NotificationTapTargetKind.wallet, id);
  const NotificationTapTarget.ride(String id)
      : this._(NotificationTapTargetKind.ride, id);
  const NotificationTapTarget.incomingCall(IncomingCallTap call)
      : this._(NotificationTapTargetKind.incomingCall, null, call);

  final NotificationTapTargetKind kind;
  final String? id;
  final IncomingCallTap? call;
}

const int _notificationPayloadMaxLen = 240;
const String _notificationChatRootPayload = 'shamell://chat';
final RegExp _notificationPayloadIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,128}$');

String? _notificationPayloadToken(String raw, String prefix) {
  if (!raw.startsWith(prefix)) return null;
  final token = raw.substring(prefix.length).trim();
  if (!_notificationPayloadIdPattern.hasMatch(token)) return null;
  return token;
}

IncomingCallTap? _parseIncomingCallPayload(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'shamell') return null;
  if (uri.host.toLowerCase() != 'call') return null;
  if (uri.userInfo.isNotEmpty || uri.hasPort) return null;
  if (uri.pathSegments.isEmpty) return null;
  final mode = uri.pathSegments.first.toLowerCase();
  if (mode != 'audio' && mode != 'video') return null;
  final callId = (uri.queryParameters['id'] ?? '').trim();
  final fromDeviceId = (uri.queryParameters['from'] ?? '').trim();
  if (!_notificationPayloadIdPattern.hasMatch(callId)) return null;
  if (!_notificationPayloadIdPattern.hasMatch(fromDeviceId)) return null;
  return IncomingCallTap(
    callId: callId,
    fromDeviceId: fromDeviceId,
    mode: mode,
  );
}

String? canonicalizePendingNotificationPayload(String payload) {
  final raw = payload.trim();
  if (raw.isEmpty || raw.length > _notificationPayloadMaxLen) {
    return null;
  }
  if (raw == 'sync') return raw;
  if (_notificationPayloadToken(raw, 'req:') != null) return raw;
  if (_notificationPayloadToken(raw, 'wallet:') != null) return raw;
  if (_notificationPayloadToken(raw, 'ride:') != null) return raw;
  if (_parseIncomingCallPayload(raw) != null) return raw;

  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'shamell') return null;
  if (uri.host.toLowerCase() != 'chat') return null;
  if (uri.userInfo.isNotEmpty || uri.hasPort) return null;
  return _notificationChatRootPayload;
}

String? payloadForNotificationTapTarget(NotificationTapTarget? tapTarget) {
  if (tapTarget == null) return null;
  final raw = switch (tapTarget.kind) {
    NotificationTapTargetKind.sync => 'sync',
    NotificationTapTargetKind.chat => _notificationChatRootPayload,
    NotificationTapTargetKind.paymentRequest =>
      'req:${(tapTarget.id ?? '').trim()}',
    NotificationTapTargetKind.wallet => 'wallet:${(tapTarget.id ?? '').trim()}',
    NotificationTapTargetKind.ride => 'ride:${(tapTarget.id ?? '').trim()}',
    NotificationTapTargetKind.incomingCall =>
      _formatIncomingCallPayload(tapTarget.call),
  };
  final canonical = canonicalizePendingNotificationPayload(raw);
  if (canonical != raw) return null;
  return canonical;
}

String _formatIncomingCallPayload(IncomingCallTap? call) {
  if (call == null) return '';
  return 'shamell://call/${call.mode}?id=${call.callId}&from=${call.fromDeviceId}';
}

NotificationTapTarget? parseNotificationTapTargetPayload(String? payload) {
  final canonical = canonicalizePendingNotificationPayload(payload ?? '');
  if (canonical == null) return null;
  switch (canonical) {
    case 'sync':
      return const NotificationTapTarget.sync();
    case _notificationChatRootPayload:
      return const NotificationTapTarget.chat();
    default:
      if (canonical.startsWith('req:')) {
        return NotificationTapTarget.paymentRequest(canonical.substring(4));
      }
      if (canonical.startsWith('wallet:')) {
        return NotificationTapTarget.wallet(canonical.substring(7));
      }
      if (canonical.startsWith('ride:')) {
        return NotificationTapTarget.ride(canonical.substring(5));
      }
      final call = _parseIncomingCallPayload(canonical);
      if (call != null) return NotificationTapTarget.incomingCall(call);
      return null;
  }
}
