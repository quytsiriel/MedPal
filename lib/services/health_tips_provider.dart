/// Singleton đơn giản để chia sẻ lời khuyên sức khỏe từ Agent 1
/// sang màn hình Nhắc nhở (Prescription tab).
class HealthTipsProvider {
  HealthTipsProvider._();
  static final HealthTipsProvider instance = HealthTipsProvider._();

  /// Tên / mô tả tình trạng bệnh (từ reply của Agent 1)
  String? conditionSummary;

  /// Danh sách thứ nên kiêng
  List<String> avoid = [];

  /// Danh sách thứ nên làm
  List<String> doList = [];

  /// Dấu hiệu cần đi khám ngay
  String? whenToSeeDoctor;

  bool get hasTips => avoid.isNotEmpty || doList.isNotEmpty;

  /// Lưu tips từ response của Agent 1
  void save({
    required Map<String, dynamic> selfCareTips,
    String? condition,
  }) {
    conditionSummary = condition;
    avoid = List<String>.from(selfCareTips['avoid'] ?? []);
    doList = List<String>.from(selfCareTips['do'] ?? []);
    whenToSeeDoctor = selfCareTips['when_to_see_doctor'] as String?;
  }

  void clear() {
    conditionSummary = null;
    avoid = [];
    doList = [];
    whenToSeeDoctor = null;
  }
}
