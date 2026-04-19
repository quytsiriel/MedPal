import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';
import '../services/audio_reader.dart';
import '../services/map_service.dart';
import '../providers/navigation_provider.dart';
import '../providers/session_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final bool isFollowUp;
  const HomeScreen({super.key, this.isFollowUp = false});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isHeartPressed = false;
  bool _isLoading = false;
  String _currentReply = "MedPal đang chuẩn bị...";
  String? _currentSessionId;
  bool _showHospitalRecommendations = false;
  final TextEditingController _typeController = TextEditingController();
  List<Hospital> _nearbyHospitals = []; // State for dynamic hospitals


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

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When returning to Khám bệnh tab after finishing Navigation
    if (!oldWidget.isFollowUp && widget.isFollowUp) {
      setState(() {
        _isLoading = false;
        _showHospitalRecommendations = false;
        _currentReply = "Chúc mừng bạn đã đến nơi.\nBác sĩ có yêu cầu bạn tới khoa nào khác không?";
      });
    }
    // If we were in follow-up mode and now we are not, reset the session
    else if (oldWidget.isFollowUp && !widget.isFollowUp) {
      _startSession();
    }
  }

  // 1. Quản lý trạng thái Session
  Future<void> _startSession() async {
    setState(() => _isLoading = true);
    
    if (widget.isFollowUp) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentReply = "Chúc mừng bạn đã đến nơi.\nBác sĩ có yêu cầu bạn tới khoa nào khác không?";
        });
      }
      return;
    }

    try {
      final res = await apiService.startSession();
      if (mounted) {
        setState(() {
          _currentSessionId = res['session_id'];
          // Luu session ID vao global provider de Agent 3 co the doc
          ref.read(sessionProvider.notifier).setActiveSession(_currentSessionId!);
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
    if (text.trim().isEmpty) return;
    if (!widget.isFollowUp && _currentSessionId == null) return;

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

    /* 
    if (inputLower.contains("bệnh viện")) {
      _showHospitalRecommendationsDialog();
    }
    */

    if (widget.isFollowUp) {
       await _handleFollowUpResponse(text);
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

      final reply = response['reply'] ?? "Lỗi: Không nhận được câu trả lời từ AI.";

      setState(() {
        _isLoading = false;
        _currentReply = reply;
        // Check stage to update UI state if needed
        if (response['stage'] == 'completed' || response['stage'] == 'complete_visit' || response['stage'] == 'complete_no_visit') {
          _showHospitalRecommendations = true;
          // Thong bao cho global provider de Agent 3 tu dong nhan du lieu
          if (_currentSessionId != null) {
            ref.read(sessionProvider.notifier).markCompleted(_currentSessionId!);
          }
        }
      });

      // Nếu Gemini phân loại đây là khẩn cấp
      if (response['emergency'] == true) {
        _showSeverityConfirmDialog(); // Bật Popup đỏ
      }
      // Nếu Gemini nhận thấy đã thu thập đủ -> Đề xuất bệnh viện
      else if (response['stage'] == 'completed' || 
               response['stage'] == 'complete_visit' ||
               reply.toLowerCase().contains("bệnh viện") ||
               reply.contains("Hệ thống sẽ giúp bạn tìm bệnh viện phù hợp gần nhất")) {
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

  // --- Follow-up Logic for new department routing ---
  Future<void> _handleFollowUpResponse(String userText) async {
    setState(() => _isLoading = true);
    final userLower = userText.trim().toLowerCase();

    if (userLower.contains("không") || userLower.contains("no") || userLower.contains("chưa")) {
      setState(() {
        _currentReply = "Chúc bạn khám bệnh thành công!";
        _isLoading = false;
      });
      // Delay briefly then reset to home for a fresh session if desired
      await Future.delayed(const Duration(seconds: 3));
      if (mounted && widget.isFollowUp) {
        context.go('/'); 
      }
      return;
    }

    // Attempt to match department and redirect directly to indoor navigation
    try {
      final success = await ref.read(navigationProvider.notifier).setDepartmentFromFollowUp(userText);
      
      if (success) {
        final navState = ref.read(navigationProvider);
        if (mounted) {
          setState(() {
            _currentReply = "Đã tìm thấy thông tin. Đang điều hướng bạn tới ${navState.targetDepartment} tại Bệnh viện E...";
          });
        }
        // Short pause to let them read the canonical name
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          context.go('/navigation');
          // Reset câu thoại ngay lập tức để khi ứng dụng văng ngược lại từ Agent 2 sẽ không bị kẹt câu cũ
          setState(() {
            _currentReply = "Chúc mừng bạn đã đến nơi.\nBác sĩ có yêu cầu bạn tới khoa nào khác không?";
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentReply = "Không tìm thấy khoa bạn cần. Bác sĩ có yêu cầu bạn đến với khoa nào khác không?";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentReply = "Lỗi tra soát: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
        // Automatically request GPS location silently in the background
        mapService.getCurrentLocation();
        
        final filePath = await createRecordingPath();
        final config = const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        );
        await _audioRecorder.start(config, path: filePath);
        _recordTimer?.cancel();
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

    if (path == null) return;
    
    // In Follow-up mode, we use a temporary session ID to just get transcription
    final String sessionToUse = _currentSessionId ?? 'temp_voice_session';

    setState(() {
      _isLoading = true;
      _currentReply = '🎤 Đang nhận dạng giọng nói...';
    });

    try {
      final bytes = await readRecordedAudio(path);
      final base64Audio = base64Encode(bytes);

      final response = await apiService.chatSymptom(
        sessionId: sessionToUse,
        voiceBase64: base64Audio,
      );

      final transcript = response['transcript'] as String?;
      if (transcript != null) {
         if (widget.isFollowUp) {
            // Use the transcription-only response to handle navigation
            await _handleFollowUpResponse(transcript);
         } else {
            final reply = response['reply'] ?? "Tôi đã nhận được tin nhắn giọng nói của bạn.";
            setState(() {
              _currentReply = reply;
            });
            
             if (response['stage'] == 'completed' || response['stage'] == 'complete_visit') {
                setState(() => _showHospitalRecommendations = true);
             }
         }
      }
    } catch (e) {
      // HANDLE 404 Session Not Found by falling back to transcription only
      if (e.toString().contains("404") && widget.isFollowUp) {
        try {
          final bytes = await readRecordedAudio(path);
          final base64Audio = base64Encode(bytes);
          final transcribeRes = await apiService.transcribe(base64Audio);
          final text = transcribeRes['transcript'];
          if (text != null) {
            await _handleFollowUpResponse(text);
          }
          return;
        } catch (innerE) {
           print("Transcription fallback failed: $innerE");
        }
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentReply = 'Lỗi nhận dạng giọng nói: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
              const SizedBox(height: 16),
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
               : Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     AnimatedTypewriterText(
                       text: _currentReply,
                       textAlign: TextAlign.center,
                       style: const TextStyle(
                         fontSize: 20,
                         fontWeight: FontWeight.bold,
                         color: Color(0xFF006B70),
                         height: 1.4,
                       ),
                     ),
                     if (_showHospitalRecommendations) ...[
                       const SizedBox(height: 16),
                       SizedBox(
                         width: double.infinity,
                         child: ElevatedButton.icon(
                           onPressed: _showHospitalRecommendationsDialog,
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
                   ],
                 ),
        ),
      ),
    );
  }

  void _showHospitalRecommendationsDialog() async {
    // 1. Fetch real nearby hospitals if not already fetched
    if (_nearbyHospitals.isEmpty) {
      final loc = await mapService.getCurrentLocation();
      if (loc != null) {
        _nearbyHospitals = await apiService.getNearbyHospitals(loc.lat, loc.lng);
      }
    }

    // 2. Prepare the list: Bệnh viện E first, then 2 real nearest
    List<Hospital> displayList = [];
    
    // Hardcode BV E as primary choice for Demo
    displayList.add(Hospital(
      name: "Bệnh viện E",
      address: "89 Trần Cung, Nghĩa Tân, Cầu Giấy, Hà Nội",
      openStatus: "Đang mở cửa",
      lat: 21.0463,
      lng: 105.7865,
      photoUrl: "assets/benhvien_e.jpg",
    ));

    // Add up to 2 more from real API results (avoid duplicating BV E if it's there)
    for (var h in _nearbyHospitals) {
      if (displayList.length >= 3) break;
      if (!h.name.contains("Bệnh viện E")) {
        displayList.add(h);
      }
    }

    // Fallback if API results are thin
    if (displayList.length < 3) {
      displayList.add(Hospital(
        name: "Phòng khám Đa khoa Thu Cúc",
        address: "286 Thụy Khuê, Tây Hồ, Hà Nội",
        openStatus: "Đang mở cửa",
        lat: 21.0375,
        lng: 105.8038,
      ));
    }

    if (!mounted) return;

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
                "Đề xuất cho bạn",
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
            children: displayList.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildHospitalCard(
                ctx,
                h.name,
                "Cách đây ~1km", // Simplified for UI
                h.openStatus,
                photoUrl: h.photoUrl,
                lat: h.lat,
                lng: h.lng,
                address: h.address,
              ),
            )).toList(),
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
    String? photoUrl,
    double lat = 0.0,
    double lng = 0.0,
    String address = "",
  }) {
    return GestureDetector(
      onTap: () {
        // Capture context and ref before pop if safe, or check mounted after
        final navigationNotifier = ref.read(navigationProvider.notifier);
        
        Navigator.pop(ctx);
        
        if (!mounted) return;
        
        // Dispatch to navigationProvider
        final hospital = Hospital(
          name: name,
          address: address,
          openStatus: status,
          lat: lat,
          lng: lng,
          photoUrl: photoUrl,
        );
        navigationNotifier.setHospital(hospital, null, null);
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
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFF4FAFA),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.hardEdge,
              child: photoUrl != null 
                ? (photoUrl.startsWith('http') 
                    ? Image.network(photoUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.local_hospital_rounded, color: Color(0xFF006A71), size: 28))
                    : Image.asset(photoUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.local_hospital_rounded, color: Color(0xFF006A71), size: 28)))
                : const Icon(Icons.local_hospital_rounded, color: Color(0xFF006A71), size: 28),
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
                final hospital = Hospital(name: name, address: address, openStatus: status, lat: lat, lng: lng, photoUrl: photoUrl);
                ref.read(navigationProvider.notifier).setHospital(hospital, null, null);
                context.go('/navigation');
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
                hintText: widget.isFollowUp ? "Nhập tên khoa hoặc 'Không'..." : "Nhập triệu chứng...",
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

class AnimatedTypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final Duration speed;

  const AnimatedTypewriterText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
    this.speed = const Duration(milliseconds: 30),
  });

  @override
  State<AnimatedTypewriterText> createState() => _AnimatedTypewriterTextState();
}

class _AnimatedTypewriterTextState extends State<AnimatedTypewriterText> {
  String _displayedText = "";
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(AnimatedTypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _startAnimation();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _timer?.cancel();
    _displayedText = "";
    int index = 0;
    _timer = Timer.periodic(widget.speed, (timer) {
      if (index < widget.text.length) {
        if (mounted) {
          setState(() {
            _displayedText += widget.text[index];
            index++;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: widget.style,
      textAlign: widget.textAlign,
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
