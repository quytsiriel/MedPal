
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SymptomScreen extends StatefulWidget {
  const SymptomScreen({super.key});

  @override
  State<SymptomScreen> createState() => _SymptomScreenState();
}

class _SymptomScreenState extends State<SymptomScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isInit = true; // Trạng thái đang bốc sessionId ở lần đầu mở
  bool _isCompleted = false; // Phiên đã kết thúc
  String? _currentSessionId;
  
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isMicPressed = false;

  @override
  void initState() {
    super.initState();
    _startConversation();
  }

  // 1. Hook khởi tạo lấy session_id
  Future<void> _startConversation() async {
    setState(() => _isInit = true);
    try {
      final res = await apiService.startSession();
      _currentSessionId = res["session_id"];
      
      setState(() {
        _messages.add(
          ChatMessage(
            text: res["message"] ?? "Đã kết nối trợ lý y tế.",
            isUser: false,
            timestamp: DateTime.now(),
            stage: res["stage"],
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể kết nối đến máy chủ.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInit = false);
      }
    }
  }

  // 1b. STT Handlers
  void _onMicTapDown() async {
    setState(() => _isMicPressed = true);
    
    // Yêu cầu STT chạy dưới nền
    bool available = await _speechToText.initialize();
    if (available && _isMicPressed) {
      _speechToText.listen(
        onResult: (val) => setState(() {
          _textController.text = val.recognizedWords;
        }),
        localeId: 'vi_VN',
      );
    } else if (!available && mounted) {
       // Cảnh báo nếu test trên laptop k có mic
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Không thể kích hoạt Micro trên thiết bị hiện tại.'))
       );
    }
  }

  void _onMicTapUp() async {
    setState(() => _isMicPressed = false);
    await _speechToText.stop();
  }

  // 2. Logic gửi tin nhắn với session_id
  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty || _currentSessionId == null || _isCompleted) return;
    _textController.clear();

    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await apiService.chatSymptom(
        sessionId: _currentSessionId!,
        message: text,
      );
      
      final stage = response['stage'] as String? ?? 'collecting';
      final decision = response['decision'] as String?;
      final advice = response['advice'] as String?;
      final record = response['record'] as Map<String, dynamic>?;
      final recommendedDept = response['recommended_dept'] as String?;
      
      setState(() {
        _messages.add(
          ChatMessage(
            text: response['reply'] ?? "Tôi đang phân tích...",
            isUser: false,
            timestamp: DateTime.now(),
            stage: stage,
            decision: decision,
            advice: advice,
            record: record,
            recommendedDept: recommendedDept,
          ),
        );
        
        // Đánh dấu phiên kết thúc nếu complete
        if (stage == 'complete_visit' || stage == 'complete_no_visit') {
          _isCompleted = true;
        }
      });
    } catch (e) {
       setState(() {
          _messages.add(
            ChatMessage(
              text: "Lỗi đường truyền mạng: $e",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      appBar: AppBar(
        title: const Text('Check Symptoms', style: TextStyle(color: Color(0xFF006B70))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF006B70)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // List tin nhắn
            Expanded(
              child: _isInit 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF006A71))) 
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      // Kiểm tra stage đặc biệt cho UI khác nhau
                      if (!message.isUser && message.stage == 'clarifying') {
                        return _buildClarifyBubble(message);
                      }
                      if (!message.isUser && message.stage == 'complete_visit') {
                        return _buildCompleteVisitCard(message);
                      }
                      if (!message.isUser && message.stage == 'complete_no_visit') {
                        return _buildCompleteNoVisitCard(message);
                      }
                      return _buildChatBubble(message);
                    },
                  ),
            ),
            
            // Loading Indicator (Typing)
            if (_isLoading)
               Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006a71)),
                    ),
                    const SizedBox(width: 8),
                    Text('MedPal đang suy nghĩ...', style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),

            if (_isMicPressed)
               Padding(
                 padding: const EdgeInsets.symmetric(vertical: 8.0),
                 child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       const Icon(Icons.mic, color: Colors.red, size: 18),
                       const SizedBox(width: 8),
                       Text('Đang ghi âm...', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                    ]
                 )
               ),

            // Bottom Input Bar
            if (!_isCompleted) _buildInputArea(),
          ],
        ),
      ),
    );
  }

  // ── Chat Bubble bình thường ─────────────────────
  Widget _buildChatBubble(ChatMessage message) {
    final isUser = message.isUser;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                const CircleAvatar(
                  backgroundColor: Color(0xFF96F1FA),
                  child: Icon(Icons.pets, color: Color(0xFF006B70)),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: isUser ? const Color(0xFFCAE6FF) : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                          bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Text(
                        message.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: isUser ? const Color(0xFF00474C) : Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),

                  ],
                ),
              ),
              if (isUser) const SizedBox(width: 52),
            ],
          ),
        ],
      ),
    );
  }

  // ── Clarifying Bubble (💡 Giải thích thuật ngữ) ──
  Widget _buildClarifyBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFFFF3CD),
            child: Icon(Icons.lightbulb_outline, color: Color(0xFFB8860B)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF0),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(color: const Color(0xFFFFE0A0), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Color(0xFFB8860B)),
                      SizedBox(width: 6),
                      Text(
                        'Giải thích thuật ngữ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB8860B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF5D4E37),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Complete Visit Card (🏥 Đề xuất đi khám) ──
  Widget _buildCompleteVisitCard(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFDCEFFF),
            child: Icon(Icons.local_hospital, color: Color(0xFF1565C0)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE8F4FD), Color(0xFFFFFFFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(color: const Color(0xFFB3D9F2), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.medical_services, size: 18, color: Color(0xFF1565C0)),
                      SizedBox(width: 8),
                      Text(
                        'Đề xuất đi khám bác sĩ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF333333),
                      height: 1.5,
                    ),
                  ),
                  if (message.recommendedDept != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.domain, size: 16, color: Color(0xFF1565C0)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Khoa: ${message.recommendedDept}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Navigate sang màn hình tìm bệnh viện
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tính năng tìm bệnh viện đang phát triển.')),
                        );
                      },
                      icon: const Icon(Icons.location_on, size: 18),
                      label: const Text('Tìm bệnh viện gần nhất'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006A71),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Complete No-Visit Card (🏡 Lời khuyên tại nhà) ──
  Widget _buildCompleteNoVisitCard(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFD4EDDA),
            child: Icon(Icons.health_and_safety, color: Color(0xFF28A745)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEEF9F0), Color(0xFFFFFFFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(color: const Color(0xFFC3E6CB), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.spa, size: 18, color: Color(0xFF28A745)),
                      SizedBox(width: 8),
                      Text(
                        'Chăm sóc tại nhà',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF28A745),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF333333),
                      height: 1.5,
                    ),
                  ),
                  if (message.advice != null && message.advice!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF28A745).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.tips_and_updates, size: 16, color: Color(0xFF28A745)),
                              SizedBox(width: 6),
                              Text(
                                'Lời khuyên',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF28A745),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            message.advice!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF2D5A30),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, size: 16, color: Color(0xFFB8860B)),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Nếu triệu chứng nặng hơn, hãy đi khám ngay!',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF856404),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
           BoxShadow(
             color: Colors.black.withValues(alpha: 0.05),
             blurRadius: 10,
             offset: const Offset(0, -5),
           )
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF6FAFB),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFDAE4E6)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        enabled: !_isLoading && !_isInit && !_isCompleted,
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(
                          hintText: 'Nhập triệu chứng...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        onSubmitted: _isLoading ? null : _handleSubmitted,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF006A71)),
                      onPressed: _isLoading || _isInit || _isCompleted
                          ? null 
                          : () => _handleSubmitted(_textController.text),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTapDown: (_) => _onMicTapDown(),
              onTapUp: (_) => _onMicTapUp(),
              onTapCancel: () => _onMicTapUp(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.all(_isMicPressed ? 18 : 14),
                decoration: BoxDecoration(
                  color: _isMicPressed ? Colors.red : const Color(0xFF006A71),
                  shape: BoxShape.circle,
                  boxShadow: _isMicPressed 
                    ? [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 15, spreadRadius: 3)] 
                    : [],
                ),
                child: Icon(
                  _isMicPressed ? Icons.mic : Icons.mic_none, 
                  color: Colors.white, 
                  size: _isMicPressed ? 32 : 28
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
