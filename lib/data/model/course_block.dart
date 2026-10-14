/// 课程块：一门课在某一天某一节次的信息
class CourseBlock {
  final String name;
  final String place;
  final String teacher;
  final String campus;
  final int dayOfWeek; // 1=周一 ... 7=周日
  final int startPeriod;
  final int endPeriod;
  final List<int> weeks; // 上课周次列表
  final String weeksText;

  const CourseBlock({
    required this.name,
    this.place = '',
    this.teacher = '',
    this.campus = '',
    required this.dayOfWeek,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    this.weeksText = '',
  });

  factory CourseBlock.fromJson(Map<String, dynamic> json) {
    final weeksArr = json['weeks_arr'] as List?;
    return CourseBlock(
      name: json['course'] as String? ?? '',
      place: json['place'] as String? ?? '',
      teacher: json['teacher'] as String? ?? '',
      campus: json['campus'] as String? ?? '',
      dayOfWeek: (json['week_day'] as num?)?.toInt() ?? 1,
      startPeriod: _parseSection(json['section'] as String? ?? '1').$1,
      endPeriod: _parseSection(json['section'] as String? ?? '1').$2,
      weeks: weeksArr?.map((e) => (e as num).toInt()).where((w) => w > 0).toList() ?? [],
      weeksText: json['weeks_text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'course': name,
        'place': place,
        'teacher': teacher,
        'campus': campus,
        'week_day': dayOfWeek,
        'section': '$startPeriod-$endPeriod',
        'weeks_arr': weeks,
        'weeks_text': weeksText,
      };

  CourseBlock copyWith({List<int>? weeks}) => CourseBlock(
        name: name,
        place: place,
        teacher: teacher,
        campus: campus,
        dayOfWeek: dayOfWeek,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        weeks: weeks ?? this.weeks,
        weeksText: weeksText,
      );

  /// "1-2" -> (1,2); "3" -> (3,3); "1-2,5-6" 取第一段
  static (int, int) _parseSection(String section) {
    final first = section.split(RegExp(r'[，,]')).firstWhere((s) => s.trim().isNotEmpty, orElse: () => '1');
    final nums = RegExp(r'\d+').allMatches(first).map((m) => int.parse(m.group(0)!)).toList();
    if (nums.isEmpty) return (1, 1);
    if (nums.length == 1) return (nums[0], nums[0]);
    return (nums[0].clamp(1, 12), nums[1].clamp(1, 12));
  }

  String get slotDesc {
    const dowNames = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${dowNames[dayOfWeek - 1]} $startPeriod-${endPeriod}节 · ${place.isEmpty ? "待定" : place}';
  }
}
