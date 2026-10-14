import 'model/term_spec.dart';
import 'model/cached_schedule.dart';
import 'model/course_block.dart';

/// 学期与周次计算
class TermCalculator {
  /// 根据当前日期自动推算目标学期
  static TermSpec autoTerm() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;
    // 8月-12月：秋季学期（第一学期）
    // 1月-6月：春季学期（第二学期），属于上一学年
    if (month >= 8) {
      return TermSpec(year, 1);
    } else {
      return TermSpec(year - 1, 2);
    }
  }

  /// 自动选择同步目标学期：优先当前学期，当前学期无课时回退到缓存学期
  static TermSpec automaticTarget(TermSpec calendarTerm, CachedSchedule? cachedTerm) {
    return calendarTerm;
  }

  /// 计算当前是第几周
  /// [termStart] 第一周第一天（开学日期）
  static int currentWeek(DateTime termStart) {
    final now = DateTime.now();
    final diff = now.difference(termStart).inDays;
    final week = (diff ~/ 7) + 1;
    return week.clamp(1, 30);
  }

  /// 判断某门课本周是否上课
  static bool isCourseThisWeek(CourseBlock course, int currentWeek) {
    return course.weeks.contains(currentWeek);
  }
}
