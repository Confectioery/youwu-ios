import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/model/cached_schedule.dart';
import '../../data/model/course_block.dart';
import '../../data/schedule_repository.dart';
import '../../data/term_calculator.dart';
import '../../data/local/settings_store.dart';
import '../../data/local/schedule_cache.dart';

/// 课表页面
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final ScheduleRepository _repo = ScheduleRepository();
  final SettingsStore _settings = SettingsStore();
  final ScheduleCache _cache = ScheduleCache();

  CachedSchedule? _schedule;
  bool _loading = false;
  String? _error;
  int _currentWeek = 1;
  DateTime? _termStart;

  static const List<String> _timeSlots = [
    '08:30', '09:20', '10:25', '11:15',
    '14:40', '15:30', '16:30', '17:20',
    '19:30', '20:20', '21:10', '22:00',
  ];

  static const List<String> _weekDays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    final cached = await _cache.loadLatest();
    final term = cached != null ? TermSpecLocal(cached.xnm, cached.term) : null;
    DateTime? start;
    if (term != null) {
      start = await _settings.getTermStart(term.xnm, term.term);
    }
    setState(() {
      _schedule = cached;
      _termStart = start;
      if (start != null) {
        _currentWeek = TermCalculator.currentWeek(start);
      }
    });
  }

  Future<void> _sync() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.sync(
      onLog: (log) => debugPrint(log),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is SyncSuccess) {
        _schedule = result.schedule;
      } else if (result is SyncFailure) {
        _error = result.message;
      }
    });
    if (result is SyncSuccess) {
      _loadCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表'),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _sync,
            tooltip: '同步课表',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _schedule == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _schedule == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _sync, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_schedule == null || _schedule!.courses.isEmpty) {
      return const Center(child: Text('暂无课表数据，点击右上角同步'));
    }
    return Column(
      children: [
        _buildWeekSelector(),
        Expanded(child: _buildScheduleGrid()),
      ],
    );
  }

  Widget _buildWeekSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('第 $_currentWeek 周', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentWeek > 1 ? () => setState(() => _currentWeek--) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentWeek < 30 ? () => setState(() => _currentWeek++) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleGrid() {
    final showWeekend = true; // 简化处理，实际从设置读取
    final cols = showWeekend ? 7 : 5;
    final courses = _schedule!.courses.where((c) {
      return c.dayOfWeek <= cols && c.weeks.contains(_currentWeek);
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Column(
          children: [
            // 星期表头
            Row(
              children: [
                SizedBox(width: 40, child: Container()),
                ...List.generate(cols, (i) {
                  final isToday = (i + 1) == DateTime.now().weekday;
                  return Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isToday ? Theme.of(context).colorScheme.primaryContainer : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '周${_weekDays[i]}',
                        style: TextStyle(
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isToday ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
            // 课程网格
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(12, (period) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 40,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${period + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ),
                        ),
                        ...List.generate(cols, (day) {
                          final course = courses.where((c) =>
                              c.dayOfWeek == day + 1 &&
                              c.startPeriod <= period + 1 &&
                              c.endPeriod >= period + 1).firstOrNull;
                          if (course == null) {
                            return Expanded(
                              child: Container(
                                height: 56,
                                margin: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade200, width: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            );
                          }
                          // 只在课程起始节渲染完整卡片
                          if (course.startPeriod != period + 1) {
                            return Expanded(child: const SizedBox.shrink());
                          }
                          final span = course.endPeriod - course.startPeriod + 1;
                          return Expanded(
                            child: Container(
                              height: 56.0 * span,
                              margin: const EdgeInsets.all(1),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _courseColor(course.name),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    course.name,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    course.place,
                                    style: const TextStyle(fontSize: 9, color: Colors.white70),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    course.teacher,
                                    style: const TextStyle(fontSize: 9, color: Colors.white70),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _courseColor(String name) {
    final colors = [
      const Color(0xFF2D6A4F),
      const Color(0xFF40916C),
      const Color(0xFF52B788),
      const Color(0xFF74C69D),
      const Color(0xFF1B4332),
      const Color(0xFF081C15),
      const Color(0xFF95D5B2),
      const Color(0xFFB7E4C7),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}

/// 本地TermSpec（避免import冲突）
class TermSpecLocal {
  final int xnm;
  final int term;
  const TermSpecLocal(this.xnm, this.term);
}
