import '../domain/chat_message.dart';

class NoActiveChatPeerException implements Exception {
  final String message;

  const NoActiveChatPeerException([
    this.message = 'No chat contact selected yet.',
  ]);

  @override
  String toString() => message;
}

abstract class ChatRepository {
  Future<List<ChatMessage>> listMessages();
  Future<ChatMessage> sendMessage(
      {required String text, required String sender});
}
