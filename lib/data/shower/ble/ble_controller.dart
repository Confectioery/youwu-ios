import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_frame.dart';

/// 设备状态帧解析结果
class DeviceQueryState {
  final String protocolType; // 协议版本，如"20"
  final String randomNumber; // 设备随机数，8位hex
  final int state; // 0=空闲, 1=使用中, 3/6=待结算
  final int devType; // MAC类型第1字节
  final int a1; // MAC类型第2字节

  const DeviceQueryState({
    required this.protocolType,
    required this.randomNumber,
    required this.state,
    required this.devType,
    required this.a1,
  });
}

/// 连接结果
sealed class BleConnectResult {
  const BleConnectResult();
}

class BleReady extends BleConnectResult {
  const BleReady();
}

class BleNoService extends BleConnectResult {
  const BleNoService();
}

class BleFailed extends BleConnectResult {
  final String reason;
  const BleFailed(this.reason);
}

/// 蓝牙水表GATT连接管理器
///
/// 对应Android的 BleController.kt
/// 使用 flutter_blue_plus 实现，把回调式API封装为顺序调用
class BleController {
  static const String serviceUuid = '0000FF00-0000-1000-8000-00805F9B34FB';
  static const String notifyUuid = '0000FF01-0000-1000-8000-00805F9B34FB';
  static const String writeUuid = '0000FF02-0000-1000-8000-00805F9B34FB';

  static const int chunkSize = 20; // BLE MTU-3
  static const int chunkGapMs = 20;
  static const Duration defaultTimeout = Duration(seconds: 8);
  static const Duration connectTimeout = Duration(seconds: 15);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;

  final StreamController<(int, Uint8List)> _incoming = StreamController.broadcast();
  final BytesBuilder _rxBuf = BytesBuilder();
  bool _ready = false;
  bool _sawNoService = false;

  bool get isReady => _ready;
  bool get isBluetoothOn => true; // flutter_blue_plus 有单独的状态检查

  /// MAC地址归一化：服务端给的无冒号格式 -> Android/iOS需要的带冒号格式
  /// 注意：iOS上CoreBluetooth用的是UUID而非MAC，这里保留MAC用于服务端接口
  String? normalizeMac(String raw) {
    final plain = raw.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    if (plain.length != 12 || !RegExp(r'^[0-9A-F]{12}$').hasMatch(plain)) {
      return null;
    }
    return plain.replaceAllMapped(RegExp(r'.{2}'), (m) => '${m.group(0)}:').replaceAll(RegExp(r':$'), '');
  }

