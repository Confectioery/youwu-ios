import 'dart:convert';
import 'package:http/http.dart' as http;

/// 洗澡账户认证信息
class ShowerAuth {
  final String phone;
  final String token;
  const ShowerAuth({required this.phone, required this.token});
}

/// 洗澡设备
class ShowerDevice {
  final String sn;
  final String name;
  final String controlMac; // 蓝牙MAC（无冒号格式）
  const ShowerDevice({required this.sn, this.name = '', required this.controlMac});
}

/// 蓝牙费率数据
class BleRate {
  final String consumeDate;
  final String orderNo;
  final List<int> data; // 费率包原始字节
  const BleRate({required this.consumeDate, required this.orderNo, required this.data});
}

/// 结算上传返回
class BleUploadResult {
  final String clData; // 加密的写回数据
  const BleUploadResult({required this.clData});
}

/// 会话过期异常
class ShowerSessionExpired implements Exception {
  final String message;
  const ShowerSessionExpired([this.message = '洗澡登录已过期，请重新登录']);
  @override
  String toString() => message;
}

/// 趣智校园 API（洗澡服务）
///
/// 对应Android的 ShowerApi.kt
/// 对接趣智校园平台的蓝牙水表服务
class ShowerApi {
  static const String baseUrl = 'https://api.quzhixiaoyuan.com';

  final http.Client _client;

  ShowerApi({http.Client? client}) : _client = client ?? http.Client();

  /// 登录（手机号+密码）
  Future<ShowerAuth> login(String phone, String password) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/login'),
      headers: _headers(),
      body: jsonEncode({'phone': phone, 'password': password}),
    );
    return _parseAuth(resp);
  }

  /// 登录（手机号+短信验证码）
  Future<ShowerAuth> loginWithCode(String phone, String code) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/login/code'),
      headers: _headers(),
      body: jsonEncode({'phone': phone, 'code': code}),
    );
    return _parseAuth(resp);
  }

  /// 发送短信验证码
  Future<void> sendSms(String phone) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/sms'),
      headers: _headers(),
      body: jsonEncode({'phone': phone}),
    );
    if (resp.statusCode != 200) {
      throw Exception('短信发送失败');
    }
  }

  /// 获取蓝牙费率（开水前调用）
  Future<BleRate> bleRate(ShowerAuth auth, ShowerDevice device, DeviceQueryStateCompat state) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/ble/rate'),
      headers: _headers(token: auth.token),
      body: jsonEncode({
        'sn': device.sn,
        'macAddress': device.controlMac,
        'randomNumber': state.randomNumber,
        'protocolType': state.protocolType,
        'macType': '${state.devType},${state.a1}',
        'phone': auth.phone,
      }),
    );
    if (resp.statusCode == 401) throw const ShowerSessionExpired();
    final data = jsonDecode(resp.body);
    final code = data['code'] as int? ?? -1;
    if (code != 0) {
      throw Exception(data['msg'] ?? '获取费率失败');
    }
    final result = data['data'] as Map<String, dynamic>;
    return BleRate(
      consumeDate: result['consumeDate'] as String? ?? '',
      orderNo: result['orderNo'] as String? ?? '',
      data: _hexToBytes(result['downData'] as String? ?? ''),
    );
  }

  /// 上传消费数据（结算）
  Future<BleUploadResult> bleUpload(
    ShowerAuth auth,
    DeviceQueryStateCompat state,
    List<int> xfData,
  ) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/ble/upload'),
      headers: _headers(token: auth.token),
      body: jsonEncode({
        'xfData': _bytesToHex(xfData),
        'phone': auth.phone,
      }),
    );
    if (resp.statusCode == 401) throw const ShowerSessionExpired();
    final data = jsonDecode(resp.body);
    final code = data['code'] as int? ?? -1;
    if (code != 0) {
      throw Exception(data['msg'] ?? '结算上传失败');
    }
    final result = data['data'] as Map<String, dynamic>;
    return BleUploadResult(clData: result['clData'] as String? ?? '');
  }

  /// 结算失败上报
  Future<void> bleFail(ShowerAuth auth, String consumeDate) async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/api/ble/fail'),
        headers: _headers(token: auth.token),
        body: jsonEncode({'consumeDate': consumeDate, 'phone': auth.phone}),
      );
    } catch (_) {}
  }

  /// 获取绑定设备列表
  Future<List<ShowerDevice>> devices(ShowerAuth auth) async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/devices'),
      headers: _headers(token: auth.token),
    );
    if (resp.statusCode == 401) throw const ShowerSessionExpired();
    final data = jsonDecode(resp.body);
    final list = data['data'] as List? ?? [];
    return list
        .map((e) => ShowerDevice(
              sn: e['sn'] as String? ?? '',
              name: e['name'] as String? ?? '热水器',
              controlMac: e['mac'] as String? ?? '',
            ))
        .toList();
  }

  ShowerAuth _parseAuth(http.Response resp) {
    if (resp.statusCode != 200) {
      throw Exception('登录失败: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body);
    final code = data['code'] as int? ?? -1;
    if (code != 0) {
      throw Exception(data['msg'] ?? '登录失败');
    }
    final result = data['data'] as Map<String, dynamic>;
    return ShowerAuth(
      phone: result['phone'] as String? ?? '',
      token: result['token'] as String? ?? '',
    );
  }

  Map<String, String> _headers({String? token}) {
    final h = {
      'Content-Type': 'application/json',
      'User-Agent': 'Youwu/1.1 (iOS)',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    };
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = token;
    }
    return h;
  }

  List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final bytes = List<int>.filled(clean.length ~/ 2, 0);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void close() => _client.close();
}

/// 兼容用的设备状态（避免循环引用）
class DeviceQueryStateCompat {
  final String protocolType;
  final String randomNumber;
  final int state;
  final int devType;
  final int a1;
  const DeviceQueryStateCompat({
    required this.protocolType,
    required this.randomNumber,
    required this.state,
    required this.devType,
    required this.a1,
  });
}
