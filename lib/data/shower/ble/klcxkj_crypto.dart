import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';

/// 康蓝科技(Klcxkj)蓝牙水表AES加解密
///
/// 对应Android的 KlcxkjCrypto.kt
/// 结算数据通过AES加密传输，需要解密后解析写回帧
class KlcxkjCrypto {
  static const String _key = 'klcxkj_ble_water_2024'; // 设备厂商固定密钥

  static Key get _encKey {
    final bytes = utf8.encode(_key);
    final padded = List<int>.filled(16, 0);
    for (var i = 0; i < bytes.length && i < 16; i++) {
      padded[i] = bytes[i];
    }
    return Key(Uint8List.fromList(padded));
  }

  /// AES解密结算返回的clData
  /// 返回明文，失败返回null
  static String? decryptByAes(String? hexData) {
    if (hexData == null || hexData.isEmpty) return null;
    try {
      final data = _hexToBytes(hexData);
      if (data.length < 16) return null;
      // 前16字节为IV，后面为密文
      final iv = IV(Uint8List.fromList(data.sublist(0, 16)));
      final cipherText = data.sublist(16);
      final encrypter = Encrypter(AES(_encKey, mode: AESMode.cbc, padding: 'PKCS7'));
      final plain = encrypter.decrypt(Encrypted(Uint8List.fromList(cipherText)), iv: iv);
      return plain;
    } catch (_) {
      return null;
    }
  }

  /// AES加密
  static String encryptByAes(String plaintext) {
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(_encKey, mode: AESMode.cbc, padding: 'PKCS7'));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    final result = Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
    return _bytesToHex(result);
  }

  /// MD5签名
  static String md5Sign(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
