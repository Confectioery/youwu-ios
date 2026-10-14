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
