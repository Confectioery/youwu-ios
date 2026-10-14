import 'package:flutter/material.dart';
import '../../data/local/settings_store.dart';
import '../../data/local/crypto.dart';
import '../../data/schedule_repository.dart';

/// 初次设置引导页（欢迎 -> 教务 -> 服务 -> 偏好 -> 完成）
class WelcomeScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const WelcomeScreen({super.key, required this.onComplete});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController();
  final SettingsStore _settings = SettingsStore();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();

  int _currentStep = 0;
  bool _loggingIn = false;
  String? _loginError;
  bool _showWeekend = false;
  int _termWeeks = 20;

  static const List<_WelcomeStep> _steps = [
    _WelcomeStep(title: '欢迎', subtitle: '校园大小事，有梧搞定', icon: Icons.school),
    _WelcomeStep(title: '教务登录', subtitle: '使用学号和教务密码登录，自动同步课表', icon: Icons.login),
    _WelcomeStep(title: '服务绑定', subtitle: '绑定饮水和洗澡设备（可稍后设置）', icon: Icons.settings_bluetooth),
    _WelcomeStep(title: '课表偏好', subtitle: '设置学期周数和周末显示', icon: Icons.tune),
    _WelcomeStep(title: '完成', subtitle: '一切就绪，开始使用有梧', icon: Icons.check_circle),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _loginError = '请输入学号和密码');
      return;
    }
    setState(() {
      _loggingIn = true;
      _loginError = null;
    });

    // 保存账号和加密密码
    await _settings.setAccount(account);
    await _settings.setPasswordEnc(CryptoUtil.encrypt(password));

    // 尝试同步课表
    final repo = ScheduleRepository();
    final result = await repo.sync();

    if (!mounted) return;
    setState(() => _loggingIn = false);

    if (result is SyncFailure) {
      setState(() => _loginError = result.message);
      // 即使同步失败也允许继续（账号已保存）
    }
    _nextStep();
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 进度指示器
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: List.generate(_steps.length, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= _currentStep
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _currentStep = i),
                itemBuilder: (context, index) => _buildStepContent(index),
              ),
            ),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    TextButton(onPressed: _prevStep, child: const Text('上一步')),
                  const Spacer(),
                  if (_currentStep == 1)
                    FilledButton(
                      onPressed: _loggingIn ? null : _doLogin,
                      child: _loggingIn
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('登录并同步'),
                    )
                  else
                    FilledButton(onPressed: _nextStep, child: Text(_currentStep == _steps.length - 1 ? '开始使用' : '下一步')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(int index) {
    final step = _steps[index];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(step.icon, size: 80, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(step.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(step.subtitle, style: const TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          if (index == 1) _buildLoginForm(),
          if (index == 3) _buildPreferences(),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      children: [
        TextField(
          controller: _accountController,
          decoration: const InputDecoration(
            labelText: '学号',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '教务密码',
            prefixIcon: Icon(Icons.lock),
            border: OutlineInputBorder(),
          ),
        ),
        if (_loginError != null) ...[
          const SizedBox(height: 8),
          Text(_loginError!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  Widget _buildPreferences() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('显示周末'),
          value: _showWeekend,
          onChanged: (v) => setState(() => _showWeekend = v),
        ),
        ListTile(
          title: const Text('学期周数'),
          trailing: Text('$_termWeeks 周'),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('学期周数'),
                content: StatefulBuilder(
                  builder: (context, setDialogState) => Slider(
                    value: _termWeeks.toDouble(),
                    min: 16,
                    max: 25,
                    divisions: 9,
                    label: '$_termWeeks',
                    onChanged: (v) => setDialogState(() => _termWeeks = v.toInt()),
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      setState(() {});
                      Navigator.pop(context);
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WelcomeStep {
  final String title;
  final String subtitle;
  final IconData icon;
  const _WelcomeStep({required this.title, required this.subtitle, required this.icon});
}
