import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/drive_entry.dart';
import 'session_store.dart';

class DriveException implements Exception {
  const DriveException(this.message, {this.code = '', this.status});
  final String message;
  final String code;
  final int? status;
  @override
  String toString() => message;
}

class DeviceGrant {
  const DeviceGrant(
    this.deviceCode,
    this.userCode,
    this.verificationUrl,
    this.expiresIn,
    this.interval,
  );
  final String deviceCode;
  final String userCode;
  final Uri verificationUrl;
  final int expiresIn;
  final int interval;
}

bool isAllowedDownload(Uri uri) {
  final host = uri.host.toLowerCase();
  return uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      [
        'baidu.com',
        'baidupcs.com',
        'baidupcs.cn',
      ].any((domain) => host == domain || host.endsWith('.$domain'));
}

class BaiduClient {
  BaiduClient(this.store, {http.Client? client})
    : client = client ?? http.Client();
  final SessionStore store;
  final http.Client client;
  DriveSession session = const DriveSession();
  Future<String>? _refreshing;
  Future<void> _storageWork = Future.value();
  int _generation = 0;
  static const userAgent = 'pan.baidu.com';

  Future<void> initialize() async {
    session = await store.read();
  }

  Future<void> replaceSession(DriveSession value) async {
    final generation = ++_generation;
    session = value;
    await _persist(value, generation);
  }

  Future<void> disconnect() async {
    final generation = ++_generation;
    session = const DriveSession();
    await _persist(session, generation, clear: true);
  }

  Future<void> _persist(
    DriveSession value,
    int generation, {
    bool clear = false,
  }) {
    final next = _storageWork.then((_) async {
      if (generation != _generation) return;
      if (clear) {
        await store.clear();
      } else {
        await store.write(value);
      }
    });
    _storageWork = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  void cancelPendingAuthorization() {
    _generation++;
  }

  Future<void> validateAuthorization() async {
    await _api('nas', {'method': 'uinfo'});
  }

  Future<Map<String, dynamic>> _json(
    Uri uri, {
    Map<String, String>? form,
  }) async {
    try {
      final response =
          await (form == null
                  ? client.get(uri, headers: {'User-Agent': userAgent})
                  : client.post(
                      uri,
                      headers: {'User-Agent': userAgent},
                      body: form,
                    ))
              .timeout(const Duration(seconds: 25));
      if (response.statusCode == 429) {
        throw const DriveException(
          '百度请求过于频繁，请稍后重试',
          code: 'rate_limited',
          status: 429,
        );
      }
      if (response.statusCode >= 500) {
        throw DriveException(
          '百度服务暂时不可用，授权信息已保留，请稍后重试',
          code: 'temporary',
          status: response.statusCode,
        );
      }
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw DriveException(
          '百度返回了无法解析的响应，请稍后重试',
          code: 'invalid_response',
          status: response.statusCode,
        );
      }
      if (data is! Map<String, dynamic>) {
        throw const DriveException('百度响应格式异常', code: 'invalid_response');
      }
      if (data['error'] != null) {
        final code = '${data['error']}';
        throw DriveException(
          _oauthMessage(code),
          code: code,
          status: response.statusCode,
        );
      }
      final errno = data['errno'] ?? data['error_code'];
      if (errno != null && '$errno' != '0') {
        throw DriveException(
          _apiMessage('$errno'),
          code: '$errno',
          status: response.statusCode,
        );
      }
      if (response.statusCode >= 400) {
        throw DriveException(
          '百度请求失败（HTTP ${response.statusCode}）',
          code: 'http',
          status: response.statusCode,
        );
      }
      return data;
    } on DriveException {
      rethrow;
    } on TimeoutException {
      throw const DriveException('连接百度超时，请检查网络后重试', code: 'network');
    } catch (_) {
      throw const DriveException('无法连接百度，请检查网络后重试', code: 'network');
    }
  }

  static String _oauthMessage(String code) => switch (code) {
    'authorization_pending' => '等待你在百度页面完成授权',
    'slow_down' => '请稍候再检查授权结果',
    'invalid_client' => 'AppKey 或 SecretKey 不正确，请检查个人应用配置',
    'invalid_grant' ||
    'expired_token' ||
    'invalid_token' => '授权已过期或被撤销，请重新连接百度网盘',
    'access_denied' || 'authorization_declined' => '你取消了百度授权',
    'server_error' || 'temporarily_unavailable' => '百度授权服务暂时不可用，已有授权已保留',
    _ => '百度授权失败（$code）',
  };

