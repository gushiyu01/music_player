import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DriveSession {
  const DriveSession({
    this.appKey = '',
    this.secretKey = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.expiresAt = 0,
  });

  factory DriveSession.fromJson(Map<String, dynamic> json) => DriveSession(
    appKey: json['appKey'] as String? ?? '',
    secretKey: json['secretKey'] as String? ?? '',
    accessToken: json['accessToken'] as String? ?? '',
    refreshToken: json['refreshToken'] as String? ?? '',
    expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
  );

  final String appKey;
  final String secretKey;
  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  bool get connected => accessToken.isNotEmpty;
  bool get canRefresh =>
      appKey.isNotEmpty && secretKey.isNotEmpty && refreshToken.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'appKey': appKey,
    'secretKey': secretKey,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt,
  };
}

abstract class SessionStore {
  Future<DriveSession> read();
  Future<void> write(DriveSession session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'music_player.baidu.session.v1';
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<DriveSession> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return const DriveSession();
    try {
      return DriveSession.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } on FormatException {
      return const DriveSession();
    }
  }

  @override
  Future<void> write(DriveSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));
  @override
  Future<void> clear() => _storage.delete(key: _key);
}
