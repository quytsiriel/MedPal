import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';
import '../services/audio_reader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isHeartPressed = false;
  bool _isLoading = false;
  String _currentReply = "MedPal đang chuẩn bị...";
  String? _currentSessionId;
  bool _showHospitalRecommendations = false;
  final TextEditingController _typeController = TextEditingController();

  // ── Voice Recording ─────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  @override
  void dispose() {
    _typeController.dispose();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  // 1. Quản lý trạng thái Session
  Future<void> _startSession() async {
    setState(() => _isLoading = true);
    try {
      final res = await apiService.startSession();
      if (mounted) {
        setState(() {
          _currentSessionId = res['session_id'];
          // Hiển thị câu chào đầu tiên lên bong bóng thoại
          _currentReply = res['message'] ?? "Xin chào!";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _currentReply = "Lỗi kết nối mạng...");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 2. Logic gửi tin nhắn thật qua API Gemini
  void _sendMessage(String text) async {
    if (text.trim().isEmpty || _currentSessionId == null) return;

    final inputLower = text.toLowerCase();

    // Keyword routing sang các phần khác
    if (inputLower.contains("đơn thuốc")) {
      context.go('/prescriptions');
      return;
    } else if (inputLower.contains("điều hướng") ||
        inputLower.contains("chỉ đường")) {
      context.go('/navigation');
      return;
    }

    setState(() {
      _isLoading = true;
      _currentReply = "MedPal đang phân tích triệu chứng của bạn...";
    });

    try {
      final response = await apiService.chatSymptom(
        sessionId: _currentSessionId!,
        message: text,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _currentReply =
            response['reply'] ?? "Lỗi: Không nhận được câu trả lời từ AI.";
      });

      // Nếu Gemini phân loại đây là khẩn cấp
      if (response['emergency'] == true) {
        _showSeverityConfirmDialog(); // Bật Popup đỏ
      }
      // Nếu Gemini nhận thấy đã thu thập đủ -> Đề xuất bệnh viện
      else if (response['stage'] == 'completed') {
        _showHospitalRecommendationsDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentReply = "Có lỗi xảy ra: $e";
        });
      }
    }
  }

  // ── Voice Recording Methods ─────────────────────
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecordingAndSend();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final filePath = await createRecordingPath();
        final config = const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        );
        await _audioRecorder.start(config, path: filePath);
        setState(() {
          _isRecording = true;
          _isHeartPressed = true;
          _recordDuration = Duration.zero;
          _currentReply = '🎤 Đang ghi âm... Nhấn lại trái tim để gửi.';
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            final m = _recordDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
            final s = _recordDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
            setState(() {
              _recordDuration += const Duration(seconds: 1);
              _currentReply = '🎤 Đang ghi âm... $m:$s\nNhấn lại trái tim để gửi.';
            });
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
        setState(() => _currentReply = 'Lỗi ghi âm: $e');
      }
    }
  }

  Future<void> _stopRecordingAndSend() async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _isHeartPressed = false;
      _recordDuration = Duration.zero;
    });

    if (path == null || _currentSessionId == null) return;

    setState(() {
      _isLoading = true;
      _currentReply = '🎤 Đang nhận dạng giọng nói...';
    });

    try {
      final bytes = await readRecordedAudio(path);
      final base64Audio = base64Encode(bytes);

      final response = await apiService.chatSymptom(
        sessionId: _currentSessionId!,
        voiceBase64: base64Audio,
      );

      if (!mounted) return;

      final transcript = response['transcript'] as String?;
      final reply = response['reply'] ?? 'Lỗi: Không nhận được câu trả lời.';

      setState(() {
        _isLoading = false;
        _currentReply = reply;
      });

      // Hiển thị transcript trong snackbar
      if (transcript != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bạn nói: "$transcript"'),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF006A71),
          ),
        );
      }

      if (response['emergency'] == true) {
        _showSeverityConfirmDialog();
      } else if (response['stage'] == 'completed' ||
                 response['stage'] == 'complete_visit' ||
                 response['stage'] == 'complete_no_visit') {
        _showHospitalRecommendationsDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentReply = 'Lỗi nhận dạng giọng nói: $e';
        });
      }
    }
  }

  // MOCK: Popup xác nhận triệu chứng nặng
  void _showSeverityConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "Báo động triệu chứng",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          "Bạn có đang cảm thấy quá đau không chịu nổi hoặc khó thở nghiêm trọng không?",
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleSeverityResponse(isSevere: false);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "KHÔNG",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleSeverityResponse(isSevere: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "CÓ",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSeverityResponse({required bool isSevere}) {
    if (isSevere) {
      _showEmergencyActionDialog();
    } else {
      setState(() {
        _currentReply =
            "Đừng quá lo lắng. Hãy nghỉ ngơi, uống nhiều nước ấm.\nNếu các triệu chứng kéo dài, hãy xem danh sách phòng khám trên màn hình nhé.";
      });
      _showHospitalRecommendationsDialog();
    }
  }

  void _showEmergencyActionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFF0F0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.red, width: 2),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.emergency_outlined, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              "TÌNH TRẠNG KHẨN CẤP",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Hãy gọi 115 ngay bây giờ. Hoặc nhờ người thân đưa đến Khoa Cấp cứu gần nhất.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(
                  Icons.phone_in_talk,
                  color: Colors.white,
                  size: 28,
                ),
                label: const Text(
                  "GỌI 115",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(
                  Icons.directions,
                  color: Colors.white,
                  size: 28,
                ),
                label: const Text(
                  "CHỈ ĐƯỜNG ĐẾN BV GẦN NHẤT",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go('/navigation');
                },
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(
                  () => _currentReply =
                      "Tôi hi vọng bạn sẽ sớm nhận được sự hỗ trợ y tế kịp thời.",
                );
              },
              child: const Text(
                "Đóng",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildCustomHeader(context),
              const SizedBox(height: 24),
              _buildSpeechBubble(context),
              const SizedBox(height: 16),
              _buildRobotMascot(context),
              const SizedBox(height: 16),
              Text(
                _isRecording ? 'Nhấn lại trái tim để gửi' : 'Nhấn vào trái tim để bắt đầu nói',
                style: TextStyle(
                  fontSize: 16,
                  color: _isRecording ? Colors.red : const Color(0xFF6B7B80),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 48),
              _buildManualInput(context),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        type: BottomNavigationBarType
            .fixed, // Giữ fixed để phòng hờ sau này teammate có thêm nút thứ 4, thứ 5
        selectedItemColor: const Color(0xFF006B70),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/'); // Trang hiện tại (Symptoms)
              break;
            case 1:
              context.go('/navigation'); // Agent 2
              break;
            case 2:
              context.go('/prescriptions'); // Agent 3
              break;
            // TODO (Teammate): Mở rộng logic chuyển trang (case 3, case 4...) cho Agent mới ở đây
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.medical_services_rounded),
            label: 'Khám bệnh',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.navigation_rounded),
            label: 'Chỉ đường',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Đơn thuốc',
          ),
          // TODO (Teammate): Khi có Agent mới, copy BottomNavigationBarItem và dán vào dưới dòng này
        ],
      ),
    );
  }

  Widget _buildCustomHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        children: [
          const Text(
            'MedPal',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF006B70),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(
              Icons.settings_rounded,
              size: 30,
              color: Color(0xFF006B70),
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: CustomPaint(
        painter: SpeechBubblePainter(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 30,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF006A71),
                      ),
                    ),
                  ),
                )
              : Text(
                  _currentReply,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF006B70),
                    height: 1.4,
                  ),
                ),
        ),
      ),
    );
  }

  void _showHospitalRecommendationsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        title: const Row(
          children: [
            Icon(Icons.location_on_rounded, color: Color(0xFF006B70)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "Đề xuất phòng khám",
                style: TextStyle(
                  fontSize: 18,
                  color: Color(0xFF006B70),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHospitalCard(
                ctx,
                "Bệnh viện Đa khoa Medlatec",
                "Cách đây 1.2 km",
                "Đang mở cửa",
              ),
              const SizedBox(height: 12),
              _buildHospitalCard(
                ctx,
                "Phòng khám Đa khoa Thu Cúc",
                "Cách đây 2.5 km",
                "Đang mở cửa",
              ),
              const SizedBox(height: 12),
              _buildHospitalCard(
                ctx,
                "Bệnh viện Bạch Mai",
                "Cách đây 4.0 km",
                "Cấp cứu 24/7",
                isEmergency: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Đóng",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalCard(
    BuildContext ctx,
    String name,
    String distance,
    String status, {
    bool isEmergency = false,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        context.go('/navigation'); // Chuyển hướng sang Agent 2
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isEmergency
                ? Colors.red.withOpacity(0.3)
                : const Color(0xFFE5F1F1),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4FAFA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.local_hospital_rounded,
                color: Color(0xFF006A71),
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    distance,
                    style: const TextStyle(
                      color: Color(0xFF7F8C8D),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: TextStyle(
                      color: isEmergency ? Colors.red : Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.directions_rounded,
                color: Colors.blueAccent,
                size: 28,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/navigation'); // Chuyển hướng sang Agent 2
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRobotMascot(BuildContext context) {
    // -------------------------------------------------------------
    // Tinh chỉnh kích thước và vị trí của trái tim tại đây:
    const double heartWidth = 350.0; // Chiều ngang của trái tim
    const double heartHeight = 350.0; // Chiều cao của trái tim
    const double heartBottomOffset = -5; // Độ xa tính từ mép dưới của nhân vật
    // -------------------------------------------------------------

    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow Background
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF96F1FA).withOpacity(0.4),
                blurRadius: 60,
                spreadRadius: 20,
              ),
            ],
          ),
        ),
        // Mascot Image
        Image.asset(
          'assets/mascot.png',
          width: 320,
          height: 320,
          fit: BoxFit.contain,
        ),

        // 5. Nút Mic - Bắt sự kiện Nhấn nhả sử dụng ảnh Assets (Tắt viền trắng)
        Positioned(
          bottom: heartBottomOffset, // Vị trí trái tim lên xuống
          child: GestureDetector(
            onTap: _isLoading ? null : _toggleRecording,
            child: SizedBox(
              width: heartWidth,
              height: heartHeight,
              child: AnimatedCrossFade(
                firstChild: Image.asset(
                  'assets/heart_normal.png',
                  fit: BoxFit.contain,
                  width: heartWidth,
                  height: heartHeight,
                ),
                secondChild: Image.asset(
                  'assets/heart_pressed.png',
                  fit: BoxFit.contain,
                  width: heartWidth,
                  height: heartHeight,
                ),
                crossFadeState: _isHeartPressed
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 150),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _typeController,
              decoration: InputDecoration(
                hintText: "Nhập triệu chứng...",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(
                    color: Color(0xFFE5F1F1),
                    width: 2,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(
                    color: Color(0xFFE5F1F1),
                    width: 2,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(
                    color: Color(0xFF006A71),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
              onSubmitted: (val) {
                _sendMessage(val);
                _typeController.clear();
              },
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF006A71),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: () {
                _sendMessage(_typeController.text);
                _typeController.clear();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SpeechBubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width / 2 - 15, size.height);
    path.lineTo(size.width / 2, size.height + 15);
    path.lineTo(size.width / 2 + 15, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
