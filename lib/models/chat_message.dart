class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  
  // Các biến bổ sung từ Endpoint /agent1/chat
  final String? stage;
  final String? decision;      // "visit" | "no_visit"
  final String? advice;        // Lời khuyên khi no_visit
  final Map<String, dynamic>? record;  // Hồ sơ JSON
  final String? recommendedDept; // Khoa đề nghị khi visit

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.stage,
    this.decision,
    this.advice,
    this.record,
    this.recommendedDept,
  });
} 
