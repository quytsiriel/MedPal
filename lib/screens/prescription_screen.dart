import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../providers/session_provider.dart';

// --- Models ---
class Medicine {
  final String name;
  final String dosage;
  final List<ScheduleItem> schedule;
  final String icon;

  Medicine({
    required this.name,
    required this.dosage,
    required this.schedule,
    required this.icon,
  });
}

class ScheduleItem {
  final String time;
  bool isTaken;

  ScheduleItem({required this.time, this.isTaken = false});
}

class HealthTip {
  final String category; // "avoid", "do", "warning"
  final String icon;
  final String title;
  final String description;

  HealthTip({
    required this.category,
    required this.icon,
    required this.title,
    required this.description,
  });

  factory HealthTip.fromJson(Map<String, dynamic> json) {
    return HealthTip(
      category: json['category'] ?? 'do',
      icon: json['icon'] ?? 'info',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
    );
  }
}

class PrescriptionScreen extends ConsumerStatefulWidget {
  const PrescriptionScreen({super.key});

  @override
  ConsumerState<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends ConsumerState<PrescriptionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ImagePicker _picker = ImagePicker();

  // --- Tab 1: Prescription State ---
  bool _remindersEnabled = true;
  bool _isLoading = false;
  String _summary = "Vui lòng chụp đơn thuốc để AI tự động phân tích.";
  late List<Medicine> _medications;

  // --- Tab 2: Health Advice State ---
  bool _isAdviceLoading = false;
  String _diagnosisSummary = "";
  List<HealthTip> _healthTips = [];
  String? _adviceError;
  String? _lastFetchedSessionId; // Track which session we already fetched

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _medications = [
      Medicine(
        name: 'Paracetamol 500mg',
        dosage: '1 viên / lần',
        icon: 'pill',
        schedule: [
          ScheduleItem(time: '08:00', isTaken: true),
          ScheduleItem(time: '20:00', isTaken: false),
        ],
      ),
      Medicine(
        name: 'Amoxicillin 250mg',
        dosage: '2 viên / lần',
        icon: 'capsule',
        schedule: [
          ScheduleItem(time: '07:00', isTaken: true),
          ScheduleItem(time: '13:00', isTaken: true),
          ScheduleItem(time: '19:00', isTaken: false),
        ],
      ),
      Medicine(
        name: 'Vitamin C 1000mg',
        dosage: '1 viên sủi',
        icon: 'effervescent',
        schedule: [ScheduleItem(time: '09:00', isTaken: false)],
      ),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Tab 1: Prescription Logic ──────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
      );