  /// 连接到设备并等待服务发现+通知开启
  ///
  /// [deviceId] 在iOS上是CoreBluetooth的UUID，在Android上是MAC地址
  Future<BleConnectResult> connect(String deviceId, {Duration timeout = connectTimeout}) async {
    await disconnect();
    _ready = false;
    _sawNoService = false;

    try {
      // iOS通过扫描获取设备，Android可以直接用MAC
      // 这里假设调用方已经通过扫描拿到了BluetoothDevice
      // 如果只有MAC，需要先扫描找到设备
      _device = BluetoothDevice.fromId(deviceId);

      await _device!.connect(timeout: timeout).catchError((e) {
        return BleFailed('连接超时，请靠近设备后重试');
      });

      // 发现服务
      final services = await _device!.discoverServices();
      final svc = services.where((s) => s.uuid.toString().toUpperCase() == serviceUuid).toList();
      if (svc.isEmpty) {
        _sawNoService = true;
        await disconnect();
        return const BleNoService();
      }

      final chars = svc.first.characteristics;
      _notifyChar = chars.where((c) => c.uuid.toString().toUpperCase() == notifyUuid).firstOrNull;
      _writeChar = chars.where((c) => c.uuid.toString().toUpperCase() == writeUuid).firstOrNull;

      if (_notifyChar == null || _writeChar == null) {
        _sawNoService = true;
        await disconnect();
        return const BleNoService();
      }

      // 开启通知
      await _notifyChar!.setNotifyValue(true);
      _notifySub = _notifyChar!.lastValueStream.listen(_onCharacteristicChanged);

      _ready = true;
      return const BleReady();
    } catch (e) {
      return BleFailed('蓝牙连接异常: $e');
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _ready = false;
    await _notifySub?.cancel();
    _notifySub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _rxBuf.clear();
  }

  /// 发送命令并等待对应应答
  Future<Uint8List?> _sendAndAwait(
    int cmd, {
    List<int> data = const [],
    int? replyCmd,
    Duration timeout = defaultTimeout,
  }) async {
    if (!_ready) return null;
    final expected = replyCmd ?? cmd;

    // 先清残留帧（设备可能主动推上一笔未结算的数据）
    await _drainIncoming();

    // 发送
    final wire = BleFrame.cmdToWire(cmd, data);
    if (!await _write(wire)) return null;

    // 等应答
    try {
      final completer = Completer<Uint8List?>();
      late StreamSubscription sub;
      sub = _incoming.stream.listen((frame) {
        if (frame.$1 == expected) {
          sub.cancel();
          if (!completer.isCompleted) completer.complete(frame.$2);
        }
      });
      final result = await completer.future.timeout(timeout, onTimeout: () {
        sub.cancel();
        return null;
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 查询设备状态 (0x23)
  Future<DeviceQueryState?> query({Duration timeout = defaultTimeout}) async {
    final p = await _sendAndAwait(BleFrame.cmdQuery, timeout: timeout);
    if (p == null || p.length < 31) return null;
    return DeviceQueryState(
      protocolType: p[19].toRadixString(16).padLeft(2, '0').toUpperCase(),
      randomNumber: BleFrame.toHex(p.sublist(24, 28)),
      state: p[28],
      devType: p[29],
      a1: p[30],
    );
  }

  /// 下发费率包开阀 (0x21)
  Future<bool> writeRate(Uint8List downData, {Duration timeout = defaultTimeout}) async {
    final p = await _sendAndAwait(BleFrame.cmdRate, data: downData, timeout: timeout);
    return p != null && p.isNotEmpty && p[0] == BleFrame.ackOk;
  }

  /// 关阀 (0x22)
  Future<bool> closeValve({Duration timeout = defaultTimeout}) async {
    final p = await _sendAndAwait(BleFrame.cmdClose, timeout: timeout);
    return p != null && p.isNotEmpty && p[0] == BleFrame.ackOk;
  }

  /// 采集消费数据 (0x85)
  Future<Uint8List?> collect({Duration timeout = defaultTimeout}) async {
    return _sendAndAwait(BleFrame.cmdCollect, timeout: timeout);
  }

  /// 结算结果写回设备 (0x86)
  Future<bool> writeBack(Uint8List data, {Duration timeout = defaultTimeout}) async {
    final p = await _sendAndAwait(BleFrame.cmdWriteBack, data: data, timeout: timeout);
    return p != null && p.isNotEmpty && p[0] == BleFrame.ackOk;
  }

  /// 清空接收缓冲区
  Future<void> _drainIncoming() async {
    _rxBuf.clear();
  }

  /// 分片写入
  Future<bool> _write(Uint8List wire) async {
    final c = _writeChar;
    if (c == null) return false;

    var offset = 0;
    while (offset < wire.length) {
      final len = (offset + chunkSize > wire.length) ? wire.length - offset : chunkSize;
      final chunk = wire.sublist(offset, offset + len);
      try {
        await c.write(chunk, withoutResponse: false);
      } catch (_) {
        return false;
      }
      offset += len;
      if (offset < wire.length) {
        await Future.delayed(const Duration(milliseconds: chunkGapMs));
      }
    }
    return true;
  }

  /// 通知回调：累积字节并按0x0A切帧
  void _onCharacteristicChanged(List<int> bytes) {
    _rxBuf.add(bytes);
    final all = _rxBuf.toBytes();
    final frames = <Uint8List>[];
    var start = 0;
    for (var i = 0; i < all.length; i++) {
      if (all[i] == BleFrame.wireEnd) {
        frames.add(Uint8List.fromList(all.sublist(start, i + 1)));
        start = i + 1;
      }
    }
    if (start < all.length) {
      _rxBuf.clear();
      _rxBuf.add(all.sublist(start));
    } else {
      _rxBuf.clear();
    }

    for (final f in frames) {
      final frame = BleFrame.parseWire(f);
      if (frame == null) continue;
      final cmd = BleFrame.cmdOf(frame);
      final payload = BleFrame.payloadOf(frame) ?? Uint8List(0);
      _incoming.add((cmd, payload));
    }
  }

  void dispose() {
    disconnect();
    _incoming.close();
  }
}
