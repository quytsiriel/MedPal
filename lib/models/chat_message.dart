class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  // Các biến bổ sung từ Endpoint /agent1/chat
  final String? stage;
  final String? decision;                    // "visit" | "no_visit"
  final String? advice;                      // Lời khuyên tóm tắt khi no_visit
  final Map<String, dynamic>? record;        // Hồ sơ JSON
  final String? recommendedDept;             // Khoa đề nghị khi visit
  final Map<String, dynamic>? selfCareTips;  // Tips chi tiết: {avoid, do, when_to_see_doctor}

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.stage,
    this.decision,
    this.advice,
    this.record,
    this.recommendedDept,
    this.selfCareTips,
  });

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
    String? stage,
    String? decision,
    String? advice,
    Map<String, dynamic>? record,
    String? recommendedDept,
    Map<String, dynamic>? selfCareTips,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      stage: stage ?? this.stage,
      decision: decision ?? this.decision,
      advice: advice ?? this.advice,
      record: record ?? this.record,
      recommendedDept: recommendedDept ?? this.recommendedDept,
      selfCareTips: selfCareTips ?? this.selfCareTips,
    );
  }
}
