import 'dart:typed_data';
import 'ble_frame.dart';
import 'klcxkj_crypto.dart';

/// 蓝牙费率/结算签名构建器
///
/// 对应Android的 BleSignBuilder.kt
/// 构建发送给服务端的签名参数，以及解析服务端返回的费率数据
class BleSignBuilder {
  /// 构建费率请求签名
  static Map<String, String> buildRateParams({
    required String sn,
    required String mac,
    required String randomNumber,
    required String protocolType,
    required int devType,
    required int a1,
    required String phone,
    required String token,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sign = KlcxkjCrypto.md5Sign(
      '$sn$mac$randomNumber$protocolType$devType$a1$phone$timestamp',
    );
    return {
      'sn': sn,
      'macAddress': mac.replaceAll(':', ''),
      'randomNumber': randomNumber,
      'protocolType': protocolType,
      'macType': '$devType,$a1',
      'phone': phone,
      'timestamp': '$timestamp',
      'sign': sign,
      'token': token,
    };
  }

  /// 解析服务端返回的费率包为字节
  static Uint8List? parseRateData(String? downDataHex) {
    if (downDataHex == null || downDataHex.isEmpty) return null;
    try {
      return BleFrame.fromHex(downDataHex);
    } catch (_) {
      return null;
    }
  }

  /// 构建结算上传参数
  static Map<String, String> buildUploadParams({
    required String sn,
    required String mac,
    required String consumeDate,
    required String orderNo,
    required String xfDataHex,
    required String phone,
    required String token,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sign = KlcxkjCrypto.md5Sign('$sn$mac$consumeDate$orderNo$xfDataHex$phone$timestamp');
    return {
      'sn': sn,
      'macAddress': mac.replaceAll(':', ''),
      'consumeDate': consumeDate,
      'orderNo': orderNo,
      'xfData': xfDataHex,
      'phone': phone,
      'timestamp': '$timestamp',
      'sign': sign,
      'token': token,
    };
  }
}
