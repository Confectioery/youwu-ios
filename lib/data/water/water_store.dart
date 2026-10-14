import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'water_api.dart';

/// 饮水设备存储
class WaterStore {
  static const _keyDevices = 'water_devices';
  static const _keyDefault = 'water_default_device';

  Future<void> saveDevices(List<WaterDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final list = devices.map((d) => {'id': d.id, 'name': d.name}).toList();
    await prefs.setString(_keyDevices, jsonEncode(list));
  }

  Future<List<WaterDevice>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDevices);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => WaterDevice(
                id: e['id'] as String? ?? '',
                name: e['name'] as String? ?? '饮水设备',
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setDefaultDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefault, deviceId);
  }

  Future<String> getDefaultDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDefault) ?? '';
  }
}
