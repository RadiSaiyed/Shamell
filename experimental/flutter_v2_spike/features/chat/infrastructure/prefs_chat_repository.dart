import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/base_url.dart';
import '../../../../core/v2_chat_strangler.dart';
import '../domain/chat_message.dart';
import 'chat_repository.dart';

typedef OnChatAttemptRecorded = Future<void> Function();

class PrefsChatRepository implements ChatRepository {
  static const String _legacyMessagesKey = 'v2_chat_strangler_messages_v1';
  static const String _secureMessagesKey = 'chat.v2_strangler_messages.v2';
  static const String _scopedMessagesSecureKeyPrefix =
      'chat.v2_strangler_messages.v3.';
  static const String _scopedMessagesPrefKeyPrefix =
      'v2_chat_strangler_messages.v2.';
  static const String _prefsBaseUrlKey = 'base_url';
  static const String _unknownScope = 'unknown';
  static const FlutterSecureStorage _secureStore = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
      sharedPreferencesName: 'chat_secure_store',
    ),
    iOptions:
        IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
    mOptions:
        MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );
  final OnChatAttemptRecorded? onChatAttemptRecorded;

  PrefsChatRepository({this.onChatAttemptRecorded});

  @override
  Future<List<ChatMessage>> listMessages() async {
    final raw = (await _loadRawMessages()).trim();
    if (raw.isEmpty) {
      return <ChatMessage>[
        ChatMessage(
          id: 'seed-1',
          sender: 'system',
          text: 'V2 chat pilot is active.',
          sentAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      ];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ChatMessage>[];
      final out = <ChatMessage>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString().trim();
        final sender = (item['sender'] ?? '').toString().trim();
        final text = (item['text'] ?? '').toString();
        final sentAtRaw = (item['sent_at'] ?? '').toString().trim();
        if (id.isEmpty || sender.isEmpty || text.trim().isEmpty) continue;
        final sentAt = DateTime.tryParse(sentAtRaw) ?? DateTime.now();
        out.add(
          ChatMessage(
            id: id,
            sender: sender,
            text: text,
            sentAt: sentAt,
          ),
        );
      }
      out.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      return out;
    } catch (_) {
      return const <ChatMessage>[];
    }
  }

  @override
  Future<ChatMessage> sendMessage({
    required String text,
    required String sender,
  }) async {
    final stopwatch = Stopwatch()..start();
    var success = false;
    try {
      final cleanText = text.trim();
      final cleanSender = sender.trim();
      if (cleanText.isEmpty) {
        throw Exception('Message is empty');
      }
      if (cleanSender.isEmpty) {
        throw Exception('Sender is missing');
      }
      final now = DateTime.now();
      final next = ChatMessage(
        id: now.microsecondsSinceEpoch.toString(),
        sender: cleanSender,
        text: cleanText,
        sentAt: now,
      );
      final all = await listMessages();
      final updated = <ChatMessage>[...all, next];
      await _saveMessages(updated);
      success = true;
      return next;
    } finally {
      stopwatch.stop();
      await V2ChatStranglerStore.recordSendAttempt(
        variant: V2ChatFlowVariant.v2,
        elapsedMs: stopwatch.elapsedMilliseconds,
        success: success,
      );
      if (onChatAttemptRecorded != null) {
        try {
          await onChatAttemptRecorded!.call();
        } catch (_) {}
      }
    }
  }

  Future<void> _saveMessages(List<ChatMessage> values) async {
    final encoded = values
        .map(
          (m) => <String, Object?>{
            'id': m.id,
            'sender': m.sender,
            'text': m.text,
            'sent_at': m.sentAt.toUtc().toIso8601String(),
          },
        )
        .toList();
    await _persistRawMessages(jsonEncode(encoded));
  }

  bool _useSecureStore() => !kIsWeb;

  Future<String> _loadRawMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = _currentScope(prefs);
    final scopedSecureKey = _scopedKey(_scopedMessagesSecureKeyPrefix, scope);
    final scopedPrefKey = _scopedKey(_scopedMessagesPrefKeyPrefix, scope);

    if (_useSecureStore()) {
      try {
        final secure =
            (await _secureStore.read(key: scopedSecureKey) ?? '').trim();
        if (secure.isNotEmpty) {
          await _clearLegacyMessagesBestEffort(prefs: prefs);
          return secure;
        }
      } catch (_) {}

      try {
        final legacy =
            (await _secureStore.read(key: _secureMessagesKey) ?? '').trim();
        if (legacy.isEmpty) {
          // fall through to prefs legacy fallback
        } else {
          await _clearLegacyMessagesBestEffort(prefs: prefs);
          if (_isUnknownScope(scope)) {
            try {
              await _secureStore.write(key: scopedSecureKey, value: legacy);
              return legacy;
            } catch (_) {
              try {
                await _secureStore.delete(key: scopedSecureKey);
              } catch (_) {}
            }
          }
          return '';
        }
      } catch (_) {}
    }

    try {
      final scoped = (prefs.getString(scopedPrefKey) ?? '').trim();
      if (scoped.isNotEmpty) {
        await _clearLegacyMessagesBestEffort(prefs: prefs);
        return scoped;
      }
    } catch (_) {}

    final legacy = (prefs.getString(_legacyMessagesKey) ?? '').trim();
    if (legacy.isEmpty) return '';

    await _clearLegacyMessagesBestEffort(prefs: prefs);

    if (_useSecureStore()) {
      if (_isUnknownScope(scope)) {
        try {
          await _secureStore.write(key: scopedSecureKey, value: legacy);
          return legacy;
        } catch (_) {
          try {
            await _secureStore.delete(key: scopedSecureKey);
          } catch (_) {}
        }
      }
      return '';
    }

    if (_isUnknownScope(scope)) {
      await prefs.setString(scopedPrefKey, legacy);
      return legacy;
    }
    return '';
  }

  Future<void> _persistRawMessages(String raw) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _scopedKey(
      _useSecureStore()
          ? _scopedMessagesSecureKeyPrefix
          : _scopedMessagesPrefKeyPrefix,
      _currentScope(prefs),
    );
    if (_useSecureStore()) {
      try {
        await _secureStore.write(key: scopedKey, value: raw);
        await _clearLegacyMessagesBestEffort(prefs: prefs);
        return;
      } catch (_) {
        return;
      }
    }

    await prefs.setString(scopedKey, raw);
    await _clearLegacyMessagesBestEffort(prefs: prefs);
  }

  Future<void> _clearLegacyMessagesBestEffort(
      {SharedPreferences? prefs}) async {
    try {
      final instance = prefs ?? await SharedPreferences.getInstance();
      await instance.remove(_legacyMessagesKey);
    } catch (_) {}
    try {
      await _secureStore.delete(key: _secureMessagesKey);
    } catch (_) {}
  }

  String _currentScope(SharedPreferences prefs) {
    final rawBase = (prefs.getString(_prefsBaseUrlKey) ?? '').trim();
    final normalized = normalizeSecureApiBaseUrl(rawBase) ?? '';
    if (normalized.isEmpty) return _unknownScope;
    return Uri.parse(normalized).origin;
  }

  bool _isUnknownScope(String scope) => scope == _unknownScope;

  String _scopedKey(String prefix, String scope) => '$prefix$scope';
}
