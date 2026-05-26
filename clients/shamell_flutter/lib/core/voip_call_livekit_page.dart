import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'app_sounds.dart';
import 'call_signaling.dart';
import 'chat/chat_service.dart' show ChatLocalStore;
import 'l10n.dart';
import 'livekit_call_service.dart';
import 'media_access_policy.dart';
import 'safe_set_state.dart';

/// LiveKit-backed voice/video call page.
///
/// Replaces the manual `RTCPeerConnection`/SDP/ICE flow with a LiveKit room
/// join: the BFF issues a short-lived JWT (`POST /calls/livekit/token`), the
/// client passes that to `Room.connect(...)`, and the LiveKit server handles
/// media, TURN, simulcast, and group fan-out.
///
/// Ringing semantics still ride on top of the existing
/// `/ws/call/signaling` WebSocket so the callee sees an inbound-call UI
/// before joining the room.
class VoipCallPage extends StatefulWidget {
  final String baseUrl;
  final String peerId;
  final String? displayName;
  final String mode; // 'audio' | 'video'
  final bool autoStart;
  final VoidCallback? onCriticalSignalingSessionFailure;
  final String? callIdOverride;
  /// `true` when this page is opened from the caller side (outgoing call).
  /// Drives the local ringback ("tut-tut") that plays from page open until
  /// the peer joins the room. Callee opens this page via the incoming-call
  /// accept flow, where the callee-side native ringtone already played in
  /// the incoming banner — they pass `false` (the default).
  final bool isCaller;

  const VoipCallPage({
    super.key,
    required this.baseUrl,
    required this.peerId,
    this.displayName,
    this.mode = 'video',
    this.autoStart = true,
    this.onCriticalSignalingSessionFailure,
    this.callIdOverride,
    this.isCaller = false,
  });

  @override
  State<VoipCallPage> createState() => _VoipCallPageState();
}

