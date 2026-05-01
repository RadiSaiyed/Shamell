import 'package:flutter/foundation.dart';

import '../../../core/analytics/analytics_event.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/analytics/v2_event_catalog.dart';
import '../../../core/metrics/kpi_tracker.dart';
import '../application/send_message_use_case.dart';
import '../domain/chat_message.dart';
import '../infrastructure/chat_repository.dart';

class ChatController extends ChangeNotifier {
  final ChatRepository repository;
  final SendMessageUseCase sendMessageUseCase;
  final AnalyticsService analytics;
  final KpiTracker kpi;

  ChatController({
    required this.repository,
    required this.sendMessageUseCase,
    required this.analytics,
    required this.kpi,
  });

  bool loading = false;
  bool sending = false;
  bool needsPeerSelection = false;
  String error = '';
  List<ChatMessage> messages = <ChatMessage>[];

  Future<void> load() async {
    loading = true;
    error = '';
    notifyListeners();
    try {
      messages = await repository.listMessages();
      needsPeerSelection = false;
    } catch (e) {
      if (e is NoActiveChatPeerException) {
        needsPeerSelection = true;
        messages = <ChatMessage>[];
      } else {
        needsPeerSelection = false;
        error = _readableError(e, fallback: 'Could not load messages.');
      }
      await analytics.track(
        AnalyticsEvent(
          name: V2EventCatalog.errorShown,
          timestamp: DateTime.now(),
          properties: const <String, Object?>{
            'code': 'chat.load_failed',
            'surface': 'chat',
          },
        ),
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> send({required String text, required String sender}) async {
    final startedAt = DateTime.now();
    sending = true;
    error = '';
    notifyListeners();
    try {
      final next = await sendMessageUseCase.run(text: text, sender: sender);
      messages = List<ChatMessage>.from(messages)..add(next);
      needsPeerSelection = false;
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      await analytics.track(
        AnalyticsEvent(
          name: V2EventCatalog.chatMessageSent,
          timestamp: DateTime.now(),
          properties: <String, Object?>{
            'chat_type': 'direct',
            'elapsed_ms': elapsedMs,
          },
        ),
      );
      await kpi.markFirstSuccess(flow: 'chat');
      return true;
    } catch (e) {
      if (e is NoActiveChatPeerException) {
        needsPeerSelection = true;
        error = e.message;
      } else {
        error = _readableError(e, fallback: 'Message failed to send.');
      }
      await analytics.track(
        AnalyticsEvent(
          name: V2EventCatalog.errorShown,
          timestamp: DateTime.now(),
          properties: const <String, Object?>{
            'code': 'chat.send_failed',
            'surface': 'chat',
          },
        ),
      );
      return false;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  String _readableError(
    Object errorValue, {
    required String fallback,
  }) {
    final raw = errorValue.toString().replaceFirst('Exception:', '').trim();
    if (raw.isEmpty) return fallback;
    return raw;
  }
}
