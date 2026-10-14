import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/cached_schedule.dart';
import '../model/term_spec.dart';

/// 课表本地缓存（JSON存储）
class ScheduleCache {
  static const _keyPrefix = 'schedule_cache_';

  /// 保存课表，返回是否为最新学期
  Future<bool> save(CachedSchedule schedule) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix${schedule.xnm}_${schedule.term}';
    await prefs.setString(key, jsonEncode(schedule.toJson()));
    return true;
  }

  /// 加载指定学期课表
  Future<CachedSchedule?> load(TermSpec term) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix${term.xnm}_${term.term}';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return CachedSchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 加载最近一次有课的课表
  Future<CachedSchedule?> loadLatest() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
    if (keys.isEmpty) return null;
    // 按学年学期倒序，取最新的
    keys.sort((a, b) => b.compareTo(a));
    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        try {
          final s = CachedSchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          if (s.courses.isNotEmpty) return s;
        } catch (_) {}
      }
    }
    return null;
  }

  /// 清除指定学期缓存
  Future<void> clear(TermSpec term) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix${term.xnm}_${term.term}');
  }
}