class _VoipCallPageState extends State<VoipCallPage>
    with SafeSetStateMixin<VoipCallPage> {
  bool _active = true;
  bool _blockedByMediaPolicy = false;
  bool _connected = false;
  bool _muted = false;
  bool _videoEnabled = true;
  bool _hadConnection = false;
  // Speaker defaults to ON for video calls (hands-free + visible peer) and
  // OFF for audio calls (held-to-ear like a phone call). Toggled by the user
  // via the on-call button row.
  bool _speakerOn = false;
  String _callId = '';
  String? _deviceId;
  String _statusLabel = 'Initializing';
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  CallSignalingClient? _sigClient;
  StreamSubscription<Map<String, dynamic>>? _sigSub;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  lk.VideoTrack? _remoteVideoTrack;
  lk.VideoTrack? _localVideoTrack;
  AudioSession? _audioSession;
  bool _audioSessionActive = false;

  bool get _isVideoCall => widget.mode.toLowerCase() == 'video';

  @override
  void initState() {
    super.initState();
    _videoEnabled = _isVideoCall;
    _speakerOn = _isVideoCall;
    _callId = widget.callIdOverride?.trim() ??
        'call_${DateTime.now().millisecondsSinceEpoch}';
    if (!shamellAllowsRealtimeCalls()) {
      _active = false;
      _blockedByMediaPolicy = true;
      _statusLabel = 'Calls disabled on this surface';
      return;
    }
    if (widget.autoStart) {
      unawaited(_bootstrap());
    }
    // Caller-side ringback: play immediately on page open so the caller
    // hears the dial tone while the room is being set up + peer is
    // ringing. Stopped on ParticipantConnectedEvent (peer joined) or in
    // _cleanup (call ended / failed).
    if (widget.isCaller) {
      unawaited(ShamellCallRingback.start());
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connected && _active && mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() => _statusLabel = 'Authenticating');
    _deviceId = await CallSignalingClient.loadDeviceId(
      baseUrlOverride: widget.baseUrl,
    );
    if (_deviceId == null || _deviceId!.isEmpty) {
      _failed('No device session');
      return;
    }
    // Configure voice-call audio profile before media is published:
    //   - Android: usage=voiceCommunication + contentType=speech → audio
    //     routes to earpiece by default, Bluetooth headset auto-routes when
    //     connected, and the ringer/media stream is ducked.
    //   - Audio focus = transient-exclusive so background music pauses for
    //     the call duration and resumes on hangup.
    await _activateVoiceCallAudioSession();
    await _attachSignaling();
    if (!mounted) return;
    setState(() {
      _statusLabel = 'Connecting…';
    });
    // Wait for the WebSocket handshake to complete before firing the
    // invite. Without this gate `sendInvite` races the still-opening
    // socket and `_ws` is null → returns false → "Invite failed"
    // shown to the user (the bug field-reported on real-device QA).
    //
    // 6-second budget is generous: WS handshake on a modern uplink
    // averages 80-300 ms; values above 2 s indicate a deeper network
    // issue and bailing early gives a faster failure UX than the old
    // silent fail did.
    final wsReady =
        await _sigClient?.awaitReady(timeout: const Duration(seconds: 6)) ??
            false;
    if (!mounted) return;
    if (!wsReady) {
      _failed('Signaling unavailable');
      return;
    }
    setState(() {
      _statusLabel = 'Ringing ${widget.peerId}';
    });
    // Caller-side: invite, then join the room. The callee sees the invite
    // on its CallSignalingClient stream (or via FCM) and runs the same
    // _joinRoom() flow with its own token.
    //
    // We attach our own display name so the BFF can forward it as
    // `from_name` to chat_service's push-notify payload — receivers then
    // surface "Anna is calling…" on the lockscreen ringer even when the
    // caller is not in their local contact cache.
    final myDisplayName = await _loadMyDisplayName();
    if (await _sigClient?.sendInvite(
          callId: _callId,
          fromDeviceId: _deviceId!,
          toDeviceId: widget.peerId,
          mode: widget.mode,
          fromName: myDisplayName,
        ) ==
        false) {
      _failed('Invite failed');
      return;
    }
    await _joinRoom();
  }

  Future<String?> _loadMyDisplayName() async {
    try {
      final me = await ChatLocalStore().loadIdentity(
        baseUrlOverride: widget.baseUrl,
      );
      final name = me?.displayName?.trim();
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
    return null;
  }

  Future<void> _attachSignaling() async {
    final client = CallSignalingClient(widget.baseUrl);
    _sigClient = client;
    final stream = client.connect(deviceId: _deviceId!);
    _sigSub = stream.listen(_handleSignalingEvent);
  }

  void _handleSignalingEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = (event['type'] ?? '').toString().toLowerCase();
    switch (type) {
      case 'answer':
        // Peer accepted; LiveKit will fire ParticipantConnectedEvent.
        setState(() {
          _statusLabel = 'Peer accepted, connecting media';
        });
        break;
      case 'hangup':
        unawaited(_hangup(emitSignal: false));
        break;
      case 'error':
      case 'closed':
        if (shamellCallSignalingEventRequiresReauth(event)) {
          widget.onCriticalSignalingSessionFailure?.call();
        }
        break;
    }
  }

  Future<void> _joinRoom() async {
    if (!mounted) return;
    setState(() => _statusLabel = 'Fetching token');
    try {
      final tokenInfo = await LiveKitCallService(widget.baseUrl).requestToken(
        callId: _callId,
        mode: widget.mode,
        chatDeviceId: _deviceId,
      );
      if (!mounted) return;
      setState(() => _statusLabel = 'Connecting to room');

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
        ..on<lk.RoomConnectedEvent>((_) => _onRoomConnected(room))
        ..on<lk.RoomDisconnectedEvent>((event) {
          _onRoomDisconnected(event.reason?.toString() ?? 'closed');
        })
        ..on<lk.ParticipantConnectedEvent>((event) {
          // Peer joined → stop caller-side ringback. No-op for callee.
          unawaited(ShamellCallRingback.stop());
          if (mounted) {
            setState(() {
              _statusLabel = '${event.participant.identity} joined';
            });
          }
        })
        ..on<lk.ParticipantDisconnectedEvent>((_) {
          if (mounted) {
            setState(() => _statusLabel = 'Peer left');
          }
        })
        ..on<lk.TrackSubscribedEvent>((event) {
          final track = event.track;
          if (track is lk.VideoTrack && mounted) {
            setState(() => _remoteVideoTrack = track);
          }
        })
        ..on<lk.TrackUnsubscribedEvent>((event) {
          if (mounted && _remoteVideoTrack == event.track) {
            setState(() => _remoteVideoTrack = null);
          }
        });

      await room.connect(tokenInfo.url, tokenInfo.token);
    } catch (error) {
      _failed('Connect failed: $error');
    }
  }

  Future<void> _onRoomConnected(lk.Room room) async {
    if (!mounted) return;
    setState(() {
      _connected = true;
      _hadConnection = true;
      _statusLabel = 'Connected';
    });
    // Publish local mic + (optionally) camera.
    try {
      await room.localParticipant?.setMicrophoneEnabled(!_muted);
      if (_isVideoCall) {
        await room.localParticipant?.setCameraEnabled(_videoEnabled);
        // Latch the local video track for the picture-in-picture preview.
        final track = room.localParticipant?.videoTrackPublications
            .firstWhere((pub) => pub.track is lk.LocalVideoTrack)
            .track;
        if (track is lk.VideoTrack && mounted) {
          setState(() => _localVideoTrack = track);
        }
      }
    } catch (_) {
      // Microphone/camera permissions are surfaced via OS dialogs; if denied
      // the user still has the call but won't transmit.
    }
  }

  void _onRoomDisconnected(String reason) {
    if (!mounted) return;
    setState(() {
      _connected = false;
      _statusLabel = _hadConnection ? 'Call ended' : 'Failed: $reason';
    });
    unawaited(_cleanup());
  }

  void _failed(String reason) {
    if (!mounted) return;
    setState(() {
      _statusLabel = 'Failed: $reason';
      _active = false;
    });
    unawaited(_cleanup());
  }

  Future<void> _cleanup() async {
    // Stop ringback first so it doesn't keep tooting while the user
    // sees a "Call ended" surface.
    try {
      await ShamellCallRingback.stop();
    } catch (_) {}
    final room = _room;
    _room = null;
    final listener = _roomListener;
    _roomListener = null;
    try {
      await listener?.dispose();
    } catch (_) {}
    try {
      await room?.disconnect();
    } catch (_) {}
    try {
      await _sigSub?.cancel();
    } catch (_) {}
    _sigClient?.close();
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
      // Apply the initial speaker preference (on for video, off for audio
      // calls) so the user lands on the expected output device before any
      // media frames flow.
      try {
        await webrtc.Helper.setSpeakerphoneOn(_speakerOn);
      } catch (_) {}
    } catch (_) {
      // Audio session is a best-effort polish; failure here must not break
      // the call. LiveKit will fall back to system-default routing.
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

  Future<void> _toggleMute() async {
    final room = _room;
    if (room == null) return;
    final next = !_muted;
    try {
      await room.localParticipant?.setMicrophoneEnabled(!next);
    } catch (_) {}
    if (mounted) setState(() => _muted = next);
  }

  /// Toggle the call's audio output between the device's earpiece (loud
  /// speaker off, phone-style) and the loudspeaker (hands-free). Goes
  /// through flutter_webrtc's helper because LiveKit delegates audio routing
  /// to the underlying WebRTC engine on Android; the audio_session config
  /// set up in [_activateVoiceCallAudioSession] is the higher-level policy,
  /// and this toggle is the user-controlled override on top.
  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await webrtc.Helper.setSpeakerphoneOn(next);
    } catch (_) {}
    if (mounted) setState(() => _speakerOn = next);
  }

  Future<void> _toggleVideo() async {
    if (!_isVideoCall) return;
    final room = _room;
    if (room == null) return;
    final next = !_videoEnabled;
    try {
      await room.localParticipant?.setCameraEnabled(next);
    } catch (_) {}
    if (mounted) setState(() => _videoEnabled = next);
  }

  Future<void> _hangup({bool emitSignal = true}) async {
    if (emitSignal && _deviceId != null) {
      try {
        await _sigClient?.sendHangup(
          callId: _callId,
          fromDeviceId: _deviceId!,
          toDeviceId: widget.peerId,
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _connected = false;
        _active = false;
        _statusLabel = 'Call ended';
      });
    }
    await _cleanup();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_cleanup());
    super.dispose();
  }

  String _formatElapsed() {
    final s = _elapsed.inSeconds;
    final m = s ~/ 60;
    final ss = s % 60;
    return '${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final localTrack = _localVideoTrack;
    final remoteTrack = _remoteVideoTrack;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: remoteTrack != null
                  ? lk.VideoTrackRenderer(remoteTrack)
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircleAvatar(
                            radius: 56,
                            child: Icon(Icons.person, size: 56),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            widget.displayName?.trim().isNotEmpty == true
                                ? widget.displayName!
                                : widget.peerId,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _connected ? _formatElapsed() : _statusLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            if (_isVideoCall && localTrack != null && _videoEnabled)
              Positioned(
                top: 16,
                right: 16,
                width: 120,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: lk.VideoTrackRenderer(localTrack),
                ),
              ),
            if (_blockedByMediaPolicy)
              Center(
                child: Text(
                  l.isArabic
                      ? 'المكالمات معطلة في هذا الإصدار.'
                      : 'Calls are disabled in this build.',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    tooltip: _muted ? 'Unmute' : 'Mute',
                    onTap: _connected ? _toggleMute : null,
                    backgroundColor: _muted ? Colors.red.shade700 : null,
                  ),
                  _CallButton(
                    icon: _speakerOn
                        ? Icons.volume_up
                        : Icons.phone_in_talk_outlined,
                    tooltip: _speakerOn ? 'Earpiece' : 'Speaker',
                    onTap: _connected ? _toggleSpeaker : null,
                    backgroundColor:
                        _speakerOn ? Colors.green.shade700 : null,
                  ),
                  if (_isVideoCall)
                    _CallButton(
                      icon:
                          _videoEnabled ? Icons.videocam : Icons.videocam_off,
                      tooltip: _videoEnabled ? 'Stop video' : 'Start video',
                      onTap: _connected ? _toggleVideo : null,
                      backgroundColor:
                          !_videoEnabled ? Colors.red.shade700 : null,
                    ),
                  _CallButton(
                    icon: Icons.call_end,
                    tooltip: 'Hang up',
                    onTap: _active ? () => _hangup() : null,
                    backgroundColor: Colors.red.shade700,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const _CallButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ??
            (disabled ? Colors.grey.shade800 : Colors.grey.shade700),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Icon(
              icon,
              size: 28,
              color: disabled ? Colors.white38 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
