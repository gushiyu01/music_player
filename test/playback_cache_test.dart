// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/offline_library.dart';
import 'package:music_player/data/playback_cache.dart';
import 'package:music_player/data/transfer_control.dart';
import 'package:music_player/data/transfer_manager.dart';
import 'package:music_player/models/drive_entry.dart';
import 'package:music_player/playback/caching_audio_source.dart';

import 'baidu_client_test.dart' show MemoryStore;
import 'transfer_test.dart' show settled;

DriveEntry cacheTrack(String id, {int size = 6}) =>
    DriveEntry(id: id, name: '$id.mp3', path: '/音乐/歌手/$id.mp3', size: size);

class CacheClient extends BaiduClient {
  CacheClient() : super(MemoryStore());
  final bytes = [1, 2, 3, 4, 5, 6];
  final requests = <(int?, int?)>[];
  StreamController<List<int>>? live;
  @override
  Future<http.StreamedResponse> openStream(
    DriveEntry entry, {
    int? start,
    int? end,
    TransferControl? control,
  }) async {
    requests.add((start, end));
    final first = start ?? 0;
    final last = end ?? bytes.length;
    return http.StreamedResponse(
      start == null && live != null
          ? live!.stream
          : Stream.value(bytes.sublist(first, last)),
      start == null ? 200 : 206,
      contentLength: last - first,
      headers: {
        'content-type': 'audio/mpeg',
        if (start != null)
          'content-range': 'bytes $first-${last - 1}/${bytes.length}',
      },
    );
  }
}

