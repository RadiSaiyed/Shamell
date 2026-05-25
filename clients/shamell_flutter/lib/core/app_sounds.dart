import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kShamellSoundEffectsEnabledKey = 'ui.sound_effects.enabled';

enum ShamellSoundEffect {
  success,
  paymentSent,
  moneyReceived,
  paymentRequest,
  error,
}

class ShamellSoundEffects {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  static final Map<ShamellSoundEffect, AudioPlayer> _players = {};
  static final Map<ShamellSoundEffect, Future<AudioPlayer>> _loadingPlayers =
      {};
  static final Map<ShamellSoundEffect, DateTime> _lastPlayedAt = {};

  static const Duration _debounceWindow = Duration(milliseconds: 140);

  ShamellSoundEffects._();

  static Future<void> loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      enabled.value = sp.getBool(kShamellSoundEffectsEnabledKey) ?? true;
    } catch (_) {}
  }

  static Future<void> loadPreference() => loadPrefs();

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kShamellSoundEffectsEnabledKey, value);
    } catch (_) {}
  }

  static Future<void> warmUp() async {
    if (!enabled.value || _shouldSkipPlayback) return;
    try {
      await Future.wait(<Future<AudioPlayer>>[
        _playerFor(ShamellSoundEffect.success),
        _playerFor(ShamellSoundEffect.paymentSent),
        _playerFor(ShamellSoundEffect.moneyReceived),
        _playerFor(ShamellSoundEffect.paymentRequest),
      ]);
    } catch (_) {}
  }

  static Future<void> play(ShamellSoundEffect effect) async {
    if (!enabled.value || _shouldSkipPlayback) return;
    final now = DateTime.now();
    final previous = _lastPlayedAt[effect];
    if (previous != null && now.difference(previous) < _debounceWindow) {
      return;
    }
    _lastPlayedAt[effect] = now;

    try {
      final player = await _playerFor(effect);
      if (player.playing) {
        await player.stop();
      }
      await player.setVolume(_volumeFor(effect));
      await player.seek(Duration.zero);
      await player.play();
    } catch (_) {}
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    enabled.value = true;
    _lastPlayedAt.clear();
    final players = List<AudioPlayer>.from(_players.values);
    _players.clear();
    _loadingPlayers.clear();
    for (final player in players) {
      await player.dispose();
    }
  }

  static Future<AudioPlayer> _playerFor(ShamellSoundEffect effect) {
    final existing = _players[effect];
    if (existing != null) return Future<AudioPlayer>.value(existing);
    final loading = _loadingPlayers[effect];
    if (loading != null) return loading;

    final future = () async {
      final player = AudioPlayer();
      try {
        await player.setVolume(_volumeFor(effect));
        await player.setAsset(_assetFor(effect));
        _players[effect] = player;
        return player;
      } catch (_) {
        await player.dispose();
        rethrow;
      } finally {
        _loadingPlayers.remove(effect);
      }
    }();
    _loadingPlayers[effect] = future;
    return future;
  }

  static String _assetFor(ShamellSoundEffect effect) {
    return switch (effect) {
      ShamellSoundEffect.success => 'assets/sfx/success.wav',
      ShamellSoundEffect.paymentSent => 'assets/sfx/payment_sent.wav',
      ShamellSoundEffect.moneyReceived => 'assets/sfx/money_received.wav',
      ShamellSoundEffect.paymentRequest => 'assets/sfx/payment_request.wav',
      ShamellSoundEffect.error => 'assets/sfx/error.wav',
    };
  }

  static double _volumeFor(ShamellSoundEffect effect) {
    return switch (effect) {
      ShamellSoundEffect.moneyReceived => 0.74,
      ShamellSoundEffect.paymentRequest => 0.72,
      ShamellSoundEffect.error => 0.68,
      ShamellSoundEffect.paymentSent || ShamellSoundEffect.success => 0.70,
    };
  }

  static bool get _shouldSkipPlayback {
    if (kIsWeb) return false;
    try {
      return WidgetsBinding.instance.runtimeType
          .toString()
          .contains('TestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }
}
