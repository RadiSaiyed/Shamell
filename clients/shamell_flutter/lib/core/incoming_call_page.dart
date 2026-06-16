import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'l10n.dart';
import 'call_signaling.dart';
import 'safe_set_state.dart';
import 'chat/chat_service.dart';
import 'chat/chat_models.dart';

class IncomingCallPage extends StatefulWidget {
  final String baseUrl;
  final String callId;
  final String fromDeviceId;
  final String mode; // 'audio' | 'video'

  const IncomingCallPage({
    super.key,
    required this.baseUrl,
    required this.callId,
    required this.fromDeviceId,
    this.mode = 'video',
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
  CallSignalingClient? _client;
  StreamSubscription<Map<String, dynamic>>? _sigSub;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _deviceId;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _accepted = false;
  bool _acceptRequested = false;
  bool _answerSent = false;
  bool _processingOffer = false;
  bool _signalingInitStarted = false;
  String? _pendingOfferSdp;
  bool _muted = false;
  bool _videoEnabled = true;
  bool _speakerOn = false;
  bool _logged = false;
  String _callerName = '';

  bool get _isVideoCall => widget.mode.toLowerCase() == 'video';

  @override
  void initState() {
    super.initState();
    _videoEnabled = _isVideoCall;
    _speakerOn = _isVideoCall;
    _callerName = widget.fromDeviceId;
    _resolveCallerName();
    _initSignaling();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_active || !_connected) return;
      setState(() {
        _elapsed += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _initSignaling() async {
    if (_signalingInitStarted) return;
    _signalingInitStarted = true;
    try {
      final devId = await CallSignalingClient.loadDeviceId();
      if (!mounted) return;
      if (devId == null || devId.isEmpty) {
        return;
      }
      _deviceId = devId;
      final client = CallSignalingClient(widget.baseUrl);
      final stream = client.connect(deviceId: devId);
      _client = client;
      _sigSub = stream.listen(_onSignal);
      if (_acceptRequested) {
        unawaited(_flushAcceptFlow());
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _resolveCallerName() async {
    final fromId = widget.fromDeviceId.trim();
    if (fromId.isEmpty) return;
    String label = '';
    try {
      final sp = await SharedPreferences.getInstance();
      final rawAliases = sp.getString('friends.aliases') ?? '{}';
      final decoded = jsonDecode(rawAliases);
      if (decoded is Map) {
        final v = decoded[fromId];
        if (v is String && v.trim().isNotEmpty) {
          label = v.trim();
        }
      }
    } catch (_) {}
    if (label.isEmpty) {
      try {
        final contacts = await ChatLocalStore().loadContacts();
        for (final c in contacts) {
          if (c.id.trim() != fromId) continue;
          final name = (c.name ?? '').trim();
          if (name.isNotEmpty) {
            label = name;
            break;
          }
        }
      } catch (_) {}
    }
    if (label.isEmpty) {
      try {
        final svc = ChatService(widget.baseUrl);
        final c = await svc.resolveDevice(fromId);
        final name = (c.name ?? '').trim();
        if (name.isNotEmpty) label = name;
      } catch (_) {}
    }
    if (label.isEmpty) label = fromId;
    if (!mounted) return;
    setState(() {
      _callerName = label;
    });
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
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

  Future<void> _onSignal(Map<String, dynamic> msg) async {
    if (!mounted) return;
    final type = (msg['type'] ?? '').toString();
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
      _endCall();
    } else if (type == 'answer') {
      setState(() {
        _connected = true;
      });
    }
  }

  void _endCall() {
    final client = _client;
    final devId = _deviceId;
    if (client != null && devId != null && devId.isNotEmpty) {
      client
          .sendHangup(
            callId: widget.callId,
            fromDeviceId: devId,
            toDeviceId: widget.fromDeviceId,
          )
          .catchError((_) {});
    }
    _logAndPop(accepted: _connected);
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

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
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
    if (!_connected) {
      controls = Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: Icons.call_end,
            label: l.isArabic ? 'رفض' : 'Decline',
            background: Colors.redAccent,
            onTap: _endCall,
          ),
          _roundButton(
            icon: isVideoCall ? Icons.videocam : Icons.call,
            label: l.isArabic ? 'قبول' : 'Accept',
            background: Tokens.colorPayments,
            onTap: _acceptCall,
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
            onTap: _endCall,
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
            onTap: _endCall,
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

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _logAndPop({required bool accepted}) async {
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
      await store.append(entry);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _processOffer() async {
    final sdp = _pendingOfferSdp;
    if (sdp == null || sdp.isEmpty) return;
    await _ensurePeerConnection();
    final pc = _pc;
    final devId = _deviceId;
    if (pc == null || devId == null || devId.isEmpty) return;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'),
      );
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final client = _client;
      if (client != null) {
        await client.send({
          'type': 'webrtc_answer',
          'call_id': widget.callId,
          'from': devId,
          'to': widget.fromDeviceId,
          'sdp': answer.sdp,
          'sdp_type': answer.type,
        });
      }
      setState(() {
        _connected = true;
      });
    } catch (_) {}
  }

  Future<void> _flushAcceptFlow() async {
    if (!_active || !_acceptRequested) return;
    final client = _client;
    final devId = _deviceId;
    if (!_answerSent && client != null && devId != null && devId.isNotEmpty) {
      await client.sendAnswer(
        callId: widget.callId,
        fromDeviceId: devId,
        toDeviceId: widget.fromDeviceId,
      );
      _answerSent = true;
    }
    if (!_processingOffer &&
        _pendingOfferSdp != null &&
        _pendingOfferSdp!.isNotEmpty) {
      _processingOffer = true;
      try {
        await _processOffer();
      } finally {
        _processingOffer = false;
      }
    }
  }

  void _acceptCall() async {
    if (!_active || _connected) return;
    setState(() {
      _accepted = true;
      _acceptRequested = true;
    });
    if (_client == null || _deviceId == null || _deviceId!.isEmpty) {
      unawaited(_initSignaling());
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
    if (stream == null) return;
    setState(() {
      _muted = !_muted;
    });
    for (final t in stream.getAudioTracks()) {
      t.enabled = !_muted;
    }
  }

  void _toggleVideo() {
    if (!_isVideoCall) return;
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
