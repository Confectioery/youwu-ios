import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

/// 凯路设备域 AES 加解密
///
/// 对应Android的 KlcxkjCrypto.kt
/// 算法：AES-128-ECB，密钥 "20210118klcx@002"
/// 密文：标准Base64
/// 用于结算写回 clData 的解密
class KlcxkjCrypto {
  static const String _aesKey = '20210118klcx@002';

  /// AES解密（设备域 clData）
  /// 返回解密后的明文；失败返回null
  /// 明文格式是 <前缀>-<dataHex>，取 - 之后那段才是要写回设备的0x86数据
  static String? decryptByAes(String? cipher) {
    if (cipher == null || cipher.isEmpty) return null;
    try {
      final decoded = base64Decode(cipher);
      if (decoded.isEmpty || decoded.length % 16 != 0) return null;

      final key = Key(Uint8List.fromList(utf8.encode(_aesKey)));
      final encrypter = Encrypter(AES(key, mode: AESMode.ecb, padding: null));
      final decrypted = encrypter.decrypt(Encrypted(decoded));

      return _stripPaddingToText(utf8.encode(decrypted));
    } catch (_) {
      return null;
    }
  }

  /// 去填充 + 转文本（对齐native语义）
  /// - 末字节last满足1..n时校验末尾last字节是否都等于last（PKCS#7）
  /// - last==0或>n视为无填充
  /// - 最后按C字符串截断（到第一个0x00）
  static String _stripPaddingToText(List<int> decrypted) {
    final n = decrypted.length;
    if (n == 0) return '';
    final last = decrypted[n - 1] & 0xFF;
    var effective = decrypted;
    if (last >= 1 && last <= n) {
      final start = n - last;
      var valid = true;
      for (var i = n - 1; i >= start; i--) {
        if ((decrypted[i] & 0xFF) != last) {
          valid = false;
          break;
        }
      }
      if (valid) {
        effective = decrypted.sublist(0, n - last);
      }
    }
    final zeroIndex = effective.indexWhere((b) => b == 0);
    final end = zeroIndex >= 0 ? zeroIndex : effective.length;
    return utf8.decode(effective.sublist(0, end), allowMalformed: true);
  }
}
