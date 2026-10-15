import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// 饮水设备
class WaterDevice {
  final String id;
  final String name;
  const WaterDevice({required this.id, this.name = '饮水设备'});
}

/// 饮水会话过期
class WaterSessionExpired implements Exception {
  final String message;
  const WaterSessionExpired([this.message = '喝水登录已过期，请重新登录']);
  @override
  String toString() => message;
}

/// 慧生活798 饮水设备 API
///
/// 对应Android的 WaterApi.kt
/// 协议逆向自 nocookies111/life-798 (MIT)
class WaterApi {
  final String gateway;
  final String cid;
  final http.Client _client;

  WaterApi({
    this.gateway = 'https://i.ilife798.com/api/v1',
    this.cid = 'drinkwaterapp123456789',
    http.Client? client,
  }) : _client = client ?? http.Client();

  bool get configured => gateway.startsWith('https://') && cid.isNotEmpty;

  /// 获取图形验证码
  Future<Uint8List> captcha(String key) async {
    final path = '/captcha/?s=${Uri.encodeComponent(key)}&r=${DateTime.now().millisecondsSinceEpoch}';
    final resp = await _client.get(
      Uri.parse('${gateway.replaceAll(RegExp(r"/$"), "")}$path'),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('图形验证码获取失败');
    }
    return resp.bodyBytes;
  }

  /// 发送短信验证码
  Future<void> sendSms(String phone, String graphCode, String key) async {
    await _json(
      '/acc/login/code',
      body: {'un': phone, 'authCode': graphCode, 's': key},
      app: false,
    );
  }

  /// 登录
  Future<String> login(String phone, String code) async {
    final result = await _json(
      '/acc/login',
      body: {'openCode': '', 'authCode': code, 'un': phone, 'cid': cid},
    );
    final token = result['data']?['al']?['token']?.toString();
    if (token == null || token.isEmpty || token == 'null') {
      throw Exception('登录未返回有效凭据，请重试');
    }
    return token;
  }

  /// 获取绑定设备列表
  Future<List<WaterDevice>> devices(String token) async {
    final result = await _json('/ui/app/master', token: token);
    final items = result['data']?['favos'] as List?;
    if (items == null) return [];
    return items
        .map((e) {
          final m = e as Map<String, dynamic>;
          final id = m['id']?.toString();
          if (id == null || id.isEmpty || id == 'null') return null;
          final name = m['name']?.toString();
          return WaterDevice(
            id: id,
            name: (name == null || name.isEmpty || name == 'null') ? '饮水设备' : name,
          );
        })
        .whereType<WaterDevice>()
        .toList();
  }

  /// 绑定设备
  Future<void> bind(String token, String deviceId) async {
    await _json('/dev/favo?did=${Uri.encodeComponent(deviceId)}&remove=0', token: token);
  }

  /// 启动饮水设备
  Future<void> start(String token, String deviceId) async {
    await _json(
      '/dev/start?did=${Uri.encodeComponent(deviceId)}&upgrade=true&ptype=91&rcp=false',
      token: token,
    );
  }

  Future<Map<String, dynamic>> _json(
    String path, {
    String token = '',
    Map<String, dynamic>? body,
    bool app = true,
  }) async {
    if (!configured) {
      throw Exception('喝水服务暂未配置，请联系应用维护者');
    }
    final resp = await _client.post(
      Uri.parse('${gateway.replaceAll(RegExp(r"/$"), "")}$path'),
      headers: _headers(token: token, app: app),
      body: body != null ? jsonEncode(body) : null,
    );

    if (resp.statusCode == 401) throw const WaterSessionExpired();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('服务暂时不可用（${resp.statusCode}）');
    }

    final result = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = result['code'] as int?;
    if (code == -99) throw const WaterSessionExpired();
    if (code == -21) throw const WaterSessionExpired('设备登录未被接受，请重新登录');
    if (code != null && code != 0) {
      throw Exception(switch (code) {
        -88 => '请先在慧生活798完成代扣签约',
        -87 => '代扣签约已过期，请在慧生活798重新签约',
        -52 => '账户欠费，请充值后使用',
        -20 => '请先在慧生活798绑定一卡通账户',
        -19 => '设备准备中，请稍后再试',
        -82 => '请先在慧生活798完成支付',
        _ => (result['msg'] as String?)?.let((m) => m.isEmpty ? '请求失败（$code）' : m) ?? '请求失败（$code）',
      });
    }
    return result;
  }

  Map<String, String> _headers({String token = '', bool app = true}) {
    return {
      'ApplicationType': app ? '1,1' : '1,5',
      'VersionCode': '2.0.83',
      'User-Agent': 'Youwu/1.1 (iOS)',
      'Content-Type': 'application/json',
      'Accept-Language': 'zh-Hans-CN;q=1',
      if (token.isNotEmpty) 'Authorization': token,
    };
  }

  void close() => _client.close();
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