Future<List<int>> collect(Stream<List<int>> stream) =>
    stream.expand((v) => v).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SharedPreferences prefs;
  late PlaybackCache cache;
  late CacheClient client;
  Future<void> save(DriveEntry entry) async {
    final write = (await cache.begin(entry))!;
    await write.file.writeAsBytes(List.filled(entry.size, 1));
    expect(await cache.complete(write, entry.size), isTrue);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('playback-cache-');
    cache = PlaybackCache(
      Directory('${directory.path}/cache'),
      prefs,
      maximumBytes: 12,
    );
    await cache.initialize();
    client = CacheClient();
  });
  tearDown(() async {
    cache.dispose();
    client.client.close();
    await directory.delete(recursive: true);
  });

  test(
    'one playback stream persists complete bytes and survives restart',
    () async {
      final entry = cacheTrack('one');
      final source = CachingAudioSource(client, entry, cache);
      final response = await source.request();
      expect(await collect(response.stream), client.bytes);
      await source.close();
      expect(client.requests, [(null, null)]);
      expect(cache.totalBytes, 6);
      final restored = PlaybackCache(
        cache.storage.directory,
        prefs,
        maximumBytes: 12,
      );
      await restored.initialize();
      expect(File(restored.localPath(entry)!).readAsBytesSync(), client.bytes);
      // Local selection uses this path without resolving a Baidu link.
      expect(client.requests.length, 1);
      restored.dispose();
    },
  );

  test(
    'decoder gets first bytes before full cache and seeks beyond tail use Range',
    () async {
      client.live = StreamController();
      final source = CachingAudioSource(
        client,
        cacheTrack('progressive'),
        cache,
      );
      final response = await source.request(0, 3);
      client.live!.add([1, 2, 3]);
      expect(await collect(response.stream), [1, 2, 3]);
      expect(cache.entries, isEmpty);
      final seek = await source.request(4, 6);
      expect(await collect(seek.stream), [5, 6]);
      expect(client.requests, [(null, null), (4, 6)]);
      client.live!.add([4, 5, 6]);
      await client.live!.close();
      await cache.pending(cacheTrack('progressive'));
      expect(cache.totalBytes, 6);
      await source.close();
    },
  );

  test(
    'clearing during a live stream cancels writer and prevents stale commit',
    () async {
      client.live = StreamController();
      final source = CachingAudioSource(client, cacheTrack('clear'), cache);
      await source.request();
      client.live!.add([1]);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await cache.clear().timeout(const Duration(seconds: 2));
      expect(cache.entries, isEmpty);
      expect(cache.activeCount, 0);
      expect(await cache.storage.directory.list().toList(), isEmpty);
      await source.close();
      await client.live!.close();
    },
  );

  test(
    'truncated stream is discarded and playback can recover using Range',
    () async {
      client.live = StreamController();
      final source = CachingAudioSource(client, cacheTrack('short'), cache);
      final response = await source.request();
      final played = collect(response.stream);
      client.live!.add([1, 2]);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await client.live!.close();
      expect(await played, client.bytes);
      await source.close();
      expect(cache.totalBytes, 0);
      expect(await cache.storage.directory.list().toList(), isEmpty);
    },
  );

  test(
    'stopping an unfinished song cancels and removes its partial cache',
    () async {
      client.live = StreamController();
      final entry = cacheTrack('stop');
      final source = CachingAudioSource(client, entry, cache);
      final response = await source.request(0, 1);
      client.live!.add([1]);
      expect(await collect(response.stream), [1]);
      await source.close().timeout(const Duration(seconds: 2));
      expect(cache.entries, isEmpty);
      expect(cache.activeCount, 0);
      expect(await cache.storage.directory.list().toList(), isEmpty);
      await client.live!.close();
    },
  );

  test(
    'songs above cache limit still play directly without a duplicate request',
    () async {
      final source = CachingAudioSource(
        client,
        cacheTrack('large', size: 13),
        cache,
      );
      final response = await source.request();
      expect(await collect(response.stream), client.bytes);
      expect(client.requests, [(null, null)]);
      expect(cache.entries, isEmpty);
      await source.close();
    },
  );

  test(
    'moving and deleting cache entries updates their local identity',
    () async {
      final old = cacheTrack('move');
      final moved = DriveEntry(
        id: old.id,
        name: old.name,
        path: '/音乐/其他/${old.name}',
        size: old.size,
      );
      await save(old);
      await cache.relocate(old, moved);
      expect(cache.localPath(old), isNull);
      expect(cache.localPath(moved), isNotNull);
      expect(cache.entries.single.parent, '/音乐/其他');
      await cache.remove(moved);
      expect(cache.entries, isEmpty);
      expect(await cache.storage.directory.list().toList(), isEmpty);
    },
  );

  test('capacity evicts least recently used unprotected songs', () async {
    final a = cacheTrack('a'), b = cacheTrack('b'), c = cacheTrack('c');
    await save(a);
    await save(b);
    await cache.touch(a);
    cache.protect(a);
    await save(c);
    expect(cache.localPath(a), isNotNull);
    expect(cache.localPath(b), isNull);
    expect(cache.localPath(c), isNotNull);
    expect(cache.totalBytes, 12);
    expect(await cache.begin(cacheTrack('oversized', size: 13)), isNull);
    cache.release(a);
  });

  test(
    'cache identity rejects changed sizes and restart removes orphan files',
    () async {
      final a = cacheTrack('a');
      await save(a);
      expect(cache.localPath(cacheTrack('a', size: 7)), isNull);
      await File(
        '${cache.storage.directory.path}/orphan.mp3',
      ).writeAsBytes([1]);
      final restored = PlaybackCache(cache.storage.directory, prefs);
      await restored.initialize();
      expect(restored.entries.length, 1);
      expect((await cache.storage.directory.list().toList()).length, 1);
      restored.dispose();
    },
  );

  test(
    'manual download promotes complete cache with zero network; clear preserves downloads',
    () async {
      final entry = cacheTrack('download');
      await save(entry);
      final library = OfflineLibrary(
        Directory('${directory.path}/downloads'),
        prefs,
      );
      await library.initialize();
      final manager = TransferManager(client, library, cache: cache);
      manager.download(entry);
      await settled(manager);
      expect(manager.tasks.single.status, TransferStatus.done);
      expect(client.requests, isEmpty);
      expect(library.localPath(entry), isNotNull);
      await cache.clear();
      expect(library.localPath(entry), isNotNull);
      final restored = OfflineLibrary(library.directory, prefs);
      await restored.initialize();
      expect(restored.entries.single.id, entry.id);
      restored.dispose();
      manager.dispose();
      library.dispose();
    },
  );
}
