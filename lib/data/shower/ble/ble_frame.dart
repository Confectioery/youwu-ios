import 'dart:typed_data';

/// 蓝牙水表帧编解码
///
/// 协议基于林宇(LinYu) MIT实现逆向
/// 帧格式：[命令码] + [payload] + [0x0A 帧尾]
class BleFrame {
  static const int wireEnd = 0x0A;

  // 命令码
  static const int cmdQuery = 0x23; // 查询状态
  static const int cmdRate = 0x21; // 下发费率包(开阀)
  static const int cmdClose = 0x22; // 关阀
  static const int cmdCollect = 0x85; // 采集消费数据
  static const int cmdWriteBack = 0x86; // 写回设备存储

  static const int ackOk = 0x80; // 应答成功字节

  /// 命令转线上帧：[cmd] + data + [0x0A]
  static Uint8List cmdToWire(int cmd, [List<int> data = const []]) {
    final wire = Uint8List(1 + data.length + 1);
    wire[0] = cmd;
    wire.setRange(1, 1 + data.length, data);
    wire[wire.length - 1] = wireEnd;
    return wire;
  }

  /// 解析线上帧，返回帧内容（不含帧尾），失败返回null
  static Uint8List? parseWire(Uint8List wire) {
    if (wire.isEmpty) return null;
    if (wire.last != wireEnd) return null;
    return Uint8List.fromList(wire.sublist(0, wire.length - 1));
  }

  /// 从帧中取命令码
  static int cmdOf(Uint8List frame) => frame.isEmpty ? 0 : frame[0];

  /// 从帧中取payload（命令码之后的数据）
  static Uint8List? payloadOf(Uint8List frame) {
    if (frame.length < 2) return null;
    return Uint8List.fromList(frame.sublist(1));
  }

  /// 字节转hex字符串
  static String toHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
  }

  /// hex字符串转字节
  static Uint8List fromHex(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
