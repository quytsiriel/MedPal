
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/audio_reader.dart';

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

  // ── Voice Recording ─────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    _startConversation();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
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

  // 2. Logic gửi tin nhắn text với session_id
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
      _handleAgentResponse(response);
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

  // ── Voice Recording Methods ─────────────────────
  bool _isProcessingMic = false;

  Future<void> _toggleRecording() async {
    if (_isProcessingMic) return;
    _isProcessingMic = true;
    try {
      if (_isRecording) {
        await _stopRecordingAndSend();
      } else {
        await _startRecording();
      }
    } finally {
      _isProcessingMic = false;
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final filePath = await createRecordingPath();
        final config = kIsWeb
            ? const RecordConfig(encoder: AudioEncoder.opus)
            : const RecordConfig(
                encoder: AudioEncoder.wav,
                sampleRate: 16000,
                numChannels: 1,
              );
        await _audioRecorder.start(config, path: filePath);
        _recordTimer?.cancel();
        setState(() {
          _isRecording = true;
          _recordDuration = Duration.zero;
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _recordDuration += const Duration(seconds: 1));
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần cấp quyền microphone để ghi âm.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi ghi âm: $e')),
        );
      }
    }
  }

  Future<void> _stopRecordingAndSend() async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
    });

    if (path == null || _currentSessionId == null) return;

    try {
      // Đọc audio bytes (cross-platform: File trên mobile, blob URL trên web)
      final bytes = await readRecordedAudio(path);
      final base64Audio = base64Encode(bytes);

      // Thêm placeholder tin nhắn đang nhận dạng
      setState(() {
        _messages.add(ChatMessage(
          text: '🎤 Đang nhận dạng giọng nói...',
          isUser: true,
          timestamp: DateTime.now(),
        ));
        _isLoading = true;
      });
      _scrollToBottom();

      // Gửi audio đến backend
      final response = await apiService.chatSymptom(
        sessionId: _currentSessionId!,
        voiceBase64: base64Audio,
      );

      // Cập nhật placeholder với transcript thực tế
      final transcript = response['transcript'] as String?;
      if (transcript != null && _messages.isNotEmpty) {
        // Tìm placeholder message cuối cùng và thay thế
        for (int i = _messages.length - 1; i >= 0; i--) {
          if (_messages[i].isUser && _messages[i].text.contains('Đang nhận dạng')) {
            setState(() {
              _messages[i] = ChatMessage(
                text: transcript,
                isUser: true,
                timestamp: _messages[i].timestamp,
              );
            });
            break;
          }
        }
      }

      // Xử lý response từ Agent
      _handleAgentResponse(response);
    } catch (e) {
      setState(() {
        // Cập nhật placeholder thành lỗi
        for (int i = _messages.length - 1; i >= 0; i--) {
          if (_messages[i].isUser && _messages[i].text.contains('Đang nhận dạng')) {
            _messages[i] = ChatMessage(
              text: '🎤 Không thể nhận dạng giọng nói',
              isUser: true,
              timestamp: _messages[i].timestamp,
            );
            break;
          }
        }
        _messages.add(
          ChatMessage(
            text: "Lỗi nhận dạng giọng nói. Vui lòng thử lại hoặc nhập bằng văn bản.",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
    });
  }

  // ── Shared Response Handler ─────────────────────
  void _handleAgentResponse(Map<String, dynamic> response) {
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

  // ── Recording Indicator ─────────────────────────
  Widget _buildRecordingIndicator() {
    final minutes = _recordDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _recordDuration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        border: Border(
          top: BorderSide(color: Colors.red.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Pulsing red dot (nhấp nháy mỗi giây nhờ Timer rebuild)
          AnimatedOpacity(
            opacity: _recordDuration.inSeconds.isEven ? 1.0 : 0.3,
            duration: const Duration(milliseconds: 300),
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Đang ghi âm',
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '$minutes:$seconds',
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Text(
                'Hủy',
                style: TextStyle(
                  color: Colors.red.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input Area with Mic Button ──────────────────
  Widget _buildInputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Recording banner (hiện khi đang ghi âm)
        if (_isRecording) _buildRecordingIndicator(),

        Container(
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
                            enabled: !_isLoading && !_isInit && !_isCompleted && !_isRecording,
                            style: const TextStyle(fontSize: 18),
                            decoration: InputDecoration(
                              hintText: _isRecording ? 'Đang ghi âm...' : 'Nhập triệu chứng...',
                              hintStyle: TextStyle(
                                color: _isRecording ? Colors.red.shade300 : Colors.grey,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                            onSubmitted: _isLoading ? null : _handleSubmitted,
                          ),
                        ),
                        if (!_isRecording)
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
                // ── Mic / Stop Button ──
                GestureDetector(
                  onTap: _isLoading || _isInit || _isCompleted
                      ? null
                      : _toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? const Color(0xFFE53935)
                          : const Color(0xFF006A71),
                      shape: BoxShape.circle,
                      boxShadow: _isRecording
                          ? [
                              BoxShadow(
                                color: const Color(0xFFE53935).withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_none,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
