import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';

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
  String? _currentSessionId;

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

  // 2. Logic gửi tin nhắn với session_id
  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty || _currentSessionId == null) return;
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
      
      setState(() {
        _messages.add(
          ChatMessage(
            text: response['reply'] ?? "Tôi đang phân tích...",
            isUser: false,
            timestamp: DateTime.now(),
            stage: response['stage'],
          ),
        );
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
                      return _buildChatBubble(_messages[index]);
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

            // Bottom Input Bar
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

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
                            color: Colors.black.withOpacity(0.04),
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

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
           BoxShadow(
             color: Colors.black.withOpacity(0.05),
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
                        enabled: !_isLoading && !_isInit,
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(
                          hintText: 'Nhập triệu chứng...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        // Nếu user gõ chữ "xong", server sẽ test trả về success
                        onSubmitted: _isLoading ? null : _handleSubmitted,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF006A71)),
                      onPressed: _isLoading || _isInit
                          ? null 
                          : () => _handleSubmitted(_textController.text),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
               onTap: () {
                // TBD: Tích hợp Ghi âm
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Color(0xFF006A71),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_none, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
