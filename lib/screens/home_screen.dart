import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import '../services/api_service.dart';
import 'dart:math' as math;

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

  @override
  void dispose() {
    _typeController.dispose();
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
    } catch(e) {
      if (mounted) {
        setState(() => _currentReply = "Lỗi kết nối mạng...");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 2. Mock Logic gửi tin nhắn (Bằng tay hoặc giả lập Voice)
  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _currentReply = "MedPal đang phân tích triệu chứng của bạn...";
      _showHospitalRecommendations = false;
    });

    // MOCK: Delay 1.5s để giả lập xử lý
    await Future.delayed(const Duration(milliseconds: 1500));
    
    if (mounted) {
      setState(() => _isLoading = false);
      // MOCK: Luôn hiển thị popup xác nhận tình trạng nặng
      _showSeverityConfirmDialog();
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
            Expanded(child: Text("Báo động triệu chứng", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("KHÔNG", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleSeverityResponse(isSevere: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("CÓ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      )
    );
  }

  void _handleSeverityResponse({required bool isSevere}) {
    if (isSevere) {
      _showEmergencyActionDialog();
    } else {
      setState(() {
        _currentReply = "Đừng quá lo lắng. Hãy nghỉ ngơi, uống nhiều nước ấm.\nNếu các triệu chứng kéo dài hoặc nặng lên, hãy đến các phòng khám gần nhất dưới đây để kiểm tra nhé.";
        _showHospitalRecommendations = true;
      });
    }
  }

  void _showEmergencyActionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFF0F0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.red, width: 2)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.emergency_outlined, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              "TÌNH TRẠNG KHẨN CẤP",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 16),
            const Text(
              "Hãy gọi 115 ngay bây giờ. Hoặc nhờ người thân đưa đến Khoa Cấp cứu gần nhất.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.phone_in_talk, color: Colors.white, size: 28),
                label: const Text("GỌI 115", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                icon: const Icon(Icons.directions, color: Colors.white, size: 28),
                label: const Text("CHỈ ĐƯỜNG ĐẾN BỆNH VIỆN", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                   Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _currentReply = "Tôi hi vọng bạn sẽ sớm nhận được sự hỗ trợ y tế kịp thời.");
              },
              child: const Text("Đóng", style: TextStyle(fontSize: 16, color: Colors.grey)),
            )
          ],
        ),
      )
    );
  }

  // 3. Popup hiển thị QR Code thay vì dính trong bong bóng
  void _showQRDialog(String base64String) {
    String cleanBase64 = base64String.contains(',') ? base64String.split(',').last : base64String;
    try {
      final decoded = base64Decode(cleanBase64);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("Mã bệnh án", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF006B70), fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               ClipRRect(
                 borderRadius: BorderRadius.circular(16),
                 child: Image.memory(decoded, width: 200, height: 200, fit: BoxFit.cover),
               ),
               const SizedBox(height: 16),
               const Text("Vui lòng đưa mã này cho nhân viên y tế tại quầy đăng ký.", 
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.4, color: Color(0xFF576162)),
               ),
            ]
          ),
          actions: [
             TextButton(
               onPressed: () => Navigator.pop(ctx), 
               child: const Text("Đóng", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF006B70)))
             )
          ]
        )
      );
    } catch(e) {
       // Ignore decode err
    }
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
              _buildHospitalRecommendations(),
              const SizedBox(height: 16),
              _buildRobotMascot(context),
              const SizedBox(height: 16),
              const Text(
                'Nhấn vào trái tim để bắt đầu nói',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF6B7B80),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 48),
              _buildManualInput(context),
              const SizedBox(height: 32),
            ],
          ),
        ),
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
            icon: const Icon(Icons.settings_rounded, size: 30, color: Color(0xFF006B70)),
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
                      width: 24, height: 24, 
                      child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006A71))
                    )
                  )
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

  Widget _buildHospitalRecommendations() {
    if (!_showHospitalRecommendations) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "📍 Đề xuất phòng khám lân cận",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF006B70)),
          ),
          const SizedBox(height: 16),
          _buildHospitalCard("Bệnh viện Đa khoa Medlatec", "Cách đây 1.2 km", "Đang mở cửa"),
          const SizedBox(height: 12),
          _buildHospitalCard("Phòng khám Đa khoa Thu Cúc", "Cách đây 2.5 km", "Đang mở cửa"),
          const SizedBox(height: 12),
          _buildHospitalCard("Bệnh viện Bạch Mai", "Cách đây 4.0 km", "Cấp cứu 24/7", isEmergency: true),
        ],
      ),
    );
  }

  Widget _buildHospitalCard(String name, String distance, String status, {bool isEmergency = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: isEmergency ? Colors.red.withOpacity(0.3) : const Color(0xFFE5F1F1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF4FAFA), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF006A71), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2C3E50))),
                const SizedBox(height: 4),
                Text(distance, style: const TextStyle(color: Color(0xFF7F8C8D), fontSize: 13)),
                const SizedBox(height: 4),
                Text(status, style: TextStyle(color: isEmergency ? Colors.red : Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.directions_rounded, color: Colors.blueAccent, size: 28),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Mở chỉ đường tới $name trên Google Maps...")));
            },
          )
        ],
      ),
    );
  }

  Widget _buildRobotMascot(BuildContext context) {
    // -------------------------------------------------------------
    // Tinh chỉnh kích thước và vị trí của trái tim tại đây:
    const double heartWidth = 350.0;        // Chiều ngang của trái tim
    const double heartHeight = 350.0;       // Chiều cao của trái tim 
    const double heartBottomOffset = -5;  // Độ xa tính từ mép dưới của nhân vật
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
              )
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
            onTapDown: (_) => setState(() => _isHeartPressed = true),
            onTapUp: (_) {
               setState(() => _isHeartPressed = false);
               // Tuơng lai: Bắt đầu thu âm voice ở đây
               // Hiện tại (Mock): Chọc bằng chữ 
               _sendMessage("Giả lập thu âm...");
            },
            onTapCancel: () => setState(() => _isHeartPressed = false),
            child: SizedBox(
               width: heartWidth, 
               height: heartHeight,
               child: AnimatedCrossFade(
                  firstChild: Image.asset('assets/heart_normal.png', fit: BoxFit.contain, width: heartWidth, height: heartHeight),
                  secondChild: Image.asset('assets/heart_pressed.png', fit: BoxFit.contain, width: heartWidth, height: heartHeight),
                  crossFadeState: _isHeartPressed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 150),
               )
            )
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
                   borderSide: const BorderSide(color: Color(0xFFE5F1F1), width: 2),
                 ),
                 enabledBorder: OutlineInputBorder(
                   borderRadius: BorderRadius.circular(30), 
                   borderSide: const BorderSide(color: Color(0xFFE5F1F1), width: 2),
                 ),
                 focusedBorder: OutlineInputBorder(
                   borderRadius: BorderRadius.circular(30), 
                   borderSide: const BorderSide(color: Color(0xFF006A71), width: 2),
                 ),
                 contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
              ),
              onSubmitted: (val) {
                 _sendMessage(val);
                 _typeController.clear();
              },
            )
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
              }
            ),
          )
        ]
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