  static String _apiMessage(String code) => switch (code) {
    '-6' || '110' || '111' => '百度授权已失效，请重新连接',
    '-7' => '目录路径不合法或没有访问权限，请检查音乐目录',
    '-9' => '该文件或目录不存在',
    '20011' => '当前应用无权访问此目录，请检查百度应用权限',
    '31326' => '百度拒绝下载请求，请重试或检查下载权限',
    '31360' => '下载链接已过期，请重试播放',
    _ => '百度网盘请求失败（错误码 $code）',
  };

  Future<DeviceGrant> requestDevice(String appKey) async {
    final data = await _json(
      Uri.https('openapi.baidu.com', '/oauth/2.0/device/code', {
        'response_type': 'device_code',
        'client_id': appKey,
        'scope': 'basic,netdisk',
      }),
    );
    final uri = Uri.tryParse('${data['verification_url']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'openapi.baidu.com' ||
        uri.userInfo.isNotEmpty) {
      throw const DriveException('百度返回的授权地址不受信任', code: 'invalid_response');
    }
    final deviceCode = data['device_code'] as String? ?? '';
    final userCode = data['user_code'] as String? ?? '';
    if (deviceCode.isEmpty || userCode.isEmpty) {
      throw const DriveException('百度未返回设备授权码', code: 'invalid_response');
    }
    return DeviceGrant(
      deviceCode,
      userCode,
      uri,
      (data['expires_in'] as num?)?.toInt() ?? 300,
      (data['interval'] as num?)?.toInt() ?? 5,
    );
  }

  Future<void> completeDevice(
    DeviceGrant grant,
    String appKey,
    String secretKey,
  ) async {
    final generation = _generation;
    final data = await _json(
      Uri.https('openapi.baidu.com', '/oauth/2.0/token'),
      form: {
        'grant_type': 'device_token',
        'code': grant.deviceCode,
        'client_id': appKey,
        'client_secret': secretKey,
      },
    );
    if (_generation != generation) {
      throw const DriveException('授权操作已取消', code: 'cancelled');
    }
    await replaceSession(
      _sessionFrom(data, DriveSession(appKey: appKey, secretKey: secretKey)),
    );
  }

  DriveSession _sessionFrom(Map<String, dynamic> data, DriveSession old) {
    final token = data['access_token'] as String? ?? '';
    if (token.isEmpty) {
      throw const DriveException(
        '百度未返回有效 token，原授权已保留',
        code: 'invalid_response',
      );
    }
    return DriveSession(
      appKey: old.appKey,
      secretKey: old.secretKey,
      accessToken: token,
      refreshToken: data['refresh_token'] as String? ?? old.refreshToken,
      expiresAt:
          DateTime.now().millisecondsSinceEpoch +
          ((data['expires_in'] as num?)?.toInt() ?? 2592000) * 1000,
    );
  }

