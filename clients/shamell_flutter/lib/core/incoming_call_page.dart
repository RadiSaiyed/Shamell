import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../main.dart' show LoginPage;
import 'design_tokens.dart';
import 'l10n.dart';
import 'call_signaling.dart';
import 'call_ice_config.dart';
import 'device_binding_guard.dart';
import 'device_binding_reauth.dart';
import 'livekit_call_service.dart';
import 'media_access_policy.dart';
import 'safe_set_state.dart';
import 'chat/chat_service.dart';
import 'chat/chat_models.dart' show ChatContact, ChatCallLogEntry;
import 'friend_annotations_store.dart';

/// Pick the label shown on the incoming-call screen before the async
/// resolver returns. Prefers the caller-volunteered `from_name` hint
/// (FCM `from_name` / WS `from_name`) when non-blank, otherwise falls
/// back to the raw `fromDeviceId` (still better than empty).
///
/// Exposed for direct unit testing — the in-widget call site is
/// `_IncomingCallPageState.initState`.
@visibleForTesting
String pickInitialCallerLabel({
  required String? hint,
  required String fromDeviceId,
}) {
  final trimmed = hint?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return fromDeviceId;
}

class IncomingCallPage extends StatefulWidget {
  final String baseUrl;
  final String callId;
  final String fromDeviceId;
  final String mode; // 'audio' | 'video'
  final bool autoStart;
  final VoidCallback? onCriticalSignalingSessionFailure;
  final Future<ChatContact> Function(String deviceId)? resolveCallerOverride;
  final Future<String?> Function()? loadDeviceIdOverride;
  final Future<bool> Function(String sdp, String deviceId)?
      processOfferOverride;
  final Future<void> Function(bool accepted)? logAndPopOverride;
  final Duration disconnectFailureDelay;

  /// Optional pre-resolved caller display name (e.g. the `from_name` we
  /// extracted from the FCM push payload). When present, the page shows
  /// this name immediately instead of flashing the raw `fromDeviceId`
  /// while the local contact/alias resolver runs. The async resolver
  /// still runs and can override this hint if it finds a more specific
  /// match (a friend alias, for instance).
  final String? initialCallerName;

