import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble/ble_controller.dart';
import 'ble/ble_frame.dart';
import 'ble/klcxkj_crypto.dart';
import 'ble/device_query_state.dart';
import 'shower_api.dart';

/// 蓝牙会话（本地持久化的交易信息）
class BleSession {
  final String sn;
  final String mac;
  final String consumeDate;
  final String orderNo;
  final String accountPhone;

  const BleSession({
    required this.sn,
    required this.mac,
    required this.consumeDate,
    required this.orderNo,
    this.accountPhone = '',
  });

  Map<String, dynamic> toJson() => {
        'sn': sn,
        'mac': mac,
        'consumeDate': consumeDate,
        'orderNo': orderNo,
        'accountPhone': accountPhone,
      };

  factory BleSession.fromJson(Map<String, dynamic> json) => BleSession(
        sn: json['sn'] as String? ?? '',
        mac: json['mac'] as String? ?? '',
        consumeDate: json['consumeDate'] as String? ?? '',
        orderNo: json['orderNo'] as String? ?? '',
        accountPhone: json['accountPhone'] as String? ?? '',
      );
}

/// 开水结果
sealed class BleOpenResult {
  const BleOpenResult();
}

class BleOpened extends BleOpenResult {
  final BleSession session;
  const BleOpened(this.session);
}

class BleResumed extends BleOpenResult {
  final BleSession session;
  const BleResumed(this.session);
}

class BleRecovered extends BleOpenResult {
  final String message;
  const BleRecovered(this.message);
}

class BleUnconfirmed extends BleOpenResult {
  final String message;
  const BleUnconfirmed(this.message);
}

class BleOpenFailed extends BleOpenResult {
  final String message;
  const BleOpenFailed(this.message);
}

/// 检查结果
sealed class BleInspection {
  const BleInspection();
}

class BleRunning extends BleInspection {
  const BleRunning();
}

class BleSettled extends BleInspection {
  const BleSettled();
}

class BlePending extends BleInspection {
  final String message;
  const BlePending(this.message);
}

/// 洗澡蓝牙控制器（业务逻辑层）
///
/// 对应Android的 ShowerBleController.kt
/// 整合BLE GATT控制和趣智校园API，实现开水/关水/结算完整流程
class ShowerBleController {
  final BleController _ble;
  final ShowerApi _api;

  /// iOS必须先扫描再连接，用户选择的设备存在这里
  BluetoothDevice? selectedDevice;

  ShowerBleController({BleController? ble, ShowerApi? api})
      : _ble = ble ?? BleController(),
        _api = api ?? ShowerApi();

  bool get isBluetoothOn => true;
  void disconnect() => _ble.disconnect();

  /// 扫描附近的蓝牙水表
  Future<List<ScannedDevice>> scanDevices() => _ble.scanDevices();

  /// 连接已选择的设备（iOS必须先扫描选择）
  Future<String?> _connect() async {
    if (selectedDevice == null) return '请先扫描并选择热水器';
    final result = await _ble.connectDevice(selectedDevice!);
    return switch (result) {
      BleReady() => null,
      BleNoService() => '设备没有蓝牙水控服务，请检查绑定的设备',
      BleFailed(:final reason) => reason,
    };
  }

  /// 开水
  Future<BleOpenResult> open(
    ShowerDevice device,
    ShowerAuth auth, {
    BleSession? previous,
    void Function(BleSession)? onPrepared,
  }) async {
    if (previous != null &&
        previous.accountPhone.isNotEmpty &&
        previous.accountPhone != auth.phone) {
      return const BleOpenFailed('请使用开水时的账户');
    }

    if (selectedDevice == null) {
      return const BleOpenFailed('请先扫描并选择热水器');
    }

    final connErr = await _connect();
    if (connErr != null) return BleOpenFailed(connErr);

    final state = await _ble.query();
    if (state == null) {
      return const BleOpenFailed('设备未响应，请靠近热水器重试');
    }

    // state=3或6：有遗留未结算记录，先结算
    if (state.state == 3 || state.state == 6) {
      final err = await _settle(state, auth);
      _ble.disconnect();
      if (err == null) {
        return const BleRecovered('上一笔用水已结算，请再点一次开水');
      }
      return BleOpenFailed(err);
    }

    // state!=0：设备正在使用中
    if (state.state != 0) {
      if (previous?.sn == device.sn) {
        return BleResumed(previous!);
      }
      return const BleOpenFailed('设备正在使用中');
    }

    if (previous != null) {
      return const BleOpenFailed('上次开水结果待确认，请先刷新状态');
    }

    // 获取费率
    late final ShowerBleRate rate;
    try {
      rate = await _api.bleRate(auth, device, state);
    } on ShowerSessionExpired {
      rethrow;
    } catch (e) {
      return BleOpenFailed(e.toString());
    }

    final session = BleSession(
      sn: device.sn,
      mac: device.controlMac,
      consumeDate: rate.consumeDate,
      orderNo: rate.orderNo,
      accountPhone: auth.phone,
    );
    onPrepared?.call(session);

    // 下发费率包开阀
    final ok = await _ble.writeRate(Uint8List.fromList(rate.data));
    if (!ok) {
      return const BleUnconfirmed('开水指令已发送，但设备未确认。请核对水流后刷新状态');
    }
    return BleOpened(session);
  }

