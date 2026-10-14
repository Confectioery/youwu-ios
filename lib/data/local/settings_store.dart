import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置存储（基于SharedPreferences）
class SettingsStore {
  static const _keyAccount = 'school_account';
  static const _keyPasswordEnc = 'school_password_enc';
  static const _keyTermStart = 'term_start_';
  static const _keyTermWeeks = 'term_weeks';
  static const _keyShowWeekend = 'show_weekend';
  static const _keyAutoUpdate = 'auto_update';
  static const _keyLastSyncXnm = 'last_sync_xnm';
  static const _keyLastSyncTerm = 'last_sync_term';
  static const _keyLastSyncTime = 'last_sync_time';
  static const _keyWaterToken = 'water_token';
  static const _keyWaterDevice = 'water_device_id';
  static const _keyShowerPhone = 'shower_phone';
  static const _keyShowerToken = 'shower_token';
  static const _keyShowerAuth = 'shower_auth_json';
  static const _keyShowerDevice = 'shower_device_json';

  Future<String> get account async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccount) ?? '';
  }

  Future<void> setAccount(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccount, v);
  }

  Future<String> get passwordEnc async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPasswordEnc) ?? '';
  }

  Future<void> setPasswordEnc(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPasswordEnc, v);
  }

  Future<DateTime?> getTermStart(int xnm, int term) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('$_keyTermStart${xnm}_$term');
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  Future<void> setTermStart(DateTime date, int xnm, int term) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_keyTermStart${xnm}_$term', date.millisecondsSinceEpoch);
  }

  Future<bool> hasTermStartFor(int xnm, int term) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_keyTermStart${xnm}_$term');
  }

  Future<int> get termWeeks async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyTermWeeks) ?? 20;
  }

  Future<void> setTermWeeks(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTermWeeks, v);
  }

  Future<bool> get showWeekend async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowWeekend) ?? false;
  }

  Future<void> setShowWeekend(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowWeekend, v);
  }

  Future<bool> get autoUpdate async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoUpdate) ?? false;
  }

  Future<void> setAutoUpdate(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoUpdate, v);
  }

  Future<void> setLastSync(int xnm, int term, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSyncXnm, xnm);
    await prefs.setInt(_keyLastSyncTerm, term);
    await prefs.setInt(_keyLastSyncTime, time.millisecondsSinceEpoch);
  }

  Future<(int, int, DateTime)?> get lastSync async {
    final prefs = await SharedPreferences.getInstance();
    final xnm = prefs.getInt(_keyLastSyncXnm);
    final term = prefs.getInt(_keyLastSyncTerm);
    final time = prefs.getInt(_keyLastSyncTime);
    if (xnm == null || term == null || time == null) return null;
    return (xnm, term, DateTime.fromMillisecondsSinceEpoch(time));
  }

  // 饮水服务
  Future<String> get waterToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWaterToken) ?? '';
  }

  Future<void> setWaterToken(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWaterToken, v);
  }

  Future<String> get waterDeviceId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWaterDevice) ?? '';
  }

  Future<void> setWaterDeviceId(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWaterDevice, v);
  }

  // 洗澡服务
  Future<String> get showerPhone async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyShowerPhone) ?? '';
  }

  Future<void> setShowerPhone(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShowerPhone, v);
  }

  Future<String> get showerToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyShowerToken) ?? '';
  }

  Future<void> setShowerToken(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShowerToken, v);
  }

  // 洗澡完整认证信息（JSON）
  Future<String> get showerAuthJson async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyShowerAuth) ?? '';
  }

  Future<void> setShowerAuthJson(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShowerAuth, v);
  }

  // 洗澡绑定设备（JSON）
  Future<String> get showerDeviceJson async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyShowerDevice) ?? '';
  }

  Future<void> setShowerDeviceJson(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShowerDevice, v);
  }
}
