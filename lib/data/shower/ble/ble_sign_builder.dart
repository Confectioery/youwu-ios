import 'klcxkj_signer.dart';

/// 蓝牙水表通道的签名构造
///
/// 对应Android的 BleSignBuilder.kt
/// 签名算法：按key字典序升序拼接键值对 → 嵌套MD5（KlcxkjSigner）
///
/// 各接口签名字段不同：
/// - 下费率(rateOrder): telephone, deviceId, xfModel, randomNumber
/// - 上传结算(upload): loginCode, telephone, xfData
/// - 失败上报(fail): consumeDate, loginCode, telephone
class BleSignBuilder {
  /// 按key升序拼接成签名原文
  /// value为null时跳过整个字段（连key一起不拼）
  static String _rawOf(Map<String, String?> params) {
    final keys = params.keys.toList()..sort();
    final sb = StringBuffer();
    for (final k in keys) {
      final v = params[k];
      if (v != null) {
        sb.write(k);
        sb.write(v);
      }
    }
    return sb.toString();
  }

  /// macType参数：两个字节的十六进制拼接（小写，各补足2位）
  /// 第一个字节来自设备状态帧的协议版本，第二个是a1
  static String macType(int type, int a1) {
    return '${(type & 0xFF).toRadixString(16).padLeft(2, '0')}'
        '${(a1 & 0xFF).toRadixString(16).padLeft(2, '0')}';
  }

  /// 下费率（开阀第一步）的签名
  /// randomNumber从设备状态帧里取到的8位hex
  static String? signRateOrder(
    String loginCode,
    String telephone,
    String deviceId,
    String xfModel,
    String randomNumber,
  ) {
    return KlcxkjSigner.signParams(
      loginCode,
      _rawOf({
        'telephone': telephone,
        'deviceId': deviceId,
        'xfModel': xfModel,
        'randomNumber': randomNumber.toLowerCase(),
      }),
    );
  }

  /// 上传消费数据（结算）的签名
  /// xfData从设备采集到的消费数据（hex，转小写后参与签名）
  static String? signUpload(
    String loginCode,
    String telephone,
    String xfData,
  ) {
    return KlcxkjSigner.signParams(
      loginCode,
      _rawOf({
        'loginCode': loginCode,
        'telephone': telephone,
        'xfData': xfData.toLowerCase(),
      }),
    );
  }

  /// 上报失败订单的签名
  /// consumeDate来自下费率响应，开阀成功时就要存下来
  static String? signFail(
    String loginCode,
    String telephone,
    String consumeDate,
  ) {
    return KlcxkjSigner.signParams(
      loginCode,
      _rawOf({
        'consumeDate': consumeDate,
        'loginCode': loginCode,
        'telephone': telephone,
      }),
    );
  }
}
