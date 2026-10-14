import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_frame.dart';
import 'device_query_state.dart';

/// 连接结果
sealed class BleConnectResult {
  const BleConnectResult();
}
class BleReady extends BleConnectResult { const BleReady(); }
class BleNoService extends BleConnectResult { const BleNoService(); }
class BleFailed extends BleConnectResult {
  final String reason;
  const BleFailed(this.reason);
}

/// 扫描到的蓝牙设备
class ScannedDevice {
  final BluetoothDevice device;
  final String name;
  final String? mac; // iOS上可能为null
  final int rssi;

  const ScannedDevice({required this.device, required this.name, this.mac, required this.rssi});
}

/// 蓝牙水表GATT连接管理器
///
/// iOS注意：CoreBluetooth不暴露MAC地址，必须先扫描设备，
/// 用扫描到的BluetoothDevice对象连接，不能用MAC地址直连。
class BleController {
  static const String serviceUuid = '0000FF00-0000-1000-8000-00805F9B34FB';
  static const String notifyUuid = '0000FF01-0000-1000-8000-00805F9B34FB';
  static const String writeUuid = '0000FF02-0000-1000-8000-00805F9B34FB';

  static const int chunkSize = 20;
  static const int chunkGapMs = 20;
  static const Duration defaultTimeout = Duration(seconds: 8);
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration scanTimeout = Duration(seconds: 10);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  final StreamController<(int, Uint8List)> _incoming = StreamController.broadcast();
  final BytesBuilder _rxBuf = BytesBuilder();
  bool _ready = false;
  bool _sawNoService = false;

  bool get isReady => _ready;
  bool get isConnected => _device != null && _ready;

  /// 扫描附近的蓝牙水表（过滤FF00服务）
  Future<List<ScannedDevice>> scanDevices({Duration timeout = scanTimeout}) async {
    final results = <String, ScannedDevice>{};
    final completer = Completer<List<ScannedDevice>>();

    try {
      // 检查蓝牙状态
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('蓝牙未开启');
      }

      _scanSub = FlutterBluePlus.scanResults.listen((resultsList) {
        for (final r in resultsList) {
          final id = r.device.remoteId.str;
          // 优先过滤有FF00服务的设备
          final hasWaterService = r.advertisementData.serviceUuids.any(
            (uuid) => uuid.toString().toUpperCase().contains('FF00'),
          );
          if (hasWaterService || results.length < 20) {
            results[id] = ScannedDevice(
              device: r.device,
              name: r.device.platformName.isNotEmpty ? r.device.platformName : (r.advertisementData.localName.isNotEmpty ? r.advertisementData.localName : '未知设备'),
              mac: r.device.remoteId.str,
              rssi: r.rssi,
            );
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout, androidUsesFineLocation: true);
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;

      if (!completer.isCompleted) {
        completer.complete(results.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
      }
    } catch (e) {
      await _scanSub?.cancel();
      _scanSub = null;
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  /// 停止扫描
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
  }

  /// 连接到已扫描到的设备
  Future<BleConnectResult> connectDevice(BluetoothDevice device, {Duration timeout = connectTimeout}) async {
    await disconnect();
    _ready = false;
    _sawNoService = false;
    _device = device;

    try {
      await device.connect(timeout: timeout);
    } catch (e) {
      return BleFailed('连接失败: $e');
    }

    // 发现服务
    List<BluetoothService> services;
    try {
      services = await device.discoverServices();
    } catch (e) {
      return BleFailed('服务发现失败: $e');
    }

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
    try {
      await _notifyChar!.setNotifyValue(true);
      _notifySub = _notifyChar!.lastValueStream.listen(_onCharacteristicChanged);
    } catch (e) {
      return BleFailed('开启通知失败: $e');
    }

    _ready = true;
    return const BleReady();
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

  /// 发送命令并等待应答
  Future<Uint8List?> _sendAndAwait(
    int cmd, {
    List<int> data = const [],
    int? replyCmd,
    Duration timeout = defaultTimeout,
  }) async {
    if (!_ready) return null;
    final expected = replyCmd ?? cmd;
    await _drainIncoming();

    final wire = BleFrame.cmdToWire(cmd, data);
    if (!await _write(wire)) return null;

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
    stopScan();
    _incoming.close();
  }
}
