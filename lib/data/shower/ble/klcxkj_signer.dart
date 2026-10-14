import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 凯路科技蓝牙水表请求签名（嵌套MD5）
///
/// 对应Android的 KlcxkjSigner.kt
/// 算法：
///   内层 = MD5(raw + "&key=" + sessionKey)
///   签名 = MD5(内层 + "&key=sign-kailu-855c74a88b8b494187c99b08b8c9a744")
///
/// sessionKey 是服务端下发的 loginCode
class KlcxkjSigner {
  static const String _outerKey = '&key=sign-kailu-855c74a88b8b494187c99b08b8c9a744';

  /// 计算签名，返回32位小写hex；参数非法返回null
  static String? signParams(String sessionKey, String raw) {
    if (sessionKey.isEmpty) return null;
    try {
      final inner = _md5Hex(raw + '&key=$sessionKey');
      return _md5Hex(inner + _outerKey);
    } catch (_) {
      return null;
    }
  }

  static String _md5Hex(String s) {
    return md5.convert(utf8.encode(s)).toString();
  }
}
