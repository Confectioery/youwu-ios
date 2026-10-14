import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'ble/ble_sign_builder.dart';
import 'ble/ble_frame.dart';
import 'ble/device_query_state.dart';

/// 洗澡账户认证信息
class ShowerAuth {
  final String loginCode;
  final String userId;
  final String accountId;
  final String projectId;
  final String phone;

  const ShowerAuth({
    required this.loginCode,
    required this.userId,
    required this.accountId,
    required this.projectId,
    required this.phone,
  });

  Map<String, String> toJson() => {
        'loginCode': loginCode,
        'userId': userId,
        'accountId': accountId,
        'projectId': projectId,
        'phone': phone,
      };

  /// 每个请求都要带上的字段
  Map<String, String> fields() => {
        'loginCode': loginCode,
        'userId': userId,
        'accountId': accountId,
        'projectId': projectId,
        'telephone': phone,
        'telPhone': phone,
        'phoneSystem': 'android',
        'version': '6.5.28',
      };

  factory ShowerAuth.fromJson(Map<String, dynamic> json) => ShowerAuth(
        loginCode: json['loginCode'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        accountId: json['accountId'] as String? ?? '',
        projectId: json['projectId'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
      );
}

/// 洗澡设备
class ShowerDevice {
  final String sn;
  final String name;
  final String mac;
  final bool bluetoothOnly;
  final int deviceId;
  final int bigTypeId;
  final int smallTypeId;
  final String realMac;

  const ShowerDevice({
    required this.sn,
    this.name = '浴室热水器',
    this.mac = '',
    this.bluetoothOnly = false,
    this.deviceId = 0,
    this.bigTypeId = 0,
    this.smallTypeId = 0,
    this.realMac = '',
  });

  /// 控制用MAC（无冒号格式，优先用realMac）
  String get controlMac =>
      (realMac.isNotEmpty ? realMac : mac).replaceAll(':', '').replaceAll('-', '').toUpperCase();

  Map<String, dynamic> toJson() => {
        'snCode': sn,
        'deviceName': name,
        'macAddress': mac,
        'isBle': bluetoothOnly,
        'deviceId': deviceId,
        'bigTypeId': bigTypeId,
        'smallTypeId': smallTypeId,
        'realMac': realMac,
      };

  factory ShowerDevice.fromJson(Map<String, dynamic> json) {
    final sn = (json['snCode'] as String?) ?? '';
    if (sn.isEmpty) throw Exception('设备信息不完整，请重新扫码');
    return ShowerDevice(
      sn: sn,
      name: (json['deviceName'] as String?)?.isNotEmpty == true ? json['deviceName'] as String : '浴室热水器',
      mac: json['macAddress'] as String? ?? '',
      bluetoothOnly: json['isBle'] as bool? ?? false,
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      bigTypeId: (json['bigTypeId'] as num?)?.toInt() ?? 0,
      smallTypeId: (json['smallTypeId'] as num?)?.toInt() ?? 0,
      realMac: json['realMac'] as String? ?? '',
    );
  }
}

/// 蓝牙费率数据
class ShowerBleRate {
  final List<int> data;
  final String consumeDate;
  final String orderNo;
  const ShowerBleRate({required this.data, required this.consumeDate, required this.orderNo});
}

/// 结算上传返回
class ShowerBleUpload {
  final String clData;
  const ShowerBleUpload(this.clData);
}

/// 会话过期异常
class ShowerSessionExpired implements Exception {
  final String message;
  const ShowerSessionExpired([this.message = '洗澡账户登录已失效，请重新登录']);
  @override
  String toString() => message;
}

/// 趣智校园 API（洗澡服务）
///
/// 对应Android的 ShowerApi.kt
/// 基础URL: https://v3-api.china-qzxy.cn
/// 协议参考 MIT 许可的 yehu-imei/linyu
class ShowerApi {
  static const String baseUrl = 'https://v3-api.china-qzxy.cn';

  final http.Client _client;

  ShowerApi({http.Client? client}) : _client = client ?? http.Client();

  /// 通用请求封装
  Future<Map<String, dynamic>> _call(
    String path,
    Map<String, String> fields, {
    bool post = true,
    ShowerAuth? auth,
    bool allowUsing = false,
    Set<int> acceptedCodes = const {},
  }) async {
    final allFields = {...?auth?.fields(), ...fields};

    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (auth != null) {
      headers['Config-Project'] = auth.projectId;
      headers['Config-Keys'] =
          'module_list,advertise_type,question_list,service_phone_list,banner_list_app,activity_list_app,aliCard_popup_config';
    }

    http.Response resp;
    if (post) {
      resp = await _client.post(uri, headers: headers, body: allFields);
    } else {
      final getUri = Uri.parse('$baseUrl$path').replace(queryParameters: allFields);
      resp = await _client.get(getUri, headers: headers);
    }

    if (auth != null && (resp.statusCode == 401 || resp.statusCode == 403)) {
      throw const ShowerSessionExpired();
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('洗澡服务连接失败（${resp.statusCode}）');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (!(json['success'] as bool? ?? false)) {
      final errorCode = (json['errorCode'] as num?)?.toInt() ?? 0;
      if ((allowUsing && errorCode == 307) || acceptedCodes.contains(errorCode)) {
        return json;
      }
      final message = (json['errorMessage'] as String?)?.isNotEmpty == true
          ? json['errorMessage'] as String
          : (json['msg'] as String?) ?? '操作失败';
      if (auth != null &&
          (message.contains('登录') ||
              message.toLowerCase().contains('token') ||
              message.contains('认证') ||
              message.contains('过期'))) {
        throw const ShowerSessionExpired();
      }
      throw Exception(message);
    }
    return json;
  }

  /// 发送短信验证码
  Future<void> sendSms(String phone) async {
    await _call(
      '/user/verification/code/get',
      {
        'telephone': phone,
        'secret': _smsSecret(phone),
        'typeId': '3',
        'platform': '1',
      },
      post: false,
    );
  }

  /// 登录
  /// [sms] true=短信验证码登录，false=密码登录
  Future<ShowerAuth> login(String phone, String secret, {bool sms = true}) async {
    final fields = <String, String>{
      'telephone': phone,
      'phoneSystem': 'android',
      'version': '6.5.28',
      'type': sms ? '5' : '0',
    };
    if (sms) {
      fields['smsCode'] = secret;
    } else {
      fields['password'] = _passwordHash(secret);
    }

    final data = await _call(
      sms ? '/user/registerAndLogin' : '/user/login',
      fields,
      post: true,
    );

    final dataObj = data['data'] as Map<String, dynamic>?;
    if (dataObj == null) throw Exception('登录返回数据为空');

    final account = dataObj['userAccount'] as Map<String, dynamic>?;
    final auth = ShowerAuth(
      loginCode: dataObj['loginCode'] as String? ?? '',
      userId: dataObj['userId'] as String? ?? '',
      accountId: account?['accountId'] as String? ?? '',
      projectId: account?['projectId'] as String? ?? '',
      phone: phone,
    );

    if (auth.loginCode.isEmpty ||
        auth.userId.isEmpty ||
        auth.accountId.isEmpty ||
        auth.projectId.isEmpty ||
        auth.loginCode == '0' ||
        auth.userId == '0') {
      throw Exception('登录信息不完整，请先在趣智校园完成学校账户绑定');
    }
    return auth;
  }

  /// 验证登录状态
  Future<void> validate(ShowerAuth auth) async {
    await _call('/account/info', {}, post: false, auth: auth);
  }

  /// 通过MAC获取设备信息
  Future<ShowerDevice> device(ShowerAuth auth, String mac) async {
    final data = await _call(
      '/device/info/mac',
      {'macAddress': mac},
      post: false,
      auth: auth,
    );
    return ShowerDevice.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// 获取蓝牙费率（开水前调用）
  Future<ShowerBleRate> bleRate(ShowerAuth auth, ShowerDevice device, DeviceQueryState state) async {
    if (device.deviceId <= 0) {
      throw Exception('设备信息不完整，请重新绑定');
    }
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(device.controlMac)) {
      throw Exception('设备蓝牙地址无效，请重新绑定');
    }

    final signature = BleSignBuilder.signRateOrder(
      auth.loginCode,
      auth.phone,
      device.deviceId.toString(),
      '0',
      state.randomNumber,
    );
    if (signature == null) throw Exception('蓝牙请求签名失败');

    final data = await _call(
      '/order/downRate/bluetooth/rateOrder',
      {
        'deviceId': device.deviceId.toString(),
        'macAddress': device.controlMac,
        'macType': BleSignBuilder.macType(state.devType, state.a1),
        'bigTypeId': device.bigTypeId.toString(),
        'smallTypeId': device.smallTypeId.toString(),
        'protocolType': state.protocolType,
        'randomNumber': state.randomNumber.toLowerCase(),
        'xfModel': '0',
        'signature': signature,
      },
      post: true,
      auth: auth,
    );

    final result = data['data'] as Map<String, dynamic>?;
    if (result == null) throw Exception('服务未返回蓝牙费率');

    final downDataHex = result['downData'] as String? ?? '';
    final raw = BleFrame.fromHex(downDataHex);
    if (raw == null || raw.isEmpty) throw Exception('服务返回的蓝牙费率无效');

    return ShowerBleRate(
      data: raw,
      consumeDate: result['consumeDate'] as String? ?? '',
      orderNo: (result['orderNo'] as String?)?.isNotEmpty == true
          ? result['orderNo'] as String
          : (result['liquidOrderNo'] as String?) ?? '',
    );
  }

  /// 上传消费数据（结算）
  Future<ShowerBleUpload> bleUpload(
    ShowerAuth auth,
    DeviceQueryState state,
    List<int> payload,
  ) async {
    final xfData = BleFrame.toHex(payload).toLowerCase();
    final signature = BleSignBuilder.signUpload(auth.loginCode, auth.phone, xfData);
    if (signature == null) throw Exception('结算签名失败');

    final data = await _call(
      '/order/upload/bluetooth/data',
      {
        'protocolType': state.protocolType,
        'randomNumber': state.randomNumber.toLowerCase(),
        'xfData': xfData,
        'signature': signature,
      },
      post: true,
      auth: auth,
      acceptedCodes: {206, 209},
    );

    final result = data['data'] as Map<String, dynamic>?;
    if (result == null) throw Exception('服务未返回结算数据');
    return ShowerBleUpload(result['clData'] as String? ?? '');
  }

  /// 结算失败上报
  Future<void> bleFail(ShowerAuth auth, String consumeDate) async {
    if (consumeDate.isEmpty) return;
    final signature = BleSignBuilder.signFail(auth.loginCode, auth.phone, consumeDate);
    if (signature == null) return;
    try {
      await _call(
        '/order/upload/bluetooth/fail',
        {'consumeDate': consumeDate, 'signature': signature},
        post: true,
        auth: auth,
      );
    } catch (_) {}
  }

  // ── 工具方法 ──

  /// 密码哈希：MD5后取后10位大写
  static String _passwordHash(String password) {
    final hash = md5.convert(utf8.encode(password)).toString();
    return hash.substring(hash.length - 10).toUpperCase();
  }

  /// 短信验证码secret：MD5(手机号前3位+后4位+"klcx")
  static String _smsSecret(String phone) {
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      throw Exception('请输入正确的手机号');
    }
    return md5.convert(utf8.encode('${phone.substring(0, 3)}${phone.substring(phone.length - 4)}klcx')).toString();
  }

  /// 从扫码结果提取设备MAC
  static String? deviceCode(String raw) {
    final code = raw.trim().substring(raw.lastIndexOf(',') + 1).replaceAll(':', '').toUpperCase();
    return RegExp(r'^[0-9A-F]{12}$').hasMatch(code) ? code : null;
  }

  void close() => _client.close();
}
