import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/api_service.dart';
import '../services/map_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isHeartPressed = false;
  bool _isLoading = false;
  String _currentReply = "MedPal đang chuẩn bị...";
  VoidCallback? _onReplyFinishedAction;
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

  Future<void> _startSession() async {
    setState(() => _isLoading = true);
    try {
      final res = await apiService.startSession();
      if (mounted) {
        setState(() {
          _currentReply = res['message'] ?? "Xin chào!";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _currentReply = "Lỗi kết nối mạng...");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final inputLower = text.toLowerCase();

    if (inputLower.contains("đơn thuốc")) {
      context.go('/prescriptions');
      return;
    }

    setState(() {
      _isLoading = false;
      if (inputLower.contains("đau ngực") ||
          inputLower.contains("khó thở") ||
          inputLower.contains("mồ hôi")) {
        _currentReply =
            "Đây có thể là dấu hiệu khẩn cấp về tim mạch. Bạn có muốn gọi xe cấp cứu 115 hoặc hướng dẫn đến khoa Cấp Cứu gần nhất không?";
        _onReplyFinishedAction = _showEmergencyActionDialog;
      } else if (inputLower.contains("ho") ||
          inputLower.contains("sổ mũi") ||
          inputLower.contains("sốt") ||
          inputLower.contains("cảm")) {
        _currentReply =
            "Có thể bạn đang bị cảm nhẹ. Bạn nên uống nước ấm, nghỉ ngơi. Nếu các triệu chứng kéo dài, tôi sẽ gợi ý phòng khám gần nhất nhé.";
        _onReplyFinishedAction = _fetchAndShowHospitals;
      } else if (inputLower.contains("tiểu đường") ||
          inputLower.contains("định kỳ") ||
          inputLower.contains("đường huyết")) {
        _currentReply =
            "Rất tốt. Tôi sẽ hướng dẫn bạn tìm cơ sở y tế gần nhất chuyên về Nội Tiết nhé!";
        _onReplyFinishedAction = _fetchAndShowHospitals;
      } else {
        _currentReply = "MedPal đang phân tích triệu chứng của bạn...";
        _onReplyFinishedAction = _showSeverityConfirmDialog;
      }
    });
  }

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
              child: Text("Báo động triệu chứng",
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("KHÔNG",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
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
            child: const Text("CÓ",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
        _onReplyFinishedAction = _fetchAndShowHospitals;
      });
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
          children: [
            const Icon(Icons.emergency_outlined, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text("TÌNH TRẠNG KHẨN CẤP",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
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
                label: const Text("GỌI 115",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await launchUrl(Uri.parse("tel:115"));
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.directions, color: Colors.white, size: 28),
                label: const Text("TÌM BỆNH VIỆN GẦN NHẤT",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _fetchAndShowHospitals();
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
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hospital flow
  // ─────────────────────────────────────────────────────────────────────────
  void _fetchAndShowHospitals() async {
    setState(() => _isLoading = true);

    final location = await mapService.getCurrentLocation();

    if (!mounted) return;

    if (location != null) {
      final hospitals = await apiService.getNearbyHospitals(location.lat, location.lng);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showHospitalDialog(hospitals, userLat: location.lat, userLng: location.lng);
    } else {
      setState(() {
        _isLoading = false;
        _currentReply = "Không lấy được vị trí GPS. Hãy bật Định vị hoặc chọn vị trí thủ công nhé!";
      });
      _showLocationPickerDialog();
    }
  }

  void _showLocationPickerDialog() {
    final presets = [
      (label: 'Đại học Bách Khoa HN',  lat: 21.0056, lng: 105.8433),
      (label: 'Hồ Hoàn Kiếm',          lat: 21.0285, lng: 105.8542),
      (label: 'Sân bay Nội Bài',        lat: 21.2187, lng: 105.8062),
      (label: 'Mỹ Đình',               lat: 21.0245, lng: 105.7834),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.my_location, color: Color(0xFF006B70)),
            SizedBox(width: 8),
            Text('Bạn đang ở đâu?',
                style: TextStyle(fontSize: 18, color: Color(0xFF006B70), fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chọn vị trí gần nhất của bạn:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ...presets.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on, color: Color(0xFF006B70)),
                  title: Text(p.label),
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);
                    final hospitals = await apiService.getNearbyHospitals(p.lat, p.lng);
                    if (mounted) {
                      setState(() => _isLoading = false);
                      _showHospitalDialog(hospitals, userLat: p.lat, userLng: p.lng);
                    }
                  },
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showHospitalDialog(List<Hospital> hospitals,
      {required double userLat, required double userLng}) {
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
              child: Text("Phòng khám gần bạn",
                  style: TextStyle(fontSize: 18, color: Color(0xFF006B70), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: hospitals.isEmpty
                ? [const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text("Không tìm thấy bệnh viện gần bạn."))]
                : hospitals
                    .map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildHospitalCard(
                            ctx: ctx,
                            hospital: h,
                            userLat: userLat,
                            userLng: userLng,
                          ),
                        ))
                    .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Đóng",
                style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalCard({
    required BuildContext ctx,
    required Hospital hospital,
    required double userLat,
    required double userLng,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        context.go('/navigation', extra: {
          'hospital': hospital,
          'userLat': userLat,
          'userLng': userLng,
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: const Color(0xFFE5F1F1)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4FAFA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_hospital_rounded,
                  color: Color(0xFF006A71), size: 28),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hospital.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF2C3E50))),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: Color(0xFF7F8C8D)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(hospital.address,
                            style: const TextStyle(
                                color: Color(0xFF7F8C8D), fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.circle,
                          size: 8,
                          color: hospital.openStatus.contains('mở cửa') ||
                                  hospital.openStatus.contains('24/7')
                              ? Colors.green
                              : Colors.orange),
                      const SizedBox(width: 4),
                      Text(hospital.openStatus,
                          style: TextStyle(
                              color: hospital.openStatus.contains('mở cửa') ||
                                      hospital.openStatus.contains('24/7')
                                  ? Colors.green
                                  : Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            // Directions button
            Container(
              margin: const EdgeInsets.only(left: 4, top: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF006A71),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.directions_rounded,
                  color: Colors.white, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFA),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 4),
              _buildSpeechBubble(context),
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
                color: Colors.black.withValues(alpha: 0.03),
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
                          strokeWidth: 3, color: Color(0xFF006A71)),
                    ),
                  ),
                )
              : TypewriterText(
                  _currentReply,
                  onFinished: () {
                    if (_onReplyFinishedAction != null) {
                      _onReplyFinishedAction!();
                      _onReplyFinishedAction = null;
                    }
                  },
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

  Widget _buildRobotMascot(BuildContext context) {
    const double heartWidth = 350.0;
    const double heartHeight = 350.0;
    const double heartBottomOffset = -5;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF96F1FA).withValues(alpha: 0.4),
                blurRadius: 60,
                spreadRadius: 20,
              ),
            ],
          ),
        ),
        Image.asset('assets/mascot.png', width: 320, height: 320, fit: BoxFit.contain),
        GestureDetector(
          onTapDown: (_) {
            setState(() => _isHeartPressed = true);
            // Proactively request GPS permission here (User initiated!)
            // This ensures Chrome shows the location prompt immediately
            mapService.getCurrentLocation();
          },
          onTapUp: (_) {
            setState(() => _isHeartPressed = false);
            _sendMessage("Giả lập thu âm...");
          },
          onTapCancel: () => setState(() => _isHeartPressed = false),
          child: SizedBox(
            width: heartWidth,
            height: heartHeight,
            child: AnimatedCrossFade(
              firstChild: Image.asset('assets/heart_normal.png',
                  fit: BoxFit.contain, width: heartWidth, height: heartHeight),
              secondChild: Image.asset('assets/heart_pressed.png',
                  fit: BoxFit.contain, width: heartWidth, height: heartHeight),
              crossFadeState: _isHeartPressed
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 150),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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

// ─── SpeechBubble painter ────────────────────────────────────────────────────
class SpeechBubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2 - 15, size.height)
      ..lineTo(size.width / 2, size.height + 15)
      ..lineTo(size.width / 2 + 15, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Typewriter animation ─────────────────────────────────────────────────────
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration typingSpeed;
  final VoidCallback? onFinished;

  const TypewriterText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.typingSpeed = const Duration(milliseconds: 20),
    this.onFinished,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = "";
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      _displayedText = "";
      _currentIndex = 0;
      _startTyping();
    }
  }

  void _startTyping() {
    if (widget.text.isEmpty) {
      if (mounted) setState(() => _displayedText = "");
      return;
    }
    _timer = Timer.periodic(widget.typingSpeed, (timer) {
      if (_currentIndex < widget.text.length) {
        if (mounted) {
          setState(() {
            _currentIndex++;
            _displayedText = widget.text.substring(0, _currentIndex);
          });
        }
      } else {
        timer.cancel();
        widget.onFinished?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(_displayedText, style: widget.style, textAlign: widget.textAlign);
}
