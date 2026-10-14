import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';

/// 简单AES加密（iOS上使用flutter_secure_storage更安全，这里用固定key的AES-GCM简化）
/// 生产环境建议替换为 flutter_secure_storage
class CryptoUtil {
  static const _key = 'youwu_school_key_2026!'; // 32字节以内

  static Key get _encKey {
    final bytes = utf8.encode(_key);
    final padded = List<int>.filled(32, 0);
    for (var i = 0; i < bytes.length && i < 32; i++) {
      padded[i] = bytes[i];
    }
    return Key(Uint8List.fromList(padded));
  }

  static String encrypt(String plaintext) {
    final iv = IV.fromSecureRandom(12);
    final encrypter = Encrypter(AES(_encKey, mode: AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${base64Encode(iv.bytes)}:${encrypted.base64}';
  }

  static String? decrypt(String stored) {
    try {
      final parts = stored.split(':');
      if (parts.length != 2) return null;
      final iv = IV(base64Decode(parts[0]));
      final encrypter = Encrypter(AES(_encKey, mode: AESMode.gcm));
      return encrypter.decrypt(Encrypted.fromBase64(parts[1]), iv: iv);
    } catch (_) {
      return null;
    }
  }

  static String md5Hex(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }
}
