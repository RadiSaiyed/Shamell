import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'config.dart';
import 'notification_service.dart';

class GotifyClient {
  static WebSocketChannel? _channel;
  static bool _connecting = false;

  static bool get isEnabled =>
      kGotifyBaseUrl.isNotEmpty &&
      kGotifyClientToken.isNotEmpty &&
      (kPushProvider.toLowerCase() == 'gotify' || kPushProvider.toLowerCase() == 'both');

  static Future<void> start() async {
    if (!isEnabled || _connecting || _channel != null) return;
    _connecting = true;
    try {
      final url = _buildStreamUrl();
      if (url == null) {
        _connecting = false;
        return;
      }
      debugPrint('Gotify: connecting to $url');
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _channel = ch;
      ch.stream.listen(
        (event) async {
          try {
            if (event is String) {
              await _handleMessage(event);
            } else if (event is List<int>) {
              await _handleMessage(utf8.decode(event));
            }
          } catch (_) {}
        },
        onError: (e) {
          debugPrint('Gotify error: $e');
          _cleanup();
        },
        onDone: () {
          debugPrint('Gotify: stream closed');
          _cleanup();
        },
      );
    } catch (e) {
      debugPrint('Gotify connect failed: $e');
      _cleanup();
    } finally {
      _connecting = false;
    }
  }

  static String? _buildStreamUrl() {
    try {
      final base = kGotifyBaseUrl.trim();
      if (base.isEmpty) return null;
      final token = kGotifyClientToken.trim();
      if (token.isEmpty) return null;
      var u = base;
      if (u.endsWith('/')) u = u.substring(0, u.length - 1);
      // Prefer wss:// for https:// base; else fall back to ws://
      if (u.startsWith('https://')) {
        u = 'wss://' + u.substring('https://'.length);
      } else if (u.startsWith('http://')) {
        u = 'ws://' + u.substring('http://'.length);
      }
      return '$u/stream?token=$token';
    } catch (_) {
      return null;
    }
  }

  static Future<void> _handleMessage(String raw) async {
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) {
        final title = (j['title'] ?? '').toString();
        final message = (j['message'] ?? '').toString();
        final priority = j['priority'];
        debugPrint('Gotify message: $title / $message (prio=$priority)');
        await NotificationService.showSimple(title: title.isEmpty ? 'Notification' : title, body: message);
      }
    } catch (e) {
      debugPrint('Gotify message parse error: $e');
    }
  }

  static Future<void> stop() async {
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _cleanup();
  }

  static void _cleanup() {
    _channel = null;
  }
}