  /// 确认正在用水（只读，不发命令）
  Future<bool> confirmRunning(BleSession session, ShowerAuth auth) async {
    if (session.accountPhone.isNotEmpty && session.accountPhone != auth.phone) {
      return false;
    }
    if (await _connect() != null) return false;
    final state = await _ble.query(timeout: const Duration(seconds: 1));
    if (state == null) return false;
    return state.state != 0 && state.state != 3 && state.state != 6;
  }

  /// 检查用水状态
  Future<BleInspection> inspect(BleSession session, ShowerAuth auth) async {
    if (session.accountPhone.isNotEmpty && session.accountPhone != auth.phone) {
      return const BlePending('请使用开水时的账户');
    }
    final connErr = await _connect();
    if (connErr != null) return BlePending(connErr);

    final state = await _ble.query();
    if (state == null) return const BlePending('设备未响应，请靠近后重试');

    if (state.state == 0) return const BleSettled();
    if (state.state == 3 || state.state == 6) {
      final err = await _settle(state, auth);
      return err == null ? const BleSettled() : BlePending(err);
    }
    return const BleRunning();
  }

  /// 关水并结算
  Future<BleInspection> close(BleSession session, ShowerAuth auth) async {
    if (session.accountPhone.isNotEmpty && session.accountPhone != auth.phone) {
      return const BlePending('请使用开水时的账户');
    }
    final connErr = await _connect();
    if (connErr != null) return BlePending(connErr);

    final before = await _ble.query();
    if (before == null) return const BlePending('设备未响应，未发送关水指令');

    // 已经关阀
    if (before.state == 0) return const BleSettled();

    // 有待结算记录
    if (before.state == 3 || before.state == 6) {
      final err = await _settle(before, auth);
      return err == null ? const BleSettled() : BlePending(err);
    }

    // 发送关阀命令
    if (!await _ble.closeValve()) {
      return const BlePending('关水未确认，请检查水流并重试');
    }

    // 断开重连（避免原连接结算出无效账单）
    _ble.disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    var err = await _connect();
    if (err != null) {
      await Future.delayed(const Duration(milliseconds: 500));
      err = await _connect();
    }
    if (err != null) {
      return const BlePending('水已关闭，但结算未完成；靠近设备后点击重试');
    }

    final after = await _ble.query();
    if (after == null) return const BlePending('水已关闭，但结算状态未确认');

    final settleErr = await _settle(after, auth);
    if (settleErr != null) {
      try {
        await _api.bleFail(auth, session.consumeDate);
      } catch (_) {}
      return BlePending('水已关闭，但结算未完成：$settleErr');
    }
    return const BleSettled();
  }

  /// 结算：采集消费数据 -> 上传服务端 -> 解密写回数据 -> 写回设备
  Future<String?> _settle(DeviceQueryState state, ShowerAuth auth) async {
    final payload = await _ble.collect();
    if (payload == null || payload.isEmpty) {
      return '未能读取设备消费数据';
    }

    late final ShowerBleUpload upload;
    try {
      upload = await _api.bleUpload(auth, state, payload);
    } on ShowerSessionExpired {
      rethrow;
    } catch (e) {
      return e.toString();
    }

    // 解密服务端返回的写回数据
    final plain = KlcxkjCrypto.decryptByAes(upload.clData);
    if (plain == null) {
      return '结算已上传，但写回数据解密失败，请重试';
    }

    // 解析写回帧（格式："xxxxx-HEXDATA"）
    final hexPart = plain.contains('-') ? plain.split('-').last : plain;
    final back = BleFrame.fromHex(hexPart);
    if (back.isEmpty) {
      return '结算已上传，但写回数据无效，请重试';
    }

    final ok = await _ble.writeBack(back);
    return ok ? null : '结算已上传，但设备写回失败，请重试';
  }

  void dispose() {
    _ble.dispose();
    _api.close();
  }
}