  Future<String> accessToken({String? rejectedToken}) async {
    if (!session.connected) {
      throw const DriveException('请先连接自己的百度网盘', code: 'not_connected');
    }
    if (rejectedToken != null && session.accessToken != rejectedToken) {
      return session.accessToken;
    }
    final expiring =
        session.expiresAt > 0 &&
        session.expiresAt < DateTime.now().millisecondsSinceEpoch + 60000;
    if (rejectedToken == null && !expiring) return session.accessToken;
    if (!session.canRefresh) {
      throw const DriveException(
        '此 token 已失效，请导入新 token 或重新授权',
        code: 'expired_token',
      );
    }
    if (_refreshing case final pending?) return pending;
    final future = _refresh();
    _refreshing = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<String> _refresh() async {
    final old = session;
    final generation = _generation;
    final data = await _json(
      Uri.https('openapi.baidu.com', '/oauth/2.0/token'),
      form: {
        'grant_type': 'refresh_token',
        'refresh_token': old.refreshToken,
        'client_id': old.appKey,
        'client_secret': old.secretKey,
      },
    );
    if (_generation != generation) {
      throw const DriveException('连接已更改，请重新操作', code: 'cancelled');
    }
    final value = _sessionFrom(data, old);
    await _persist(value, generation);
    if (_generation != generation) {
      throw const DriveException('连接已更改', code: 'cancelled');
    }
    session = value;
    return value.accessToken;
  }

  Future<Map<String, dynamic>> _api(
    String endpoint,
    Map<String, String> query,
  ) async {
    var token = await accessToken();
    final generation = _generation;
    Future<Map<String, dynamic>> invoke() => _json(
      Uri.https('pan.baidu.com', '/rest/2.0/xpan/$endpoint', {
        ...query,
        'access_token': token,
      }),
    );
    try {
      return await invoke();
    } on DriveException catch (error) {
      if (!['-6', '110', '111'].contains(error.code)) rethrow;
      if (_generation != generation) {
        throw const DriveException('连接已更改', code: 'cancelled');
      }
      token = await accessToken(rejectedToken: token);
      return invoke();
    }
  }

  Future<DirectoryPage> listDirectory(
    String dir, {
    int start = 0,
    int limit = 200,
  }) async {
    if (!dir.startsWith('/')) {
      throw const DriveException('目录必须以 / 开头', code: 'bad_path');
    }
    final data = await _api('file', {
      'method': 'list',
      'dir': dir,
      'order': 'name',
      'start': '$start',
      'limit': '$limit',
      'web': '1',
    });
    if (data['list'] is! List) {
      throw const DriveException('目录响应缺少文件列表', code: 'invalid_response');
    }
    final raw = (data['list'] as List).cast<Map<String, dynamic>>();
    return DirectoryPage(
      raw.map(DriveEntry.fromJson).toList(),
      raw.length < limit ? null : start + raw.length,
    );
  }

  Future<Uri> downloadLink(DriveEntry entry) async {
    if (!RegExp(r'^\d+$').hasMatch(entry.id)) {
      throw const DriveException('无效的文件 ID', code: 'bad_id');
    }
    final data = await _api('multimedia', {
      'method': 'filemetas',
      'fsids': '[${entry.id}]',
      'dlink': '1',
    });
    final list = data['list'] as List? ?? [];
    if (list.isEmpty) {
      throw const DriveException('百度未返回该文件的信息', code: 'not_found');
    }
    final item = list.first as Map<String, dynamic>;
    if (item['errno'] != null && item['errno'] != 0) {
      throw DriveException(
        _apiMessage('${item['errno']}'),
        code: '${item['errno']}',
      );
    }
    final uri = Uri.tryParse(item['dlink'] as String? ?? '');
    if (uri == null || !isAllowedDownload(uri)) {
      throw const DriveException('下载地址不是受信任的百度 HTTPS 地址', code: 'unsafe_link');
    }
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'access_token': await accessToken(),
      },
    );
  }

  Future<http.StreamedResponse> openStream(
    DriveEntry entry, {
    int? start,
    int? end,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      var uri = await downloadLink(entry);
      for (var hop = 0; hop <= 5; hop++) {
        if (!isAllowedDownload(uri)) {
          throw const DriveException('百度下载跳转到了不受信任的地址', code: 'unsafe_link');
        }
        final request = http.Request('GET', uri)..followRedirects = false;
        request.headers['User-Agent'] = userAgent;
        if (start != null || end != null) {
          request.headers['Range'] =
              'bytes=${start ?? 0}-${end == null ? '' : end - 1}';
        }
        http.StreamedResponse response;
        try {
          response = await client
              .send(request)
              .timeout(const Duration(seconds: 25));
        } catch (_) {
          throw const DriveException('下载连接失败，请检查网络后重试', code: 'network');
        }
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers['location'];
          await response.stream.listen((_) {}).cancel();
          if (location == null || hop == 5) {
            throw const DriveException('百度下载跳转异常', code: 'redirect');
          }
          uri = uri.resolve(location);
          continue;
        }
        if ([200, 206].contains(response.statusCode)) {
          if ((start ?? 0) > 0 && response.statusCode == 200) {
            await response.stream.listen((_) {}).cancel();
            throw const DriveException(
              '下载端未接受分段请求，请从头播放',
              code: 'range_ignored',
              status: 200,
            );
          }
          return response;
        }
        await response.stream.listen((_) {}).cancel();
        if ([401, 403, 410].contains(response.statusCode) && attempt == 0) {
          break;
        }
        throw DriveException(
          switch (response.statusCode) {
            401 || 403 => '百度拒绝下载，请重新授权或检查下载权限',
            416 => '播放进度超出文件范围，请从头播放',
            429 => '百度下载限流，请稍后重试',
            >= 500 => '百度下载服务暂时不可用，请稍后重试',
            _ => '下载失败（HTTP ${response.statusCode}）',
          },
          code: 'download_${response.statusCode}',
          status: response.statusCode,
        );
      }
    }
    throw const DriveException('重新获取下载链接后仍无法播放，请稍后重试', code: 'download_failed');
  }
}
