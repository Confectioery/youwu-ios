import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/course_block.dart';

/// 梧州学院新正方教务系统 API（Dart原生实现，替代Python桥接层）
///
/// 对接 jwxt.gxuwz.edu.cn/jwglxt
/// 登录流程：获取公钥 -> RSA加密密码 -> 提交登录 -> 携带cookie拉取课表
class SchoolApi {
  static const String host = 'jwxt.gxuwz.edu.cn';
  static const String basePath = '/jwglxt';
  static const String baseUrl = 'https://$host$basePath';

  /// 梧州学院作息时间表（第1-12节）
  static const Map<String, List<int>> scheduleTime = {
    '1': [8, 30],
    '2': [9, 20],
    '3': [10, 25],
    '4': [11, 15],
    '5': [14, 40],
    '6': [15, 30],
    '7': [16, 30],
    '8': [17, 20],
    '9': [19, 30],
    '10': [20, 20],
    '11': [21, 10],
    '12': [22, 0],
  };

  final http.Client _client;
  String? _cookie;

  SchoolApi({http.Client? client}) : _client = client ?? http.Client();

  /// 登录教务系统
  /// 返回 true 表示登录成功
  Future<bool> login(String account, String password) async {
    try {
      // 1. 获取登录页，拿cookie
      final loginPage = await _client.get(
        Uri.parse('$baseUrl/xtgl/login_initLogin.html'),
        headers: _headers(),
      );
      _cookie = loginPage.headers['set-cookie'] ?? _extractCookie(loginPage);

      // 2. 获取加密公钥（新正方系统通常需要RSA加密密码）
      final pubKeyResp = await _client.get(
        Uri.parse('$baseUrl/xtgl/login_getPublicKey.html'),
        headers: _headers(withCookie: true),
      );
      String? modulus;
      String? exponent;
      try {
        final pubKeyJson = jsonDecode(pubKeyResp.body);
        modulus = pubKeyJson['modulus'] as String?;
        exponent = pubKeyJson['exponent'] as String?;
      } catch (_) {
        // 部分学校不需要RSA加密，直接明文提交
      }

      // 3. 提交登录
      final loginBody = {
        'yhm': account,
        'mm': modulus != null ? _rsaEncrypt(password, modulus, exponent ?? '10001') : password,
      };

      final resp = await _client.post(
        Uri.parse('$baseUrl/xtgl/login_slogin.html'),
        headers: _headers(withCookie: true, formUrlEncoded: true),
        body: loginBody,
      );

      // 登录成功判断：跳转或返回成功标识
      if (resp.statusCode == 200 || resp.statusCode == 302) {
        final body = resp.body;
        if (body.contains('登录成功') ||
            body.contains('index_cxIndex.html') ||
            resp.headers['location']?.contains('index') == true) {
          _cookie = resp.headers['set-cookie'] ?? _cookie;
          return true;
        }
        // 部分学校登录后直接返回主页
        if (body.contains('首页') || body.contains('退出')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      throw Exception('教务系统登录失败: $e');
    }
  }

  /// 获取课表
  Future<Map<String, dynamic>> fetchSchedule(int year, int term) async {
    // xnm: 学年, xqm: 学期(1=第一学期, 3=第二学期 新正方系统)
    final xqm = term == 1 ? '1' : '3';
    final resp = await _client.post(
      Uri.parse('$baseUrl/kbcx/xskbcx_cxXsgrkb.html'),
      headers: _headers(withCookie: true, formUrlEncoded: true),
      body: {
        'xnm': '$year',
        'xqm': xqm,
        'kzl': 'kcd',
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('课表获取失败: HTTP ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body);
    final kbList = data['kbList'] as List? ?? [];

    // 解析课表列表为统一格式
    final courses = kbList.map((item) {
      final kcmc = item['kcmc'] as String? ?? ''; // 课程名称
      final cdmc = item['cdmc'] as String? ?? ''; // 场地名称(教室)
      final xm = item['xm'] as String? ?? ''; // 教师姓名
      final xqj = item['xqj'] as String? ?? '1'; // 星期几
      final jcs = item['jcs'] as String? ?? '1'; // 节次
      final zcd = item['zcd'] as String? ?? ''; // 周次描述
      final xqmc = item['xqmc'] as String? ?? ''; // 校区名称

      // 解析周次 "1-16周(单)" 或 "1,3,5-8周"
      final weeks = _parseWeeks(zcd);

      return {
        'course': kcmc,
        'place': cdmc,
        'teacher': xm,
        'campus': xqmc,
        'week_day': int.tryParse(xqj) ?? 1,
        'section': jcs,
        'weeks_text': zcd,
        'weeks_arr': weeks,
      };
    }).toList();

    // 获取学生信息
    final xsjbxx = data['xsjbxx'] as Map<String, dynamic>? ?? {};

    return {
      'username': xsjbxx['xm'] ?? '',
      'class_name': xsjbxx['bj'] ?? '',
      'year': year,
      'term': term,
      'courses': courses,
    };
  }

  /// 解析周次文本为周次列表
  /// "1-16周" -> [1,2,...,16]
  /// "1-16周(单)" -> [1,3,5,...,15]
  /// "1,3,5-8周" -> [1,3,5,6,7,8]
  List<int> _parseWeeks(String text) {
    final weeks = <int>{};
    // 去掉"周"字
    final clean = text.replaceAll('周', '').trim();
    // 分割逗号
    final parts = clean.split(',');
    for (final part in parts) {
      final p = part.trim();
      if (p.isEmpty) continue;
      // 判断单双周
      var oddOnly = false;
      var evenOnly = false;
      var range = p;
      if (p.contains('(单)') || p.contains('（单）')) {
        oddOnly = true;
        range = p.replaceAll('(单)', '').replaceAll('（单）', '');
      } else if (p.contains('(双)') || p.contains('（双）')) {
        evenOnly = true;
        range = p.replaceAll('(双)', '').replaceAll('（双）', '');
      }
      // 解析范围
      if (range.contains('-')) {
        final nums = range.split('-');
        final start = int.tryParse(nums[0].trim()) ?? 1;
        final end = int.tryParse(nums[1].trim()) ?? start;
        for (var w = start; w <= end; w++) {
          if (oddOnly && w.isEven) continue;
          if (evenOnly && w.isOdd) continue;
          weeks.add(w);
        }
      } else {
        final w = int.tryParse(range);
        if (w != null) weeks.add(w);
      }
    }
    return weeks.toList()..sort();
  }

  /// RSA加密密码（简化实现，实际需要pointycastle）
  String _rsaEncrypt(String password, String modulus, String exponent) {
    // 完整RSA实现需要pointycastle库
    // 这里返回base64编码的密码作为占位，实际部署时需替换为真正的RSA加密
    // 参考：new-school-sdk 的 login.py 中的 rsa_encrypt 函数
    return base64Encode(utf8.encode(password));
  }

  Map<String, String> _headers({bool withCookie = false, bool formUrlEncoded = false}) {
    final h = {
      'User-Agent': 'Youwu/1.1 (iOS)',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    };
    if (withCookie && _cookie != null) {
      h['Cookie'] = _cookie!;
    }
    if (formUrlEncoded) {
      h['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return h;
  }

  String? _extractCookie(http.Response resp) {
    final sc = resp.headers['set-cookie'];
    if (sc == null) return null;
    // 取第一个cookie的key=value部分
    return sc.split(';').first;
  }

  void close() => _client.close();
}
