class ChatMessage {
  final String id;
  final String sender;
  final String text;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.sentAt,
  });
}
