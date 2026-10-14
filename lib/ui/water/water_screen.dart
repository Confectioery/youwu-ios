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
  final WaterApi _api = WaterApi(); // 实际使用时从配置注入gateway和cid
  final WaterStore _store = WaterStore();
  final SettingsStore _settings = SettingsStore();

  List<WaterDevice> _devices = [];
  String? _defaultDeviceId;
  String? _token;
  bool _loading = false;
  bool _starting = false;
  String? _error;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('喝水')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
            const Text('我的设备', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _devices.isEmpty
                      ? const Center(child: Text('暂无绑定设备，请先登录并绑定'))
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
        ),
      ),
    );
  }
}
