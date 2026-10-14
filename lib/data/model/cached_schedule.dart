import 'course_block.dart';

/// 学生信息
class StudentInfo {
  final String name;
  final String studentId;
  final String className;

  const StudentInfo({this.name = '', this.studentId = '', this.className = ''});

  factory StudentInfo.fromJson(Map<String, dynamic> json) => StudentInfo(
        name: json['username'] as String? ?? '',
        studentId: json['student_id'] as String? ?? '',
        className: json['class_name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'username': name,
        'student_id': studentId,
        'class_name': className,
      };
}

/// 缓存的课表数据
class CachedSchedule {
  final int xnm; // 学年，如2026
  final int term; // 学期 1或2
  final DateTime fetchedAt;
  final StudentInfo student;
  final List<CourseBlock> courses;

  const CachedSchedule({
    required this.xnm,
    required this.term,
    required this.fetchedAt,
    required this.student,
    required this.courses,
  });

  factory CachedSchedule.fromJson(Map<String, dynamic> json) {
    final coursesList = (json['courses'] as List? ?? [])
        .map((e) => CourseBlock.fromJson(e as Map<String, dynamic>))
        .toList();
    return CachedSchedule(
      xnm: (json['xnm'] as num?)?.toInt() ?? 0,
      term: (json['term'] as num?)?.toInt() ?? 1,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch((json['fetched_at'] as num?)?.toInt() ?? 0),
      student: StudentInfo.fromJson(json['student'] as Map<String, dynamic>? ?? {}),
      courses: coursesList,
    );
  }

  Map<String, dynamic> toJson() => {
        'xnm': xnm,
        'term': term,
        'fetched_at': fetchedAt.millisecondsSinceEpoch,
        'student': student.toJson(),
        'courses': courses.map((c) => c.toJson()).toList(),
      };
}
