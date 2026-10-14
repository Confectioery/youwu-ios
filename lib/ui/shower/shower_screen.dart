import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../data/shower/shower_ble_controller.dart';
import '../../data/shower/shower_api.dart';
import '../../data/local/settings_store.dart';

/// 洗澡页面
class ShowerScreen extends StatefulWidget {
  const ShowerScreen({super.key});

  @override
  State<ShowerScreen> createState() => _ShowerScreenState();
}

class _ShowerScreenState extends State<ShowerScreen> {
  final ShowerBleController _bleController = ShowerBleController();
  final SettingsStore _settings = SettingsStore();

  ShowerAuth? _auth;
  BleSession? _session;
  bool _isRunning = false;
  bool _loading = false;
  String? _status;
  String? _error;

  // 演示用设备（实际从绑定列表获取）
  final ShowerDevice _demoDevice = const ShowerDevice(
    sn: 'DEMO001',
    name: '演示热水器',
    controlMac: 'AABBCCDDEEFF',
  );

  @override
  void initState() {
    super.initState();
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    final phone = await _settings.showerPhone;
    final token = await _settings.showerToken;
    if (phone.isNotEmpty && token.isNotEmpty) {
      setState(() => _auth = ShowerAuth(phone: phone, token: token));
    }
  }

  Future<void> _openWater() async {
    if (_auth == null) {
      _showLoginDialog();
      return;
    }
    setState(() {
      _loading = true;
      _status = '正在连接蓝牙设备...';
      _error = null;
    });

    final result = await _bleController.open(
      _demoDevice,
      _auth!,
      previous: _session,
      onPrepared: (session) {
        setState(() {
          _session = session;
          _status = '正在开阀...';
        });
      },
    );

    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case BleOpened(:final session):
        setState(() {
          _session = session;
          _isRunning = true;
          _status = '已开水，请开始洗澡';
        });
      case BleResumed(:final session):
        setState(() {
          _session = session;
          _isRunning = true;
          _status = '已恢复上次用水';
        });
      case BleRecovered(:final message):
        setState(() => _status = message);
      case BleUnconfirmed(:final message):
        setState(() => _status = message);
      case BleOpenFailed(:final message):
        setState(() {
          _error = message;
          _status = null;
        });
    }
  }

  Future<void> _closeWater() async {
    if (_session == null || _auth == null) return;
    setState(() {
      _loading = true;
      _status = '正在关水并结算...';
    });

    final result = await _bleController.close(_session!, _auth!);
    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case BleSettled():
        setState(() {
          _isRunning = false;
          _session = null;
          _status = '已关水并完成结算';
        });
      case BleRunning():
        setState(() => _status = '仍在用水中');
      case BlePending(:final message):
        setState(() {
          _error = message;
          _status = null;
        });
    }
  }

  Future<void> _inspect() async {
    if (_session == null || _auth == null) return;
    setState(() => _loading = true);
    final result = await _bleController.inspect(_session!, _auth!);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (result) {
      case BleSettled():
        setState(() {
          _isRunning = false;
          _session = null;
          _status = '已结算';
        });
      case BleRunning():
        setState(() => _status = '正在用水中');
      case BlePending(:final message):
        setState(() => _error = message);
    }
  }

  void _showLoginDialog() {
    final phoneController = TextEditingController();
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('洗澡登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: '手机号'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: '密码或验证码'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              // 简化：实际调用ShowerApi.login
              await _settings.setShowerPhone(phoneController.text);
              await _settings.setShowerToken('demo_token');
              setState(() {
                _auth = ShowerAuth(phone: phoneController.text, token: 'demo_token');
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('洗澡')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: _isRunning ? Colors.blue.shade50 : null,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      _isRunning ? Icons.shower : Icons.shower_outlined,
                      size: 64,
                      color: _isRunning ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isRunning ? '正在用水' : '准备就绪',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 8),
                      Text(_status!, style: const TextStyle(color: Colors.grey)),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    if (_isRunning)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _closeWater,
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          icon: _loading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.stop),
                          label: const Text('关水并结算'),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _openWater,
                          icon: _loading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.play_arrow),
                          label: const Text('一键开水'),
                        ),
                      ),
                    if (_isRunning) ...[
                      const SizedBox(height: 12),
                      TextButton(onPressed: _inspect, child: const Text('刷新状态')),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('使用说明', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('1. 开启手机蓝牙并靠近热水器'),
                    Text('2. 点击「一键开水」启动热水'),
                    Text('3. 洗完后点击「关水并结算」'),
                    Text('4. 确认停止出水和结算状态'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
