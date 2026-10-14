import 'dart:convert';
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
  final ShowerApi _api = ShowerApi();
  final SettingsStore _settings = SettingsStore();

  ShowerAuth? _auth;
  ShowerDevice? _device;
  BleSession? _session;
  bool _isRunning = false;
  bool _loading = false;
  String? _status;
  String? _error;

  // 扫描状态
  bool _scanning = false;
  List<ScannedDevice> _scannedDevices = [];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final authJson = await _settings.showerAuthJson;
    final deviceJson = await _settings.showerDeviceJson;
    if (authJson.isNotEmpty) {
      try {
        _auth = ShowerAuth.fromJson(jsonDecode(authJson));
      } catch (_) {}
    }
    if (deviceJson.isNotEmpty) {
      try {
        _device = ShowerDevice.fromJson(jsonDecode(deviceJson));
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  // ── 登录 ──

  void _showLoginDialog() {
    final phoneController = TextEditingController();
    final secretController = TextEditingController();
    bool useSms = true;
    bool sendingCode = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('趣智校园登录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: '手机号'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('短信验证码'),
                    selected: useSms,
                    onSelected: (v) => setDialogState(() => useSms = v),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('密码'),
                    selected: !useSms,
                    onSelected: (v) => setDialogState(() => useSms = !v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: secretController,
                      decoration: InputDecoration(
                        labelText: useSms ? '验证码' : '密码',
                      ),
                      obscureText: !useSms,
                    ),
                  ),
                  if (useSms) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: sendingCode
                          ? null
                          : () async {
                              setDialogState(() => sendingCode = true);
                              try {
                                await _api.sendSms(phoneController.text);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('验证码已发送')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('发送失败: $e')),
                                  );
                                }
                              } finally {
                                setDialogState(() => sendingCode = false);
                              }
                            },
                      child: Text(sendingCode ? '发送中...' : '获取验证码'),
                    ),
                  ],
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _doLogin(phoneController.text, secretController.text, useSms);
              },
              child: const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doLogin(String phone, String secret, bool sms) async {
    setState(() {
      _loading = true;
      _status = '正在登录...';
      _error = null;
    });
    try {
      final auth = await _api.login(phone, secret, sms: sms);
      await _settings.setShowerAuthJson(jsonEncode(auth.toJson()));
      setState(() {
        _auth = auth;
        _status = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _status = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── 设备扫描与绑定 ──

  Future<void> _scanDevices() async {
    setState(() {
      _scanning = true;
      _scannedDevices = [];
      _error = null;
    });
    try {
      final devices = await _bleController.scanDevices();
      setState(() => _scannedDevices = devices);
    } catch (e) {
      setState(() => _error = '扫描失败: $e');
    } finally {
      setState(() => _scanning = false);
    }
  }

  Future<void> _bindDevice(ScannedDevice scanned) async {
    if (_auth == null) return;
    setState(() {
      _loading = true;
      _status = '正在绑定设备...';
      _error = null;
    });
    try {
      // 从扫描设备获取MAC（iOS上remoteId是UUID，不是MAC）
      // 需要通过设备名称或广播数据获取MAC，或者让用户手动输入
      final mac = scanned.mac ?? '';
      if (mac.isEmpty || !RegExp(r'^[0-9A-Fa-f:]{17}$').hasMatch(mac)) {
        // iOS上拿不到MAC，提示用户手动输入
        _showManualMacDialog(scanned);
        return;
      }
      final device = await _api.device(_auth!, mac.replaceAll(':', '').toUpperCase());
      await _settings.setShowerDeviceJson(jsonEncode(device.toJson()));
      _bleController.selectedDevice = scanned.device;
      setState(() {
        _device = device;
        _status = null;
      });
    } catch (e) {
      setState(() => _error = '绑定失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showManualMacDialog(ScannedDevice scanned) {
    final macController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入设备MAC地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('iOS无法直接获取蓝牙MAC地址，请在设备标签上查找并输入'),
            const SizedBox(height: 12),
            TextField(
              controller: macController,
              decoration: const InputDecoration(
                labelText: 'MAC地址',
                hintText: 'AA:BB:CC:DD:EE:FF',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_auth == null) return;
              setState(() {
                _loading = true;
                _status = '正在绑定设备...';
              });
              try {
                final mac = macController.text.replaceAll(':', '').toUpperCase();
                final device = await _api.device(_auth!, mac);
                await _settings.setShowerDeviceJson(jsonEncode(device.toJson()));
                _bleController.selectedDevice = scanned.device;
                setState(() {
                  _device = device;
                  _status = null;
                });
              } catch (e) {
                setState(() => _error = '绑定失败: $e');
              } finally {
                setState(() => _loading = false);
              }
            },
            child: const Text('绑定'),
          ),
        ],
      ),
    );
  }

  // ── 开水/关水 ──

  Future<void> _openWater() async {
    if (_auth == null) {
      _showLoginDialog();
      return;
    }
    if (_device == null) {
      setState(() => _error = '请先绑定热水器');
      return;
    }
    if (_bleController.selectedDevice == null) {
      setState(() => _error = '请先扫描并选择热水器');
      return;
    }

    setState(() {
      _loading = true;
      _status = '正在连接蓝牙设备...';
      _error = null;
    });

    final result = await _bleController.open(
      _device!,
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

  // ── 构建UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('洗澡'),
        actions: [
          if (_auth != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '退出登录',
              onPressed: () async {
                await _settings.setShowerAuthJson('');
                await _settings.setShowerDeviceJson('');
                setState(() {
                  _auth = null;
                  _device = null;
                  _session = null;
                  _isRunning = false;
                });
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_auth == null) {
      return _buildLoginPrompt();
    }
    if (_device == null) {
      return _buildDeviceBinding();
    }
    return _buildMainControl();
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shower_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 24),
          const Text(
            '登录趣智校园',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '使用手机号和验证码/密码登录',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 200,
            height: 48,
            child: FilledButton(
              onPressed: _showLoginDialog,
              child: const Text('立即登录'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceBinding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.bluetooth_searching, size: 48, color: Colors.blue),
                const SizedBox(height: 12),
                const Text(
                  '绑定热水器',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '开启蓝牙并靠近热水器，点击扫描按钮搜索设备',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _scanning ? null : _scanDevices,
                    icon: _scanning
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search),
                    label: Text(_scanning ? '扫描中...' : '扫描蓝牙设备'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (_scannedDevices.isNotEmpty)
          Expanded(
            child: Card(
              child: ListView.builder(
                itemCount: _scannedDevices.length,
                itemBuilder: (context, index) {
                  final device = _scannedDevices[index];
                  return ListTile(
                    leading: const Icon(Icons.bluetooth, color: Colors.blue),
                    title: Text(device.name),
                    subtitle: Text('${device.mac ?? '未知MAC'} · ${device.rssi} dBm'),
                    trailing: FilledButton(
                      onPressed: () => _bindDevice(device),
                      child: const Text('绑定'),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMainControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 设备信息
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.shower, size: 40, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _device!.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SN: ${_device!.sn}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _device = null;
                      _bleController.selectedDevice = null;
                    });
                    _settings.setShowerDeviceJson('');
                  },
                  child: const Text('更换'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 控制面板
        Expanded(
          child: Card(
            color: _isRunning ? Colors.blue.shade50 : null,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isRunning ? Icons.shower : Icons.shower_outlined,
                    size: 72,
                    color: _isRunning ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isRunning ? '正在用水' : '准备就绪',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(_status!, style: const TextStyle(color: Colors.grey)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 32),
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
    );
  }

  @override
  void dispose() {
    _bleController.dispose();
    _api.close();
    super.dispose();
  }
}
