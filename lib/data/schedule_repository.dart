import 'dart:convert';
import 'model/course_block.dart';
import 'model/cached_schedule.dart';
import 'model/course_change.dart';
import 'model/term_spec.dart';
import 'term_calculator.dart';
import 'local/schedule_cache.dart';
import 'local/settings_store.dart';
import 'local/crypto.dart';
import 'local/course_change_store.dart';
import 'school/school_api.dart';

/// 课表同步结果
sealed class SyncOutcome {
  const SyncOutcome();
}

class SyncSuccess extends SyncOutcome {
  final CachedSchedule schedule;
  const SyncSuccess(this.schedule);
}

class SyncFailure extends SyncOutcome {
  final String message;
  const SyncFailure(this.message);
}

/// 课表仓库：登录教务系统 -> 拉取课表 -> 解析 -> 缓存 -> 异动检测
class ScheduleRepository {
  final SettingsStore settings;
  final ScheduleCache cache;
  final CourseChangeStore changes;
  final SchoolApi _api = SchoolApi();

  ScheduleRepository({
    SettingsStore? settings,
    ScheduleCache? cache,
    CourseChangeStore? changes,
  })  : settings = settings ?? SettingsStore(),
        cache = cache ?? ScheduleCache(),
        changes = changes ?? CourseChangeStore();

  /// 同步课表
  /// [requested] 指定学期，null时自动选择当前学期
  /// [onLog] 进度日志回调
  Future<SyncOutcome> sync({
    TermSpec? requested,
    void Function(String)? onLog,
  }) async {
    onLog?.call('启动获取引擎…');

    final account = await settings.account;
    if (account.isEmpty) {
      return const SyncFailure('尚未绑定账号');
    }

    final passwordEnc = await settings.passwordEnc;
    final password = CryptoUtil.decrypt(passwordEnc);
    if (password == null) {
      return const SyncFailure('本地密码解密失败，请重新登录');
    }

    final calendarTerm = TermCalculator.autoTerm();
    final cached = await cache.loadLatest();
    final cachedTerm = cached != null && cached.courses.isNotEmpty
        ? TermSpec(cached.xnm, cached.term)
        : null;
    final target = requested ?? TermCalculator.automaticTarget(calendarTerm, cached);

    onLog?.call('当前目标为 ${target.xnm}-${target.xnm + 1} 学年第 ${target.term} 学期');

    try {
      onLog?.call('登录教务系统…');
      final loginOk = await _api.login(account, password);
      if (!loginOk) {
        return const SyncFailure('教务系统登录失败，请检查学号和密码');
      }

      onLog?.call('获取 ${target.xnm}-${target.xnm + 1} 学年第 ${target.term} 学期课表…');
      final raw = await _api.fetchSchedule(target.xnm, target.term);

      onLog?.call('解析课程数据…');
      final schedule = _parseSchedule(raw, account, target);
      if (schedule == null) {
        return const SyncFailure('课表解析失败');
      }
      if (schedule.courses.isEmpty) {
        return const SyncFailure('该学期暂无课表数据，已保留上次成功获取的课程');
      }

      onLog?.call('检测课程异动并写入缓存…');
      final now = DateTime.now();
      final oldCached = await cache.load(target);
      final detected = (oldCached != null &&
              oldCached.xnm == schedule.xnm &&
              oldCached.term == schedule.term &&
              oldCached.courses.isNotEmpty)
          ? _diffSchedule(oldCached, schedule, now)
          : <CourseChange>[];

      await cache.save(schedule);
      await changes.save(detected);
      await settings.setLastSync(target.xnm, target.term, now);

      onLog?.call('完成：共 ${schedule.courses.length} 门课程');
      return SyncSuccess(schedule);
    } catch (e) {
      return SyncFailure('同步失败: ${e.toString()}');
    }
  }

