import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
    this.releaseGroupId,
  });
  final String id, title, artist, album;
  final String? lyrics, releaseGroupId;
  final int? duration;
}

class CatalogException extends DriveException {
  const CatalogException(
    super.message, {
    super.code,
    super.status,
    this.retryAfter,
  });
  final Duration? retryAfter;
}

class OnlineCatalog {
  OnlineCatalog({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 12),
    this.requestGap = const Duration(milliseconds: 1200),
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  }) : client = client ?? http.Client(),
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  // Dedicated client: no Baidu headers, tokens, paths or audio are sent here.
  final http.Client client;
  final Duration requestTimeout, requestGap;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;
  static const userAgent =
      'YunjianMusic/0.4.0 (https://github.com/gushiyu01/music_player)';
  final _queues = <String, Future<void>>{};
  final _next = <String, DateTime>{};
  final _aborts = <Completer<void>>{};
  final _pending = <String, Future<List<CatalogResult>>>{};
  final _cache = <String, ({DateTime expires, List<CatalogResult> items})>{};
  bool _closed = false;

  Future<T> _serial<T>(String service, Future<T> Function() work) async {
    final previous = _queues[service];
    final gate = Completer<void>();
    _queues[service] = gate.future;
    try {
      await previous;
      _checkOpen();
      return await work();
    } finally {
      gate.complete();
      if (identical(_queues[service], gate.future)) _queues.remove(service);
    }
  }

  void _checkOpen() {
    if (_closed) throw const CatalogException('搜索已结束', code: 'cancelled');
  }

  Future<void> _waitTurn(String service) async {
    final wait = (_next[service] ?? _now()).difference(_now());
    if (wait > const Duration(seconds: 4)) {
      final seconds = (wait.inMilliseconds / 1000).ceil();
      throw CatalogException(
        '这个资料服务正在限流，请 $seconds 秒后重试；也可搜索另一种资料',
        code: 'rate_limited',
        retryAfter: wait,
      );
    }
    if (wait > Duration.zero) await _delay(wait);
    _checkOpen();
  }

  static bool _coverHost(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (uri.host == 'coverartarchive.org' ||
          uri.host == 'archive.org' ||
          uri.host.endsWith('.archive.org'));

  DateTime? _retryDeadline(String? value) {
    final seconds = int.tryParse(value ?? '');
    if (seconds != null) {
      return _now().add(
        Duration(
          milliseconds: max(0, seconds) * 1000 + 250 + Random().nextInt(250),
        ),
      );
    }
    try {
      return HttpDate.parse(value!).add(const Duration(milliseconds: 500));
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _get(Uri uri, int maximum, {bool image = false}) =>
      _serial(uri.host, () async {
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            return await _attempt(uri, maximum, image: image);
          } on CatalogException catch (failure) {
            if (attempt == 1 ||
                !['network', 'unavailable'].contains(failure.code)) {
              rethrow;
            }
          } on TimeoutException {
            if (attempt == 1) {
              throw const CatalogException(
                '连接资料服务超时，请检查网络后重试；已有歌词和封面会保留',
                code: 'network',
              );
            }
          } on http.ClientException {
            if (attempt == 1) {
              throw const CatalogException(
                '无法连接资料服务，请检查网络后重试；已有资料会保留',
                code: 'network',
              );
            }
          } on IOException {
            if (attempt == 1) {
              throw const CatalogException('资料下载中断，请检查网络后重试', code: 'network');
            }
          }
        }
        throw StateError('Unreachable');
      });

  Future<Uint8List> _attempt(
    Uri uri,
    int maximum, {
    required bool image,
  }) async {
    final service = uri.host;
    var current = uri;
    for (var hop = 0; hop < 6; hop++) {
      if (image && !_coverHost(current)) {
        throw const FormatException('封面跳转地址不受信任');
      }
      await _waitTurn(service);
      final abort = Completer<void>();
      _aborts.add(abort);
      try {
        _next[service] = _now().add(requestGap);
        final response = await client
            .send(
              http.AbortableRequest('GET', current, abortTrigger: abort.future)
                ..followRedirects = false
                ..headers['User-Agent'] = userAgent
                ..headers['Accept'] = image ? 'image/*' : 'application/json',
            )
            .timeout(requestTimeout);
        final status = response.statusCode;
        if ([429, 503].contains(status)) {
          var deadline =
              _retryDeadline(response.headers['retry-after']) ??
              _now().add(Duration(seconds: status == 429 ? 30 : 2));
          if (_next[service]!.isAfter(deadline)) {
            deadline = _next[service]!;
          }
          _next[service] = deadline;
          await response.stream.listen((_) {}).cancel();
          final wait = deadline.difference(_now());
          if (status == 503 && wait <= const Duration(seconds: 4)) {
            throw CatalogException(
              '资料服务繁忙，请重试',
              code: 'unavailable',
              status: status,
            );
          }
          throw CatalogException(
            '这个资料服务正在限流，请 ${(wait.inMilliseconds / 1000).ceil()} 秒后重试',
            code: 'rate_limited',
            status: status,
            retryAfter: wait,
          );
        }
        if (image && [301, 302, 303, 307, 308].contains(status)) {
          final location = response.headers['location'];
          await response.stream.listen((_) {}).cancel();
          if (location == null) throw const FormatException('封面跳转缺少地址');
          current = current.resolve(location);
          if (current.scheme == 'http') {
            current = current.replace(scheme: 'https');
          }
          continue;
        }
        if (status != 200) {
          await response.stream.listen((_) {}).cancel();
          throw CatalogException(
            status == 404
                ? '这个版本暂无封面，请选择其他候选'
                : status >= 500
                ? '资料服务暂时不可用（HTTP $status），请稍后重试'
                : '资料服务拒绝请求（HTTP $status），请稍后重试',
            code: status == 404
                ? 'not_found'
                : status >= 500
                ? 'unavailable'
                : 'rejected',
            status: status,
          );
        }
        return await SongDetailsRepository.readLimited(
          response.stream.timeout(requestTimeout),
          maximum,
        ).timeout(requestTimeout);
      } finally {
        if (!abort.isCompleted) abort.complete();
        _aborts.remove(abort);
      }
    }
    throw const FormatException('封面跳转次数过多');
  }

  Future<dynamic> _json(Uri uri) async {
    final bytes = await _get(uri, 4 * 1024 * 1024);
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const CatalogException('资料服务返回了异常内容，请稍后重试', code: 'bad_response');
    }
  }

  Future<List<CatalogResult>> _remember(
    String key,
    Future<List<CatalogResult>> Function() search,
  ) {
    _checkOpen();
    final cached = _cache[key];
    if (cached != null && cached.expires.isAfter(_now())) {
      return Future.value(cached.items);
    }
    if (_pending[key] != null) return _pending[key]!;
    final future =
        (() async {
          final items = List<CatalogResult>.unmodifiable(await search());
          if (_cache.length >= 24) _cache.remove(_cache.keys.first);
          _cache[key] = (
            expires: _now().add(Duration(minutes: items.isEmpty ? 2 : 20)),
            items: items,
          );
          return items;
        })().whenComplete(() {
          _pending.remove(key);
        });
    _pending[key] = future;
    return future;
  }

  static String _text(Object? value, [String fallback = '']) =>
      value is String ? value : fallback;
  static int? _duration(Object? value, {bool milliseconds = false}) =>
      value is num ? (value / (milliseconds ? 1000 : 1)).round() : null;

  Future<List<CatalogResult>> lyrics(String title, String artist) {
    title = title.trim();
    artist = artist.trim();
    if (title.isEmpty) return Future.error(const FormatException('请填写歌名'));
    return _remember('lyrics:$title:$artist', () async {
      final queries = [
        {'track_name': title, if (artist.isNotEmpty) 'artist_name': artist},
        {'q': '$title $artist'.trim()},
        if (artist.isNotEmpty) {'q': title},
      ];
      for (final query in queries) {
        final value = await _json(
          Uri.https('lrclib.net', '/api/search', query),
        );
        if (value is! List) {
          throw const CatalogException('歌词响应格式异常', code: 'bad_response');
        }
        final results = <CatalogResult>[];
        for (final item in value.whereType<Map>().take(30)) {
          final synced = _text(item['syncedLyrics']);
          final plain = _text(item['plainLyrics']);
          final text = synced.trim().isNotEmpty ? synced : plain;
          if (text.trim().isEmpty ||
              utf8.encode(text).length > AudioTags.maxLyrics) {
            continue;
          }
          results.add(
            CatalogResult(
              id: '${item['id']}',
              title: _text(item['trackName'], title),
              artist: _text(item['artistName'], artist),
              album: _text(item['albumName']),
              duration: _duration(item['duration']),
              lyrics: text,
            ),
          );
        }
        if (results.isNotEmpty) return results;
      }
      return [];
    });
  }

  static String _quoted(String text) =>
      '"${text.replaceAll(RegExp(r'["\\]'), ' ')}"';
  static bool _uuid(String value) => RegExp(
    r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$',
  ).hasMatch(value);

  Future<List<CatalogResult>> covers(String title, String artist) {
    title = title.trim();
    artist = artist.trim();
    if (title.isEmpty) return Future.error(const FormatException('请填写歌名'));
    return _remember('covers:$title:$artist', () async {
      for (final who in [artist, if (artist.isNotEmpty) '']) {
        final query =
            'recording:${_quoted(title)}${who.isEmpty ? '' : ' AND artist:${_quoted(who)}'}';
        final value = await _json(
          Uri.https('musicbrainz.org', '/ws/2/recording', {
            'query': query,
            'fmt': 'json',
            'limit': '10',
          }),
        );
        if (value is! Map || value['recordings'] is! List) {
          throw const CatalogException('封面响应格式异常', code: 'bad_response');
        }
        final results = <String, CatalogResult>{};
        for (final record in (value['recordings'] as List).whereType<Map>()) {
          final credits =
              (record['artist-credit'] is List
                      ? record['artist-credit'] as List
                      : [])
                  .whereType<Map>()
                  .map((c) => _text(c['name']))
                  .where((s) => s.isNotEmpty)
                  .join(' / ');
          for (final release
              in (record['releases'] is List ? record['releases'] as List : [])
                  .whereType<Map>()) {
            final id = '${release['id']}';
            if (!_uuid(id)) continue;
            final group = release['release-group'];
            results[id] = CatalogResult(
              id: id,
              title: _text(record['title'], title),
              artist: credits,
              album: _text(release['title']),
              duration: _duration(record['length'], milliseconds: true),
              releaseGroupId: group is Map && _uuid('${group['id']}')
                  ? '${group['id']}'
                  : null,
            );
          }
        }
        if (results.isNotEmpty) return results.values.take(30).toList();
      }
      return [];
    });
  }

  Future<Uint8List> coverBytes(CatalogResult result) async {
    if (!_uuid(result.id)) throw const FormatException('无效的封面 ID');
    final paths = [
      '/release/${result.id}/front-500',
      '/release/${result.id}/front-250',
      if (result.releaseGroupId != null && _uuid(result.releaseGroupId!))
        '/release-group/${result.releaseGroupId}/front-500',
    ];
    for (var i = 0; i < paths.length; i++) {
      try {
        return await _get(
          Uri.https('coverartarchive.org', paths[i]),
          AudioTags.maxCover,
          image: true,
        );
      } on CatalogException catch (failure) {
        if (failure.code != 'not_found' || i == paths.length - 1) rethrow;
      }
    }
    throw StateError('Unreachable');
  }

  void dispose() {
    _closed = true;
    for (final abort in _aborts) {
      if (!abort.isCompleted) abort.complete();
    }
    client.close();
  }
}
