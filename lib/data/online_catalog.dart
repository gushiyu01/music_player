import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'audio_tags.dart';
import 'baidu_client.dart';
import 'song_details_repository.dart';

class CatalogResult {
  const CatalogResult({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.lyrics,
    this.duration,
  });
  final String id, title, artist, album;
  final String? lyrics;
  final int? duration;
}

class OnlineCatalog {
  OnlineCatalog({http.Client? client}) : client = client ?? http.Client();
  // This client never receives Baidu session headers, access tokens or audio.
  final http.Client client;
  static const userAgent =
      'YunjianMusic/0.3.0 (https://github.com/gushiyu01/music_player)';
  DateTime _next = DateTime(2000);
  bool _requesting = false;

  Future<http.StreamedResponse> _request(Uri uri, {bool image = false}) async {
    final wait = _next.difference(DateTime.now());
    if (_requesting || wait.inMilliseconds > 1500) {
      throw const DriveException('请求较快，请稍后再试', code: 'rate_limited');
    }
    _requesting = true;
    try {
      if (!wait.isNegative) await Future<void>.delayed(wait);
      var current = uri;
      for (var hop = 0; hop < 6; hop++) {
        if (image && !_coverHost(current)) {
          throw const FormatException('封面地址不受信任');
        }
        final response = await client
            .send(
              http.Request('GET', current)
                ..followRedirects = false
                ..headers['User-Agent'] = userAgent,
            )
            .timeout(const Duration(seconds: 20));
        if ([429, 503].contains(response.statusCode)) {
          final retry = response.headers['retry-after'];
          final seconds = int.tryParse(retry ?? '');
          final deadline = seconds != null
              ? DateTime.now().add(Duration(seconds: seconds + 1))
              : _httpDate(retry);
          _next = deadline ?? DateTime.now().add(const Duration(seconds: 30));
          await response.stream.listen((_) {}).cancel();
          throw const DriveException('资料服务繁忙，请稍后再试', code: 'rate_limited');
        }
        if (image && [301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers['location'];
          await response.stream.listen((_) {}).cancel();
          if (location == null) break;
          current = current.resolve(location);
          if (current.scheme == 'http') {
            current = current.replace(scheme: 'https');
          }
          continue;
        }
        if (response.statusCode != 200) {
          await response.stream.listen((_) {}).cancel();
          throw DriveException(
            response.statusCode == 404
                ? '这个版本没有可用资料，请选择其他候选或从手机导入'
                : '资料服务暂时不可用，请稍后重试',
            code: 'catalog_error',
          );
        }
        return response;
      }
      throw const FormatException('封面跳转次数过多');
    } finally {
      _requesting = false;
      if (_next.isBefore(DateTime.now())) {
        _next = DateTime.now().add(const Duration(milliseconds: 1200));
      }
    }
  }

  DateTime? _httpDate(String? value) {
    try {
      return HttpDate.parse(value!);
    } catch (_) {
      return null;
    }
  }

  static bool _coverHost(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (uri.host == 'coverartarchive.org' ||
          uri.host == 'archive.org' ||
          uri.host.endsWith('.archive.org'));

  Future<dynamic> _json(Uri uri) async {
    final response = await _request(uri);
    final bytes = await SongDetailsRepository.readLimited(
      response.stream,
      1024 * 1024,
    );
    return jsonDecode(utf8.decode(bytes));
  }

  Future<List<CatalogResult>> lyrics(String title, String artist) async {
    if (title.trim().isEmpty) throw const FormatException('请填写歌名');
    final value = await _json(
      Uri.https('lrclib.net', '/api/search', {
        'track_name': title.trim(),
        if (artist.trim().isNotEmpty) 'artist_name': artist.trim(),
      }),
    );
    if (value is! List) throw const FormatException('歌词响应格式异常');
    final results = <CatalogResult>[];
    for (final item in value.whereType<Map>().take(30)) {
      final synced = item['syncedLyrics'];
      final plain = item['plainLyrics'];
      final text = synced is String && synced.trim().isNotEmpty
          ? synced
          : plain is String && plain.trim().isNotEmpty
          ? plain
          : null;
      if (text != null) {
        results.add(
          CatalogResult(
            id: '${item['id']}',
            title: '${item['trackName'] ?? title}',
            artist: '${item['artistName'] ?? artist}',
            album: '${item['albumName'] ?? ''}',
            duration: (item['duration'] as num?)?.round(),
            lyrics: text,
          ),
        );
      }
    }
    return results;
  }

  static String _quoted(String text) =>
      '"${text.replaceAll(RegExp(r'["\\]'), ' ')}"';
  Future<List<CatalogResult>> covers(String title, String artist) async {
    if (title.trim().isEmpty) throw const FormatException('请填写歌名');
    final query =
        'recording:${_quoted(title.trim())}${artist.trim().isEmpty ? '' : ' AND artist:${_quoted(artist.trim())}'}';
    final value = await _json(
      Uri.https('musicbrainz.org', '/ws/2/recording', {
        'query': query,
        'fmt': 'json',
        'limit': '10',
      }),
    );
    if (value is! Map || value['recordings'] is! List) {
      throw const FormatException('封面响应格式异常');
    }
    final results = <String, CatalogResult>{};
    for (final record in (value['recordings'] as List).whereType<Map>()) {
      final credits = (record['artist-credit'] as List? ?? [])
          .whereType<Map>()
          .map((c) => '${c['name'] ?? ''}')
          .join(' / ');
      for (final release
          in (record['releases'] as List? ?? []).whereType<Map>()) {
        final id = '${release['id']}';
        if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) continue;
        results[id] = CatalogResult(
          id: id,
          title: '${record['title'] ?? title}',
          artist: credits,
          album: '${release['title'] ?? ''}',
          duration: (record['length'] as num?)?.round() == null
              ? null
              : (record['length'] as num).round() ~/ 1000,
        );
      }
    }
    return results.values.take(30).toList();
  }

  Future<Uint8List> coverBytes(CatalogResult result) async {
    if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(result.id)) {
      throw const FormatException('无效的封面 ID');
    }
    final response = await _request(
      Uri.https('coverartarchive.org', '/release/${result.id}/front-500'),
      image: true,
    );
    return SongDetailsRepository.readLimited(
      response.stream,
      AudioTags.maxCover,
    );
  }

  void dispose() => client.close();
}
