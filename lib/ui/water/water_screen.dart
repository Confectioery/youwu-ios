import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/water/water_api.dart';
import '../../data/water/water_store.dart';
import '../../data/local/settings_store.dart';

/// 饮水设备页面
class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key});

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen> {
  final WaterApi _api = WaterApi();
  final WaterStore _store = WaterStore();
  final SettingsStore _settings = SettingsStore();

  List<WaterDevice> _devices = [];
  String? _defaultDeviceId;
  String? _token;
  bool _loading = false;
  bool _starting = false;
  String? _error;

  // 登录相关
  String? _captchaKey;
  Uint8List? _captchaImage;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    _token = await _settings.waterToken;
    _defaultDeviceId = await _settings.waterDeviceId;
    _devices = await _store.loadDevices();
    setState(() {});
    if (_token != null && _token!.isNotEmpty) {
      _refreshDevices();
    }
  }

  Future<void> _refreshDevices() async {
    if (_token == null) return;
    setState(() => _loading = true);
    try {
      final devices = await _api.devices(_token!);
      await _store.saveDevices(devices);
      setState(() => _devices = devices);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _startWater() async {
    if (_defaultDeviceId == null || _defaultDeviceId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择默认饮水设备')),
      );
      return;
    }
    setState(() => _starting = true);
    try {
      await _api.start(_token!, _defaultDeviceId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('饮水设备已启动，请在饮水机上选择水温接水')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动失败: $e')),
        );
      }
    } finally {
      setState(() => _starting = false);
    }
  }

  // ── 登录 ──

  void _showLoginDialog() {
    final phoneController = TextEditingController();
    final graphCodeController = TextEditingController();
    final smsCodeController = TextEditingController();
    bool sendingSms = false;
    bool loggingIn = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('慧生活798登录'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: '手机号'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                // 图形验证码
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: graphCodeController,
                        decoration: const InputDecoration(labelText: '图形验证码'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        try {
                          final key = DateTime.now().millisecondsSinceEpoch.toString();
                          final img = await _api.captcha(key);
                          setDialogState(() {
                            _captchaKey = key;
                            _captchaImage = img;
                          });
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('获取验证码失败: $e')),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: 100,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: _captchaImage != null
                            ? Image.memory(_captchaImage!, fit: BoxFit.fill)
                            : const Center(child: Text('点击获取', style: TextStyle(fontSize: 12))),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 短信验证码
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: smsCodeController,
                        decoration: const InputDecoration(labelText: '短信验证码'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: sendingSms
                          ? null
                          : () async {
                              if (phoneController.text.isEmpty || graphCodeController.text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('请先输入手机号和图形验证码')),
                                );
                                return;
                              }
                              setDialogState(() => sendingSms = true);
                              try {
                                await _api.sendSms(
                                  phoneController.text,
                                  graphCodeController.text,
                                  _captchaKey ?? '',
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('短信验证码已发送')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('发送失败: $e')),
                                  );
                                }
                              } finally {
                                setDialogState(() => sendingSms = false);
                              }
                            },
                      child: Text(sendingSms ? '发送中...' : '获取验证码'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: loggingIn
                  ? null
                  : () async {
                      if (phoneController.text.isEmpty || smsCodeController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入手机号和短信验证码')),
                        );
                        return;
                      }
                      setDialogState(() => loggingIn = true);
                      try {
                        final token = await _api.login(phoneController.text, smsCodeController.text);
                        await _settings.setWaterToken(token);
                        if (mounted) {
                          Navigator.pop(context);
                          setState(() {
                            _token = token;
                            _error = null;
                          });
                          _refreshDevices();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('登录失败: $e')),
                          );
                        }
                      } finally {
                        setDialogState(() => loggingIn = false);
                      }
                    },
              child: Text(loggingIn ? '登录中...' : '登录'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('喝水'),
        actions: [
          if (_token != null && _token!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '退出登录',
              onPressed: () async {
                await _settings.setWaterToken('');
                setState(() {
                  _token = null;
                  _devices = [];
                });
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _token == null || _token!.isEmpty ? _buildLoginPrompt() : _buildMainContent(),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_drink_outlined, size: 80, color: Colors.blue.shade300),
          const SizedBox(height: 24),
          const Text(
            '登录慧生活798',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '使用手机号、图形验证码和短信验证码登录',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: 200,
            height: 48,
            child: FilledButton(
              onPressed: () {
                setState(() => _error = null);
                _showLoginDialog();
              },
              child: const Text('立即登录'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.local_drink, size: 64, color: Colors.blue.shade400),
                const SizedBox(height: 16),
                const Text('一键启动饮水设备', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  _defaultDeviceId != null && _defaultDeviceId!.isNotEmpty
                      ? '当前设备: ${_devices.where((d) => d.id == _defaultDeviceId).firstOrNull?.name ?? _defaultDeviceId}'
                      : '未选择默认设备',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _starting ? null : _startWater,
                    icon: _starting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                    label: Text(_starting ? '启动中...' : '启动饮水设备'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('我的设备', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: _refreshDevices,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _devices.isEmpty
                  ? const Center(child: Text('暂无绑定设备，请先在慧生活798 APP绑定设备'))
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        final isDefault = device.id == _defaultDeviceId;
                        return Card(
                          child: ListTile(
                            leading: Icon(Icons.water_drop, color: isDefault ? Colors.blue : Colors.grey),
                            title: Text(device.name),
                            subtitle: Text(device.id),
                            trailing: isDefault
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : TextButton(
                                    onPressed: () async {
                                      await _settings.setWaterDeviceId(device.id);
                                      setState(() => _defaultDeviceId = device.id);
                                    },
                                    child: const Text('设为默认'),
                                  ),
                          ),
                        );
                      },
                    ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }
}
