import '../domain/chat_message.dart';
import '../infrastructure/chat_repository.dart';

class SendMessageUseCase {
  final ChatRepository repository;

  SendMessageUseCase({required this.repository});

  Future<ChatMessage> run({required String text, required String sender}) {
    return repository.sendMessage(text: text, sender: sender);
  }
}
