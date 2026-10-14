import 'package:flutter/material.dart';
import '../../data/local/settings_store.dart';
import '../../data/schedule_repository.dart';

/// 我的页面
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SettingsStore _settings = SettingsStore();
  String _account = '';
  String _studentName = '';
  bool _autoUpdate = false;
  bool _showWeekend = false;
  int _termWeeks = 20;
  (int, int, DateTime)? _lastSync;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final account = await _settings.account;
    final autoUpdate = await _settings.autoUpdate;
    final showWeekend = await _settings.showWeekend;
    final termWeeks = await _settings.termWeeks;
    final lastSync = await _settings.lastSync;
    setState(() {
      _account = account;
      _autoUpdate = autoUpdate;
      _showWeekend = showWeekend;
      _termWeeks = termWeeks;
      _lastSync = lastSync;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          // 用户信息
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 32,
                    child: Icon(Icons.person, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _studentName.isEmpty ? '未登录' : _studentName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _account.isEmpty ? '点击绑定教务账号' : '学号: $_account',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (_account.isEmpty)
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: const Text('绑定'),
                    ),
                ],
              ),
            ),
          ),

          // 同步与数据
          _buildSectionTitle('同步与数据'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('立即同步课表'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final repo = ScheduleRepository();
                    final result = await repo.sync();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result is SyncSuccess ? '同步成功' : '同步失败'),
                        ),
                      );
                    }
                    _loadSettings();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('上次同步'),
                  subtitle: Text(_lastSync == null
                      ? '从未同步'
                      : '${_lastSync!.$1}-${_lastSync!.$1 + 1}学年第${_lastSync!.$2}学期 · ${_formatDate(_lastSync!.$3)}'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew),
                  title: const Text('自动更新课表'),
                  subtitle: const Text('每6小时后台同步'),
                  value: _autoUpdate,
                  onChanged: (v) async {
                    await _settings.setAutoUpdate(v);
                    setState(() => _autoUpdate = v);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          // 课表偏好
          _buildSectionTitle('课表偏好'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.calendar_view_week),
                  title: const Text('显示周末'),
                  value: _showWeekend,
                  onChanged: (v) async {
                    await _settings.setShowWeekend(v);
                    setState(() => _showWeekend = v);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.date_range),
                  title: const Text('学期周数'),
                  trailing: Text('$_termWeeks 周'),
                  onTap: () => _showTermWeeksDialog(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          // 关于
          _buildSectionTitle('关于'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('版本'),
                  trailing: Text('1.1.0'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.code),
                  title: Text('开源许可'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showTermWeeksDialog() {
    showDialog(
      context: context,
      builder: (context) {
        int value = _termWeeks;
        return AlertDialog(
          title: const Text('学期周数'),
          content: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$value 周', style: const TextStyle(fontSize: 24)),
                Slider(
                  value: value.toDouble(),
                  min: 16,
                  max: 25,
                  divisions: 9,
                  label: '$value',
                  onChanged: (v) => setDialogState(() => value = v.toInt()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                await _settings.setTermWeeks(value);
                setState(() => _termWeeks = value);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}