      if (pickedFile != null) {
        setState(() {
          _isLoading = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đang dùng AI để phân tích đơn thuốc...',
                style: GoogleFonts.lexend(),
              ),
              backgroundColor: Colors.blueGrey,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }

        final bytes = await pickedFile.readAsBytes();
        final base64Image = base64Encode(bytes);

        // Fetch from Agent 3 API
        final result = await apiService.scanPrescription(
          "user_session",
          base64Image,
        );

        if (mounted) {
          setState(() {
            _isLoading = false;

            // Parse result into List<Medicine>
            if (result['medications'] != null &&
                (result['medications'] as List).isNotEmpty) {
              _medications = (result['medications'] as List).map((medObj) {
                return Medicine(
                  name: medObj['name'] ?? 'Không rõ',
                  dosage: medObj['dosage'] ?? 'Không rõ',
                  icon: medObj['icon'] ?? 'pill',
                  schedule:
                      (medObj['schedule'] as List?)?.map((timeStr) {
                        return ScheduleItem(
                          time: timeStr.toString(),
                          isTaken: false,
                        );
                      }).toList() ??
                      [],
                );
              }).toList();
            }
            if (result['summary'] != null) {
              _summary = result['summary'];
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đã phân tích thông tin xong!',
                style: GoogleFonts.lexend(),
              ),
              backgroundColor: const Color(0xFF006A71),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e', style: GoogleFonts.lexend()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  double _calculateProgress() {
    int total = 0;
    int taken = 0;
    for (var med in _medications) {
      for (var item in med.schedule) {
        total++;
        if (item.isTaken) taken++;
      }
    }
    return total == 0 ? 0 : taken / total;
  }

  // ── Tab 2: Health Advice Logic ──────────────────────

  Future<void> _fetchHealthAdvice([String? overrideSessionId]) async {
    final sessionId =
        overrideSessionId ?? ref.read(sessionProvider).lastSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      setState(
        () => _adviceError =
            "Chưa có phiên khám nào. Hãy khám bệnh với AI trước.",
      );
      return;
    }

    // Guard is now in _buildHealthAdviceTab via fetchKey

    setState(() {
      _isAdviceLoading = true;
      _adviceError = null;
      _healthTips = [];
      _diagnosisSummary = "";
    });

    try {
      final result = await apiService.getHealthAdvice(sessionId);

      if (mounted) {
        setState(() {
          _isAdviceLoading = false;
          _diagnosisSummary = result['diagnosis_summary'] ?? '';
          if (result['tips'] != null) {
            _healthTips = (result['tips'] as List)
                .map((t) => HealthTip.fromJson(t as Map<String, dynamic>))
                .toList();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAdviceLoading = false;
          _adviceError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF006A71);
    const Color surfaceColor = Color(0xFFF4FAFA);

    return Scaffold(
      backgroundColor: surfaceColor,
      body: Column(
        children: [
          // TabBar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: primaryColor,
              indicatorWeight: 3,
              labelColor: primaryColor,
              unselectedLabelColor: Colors.grey,
              labelStyle: GoogleFonts.lexend(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: GoogleFonts.lexend(
                fontWeight: FontWeight.w400,
                fontSize: 14,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.medication_rounded, size: 20),
                  text: 'Đơn thuốc',
                ),
                Tab(
                  icon: Icon(Icons.health_and_safety_rounded, size: 20),
                  text: 'Lời khuyên',
                ),
              ],
            ),
          ),
          // TabBarView
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPrescriptionTab(primaryColor),
                _buildHealthAdviceTab(primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════
  //  TAB 1: ĐƠN THUỐC (Giữ nguyên giao diện cũ)
  // ══════════════════════════════════════════════════

  Widget _buildPrescriptionTab(Color primaryColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildProgressSummary(primaryColor),
            const SizedBox(height: 24),
            _buildReminderToggle(primaryColor),
            const SizedBox(height: 32),
            Text(
              'Lịch uống thuốc hôm nay',
              style: GoogleFonts.lexend(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _summary,
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: Color(0xFF006A71)),
                ),
              )
            else if (_medications.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    'Chưa có thuốc nào trong lịch.',
                    style: GoogleFonts.lexend(color: Colors.grey.shade500),
                  ),
                ),
              )
            else
              ..._medications.map(
                (med) => _buildMedicationCard(med, primaryColor),
              ),
            const SizedBox(height: 24),
            _buildAddMoreSection(primaryColor),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════
  //  TAB 2: LỜI KHUYÊN SỨC KHỎE
  // ══════════════════════════════════════════════════

  Widget _buildHealthAdviceTab(Color primaryColor) {
    // Watch the session state reactively
    final sessionState = ref.watch(sessionProvider);
    final hasSession = sessionState.lastSessionId != null;
    final isCompleted = sessionState.isCompleted;
    final careMode = sessionState.careMode; // 'home' or 'hospital'

    // Build a key that includes refreshToken so we re-fetch when advice is invalidated
    final fetchKey = '${sessionState.lastSessionId}_${sessionState.refreshToken}';

    // Auto-fetch logic based on care mode:
    // - 'home' mode: fetch immediately when session completes (advice from symptoms)
    // - 'hospital' mode: only fetch after doctor conclusion (when invalidateAdvice is called, refreshToken > 0)
    final shouldAutoFetch = isCompleted &&
        hasSession &&
        _lastFetchedSessionId != fetchKey &&
        !_isAdviceLoading &&
        (careMode == 'home' || (careMode == 'hospital' && sessionState.refreshToken > 0));

    if (shouldAutoFetch) {
      // Schedule fetch after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _lastFetchedSessionId = fetchKey;
        _fetchHealthAdvice(sessionState.lastSessionId);
      });
    }

    // Determine header text based on care mode
    String headerText;
    if (!hasSession) {
      headerText = 'Hãy khám bệnh với AI trước để nhận lời khuyên chăm sóc sức khỏe cá nhân hóa.';
    } else if (!isCompleted) {
      headerText = 'Đang trong phiên khám. Hoàn thành khám bệnh để nhận lời khuyên.';
    } else if (careMode == 'hospital') {
      if (_healthTips.isNotEmpty || _isAdviceLoading) {
        headerText = 'Lời khuyên dựa trên kết luận của bác sĩ sau khám.';
      } else {
        headerText = 'Hoàn thành khám bệnh và nhập kết luận bác sĩ để nhận lời khuyên.';
      }
    } else {
      headerText = 'Lời khuyên chăm sóc tại nhà dựa trên triệu chứng của bạn.';
    }

    // Source label
    final String sourceLabel = careMode == 'hospital'
        ? '📋 Nguồn: Kết luận bác sĩ'
        : '🩺 Nguồn: Triệu chứng người dùng';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'MedGemma AI',
                        style: GoogleFonts.lexend(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    headerText,
                    style: GoogleFonts.lexend(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasSession
                              ? (isCompleted ? Icons.check_circle : Icons.sync)
                              : Icons.info_outline,
                          color: Colors.white70,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasSession
                                ? 'Session: ${sessionState.lastSessionId!.substring(0, 8)}...'
                                : 'Chưa có phiên khám',
                            style: GoogleFonts.lexend(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Source indicator
                  if (isCompleted && careMode != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        sourceLabel,
                        style: GoogleFonts.lexend(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  // Manual refresh button if already have data
                  if (isCompleted && _healthTips.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isAdviceLoading
                            ? null
                            : () {
                                _lastFetchedSessionId = null; // Force re-fetch
                                _fetchHealthAdvice();
                              },
                        icon: const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                        label: Text(
                          'Làm mới lời khuyên',
                          style: GoogleFonts.lexend(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Loading indicator
            if (_isAdviceLoading)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF006A71)),
                    const SizedBox(height: 16),
                    Text(
                      'MedGemma đang phân tích dữ liệu bệnh lý...',
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Quá trình này có thể mất 30-60 giây',
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),

            // Error Message
            if (_adviceError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _adviceError!,
                        style: GoogleFonts.lexend(
                          color: Colors.red.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Diagnosis Summary
            if (_diagnosisSummary.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.summarize_rounded,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tóm tắt tình trạng',
                          style: GoogleFonts.lexend(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _diagnosisSummary,
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: Colors.blue.shade900,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Tips grouped by category
            if (_healthTips.isNotEmpty) ...[
              // AVOID tips
              ..._buildTipSection(
                title: 'Nên tránh',
                icon: Icons.block_rounded,
                color: Colors.red.shade600,
                bgColor: Colors.red.shade50,
                borderColor: Colors.red.shade200,
                tips: _healthTips.where((t) => t.category == 'avoid').toList(),
              ),

              // DO tips
              ..._buildTipSection(
                title: 'Nên làm',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF28A745),
                bgColor: const Color(0xFFEEF9F0),
                borderColor: const Color(0xFFC3E6CB),
                tips: _healthTips.where((t) => t.category == 'do').toList(),
              ),

              // WARNING tips
              ..._buildTipSection(
                title: 'Cảnh báo quan trọng',
                icon: Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                bgColor: Colors.orange.shade50,
                borderColor: Colors.orange.shade200,
                tips: _healthTips
                    .where((t) => t.category == 'warning')
                    .toList(),
              ),
            ],

            // Empty state — different based on careMode
            if (_healthTips.isEmpty &&
                !_isAdviceLoading &&
                _adviceError == null &&
                _diagnosisSummary.isEmpty)
              _buildEmptyAdviceState(hasSession, isCompleted, careMode),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAdviceState(bool hasSession, bool isCompleted, String? careMode) {
    IconData icon;
    String title;
    String subtitle;

    if (!hasSession) {
      icon = Icons.health_and_safety_outlined;
      title = 'Chưa có lời khuyên nào';
      subtitle = 'Hãy bắt đầu khám bệnh với AI ở tab "Khám bệnh" để nhận lời khuyên sức khỏe cá nhân hóa.';
    } else if (!isCompleted) {
      icon = Icons.hourglass_empty_rounded;
      title = 'Đang trong phiên khám';
      subtitle = 'Hoàn thành phiên khám với AI Agent 1 để nhận lời khuyên tự động.';
    } else if (careMode == 'hospital') {
      icon = Icons.local_hospital_rounded;
      title = 'Chờ kết luận bác sĩ';
      subtitle = 'Sau khi khám xong, hãy nhập kết luận của bác sĩ tại màn hình điều hướng để nhận lời khuyên từ MedGemma.';
    } else {
      icon = Icons.hourglass_empty_rounded;
      title = 'Đang chuẩn bị lời khuyên...';
      subtitle = 'Lời khuyên sẽ được tự động tạo sau khi hoàn thành phiên khám.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.lexend(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 13,
                color: Colors.grey.shade400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTipSection({
    required String title,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required List<HealthTip> tips,
  }) {
    if (tips.isEmpty) return [];

    return [
      Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.lexend(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ...tips.map(
        (tip) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tip.title,
                style: GoogleFonts.lexend(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tip.description,
                style: GoogleFonts.lexend(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  // ══════════════════════════════════════════════════
  //  SHARED WIDGETS (Tab 1)
  // ══════════════════════════════════════════════════

  Widget _buildProgressSummary(Color primaryColor) {
    double progress = _calculateProgress();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: GoogleFonts.lexend(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tiến độ uống thuốc',
                  style: GoogleFonts.lexend(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bạn đã hoàn thành ${(_medications.expand((m) => m.schedule).where((i) => i.isTaken).length)} / ${_medications.expand((m) => m.schedule).length} liều hôm nay.',
                  style: GoogleFonts.lexend(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderToggle(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nhắc nhở qua điện thoại',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: const Color(0xFF2C3E50),
                  ),
                ),
                Text(
                  'Gửi thông báo đẩy khi đến giờ',
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _remindersEnabled,
            activeColor: primaryColor,
            onChanged: (val) {
              setState(() => _remindersEnabled = val);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    val ? 'Đã bật nhắc nhở điện thoại' : 'Đã tắt nhắc nhở',
                  ),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(Medicine med, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                med.icon == 'capsule'
                    ? Icons.medication_liquid_rounded
                    : med.icon == 'effervescent'
                    ? Icons.bubble_chart_rounded
                    : med.icon == 'syrup'
                    ? Icons.local_drink_rounded
                    : med.icon == 'injection'
                    ? Icons.vaccines_rounded
                    : Icons.medication_rounded,
                color: primaryColor,
              ),
            ),
            title: Text(
              med.name,
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              med.dosage,
              style: GoogleFonts.lexend(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
            trailing: const Icon(Icons.more_vert_rounded),
          ),
          Container(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: med.schedule.map((item) {
                bool isTaken = item.isTaken;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      item.isTaken = !item.isTaken;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isTaken ? primaryColor : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isTaken ? primaryColor : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isTaken
                              ? Icons.check_circle_rounded
                              : Icons.schedule_rounded,
                          size: 16,
                          color: isTaken ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.time,
                          style: GoogleFonts.lexend(
                            color: isTaken
                                ? Colors.white
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMoreSection(Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.1),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.add_photo_alternate_rounded,
            size: 48,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            'Thêm đơn thuốc mới',
            style: GoogleFonts.lexend(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: const Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Quét thêm đơn thuốc để tự động cập nhật lịch.',
            textAlign: TextAlign.center,
            style: GoogleFonts.lexend(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSmallActionButton(
                  onTap: () => _pickImage(ImageSource.camera),
                  icon: Icons.photo_camera_rounded,
                  label: 'Máy ảnh',
                  primaryColor: primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSmallActionButton(
                  onTap: () => _pickImage(ImageSource.gallery),
                  icon: Icons.image_rounded,
                  label: 'Thư viện',
                  primaryColor: primaryColor,
                  isOutline: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallActionButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Color primaryColor,
    bool isOutline = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isOutline ? Colors.white : primaryColor,
          borderRadius: BorderRadius.circular(12),
          border: isOutline
              ? Border.all(color: primaryColor.withValues(alpha: 0.2))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isOutline ? primaryColor : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isOutline ? primaryColor : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
