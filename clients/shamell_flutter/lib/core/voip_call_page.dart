import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'l10n.dart';
import 'call_signaling.dart';
import 'chat/chat_service.dart';
import 'chat/chat_models.dart' show ChatCallLogEntry, generateShortId;

class VoipCallPage extends StatefulWidget {
  final String baseUrl;
  final String peerId;
  final String? displayName;
  final String mode; // 'audio' | 'video'

  const VoipCallPage({
    super.key,
    required this.baseUrl,
    required this.peerId,
    this.displayName,
    this.mode = 'video',
  });

  @override
  State<VoipCallPage> createState() => _VoipCallPageState();
}

class _VoipCallPageState extends State<VoipCallPage> {
  bool _active = true;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  bool _ringing = false;
  bool _connected = false;
  String _callId = '';
  String? _deviceId;
  CallSignalingClient? _client;
  StreamSubscription<Map<String, dynamic>>? _sigSub;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _muted = false;
  bool _videoEnabled = true;
  bool _speakerOn = false;
  bool _logged = false;

  bool get _isVideoCall => widget.mode.toLowerCase() == 'video';

  @override
  void initState() {
    super.initState();
    _callId = 'call_${generateShortId(length: 10)}';
    _videoEnabled = _isVideoCall;
    _speakerOn = _isVideoCall;
    _initSignaling();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_active) return;
      setState(() {
        _elapsed += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _initSignaling() async {
    try {
      final devId = await CallSignalingClient.loadDeviceId();
      if (!mounted) return;
      if (devId == null || devId.isEmpty) {
        // No Mirsaal identity yet; keep call UI local-only.
        return;
      }
      _deviceId = devId;
      final client = CallSignalingClient(widget.baseUrl);
      final stream = client.connect(deviceId: devId);
      _client = client;
      _sigSub = stream.listen(_handleSignal);
      await _initWebRtc(devId);
      await client.sendInvite(
        callId: _callId,
        fromDeviceId: devId,
        toDeviceId: widget.peerId,
        mode: widget.mode,
      );
    } catch (_) {
      // Best-effort; fallback to local-only timer UI.
    }
  }

  void _handleSignal(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = (msg['type'] ?? '').toString();
    final callId = (msg['call_id'] ?? '').toString();
    if (callId.isEmpty || callId != _callId) return;
    if (type == 'ringing') {
      setState(() {
        _ringing = true;
      });
    } else if (type == 'answer') {
      setState(() {
        _connected = true;
      });
    } else if (type == 'hangup' || type == 'reject') {
      setState(() {
        _active = false;
      });
    } else if (type == 'webrtc_answer') {
      final sdp = (msg['sdp'] ?? '').toString();
      final pc = _pc;
      if (pc != null && sdp.isNotEmpty) {
        final desc = RTCSessionDescription(sdp, 'answer');
        pc.setRemoteDescription(desc);
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
          pc.addCandidate(ice);
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    super.dispose();
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerOn = !_speakerOn;
    });
    try {
      Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
  }

  void _hangup() {
    setState(() {
      _active = false;
    });
    final client = _client;
    final devId = _deviceId;
    if (client != null && devId != null && devId.isNotEmpty) {
      // Best-effort hangup; ignore failures.
      client
          .sendHangup(callId: _callId, fromDeviceId: devId)
          .catchError((_) {});
    }
    _logCallAndPop(accepted: _connected);
  }

  Future<void> _logCallAndPop({required bool accepted}) async {
    if (_logged) {
      Navigator.of(context).pop();
      return;
    }
    _logged = true;
    try {
      final store = ChatCallStore();
      final entry = ChatCallLogEntry(
        id: _callId,
        peerId: widget.peerId,
        ts: DateTime.now(),
        direction: 'out',
        kind: _isVideoCall ? 'video' : 'voice',
        accepted: accepted,
        duration: _elapsed,
      );
      await store.append(entry);
    } catch (_) {}
    Navigator.of(context).pop();
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final name = (widget.displayName != null && widget.displayName!.isNotEmpty)
        ? widget.displayName!
        : widget.peerId;
    final isVideoCall = _isVideoCall;
    final modeLabel = isVideoCall
        ? (l.isArabic ? 'مكالمة فيديو' : 'Video call')
        : (l.isArabic ? 'مكالمة صوتية' : 'Voice call');

    String statusText;
    if (!_active) {
      statusText = l.isArabic ? 'انتهت المكالمة' : 'Call ended';
    } else if (_connected && _elapsed.inSeconds > 0) {
      statusText = _fmt(_elapsed);
    } else if (_ringing) {
      statusText = l.isArabic ? 'يرن…' : 'Ringing…';
    } else {
      statusText = l.isArabic ? 'جارٍ الاتصال...' : 'Calling…';
    }

    final hasRemote =
        _remoteStream != null && _remoteRenderer.srcObject != null;
    final hasLocal = _localStream != null && _localRenderer.srcObject != null;

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
    } else if (hasRemote) {
      remoteView = RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
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
      localPreview = Positioned(
        top: 16,
        right: 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 96,
            height: 144,
            color: Colors.black87,
            child: RTCVideoView(
              _localRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
      );
    }

    Widget controls;
    if (!isVideoCall) {
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
            onTap: _hangup,
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
            onTap: _hangup,
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

  Future<void> _initWebRtc(String deviceId) async {
    try {
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      };
      final pc = await createPeerConnection(config);
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
        await pc.addTrack(track, stream);
      }
      _localRenderer.srcObject = stream;
      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          final remote = event.streams.first;
          setState(() {
            _remoteStream = remote;
          });
          _remoteRenderer.srcObject = remote;
        }
      };
      pc.onIceCandidate = (cand) {
        final client = _client;
        if (client == null || cand.candidate == null) return;
        client.send({
          'type': 'ice_candidate',
          'call_id': _callId,
          'from': deviceId,
          'to': widget.peerId,
          'candidate': {
            'candidate': cand.candidate,
            'sdpMid': cand.sdpMid,
            'sdpMLineIndex': cand.sdpMLineIndex,
          },
        });
      };
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final client = _client;
      if (client != null) {
        await client.send({
          'type': 'webrtc_offer',
          'call_id': _callId,
          'from': deviceId,
          'to': widget.peerId,
          'sdp': offer.sdp,
          'sdp_type': offer.type,
        });
      }
    } catch (_) {
      // If WebRTC setup fails, keep signaling-only call UI.
    }
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
    if (stream == null) return;
    setState(() {
      _muted = !_muted;
    });
    for (final t in stream.getAudioTracks()) {
      t.enabled = !_muted;
    }
  }

  void _toggleVideo() {
    final stream = _localStream;
    if (stream == null) return;
    setState(() {
      _videoEnabled = !_videoEnabled;
    });
    for (final t in stream.getVideoTracks()) {
      t.enabled = _videoEnabled;
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
