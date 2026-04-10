class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  
  // Các biến bổ sung từ Endpoint /agent1/chat
  final String? stage;
  final String? qrCodeBase64; // Chỉ có sẵn khi stage = 'completed'

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.stage,
    this.qrCodeBase64,
  });
}