  /// 解析教务系统返回的课表JSON
  CachedSchedule? _parseSchedule(Map<String, dynamic> raw, String account, TermSpec term) {
    final items = raw['courses'] as List? ?? [];
    final blocks = <CourseBlock>[];

    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final name = m['course'] as String? ?? '';
      if (name.isEmpty) continue;
      final day = (m['week_day'] as num?)?.toInt() ?? 1;
      if (day < 1 || day > 7) continue;
      final weeksArr = m['weeks_arr'] as List?;
      final weeks = weeksArr?.map((e) => (e as num).toInt()).where((w) => w > 0).toList() ?? [];
      if (weeks.isEmpty) continue;

      final section = m['section'] as String? ?? '1';
      final se = CourseBlock.fromJson({'section': section});

      blocks.add(CourseBlock(
        name: name,
        place: m['place'] as String? ?? '',
        teacher: m['teacher'] as String? ?? '',
        campus: m['campus'] as String? ?? '',
        dayOfWeek: day,
        startPeriod: se.startPeriod,
        endPeriod: se.endPeriod,
        weeks: weeks,
        weeksText: m['weeks_text'] as String? ?? '',
      ));
    }

    // 同课程同时段合并周次
    final merged = <String, CourseBlock>{};
    for (final b in blocks) {
      final key = '${b.name}|${b.dayOfWeek}|${b.startPeriod}|${b.endPeriod}|${b.place}|${b.teacher}';
      final prev = merged[key];
      merged[key] = prev == null
          ? b
          : prev.copyWith(weeks: [...prev.weeks, ...b.weeks].toSet().toList()..sort());
    }
    final sorted = merged.values.toList()
      ..sort((a, b) {
        if (a.dayOfWeek != b.dayOfWeek) return a.dayOfWeek.compareTo(b.dayOfWeek);
        return a.startPeriod.compareTo(b.startPeriod);
      });

    final student = StudentInfo(
      name: raw['username'] as String? ?? '',
      studentId: account,
      className: raw['class_name'] as String? ?? '',
    );

    return CachedSchedule(
      xnm: term.xnm,
      term: term.term,
      fetchedAt: DateTime.now(),
      student: student,
      courses: sorted,
    );
  }

  /// 课程异动对比：新增 / 取消 / 调整
  List<CourseChange> _diffSchedule(CachedSchedule old, CachedSchedule nw, DateTime now) {
    final oldByName = <String, List<CourseBlock>>{};
    final newByName = <String, List<CourseBlock>>{};
    for (final c in old.courses) {
      oldByName.putIfAbsent(c.name, () => []).add(c);
    }
    for (final c in nw.courses) {
      newByName.putIfAbsent(c.name, () => []).add(c);
    }

    final out = <CourseChange>[];

    for (final entry in newByName.entries) {
      final name = entry.key;
      final newList = entry.value;
      final oldList = oldByName[name];
      if (oldList == null) {
        final min = newList.reduce((a, b) => a.startPeriod < b.startPeriod ? a : b);
        out.add(CourseChange(
          type: ChangeType.added,
          course: name,
          detail: '新增 ${min.slotDesc}',
          detectedAt: now,
        ));
      } else {
        final oldKey = oldList.map((c) => '${c.dayOfWeek}|${c.startPeriod}|${c.endPeriod}|${c.place}').toSet();
        final newKey = newList.map((c) => '${c.dayOfWeek}|${c.startPeriod}|${c.endPeriod}|${c.place}').toSet();
        if (oldKey.length != newKey.length || oldKey.intersection(newKey).length != oldKey.length) {
          final o = oldList.reduce((a, b) => a.startPeriod < b.startPeriod ? a : b);
          final n = newList.reduce((a, b) => a.startPeriod < b.startPeriod ? a : b);
          out.add(CourseChange(
            type: ChangeType.changed,
            course: name,
            detail: '${o.slotDesc} → ${n.slotDesc}',
            detectedAt: now,
          ));
        }
      }
    }

    for (final entry in oldByName.entries) {
      final name = entry.key;
      if (!newByName.containsKey(name)) {
        final min = entry.value.reduce((a, b) => a.startPeriod < b.startPeriod ? a : b);
        out.add(CourseChange(
          type: ChangeType.removed,
          course: name,
          detail: '取消 ${min.slotDesc}',
          detectedAt: now,
        ));
      }
    }

    const order = {ChangeType.changed: 0, ChangeType.added: 1, ChangeType.removed: 2};
    out.sort((CourseChange a, CourseChange b) {
      final oa = order[a.type] ?? 3;
      final ob = order[b.type] ?? 3;
      if (oa != ob) return oa.compareTo(ob);
      return a.course.compareTo(b.course);
    });
    return out;
  }

  void dispose() => _api.close();
}