  const IncomingCallPage({
    super.key,
    required this.baseUrl,
    required this.callId,
    required this.fromDeviceId,
    this.mode = 'video',
    this.autoStart = true,
    this.onCriticalSignalingSessionFailure,
    this.resolveCallerOverride,
    this.loadDeviceIdOverride,
    this.processOfferOverride,
    this.logAndPopOverride,
    this.disconnectFailureDelay = const Duration(seconds: 10),
    this.initialCallerName,
  });

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage>
    with SafeSetStateMixin<IncomingCallPage> {
  bool _active = true;
  bool _connected = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _disconnectFailureTimer;
  CallSignalingClient? _client;
  StreamSubscription<Map<String, dynamic>>? _sigSub;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _deviceId;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // LiveKit room state. The receiver side joins the same LiveKit room as
  // the caller (keyed by `widget.callId`) so media flows over LiveKit's
  // SFU rather than expecting a peer-to-peer SDP offer/ICE exchange. The
  // legacy WebRTC fields above stay around as a fallback path; in
  // practice, the LiveKit caller (`VoipCallPage`) never sends an offer,
  // so only this path is exercised today.
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  lk.VideoTrack? _lkLocalVideoTrack;
  lk.VideoTrack? _lkRemoteVideoTrack;
  bool _lkJoinAttempted = false;

  bool _accepted = false;
  bool _acceptRequested = false;
  bool _answerSent = false;
  bool _processingOffer = false;
  bool _signalingInitStarted = false;
  bool _transportFailureHandled = false;
  bool _blockedByMediaPolicy = false;
  String? _pendingOfferSdp;
  bool _muted = false;
  bool _videoEnabled = true;
  bool _speakerOn = false;
  bool _logged = false;
  bool _debugLocalMediaPresent = false;
  bool _debugRemoteMediaPresent = false;
  AudioSession? _audioSession;
  bool _audioSessionActive = false;
  String _callQualityLabel = 'Connecting';
  Color _callQualityColor = Colors.white70;
  String _callerName = '';
  int _callerResolveGeneration = 0;

  bool get _isVideoCall => widget.mode.toLowerCase() == 'video';

  @override
  void initState() {
    super.initState();
    _videoEnabled = _isVideoCall;
    _speakerOn = _isVideoCall;
    // Seed the visible caller label with the FCM-provided `from_name`
    // (when the caller volunteered one) so the screen never flashes the
    // raw deviceId. The local resolver runs in parallel and can still
    // upgrade this to a friend alias if the user assigned one.
    _callerName = pickInitialCallerLabel(
      hint: widget.initialCallerName,
      fromDeviceId: widget.fromDeviceId,
    );
    if (!shamellAllowsRealtimeCalls()) {
      _active = false;
      _blockedByMediaPolicy = true;
      return;
    }
    if (widget.autoStart) {
      _resolveCallerName();
      _initSignaling();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_active || !_connected) return;
      setState(() {
        _elapsed += const Duration(seconds: 1);
      });
    });
  }

  Future<bool> _initSignaling() async {
    if (_signalingInitStarted) {
      return _client != null &&
          _deviceId != null &&
          _deviceId!.trim().isNotEmpty;
    }
    _signalingInitStarted = true;
    var ready = false;
    try {
      // Voice-call audio profile — same shape as VoipCallPage so inbound and
      // outbound calls share routing behavior (Bluetooth auto-route,
      // earpiece by default for audio calls, ducks media, claims focus).
      await _activateVoiceCallAudioSession();
      try {
        final svc = ChatService(widget.baseUrl);
        try {
          await svc.ensureAccountChatReady();
        } finally {
          svc.close();
        }
      } catch (_) {
        // Incoming call signaling is device-scoped. Keep account bootstrap
        // best-effort so stale account-session state does not block the local
        // device from answering an otherwise valid call.
      }
      final devId = await (widget.loadDeviceIdOverride != null
          ? widget.loadDeviceIdOverride!()
          : CallSignalingClient.loadDeviceId(
              baseUrlOverride: widget.baseUrl,
            ));
      if (!mounted) return false;
      if (devId == null || devId.isEmpty) {
        return false;
      }
      _deviceId = devId;
      final client = CallSignalingClient(widget.baseUrl);
      final stream = client.connect(deviceId: devId);
      _client = client;
      _sigSub = stream.listen((msg) {
        unawaited(_onSignal(msg));
      });
      ready = true;
      if (_acceptRequested) {
        unawaited(_flushAcceptFlow());
      }
    } catch (_) {
      await _teardownCallResources();
      return false;
    } finally {
      if (!ready) {
        _signalingInitStarted = false;
      }
    }
    return ready;
  }

  Future<void> _resolveCallerName() async {
    final fromId = widget.fromDeviceId.trim();
    if (fromId.isEmpty) return;
    final generation = ++_callerResolveGeneration;
    if (widget.resolveCallerOverride != null) {
      try {
        final c = await widget.resolveCallerOverride!(fromId);
        final name = (c.name ?? '').trim();
        if (!mounted || generation != _callerResolveGeneration) return;
        setState(() {
          _callerName = name.isNotEmpty ? name : fromId;
        });
      } catch (e) {
        await _handleCriticalResolveFailure(e);
      }
      return;
    }
    final aliasFuture = _loadCachedCallerAlias(fromId);
    final contactFuture = _loadCachedCallerContactName(fromId);
    unawaited(
      contactFuture.then((label) {
        _applyCallerFallbackLabel(
          generation: generation,
          placeholder: fromId,
          label: label,
        );
      }),
    );

    final aliasLabel = await aliasFuture;
    if (aliasLabel.isNotEmpty) {
      _applyCallerLabel(generation: generation, label: aliasLabel);
      return;
    }

    final contactLabel = await contactFuture;
    if (contactLabel.isNotEmpty) {
      _applyCallerFallbackLabel(
        generation: generation,
        placeholder: fromId,
        label: contactLabel,
      );
      return;
    }

    String label = '';
    if (label.isEmpty) {
      try {
        ChatContact c;
        if (widget.resolveCallerOverride != null) {
          c = await widget.resolveCallerOverride!(fromId);
        } else {
          final svc = ChatService(widget.baseUrl);
          try {
            c = await svc.resolveDevice(fromId);
          } finally {
            svc.close();
          }
        }
        final name = (c.name ?? '').trim();
        if (name.isNotEmpty) label = name;
      } catch (e) {
        if (await _handleCriticalResolveFailure(e)) return;
      }
    }
    if (label.isEmpty) label = fromId;
    _applyCallerLabel(generation: generation, label: label);
  }

  Future<String> _loadCachedCallerAlias(String fromId) async {
    try {
      return (await loadFriendAliases(baseUrlOverride: widget.baseUrl))[fromId]
              ?.trim() ??
          '';
    } catch (_) {
      return '';
    }
  }

  Future<String> _loadCachedCallerContactName(String fromId) async {
    try {
      final contacts = await ChatLocalStore().loadContacts(
        baseUrlOverride: widget.baseUrl,
      );
      for (final c in contacts) {
        if (c.id.trim() != fromId) continue;
        final name = (c.name ?? '').trim();
        if (name.isNotEmpty) {
          return name;
        }
      }
    } catch (_) {}
    return '';
  }

  void _applyCallerLabel({
    required int generation,
    required String label,
  }) {
    final normalized = label.trim();
    if (!mounted ||
        generation != _callerResolveGeneration ||
        normalized.isEmpty ||
        normalized == _callerName) {
      return;
    }
    setState(() {
      _callerName = normalized;
    });
  }

  void _applyCallerFallbackLabel({
    required int generation,
    required String placeholder,
    required String label,
  }) {
    final normalized = label.trim();
    final current = _callerName.trim();
    if (!mounted ||
        generation != _callerResolveGeneration ||
        normalized.isEmpty ||
        (current.isNotEmpty && current != placeholder)) {
      return;
    }
    setState(() {
      _callerName = normalized;
    });
  }

  Future<bool> _handleCriticalResolveFailure(Object error) async {
    if (widget.onCriticalSignalingSessionFailure != null &&
        shamellIsCriticalAccountSessionError(error)) {
      widget.onCriticalSignalingSessionFailure!();
      return true;
    }
    return shamellForceReauthIfCriticalDeviceBindingDrift(
      context,
      error: error,
      loginPageBuilder: (_) => const LoginPage(),
    );
  }

  bool _isTerminalPeerConnectionState(RTCPeerConnectionState state) {
    return state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateClosed;
  }

  bool _isTerminalIceConnectionState(RTCIceConnectionState state) {
    return state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
        state == RTCIceConnectionState.RTCIceConnectionStateClosed;
  }

  bool _isDisconnectedPeerConnectionState(RTCPeerConnectionState state) {
    return state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected;
  }

  bool _isDisconnectedIceConnectionState(RTCIceConnectionState state) {
    return state == RTCIceConnectionState.RTCIceConnectionStateDisconnected;
  }

  void _clearDisconnectFailureTimer() {
    _disconnectFailureTimer?.cancel();
    _disconnectFailureTimer = null;
  }

  void _scheduleDisconnectFailureTimer() {
    if (_disconnectFailureTimer != null || !_active) return;
    final delay = widget.disconnectFailureDelay;
    if (delay <= Duration.zero) {
      unawaited(_handleAcceptedTransportFailure());
      return;
    }
    _disconnectFailureTimer = Timer(delay, () {
      _disconnectFailureTimer = null;
      unawaited(_handleAcceptedTransportFailure());
    });
  }

  bool get _hasRemoteMedia =>
      _debugRemoteMediaPresent ||
      (_remoteStream != null && _remoteRenderer.srcObject != null);

  Future<void> _clearRemoteMedia({bool clearStream = true}) async {
    _debugRemoteMediaPresent = false;
    if (clearStream) {
      _remoteStream = null;
    }
    try {
      _remoteRenderer.srcObject = null;
    } catch (_) {}
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleRemoteStreamRemoved(MediaStream stream) async {
    final current = _remoteStream;
    if (current == null || current.id == stream.id) {
      await _clearRemoteMedia();
    }
  }

  Future<void> _handleRemoteTrackRemoved(
    MediaStream stream,
    MediaStreamTrack track,
  ) async {
    final current = _remoteStream;
    if (current == null || current.id != stream.id) return;
    if (track.kind == 'video' || stream.getVideoTracks().isEmpty) {
      await _clearRemoteMedia(clearStream: stream.getTracks().isEmpty);
    }
  }

  Future<void> _handleAcceptedTransportFailure() async {
    if (_transportFailureHandled || !_active) return;
    if (!_accepted && !_connected && !_answerSent) return;
    _transportFailureHandled = true;
    _clearDisconnectFailureTimer();
    await _failClosedAcceptedCall();
  }

  Future<void> _handleSignalingChannelFailure() async {
    if (!_active) return;
    if (_accepted || _connected || _answerSent) {
      await _handleAcceptedTransportFailure();
      return;
    }
    await _teardownCallResources();
    if (mounted) {
      setState(() {
        _active = false;
      });
    } else {
      _active = false;
    }
  }

  Future<void> _handlePeerConnectionState(
    RTCPeerConnectionState state,
  ) async {
    if (_isTerminalPeerConnectionState(state)) {
      _setCallQuality('Connection failed', Colors.redAccent);
      await _handleAcceptedTransportFailure();
      return;
    }
    if (_isDisconnectedPeerConnectionState(state)) {
      _setCallQuality('Reconnecting', Colors.orangeAccent);
      _scheduleDisconnectFailureTimer();
      return;
    }
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _setCallQuality('Network good', Colors.lightGreenAccent);
    }
    _clearDisconnectFailureTimer();
  }

  Future<void> _handleIceConnectionState(
    RTCIceConnectionState state,
  ) async {
    if (_isTerminalIceConnectionState(state)) {
      _setCallQuality('Connection failed', Colors.redAccent);
      await _handleAcceptedTransportFailure();
      return;
    }
    if (_isDisconnectedIceConnectionState(state)) {
      _setCallQuality('Reconnecting', Colors.orangeAccent);
      _scheduleDisconnectFailureTimer();
      return;
    }
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _setCallQuality('Network good', Colors.lightGreenAccent);
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
      _setCallQuality('Checking network', Colors.white70);
    }
    _clearDisconnectFailureTimer();
  }

  void _setCallQuality(String label, Color color) {
    if (_callQualityLabel == label && _callQualityColor == color) return;
    _callQualityLabel = label;
    _callQualityColor = color;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleLocalTrackEnded(MediaStreamTrack track) async {
    final kind = (track.kind ?? '').toLowerCase();
    if (kind == 'video') {
      _debugLocalMediaPresent = false;
      _videoEnabled = false;
      try {
        _localRenderer.srcObject = null;
      } catch (_) {}
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (kind != 'audio') return;
    await _handleAcceptedTransportFailure();
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
    try {
      final pc = await createPeerConnection(shamellCallPeerConnectionConfig());
      final stream = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': _isVideoCall});
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      setState(() {
        _pc = pc;
        _localStream = stream;
      });
      try {
        Helper.setSpeakerphoneOn(_speakerOn);
      } catch (_) {}
      for (final track in stream.getTracks()) {
        track.onEnded = () {
          unawaited(_handleLocalTrackEnded(track));
        };
        await pc.addTrack(track, stream);
      }
      _debugLocalMediaPresent = false;
      _localRenderer.srcObject = stream;
      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          final remote = event.streams.first;
          _debugRemoteMediaPresent = false;
          setState(() {
            _remoteStream = remote;
          });
          _remoteRenderer.srcObject = remote;
        }
      };
      pc.onRemoveStream = (stream) {
        unawaited(_handleRemoteStreamRemoved(stream));
      };
      pc.onRemoveTrack = (stream, track) {
        unawaited(_handleRemoteTrackRemoved(stream, track));
      };
      pc.onConnectionState = (state) {
        unawaited(_handlePeerConnectionState(state));
      };
      pc.onIceConnectionState = (state) {
        unawaited(_handleIceConnectionState(state));
      };
      pc.onIceCandidate = (cand) {
        final client = _client;
        final devId = _deviceId;
        if (client == null ||
            devId == null ||
            devId.isEmpty ||
            cand.candidate == null) {
          return;
        }
        client.send({
          'type': 'ice_candidate',
          'call_id': widget.callId,
          'from': devId,
          'to': widget.fromDeviceId,
          'candidate': {
            'candidate': cand.candidate,
            'sdpMid': cand.sdpMid,
            'sdpMLineIndex': cand.sdpMLineIndex,
          },
        });
      };
    } catch (_) {
      // keep UI, but no media
    }
  }

  Future<bool> _handleCriticalSignalingSessionFailure(
    Map<String, dynamic> msg,
  ) async {
    if (!shamellCallSignalingEventRequiresReauth(msg)) return false;
    _sigSub?.cancel();
    _client?.close();
    if (widget.onCriticalSignalingSessionFailure != null) {
      widget.onCriticalSignalingSessionFailure!();
      return true;
    }
    return shamellForceReauthIfCriticalDeviceBindingDrift(
      context,
      error: (msg['detail'] ?? msg['reason'] ?? '').toString(),
      loginPageBuilder: (_) => const LoginPage(),
    );
  }

  Future<void> _onSignal(Map<String, dynamic> msg) async {
    if (!mounted) return;
    if (await _handleCriticalSignalingSessionFailure(msg)) return;
    final type = (msg['type'] ?? '').toString();
    if (type == 'closed' || type == 'error') {
      await _handleSignalingChannelFailure();
      return;
    }
    final callId = (msg['call_id'] ?? '').toString();
    if (callId != widget.callId) return;

    if (type == 'webrtc_offer') {
      final sdp = (msg['sdp'] ?? '').toString();
      if (sdp.isEmpty) return;
      _pendingOfferSdp = sdp;
      if (_acceptRequested) {
        await _flushAcceptFlow();
      }
    } else if (type == 'ice_candidate') {
      final cand = msg['candidate'];
      if (cand is Map<String, dynamic>) {
        final pc = _pc;
        if (pc != null) {
          final ice = RTCIceCandidate(
            cand['candidate']?.toString() ?? '',
            cand['sdpMid']?.toString(),
            int.tryParse(cand['sdpMLineIndex']?.toString() ?? '') ?? 0,
          );
          try {
            await pc.addCandidate(ice);
          } catch (_) {}
        }
      }
    } else if (type == 'hangup' || type == 'reject') {
      setState(() {
        _active = false;
      });
      await _endCall(notifyPeer: false);
    }
  }

  @visibleForTesting
  Future<void> debugHandleSignalingEvent(Map<String, dynamic> msg) async {
    await _onSignal(msg);
  }

  @visibleForTesting
  Future<void> debugResolveCallerName() async {
    await _resolveCallerName();
  }

  @visibleForTesting
  String get debugCallerName => _callerName;

  @visibleForTesting
  void debugAttachSignalingClient(
    CallSignalingClient client, {
    required String deviceId,
  }) {
    _client = client;
    _deviceId = deviceId;
  }

  @visibleForTesting
  Future<void> debugAcceptCall() async {
    await _acceptCall();
  }

  @visibleForTesting
  bool get debugAccepted => _accepted;

  @visibleForTesting
  bool get debugAnswerSent => _answerSent;

  @visibleForTesting
  bool get debugConnected => _connected;

  @visibleForTesting
  bool get debugActive => _active;

  @visibleForTesting
  bool get debugHasSignalingClient => _client != null;

  @visibleForTesting
  bool get debugHasRemoteMedia => _hasRemoteMedia;

  @visibleForTesting
  bool get debugHasLocalMedia =>
      _debugLocalMediaPresent ||
      (_localStream != null && _localRenderer.srcObject != null);

  @visibleForTesting
  void debugMarkRemoteMediaAttached() {
    _debugRemoteMediaPresent = true;
  }

  @visibleForTesting
  void debugMarkLocalMediaAttached() {
    _debugLocalMediaPresent = true;
  }

  @visibleForTesting
  Future<void> debugHandleRemoteStreamRemoved() async {
    await _clearRemoteMedia();
  }

  @visibleForTesting
  Future<void> debugHandleLocalTrackEnded(String kind) async {
    final track = _DebugMediaStreamTrack(kindValue: kind);
    await _handleLocalTrackEnded(track);
  }

  @visibleForTesting
  Future<void> debugHandlePeerConnectionState(
    RTCPeerConnectionState state,
  ) async {
    await _handlePeerConnectionState(state);
  }

  @visibleForTesting
  Future<void> debugHandleIceConnectionState(
    RTCIceConnectionState state,
  ) async {
    await _handleIceConnectionState(state);
  }

  Future<void> _teardownCallResources() async {
    _disconnectFailureTimer?.cancel();
    _disconnectFailureTimer = null;
    final sigSub = _sigSub;
    _sigSub = null;
    if (sigSub != null) {
      try {
        unawaited(sigSub.cancel());
      } catch (_) {}
    }
    final client = _client;
    _client = null;
    try {
      client?.close();
    } catch (_) {}
    _deviceId = null;
    _callQualityLabel = 'Connecting';
    _callQualityColor = Colors.white70;
    _debugLocalMediaPresent = false;
    _debugRemoteMediaPresent = false;
    try {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    } catch (_) {}
    try {
      _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    // LiveKit teardown: disconnect the room and drop the listener so the
    // SFU releases this participant's slot and stops billing/publishing.
    final lkRoom = _room;
    _room = null;
    final lkListener = _roomListener;
    _roomListener = null;
    _lkLocalVideoTrack = null;
    _lkRemoteVideoTrack = null;
    try {
      await lkListener?.dispose();
    } catch (_) {}
    try {
      await lkRoom?.disconnect();
    } catch (_) {}
    await _deactivateVoiceCallAudioSession();
  }

  Future<void> _activateVoiceCallAudioSession() async {
    if (_audioSessionActive) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        androidWillPauseWhenDucked: true,
      ));
      _audioSession = session;
      await session.setActive(true);
      _audioSessionActive = true;
      try {
        Helper.setSpeakerphoneOn(_speakerOn);
      } catch (_) {}
    } catch (_) {
      // Best-effort polish; on failure WebRTC falls back to system defaults.
    }
  }

  Future<void> _deactivateVoiceCallAudioSession() async {
    final session = _audioSession;
    _audioSession = null;
    _audioSessionActive = false;
    if (session == null) return;
    try {
      await session.setActive(false);
    } catch (_) {}
  }

  Future<void> _endCall({bool notifyPeer = true}) async {
    final accepted = _connected;
    final client = _client;
    final devId = _deviceId;
    if (notifyPeer && client != null && devId != null && devId.isNotEmpty) {
      try {
        await client.sendHangup(
          callId: widget.callId,
          fromDeviceId: devId,
          toDeviceId: widget.fromDeviceId,
        );
      } catch (_) {}
    }
    await _teardownCallResources();
    await _logAndPop(accepted: accepted, deviceId: devId);
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerOn = !_speakerOn;
    });
    try {
      Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disconnectFailureTimer?.cancel();
    _sigSub?.cancel();
    _client?.close();
    try {
      _localRenderer.dispose();
      _remoteRenderer.dispose();
    } catch (_) {}
    try {
      _localStream?.dispose();
    } catch (_) {}
    try {
      _pc?.close();
    } catch (_) {}
    // LiveKit cleanup — dispose() is the last-chance path (e.g. user
    // pops the page without explicitly hanging up). `_teardownCallResources`
    // already nulls these out in the normal flow, so the calls below
    // become no-ops in that case.
    final lkRoom = _room;
    final lkListener = _roomListener;
    _room = null;
    _roomListener = null;
    _lkLocalVideoTrack = null;
    _lkRemoteVideoTrack = null;
    if (lkListener != null) {
      unawaited(() async {
        try {
          await lkListener.dispose();
        } catch (_) {}
      }());
    }
    if (lkRoom != null) {
      unawaited(() async {
        try {
          await lkRoom.disconnect();
        } catch (_) {}
      }());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    if (_blockedByMediaPolicy) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                shamellRestrictedMediaMessage(
                  context,
                  camera: _isVideoCall,
                  microphone: true,
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final isVideoCall = _isVideoCall;
    final name = _callerName.trim().isNotEmpty
        ? _callerName.trim()
        : widget.fromDeviceId;
    final modeLabel = isVideoCall
        ? (l.isArabic ? 'مكالمة فيديو' : 'Video call')
        : (l.isArabic ? 'مكالمة صوتية' : 'Voice call');

    final statusText = !_active
        ? (l.isArabic ? 'انتهت المكالمة' : 'Call ended')
        : (_connected
            ? _fmt(_elapsed)
            : (_accepted
                ? (l.isArabic ? 'جارٍ الاتصال...' : 'Connecting…')
                : (isVideoCall
                    ? (l.isArabic
                        ? 'مكالمة فيديو واردة'
                        : 'Incoming video call')
                    : (l.isArabic
                        ? 'مكالمة صوتية واردة'
                        : 'Incoming voice call'))));

    // Prefer the LiveKit-published tracks (today's path) over the WebRTC
    // renderers (legacy fallback). For audio calls the renderer doesn't
    // matter — we render the avatar — so the booleans are only consulted
    // in the video-call branch below.
    final lkRemote = _lkRemoteVideoTrack;
    final lkLocal = _lkLocalVideoTrack;
    final hasRemote = lkRemote != null || _hasRemoteMedia;
    final hasLocal = lkLocal != null ||
        _debugLocalMediaPresent ||
        (_localStream != null && _localRenderer.srcObject != null);

    Widget remoteView;
    if (!isVideoCall) {
      remoteView = Container(
        color: Colors.black,
        child: Center(
          child: CircleAvatar(
            radius: 56,
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    } else if (lkRemote != null) {
      remoteView = lk.VideoTrackRenderer(lkRemote);
    } else if (hasRemote) {
      remoteView = RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    } else if (lkLocal != null) {
      remoteView = lk.VideoTrackRenderer(lkLocal);
    } else if (hasLocal) {
      remoteView = RTCVideoView(
        _localRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    } else {
      remoteView = Container(
        color: Colors.black,
        child: Center(
          child: CircleAvatar(
            radius: 48,
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    Widget localPreview = const SizedBox.shrink();
    if (isVideoCall && hasLocal && hasRemote) {
      // Local preview prefers the LiveKit track too — keeps the local
      // camera feed consistent with the remote rendering pipeline.
      final localChild = lkLocal != null
          ? lk.VideoTrackRenderer(lkLocal)
          : RTCVideoView(
              _localRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            );
      localPreview = Positioned(
        top: 16,
        right: 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 96,
            height: 144,
            color: Colors.black87,
            child: localChild,
          ),
        ),
      );
    }

    Widget controls;
    if (!_connected) {
      controls = Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: Icons.call_end,
            label: l.isArabic ? 'رفض' : 'Decline',
            background: Colors.redAccent,
            onTap: () {
              unawaited(_endCall());
            },
          ),
          _roundButton(
            icon: isVideoCall ? Icons.videocam : Icons.call,
            label: l.isArabic ? 'قبول' : 'Accept',
            background: Tokens.colorPayments,
            onTap: () {
              unawaited(_acceptCall());
            },
          ),
        ],
      );
    } else if (!isVideoCall) {
      controls = Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: _speakerOn ? Icons.volume_up : Icons.hearing,
            label: l.isArabic ? 'مكبر الصوت' : 'Speaker',
            onTap: _toggleSpeaker,
          ),
          _roundButton(
            icon: _muted ? Icons.mic_off : Icons.mic,
            label: l.isArabic ? 'ميكروفون' : 'Mute',
            onTap: _toggleMute,
          ),
          _roundButton(
            icon: Icons.call_end,
            label: l.isArabic ? 'إنهاء' : 'End',
            background: Colors.redAccent,
            onTap: () {
              unawaited(_endCall());
            },
          ),
        ],
      );
    } else {
      controls = Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: _muted ? Icons.mic_off : Icons.mic,
            label: l.isArabic ? 'ميكروفون' : 'Mute',
            onTap: _toggleMute,
          ),
          _roundButton(
            icon: _videoEnabled ? Icons.videocam : Icons.videocam_off,
            label: l.isArabic ? 'الكاميرا' : 'Video',
            onTap: _toggleVideo,
          ),
          _roundButton(
            icon: Icons.cameraswitch,
            label: l.isArabic ? 'تبديل' : 'Switch',
            onTap: _switchCamera,
          ),
          _roundButton(
            icon: Icons.call_end,
            label: l.isArabic ? 'إنهاء' : 'End',
            background: Colors.redAccent,
            onTap: () {
              unawaited(_endCall());
            },
          ),
        ],
      );
    }

    final body = Stack(
      children: [
        Positioned.fill(child: remoteView),
        if (isVideoCall && hasLocal && hasRemote) localPreview,
        Positioned(
          top: 24,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                modeLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                statusText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                _callQualityLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _callQualityColor,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: controls,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: body),
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _logAndPop({
    required bool accepted,
    String? deviceId,
  }) async {
    if (widget.logAndPopOverride != null) {
      await widget.logAndPopOverride!(accepted);
      return;
    }
    if (_logged) {
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    _logged = true;
    try {
      final store = ChatCallStore();
      final entry = ChatCallLogEntry(
        id: widget.callId,
        peerId: widget.fromDeviceId,
        ts: DateTime.now(),
        direction: 'in',
        kind: _isVideoCall ? 'video' : 'voice',
        accepted: accepted,
        duration: _elapsed,
      );
      await store.append(entry, baseUrlOverride: widget.baseUrl);
      final logDeviceId = (deviceId ?? _deviceId ?? '').trim();
      if (logDeviceId.isNotEmpty) {
        final svc = ChatService(widget.baseUrl);
        try {
          await svc.saveCallLog(deviceId: logDeviceId, entry: entry);
        } finally {
          svc.close();
        }
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _failClosedAcceptedCall() async {
    final client = _client;
    final devId = _deviceId;
    if (client != null && devId != null && devId.isNotEmpty) {
      try {
        await client.sendHangup(
          callId: widget.callId,
          fromDeviceId: devId,
          toDeviceId: widget.fromDeviceId,
        );
      } catch (_) {}
    }
    final sigSub = _sigSub;
    _sigSub = null;
    if (sigSub != null) {
      try {
        unawaited(sigSub.cancel());
      } catch (_) {}
    }
    final signalingClient = _client;
    _client = null;
    try {
      signalingClient?.close();
    } catch (_) {}
    _deviceId = null;
    _accepted = false;
    _acceptRequested = false;
    _answerSent = false;
    _processingOffer = false;
    _pendingOfferSdp = null;
    _connected = false;
    try {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    } catch (_) {}
    try {
      _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    if (mounted) {
      setState(() {
        _active = false;
      });
    } else {
      _active = false;
    }
  }

  Future<bool> _processOffer() async {
    final sdp = _pendingOfferSdp;
    final devId = _deviceId;
    if (sdp == null || sdp.isEmpty || devId == null || devId.isEmpty) {
      return false;
    }
    if (widget.processOfferOverride != null) {
      return widget.processOfferOverride!(sdp, devId);
    }
    await _ensurePeerConnection();
    final pc = _pc;
    if (pc == null) return false;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'),
      );
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final client = _client;
      var dispatched = false;
      if (client != null) {
        dispatched = await client.send({
          'type': 'webrtc_answer',
          'call_id': widget.callId,
          'from': devId,
          'to': widget.fromDeviceId,
          'sdp': answer.sdp,
          'sdp_type': answer.type,
        });
      }
      if (!dispatched) return false;
      setState(() {
        _connected = true;
      });
      return true;
    } catch (_) {}
    return false;
  }

  Future<void> _flushAcceptFlow() async {
    if (!_active || !_acceptRequested) return;
    final client = _client;
    final devId = _deviceId;
    if (!_answerSent && client != null && devId != null && devId.isNotEmpty) {
      final dispatched = await client.sendAnswer(
        callId: widget.callId,
        fromDeviceId: devId,
        toDeviceId: widget.fromDeviceId,
      );
      if (!dispatched) {
        if (mounted) {
          setState(() {
            _accepted = false;
            _acceptRequested = false;
          });
        } else {
          _accepted = false;
          _acceptRequested = false;
        }
        return;
      }
      _answerSent = true;
      // The LiveKit caller never sends an SDP offer — both sides join the
      // same room keyed by callId and the SFU handles media. Kick off the
      // receiver-side room join in the background; the WebRTC offer-path
      // below stays as a fallback for legacy callers that still send an
      // SDP offer (none today, but cheap to keep as a fail-soft path).
      unawaited(_joinLiveKitRoom());
    }
    if (!_processingOffer &&
        _pendingOfferSdp != null &&
        _pendingOfferSdp!.isNotEmpty) {
      _processingOffer = true;
      try {
        final processed = await _processOffer();
        if (!processed) {
          await _failClosedAcceptedCall();
        }
      } finally {
        _processingOffer = false;
      }
    }
  }

  /// Receiver-side LiveKit join. Mirrors `VoipCallPage._joinRoom`:
  ///   1. Ask the BFF for a fresh per-room JWT (`POST /calls/livekit/token`)
  ///   2. Connect to the LiveKit room URL with that token
  ///   3. Publish mic (+ camera for video calls) — the caller is already
  ///      in the room and will see us as a new participant.
  ///
  /// Idempotent — guarded by `_lkJoinAttempted` so re-emitting `sendAnswer`
  /// (e.g. on signaling-channel reconnect) never spins up a second room.
  Future<void> _joinLiveKitRoom() async {
    if (_lkJoinAttempted) return;
    _lkJoinAttempted = true;
    final devId = _deviceId;
    try {
      final tokenInfo = await LiveKitCallService(widget.baseUrl).requestToken(
        callId: widget.callId,
        mode: widget.mode,
        chatDeviceId: devId,
      );
      if (!mounted) return;
      final room = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );
      _room = room;
      final listener = room.createListener();
      _roomListener = listener;
      listener
        ..on<lk.RoomConnectedEvent>((_) => _onLiveKitConnected(room))
        ..on<lk.RoomDisconnectedEvent>((event) {
          _onLiveKitDisconnected(event.reason?.toString() ?? 'closed');
        })
        ..on<lk.TrackSubscribedEvent>((event) {
          final track = event.track;
          if (track is lk.VideoTrack && mounted) {
            setState(() => _lkRemoteVideoTrack = track);
          }
        })
        ..on<lk.TrackUnsubscribedEvent>((event) {
          if (mounted && _lkRemoteVideoTrack == event.track) {
            setState(() => _lkRemoteVideoTrack = null);
          }
        });
      await room.connect(tokenInfo.url, tokenInfo.token);
    } catch (_) {
      // LiveKit join failed — leave the WebRTC fallback path armed so a
      // legacy peer-to-peer offer can still complete the call. Reset the
      // guard so a manual re-accept attempt can retry.
      _lkJoinAttempted = false;
    }
  }

  Future<void> _onLiveKitConnected(lk.Room room) async {
    if (!mounted) return;
    setState(() {
      _connected = true;
    });
    // `_setCallQuality` runs its own `setState` and is idempotent — pulling
    // it out of the block above keeps each setState scope single-purpose.
    _setCallQuality('Network good', Colors.lightGreenAccent);
    try {
      await room.localParticipant?.setMicrophoneEnabled(!_muted);
      if (_isVideoCall) {
        await room.localParticipant?.setCameraEnabled(_videoEnabled);
        final track = room.localParticipant?.videoTrackPublications
            .firstWhere((pub) => pub.track is lk.LocalVideoTrack)
            .track;
        if (track is lk.VideoTrack && mounted) {
          setState(() => _lkLocalVideoTrack = track);
        }
      }
    } catch (_) {
      // Mic/camera permission denied — call still proceeds, just one-way.
    }
  }

  void _onLiveKitDisconnected(String reason) {
    if (!mounted) return;
    setState(() {
      _lkRemoteVideoTrack = null;
      _lkLocalVideoTrack = null;
    });
    // Reuse the existing transport-failure handler so the user-visible
    // "Connection failed / call ended" path matches the WebRTC fallback.
    unawaited(_handleAcceptedTransportFailure());
  }

  Future<void> _acceptCall() async {
    if (!_active || _connected) return;
    setState(() {
      _accepted = true;
      _acceptRequested = true;
    });
    if (_client == null || _deviceId == null || _deviceId!.isEmpty) {
      final ready = await _initSignaling();
      if (!ready ||
          _client == null ||
          _deviceId == null ||
          _deviceId!.isEmpty) {
        if (mounted) {
          setState(() {
            _accepted = false;
            _acceptRequested = false;
          });
        } else {
          _accepted = false;
          _acceptRequested = false;
        }
        return;
      }
    }
    await _flushAcceptFlow();
  }

  Widget _roundButton({
    required IconData icon,
    required String label,
    Color? background,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final bg = background ?? theme.colorScheme.surface.withValues(alpha: .80);
    final fg = background != null ? Colors.white : theme.colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fg),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .85),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _toggleMute() {
    final stream = _localStream;
    final room = _room;
    if (stream == null && room == null) return;
    setState(() {
      _muted = !_muted;
    });
    // WebRTC fallback path
    if (stream != null) {
      for (final t in stream.getAudioTracks()) {
        t.enabled = !_muted;
      }
    }
    // LiveKit path — toggles the publishing state on the SFU
    if (room != null) {
      unawaited(() async {
        try {
          await room.localParticipant?.setMicrophoneEnabled(!_muted);
        } catch (_) {}
      }());
    }
  }

  void _toggleVideo() {
    if (!_isVideoCall) return;
    final stream = _localStream;
    final room = _room;
    if (stream == null && room == null) return;
    setState(() {
      _videoEnabled = !_videoEnabled;
    });
    if (stream != null) {
      for (final t in stream.getVideoTracks()) {
        t.enabled = _videoEnabled;
      }
    }
    if (room != null) {
      unawaited(() async {
        try {
          await room.localParticipant?.setCameraEnabled(_videoEnabled);
        } catch (_) {}
      }());
    }
  }

  void _switchCamera() {
    if (!_isVideoCall) return;
    final stream = _localStream;
    if (stream == null) return;
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) return;
    Helper.switchCamera(tracks.first);
  }
}

class _DebugMediaStreamTrack extends MediaStreamTrack {
  _DebugMediaStreamTrack({required this.kindValue});

  final String kindValue;
  bool _enabled = true;

  @override
  String? get id => 'debug-$kindValue-track';

  @override
  String? get label => 'debug-$kindValue';

  @override
  String? get kind => kindValue;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool b) {
    _enabled = b;
  }

  @override
  bool? get muted => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
