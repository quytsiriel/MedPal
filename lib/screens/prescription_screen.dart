import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:convert';
import '../services/api_service.dart';
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

class PrescriptionScreen extends StatefulWidget {
  const PrescriptionScreen({super.key});

  @override
  State<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends State<PrescriptionScreen> {
  final ImagePicker _picker = ImagePicker();
  
  // State for Reminders
  bool _remindersEnabled = true;
  bool _isLoading = false;
  String _summary = "Vui lòng chụp đơn thuốc để AI tự động phân tích.";

  // Mock Data
  late List<Medicine> _medications;

  @override
  void initState() {
    super.initState();
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
        schedule: [
          ScheduleItem(time: '09:00', isTaken: false),
        ],
      ),
    ];
  }

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
              content: Text('Đang dùng AI để phân tích đơn thuốc...', style: GoogleFonts.lexend()),
              backgroundColor: Colors.blueGrey,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }

        final bytes = await pickedFile.readAsBytes();
        final base64Image = base64Encode(bytes);

        // Fetch from Agent 3 API
        final result = await apiService.scanPrescription("user_session", base64Image);

        if (mounted) {
          setState(() {
            _isLoading = false;
            
            // Parse result into List<Medicine>
            if (result['medications'] != null && (result['medications'] as List).isNotEmpty) {
              _medications = (result['medications'] as List).map((medObj) {
                return Medicine(
                  name: medObj['name'] ?? 'Không rõ',
                  dosage: medObj['dosage'] ?? 'Không rõ',
                  icon: medObj['icon'] ?? 'pill',
                  schedule: (medObj['schedule'] as List?)?.map((timeStr) {
                    return ScheduleItem(time: timeStr.toString(), isTaken: false);
                  }).toList() ?? [],
                );
              }).toList();
            }
            if (result['summary'] != null) {
              _summary = result['summary'];
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã phân tích thông tin xong!', style: GoogleFonts.lexend()),
              backgroundColor: const Color(0xFF006A71),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF006A71);
    const Color surfaceColor = Color(0xFFF4FAFA);

    return Scaffold(
      backgroundColor: surfaceColor,
      body: Column(
        children: [
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      // 2. Daily Progress Summary
                      _buildProgressSummary(primaryColor),
                      
                      const SizedBox(height: 24),
                      // 3. Notification Master Toggle
                      _buildReminderToggle(primaryColor),

                      const SizedBox(height: 32),
                      // 4. Section Title
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

                      // 5. Medication List
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
                        ..._medications.map((med) => _buildMedicationCard(med, primaryColor)),

                      const SizedBox(height: 24),
                      // 6. Add More Section
                      _buildAddMoreSection(primaryColor),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }


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
            child: Icon(Icons.notifications_active_rounded, color: primaryColor, size: 24),
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
                  content: Text(val ? 'Đã bật nhắc nhở điện thoại' : 'Đã tắt nhắc nhở'),
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
                med.icon == 'capsule' ? Icons.medication_liquid_rounded :
                med.icon == 'effervescent' ? Icons.bubble_chart_rounded :
                med.icon == 'syrup' ? Icons.local_drink_rounded :
                med.icon == 'injection' ? Icons.vaccines_rounded :
                Icons.medication_rounded,
                color: primaryColor,
              ),
            ),
            title: Text(
              med.name,
              style: GoogleFonts.lexend(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              med.dosage,
              style: GoogleFonts.lexend(color: Colors.grey.shade600, fontSize: 13),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                          isTaken ? Icons.check_circle_rounded : Icons.schedule_rounded,
                          size: 16,
                          color: isTaken ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.time,
                          style: GoogleFonts.lexend(
                            color: isTaken ? Colors.white : Colors.grey.shade700,
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
        border: Border.all(color: primaryColor.withValues(alpha: 0.1), style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          const Icon(Icons.add_photo_alternate_rounded, size: 48, color: Colors.grey),
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
            style: GoogleFonts.lexend(fontSize: 13, color: Colors.grey.shade600),
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
          border: isOutline ? Border.all(color: primaryColor.withValues(alpha: 0.2)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isOutline ? primaryColor : Colors.white),
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
