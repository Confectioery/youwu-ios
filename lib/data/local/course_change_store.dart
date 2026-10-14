import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/course_change.dart';

/// 课程异动存储
class CourseChangeStore {
  static const _key = 'course_changes';

  Future<void> save(List<CourseChange> changes) async {
    final prefs = await SharedPreferences.getInstance();
    final list = changes.map((c) => c.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }

  Future<List<CourseChange>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => CourseChange.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
