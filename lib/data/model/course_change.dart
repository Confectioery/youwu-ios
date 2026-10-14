/// 课程异动类型
enum ChangeType { added, changed, removed }

ChangeType changeTypeFromString(String s) {
  switch (s) {
    case 'added':
      return ChangeType.added;
    case 'changed':
      return ChangeType.changed;
    case 'removed':
      return ChangeType.removed;
    default:
      return ChangeType.changed;
  }
}

String changeTypeToString(ChangeType t) => t.name;

/// 课程异动记录
class CourseChange {
  final ChangeType type;
  final String course;
  final String detail;
  final DateTime detectedAt;

  const CourseChange({
    required this.type,
    required this.course,
    required this.detail,
    required this.detectedAt,
  });

  factory CourseChange.fromJson(Map<String, dynamic> json) => CourseChange(
        type: changeTypeFromString(json['type'] as String? ?? 'changed'),
        course: json['course'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        detectedAt: DateTime.fromMillisecondsSinceEpoch((json['detected_at'] as num?)?.toInt() ?? 0),
      );

  Map<String, dynamic> toJson() => {
        'type': changeTypeToString(type),
        'course': course,
        'detail': detail,
        'detected_at': detectedAt.millisecondsSinceEpoch,
      };
}
